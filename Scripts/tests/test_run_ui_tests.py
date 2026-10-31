"""Prevent a successful tool exit from being mistaken for an executed UI regression suite."""

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from apple_build_support import BuildError
from run_ui_tests import arguments, build_command, verified_pass_count


class UIResultTests(unittest.TestCase):
    """Require evidence of executed passing tests in the Xcode result summary."""

    def test_passed_suite_reports_executed_count(self):
        self.assertEqual(verified_pass_count({
            "result": "Passed", "passedTests": 5, "failedTests": 0,
        }), 5)

    def test_empty_or_skipped_only_selection_is_not_success(self):
        for summary in ({}, {"result": "Passed", "passedTests": 0}, {
            "result": "Skipped", "passedTests": 0, "skippedTests": 5,
        }):
            with self.subTest(summary=summary), self.assertRaises(BuildError):
                verified_pass_count(summary)

    def test_partial_pass_cannot_hide_failures(self):
        with self.assertRaises(BuildError):
            verified_pass_count({"result": "Failed", "passedTests": 4, "failedTests": 1})


class UIDestinationTests(unittest.TestCase):
    """Keep native Mac, simulator, and physical-device builds in their intended targets."""

    def test_macos_uses_native_scheme_and_local_signing(self):
        options = arguments(["--macos", "--only-testing", "PlaylistUITests"])
        command = build_command(options, Path("result.xcresult"))
        self.assertIn("iMusicMac UI Tests", command)
        self.assertIn("platform=macOS", command)
        self.assertIn("CODE_SIGN_IDENTITY=-", command)
        self.assertIn("-only-testing:iMusicMacUITests/PlaylistUITests", command)
        self.assertNotIn("-allowProvisioningDeviceRegistration", command)

    def test_simulator_keeps_unsigned_ios_target(self):
        command = build_command(arguments(["--simulator", "SIM-UUID"]), Path("result"))
        self.assertIn("iMusic UI Tests", command)
        self.assertIn("platform=iOS Simulator,id=SIM-UUID", command)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", command)

    def test_device_keeps_team_and_registration_support(self):
        options = arguments(["--device", "DEVICE-UDID", "--team", "TEAM-ID", "--skip-build"])
        command = build_command(options, Path("result"))
        self.assertIn("platform=iOS,id=DEVICE-UDID", command)
        self.assertIn("DEVELOPMENT_TEAM=TEAM-ID", command)
        self.assertIn("-allowProvisioningDeviceRegistration", command)
        self.assertEqual(command[-1], "test-without-building")


if __name__ == "__main__":
    unittest.main()
