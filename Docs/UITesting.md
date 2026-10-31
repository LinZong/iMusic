# UI automation on iPhone and iPad

The shared **iMusic UI Tests** scheme runs XCTest / XCUIAutomation against an independently
installed **iMusic UI Tests** app. The test host uses the production SwiftUI views, feature models,
SQLite store, importer, and playback coordinator. It replaces only audio rendering with a silent
clock backend and disables system media integration and CloudKit.

## Isolation and scope

- `iMusicUITestHost` uses `$(IMUSIC_BUNDLE_PREFIX).uitesting.ios`; the runner uses
  `$(IMUSIC_BUNDLE_PREFIX).uitesting.tests`. Neither overwrites the normal `.ios` application.
- Host-only Swift sources live under `Apps/Testing/` and compile exclusively into the test host.
  Shipping iOS and macOS targets do not include them or define `IMUSIC_UI_TESTING`.
- Each scenario receives a fresh UUID and uses `Documents/UITesting/<UUID>` in the test host's
  own sandbox. The host refuses to launch without a valid test invocation. It never accepts an
  arbitrary library path or clears the normal application library.
- Generated WAVs contain only zero samples. Their different durations prevent content-based
  deduplication. The production importer admits them before tests interact with the UI.
- Only the persistence scenario reuses a UUID across process launches. Test data remains in the
  disposable host container for diagnosis; uninstalling **iMusic UI Tests** removes it.
- Automation identifiers supplement accessible labels. User-facing labels remain localized.
  This initial suite explicitly launches in English for native system controls.

The suite covers primary-page empty states and scoped search, song filtering, playlist creation
and persistence through the shared playlist editor, Now Playing song menus, paused seeking and track switching, Trash swipe restore
and permanent deletion of generated fixtures, and presenting/cancelling the native folder picker.
Screenshots are attached to the Xcode result bundle.

These are UI regressions, not an audio-quality certification. Real decoder, output routing,
background playback, gapless playback, interruptions, AirPlay, and audible distortion require
separate tests with the production backend. Use **iMusic Playback** for listening acceptance without
LLDB. The folder-picker smoke test does not authorize an iCloud folder or prove cloud hydration;
account setup, source authorization and an actual cloud-only sample require a separate acceptance.

## Xcode

1. Open `iMusic.xcodeproj` and select **iMusic UI Tests**.
2. Choose an iPhone or iPad simulator, or a paired physical device.
3. Choose **Product > Test** (`⌘U`), rather than Run. The test runner supplies the host's required
   launch arguments and isolated-library identifier.
4. Review results and screenshots in the Report navigator.

A device must be paired and trusted, have Developer Mode enabled, and be unlocked for UI testing.
Set the signing team and unique bundle prefix in the ignored `Config/Signing.local.xcconfig`.
The same team signs both the test host and the runner. First-time device trust, account sign-in,
and protected authentication prompts may require manual action.

## Command line

Use Python 3.10+, full Xcode, and Node.js 22.12+. Select a destination explicitly; the script never
silently chooses among connected phones or tablets.

```sh
xcrun simctl list devices available
./Scripts/run_ui_tests.py --simulator '<simulator-UUID>'
```

For a physical iPhone or iPad, find the UDID in Xcode's device manager or the existing installer:

```sh
./Scripts/install_ios_release.py --list-devices
./Scripts/run_ui_tests.py --device '<physical-device-UDID>'
# Optional signing-team override:
./Scripts/run_ui_tests.py --device '<physical-device-UDID>' --team '<team-ID>'
```

Device execution allows Xcode to refresh signing profiles and register the explicitly selected
device. It installs only the separate host and runner. It requires no Appium server, jailbreak,
or third-party device-control service.

```sh
# Select one scenario:
./Scripts/run_ui_tests.py --simulator '<UUID>' \
  --only-testing LibraryUITests/testPlayerMenusSeekingAndTrackChanges

# Reuse compatible build-for-testing artifacts on the same platform:
./Scripts/run_ui_tests.py --simulator '<UUID>' --skip-build
```

