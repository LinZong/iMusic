#!/usr/bin/env python3
"""Build, validate, and install a signed iOS Release app without opening Xcode."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
import plistlib
import sys
from typing import Sequence


from apple_build_support import (
    ROOT,
    BuildError as InstallError,
    CommandError,
    Runner,
    prepare_web,
    tool,
)


@dataclass(frozen=True)
class Device:
    """Identify one reachable physical iOS device and its installation transport."""

    # CoreDevice identifier accepted by devicectl; never a simulator UUID.
    identifier: str
    # Hardware UDID used to check provisioning and address ideviceinstaller.
    udid: str
    # User-assigned device name used for display and exact-name selection.
    name: str
    # Marketing name shown alongside the user-assigned name.
    model: str
    # Installed OS version used to reject incompatible deployment targets.
    os_version: str
    # True for a device observed over USB, rather than a network-only connection.
    usb: bool
    # Developer Mode status reported by CoreDevice, if known.
    developer_mode: str


def reachable_devices(payload: dict, usb_udids: set[str] | None) -> list[Device]:
    """Ignore cached unavailable devices; USB discovery also works without a DDI."""
    devices = []
    for raw in payload.get("result", {}).get("devices", []):
        hardware = raw.get("hardwareProperties", {})
        properties = raw.get("deviceProperties", {})
        connection = raw.get("connectionProperties", {})
        if hardware.get("platform") != "iOS" or hardware.get("reality") != "physical":
            continue
        udid = hardware.get("udid", "")
        usb = udid in usb_udids if usb_udids is not None else (
            connection.get("transportType") == "wired"
            and connection.get("tunnelState") in {"connected", "connecting", "disconnected"}
        )
        if not usb and connection.get("tunnelState") != "connected":
            continue
        if not udid or not raw.get("identifier"):
            continue
        devices.append(Device(
            identifier=raw["identifier"], udid=udid,
            name=properties.get("name", hardware.get("marketingName", udid)),
            model=hardware.get("marketingName", hardware.get("productType", "iOS device")),
            os_version=properties.get("osVersionNumber", ""), usb=usb,
            developer_mode=properties.get("developerModeStatus", "unknown"),
        ))
    return sorted(devices, key=lambda device: (device.name.casefold(), device.udid))


def select_device(devices: list[Device], selector: str | None) -> Device:
    """Require a unique connected target instead of guessing among multiple devices."""
    if selector:
        matches = [device for device in devices if selector.casefold() in {
            device.udid.casefold(), device.identifier.casefold(), device.name.casefold(),
        }]
    else:
        matches = devices
    if len(matches) == 1:
        return matches[0]
    if not devices:
        raise InstallError(
            "No reachable iPhone/iPad. Connect, unlock, and trust this Mac, then retry."
        )
    if not matches:
        raise InstallError(f"No connected device matches {selector!r}. Use --list-devices.")
    raise InstallError("Multiple devices match. Use --device with an exact name or UDID.")


def discover(runner: Runner) -> list[Device]:
    """Read CoreDevice's supported JSON output and optionally cross-check live USB UDIDs."""
    destination = runner.directory / "devices.json"
    runner.run([
        "xcrun", "devicectl", "list", "devices", "--timeout", "30",
        "--json-output", str(destination),
    ], "discover-devices", timeout=40)
    usb_udids = None
    usb_tool = tool("idevice_id")
    if usb_tool:
        usb_udids = set(runner.run([usb_tool, "-l"], "discover-usb", timeout=30).splitlines())
    return reachable_devices(json.loads(destination.read_text()), usb_udids)


def print_devices(devices: list[Device]) -> None:
    """List stable identifiers without writing device details into source configuration."""
    for device in devices:
        transport = "USB" if device.usb else "network"
        print(f"{device.name} | {device.model} | iOS {device.os_version} | {transport}")
        print(f"  UDID: {device.udid}")


