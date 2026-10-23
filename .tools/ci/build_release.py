#!/usr/bin/env python3

import importlib.util
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


spec = importlib.util.spec_from_file_location(
    "addon_check", Path(__file__).with_name("addon_check.py"))
check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check)


def build(root, output):
    root = Path(root).absolute()
    output = Path(output).absolute()
    check.require(output.suffix == ".zip", "Output must be a .zip file")
    files = {}

    for addon in check.ADDONS:
        directory = check.exact(root, addon, "directory")
        check.require(not output.resolve().is_relative_to(directory.resolve()),
                      "Output must be outside addon directories")
        entries = check.inventory(directory)
        toc = addon + ".toc"
        check.require(toc in entries, f"Missing exact-name manifest: {addon}/{toc}")
        check.manifest(entries[toc])
        files.update((f"{addon}/{name}", path) for name, path in entries.items())

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
    check.require(len(sys.argv) == 3,
                  "Usage: build_release.py REPOSITORY_ROOT OUTPUT.zip")
    count = build(sys.argv[1], sys.argv[2])
    print(f"PASS: {count} files in three addon folders: {sys.argv[2]}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"Release build failed: {error}", file=sys.stderr)
        sys.exit(1)
