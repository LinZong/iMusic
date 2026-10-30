#!/usr/bin/env python3
"""Build and export a locally signed macOS Release app without opening Xcode."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
from pathlib import Path
import plistlib
import sys
import tempfile
from typing import Sequence

from apple_build_support import ROOT, BuildError, Runner, prepare_web


# The universal default matches both supported Mac CPU families.
ARCHITECTURES = {
    "universal": {"arm64", "x86_64"},
    "arm64": {"arm64"},
    "x86_64": {"x86_64"},
}


def build_release(runner: Runner, derived_data: Path, architecture: str) -> Path:
    """Build the local Mac target with Release optimization and account-free ad-hoc signing."""
    prepare_web(runner)
    architectures = " ".join(sorted(ARCHITECTURES[architecture]))
    print(f"Building macOS Release ({architecture}). Logs: {runner.directory}", flush=True)
    runner.run([
        "xcrun", "xcodebuild", "-project", str(ROOT / "iMusic.xcodeproj"),
        "-scheme", "iMusicMac", "-configuration", "Release",
        "-destination", "generic/platform=macOS", "-derivedDataPath", str(derived_data),
        f"ARCHS={architectures}", "ONLY_ACTIVE_ARCH=NO", "CODE_SIGN_STYLE=Manual",
        "CODE_SIGN_IDENTITY=-", "DEVELOPMENT_TEAM=", "PROVISIONING_PROFILE_SPECIFIER=",
        "PROVISIONING_PROFILE=", "CODE_SIGNING_ALLOWED=YES", "build",
    ], "macos-release-build")
    return derived_data / "Build/Products/Release/iMusic.app"


def validate_web_resources(app: Path) -> None:
    """Reject incomplete app bundles before exporting a player with a broken upload page."""
    manifests = list((app / "Contents/Resources").rglob("upload-assets.json"))
    if len(manifests) != 1:
        raise BuildError("The app must contain exactly one bundled Wi-Fi Upload asset manifest.")
    manifest = manifests[0]
    files = json.loads(manifest.read_text()).get("files", [])
    if not isinstance(files, list) or "upload-index.html" not in files:
        raise BuildError("The bundled Wi-Fi Upload index is missing from the asset manifest.")
    for name in files:
        if (
            not isinstance(name, str) or Path(name).name != name
            or not name.startswith("upload-")
        ):
            raise BuildError("The bundled Wi-Fi Upload manifest contains an invalid filename.")
        asset = manifest.parent / name
        if not asset.is_file() or asset.stat().st_size == 0:
            raise BuildError(f"A bundled Wi-Fi Upload asset is missing or empty: {name}")
    licenses = manifest.parent / "upload-licenses.txt"
    if not licenses.is_file() or licenses.stat().st_size == 0:
        raise BuildError("The bundled Wi-Fi Upload dependency notices are missing.")


def validate_app(runner: Runner, app: Path, architecture: str) -> dict:
    """Verify the Mac bundle, requested CPU slices, web assets, and recursive code signature."""
    info_path = app / "Contents/Info.plist"
    if not info_path.is_file():
        raise BuildError(f"No macOS application was produced at {app}.")
    info = plistlib.loads(info_path.read_bytes())
    if info.get("DTPlatformName") != "macosx" or info.get("CFBundlePackageType") != "APPL":
        raise BuildError("The product is not a macOS application bundle.")
    if not info.get("CFBundleIdentifier"):
        raise BuildError("The macOS app has no bundle identifier.")
    executable = info.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable:
        raise BuildError("The macOS app has an invalid executable name.")
    binary = app / "Contents/MacOS" / executable
    actual = set(runner.run(["xcrun", "lipo", "-archs", str(binary)], "verify-cpu-slices").split())
    if actual != ARCHITECTURES[architecture]:
        raise BuildError(
            f"Incorrect app architectures: {sorted(actual)}; expected "
            f"{sorted(ARCHITECTURES[architecture])}."
        )
    validate_web_resources(app)
    runner.run(["codesign", "--verify", "--deep", "--strict", str(app)], "verify-mac-signature")
    return info


def export_app(runner: Runner, app: Path, output: Path, architecture: str) -> Path:
    """Stage and verify a complete copy, retaining the previous app if publication fails."""
    destination = output / "iMusic.app"
    if destination.is_symlink():
        raise BuildError(f"Refusing to replace a symbolic link: {destination}")
    if destination.resolve() == app.resolve():
        return destination
    if destination.exists():
        info_path = destination / "Contents/Info.plist"
        source_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        if not info_path.is_file() or (
            plistlib.loads(info_path.read_bytes()).get("CFBundleIdentifier")
            != source_info.get("CFBundleIdentifier")
        ):
            raise BuildError(
                f"The output path contains an unrelated app or directory: {destination}"
            )
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".imusic-release-", dir=output) as temporary:
        staging = Path(temporary)
        staged_app = staging / "iMusic.app"
        # ditto preserves framework symlinks, permissions, and bundle metadata.
        runner.run(["ditto", str(app), str(staged_app)], "copy-release-app")
        validate_app(runner, staged_app, architecture)
        backup = staging / "previous.app"
        if destination.exists():
            destination.rename(backup)
        try:
            staged_app.rename(destination)
        except OSError:
            if backup.exists():
                backup.rename(destination)
            raise
    return destination


def arguments(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Expose CPU selection and independent cache/output directories without signing secrets."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--arch", choices=tuple(ARCHITECTURES), default="universal",
        help="CPU architecture (default: universal, Apple Silicon and Intel)",
    )
    parser.add_argument(
        "--derived-data", type=Path, default=ROOT / ".build-mac",
        help="build/cache directory (default: repository .build-mac)",
    )
    parser.add_argument(
        "--output-dir", type=Path, default=ROOT / "build/Release-macOS",
        help="export directory (default: repository build/Release-macOS)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    """Compile and verify a Mac Release app, then export it without launching playback."""
    args = arguments(argv)
    if sys.platform != "darwin":
        raise BuildError("This script requires macOS and the full Xcode command-line toolchain.")
    derived_data = args.derived_data.expanduser().resolve()
    output = args.output_dir.expanduser().resolve()
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    runner = Runner(derived_data / "release-logs" / timestamp)
    app = build_release(runner, derived_data, args.arch)
    info = validate_app(runner, app, args.arch)
    destination = export_app(runner, app, output, args.arch)
    print(
        f"Built iMusic {info.get('CFBundleShortVersionString', '?')} "
        f"(build {info.get('CFBundleVersion', '?')}) for macOS: {args.arch}.\n"
        f"App: {destination}\nLogs: {runner.directory}\n"
        "The app is ad-hoc signed for local use; it has not been notarized."
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (BuildError, OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nCancelled.", file=sys.stderr)
        sys.exit(130)