def build_release(runner: Runner, derived_data: Path, team: str | None) -> Path:
    """Build the local iOS target with Release optimization and automatic signing."""
    prepare_web(runner)
    command = [
        "xcrun", "xcodebuild", "-project", str(ROOT / "iMusic.xcodeproj"),
        "-scheme", "iMusic", "-configuration", "Release",
        "-destination", "generic/platform=iOS", "-derivedDataPath", str(derived_data),
        "-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration",
    ]
    if team:
        command.append(f"DEVELOPMENT_TEAM={team}")
    command.append("build")
    print(f"Building signed Release app. Logs: {runner.directory}", flush=True)
    runner.run(command, "release-build")
    return derived_data / "Build/Products/Release-iphoneos/iMusic.app"


def validate_profile(profile: dict, device: Device, now: datetime) -> None:
    """Reject expired profiles and devices outside the signed installation allowlist."""
    expires = profile.get("ExpirationDate")
    if not isinstance(expires, datetime):
        raise InstallError("The provisioning profile has no expiration date. Rebuild with signing.")
    if expires.replace(tzinfo=timezone.utc) <= now:
        raise InstallError("The provisioning profile has expired. Refresh signing and rebuild.")
    registered = device.udid in profile.get("ProvisionedDevices", [])
    if not profile.get("ProvisionsAllDevices") and not registered:
        raise InstallError(
            "The signing profile does not include this device. Register its UDID with your "
            "Apple developer team, refresh the profile, then rebuild without --skip-build. "
            "For a first-time setup, sign in under Xcode Settings > Accounts."
        )


def validate_app(runner: Runner, app: Path, device: Device) -> dict:
    """Verify the signed physical-device bundle before any installation is attempted."""
    if not (app / "Info.plist").is_file() or not (app / "embedded.mobileprovision").is_file():
        raise InstallError(f"No signed Release app at {app}. Run without --skip-build first.")
    info = plistlib.loads((app / "Info.plist").read_bytes())
    if info.get("DTPlatformName") != "iphoneos":
        raise InstallError("The app is not a physical iOS device build.")
    bundle_id = info.get("CFBundleIdentifier")
    if not isinstance(bundle_id, str) or not bundle_id:
        raise InstallError("The app has no bundle identifier.")
    if device.os_version and info.get("MinimumOSVersion"):
        minimum = tuple(int(part) for part in info["MinimumOSVersion"].split("."))
        current = tuple(int(part) for part in device.os_version.split("."))
        minimum += (0,) * (3 - len(minimum))
        current += (0,) * (3 - len(current))
        if current < minimum:
            raise InstallError(f"This build requires iOS {info['MinimumOSVersion']} or later.")
    runner.run(["codesign", "--verify", "--deep", "--strict", str(app)], "verify-signature")
    profile_data = runner.run([
        "security", "cms", "-D", "-i", str(app / "embedded.mobileprovision"),
    ], "decode-profile")
    validate_profile(plistlib.loads(profile_data.encode()), device, datetime.now(timezone.utc))
    return info


def ddi_failure(output: str) -> bool:
    """Recognize developer-image errors without hiding ordinary installation failures."""
    return any(marker in output.lower() for marker in (
        "developer disk image", "12040", "0xe800010f",
    ))


def install_direct(runner: Runner, app: Path, device: Device, bundle_id: str) -> None:
    """Use the device installation service and confirm the installed bundle exists."""
    installer = tool("ideviceinstaller")
    if not installer:
        raise InstallError(
            "The direct installer is missing. Run: brew install ideviceinstaller\n"
            "Then retry with --skip-build. ideviceinstaller 1.2+ is required."
        )
    command = [installer, "-u", device.udid]
    if not device.usb:
        command.append("--network")
    runner.run(command + ["install", str(app)], "direct-install", timeout=180)
    output = runner.run(command + [
        "list", "--bundle-identifier", bundle_id, "--xml",
    ], "verify-direct-install", timeout=60)
    start = output.find("<?xml")
    if start < 0:
        raise InstallError("The installer did not return an application list for verification.")
    apps = plistlib.loads(output[start:].encode())
    if not any(item.get("CFBundleIdentifier") == bundle_id for item in apps):
        raise InstallError(
            "Installation reported success, but the app was not found on the device."
        )


