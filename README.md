# iMusic

A native offline music player for **iPhone, iPad, and macOS**, built with SwiftUI.
Keep a local music library, organize playlists, and listen without a streaming account.

English · [简体中文](README.zh-CN.md)

> iMusic is under active development. Build it from source; signed downloads are not
> published yet. CloudKit and CarPlay are optional and require your own signing capabilities.

## Features

- Adaptive phone, tablet, and desktop layouts with a shared playback core.
- Import from Files, linked folders, or a paired browser over your local Wi-Fi network.
  Imports are copied into the app's managed library; source files remain untouched.
- Songs, artists, albums, genres, favorites, playlists, and an editable playback queue.
- MP3, AAC/M4A, ALAC, FLAC, WAV, AIFF, Ogg Vorbis, Opus, and other formats supported
  by the bundled decoder. Availability depends on the actual container and codec.
- Shuffle, repeat, seeking, playback speed, equalizer, A/B repeat, and a sleep timer.
- Artwork and metadata editing, optional manual cover lookup, ZIP backup and restore,
  and a recoverable Trash with explicit permanent deletion of managed copies.
- macOS playback controls include persistent app volume and mute settings.
- English, Simplified Chinese, and Traditional Chinese. Appearance follows the system.
- Local listening statistics without unsolicited reports or notification prompts.

## Build and run

Requirements: macOS with Xcode, Node.js **22.12 or newer**, and npm. The project has
been built with **Xcode 26.3 / Swift 6.2.4**. Dependencies require Swift 6.1 or newer;
deployment targets are **iOS/iPadOS 17** and **macOS 14**.

```sh
git clone https://github.com/LinZong/iMusic.git
cd iMusic
npm ci --prefix Web/WiFiUpload
open iMusic.xcodeproj
```

Allow Xcode to resolve Swift packages and download the audio XCFrameworks. Trust
the repository's local `WiFiUploadBuild` plugin when prompted. Select `iMusicMac`
for Mac, or `iMusic` for an iPhone/iPad simulator or connected development device.

For a physical device, copy `Config/Signing.example.xcconfig` to
`Config/Signing.local.xcconfig`, then set your development team and a unique bundle
prefix. The local file is ignored by Git. See [signing and capabilities](Docs/Signing.md)
for device setup, CloudKit, and CarPlay.

Native dependencies use **Swift Package Manager**, and the upload client uses
**npm / React / TypeScript / Vite**. CocoaPods is not needed. SwiftPM builds the upload
client and bundles its static assets during Build, Run, Archive, and `swift test`.
Node and external web hosting are not required at runtime.

### Schemes

| Scheme | Purpose |
| --- | --- |
| `iMusic` / `iMusicMac` | Local development with Debug and LLDB |
| `iMusic Playback` | iPhone/iPad Release build, launched without LLDB |
| `iMusicMac Playback` | macOS Debug build, launched without LLDB |
| `iMusic Cloud` / `iMusicMac Cloud` | Optional private CloudKit sync |
| `iMusic CarPlay` | Optional CarPlay interface with an approved entitlement |
| `iMusic Full` / `iMusicMac Full` | CloudKit; also CarPlay on iOS. Archive uses FullRelease. |

Use the Playback schemes for listening and playback continuity checks. Debugger
pauses, including internal loader and thread breakpoints, can interrupt real-time
audio. The regular schemes retain breakpoint debugging. Local Debug and Release
builds do not require CloudKit, push, or CarPlay entitlements.

## Development and validation

```sh
python3 Scripts/swift_style.py check
python3 Scripts/check_localizations.py
npm run format:check --prefix Web/WiFiUpload
npm test --prefix Web/WiFiUpload
swift test

xcodebuild -project iMusic.xcodeproj -scheme iMusicMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project iMusic.xcodeproj -scheme iMusic \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The unsigned builds above validate compilation; device installation needs signing.
Ordinary tests use a controlled audio engine and do not play sound. Hardware audio
and performance tests are opt-in; see the [contribution guide](CONTRIBUTING.md).
CI checks Swift formatting, localization, web tests, package tests, and native builds.

Views and view models live in feature folders under `Sources/iMusicKit/View/` and
`Sources/iMusicKit/ViewModel/`. `Application/AppModel.swift` assembles dependencies
and starts the app. The upload client has its own
[development guide](Web/WiFiUpload/README.md).

- [Architecture and state ownership](Docs/Architecture.md)
- [Backup format](Docs/BackupFormat.md)
- [Signing, CloudKit, and CarPlay](Docs/Signing.md)
- [Validation scope and device checks](Docs/Validation.md)
- [Localization](Docs/Localization.md)
- [Swift style](Docs/CodeStyle.md)
- [Contributing](CONTRIBUTING.md) · [Security reporting](SECURITY.md)

Some detailed engineering documents are currently in Chinese. The committed Xcode
project is ready to open; regenerating it with `Scripts/generate_project.rb` is
optional and requires the Ruby `xcodeproj` gem.

## Current limits

Lyrics, Apple Watch, Siri/Shortcuts, widgets, NAS integration, and cross-device
playback handoff are not implemented. iOS folder rescans occur on launch, foreground
entry, or manual request. AirPlay route changes can briefly pause playback.
CloudKit and CarPlay builds require separate setup and device validation.

## License

iMusic's original source is available under the [MIT license](LICENSE).
Dependencies retain their own licenses; see [ThirdPartyNotices](ThirdPartyNotices).
That directory includes the pinned dependency graph and component notices, including
additional terms for audio components. Review those terms before distributing binaries.
Music files, personal libraries, signing credentials, and developer configuration
are not included in the source distribution.
