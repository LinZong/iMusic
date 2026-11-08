# Build an unsigned IPA for SideStore

`Scripts/build_sidestore_ipa.py` builds the standard local `iMusic` scheme with
Release optimization, disables Xcode signing and provisioning for that invocation,
and exports a SideStore-ready ZIP archive with this layout:

```text
Payload/
└── iMusic.app/
```

The resulting IPA is deliberately unsigned. It cannot be installed or launched
directly; SideStore must re-sign it for the destination device.

## Requirements

- macOS with the full Xcode command-line toolchain selected by `xcode-select`.
- Python 3.10+ and Node.js 22.12+ with npm.
- Network access for the first Swift package resolution and locked npm installation.

No Apple development team, certificate, provisioning profile, connected device,
or Developer Mode is required to create the IPA. The script clears signing inputs
only on its `xcodebuild` command; it does not edit `Config/Signing.local.xcconfig`
or the shared project.

## Commands

Run from the repository root:

```sh
# Build, validate, and export the unsigned IPA.
./Scripts/build_sidestore_ipa.py

# Package the unsigned app already present in the default build cache.
./Scripts/build_sidestore_ipa.py --skip-build

# Choose separate cache and output paths. Paths with spaces are supported.
./Scripts/build_sidestore_ipa.py --derived-data /tmp/imusic-sidestore-cache \
  --output "$HOME/Desktop/iMusic-unsigned.ipa"
```

Default output:

```text
build/SideStore/iMusic-unsigned.ipa
```

`--skip-build` expects
`Build/Products/Release-iphoneos/iMusic.app` inside the selected derived-data
directory. It still rejects a signed app or one containing an embedded profile.
Omit the option after source, dependency, or web-client changes.

Import the resulting `.ipa` into SideStore using its normal source or file-import
workflow. The script only creates the input artifact; it does not connect to a
SideStore server, register an App ID, install the app, or manage SideStore's
device-side refresh.

## Validation and logs

Each build runs `npm ci` so the Wi-Fi Upload client uses its lockfile. Before
publication, the script checks the physical-device platform, arm64 executable,
bundle metadata, web assets and notices, absence of `_CodeSignature` directories
and embedded provisioning profiles, and a failing `codesign --verify` result. It
then stages `Payload/iMusic.app` with `ditto`, creates the IPA, verifies the ZIP
without resource-fork or extended-attribute sidecars, verifies the ZIP layout and
executable permission, tests every archive member, and atomically
replaces an older output file. Output symlinks and non-file destinations are
rejected.

The default cache is `.build-sidestore`. Logs are stored in
`.build-sidestore/sidestore-logs/<timestamp>/`; both cache and IPA output are
ignored by Git. The build uses the ordinary `iMusic` scheme and therefore does
not request CloudKit or CarPlay capabilities.

Run the build-script regression suite with:

```sh
python3 -m unittest discover -s Scripts/tests -p 'test_*.py'
```
