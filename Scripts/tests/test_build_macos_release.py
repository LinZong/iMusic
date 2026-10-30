"""Verify Release CPU coverage, bundled resources, and safe macOS app export."""

import json
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_macos_release as builder


def app_fixture(parent: Path, bundle_id="org.example.imusic") -> Path:
    """Create a small synthetic app tree without executable audio or user data."""
    app = parent / "iMusic.app"
    contents = app / "Contents"
    resources = contents / "Resources/Test.bundle/Contents/Resources"
    resources.mkdir(parents=True)
    (contents / "Info.plist").write_bytes(plistlib.dumps({
        "DTPlatformName": "macosx", "CFBundlePackageType": "APPL",
        "CFBundleIdentifier": bundle_id, "CFBundleExecutable": "iMusic",
    }))
    binary = contents / "MacOS/iMusic"
    binary.parent.mkdir()
    binary.write_text("synthetic executable")
    names = ["upload-index.html", "upload-index-test.js", "upload-index-test.css"]
    (resources / "upload-assets.json").write_text(json.dumps({"files": names}))
    for name in names:
        (resources / name).write_text("synthetic asset")
    (resources / "upload-licenses.txt").write_text("synthetic notice")
    return app


class MacBuildTests(unittest.TestCase):
    def test_release_is_universal_and_independent_of_personal_signing_settings(self):
        runner = Mock()
        with patch.object(builder, "prepare_web"):
            builder.build_release(runner, Path("/tmp/Build With Spaces"), "universal")
        command = runner.run.call_args.args[0]
        self.assertEqual(command[command.index("-configuration") + 1], "Release")
        self.assertEqual(command[command.index("-scheme") + 1], "iMusicMac")
        self.assertIn("ARCHS=arm64 x86_64", command)
        self.assertIn("ONLY_ACTIVE_ARCH=NO", command)
        self.assertIn("CODE_SIGN_IDENTITY=-", command)
        self.assertIn("DEVELOPMENT_TEAM=", command)

    def test_universal_build_rejects_a_missing_intel_slice(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = app_fixture(Path(temporary))
            runner = Mock()
            runner.run.return_value = "arm64\n"
            with self.assertRaisesRegex(builder.BuildError, "Incorrect app architectures"):
                builder.validate_app(runner, app, "universal")

    def test_correct_universal_bundle_requires_recursive_signature_verification(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = app_fixture(Path(temporary))
            runner = Mock()
            runner.run.side_effect = ["arm64 x86_64\n", ""]
            info = builder.validate_app(runner, app, "universal")
            self.assertEqual(info["CFBundleIdentifier"], "org.example.imusic")
            self.assertEqual(
                runner.run.call_args.args[0],
                ["codesign", "--verify", "--deep", "--strict", str(app)],
            )

    def test_missing_web_asset_prevents_exporting_an_incomplete_app(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = app_fixture(Path(temporary))
            next(app.rglob("upload-index-test.js")).unlink()
            with self.assertRaisesRegex(builder.BuildError, "missing or empty"):
                builder.validate_web_resources(app)

    def test_missing_web_license_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = app_fixture(Path(temporary))
            next(app.rglob("upload-licenses.txt")).unlink()
            with self.assertRaisesRegex(builder.BuildError, "notices are missing"):
                builder.validate_web_resources(app)


class MacExportTests(unittest.TestCase):
    def test_unrelated_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = app_fixture(root / "source")
            previous = app_fixture(root / "output", "org.example.unrelated")
            with self.assertRaisesRegex(builder.BuildError, "unrelated app"):
                builder.export_app(Mock(), source, previous.parent, "universal")
            info = plistlib.loads((previous / "Contents/Info.plist").read_bytes())
            self.assertEqual(info["CFBundleIdentifier"], "org.example.unrelated")

    def test_failed_copy_keeps_the_existing_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = app_fixture(root / "source")
            previous = app_fixture(root / "output")
            marker = previous / "old-release-marker"
            marker.touch()
            runner = Mock()
            runner.run.side_effect = builder.BuildError("copy failed")
            with self.assertRaisesRegex(builder.BuildError, "copy failed"):
                builder.export_app(runner, source, previous.parent, "universal")
            self.assertTrue(marker.exists())

    def test_failed_publication_restores_the_previous_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = app_fixture(root / "source")
            previous = app_fixture(root / "output")
            marker = previous / "old-release-marker"
            marker.touch()
            runner = Mock()
            runner.run.side_effect = lambda args, label: shutil.copytree(args[1], args[2])
            original_rename = Path.rename

            def fail_new_app(path, destination):
                """Simulate an export failure after moving the previous app aside."""
                if path.name == "iMusic.app" and path.parent.name.startswith(".imusic-release-"):
                    raise OSError("publication failed")
                return original_rename(path, destination)

            with (
                patch.object(builder, "validate_app"),
                patch.object(Path, "rename", fail_new_app),
            ):
                with self.assertRaisesRegex(OSError, "publication failed"):
                    builder.export_app(runner, source, previous.parent, "universal")
            self.assertTrue(marker.exists())

    def test_output_symlink_does_not_replace_its_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = app_fixture(root / "source")
            output = root / "output"
            output.mkdir()
            destination = output / "iMusic.app"
            destination.symlink_to(source, target_is_directory=True)
            with self.assertRaisesRegex(builder.BuildError, "symbolic link"):
                builder.export_app(Mock(), source, output, "universal")
            self.assertTrue(source.exists())
            self.assertTrue(destination.is_symlink())


if __name__ == "__main__":
    unittest.main()
