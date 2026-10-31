"""Prevent a successful tool exit from being mistaken for an executed UI regression suite."""

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from apple_build_support import BuildError
from run_ui_tests import verified_pass_count


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


if __name__ == "__main__":
    unittest.main()