Build artifacts default to `.build-ui-tests/DerivedData`. Logs, screenshots and `Tests.xcresult`
are retained under `.build-ui-tests/Results/<unique-run>/` and ignored by Git. Open the `.xcresult`
in Xcode to inspect failures and attachments. `--derived-data` selects another cache; `--skip-build`
requires artifacts for the current source, platform, architecture and scheme.

The script disables parallel UI execution to avoid simultaneous scenarios competing for a device.
Successful exit means the selected tests passed; build, signing, runner or assertion failures return
a nonzero exit code. Inspect the saved log rather than treating successful app installation as a
successful UI test.

## Maintaining the project

`Scripts/generate_project.rb` includes both test targets and the shared scheme. If adding host or
UI-test Swift files, regenerate with `ruby Scripts/generate_project.rb` (requires the `xcodeproj`
Ruby gem), then commit the resulting project and scheme. The test host is deliberately outside
SwiftPM's library and unit-test targets.

Apple references: [XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation),
[running tests](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results).

## Verified baseline (2026-10-31)

| Destination | System | Result |
| --- | --- | --- |
| iPhone 15 Pro simulator | iOS 17.4 | All 5 UI scenarios passed |
| iPad Pro 11-inch (M5) simulator | iPadOS 26.3 | All 5 UI scenarios passed |

The iPad run exercised the script's build-and-test path; the phone run also verified the cached
`--skip-build` path. Result summaries confirm five executed passes for each destination. Normal iOS
Simulator and macOS app builds, Swift formatting, localization validation, 31 Python script tests,
and 108 Swift tests also passed (7 optional fixture/hardware tests skipped in the silent run).
Physical-device execution is supported by the target and script but has not been accepted on hardware.

Native macOS UI acceptance also passed on macOS 15.7.4 with an arm64 Release build from the current
source: Create stayed disabled for empty and whitespace-only names, a valid name enabled Create,
and the resulting playlist appeared in both the sidebar and Playlists grid. Quitting and relaunching
the app retained the playlist. The empty `macOS Playlist Check 2026-10-31` playlist remains available
for inspection. This was manual desktop automation, separate from the iOS XCUITest suite above.

## New-playlist alert diagnosis (2026-10-31)

The original `DestinationView` attached a text-field alert to the toolbar destination. Its Create
button called `LibraryViewModel.createPlaylist`, with this modifier:

```swift
.disabled(model.playlistName.trimmingCharacters(in: .whitespaces).isEmpty)
```

On the iPhone 15 Pro simulator running iOS 17.4, entering a valid name visibly enabled Create, but
tapping it dismissed the alert without executing the button action. Temporary file-based probes
confirmed the full draft, the same model identity, and presentation changing to false; neither the
Create action nor `createPlaylist` ran. The problem occurred before any SQLite write or refresh.

A controlled comparison retained the same menu, alert, text input and business action:

| Change from the original alert | Create callback and playlist creation |
| --- | --- |
| None | Failed |
| Remove only the ancestor global error alert | Failed |
| Evaluate name validity in the outer view body | Failed |
| Store the draft in view-owned `@State` instead of the observable model | Failed |
| Replace only the button modifier with `.disabled(false)` | Passed |
| Remove only the button's `.disabled` modifier | Passed, including process-relaunch persistence |

This isolates the source-level trigger to dynamic disabled-state updates on this native alert
action in the tested runtime. It does not establish SwiftUI's internal implementation fault or
claim every supported OS version behaves identically. Instrumentation was removed after diagnosis;
the local comparison traces and result bundles remain under ignored `.build-ui-tests/diagnosis/`.

New playlist creation uses the existing playlist editor sheet, where the ordinary toolbar button
retains empty/whitespace validation without the alert action bridge. This path saves the playlist
draft through `PlaylistEditorViewModel.save` and `LibraryViewModel.save`; it also supports artwork.
The UI regression checks disabled empty/whitespace names, enabled valid input, an actual created
playlist, and persistence after terminating and relaunching the application.
