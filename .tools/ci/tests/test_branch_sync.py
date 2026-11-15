import importlib.util
import io
import json
import os
from pathlib import Path
import textwrap
import unittest
import urllib.error
from unittest.mock import mock_open, patch


ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    "sync_idle_branches", ROOT / ".tools/ci/sync_idle_branches.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

TARGET, OLD, CHANGED = "a" * 40, "b" * 40, "c" * 40


def branch(name, sha=OLD, protected=False):
    return {"name": name, "commit": {"sha": sha}, "protected": protected}


class FakeGitHub:
    def __init__(self, branches=None):
        self.branches = branches if branches is not None else [branch("retail/feature/new")]
        self.heads = {row["name"]: row["commit"]["sha"] for row in self.branches}
        self.heads["retail/dev"] = TARGET
        self.comparisons = {}
        self.updates = []
        self.before_update = None
        self.dev_reads = 0
        self.change_dev_at = None
        self.reject = False
        self.newly_protected = set()
        self.merged_branches = set()

    def reference(self, name):
        if name == "retail/dev":
            self.dev_reads += 1
            if self.change_dev_at == self.dev_reads:
                self.heads["retail/dev"] = CHANGED
        return self.heads.get(name)

    def snapshots(self):
        return self.branches

    def compare(self, base, head):
        assert base == TARGET
        return self.comparisons.get(head, {
            "status": "behind", "ahead_by": 0, "behind_by": 3,
            "merge_base_commit": {"sha": head},
        })

    def protected(self, name):
        return name in self.newly_protected

    def was_merged(self, name):
        return name in self.merged_branches

    def fast_forward(self, name, before, after):
        if self.before_update:
            self.before_update(self, name)
        if self.reject or self.heads.get(name) != before:
            raise sync.SyncError("Rejected update")
        assert after == TARGET
        self.updates.append((name, before, after))
        self.heads[name] = after


