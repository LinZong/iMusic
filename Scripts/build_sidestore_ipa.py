#!/usr/bin/env python3
"""Build and export an unsigned iOS Release IPA for SideStore re-signing."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import sys
import tempfile
from typing import Sequence
import zipfile

from apple_build_support import (
    ROOT,
    BuildError,
    CommandError,
    Runner,
    prepare_web,
)


def build_release(runner: Runner, derived_data: Path) -> Path:
    """Build the physical-device Release target without signing or provisioning."""
    prepare_web(runner)
    print(f"Building unsigned iOS Release app. Logs: {runner.directory}", flush=True)
    runner.run([
        "xcrun", "xcodebuild", "-project", str(ROOT / "iMusic.xcodeproj"),
        "-scheme", "iMusic", "-configuration", "Release",
        "-destination", "generic/platform=iOS", "-derivedDataPath", str(derived_data),
        "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=",
        "DEVELOPMENT_TEAM=", "PROVISIONING_PROFILE_SPECIFIER=", "PROVISIONING_PROFILE=",
        "build",
    ], "sidestore-release-build")
    return derived_data / "Build/Products/Release-iphoneos/iMusic.app"


def validate_web_resources(app: Path) -> None:
    """Reject an app whose bundled Wi-Fi Upload client is missing or incomplete."""
    manifests = list(app.rglob("upload-assets.json"))
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


def signing_artifacts(app: Path) -> list[Path]:
    """Find resource signatures and provisioning profiles that cannot enter the IPA."""
    artifacts = []
    for path in app.rglob("*"):
        if path.name == "_CodeSignature" or path.name in {
            "embedded.mobileprovision", "embedded.provisionprofile",
        }:
            artifacts.append(path)
    return sorted(artifacts)


def validate_app(runner: Runner, app: Path) -> dict:
    """Verify the device bundle, arm64 executable, resources, and unsigned state."""
    info_path = app / "Info.plist"
    if not info_path.is_file():
        raise BuildError(f"No unsigned iOS Release app was produced at {app}.")
    info = plistlib.loads(info_path.read_bytes())
    if info.get("DTPlatformName") != "iphoneos" or info.get("CFBundlePackageType") != "APPL":
        raise BuildError("The product is not a physical-device iOS application bundle.")
    bundle_id = info.get("CFBundleIdentifier")
    if not isinstance(bundle_id, str) or not bundle_id:
        raise BuildError("The iOS app has no bundle identifier.")
    executable = info.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable:
        raise BuildError("The iOS app has an invalid executable name.")
    binary = app / executable
    if not binary.is_file() or not os.access(binary, os.X_OK):
        raise BuildError("The iOS app executable is missing or is not executable.")
    architectures = set(
        runner.run(["xcrun", "lipo", "-archs", str(binary)], "verify-ios-cpu-slices").split()
    )
    if "arm64" not in architectures:
        raise BuildError(f"The SideStore build has no arm64 slice: {sorted(architectures)}.")
    artifacts = signing_artifacts(app)
    if artifacts:
        relative = artifacts[0].relative_to(app)
        raise BuildError(f"The SideStore app contains a signing artifact: {relative}")
    try:
        runner.run(["codesign", "--verify", "--strict", str(app)], "verify-app-is-unsigned")
    except CommandError as error:
        if "code object is not signed at all" not in error.output.lower():
            raise BuildError(
                f"Unable to confirm that the SideStore app is unsigned. Log: {error.log}"
            ) from error
    else:
        raise BuildError("The SideStore app still has a code signature.")
    validate_web_resources(app)
    return info


def validate_ipa(ipa: Path, expected_info: dict) -> None:
    """Verify the ZIP layout, metadata, permissions, and absence of signing files."""
    if not ipa.is_file() or not zipfile.is_zipfile(ipa):
        raise BuildError(f"The exported SideStore IPA is not a valid ZIP archive: {ipa}")
    with zipfile.ZipFile(ipa) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        if not entries or len(names) != len(set(names)):
            raise BuildError("The SideStore IPA is empty or contains duplicate entries.")
        for name in names:
            path = PurePosixPath(name)
            if not path.parts or path.is_absolute() or ".." in path.parts:
                raise BuildError(f"The SideStore IPA contains an unsafe path: {name}")
            if path.parts[0] != "Payload":
                raise BuildError(f"The SideStore IPA contains a file outside Payload: {name}")
            if len(path.parts) > 1 and path.parts[1] != "iMusic.app":
                raise BuildError(f"The SideStore IPA contains an unexpected payload item: {name}")
            if "_CodeSignature" in path.parts or path.name in {
                "embedded.mobileprovision", "embedded.provisionprofile",
            }:
                raise BuildError(f"The SideStore IPA contains a signing artifact: {name}")
        info_name = "Payload/iMusic.app/Info.plist"
        if info_name not in names:
            raise BuildError("The SideStore IPA does not contain Payload/iMusic.app/Info.plist.")
        archived_info = plistlib.loads(archive.read(info_name))
        if archived_info.get("CFBundleIdentifier") != expected_info.get("CFBundleIdentifier"):
            raise BuildError("The SideStore IPA bundle identifier changed during packaging.")
        executable = archived_info.get("CFBundleExecutable", "")
        executable_name = f"Payload/iMusic.app/{executable}"
        if executable_name not in names:
            raise BuildError("The SideStore IPA does not contain its declared executable.")
        executable_mode = archive.getinfo(executable_name).external_attr >> 16
        if not executable_mode & 0o111:
            raise BuildError("The SideStore IPA executable lost its executable permission.")
        damaged = archive.testzip()
        if damaged:
            raise BuildError(f"The SideStore IPA has a corrupt archive member: {damaged}")


def export_ipa(runner: Runner, app: Path, output: Path, info: dict) -> Path:
    """Stage and atomically publish a standard Payload-based unsigned IPA."""
    if output.suffix.lower() != ".ipa":
        raise BuildError("--output must name a file with the .ipa extension.")
    if output.is_symlink():
        raise BuildError(f"Refusing to replace a symbolic link: {output}")
    if output.exists() and not output.is_file():
        raise BuildError(f"The SideStore output path is not a regular file: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".imusic-sidestore-", dir=output.parent) as temporary:
        staging = Path(temporary)
        payload = staging / "Payload"
        payload.mkdir()
        staged_app = payload / "iMusic.app"
        # ditto preserves executable permissions and any bundle symlinks.
        runner.run(["ditto", str(app), str(staged_app)], "copy-sidestore-app")
        validate_app(runner, staged_app)
        staged_ipa = staging / "iMusic-unsigned.ipa"
        runner.run([
            "ditto", "-c", "-k", "--norsrc", "--keepParent",
            str(payload), str(staged_ipa),
        ], "package-sidestore-ipa")
        validate_ipa(staged_ipa, info)
        staged_ipa.replace(output)
    return output


def arguments(argv: Sequence[str] | None = None) -> argparse.Namespace:
    """Expose independent cache and IPA paths without accepting signing credentials."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--skip-build", action="store_true",
        help="package the existing unsigned Release app without rebuilding",
    )
    parser.add_argument(
        "--derived-data", type=Path, default=ROOT / ".build-sidestore",
        help="build/cache directory (default: repository .build-sidestore)",
    )
    parser.add_argument(
        "--output", type=Path, default=ROOT / "build/SideStore/iMusic-unsigned.ipa",
        help="IPA path (default: repository build/SideStore/iMusic-unsigned.ipa)",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    """Compile or reuse an unsigned app, validate it, and export the SideStore IPA."""
    args = arguments(argv)
    if sys.platform != "darwin":
        raise BuildError("This script requires macOS and the full Xcode command-line toolchain.")
    derived_data = args.derived_data.expanduser().resolve()
    # Keep the final path unresolved so export_ipa can reject a caller-supplied symlink.
    output = args.output.expanduser().absolute()
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    runner = Runner(derived_data / "sidestore-logs" / timestamp)
    app = derived_data / "Build/Products/Release-iphoneos/iMusic.app"
    if not args.skip_build:
        app = build_release(runner, derived_data)
    info = validate_app(runner, app)
    destination = export_ipa(runner, app, output, info)
    print(
        f"Built iMusic {info.get('CFBundleShortVersionString', '?')} "
        f"(build {info.get('CFBundleVersion', '?')}) for SideStore.\n"
        f"Unsigned IPA: {destination}\nLogs: {runner.directory}\n"
        "This IPA must be re-signed by SideStore before it can run on a device."
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (BuildError, OSError, ValueError, zipfile.BadZipFile,
            plistlib.InvalidFileException) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nCancelled.", file=sys.stderr)
        sys.exit(130)