def install(runner: Runner, app: Path, device: Device, bundle_id: str, backend: str) -> None:
    """Prefer Apple's installer and fall back only for a missing developer disk image."""
    if backend == "ideviceinstaller":
        install_direct(runner, app, device, bundle_id)
        return
    try:
        runner.run([
            "xcrun", "devicectl", "device", "install", "app", "--device", device.identifier,
            str(app), "--timeout", "120", "--json-output", str(runner.directory / "install.json"),
        ], "apple-install", timeout=135)
    except CommandError as error:
        if backend == "auto" and ddi_failure(error.output):
            print("Developer image unavailable; using the direct device installer...", flush=True)
            install_direct(runner, app, device, bundle_id)
            return
        raise
    destination = runner.directory / "installed-apps.json"
    runner.run([
        "xcrun", "devicectl", "device", "info", "apps", "--device", device.identifier,
        "--timeout", "30", "--json-output", str(destination),
    ], "verify-apple-install", timeout=45)
    apps = json.loads(destination.read_text()).get("result", {}).get("apps", [])
    if not any(item.get("bundleIdentifier") == bundle_id for item in apps):
        raise InstallError(
            "Installation reported success, but the app was not found on the device."
        )


def arguments(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Parse explicit targets and reusable build options without machine-specific defaults."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--list-devices", action="store_true", help="list reachable physical iOS devices"
    )
    parser.add_argument(
        "--device", help="exact device name, hardware UDID, or CoreDevice identifier"
    )
    parser.add_argument(
        "--skip-build", action="store_true", help="install the existing signed Release app"
    )
    parser.add_argument(
        "--derived-data", type=Path, default=ROOT / ".build-device",
        help="build/cache directory (default: repository .build-device)",
    )
    parser.add_argument("--team", help="override DEVELOPMENT_TEAM for this build only")
    parser.add_argument(
        "--installer", choices=("auto", "devicectl", "ideviceinstaller"), default="auto",
        help="installation backend (default: Apple, then direct on DDI errors)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    """Resolve one target, build or reuse Release, then validate and install it."""
    args = arguments(argv)
    if sys.platform != "darwin":
        raise InstallError("This script requires macOS and the full Xcode command-line toolchain.")
    if args.skip_build and args.team:
        raise InstallError("--team requires a rebuild. Omit --skip-build to change signing teams.")
    if args.team and (
        len(args.team) != 10 or not args.team.isascii() or not args.team.isalnum()
    ):
        raise InstallError("--team must be a 10-character Apple development team identifier.")
    derived_data = args.derived_data.expanduser().resolve()
    # Device identities and signing diagnostics remain under ignored build output.
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    runner = Runner(derived_data / "install-logs" / timestamp)
    devices = discover(runner)
    print_devices(devices)
    if args.list_devices:
        return 0
    device = select_device(devices, args.device)
    if device.developer_mode == "disabled":
        raise InstallError(
            "Enable Developer Mode in the device's Privacy & Security settings first."
        )
    print(f"Target: {device.name} ({device.udid})", flush=True)
    app = derived_data / "Build/Products/Release-iphoneos/iMusic.app"
    if not args.skip_build:
        app = build_release(runner, derived_data, args.team)
    info = validate_app(runner, app, device)
    print("Installing signed Release app...", flush=True)
    install(runner, app, device, info["CFBundleIdentifier"], args.installer)
    print(
        f"Installed iMusic {info.get('CFBundleShortVersionString', '?')} "
        f"(build {info.get('CFBundleVersion', '?')}) on {device.name}.\n"
        f"Open iMusic on the device to use it without a debugger.\nLogs: {runner.directory}"
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (InstallError, OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nCancelled.", file=sys.stderr)
        sys.exit(130)