class SyncTests(unittest.TestCase):
    def run_sync(self, client, apply=True):
        records = []
        sync.synchronize(client, TARGET, apply=apply, report=records.append)
        return records

    def test_all_three_prefixes_fast_forward(self):
        client = FakeGitHub([branch("retail/feature/new"), branch("retail/bugfix/new"), branch("retail/task/new/one")])
        self.run_sync(client)
        self.assertEqual(len(client.updates), 3)
        self.assertTrue(all(after == TARGET for _, _, after in client.updates))

    def test_only_the_tested_platform_is_synchronized(self):
        for platform in ("retail", "forever"):
            with self.subTest(platform=platform):
                client = FakeGitHub([branch("retail/feature/new"), branch("forever/feature/new"),
                                     branch("feature/legacy"), branch("forever/task/current", TARGET)])
                client.heads["forever/dev"] = TARGET
                sync.synchronize(client, TARGET, apply=True, report=lambda _: None,
                                 dev_branch=f"{platform}/dev")
                self.assertEqual(client.updates, [(f"{platform}/feature/new", OLD, TARGET)])

    def test_dry_run_never_writes(self):
        client = FakeGitHub()
        records = self.run_sync(client, apply=False)
        self.assertEqual(client.updates, [])
        self.assertEqual(records[0]["result"], "planned")

    def test_merged_branches_are_not_updated_or_planned(self):
        for apply in (False, True):
            with self.subTest(apply=apply):
                client = FakeGitHub([branch("retail/feature/merged"), branch("retail/bugfix/merged"),
                                     branch("retail/task/merged"), branch("retail/feature/new")])
                client.merged_branches.update(("retail/feature/merged", "retail/bugfix/merged", "retail/task/merged"))
                records = self.run_sync(client, apply=apply)
                self.assertEqual(sum(row["result"] == "merged" for row in records), 3)
                self.assertEqual(client.updates, [("retail/feature/new", OLD, TARGET)] if apply else [])

    def test_previously_auto_updated_merged_branch_still_stays_excluded(self):
        client = FakeGitHub([branch("retail/feature/merged", CHANGED)])
        client.merged_branches.add("retail/feature/merged")
        records = self.run_sync(client)
        self.assertEqual(client.updates, [])
        self.assertEqual(records[-1]["result"], "merged")

    def test_missing_pr_history_does_not_allow_update(self):
        client = FakeGitHub()
        def unavailable(name):
            raise sync.SyncError("Pull request history unavailable")
        client.was_merged = unavailable
        with self.assertRaises(sync.SyncError):
            self.run_sync(client)
        self.assertEqual(client.updates, [])

    def test_unrelated_protected_and_current_branches_are_untouched(self):
        client = FakeGitHub([
            branch("main"), branch("retail/dev", TARGET), branch("release/1.0"),
            branch("retail/feature/protected", protected=True), branch("retail/task/current", TARGET),
        ])
        self.run_sync(client)
        self.assertEqual(client.updates, [])

    def test_own_or_diverged_commits_are_skipped(self):
        for status, ahead in (("ahead", 1), ("diverged", 2)):
            with self.subTest(status=status):
                client = FakeGitHub()
                client.comparisons[OLD] = {"status": status, "ahead_by": ahead}
                self.run_sync(client)
                self.assertEqual(client.updates, [])

    def test_same_tree_does_not_override_commit_ancestry(self):
        client = FakeGitHub()
        client.comparisons[OLD] = {
            "status": "diverged", "ahead_by": 1, "behind_by": 2,
            "files": [], "merge_base_commit": {"sha": CHANGED},
        }
        self.run_sync(client)
        self.assertEqual(client.updates, [])

    def test_inconsistent_comparison_cannot_write(self):
        for changed in ({"ahead_by": True}, {"behind_by": 0},
                        {"merge_base_commit": {"sha": CHANGED}}):
            with self.subTest(changed=changed):
                client = FakeGitHub()
                data = client.compare(TARGET, OLD)
                client.comparisons[OLD] = {**data, **changed}
                self.run_sync(client)
                self.assertEqual(client.updates, [])

    def test_stale_dev_does_not_write(self):
        client = FakeGitHub()
        client.heads["retail/dev"] = CHANGED
        self.run_sync(client)
        self.assertEqual(client.updates, [])

    def test_dev_advance_stops_remaining_updates(self):
        client = FakeGitHub([branch("retail/feature/a"), branch("retail/feature/b")])
        client.change_dev_at = 3
        self.run_sync(client)
        self.assertLess(len(client.updates), 2)

    def test_concurrent_commit_is_preserved(self):
        client = FakeGitHub()
        client.before_update = lambda api, name: api.heads.__setitem__(name, CHANGED)
        records = self.run_sync(client)
        self.assertEqual(client.heads["retail/feature/new"], CHANGED)
        self.assertEqual(client.updates, [])
        self.assertEqual(records[-1]["result"], "changed")

    def test_concurrent_deletion_is_not_recreated(self):
        client = FakeGitHub()
        client.before_update = lambda api, name: api.heads.pop(name)
        self.run_sync(client)
        self.assertNotIn("retail/feature/new", client.heads)
        self.assertEqual(client.updates, [])

    def test_concurrent_fast_forward_to_target_is_safe(self):
        client = FakeGitHub()
        client.before_update = lambda api, name: api.heads.__setitem__(name, TARGET)
        self.run_sync(client)
        self.assertEqual(client.updates, [])
        self.assertEqual(client.heads["retail/feature/new"], TARGET)

    def test_permission_failure_is_not_hidden_or_retried(self):
        client = FakeGitHub()
        client.reject = True
        with self.assertRaises(sync.SyncError):
            self.run_sync(client)
        self.assertEqual(client.updates, [])

    def test_newly_protected_branch_is_skipped(self):
        client = FakeGitHub()
        client.newly_protected.add("retail/feature/new")
        records = self.run_sync(client)
        self.assertEqual(client.updates, [])
        self.assertEqual(records[-1]["result"], "protected-or-deleted")

    def test_dev_advance_during_mutation_can_only_apply_the_tested_revision(self):
        client = FakeGitHub()
        client.before_update = lambda api, name: api.heads.__setitem__("retail/dev", CHANGED)
        self.run_sync(client)
        self.assertEqual(client.updates, [("retail/feature/new", OLD, TARGET)])
        self.assertNotEqual(client.heads["retail/feature/new"], CHANGED)

    def test_invalid_context_stops_before_network(self):
        good = {"GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": "push",
                "GITHUB_REF": "refs/heads/retail/dev", "GITHUB_SHA": TARGET,
                "GITHUB_REPOSITORY": "owner/repo", "GH_TOKEN": "test-only"}
        for change in ({"GITHUB_EVENT_NAME": "pull_request"},
                       {"GITHUB_EVENT_NAME": "release"}, {"GITHUB_REF": "refs/heads/main"},
                       {"GITHUB_ACTIONS": "false"}, {"GITHUB_SHA": "bad"},
                       {"GITHUB_REPOSITORY": "../repo"}, {"GH_TOKEN": ""}):
            with self.subTest(change=change), patch.dict(os.environ, {**good, **change}, clear=True):
                with self.assertRaises(sync.SyncError):
                    sync.context(apply=True)


