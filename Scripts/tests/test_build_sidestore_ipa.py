"""Verify unsigned iOS build settings, validation, packaging, and publication."""

from pathlib import Path
import plistlib
import shutil
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_sidestore_ipa as builder


def app_fixture(parent: Path, signed: bool = False) -> Path:
    """Create a small physical-device app without real user data or executable code."""
    app = parent / "iMusic.app"
    resources = app / "Test.bundle"
    resources.mkdir(parents=True)
    info = {
        "DTPlatformName": "iphoneos", "CFBundlePackageType": "APPL",
        "CFBundleIdentifier": "org.example.imusic", "CFBundleExecutable": "iMusic",
        "CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "4",
    }
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    executable = app / "iMusic"
    executable.write_text("synthetic executable")
    executable.chmod(0o755)
    assets = ["upload-index.html", "upload-index-test.js", "upload-index-test.css"]
    import json

    (resources / "upload-assets.json").write_text(json.dumps({"files": assets}))
    for name in assets:
        (resources / name).write_text("synthetic asset")
    (resources / "upload-licenses.txt").write_text("synthetic notices")
    if signed:
        (app / "_CodeSignature").mkdir()
        (app / "_CodeSignature/CodeResources").write_text("synthetic signature")
    return app


class SideStoreBuildTests(unittest.TestCase):
    def test_release_build_uses_device_sdk_and_disables_all_signing_inputs(self):
        runner = Mock()
        runner.directory = Path("/tmp/synthetic-sidestore-logs")
        with patch.object(builder, "prepare_web"):
            app = builder.build_release(runner, Path("/tmp/Build With Spaces"))
        command = runner.run.call_args.args[0]
        self.assertEqual(command[command.index("-scheme") + 1], "iMusic")
        self.assertEqual(command[command.index("-configuration") + 1], "Release")
        self.assertEqual(command[command.index("-destination") + 1], "generic/platform=iOS")
        self.assertIn("CODE_SIGNING_ALLOWED=NO", command)
        self.assertIn("CODE_SIGNING_REQUIRED=NO", command)
        self.assertIn("CODE_SIGN_IDENTITY=", command)
        self.assertIn("DEVELOPMENT_TEAM=", command)
        self.assertIn("PROVISIONING_PROFILE_SPECIFIER=", command)
        self.assertEqual(
            app, Path("/tmp/Build With Spaces/Build/Products/Release-iphoneos/iMusic.app")
        )


