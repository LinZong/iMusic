"""Regression checks for device targeting, signing gates, and DDI fallback."""

from datetime import datetime, timezone
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import install_ios_release as installer


def device(udid="DEVICE-A", name="Studio iPhone", usb=True):
    """Create a synthetic device without publishing a real hardware identifier."""
    return installer.Device(
        identifier=f"CORE-{udid}", udid=udid, name=name, model="iPhone",
        os_version="27.0.1", usb=usb, developer_mode="enabled",
    )


def record(udid="DEVICE-A", state="connected", reality="physical"):
    """Model the supported CoreDevice JSON fields used by discovery."""
    return {
        "identifier": f"CORE-{udid}",
        "hardwareProperties": {
            "udid": udid, "platform": "iOS", "reality": reality,
            "marketingName": "iPhone",
        },
        "deviceProperties": {"name": "Studio iPhone", "osVersionNumber": "27.0.1"},
        "connectionProperties": {"transportType": "wired", "tunnelState": state},
    }


class DeviceSelectionTests(unittest.TestCase):
    def test_remembered_unavailable_devices_and_simulators_are_not_targets(self):
        payload = {"result": {"devices": [
            record(), record("OLD-PHONE", "unavailable"),
            record("SIMULATOR", reality="simulated"),
        ]}}
        devices = installer.reachable_devices(payload, {"DEVICE-A"})
        self.assertEqual([item.udid for item in devices], ["DEVICE-A"])

    def test_live_usb_device_does_not_require_a_developer_image_or_tunnel(self):
        payload = {"result": {"devices": [record(state="disconnected")]}}
        devices = installer.reachable_devices(payload, {"DEVICE-A"})
        self.assertEqual(installer.select_device(devices, None).udid, "DEVICE-A")

    def test_multiple_connected_devices_require_an_explicit_target(self):
        with self.assertRaisesRegex(installer.InstallError, "Multiple devices"):
            installer.select_device([device(), device("DEVICE-B", "Travel iPad")], None)

    def test_exact_name_and_both_identifiers_select_the_same_device(self):
        devices = [device(), device("DEVICE-B", "Travel iPad")]
        for selector in ("Travel iPad", "DEVICE-B", "CORE-DEVICE-B"):
            with self.subTest(selector=selector):
                self.assertEqual(installer.select_device(devices, selector).udid, "DEVICE-B")

    def test_duplicate_names_cannot_silently_select_the_first_device(self):
        with self.assertRaisesRegex(installer.InstallError, "Multiple devices"):
            installer.select_device([device(), device("DEVICE-B")], "Studio iPhone")


