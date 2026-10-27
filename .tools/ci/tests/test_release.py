import importlib.util
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from zipfile import ZipFile


spec = importlib.util.spec_from_file_location(
    "build_release", Path(__file__).resolve().parents[1] / "build_release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="spellbook-release-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.output = self.root / "release.zip"

        for addon in release.check.ADDONS:
            directory = self.root / addon
            directory.mkdir()
            (directory / (addon + ".toc")).write_text(
                "## Title: Test\n## Version: 1\n## Interface: 120100\nMain.lua\n",
                encoding="utf-8")
            (directory / "Main.lua").write_text("return true\n", encoding="utf-8")

    def set_version(self, value):
        for addon in release.check.ADDONS:
            toc = self.root / addon / (addon + ".toc")
            toc.write_text(f"## Title: Test\n## Version: {value}\n## Interface: 120100\nMain.lua\n", encoding="utf-8")

    def test_only_three_addon_roots(self):
        for name in ("LICENSE", "README.md", ".github", ".tools", "tests"):
            (self.root / name).write_text("not shipped", encoding="utf-8")

        self.assertEqual(release.build(self.root, self.output), 6)

        with ZipFile(self.output) as archive:
            expected = {
                f"{addon}/{name}"
                for addon in release.check.ADDONS
                for name in (addon + ".toc", "Main.lua")
            }
            self.assertEqual(set(archive.namelist()), expected)
            self.assertIsNone(archive.testzip())

    def test_missing_manifest(self):
        addon = release.check.ADDONS[0]
        (self.root / addon / (addon + ".toc")).unlink()

        with self.assertRaisesRegex(ValueError, "manifest"):
            release.build(self.root, self.output)

        self.assertFalse(self.output.exists())

    def test_unapproved_nested_file(self):
        path = self.root / release.check.ADDONS[0] / "extra.txt"
        path.write_text("not runtime", encoding="utf-8")

        with self.assertRaisesRegex(ValueError, "deliverable type"):
            release.build(self.root, self.output)

        self.assertFalse(self.output.exists())

    def test_existing_output_is_preserved(self):
        self.output.write_bytes(b"existing")

        with self.assertRaises(FileExistsError):
            release.build(self.root, self.output)

        self.assertEqual(self.output.read_bytes(), b"existing")

    def test_output_inside_addon_is_rejected(self):
        output = self.root / release.check.ADDONS[0] / "release.zip"

        with self.assertRaisesRegex(ValueError, "outside addon"):
            release.build(self.root, output)

        self.assertFalse(output.exists())

    def test_write_failure_removes_partial_archive(self):
        with patch.object(release.ZipFile, "write", side_effect=OSError("write failed")):
            with self.assertRaises(OSError):
                release.build(self.root, self.output)

        self.assertFalse(self.output.exists())

    def test_bad_archive_is_not_kept(self):
        with patch.object(release.ZipFile, "testzip", return_value="bad.lua"):
            with self.assertRaisesRegex(ValueError, "integrity"):
                release.build(self.root, self.output)

        self.assertFalse(self.output.exists())

    def test_missing_addon_directory(self):
        root = self.root / "empty"
        root.mkdir()

        with self.assertRaisesRegex(ValueError, "Missing or wrong-case"):
            release.build(root, self.output)

        self.assertFalse(self.output.exists())


    def test_notes_gate_starts_at_1_2(self):
        with patch.object(release.shutil, "which", return_value="lua5.1"), \
                patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "PASS")) as run:
            for value in ("1.1", "1.1.999", "1.2", "1.2.0", "1.10", "2.0"):
                self.set_version(value)
                before = run.call_count
                release.build(self.root, self.output)
                expected = 0 if release.version(value) < (1, 2, 0) else 1
                self.assertEqual(run.call_count - before, expected)
                self.output.unlink()

    def test_notes_failure_prevents_zip_creation(self):
        self.set_version("1.2")
        with patch.object(release.shutil, "which", return_value="lua5.1"), \
                patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "Missing current notes")):
            with self.assertRaisesRegex(ValueError, "Missing current notes"):
                release.build(self.root, self.output)
        self.assertFalse(self.output.exists())

    def test_missing_lua_does_not_bypass_notes_gate(self):
        self.set_version("1.2")
        with patch.object(release.shutil, "which", return_value=None):
            with self.assertRaisesRegex(ValueError, "lua5.1"):
                release.build(self.root, self.output)
        self.assertFalse(self.output.exists())

    def test_notes_timeout_prevents_zip_creation(self):
        self.set_version("1.2")
        with patch.object(release.shutil, "which", return_value="lua5.1"), \
                patch.object(release.subprocess, "run", side_effect=subprocess.TimeoutExpired("lua5.1", 30)):
            with self.assertRaisesRegex(ValueError, "30 seconds"):
                release.build(self.root, self.output)
        self.assertFalse(self.output.exists())

    def test_notes_check_uses_literal_arguments_and_clean_lua_environment(self):
        self.set_version("1.2")
        with patch.object(release.shutil, "which", return_value="lua5.1"), \
                patch.object(release.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "PASS")) as run, \
                patch.dict(os.environ, {"LUA_INIT": "untrusted preload"}):
            release.build(self.root, self.output, "release/v1.2")
        args, kwargs = run.call_args
        self.assertEqual(args[0], ["lua5.1", str(Path(release.__file__).with_name("check_release_notes.lua")), str(self.root), "1.2"])
        self.assertEqual(kwargs["timeout"], 30)
        self.assertIs(kwargs["shell"], False)
        self.assertFalse(any(key.startswith("LUA_") for key in kwargs["env"]))

    def test_release_tag_cannot_bypass_gate_with_old_metadata(self):
        self.set_version("1.1")
        with self.assertRaisesRegex(ValueError, "tag and addon version"):
            release.build(self.root, self.output, "release/v1.2")
        self.assertFalse(self.output.exists())

    def test_existing_tag_style_and_numeric_aliases_are_supported(self):
        self.set_version("1.1")
        for tag in ("1.1", "v1.1", "release/v1.1", "release/v1.1.0"):
            release.build(self.root, self.output, tag)
            self.output.unlink()

    def test_package_version_mismatch_is_rejected(self):
        self.set_version("1.1")
        toc = self.root / release.check.ADDONS[1] / (release.check.ADDONS[1] + ".toc")
        toc.write_text(toc.read_text(encoding="utf-8").replace("Version: 1.1", "Version: 1.2"), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "package versions"):
            release.build(self.root, self.output)
        self.assertFalse(self.output.exists())

    def test_failed_notes_check_preserves_existing_output(self):
        self.set_version("1.2")
        self.output.write_bytes(b"existing")
        with patch.object(release.shutil, "which", return_value=None):
            with self.assertRaises(ValueError):
                release.build(self.root, self.output)
        self.assertEqual(self.output.read_bytes(), b"existing")


if __name__ == "__main__":
    unittest.main()
