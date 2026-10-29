import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request


SHA = re.compile(r"[0-9a-f]{40}\Z")
REPOSITORY = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_][A-Za-z0-9_.-]*\Z")
PREFIXES = ("feature/", "bugfix/", "task/")
MUTATION_ID = "spellbook-idle-sync"


class SyncError(RuntimeError):
    def __init__(self, message, status=None):
        super().__init__(message)
        self.status = status


def valid_sha(value):
    return isinstance(value, str) and SHA.fullmatch(value) is not None and value != "0" * 40


def valid_branch(name):
    return (isinstance(name, str) and bool(name) and not name.startswith(("/", "-"))
            and not name.endswith(("/", ".")) and ".." not in name and "@{" not in name
            and not any(ord(char) < 33 or ord(char) == 127 or char in "~^:?*[\\" for char in name)
            and all(part and not part.startswith(".") and not part.endswith(".lock")
                    for part in name.split("/")))


def eligible(name):
    return valid_branch(name) and name.startswith(PREFIXES) and name not in PREFIXES


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class GitHub:
    def __init__(self, repository, token):
        if not REPOSITORY.fullmatch(repository) or not token:
            raise SyncError("Invalid repository or missing token")
        self.repository = repository
        self.token = token
        self.repository_id = None
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, path, payload=None):
        if not path.startswith((f"/repos/{self.repository}/",)) and path not in (
                f"/repos/{self.repository}", "/graphql"):
            raise SyncError("Unexpected API path")
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        request = urllib.request.Request("https://api.github.com" + path, data=data, headers={
            "Authorization": "Bearer " + self.token,
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "spellbook-idle-branch-sync",
        })
        try:
            with self.opener.open(request, timeout=20) as response:
                body = response.read(8 * 1024 * 1024 + 1)
            if len(body) > 8 * 1024 * 1024:
                raise SyncError("GitHub response exceeds size limit")
            return json.loads(body)
        except urllib.error.HTTPError as error:
            status = error.code
            error.close()
            raise SyncError(f"GitHub request failed (HTTP {status})", status=status) from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise SyncError("GitHub request failed; no automatic mutation retry") from None
        except (ValueError, UnicodeError):
            raise SyncError("Invalid GitHub JSON response") from None

    def reference(self, name):
        if not valid_branch(name):
            raise SyncError("Invalid branch name")
        try:
            result = self.request(f"/repos/{self.repository}/git/ref/heads/"
                                  + urllib.parse.quote(name, safe=""))
        except SyncError as error:
            if error.status == 404:
                return None
            raise
        obj = result.get("object", {}) if isinstance(result, dict) else {}
        if (not isinstance(obj, dict) or obj.get("type") != "commit"
                or not valid_sha(obj.get("sha")) or result.get("ref") != "refs/heads/" + name):
            raise SyncError("Invalid branch reference response")
        return obj["sha"]

    def snapshots(self):
        branches = {}
        for page in range(1, 101):
            rows = self.request(f"/repos/{self.repository}/branches?page={page}&per_page=100")
            if not isinstance(rows, list) or len(rows) > 100:
                raise SyncError("Invalid branch listing")
            for row in rows:
                commit = row.get("commit", {}) if isinstance(row, dict) else {}
                if (not isinstance(row, dict) or not valid_branch(row.get("name"))
                        or not isinstance(commit, dict) or not valid_sha(commit.get("sha"))
                        or type(row.get("protected")) is not bool):
                    raise SyncError("Invalid branch listing entry")
                name = row["name"]
                if name in branches and branches[name] != row:
                    raise SyncError("Branch listing changed during pagination; retry on next dev push")
                branches[name] = row
            if len(rows) < 100:
                return list(branches.values())
        raise SyncError("Branch listing exceeds pagination limit")

    def compare(self, base, head):
        if not valid_sha(base) or not valid_sha(head):
            raise SyncError("Invalid comparison revision")
        return self.request(f"/repos/{self.repository}/compare/{base}...{head}?per_page=1")

    def protected(self, name):
        if not eligible(name):
            raise SyncError("Invalid protection lookup target")
        try:
            row = self.request(f"/repos/{self.repository}/branches/"
                               + urllib.parse.quote(name, safe=""))
        except SyncError as error:
            if error.status == 404:
                return True
            raise
        if not isinstance(row, dict) or row.get("name") != name or type(row.get("protected")) is not bool:
            raise SyncError("Invalid branch protection response")
        return row["protected"]

    def fast_forward(self, name, before, after):
        if not eligible(name) or not valid_sha(before) or not valid_sha(after) or before == after:
            raise SyncError("Invalid fast-forward target")
        if self.repository_id is None:
            repository = self.request(f"/repos/{self.repository}")
            self.repository_id = repository.get("node_id") if isinstance(repository, dict) else None
            if not isinstance(self.repository_id, str) or not self.repository_id:
                raise SyncError("Missing repository node ID")
        # beforeOid prevents overwriting concurrent work or recreating a deleted branch.
        result = self.request("/graphql", {
            "query": "mutation($input:UpdateRefsInput!) { updateRefs(input:$input) { clientMutationId } }",
            "variables": {"input": {
                "repositoryId": self.repository_id, "clientMutationId": MUTATION_ID,
                "refUpdates": [{"name": "refs/heads/" + name, "beforeOid": before,
                                "afterOid": after, "force": False}],
            }},
        })
        data = result.get("data") if isinstance(result, dict) else None
        update = data.get("updateRefs") if isinstance(data, dict) else None
        if (not isinstance(result, dict) or result.get("errors") or not isinstance(update, dict)
                or update.get("clientMutationId") != MUTATION_ID):
            raise SyncError("Branch update rejected; check token permissions and branch rules")


