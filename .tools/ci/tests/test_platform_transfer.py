import importlib.util
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "sync_platform", Path(__file__).resolve().parents[1] / "sync_platform.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


@unittest.skipUnless(shutil.which("git"), "Git required for platform transfer fixtures")
class PlatformTransferTests(unittest.TestCase):
    def setUp(self):
        directory = self.enterContext(tempfile.TemporaryDirectory(prefix="spellbook-transfer-test-"))
        repository = Path(directory) / "fixture.git"
        subprocess.run(["git", "init", "--bare", str(repository)], capture_output=True, check=True)
        self.enterContext(patch.dict(sync.ENV, GIT_DIR=str(repository)))
        self.retail = self.platform(b"retail\n")
        self.forever = self.platform(b"forever\n")
        self.shared = self.directory({"ci": self.directory({"test.py": self.blob(b"CI\n")})})
        self.workflows = self.directory({"workflows": self.directory({"tests.yml": self.blob(b"CI\n")})})
        self.root = {"Retail": self.retail, "Forever": self.forever,
                     ".tools": self.shared, ".github": self.workflows, "LICENSE": self.blob(b"license")}
        self.base = self.snapshot(self.root)
        self.ref("main", self.base)
        self.ref("retail/dev", self.base)
        self.ref("forever/dev", self.base)

    def blob(self, data):
        return b"100644 blob " + sync.git("hash-object", "-w", "--stdin", data=data)

    def directory(self, items):
        return b"040000 tree " + sync.make_tree({name.encode(): value
                                               for name, value in items.items()}).encode()

    def platform(self, data, **extra):
        return self.directory({name: self.directory({"Main.lua": self.blob(data), **extra})
                               for name in sync.check.ADDONS})

    def snapshot(self, items, *parents):
        tree = sync.tree_id(self.directory(items))
        return sync.commit(tree, "Fixture", *parents)

    def ref(self, name, oid):
        sync.git("update-ref", "refs/remotes/origin/" + name, oid)

    def apply(self, plan):
        branch, base, source, destination, tree, title, message = plan
        change = sync.commit(tree, message, *((destination,) if source == destination else (destination, source)))
        # Model GitHub's "Create a merge commit"; the ancestor must not be squashed away.
        merged = sync.commit(tree, f"Merge {title}", destination, change)
        self.ref(base, merged)
        return merged

    def flat(self, platform, extra=None):
        addons = sync.entries(sync.tree_id(platform))
        items = {name.decode(): node for name, node in addons.items()}
        items.update({".tools": self.shared, ".github": self.workflows, **(extra or {})})
        return items

    def test_migration_keeps_dev_edits_removes_wrappers_and_does_not_echo(self):
        changed = self.platform(b"retail local\n")
        dev = self.snapshot({**self.root, "Retail": changed}, self.base)
        self.ref("retail/dev", dev)
        main = self.snapshot({**self.root, ".tools": self.directory(
            {"ci": self.directory({"updated.py": self.blob(b"new CI")})})}, self.base)
        self.ref("main", main)
        plan = sync.prepare("retail", "from-main", main)
        migrated = self.apply(plan)
        self.assertTrue(sync.ADDON_NAMES <= sync.entries(migrated).keys())
        self.assertFalse(sync.PLATFORM_NAMES.intersection(sync.entries(migrated)))
        self.assertEqual(sync.entries(migrated)[b".tools"], sync.entries(main)[b".tools"])
        self.assertEqual(sync.project(migrated, b"Retail"), sync.project(dev, b"Retail"))
        promotion = sync.prepare("retail", "to-main", migrated)
        promoted = self.apply(promotion)
        self.assertEqual(sync.entries(promoted)[b"Forever"], self.forever)
        self.assertTrue(sync.no_changes(*sync.prepare("retail", "from-main", promoted)[3:5]))

    def test_nonoverlapping_edits_survive_both_directions(self):
        dev = self.snapshot(self.flat(self.retail, {"Local.txt": self.blob(b"keep")}), self.base)
        self.ref("retail/dev", dev)
        changed_dev = self.snapshot(self.flat(self.platform(b"retail\n", **{"Dev.lua": self.blob(b"dev")}),
                                              {"Local.txt": self.blob(b"keep")}), dev)
        self.ref("retail/dev", changed_dev)
        changed_main = self.snapshot({**self.root, "Retail": self.platform(
            b"retail\n", **{"MainOnly.lua": self.blob(b"main")})}, self.base)
        self.ref("main", changed_main)
        promoted = self.apply(sync.prepare("retail", "to-main", changed_dev))
        backported = self.apply(sync.prepare("retail", "from-main", promoted))
        self.assertIn(b"Local.txt", sync.entries(backported))
        addon = sync.tree_id(sync.project(backported, b"Retail")[b"TRP3_RPSpellbook"])
        self.assertEqual(set(sync.entries(addon)), {b"Main.lua", b"Dev.lua", b"MainOnly.lua"})
        self.assertTrue(sync.no_changes(*sync.prepare("retail", "to-main", backported)[3:5]))

    def test_conflict_and_stale_event_do_not_change_branch_refs(self):
        dev = self.snapshot(self.flat(self.platform(b"forever dev edit\n")), self.base)
        main = self.snapshot({**self.root, "Forever": self.platform(b"forever main edit\n")}, self.base)
        self.ref("forever/dev", dev)
        self.ref("main", main)
        self.assertIsNone(sync.prepare("forever", "to-main", self.base))
        with self.assertRaisesRegex(sync.SyncError, "could not be merged"):
            sync.prepare("forever", "from-main", main)
        self.assertEqual(sync.git("rev-parse", "refs/remotes/origin/forever/dev").decode(), dev)
        self.assertEqual(sync.git("rev-parse", "refs/remotes/origin/main").decode(), main)

    def test_existing_transfer_is_not_pushed_again(self):
        plan = sync.prepare("forever", "from-main", self.base)
        branch, _, _, destination, tree, _, message = plan
        existing = sync.commit(tree, message, destination)
        self.ref(branch, existing)
        with patch.object(sync, "open_pull_request", side_effect=[b"42", b""]), \
                patch.object(sync, "git", wraps=sync.git) as git:
            sync.publish(plan)
        self.assertFalse(any(call.args[0] == "push" for call in git.call_args_list))

    def test_opposite_open_transfer_blocks_publication(self):
        plan = sync.prepare("forever", "from-main", self.base)
        with patch.object(sync, "open_pull_request", side_effect=[b"", b"42"]), \
                patch.object(sync, "commit") as commit:
            sync.publish(plan)
        commit.assert_not_called()

    def test_migration_refuses_to_discard_unpublished_other_client(self):
        changed = self.platform(b"unpublished Forever edit\n")
        dev = self.snapshot({**self.root, "Forever": changed}, self.base)
        self.ref("retail/dev", dev)
        with self.assertRaisesRegex(sync.SyncError, "dev-only changes in Forever/"):
            sync.prepare("retail", "from-main", self.base)

    def test_backport_refuses_to_overwrite_dev_only_ci(self):
        changed = self.directory({"ci": self.directory({"test.py": self.blob(b"dev changes\n")})})
        dev = self.snapshot({**self.flat(self.retail), ".tools": changed}, self.base)
        self.ref("retail/dev", dev)
        with self.assertRaisesRegex(sync.SyncError, "dev-only changes in .tools/ci/"):
            sync.prepare("retail", "from-main", self.base)

    def test_latest_merged_transfer_must_preserve_ancestry(self):
        dev = self.snapshot(self.flat(self.retail), self.base)
        real_command = sync.command

        for preserve in (True, False):
            with self.subTest(preserve=preserve):
                parents = (self.base, dev) if preserve else (self.base,)
                main = self.snapshot(self.root, *parents)
                self.ref("main", main)

                def gh(*args, **kwargs):
                    if args[0] == "gh":
                        row = f"12\t{main}\n".encode() if "platform-sync/retail/to-main" in args else b""
                        return subprocess.CompletedProcess(args, 0, row)
                    return real_command(*args, **kwargs)

                with patch.object(sync, "command", side_effect=gh):
                    if preserve:
                        sync.verify_merge_history("retail")
                    else:
                        with self.assertRaisesRegex(sync.SyncError, "PR #12 did not preserve merge ancestry"):
                            sync.verify_merge_history("retail")

    @unittest.skipUnless(shutil.which("bash"), "Bash required for release workflow tests")
    def test_release_rejects_tag_on_imported_dev_commit(self):
        workflow = Path(__file__).resolve().parents[3] / ".github/workflows/release.yml"
        block = workflow.read_text(encoding="utf-8").split("      - name: Verify release comes from main\n", 1)[1]
        script = textwrap.dedent(block.split("        run: |\n", 1)[1].split("\n\n", 1)[0])
        dev = self.snapshot(self.flat(self.retail), self.base)
        main = self.snapshot(self.root, self.base, dev)
        self.ref("main", main)

        for tagged, expected in ((main, 0), (self.base, 0), (dev, 1)):
            with self.subTest(tagged=tagged):
                sync.git("update-ref", "refs/heads/release-fixture", tagged)
                sync.git("symbolic-ref", "HEAD", "refs/heads/release-fixture")
                result = subprocess.run(["bash", "-c", script], env=sync.ENV,
                                        capture_output=True, timeout=10)
                self.assertEqual(result.returncode, expected, result.stderr)
