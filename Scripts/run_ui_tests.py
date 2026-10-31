#!/usr/bin/env python3
"""Run isolated, silent XCUITests on an explicitly selected simulator or iOS device."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import subprocess
from pathlib import Path
import sys
from uuid import uuid4

from apple_build_support import ROOT, BuildError, CommandError, Runner, prepare_web


def verified_pass_count(summary: dict) -> int:
    """Reject empty, skipped-only, or failed runs even when xcodebuild exits successfully."""
    passed = summary.get("passedTests", 0)
    if summary.get("result") != "Passed" or summary.get("failedTests", 0) or passed < 1:
        raise BuildError("No passing UI run was verified. Inspect Tests.xcresult and the saved logs.")
    return passed


def execute_tests(command: list[str], directory: Path) -> None:
    """Write test output as it arrives so a running or interrupted suite remains diagnosable."""
    log = directory / "ui-tests.log"
    print(f"Live test log: {log}", flush=True)
    try:
        with log.open("w") as output:
            result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    except OSError as error:
        raise BuildError(f"Cannot execute UI tests: {error}") from error
    if result.returncode:
        raise CommandError(command, log.read_text(errors="replace"), log)


def main() -> int:
    """Build the test host, execute UI scenarios, and retain logs and xcresult attachments."""
    parser = argparse.ArgumentParser(description=__doc__)
    destination = parser.add_mutually_exclusive_group(required=True)
    destination.add_argument("--simulator", metavar="UUID", help="Simulator UUID from simctl list devices")
    destination.add_argument("--device", metavar="UDID", help="Paired physical iPhone/iPad UDID")
    parser.add_argument("--team", help="Override the Apple development team for device signing")
    parser.add_argument(
        "--derived-data", type=Path, default=ROOT / ".build-ui-tests/DerivedData",
        help="Reusable build cache directory",
    )
    parser.add_argument(
        "--only-testing", action="append", default=[], metavar="CLASS[/METHOD]",
        help="Run selected iMusicUITests scenarios; may be repeated",
    )
    parser.add_argument(
        "--skip-build", action="store_true",
        help="Use compatible build-for-testing artifacts already in DerivedData",
    )
    options = parser.parse_args()
    run_name = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid4().hex[:8]
    directory = ROOT / ".build-ui-tests/Results" / run_name
    runner = Runner(directory)
    result = directory / "Tests.xcresult"
    platform = "iOS Simulator" if options.simulator else "iOS"
    identifier = options.simulator or options.device
    command = [
        "xcrun", "xcodebuild", "-project", str(ROOT / "iMusic.xcodeproj"),
        "-scheme", "iMusic UI Tests", "-configuration", "Debug",
        "-destination", f"platform={platform},id={identifier}",
        "-destination-timeout", "60", "-derivedDataPath", str(options.derived_data.resolve()),
        "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
        "-maximum-concurrent-test-simulator-destinations", "1",
    ]
    for selection in options.only_testing:
        command.append(f"-only-testing:iMusicUITests/{selection}")
    if options.simulator:
        command.append("CODE_SIGNING_ALLOWED=NO")
    else:
        command.extend(["-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration"])
        if options.team:
            command.append(f"DEVELOPMENT_TEAM={options.team}")
    command.append("test-without-building" if options.skip_build else "test")
    print(f"Target: {platform} {identifier}", flush=True)
    print(f"Logs and screenshots: {directory}", flush=True)
    print("Uses the separate iMusic UI Tests app and silent playback backend.", flush=True)
    try:
        if not options.skip_build:
            prepare_web(runner)
        execute_tests(command, directory)
        summary = json.loads(runner.run([
            "xcrun", "xcresulttool", "get", "test-results", "summary",
            "--path", str(result), "--format", "json",
        ], "test-summary", timeout=30))
        (directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        passed = verified_pass_count(summary)
    except (BuildError, ValueError) as error:
        print(str(error), file=sys.stderr)
        print(f"Test results, if produced: {result}", file=sys.stderr)
        return 1
    print(f"UI tests passed ({passed}). Open results with: open '{result}'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