class TransportTests(unittest.TestCase):
    def client(self):
        return sync.GitHub("owner/repo", "test-secret-not-real")

    def pull_request(self, name="retail/feature/new", repository="owner/repo", merged=True):
        return {"merged_at": "2026-10-28T12:00:00Z" if merged else None,
                "head": {"ref": name, "repo": {"full_name": repository}}}

    def test_merged_pr_lookup_is_by_branch_history_not_current_sha(self):
        api = self.client()
        calls = []
        def request(path, payload=None):
            calls.append(path)
            return [self.pull_request()]
        api.request = request
        self.assertTrue(api.was_merged("retail/feature/new"))
        query = sync.urllib.parse.parse_qs(sync.urllib.parse.urlsplit(calls[0]).query)
        self.assertEqual(query["head"], ["owner:retail/feature/new"])
        self.assertEqual(query["state"], ["closed"])
        self.assertNotIn("base", query)

    def test_closed_unmerged_and_other_source_prs_do_not_exclude_branch(self):
        api = self.client()
        api.request = lambda *args: [self.pull_request(merged=False),
                                    self.pull_request(repository="fork/repo"),
                                    self.pull_request(name="retail/feature/other"),
                                    {"merged_at": "2026-10-28T12:00:00Z",
                                     "head": {"ref": "retail/feature/new", "repo": None}}]
        self.assertFalse(api.was_merged("retail/feature/new"))

    def test_merged_pr_lookup_paginates_past_unmerged_entries(self):
        api = self.client()
        calls = []
        def request(path, payload=None):
            calls.append(path)
            query = sync.urllib.parse.parse_qs(sync.urllib.parse.urlsplit(path).query)
            return [self.pull_request(merged=False)] * 100 if query["page"] == ["1"] else [self.pull_request()]
        api.request = request
        self.assertTrue(api.was_merged("retail/feature/new"))
        self.assertEqual(len(calls), 2)

    def test_invalid_or_unbounded_pr_history_fails_closed(self):
        invalid = ({}, [{}], [{"merged_at": False}], [{"merged_at": ""}],
                   [{"merged_at": "2026-10-28T12:00:00Z", "head": {}}],
                   [self.pull_request(merged=False)] * 101)
        for response in invalid:
            with self.subTest(response_size=len(response)):
                api = self.client(); api.request = lambda *args: response
                with self.assertRaises(sync.SyncError):
                    api.was_merged("retail/feature/new")
        api = self.client()
        api.request = lambda *args: [self.pull_request(merged=False)] * 100
        with self.assertRaises(sync.SyncError):
            api.was_merged("retail/feature/new")

    def test_mutation_requires_exact_old_oid_and_no_force(self):
        api = self.client()
        calls = []
        def request(path, payload=None):
            calls.append((path, payload))
            if path != "/graphql":
                return {"node_id": "R_test"}
            return {"data": {"updateRefs": {"clientMutationId": "spellbook-idle-sync"}}}
        api.request = request
        api.fast_forward("retail/feature/new", OLD, TARGET)
        update = calls[-1][1]["variables"]["input"]["refUpdates"][0]
        self.assertEqual(update, {"name": "refs/heads/retail/feature/new", "beforeOid": OLD,
                                  "afterOid": TARGET, "force": False})

    def test_mutation_cannot_target_other_prefixes(self):
        api = self.client()
        api.request = lambda *args: self.fail("Network called for forbidden ref")
        for name in ("retail/dev", "main", "release/1", "retail/feature/", "retail/feature/x\n::error::bad"):
            with self.subTest(name=name), self.assertRaises(sync.SyncError):
                api.fast_forward(name, OLD, TARGET)

    def test_graphql_errors_fail_closed(self):
        api = self.client()
        api.request = lambda path, payload=None: (
            {"node_id": "R_test"} if path != "/graphql" else {"errors": [{"message": "denied"}]})
        with self.assertRaises(sync.SyncError):
            api.fast_forward("retail/feature/new", OLD, TARGET)

    def test_branch_listing_is_paginated_before_writing(self):
        api = self.client()
        pages = []
        def request(path, payload=None):
            pages.append(path)
            return [branch("retail/feature/" + str(i)) for i in range(100)] if "page=1&" in path else []
        api.request = request
        self.assertEqual(len(api.snapshots()), 100)
        self.assertEqual(len(pages), 2)

    def test_reference_404_is_missing_not_created(self):
        api = self.client()
        def missing(*args):
            raise sync.SyncError("missing", status=404)
        api.request = missing
        self.assertIsNone(api.reference("retail/feature/deleted"))

    def test_protection_lookup_rejects_unknown_and_missing_branches(self):
        api = self.client()
        for response in ({"name": "retail/feature/new", "protected": True},
                         {"name": "other", "protected": False}, {}):
            api.request = lambda *args: response
            if response.get("name") == "retail/feature/new":
                self.assertTrue(api.protected("retail/feature/new"))
            else:
                with self.assertRaises(sync.SyncError):
                    api.protected("retail/feature/new")
        def missing(*args):
            raise sync.SyncError("missing", status=404)
        api.request = missing
        self.assertTrue(api.protected("retail/feature/new"))

    def test_invalid_api_payloads_fail_closed(self):
        for response in ({}, [branch("retail/feature/x", "bad")],
                         [{**branch("retail/feature/x"), "protected": "false"}]):
            with self.subTest(response=response):
                api = self.client(); api.request = lambda *args: response
                with self.assertRaises(sync.SyncError):
                    api.snapshots()

    def test_zero_oids_never_create_or_delete(self):
        api = self.client()
        api.request = lambda *args: self.fail("Network called for zero OID")
        for before, after in (("0" * 40, TARGET), (OLD, "0" * 40)):
            with self.subTest(before=before, after=after), self.assertRaises(sync.SyncError):
                api.fast_forward("retail/feature/new", before, after)

    def test_malformed_success_is_not_accepted(self):
        for response in ({}, {"data": None}, {"data": {"updateRefs": None}},
                         {"data": {"updateRefs": {"clientMutationId": "different"}}}):
            with self.subTest(response=response):
                api = self.client()
                api.request = lambda path, payload=None: (
                    {"node_id": "R_test"} if path != "/graphql" else response)
                with self.assertRaises(sync.SyncError):
                    api.fast_forward("retail/task/new", OLD, TARGET)

    def test_inconsistent_paginated_listing_fails_before_mutations(self):
        api = self.client()
        first = [branch("retail/feature/" + str(i)) for i in range(100)]
        api.request = lambda path, payload=None: first if "page=1&" in path else [branch("retail/feature/0", CHANGED)]
        with self.assertRaises(sync.SyncError):
            api.snapshots()

    def test_malformed_reference_is_not_trusted(self):
        for response in ([], {}, {"ref": "refs/heads/retail/dev", "object": {"type": "tree", "sha": TARGET}},
                         {"ref": "refs/heads/main", "object": {"type": "commit", "sha": TARGET}}):
            with self.subTest(response=response):
                api = self.client(); api.request = lambda *args: response
                with self.assertRaises(sync.SyncError):
                    api.reference("retail/dev")

    def test_timeout_and_http_errors_do_not_expose_token_or_retry(self):
        errors = [TimeoutError("test-secret-not-real"),
                  urllib.error.URLError("test-secret-not-real"),
                  urllib.error.HTTPError("https://api.github.com", 403, "test-secret-not-real", {}, None)]
        for error in errors:
            with self.subTest(error=type(error).__name__):
                api = self.client()
                with patch.object(api.opener, "open", side_effect=error) as opened:
                    with self.assertRaises(sync.SyncError) as raised:
                        api.request("/graphql", {"test": True})
                self.assertNotIn("test-secret", str(raised.exception))
                self.assertEqual(opened.call_count, 1)

    def test_invalid_json_and_oversized_response_fail_closed(self):
        for body in (b"not json", b"\xff", b" " * (8 * 1024 * 1024 + 1)):
            with self.subTest(size=len(body)):
                api = self.client()
                with patch.object(api.opener, "open", return_value=io.BytesIO(body)):
                    with self.assertRaises(sync.SyncError):
                        api.request("/repos/owner/repo")

    def test_request_is_pinned_and_redirects_are_rejected(self):
        api = self.client()
        with patch.object(api.opener, "open", return_value=io.BytesIO(b"{}")) as opened:
            api.request("/repos/owner/repo")
        request = opened.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.github.com/repos/owner/repo")
        self.assertEqual(opened.call_args.kwargs["timeout"], 20)
        self.assertIsNone(sync.NoRedirect().redirect_request(request, None, 302, "", {}, "https://other.invalid"))
        with self.assertRaises(sync.SyncError):
            api.request("https://other.invalid/graphql")