def synchronize(client, target, apply=False, report=None):
    if not valid_sha(target):
        raise SyncError("Invalid tested dev revision")
    if report is None:
        report = lambda record: print(json.dumps(record, ensure_ascii=True))
    if client.reference("dev") != target:
        report({"result": "stale-dev"})
        return
    for row in client.snapshots():
        name, before = row["name"], row["commit"]["sha"]
        if not eligible(name):
            continue
        if row["protected"]:
            report({"branch": name, "result": "protected"})
            continue
        if before == target:
            report({"branch": name, "result": "current"})
            continue
        comparison = client.compare(target, before)
        merge_base = comparison.get("merge_base_commit") if isinstance(comparison, dict) else None
        if not (isinstance(comparison, dict) and comparison.get("status") == "behind"
                and type(comparison.get("ahead_by")) is int and comparison["ahead_by"] == 0
                and type(comparison.get("behind_by")) is int and comparison["behind_by"] > 0
                and isinstance(merge_base, dict) and merge_base.get("sha") == before):
            report({"branch": name, "result": "own-commits-or-unverified"})
            continue
        if client.protected(name):
            report({"branch": name, "result": "protected-or-deleted"})
            continue
        if client.reference("dev") != target:
            report({"result": "stale-dev"})
            return
        if not apply:
            report({"branch": name, "result": "planned"})
            continue
        try:
            client.fast_forward(name, before, target)
        except SyncError:
            if client.reference(name) != before:
                report({"branch": name, "result": "changed"})
                continue
            raise
        report({"branch": name, "result": "updated"})


def context(apply=False):
    if apply and (os.environ.get("GITHUB_ACTIONS") != "true"
                  or os.environ.get("GITHUB_EVENT_NAME") != "push"
                  or os.environ.get("GITHUB_REF") != "refs/heads/dev"):
        raise SyncError("Apply is restricted to the dev push workflow")
    repository, target, token = (os.environ.get(key, "") for key in (
        "GITHUB_REPOSITORY", "GITHUB_SHA", "GH_TOKEN"))
    if not REPOSITORY.fullmatch(repository) or not valid_sha(target) or not token:
        raise SyncError("Missing or invalid repository, tested revision or token")
    return repository, target, token


def main():
    parser = argparse.ArgumentParser(description="Fast-forward idle development branches; read-only by default.")
    parser.add_argument("--apply", action="store_true", help="Apply in the successful dev push workflow only")
    args = parser.parse_args()
    counts = Counter()
    target = None

    def report(record):
        counts[record["result"]] += 1
        print(json.dumps(record, ensure_ascii=True), flush=True)

    try:
        repository, target, token = context(apply=args.apply)
        synchronize(GitHub(repository, token), target, apply=args.apply, report=report)
        return 0
    except SyncError as error:
        report({"result": "failed"})
        print(str(error), file=sys.stderr)
        return 1
    finally:
        summary = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary:
            with Path(summary).open("a", encoding="utf-8") as output:
                output.write("### Idle branch synchronization\n\n")
                if valid_sha(target):
                    output.write(f"Tested dev revision: `{target}`\n\n")
                for result, count in sorted(counts.items()):
                    output.write(f"- {result}: {count}\n")


if __name__ == "__main__":
    sys.exit(main())
