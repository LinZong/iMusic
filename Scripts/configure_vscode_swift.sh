#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
platform="${1:-macos}"
case "$platform" in
    macos)
        scheme="iMusicMac"
        destination="platform=macOS,arch=$(uname -m)"
        derived_data="$project_root/.build-mac"
        ;;
    ios)
        scheme="iMusic"
        destination="generic/platform=iOS Simulator"
        derived_data="$project_root/.build-ios"
        ;;
    *)
        echo "Usage: bash Scripts/configure_vscode_swift.sh [macos|ios]" >&2
        exit 1
        ;;
esac

build_server="$(command -v xcode-build-server || true)"
if [[ -z "$build_server" && -x /opt/homebrew/bin/xcode-build-server ]]; then
    build_server=/opt/homebrew/bin/xcode-build-server
elif [[ -z "$build_server" && -x /usr/local/bin/xcode-build-server ]]; then
    build_server=/usr/local/bin/xcode-build-server
fi
if [[ -z "$build_server" ]]; then
    echo "Install the Xcode language-service bridge: brew install xcode-build-server" >&2
    exit 1
fi

# Keep the package and its tests on SwiftPM. SourceKit-LSP discovers this nested
# build server for Apps/Shared, which is not part of Package.swift.
cd "$project_root/Apps"
"$build_server" config \
    -workspace "$project_root/iMusic.xcodeproj/project.xcworkspace" \
    -scheme "$scheme" --build_root "$derived_data"

# A result bundle makes xcodebuild persist the activity log used by the server.
# Each invocation needs a new path, including incremental builds.
result_directory="$(mktemp -d "${TMPDIR:-/tmp}/imusic-vscode.XXXXXX")"
cd "$project_root"
/usr/bin/xcrun xcodebuild \
    -project iMusic.xcodeproj -scheme "$scheme" -configuration Debug \
    -destination "$destination" -derivedDataPath "$derived_data" \
    -resultBundlePath "$result_directory/Build.xcresult" \
    CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=YES build

echo "App index refreshed ($scheme). If needed, run Swift: Restart Language Server in VS Code."
