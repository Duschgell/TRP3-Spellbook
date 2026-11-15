import importlib.util
import os
import re
import shutil
import subprocess
import tempfile
import textwrap
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
        self.source = self.root / "Retail"
        self.output = self.root / "release.zip"

        for platform, interface, allowed, excluded in (
            ("Retail", "120105", "standard", "camelot, classic"),
            ("Forever", "16001", "camelot", "standard, classic"),
        ):
            for addon in release.check.ADDONS:
                directory = self.root / platform / addon
                directory.mkdir(parents=True)
                dependency = "totalRP3" if addon == release.check.CORE else release.check.CORE
                (directory / (addon + ".toc")).write_text(
                    f"## Title: Test\n## Version: 1\n## Interface: {interface}\n"
                    f"## AllowLoadGameType: {allowed}\n## ExcludeLoadGameType: {excluded}\n"
                    f"## RequiredDeps: {dependency}\nMain.lua\n", encoding="utf-8")
                (directory / "Main.lua").write_text(f"return '{platform}'\n", encoding="utf-8")

    def set_version(self, value):
        for addon in release.check.ADDONS:
            toc = self.source / addon / (addon + ".toc")
            updated = re.sub(r"(?m)^## Version: .+$", f"## Version: {value}",
                             toc.read_text(encoding="utf-8"))
            toc.write_text(updated, encoding="utf-8")

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

    def test_packages_are_separate_and_keep_runtime_and_dependencies(self):
        retail = self.root / "retail.zip"
        forever = self.root / "forever.zip"
        release.build(self.root, retail, target="retail")
        release.build(self.root, forever, target="forever")

        with ZipFile(retail) as retail_zip, ZipFile(forever) as forever_zip:
            self.assertEqual(retail_zip.namelist(), forever_zip.namelist())
            self.assertIsNone(retail_zip.testzip())
            self.assertIsNone(forever_zip.testzip())
            for addon in release.check.ADDONS:
                toc = f"{addon}/{addon}.toc"
                for archive, platform in ((retail_zip, "Retail"), (forever_zip, "Forever")):
                    self.assertEqual(archive.read(toc), (self.root / platform / toc).read_bytes())
                    self.assertEqual(archive.read(f"{addon}/Main.lua"),
                                     (self.root / platform / addon / "Main.lua").read_bytes())

    def test_unsupported_target_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unsupported build target"):
            release.build(self.root, self.output, target="classic")
        self.assertFalse(self.output.exists())

    def test_holiday_files_and_load_entries_are_retail_only(self):
        addon = release.check.CORE
        root = Path(__file__).resolve().parents[3]
        toc = f"{addon}.toc"
        holiday_files = (
            "Core/SeasonalCalendar.lua", "Data/SeasonalStyles.lua",
            "UI/SeasonalCorners.lua", "UI/SeasonalOrnaments.lua", "UI/SeasonalVisuals.lua",
        )
        versions = []
        for target in ("retail", "forever"):
            if os.environ.get("BUILD_TARGET", "both") not in ("both", target):
                continue
            output = self.root / f"{target}.zip"
            with patch.object(release, "check_release_notes"):
                release.build(root, output, target=target)
            with ZipFile(output) as archive:
                includes_holidays = target == "retail"
                lines = archive.read(f"{addon}/{toc}").decode("utf-8").splitlines()
                versions.append(next(line for line in lines if line.startswith("## Version: ")))
                self.assertIn("UI\\FancyBookControls.lua", lines)
                for name in holiday_files:
                    self.assertEqual(name.replace("/", "\\") in lines, includes_holidays)
                    self.assertEqual(f"{addon}/{name}" in archive.namelist(), includes_holidays)
        self.assertTrue(versions)
        self.assertEqual(len(set(versions)), 1)

    def test_flat_checkout_packages_only_its_own_client(self):
        source = self.root / "Forever"
        release.build(source, self.output, target="forever")
        with ZipFile(self.output) as archive:
            self.assertIn(b"'Forever'", archive.read(f"{release.check.CORE}/Main.lua"))
        with self.assertRaisesRegex(ValueError, "Unexpected retail interface"):
            release.build(source, self.root / "wrong.zip", target="retail")

    def test_forever_manifest_preserves_utf8_bom_and_crlf(self):
        addon = release.check.ADDONS[0]
        toc = self.root / "Forever" / addon / f"{addon}.toc"
        source = b"\xef\xbb\xbf" + toc.read_text(encoding="utf-8").replace("\n", "\r\n").encode()
        toc.write_bytes(source)
        release.build(self.root, self.output, target="forever")
        with ZipFile(self.output) as archive:
            self.assertEqual(archive.read(f"{addon}/{toc.name}"), source)

    def test_additional_manifest_is_rejected(self):
        addon = release.check.ADDONS[0]
        manifest = self.root / "Forever" / addon / f"{addon}_Camelot.toc"
        manifest.write_bytes(manifest.with_name(f"{addon}.toc").read_bytes())
        with self.assertRaisesRegex(ValueError, "additional manifest"):
            release.build(self.root, self.output, target="forever")
        self.assertFalse(self.output.exists())

    def test_interface_must_match_target(self):
        addon = release.check.ADDONS[0]
        toc = self.root / "Forever" / addon / f"{addon}.toc"
        original = toc.read_bytes()
        for interface in (b"120105", b"120105, 16001"):
            with self.subTest(interface=interface):
                toc.write_bytes(original.replace(b"16001", interface))
                with self.assertRaisesRegex(ValueError, "Unexpected forever interface"):
                    release.build(self.root, self.output, target="forever")
                self.assertFalse(self.output.exists())

    def test_source_game_type_gate_is_rejected(self):
        addon = release.check.ADDONS[0]
        toc = self.root / "Forever" / addon / f"{addon}.toc"
        toc.write_bytes(toc.read_bytes().replace(b"AllowLoadGameType: camelot", b"AllowLoadGameType: standard"))
        with self.assertRaisesRegex(ValueError, "Unexpected game type restrictions"):
            release.build(self.root, self.output, target="forever")
        self.assertFalse(self.output.exists())

    def test_missing_manifest(self):
        addon = release.check.ADDONS[0]
        (self.source / addon / (addon + ".toc")).unlink()

        with self.assertRaisesRegex(ValueError, "manifest"):
            release.build(self.root, self.output)

        self.assertFalse(self.output.exists())

    def test_unapproved_nested_file(self):
        path = self.source / release.check.ADDONS[0] / "extra.txt"
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
        output = self.source / release.check.ADDONS[0] / "release.zip"

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
        self.assertEqual(args[0], ["lua5.1", str(Path(release.__file__).with_name("check_release_notes.lua")), str(self.source), "1.2"])
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
        toc = self.source / release.check.ADDONS[1] / (release.check.ADDONS[1] + ".toc")
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


