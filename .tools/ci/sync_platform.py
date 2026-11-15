"""Prepare a reviewable transfer between the flat client and main layouts."""

import argparse
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys

spec = importlib.util.spec_from_file_location(
    "addon_check", Path(__file__).with_name("addon_check.py"))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


class SyncError(RuntimeError):
    pass


ADDON_NAMES = {name.encode() for name in check.ADDONS}
PLATFORM_NAMES = {config[0].encode() for config in check.TARGETS.values()}
SHARED_CI = ((b".github", b"workflows"), (b".tools", b"ci"))
BOT = "github-actions[bot]"
BOT_EMAIL = "41898282+github-actions[bot]@users.noreply.github.com"
ENV = dict(os.environ, GIT_AUTHOR_NAME=BOT, GIT_AUTHOR_EMAIL=BOT_EMAIL,
           GIT_COMMITTER_NAME=BOT, GIT_COMMITTER_EMAIL=BOT_EMAIL, GH_PROMPT_DISABLED="1")


def command(*args, data=None, allow_failure=False):
    result = subprocess.run(args, input=data, stdout=subprocess.PIPE, env=ENV, check=False)
    if result.returncode and not allow_failure:
        raise SyncError(f"{args[0]} {args[1]} failed (exit {result.returncode})")
    return result


def git(*args, data=None):
    return command("git", *args, data=data).stdout.strip()


def entries(tree):
    result = {}
    for record in git("ls-tree", "-z", tree).split(b"\0"):
        if record:
            header, name = record.split(b"\t", 1)
            result[name] = header
    return result


def make_tree(items):
    data = b"".join(header + b"\t" + name + b"\0" for name, header in items.items())
    return git("mktree", "-z", data=data).decode("ascii")


def tree_id(header):
    mode, kind, oid = header.split()
    if mode != b"040000" or kind != b"tree":
        raise SyncError("Expected a source directory")
    return oid.decode("ascii")


def project(revision, folder):
    root = entries(revision)
    if folder in root:
        if ADDON_NAMES.intersection(root):
            raise SyncError("Cannot synchronize a mixed source layout")
        root = entries(tree_id(root[folder]))
    elif PLATFORM_NAMES.intersection(root):
        raise SyncError(f"Missing {folder.decode()} on {revision}")
    if not ADDON_NAMES <= root.keys():
        raise SyncError(f"Missing one or more addon directories on {revision}")
    for addon in ADDON_NAMES:
        tree_id(root[addon])
    return {name: root[name] for name in ADDON_NAMES}


def commit(tree, message, *parents):
    args = [arg for parent in parents for arg in ("-p", parent)]
    return git("commit-tree", tree, *args, "-m", message).decode("ascii")


def merge_platform(base, destination, source, folder):
    base_tree, destination_tree, source_tree = (
        make_tree(project(rev, folder)) for rev in (base, destination, source))
    if destination_tree == source_tree or source_tree == base_tree:
        return destination_tree
    if destination_tree == base_tree:
        return source_tree
    ancestor = commit(base_tree, "Platform merge base")
    ours = commit(destination_tree, "Platform destination", ancestor)
    theirs = commit(source_tree, "Platform source", ancestor)
    result = command("git", "merge-tree", "--write-tree", ours, theirs, allow_failure=True)
    if result.returncode != 0:
        sys.stderr.buffer.write(result.stdout)
        raise SyncError("Platform transfer could not be merged; no PR was updated")
    return result.stdout.splitlines()[0].decode("ascii")


def destination_tree(base, destination, source, platform_tree, folder, to_main):
    root = entries(destination)
    if to_main:
        root[folder] = b"040000 tree " + platform_tree.encode()
    else:
        ancestor = entries(base)
        main = entries(source)
        for other in PLATFORM_NAMES - {folder}:
            if other in root and root[other] not in (ancestor.get(other), main.get(other)):
                raise SyncError(f"Migration would discard dev-only changes in {other.decode()}/")
        for platform in PLATFORM_NAMES:
            root.pop(platform, None)
        root.update(entries(platform_tree))
        for parent, child in SHARED_CI:
            existing = entries(tree_id(root[parent])) if parent in root else {}
            base_ci = entries(tree_id(ancestor[parent])) if parent in ancestor else {}
            shared = entries(tree_id(main[parent]))
            if existing.get(child) not in (base_ci.get(child), shared[child]):
                raise SyncError(f"Backport would overwrite dev-only changes in {(parent + b'/' + child).decode()}/")
            existing[child] = shared[child]
            root[parent] = b"040000 tree " + make_tree(existing).encode()
    return make_tree(root)