class CommandTests(unittest.TestCase):
    def run_command(self, client, apply=False, environment=None):
        env = {"GITHUB_ACTIONS": "true", "GITHUB_EVENT_NAME": "push",
               "GITHUB_REF": "refs/heads/retail/dev", "GITHUB_SHA": TARGET,
               "GITHUB_REPOSITORY": "owner/repo", "GH_TOKEN": "test-only",
               "GITHUB_STEP_SUMMARY": "test-summary-not-on-disk"}
        env.update(environment or {})
        output, errors, summary = io.StringIO(), io.StringIO(), mock_open()
        argv = ["sync_idle_branches.py"] + (["--apply"] if apply else [])
        with patch.dict(os.environ, env, clear=True), patch.object(sync.sys, "argv", argv), \
                patch.object(sync, "GitHub", return_value=client) as constructor, \
                patch.object(sync.sys, "stdout", output), patch.object(sync.sys, "stderr", errors), \
                patch.object(sync.Path, "open", summary):
            result = sync.main()
        text = "".join(call.args[0] for call in summary().write.call_args_list)
        return result, output.getvalue(), errors.getvalue(), text, constructor

    def test_command_is_read_only_by_default_and_reports_plan(self):
        client = FakeGitHub()
        result, output, errors, summary, _ = self.run_command(client)
        self.assertEqual(result, 0)
        self.assertEqual(client.updates, [])
        self.assertEqual(json.loads(output)["result"], "planned")
        self.assertEqual(errors, "")
        self.assertIn("planned: 1", summary)
        self.assertIn(TARGET, summary)

    def test_invalid_apply_context_never_constructs_api_client(self):
        result, output, errors, summary, constructor = self.run_command(
            FakeGitHub(), apply=True, environment={"GITHUB_EVENT_NAME": "pull_request"})
        self.assertEqual(result, 1)
        constructor.assert_not_called()
        self.assertEqual(json.loads(output)["result"], "failed")
        self.assertIn("restricted", errors)
        self.assertIn("failed: 1", summary)

    def test_partial_failure_keeps_failure_exit_and_both_summary_counts(self):
        client = FakeGitHub([branch("retail/feature/a"), branch("retail/feature/b")])
        client.before_update = lambda api, name: setattr(api, "reject", name == "retail/feature/b")
        result, output, errors, summary, _ = self.run_command(client, apply=True)
        self.assertEqual(result, 1)
        self.assertEqual(client.updates, [("retail/feature/a", OLD, TARGET)])
        self.assertEqual([json.loads(line)["result"] for line in output.splitlines()], ["updated", "failed"])
        self.assertIn("updated: 1", summary)
        self.assertIn("failed: 1", summary)
        self.assertIn("Rejected", errors)


