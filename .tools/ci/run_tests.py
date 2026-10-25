#!/usr/bin/env python3

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BASE = Path(__file__).resolve().parent
ROOT = BASE.parents[1]
TESTS = BASE / "tests"
RUNNER = BASE / "runner.lua"


def invoke(lua, test_file, probe="", timeout=10):
    with tempfile.TemporaryDirectory(prefix="spellbook-test-") as directory:
        report = Path(directory) / "completed"
        try:
            process = subprocess.run(
                [lua, str(RUNNER), str(ROOT), str(test_file), str(report), probe],
                cwd=ROOT,
                env={
                    key: value
                    for key, value in os.environ.items()
                    if not key.startswith("LUA_")
                },
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
                shell=False,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            output = error.stdout or b""
            if isinstance(output, bytes):
                output = output.decode("utf-8", "replace")
            return "timeout", [], output + f"\nExceeded {timeout}s"
        except OSError as error:
            return "launch", [], str(error)

        if process.returncode != 0:
            return "exit", [], process.stdout

        try:
            lines = report.read_text(encoding="ascii").splitlines()
            magic, registered, executed, failed = lines[0].split("\t")
            registered, executed, failed = map(int, (registered, executed, failed))
            rows = [line.split("\t") for line in lines[1:]]
            if (
                magic != "SBTEST1"
                or registered <= 0
                or executed != registered
                or failed != 0
                or len(rows) != registered
            ):
                raise ValueError("incomplete final status")
            for row in rows:
                if (
                    len(row) != 2
                    or not re.fullmatch(r"[a-z][a-z0-9_.-]+", row[0])
                    or not row[1].isdigit()
                    or int(row[1]) < 1
                ):
                    raise ValueError("invalid case/assertion record")
            identifiers = [row[0] for row in rows]
            if len(set(identifiers)) != registered:
                raise ValueError("duplicate case IDs")
        except (OSError, UnicodeError, ValueError, IndexError) as error:
            return "report", [], process.stdout + f"\nInvalid completion: {error}"
        return "ok", identifiers, process.stdout


def main():
    lua = shutil.which("lua5.1")
    if not lua:
        raise RuntimeError("Required executable not found: lua5.1")
    test_files = sorted(TESTS.rglob("*.spec.lua"))
    if not test_files:
        raise RuntimeError("No *.spec.lua tests discovered")
    if any(not path.resolve().is_relative_to(TESTS.resolve()) for path in test_files):
        raise RuntimeError("Test resolves outside the test directory")

    probes = {
        "ok": "ok", "assertion": "exit", "suppressed": "exit", "empty": "exit",
        "duplicate": "exit", "skip": "exit", "noassert": "exit",
        "plan": "exit", "setup": "exit", "return": "exit",
        "early": "report", "timeout": "timeout",
    }
    for probe, expected in probes.items():
        kind, _, output = invoke(
            lua, TESTS / "probe", probe, timeout=1 if probe == "timeout" else 10
        )
        if kind != expected:
            raise RuntimeError(
                f"Runner probe {probe}: expected {expected}, got {kind}\n{output}"
            )

    failed, seen = False, set()
    for test_file in test_files:
        kind, identifiers, output = invoke(lua, test_file)
        duplicates = seen.intersection(identifiers)
        if kind != "ok" or duplicates:
            failed = True
            print(
                f"FAIL {test_file.relative_to(ROOT)}: {kind}; "
                f"duplicate IDs={sorted(duplicates)}\n{output}",
                file=sys.stderr,
            )
        else:
            print(f"{test_file.relative_to(ROOT)}: {len(identifiers)} cases completed")
        seen.update(identifiers)
    return int(failed or not seen)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print(f"Test runner failed: {error}", file=sys.stderr)
        sys.exit(1)
