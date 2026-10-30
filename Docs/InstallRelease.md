# Install an iOS Release build from the terminal

`Scripts/install_ios_release.py` builds and installs iMusic without opening the
Xcode application. It uses the local iOS target, Release configuration, and your
development signing identity. This does not archive or upload an App Store build.

## One-time setup

- Install the full Xcode toolchain and select it with `xcode-select`. The script
  does not replace Apple's SDKs, compiler, signing tools, or account setup.
- Use Python 3.10+ and Node.js 22.12+ with npm. Each build runs `npm ci` to use the
  upload client's pinned dependencies. `--skip-build` does not require Node/npm.
- Copy `Config/Signing.example.xcconfig` to `Config/Signing.local.xcconfig`; set
  your development team and unique bundle prefix. Keep the local file ignored.
- Connect and unlock an iPhone/iPad, trust the Mac, and enable Developer Mode.
- For a new device, its UDID must be registered with your development team and
  included in the provisioning profile. Automatic signing can refresh available
  profiles when your Xcode account session is valid. An unregistered device or
  expired account session needs to be resolved before installation can succeed.

For newer devices whose developer support image is missing from Xcode, install
the optional direct installer:

```sh
brew install ideviceinstaller
```

Version 1.2+ of `ideviceinstaller` is required. It uses the device's app installation
service, so installing an already signed app does not require mounting Xcode's
developer disk image. This fallback does not provide Xcode debugging support.

## Commands

Run these commands from the repository root. The script itself also works when
invoked by absolute path from another directory.

```sh
# List reachable physical iOS devices, including their names and UDIDs.
./Scripts/install_ios_release.py --list-devices

# Build, validate signing, and install. A single reachable device is selected automatically.
./Scripts/install_ios_release.py

# With multiple devices, use an exact name, hardware UDID, or CoreDevice identifier.
./Scripts/install_ios_release.py --device "My iPhone"

# Install the existing signed Release app without rebuilding or installing npm dependencies.
./Scripts/install_ios_release.py --skip-build

# Force the direct installer when Xcode lacks support for the connected model.
./Scripts/install_ios_release.py --skip-build --installer ideviceinstaller

# Temporarily override the signing team without editing shared project settings.
./Scripts/install_ios_release.py --team YOURTEAMID
```

`--derived-data /path/to/cache` changes the build/cache directory. The default is
the repository's ignored `.build-device` directory. `--skip-build` expects
`Build/Products/Release-iphoneos/iMusic.app` inside that directory. It reuses that
artifact as-is; omit the flag after source or signing changes.

## Installation and diagnostics

The default `--installer auto` first uses Apple's `devicectl`. Only developer disk
image errors trigger a fallback to `ideviceinstaller`. Other installation errors
are reported directly. `--installer devicectl` disables fallback; selecting
`ideviceinstaller` explicitly skips the Apple installation attempt.

Before installing, the script verifies the code signature, physical-device build
platform, minimum OS version, provisioning expiry, and target UDID. After installing,
it checks the device's application list for the expected bundle identifier. It
does not uninstall the app or clear its library. Open iMusic on the device after
installation; the script does not attach a debugger or start audio playback.

Command output, device discovery JSON, and signing diagnostics are kept under
`.build-device/install-logs/<timestamp>/` by default. If a command fails, the script
prints the log path. Remove device identifiers, account details, and local paths
before sharing those logs.

Common failures:

- **No reachable device:** unlock it, accept the trust prompt, and reconnect USB.
- **Multiple devices:** pass `--device` with the intended UDID or exact device name.
- **Signing failure:** check your local signing configuration, account session,
  certificate, and profile. See [Signing.md](Signing.md).
- **Profile does not include this device:** register its UDID with the developer
  team and rebuild with an updated profile; reusing the old app cannot fix this.
- **Missing developer image:** install the optional direct installer and retry
  with `--skip-build`. Updating Xcode is needed if you also want debugging support.
- **Node version error:** activate Node.js 22.12+ on PATH, or set `NODE_BINARY` to
  the executable you want the build to use.

Script regression tests run without building, installing, or playing audio:

```sh
python3 -m unittest discover -s Scripts/tests -p 'test_*.py'
```