class SideStoreValidationTests(unittest.TestCase):
    def test_unsigned_device_app_with_arm64_and_web_assets_passes(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = app_fixture(Path(temporary))
            runner = Mock()
            runner.run.side_effect = [
                "arm64\n",
                builder.CommandError(
                    ["codesign"], f"{app}: code object is not signed at all",
                    Path("unsigned.log"),
                ),
            ]
            info = builder.validate_app(runner, app)
            self.assertEqual(info["CFBundleIdentifier"], "org.example.imusic")

    def test_signed_app_is_rejected_before_packaging(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = app_fixture(Path(temporary), signed=True)
            runner = Mock()
            runner.run.return_value = "arm64\n"
            with self.assertRaisesRegex(builder.BuildError, "signing artifact"):
                builder.validate_app(runner, app)
            self.assertEqual(runner.run.call_count, 1)

    def test_embedded_profile_is_rejected_even_without_signature_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = app_fixture(Path(temporary))
            (app / "embedded.mobileprovision").write_text("synthetic profile")
            runner = Mock()
            runner.run.return_value = "arm64\n"
            with self.assertRaisesRegex(builder.BuildError, "embedded.mobileprovision"):
                builder.validate_app(runner, app)

    def test_valid_codesign_verification_means_app_is_not_unsigned(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = app_fixture(Path(temporary))
            runner = Mock()
            runner.run.side_effect = ["arm64\n", "valid signature\n"]
            with self.assertRaisesRegex(builder.BuildError, "still has a code signature"):
                builder.validate_app(runner, app)


class SideStoreExportTests(unittest.TestCase):
    def test_export_has_standard_payload_and_preserves_executable_mode(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = app_fixture(root / "source")
            output = root / "output/iMusic.ipa"
            info = plistlib.loads((app / "Info.plist").read_bytes())
            runner = Mock()

            def run(command, label):
                """Provide the two ditto operations used after patched app validation."""
                if label == "copy-sidestore-app":
                    shutil.copytree(command[1], command[2])
                elif label == "package-sidestore-ipa":
                    payload = Path(command[-2])
                    with zipfile.ZipFile(command[-1], "w") as archive:
                        for path in payload.rglob("*"):
                            archive.write(path, path.relative_to(payload.parent))
                else:
                    self.fail(f"unexpected command label: {label}")
                return ""

            runner.run.side_effect = run
            with patch.object(builder, "validate_app", return_value=info):
                self.assertEqual(builder.export_ipa(runner, app, output, info), output)
            package_command = runner.run.call_args_list[-1].args[0]
            self.assertIn("--norsrc", package_command)
            with zipfile.ZipFile(output) as archive:
                self.assertIn("Payload/iMusic.app/Info.plist", archive.namelist())
                mode = archive.getinfo("Payload/iMusic.app/iMusic").external_attr >> 16
                self.assertTrue(mode & 0o111)

    def test_output_symlink_does_not_replace_its_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = app_fixture(root / "source")
            target = root / "keep.ipa"
            target.write_text("keep me")
            output = root / "iMusic.ipa"
            output.symlink_to(target)
            with self.assertRaisesRegex(builder.BuildError, "symbolic link"):
                builder.export_ipa(Mock(), app, output, {})
            self.assertEqual(target.read_text(), "keep me")

    def test_archive_with_signing_artifact_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = app_fixture(root / "source", signed=True)
            ipa = root / "signed.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                for path in app.rglob("*"):
                    archive.write(path, Path("Payload/iMusic.app") / path.relative_to(app))
            info = plistlib.loads((app / "Info.plist").read_bytes())
            with self.assertRaisesRegex(builder.BuildError, "signing artifact"):
                builder.validate_ipa(ipa, info)


class SideStoreWorkflowTests(unittest.TestCase):
    def test_skip_build_reuses_only_the_unsigned_cache_product(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            app = app_fixture(root / "Build/Products/Release-iphoneos")
            info = plistlib.loads((app / "Info.plist").read_bytes())
            destination = root / "iMusic.ipa"
            runner = Mock()
            with (
                patch.object(builder.sys, "platform", "darwin"),
                patch.object(builder, "Runner", return_value=runner),
                patch.object(builder, "build_release") as build,
                patch.object(builder, "validate_app", return_value=info) as validate,
                patch.object(builder, "export_ipa", return_value=destination) as export,
                patch("builtins.print"),
            ):
                self.assertEqual(builder.main([
                    "--skip-build", "--derived-data", str(root),
                    "--output", str(destination),
                ]), 0)
            build.assert_not_called()
            validate.assert_called_once_with(runner, app)
            export.assert_called_once_with(runner, app, destination, info)

    def test_main_does_not_resolve_an_output_symlink_before_the_safety_check(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            app = app_fixture(root / "Build/Products/Release-iphoneos")
            info = plistlib.loads((app / "Info.plist").read_bytes())
            target = root / "keep.ipa"
            target.write_text("keep me")
            output = root / "iMusic.ipa"
            output.symlink_to(target)
            runner = Mock()
            with (
                patch.object(builder.sys, "platform", "darwin"),
                patch.object(builder, "Runner", return_value=runner),
                patch.object(builder, "validate_app", return_value=info),
            ):
                with self.assertRaisesRegex(builder.BuildError, "symbolic link"):
                    builder.main([
                        "--skip-build", "--derived-data", str(root),
                        "--output", str(output),
                    ])
            self.assertEqual(target.read_text(), "keep me")


if __name__ == "__main__":
    unittest.main()
