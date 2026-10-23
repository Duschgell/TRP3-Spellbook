import importlib.util
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


if __name__ == "__main__":
    unittest.main()