@unittest.skipUnless(shutil.which("bash"), "Bash required for release workflow tests")
class ReleaseUploadTests(unittest.TestCase):
    retail = "/release files/TRP3_Spellbook-Retail.zip"
    forever = "/release files/TRP3_Spellbook-Forever.zip"
    license = "/source files/LICENSE"

    def run_upload(self, assets="", *, view_status="0", upload_status="0"):
        root = Path(__file__).resolve().parents[3]
        workflow = (root / ".github/workflows/release.yml").read_text(encoding="utf-8")
        step = workflow.split("- name: Attach both ZIPs and license to release\n", 1)[1]
        block = step.split("        run: |\n", 1)[1].splitlines()
        script = textwrap.dedent("\n".join(line for line in block if line)).rstrip()
        stub = """
gh() {
    case "$1 $2" in
        "release view")
            printf '%s' "$TEST_ASSETS"
            return "$VIEW_STATUS"
            ;;
        "release upload")
            shift 2
            printf 'UPLOAD %s\\n' "$@"
            return "$UPLOAD_STATUS"
            ;;
        *) return 99 ;;
    esac
}
"""
        result = subprocess.run(
            ["bash", "--noprofile", "--norc", "-s"],
            input=stub + script + "\n", text=True, capture_output=True, timeout=10,
            env=dict(os.environ, TEST_ASSETS=assets, VIEW_STATUS=view_status,
                     UPLOAD_STATUS=upload_status, RUNNER_TEMP="/release files",
                     GITHUB_WORKSPACE="/source files", GITHUB_REPOSITORY="owner/repo",
                     RELEASE_TAG="v1.2.2", BASH_ENV=""),
        )
        args = [line.removeprefix("UPLOAD ") for line in result.stdout.splitlines()
                if line.startswith("UPLOAD ")]
        return result, args

    def test_upload_only_missing_assets(self):
        uploaded = lambda path: f"{Path(path).name}\tuploaded\n"
        for assets, missing in (
            ("", [self.retail, self.forever, self.license]),
            (uploaded(self.retail) + uploaded(self.license), [self.forever]),
            (uploaded(self.retail) + uploaded(self.forever) + uploaded(self.license), []),
        ):
            with self.subTest(assets=assets):
                result, args = self.run_upload(assets)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(args, ["--repo", "owner/repo", "--", "v1.2.2", *missing]
                                 if missing else [])

    def test_incomplete_asset_is_not_treated_as_uploaded(self):
        result, args = self.run_upload("TRP3_Spellbook-Forever.zip\tstarter\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("TRP3_Spellbook-Forever.zip is incomplete", result.stderr)
        self.assertEqual(args, [])

    def test_lookup_failure_aborts_and_upload_failure_is_reported(self):
        result, args = self.run_upload(view_status="42")
        self.assertEqual(result.returncode, 42)
        self.assertEqual(args, [])
        result, args = self.run_upload(upload_status="43")
        self.assertEqual(result.returncode, 43)
        self.assertIn(self.forever, args)


if __name__ == "__main__":
    unittest.main()