def prepare(platform, direction, expected):
    folder = check.TARGETS[platform][0].encode()
    to_main = direction == "to-main"
    dev = f"{platform}/dev"
    base_branch, source_branch = ("main", dev) if to_main else (dev, "main")
    destination, source = (git("rev-parse", f"refs/remotes/origin/{name}").decode("ascii")
                           for name in (base_branch, source_branch))
    if source != expected:
        print(f"Skipping stale {source_branch} revision")
        return None
    dev_commit = source if to_main else destination
    if to_main and folder in entries(dev_commit):
        print(f"Waiting for the flat-layout migration on {dev}")
        return None
    bases = git("merge-base", "--all", destination, source).decode("ascii").splitlines()
    if len(bases) != 1:
        raise SyncError("Expected one common ancestor; resolve branch ancestry before syncing")
    merged = merge_platform(bases[0], destination, source, folder)
    tree = destination_tree(bases[0], destination, source, merged, folder, to_main)
    branch = f"platform-sync/{platform}/{direction}"
    title = f"Sync {source_branch} into {base_branch}"
    commit_message = f"{title}\n\nSpellbook-Platform-Sync: {branch}"
    return branch, base_branch, source, destination, tree, title, commit_message


def publish(plan):
    branch, base, source, destination, tree, title, message = plan
    empty = no_changes(destination, tree)
    current_pr = open_pull_request(branch, base=base)
    if empty and not current_pr:
        print(f"No changes for {base}")
        return
    prefix, _, direction = branch.rpartition("/")
    opposite = prefix + ("/from-main" if direction == "to-main" else "/to-main")
    opposite_base = prefix.split("/")[1] + "/dev" if base == "main" else "main"
    if not empty and open_pull_request(opposite, base=opposite_base):
        print(f"Waiting for the open transfer from {opposite}")
        return
    ref = f"refs/heads/{branch}"
    tracking = f"refs/remotes/origin/{branch}"
    existing = command("git", "rev-parse", "--verify", "--quiet", tracking, allow_failure=True)
    previous = existing.stdout.strip().decode("ascii")
    if existing.returncode not in (0, 1):
        raise SyncError("Could not check the generated branch")
    parents = (destination,) if destination == source else (destination, source)
    candidate_unchanged = False
    if previous:
        author, old_tree, old_parents, body = git(
            "show", "-s", "--format=%ae%n%T%n%P%n%B", previous).split(b"\n", 3)
        if author != BOT_EMAIL.encode() or body != message.encode():
            raise SyncError(f"Refusing to replace a manually updated branch: {branch}")
        candidate_unchanged = old_tree == tree.encode() and old_parents == " ".join(parents).encode()
    if empty:
        if not previous:
            raise SyncError(f"Cannot verify the open automation branch: {branch}")
        command("gh", "pr", "close", current_pr.decode("ascii"), "--comment",
                "Closed by platform sync: there are no longer changes to transfer.")
        return
    if not candidate_unchanged:
        candidate = commit(tree, message, *parents)
        # Only the dedicated automation ref is replaceable; the lease rejects concurrent changes.
        git("push", f"--force-with-lease={ref}:{previous}", "origin", f"{candidate}:{ref}")
    if not current_pr:
        command("gh", "pr", "create", "--head", branch, "--base", base, "--title", title,
                "--body", "Automated platform transfer. Review the files and use **Create a merge commit** (not squash or rebase) to retain the synchronization history.")


def open_pull_request(branch, *, base):
    result = command("gh", "pr", "list", "--head", branch, "--base", base, "--state", "open",
                     "--json", "number", "--jq", ".[].number").stdout.strip()
    if result and not result.isdigit():
        raise SyncError(f"Unexpected list of pull requests for {branch}")
    return result


def verify_merge_history(platform):
    for direction, base in (("to-main", "main"), ("from-main", f"{platform}/dev")):
        branch = f"platform-sync/{platform}/{direction}"
        row = command("gh", "pr", "list", "--head", branch, "--base", base, "--state", "merged",
                      "--limit", "10", "--json", "isCrossRepository,mergeCommit,number",
                      "--jq", "[.[] | select(.isCrossRepository == false)] | .[:1][] | [.number, .mergeCommit.oid] | @tsv"
                      ).stdout.strip()
        if not row:
            continue
        match = re.fullmatch(rb"([0-9]+)\t([0-9a-f]{40})", row)
        if not match:
            raise SyncError(f"Could not verify the last merged PR for {branch}")
        number, oid = (value.decode("ascii") for value in match.groups())
        parents = git("rev-list", "--parents", "-n", "1", oid).split()
        if len(parents) != 3:
            raise SyncError(f"PR #{number} did not preserve merge ancestry. "
                            "Restore the transfer history before syncing; use Create a merge commit for these PRs.")
        result = command("git", "merge-base", "--is-ancestor", oid,
                         f"refs/remotes/origin/{base}", allow_failure=True)
        if result.returncode:
            raise SyncError(f"PR #{number} is not in the history of {base}; no transfer attempted")


def no_changes(destination, tree):
    return tree == git("rev-parse", f"{destination}^{{tree}}").decode("ascii")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("platform", choices=check.TARGETS)
    parser.add_argument("direction", choices=("to-main", "from-main"))
    parser.add_argument("expected_source")
    args = parser.parse_args()
    verify_merge_history(args.platform)
    plan = prepare(args.platform, args.direction, args.expected_source)
    if plan:
        publish(plan)


if __name__ == "__main__":
    try:
        main()
    except (SyncError, OSError, KeyError, ValueError) as error:
        print(f"Platform sync failed: {error}", file=sys.stderr)
        sys.exit(1)
