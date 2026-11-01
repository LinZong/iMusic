"""Verify Release CPU coverage, bundled resources, and safe macOS app export."""

import json
from pathlib import Path
import plistlib
import shutil
import subprocess
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
        with tempfile.TemporaryDirectory() as temporary:
            runner.directory = Path(temporary)
            with patch.object(builder, "prepare_web"):
                builder.build_release(runner, Path("/tmp/Build With Spaces"), "universal")
            entitlements = plistlib.loads(
                (runner.directory / "macOS-local.entitlements").read_bytes()
            )
            self.assertTrue(entitlements[builder.LOCAL_LIBRARY_EXCEPTION])
            self.assertIn(f"CODE_SIGN_ENTITLEMENTS={runner.directory}/macOS-local.entitlements",
                          runner.run.call_args.args[0])
        command = runner.run.call_args.args[0]
        self.assertEqual(command[command.index("-configuration") + 1], "Release")
        self.assertEqual(command[command.index("-scheme") + 1], "iMusicMac")
        self.assertIn("ARCHS=arm64 x86_64", command)
        self.assertIn("ONLY_ACTIVE_ARCH=NO", command)
        self.assertIn("CODE_SIGN_IDENTITY=-", command)
        self.assertIn("DEVELOPMENT_TEAM=", command)
        self.assertIn("ENABLE_HARDENED_RUNTIME=YES", command)

    def test_local_exception_preserves_sandbox_without_changing_shared_entitlements(self):
        base = builder.ROOT / "Config/macOS.entitlements"
        original = base.read_bytes()
        with tempfile.TemporaryDirectory() as temporary:
            path = builder.local_entitlements(Path(temporary))
            local = plistlib.loads(path.read_bytes())
        self.assertTrue(local[builder.LOCAL_LIBRARY_EXCEPTION])
        for key, value in plistlib.loads(original).items():
            self.assertEqual(local[key], value)
        self.assertEqual(base.read_bytes(), original)

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
            entitlements = plistlib.dumps({
                builder.LOCAL_LIBRARY_EXCEPTION: True,
                "com.apple.security.app-sandbox": True,
            }).decode()
            runner.run.side_effect = ["arm64 x86_64\n", "", "Executable=iMusic\n" + entitlements]
            info = builder.validate_app(runner, app, "universal")
            self.assertEqual(info["CFBundleIdentifier"], "org.example.imusic")
            runner.run.assert_any_call(
                ["codesign", "--verify", "--deep", "--strict", str(app)],
                "verify-mac-signature",
            )

    def test_valid_signature_without_local_loading_exception_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = app_fixture(Path(temporary))
            runner = Mock()
            # This is the original failing configuration: a valid signature and sandbox,
            # but no exception for team-less ad-hoc audio frameworks.
            signed = plistlib.dumps({"com.apple.security.app-sandbox": True}).decode()
            runner.run.side_effect = ["arm64 x86_64\n", "", signed]
            with self.assertRaisesRegex(builder.BuildError, "may abort at launch"):
                builder.validate_app(runner, app, "universal")

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


class MacReleaseWorkflowTests(unittest.TestCase):
    def test_release_exports_only_after_build_and_validation(self):
        for failure in (None, "build", "validation", "export"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                runner = Mock()
                runner.directory = Path(temporary)
                events = []

                def complete(stage, value):
                    """Record workflow order and stop at the selected failing stage."""
                    events.append(stage)
                    if failure == stage:
                        raise builder.BuildError(f"{stage} failed")
                    return value

                with (
                    patch.object(builder.sys, "platform", "darwin"),
                    patch.object(builder, "Runner", return_value=runner),
                    patch.object(builder, "build_release", side_effect=lambda *args:
                                 complete("build", Path(temporary) / "iMusic.app")),
                    patch.object(builder, "validate_app", side_effect=lambda *args:
                                 complete("validation", {})),
                    patch.object(builder, "export_app", side_effect=lambda *args:
                                 complete("export", Path(temporary) / "export/iMusic.app")),
                    patch("builtins.print") as output,
                ):
                    if failure:
                        with self.assertRaisesRegex(builder.BuildError, f"{failure} failed"):
                            builder.main([])
                        stages = ["build", "validation", "export"]
                        self.assertEqual(events, stages[:stages.index(failure) + 1])
                        output.assert_not_called()
                    else:
                        self.assertEqual(builder.main([]), 0)
                        self.assertEqual(events, ["build", "validation", "export"])
                        output.assert_called_once()
                        self.assertIn(
                            f"App: {Path(temporary) / 'export/iMusic.app'}",
                            output.call_args.args[0],
                        )
                    runner.run.assert_not_called()


@unittest.skipUnless(sys.platform == "darwin", "Requires Apple's native signing and loader tools")
class NativeLibraryLoadingTests(unittest.TestCase):
    def test_hardened_ad_hoc_host_can_load_ad_hoc_library(self):
        """Exercise dyld's real team policy without starting a UI or audio engine."""
        with tempfile.TemporaryDirectory(prefix="imusic loader ") as temporary:
            root = Path(temporary)
            generated = plistlib.loads(builder.local_entitlements(root / "logs").read_bytes())
            # The probe isolates the loader policy; sandbox preservation is checked above.
            policy = root / "loader.entitlements"
            policy.write_bytes(plistlib.dumps({
                builder.LOCAL_LIBRARY_EXCEPTION: generated[builder.LOCAL_LIBRARY_EXCEPTION],
            }))
            library = root / "libfixture.dylib"
            host = root / "host"
            (root / "codec.c").write_text("int codec_fixture(void) { return 42; }\n")
            (root / "main.c").write_text(
                "extern int codec_fixture(void);\n"
                "int main(void) { return codec_fixture() == 42 ? 0 : 1; }\n"
            )
            commands = [
                ["xcrun", "clang", "-dynamiclib", str(root / "codec.c"),
                 "-Wl,-install_name,@rpath/libfixture.dylib", "-o", str(library)],
                ["xcrun", "clang", str(root / "main.c"), f"-L{root}", "-lfixture",
                 "-Wl,-rpath,@executable_path", "-o", str(host)],
                ["codesign", "--force", "--sign", "-", "--options", "runtime", str(library)],
                ["codesign", "--force", "--sign", "-", "--options", "runtime",
                 "--entitlements", str(policy), str(host)],
                [str(host)],
            ]
            for command in commands:
                result = subprocess.run(command, capture_output=True, text=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
