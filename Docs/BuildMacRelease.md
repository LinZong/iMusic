# Build a macOS Release app from the terminal

`Scripts/build_macos_release.py` compiles and exports iMusic without opening the
Xcode application. It builds the local `iMusicMac` target with the `Release`
configuration and includes the React Wi-Fi Upload assets through the existing
SwiftPM build plugin.

## Requirements

- macOS with the full Xcode command-line toolchain selected by `xcode-select`.
- Python 3.10+ and Node.js 22.12+ with npm.
- Network access for the first Swift package resolution and locked npm installation.

The script uses ad-hoc signing for local use. It clears development-team and
provisioning overrides for this invocation, so no developer account or signing
certificate is required. Your local signing file and the shared Xcode project
remain unchanged. Developer ID signing, notarization, and public distribution are
separate release steps.

The script preserves App Sandbox and Hardened Runtime. Because ad-hoc signatures
have no Team ID, each invocation generates an ignored local entitlements file
with `com.apple.security.cs.disable-library-validation` enabled for the bundled
audio frameworks. It verifies that exception in the signed app before exporting.
The shared `Config/macOS.entitlements` file retains the normal library policy for
certificate-signed builds. See Apple's
[library validation documentation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation).

## Commands

From the repository root:

```sh
# Build one app with Apple Silicon and Intel CPU slices.
./Scripts/build_macos_release.py

# Build Apple Silicon only, or Intel only.
./Scripts/build_macos_release.py --arch arm64
./Scripts/build_macos_release.py --arch x86_64

# Choose a different export directory. Paths containing spaces are supported.
./Scripts/build_macos_release.py --output-dir "$HOME/Desktop/iMusic Release"

# Use a separate build cache.
./Scripts/build_macos_release.py --derived-data /tmp/imusic-mac-cache
```

The script also works when invoked by absolute path from another directory.
Default output:

```text
build/Release-macOS/iMusic.app
```

Open that app in Finder, or copy it to Applications yourself. The script only
builds and exports; it does not launch the app, play music, or install over an
existing application in `/Applications`.

After a successful export, the script reports the app and log paths and exits.

## Validation and logs

Every build runs `npm ci` to honor the upload client's lockfile. The script checks
the app's platform, requested CPU slices, bundled upload assets and license notices,
recursive code signature, and signed local-build entitlements. It copies the app with
`ditto` and verifies the copy
before replacing an earlier export. An unrelated app or symbolic link at the
destination is rejected. Failed staging leaves the earlier export in place.

The default cache is `.build-mac`. Command logs are stored in
`.build-mac/release-logs/<timestamp>/`; both cache and export paths are ignored by
Git. Compiler products and available debug symbols remain under
`.build-mac/Build/Products/Release/`.

If a build fails, inspect the log printed by the script. Activate a compatible
Node version on PATH, or set `NODE_BINARY`, when the web dependency check fails.
Use `DEVELOPER_DIR` or `xcode-select` to choose an installed Xcode toolchain; the
script does not change the machine's selected toolchain.

Build-script regression tests do not launch the iMusic UI or play audio. On macOS,
one regression test builds a tiny signed host and dynamic library to exercise the
real Hardened Runtime loader policy:

```sh
python3 -m unittest discover -s Scripts/tests -p 'test_*.py'
```