class SigningTests(unittest.TestCase):
    def test_profile_must_include_the_selected_device(self):
        profile = {"ExpirationDate": datetime(2099, 1, 1), "ProvisionedDevices": ["DEVICE-B"]}
        with self.assertRaisesRegex(installer.InstallError, "does not include this device"):
            installer.validate_profile(profile, device(), datetime.now(timezone.utc))

    def test_expired_profile_is_rejected_even_for_a_registered_device(self):
        profile = {"ExpirationDate": datetime(2000, 1, 1), "ProvisionedDevices": ["DEVICE-A"]}
        with self.assertRaisesRegex(installer.InstallError, "expired"):
            installer.validate_profile(profile, device(), datetime.now(timezone.utc))

    def test_valid_registered_device_passes_signing_gate(self):
        profile = {"ExpirationDate": datetime(2099, 1, 1), "ProvisionedDevices": ["DEVICE-A"]}
        installer.validate_profile(profile, device(), datetime.now(timezone.utc))

    def test_simulator_bundle_is_rejected_before_external_installation(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "iMusic.app"
            app.mkdir()
            (app / "Info.plist").write_bytes(plistlib.dumps({"DTPlatformName": "iphonesimulator"}))
            (app / "embedded.mobileprovision").write_text("synthetic test profile")
            runner = Mock()
            with self.assertRaisesRegex(installer.InstallError, "physical iOS device"):
                installer.validate_app(runner, app, device())
            runner.run.assert_not_called()


class InstallBackendTests(unittest.TestCase):
    def test_ddi_failure_uses_the_same_app_and_selected_device_for_fallback(self):
        runner = Mock()
        runner.directory = Path("/tmp/synthetic-install-log")
        runner.run.side_effect = installer.CommandError(
            ["xcrun"], "CoreDeviceError 12040: developer disk image missing", Path("error.log"),
        )
        target = device()
        app = Path("/tmp/Build With Spaces/iMusic.app")
        with patch.object(installer, "install_direct") as direct:
            installer.install(runner, app, target, "org.example.imusic", "auto")
        direct.assert_called_once_with(runner, app, target, "org.example.imusic")

    def test_signing_failure_does_not_trigger_a_retry_through_another_backend(self):
        runner = Mock()
        runner.directory = Path("/tmp/synthetic-install-log")
        runner.run.side_effect = installer.CommandError(
            ["xcrun"], "The application has an invalid signature", Path("error.log"),
        )
        with patch.object(installer, "install_direct") as direct:
            with self.assertRaises(installer.CommandError):
                installer.install(
                    runner, Path("iMusic.app"), device(), "org.example.imusic", "auto"
                )
        direct.assert_not_called()

    def test_explicit_apple_backend_preserves_ddi_error(self):
        runner = Mock()
        runner.directory = Path("/tmp/synthetic-install-log")
        runner.run.side_effect = installer.CommandError(["xcrun"], "12040", Path("error.log"))
        with patch.object(installer, "install_direct") as direct:
            with self.assertRaises(installer.CommandError):
                installer.install(
                    runner, Path("iMusic.app"), device(), "org.example.imusic", "devicectl"
                )
        direct.assert_not_called()

    def test_direct_install_requires_the_bundle_to_appear_on_the_selected_device(self):
        runner = Mock()
        runner.run.side_effect = ["Complete", plistlib.dumps([
            {"CFBundleIdentifier": "org.example.other"},
        ]).decode()]
        with patch.object(installer, "tool", return_value="ideviceinstaller"):
            with self.assertRaisesRegex(installer.InstallError, "not found on the device"):
                installer.install_direct(runner, Path("iMusic.app"), device(), "org.example.imusic")
        for call in runner.run.call_args_list:
            self.assertEqual(call.args[0][1:3], ["-u", "DEVICE-A"])


class WorkflowTests(unittest.TestCase):
    def test_team_override_cannot_be_silently_ignored_when_reusing_a_build(self):
        with patch.object(installer.sys, "platform", "darwin"):
            with self.assertRaisesRegex(installer.InstallError, "requires a rebuild"):
                installer.main(["--skip-build", "--team", "ABCDE12345"])

    def test_release_build_uses_physical_sdk_and_automatic_signing(self):
        runner = Mock()
        with patch.object(installer, "prepare_web"):
            installer.build_release(runner, Path("/tmp/Build With Spaces"), "ABCDE12345")
        command = runner.run.call_args.args[0]
        self.assertEqual(command[command.index("-configuration") + 1], "Release")
        self.assertEqual(command[command.index("-destination") + 1], "generic/platform=iOS")
        self.assertIn("-allowProvisioningUpdates", command)
        self.assertIn("DEVELOPMENT_TEAM=ABCDE12345", command)

    def test_skip_build_still_validates_signing_before_install(self):
        with tempfile.TemporaryDirectory() as directory:
            with (
                patch.object(installer.sys, "platform", "darwin"),
                patch.object(installer, "discover", return_value=[device()]),
                patch.object(installer, "build_release") as build,
                patch.object(
                    installer, "validate_app", side_effect=installer.InstallError("bad profile")
                ),
                patch.object(installer, "install") as install,
            ):
                with self.assertRaisesRegex(installer.InstallError, "bad profile"):
                    installer.main(["--skip-build", "--derived-data", directory])
            build.assert_not_called()
            install.assert_not_called()


if __name__ == "__main__":
    unittest.main()