class WorkflowTests(unittest.TestCase):
    def test_pull_request_scope(self):
        workflow = (ROOT / ".github/workflows/tests.yml").read_text(encoding="utf-8")
        script = textwrap.dedent(workflow.split("python3 -I -B - <<'PY'\n", 1)[1]
                                 .split("\n          PY\n", 1)[0])
        scenarios = (
            ("retail/dev", "retail/feature/test", b"TRP3_RPSpellbook/test.lua\0", True),
            ("forever/dev", "forever/bugfix/test", b"TRP3_RPSpellbook_NPC/test.lua\0", True),
            ("retail/dev", "forever/feature/test", b"TRP3_RPSpellbook/test.lua\0", False),
            ("retail/dev", "retail/feature/test", b"TRP3_RPSpellbook/test.lua\0Forever/test.lua\0", False),
            ("main", "forever/dev", b"Forever/test.lua\0", False),
            ("main", "platform-sync/forever/to-main", b"Forever/test.lua\0", True),
            ("main", "platform-sync/forever/to-main", b"Retail/test.lua\0", False),
            ("main", "platform-sync/forever/to-main", b".github/workflows/tests.yml\0", False),
            ("forever/dev", "platform-sync/forever/from-main", b"TRP3_RPSpellbook/test.lua\0.tools/ci/run_tests.py\0", True),
            ("forever/dev", "platform-sync/forever/from-main", b"Retail/test.lua\0", False),
            ("forever/dev", "main", b"TRP3_RPSpellbook/test.lua\0", False),
        )
        for base, head, paths, accepted in scenarios:
            with self.subTest(base=base, head=head, paths=paths), \
                    patch.dict(os.environ, BASE_REF=base, HEAD_REF=head, BASE_SHA=OLD,
                               HEAD_REPOSITORY="owner/repo", GITHUB_REPOSITORY="owner/repo"), \
                    patch("subprocess.check_output", side_effect=lambda args: (
                        b"" if "--diff-filter=D" in args else paths)) as diff:
                if accepted:
                    exec(compile(script, "tests.yml", "exec"), {})
                    self.assertEqual(diff.call_args.args[0][-3:], [OLD, "HEAD", "--"])
                else:
                    with self.assertRaises(SystemExit):
                        exec(compile(script, "tests.yml", "exec"), {})
        with patch.dict(os.environ, BASE_REF="forever/dev", HEAD_REF="platform-sync/forever/from-main",
                        BASE_SHA=OLD, HEAD_REPOSITORY="owner/repo", GITHUB_REPOSITORY="owner/repo"), \
                patch("subprocess.check_output", side_effect=[
                    b"Retail/obsolete.lua\0Forever/obsolete.lua\0",
                    b"Retail/obsolete.lua\0Forever/obsolete.lua\0TRP3_RPSpellbook/test.lua\0",
                ]):
            exec(compile(script, "tests.yml", "exec"), {})

    def test_dev_sync_is_gated_and_does_not_broaden_reusable_checks(self):
        workflow = (ROOT / ".github/workflows/sync-branches.yml").read_text(encoding="utf-8")
        checks = (ROOT / ".github/workflows/tests.yml").read_text(encoding="utf-8")
        self.assertIn("branches: [retail/dev, forever/dev]", workflow)
        self.assertIn("uses: ./.github/workflows/tests.yml", workflow)
        self.assertIn("needs: checks", workflow)
        self.assertIn("needs.checks.result == 'success'", workflow)
        self.assertIn("github.event_name == 'push'", workflow)
        for platform in ("retail", "forever"):
            self.assertIn(f"github.ref == 'refs/heads/{platform}/dev'", workflow)
        self.assertIn("contents: write", workflow)
        self.assertIn("      pull-requests: read", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("sync_idle_branches.py --apply", workflow)
        self.assertNotIn("contents: write", checks)
        self.assertNotIn("  push:", checks)
        self.assertIn("  pull_request:", checks)
        self.assertIn("types: [opened, synchronize, reopened, edited]", checks)
        self.assertIn("  workflow_call:", checks)


if __name__ == "__main__":
    unittest.main()
