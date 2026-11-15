#!/usr/bin/env python3

import argparse
import importlib.util
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


spec = importlib.util.spec_from_file_location(
    "addon_check", Path(__file__).with_name("addon_check.py"))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)

def version(value):
    check.require(isinstance(value, str) and len(value) <= 24
                  and re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value),
                  "Expected a stable numeric release version")
    parts = tuple(map(int, value.split(".")))
    check.require(all(part <= 999999 for part in parts), "Release version component is too large")
    return parts + (0,) * (3 - len(parts))


def check_release_notes(root, current):
    if version(current) < (1, 2, 0):
        return
    lua = shutil.which("lua5.1")
    check.require(lua, "Required tool missing for release notes: lua5.1")
    script = Path(__file__).with_name("check_release_notes.lua")
    try:
        result = subprocess.run(
            [lua, str(script), str(root), current], cwd=root,
            env={key: value for key, value in os.environ.items() if not key.startswith("LUA_")},
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            encoding="utf-8", errors="replace", timeout=30, check=False, shell=False,
        )
    except subprocess.TimeoutExpired as error:
        raise ValueError("Release notes check exceeded 30 seconds") from error
    check.require(result.returncode == 0, "Release notes check failed: " + result.stdout.strip())
    print(result.stdout.strip())


def build(root, output, release_tag=None, *, target="retail"):
    root = Path(root).absolute()
    source = check.platform_root(root, target)
    output = Path(output).absolute()
    check.require(output.suffix == ".zip", "Output must be a .zip file")
    files = {}
    versions = {}
    interfaces = set()

    for addon in check.ADDONS:
        directory = check.exact(source, addon, "directory")
        check.require(not output.resolve().is_relative_to(directory.resolve()),
                      "Output must be outside addon directories")
        entries = check.inventory(directory)
        toc = addon + ".toc"
        check.require(toc in entries, f"Missing exact-name manifest: {addon}/{toc}")
        check.require({name for name in entries if name.endswith(".toc")} == {toc},
                      f"Unexpected additional manifest in {addon}")
        metadata, _ = check.manifest(entries[toc])
        check.check_target_manifest(metadata, target, toc)
        interfaces.add(metadata["interface"])
        versions[addon] = metadata["version"]
        files.update((f"{addon}/{name}", path) for name, path in entries.items())

    current = versions[check.CORE]
    check.require(len(set(versions.values())) == 1, "Addon package versions disagree")
    check.require(len(interfaces) == 1, "Addon package interfaces disagree")
    if release_tag is not None:
        check.require(isinstance(release_tag, str), "Release tag must be text")
        check.require(version(release_tag.removeprefix("release/").removeprefix("v")) == version(current),
                      "Release tag and addon version disagree")
    check_release_notes(source, current)
    handle = output.open("xb")

    try:
        with handle:
            with ZipFile(handle, "w", compression=ZIP_DEFLATED) as archive:
                for name, path in sorted(files.items()):
                    archive.write(path, name)

        with ZipFile(output) as archive:
            names = archive.namelist()
            check.require(len(names) == len(set(names))
                          and set(names) == set(files), "ZIP inventory mismatch")
            check.require({name.split("/", 1)[0] for name in names}
                          == set(check.ADDONS), "Unexpected ZIP root")
            check.require(archive.testzip() is None, "ZIP integrity check failed")

    except BaseException:
        output.unlink()
        raise

    return len(files)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root")
    parser.add_argument("output")
    parser.add_argument("release_tag", nargs="?")
    parser.add_argument("--target", choices=check.TARGETS, default="retail")
    args = parser.parse_args()
    count = build(args.root, args.output, args.release_tag, target=args.target)
    print(f"PASS: {args.target}, {count} files in three addon folders: {args.output}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"Release build failed: {error}", file=sys.stderr)
        sys.exit(1)
