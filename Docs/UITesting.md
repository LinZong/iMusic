# UI automation on iPhone, iPad, and macOS

The shared **iMusic UI Tests** (iOS) and **iMusicMac UI Tests** (native macOS) schemes run
XCTest / XCUIAutomation against independently installed test-host apps. The hosts use the production
SwiftUI views, feature models, SQLite store, importer, and playback coordinator. It replaces only audio rendering with a silent
clock backend and disables system media integration and CloudKit.

## Isolation and scope

- The native `iMusicMacUITestHost` uses `$(IMUSIC_BUNDLE_PREFIX).uitesting.mac`; its test bundle
  uses `$(IMUSIC_BUNDLE_PREFIX).uitesting.mac.tests`. The host and runner retain App Sandbox;
  Xcode appends `.xctrunner` to the runner app's identifier.
- `iMusicUITestHost` uses `$(IMUSIC_BUNDLE_PREFIX).uitesting.ios`; the test bundle uses
  `$(IMUSIC_BUNDLE_PREFIX).uitesting.tests` (the runner app adds `.xctrunner`). These identities
  keep the normal `.ios` application separate.
- Host-only Swift sources live under `Apps/Testing/` and compile exclusively into the test host.
  Shipping iOS and macOS targets do not include them or define `IMUSIC_UI_TESTING`.
- Each scenario receives a fresh UUID and uses `Documents/UITesting/<UUID>` in the test host's
  own sandbox. The host refuses to launch without a valid test invocation. It never accepts an
  arbitrary library path or clears the normal application library.
- Generated WAVs contain only zero samples. Their different durations prevent content-based
  deduplication. The production importer admits them before tests interact with the UI.
- Only scenarios intentionally relaunching the process reuse their UUID. Test data remains in the
  disposable host container for diagnosis; uninstalling the platform test host removes it.
- Automation identifiers supplement accessible labels. User-facing labels remain localized.
  This initial suite explicitly launches in English for native system controls.

## Regression suite structure

```text
UITests/iMusicUITests/
  Support/UITestCase.swift          # Launch isolation, run UUIDs, failure artifacts
  Support/NativeUI.swift            # Native click/tap and slider/text adapters
  Screens/LibraryScreen.swift       # Sidebar/tabs, tables/lists, context/swipe actions, pickers
  Screens/PlaylistEditorScreen.swift
  Screens/PlayerScreen.swift
  LibraryUITests.swift
  LibraryWorkflowUITests.swift
  PlaylistUITests.swift
  MacPlaybackUITests.swift          # Compiles only on macOS
```

Screen objects own native control differences; test cases state user-visible expectations. Add a
new scenario to the appropriate feature class, reuse screen operations, and rerun both native
schemes. `configure_ui_tests.rb` synchronizes recursive Swift sources into both targets without
replacing production target identities. Running it repeatedly is safe.

| Feature class | Regression coverage | Platforms |
| --- | --- | --- |
| `LibraryUITests` | Empty states/search ownership; song search; name validation and playlist relaunch persistence; player menus, paused seek and next track; Trash restore/permanent deletion; Link Folder picker cancellation | iPhone, iPad, macOS |
| `LibraryWorkflowUITests` | Equal Home card dimensions; favorite filtering and persistence; Import Music picker cancellation; artist collection navigation | iPhone, iPad, macOS |
| `PlaylistUITests` | Cancelled drafts do not persist or leak; playlist-name search is scoped; soft delete and restore | iPhone, iPad, macOS |
| `MacPlaybackUITests` | Persistent volume, mute/unmute restoration; desktop previous/next, repeat, shuffle and favorite controls; Space shortcut; full-player and standalone-window synchronization | macOS |

The shared suite has 12 scenarios; native macOS adds 3 desktop scenarios. Each scenario imports
only generated fixtures through the production importer or starts empty. Screenshots are attached
to the result bundle; failures also attach the accessibility hierarchy. Native AppKit tables expose
Outline rows, and text may be reported in `value` rather than `label`. Mac file-picker queries must
exclude Touch Bar buttons. Context-menu queries stay inside app windows, avoiding hidden Window
menu entries with the same titles as commands. These adaptations belong in `Screens/` and
`Support/`, not feature tests.

These are UI regressions, not an audio-quality certification. Real decoder, output routing,
background playback, gapless playback, interruptions, AirPlay, and audible distortion require
separate tests with the production backend. Use **iMusic Playback** for listening acceptance without
LLDB. The folder-picker smoke test does not authorize an iCloud folder or prove cloud hydration;
account setup, source authorization and an actual cloud-only sample require a separate acceptance.

## Xcode

1. Open `iMusic.xcodeproj` and select **iMusic UI Tests** or **iMusicMac UI Tests**.
2. Choose an iPhone/iPad simulator, a paired physical device, or **My Mac** for the Mac scheme.
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
./Scripts/run_ui_tests.py --macos
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
# Run just the desktop playback regressions:
./Scripts/run_ui_tests.py --macos --only-testing MacPlaybackUITests

# Select one shared scenario:
./Scripts/run_ui_tests.py --simulator '<UUID>' \
  --only-testing LibraryUITests/testPlayerMenusSeekingAndTrackChanges

# Reuse compatible build-for-testing artifacts on the same platform:
./Scripts/run_ui_tests.py --simulator '<UUID>' --skip-build
```

Build artifacts default to `.build-ui-tests/DerivedData/macOS` or
`.build-ui-tests/DerivedData/iOS`, keeping native build-for-testing caches separate. Logs,
screenshots and `Tests.xcresult` are retained under `.build-ui-tests/Results/<unique-run>/` and ignored by Git. Open the `.xcresult`
in Xcode to inspect failures and attachments. `--derived-data` selects another cache; `--skip-build`
requires artifacts for the current source, platform, architecture and scheme.

For native macOS, the script signs the host and runner locally with an ad-hoc identity, without
registering a device or requiring a development team. The test host keeps App Sandbox and disables
Hardened Runtime only for the debug test process so instrumentation can load; shipping targets keep
their own signing and hardening configuration. Run in a logged-in, unlocked graphical session.
If macOS/Xcode requests permission to run UI automation, complete that system authorization before
rerunning. Desktop automation controls the pointer and foreground window; avoid interacting with
the Mac during a run and do not run two desktop UI suites at once.

The script disables parallel UI execution to avoid simultaneous scenarios competing for a device.
Successful exit means the selected tests passed; build, signing, runner or assertion failures return
a nonzero exit code. Inspect the saved log rather than treating successful app installation as a
successful UI test.

## Maintaining the project

After adding host or UI-test Swift files, run `ruby Scripts/configure_ui_tests.rb` (requires the
`xcodeproj` Ruby gem). It updates source references and both native test pairs while preserving
existing target identities. Commit the resulting project and shared schemes with the new sources.
`Scripts/generate_project.rb` also includes both test pairs when deliberately regenerating the whole
project. Test hosts and UI tests remain outside SwiftPM's library and unit-test targets.

Apple references: [XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation),
[running tests](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results).

## Verified regressions (2026-10-31)

| Destination | System | Result |
| --- | --- | --- |
| Native MacBook Pro | macOS 15.7.4 (arm64) | 15 passed, 0 failed, 0 skipped |
| iPhone 15 Pro simulator | iOS 17.4 | 12 passed, 0 failed, 0 skipped |
| iPad Pro 11-inch (M5) simulator | iPadOS 26.3.1 | 12 passed, 0 failed, 0 skipped |

The Mac and iPhone runs exercised the script's build-and-test path; the iPad run reused the iOS
build through `--skip-build`. Saved xcresult summaries verify 39 executed passes across the three
platforms. Shared text-reading adapters also receive focused Mac regression after UIKit-specific
normalization changes. Swift formatting (121 first-party files), localization validation (364 keys,
3 languages), 34 Python script tests, and repeated project-configuration idempotence checks passed.
Physical-device execution is supported by the target and script but has not been accepted on hardware.

The existing Swift unit suite complements this UI suite; UI automation intentionally replaces audio
rendering and does not certify production decoder or device-output behavior. Earlier native macOS
Release acceptance also verified playlist name validation, creation, and process-relaunch persistence
through the normal application.

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

## Desktop keyboard regression

The desktop regression initially found that the menu-only Space shortcut did not reach the
playback engine, even with the app explicitly in the foreground; clicking Play / Pause in the same
menu worked. Binding Space to the live play/pause buttons in the desktop bar, full player, and
standalone mini-player window makes the command local to the active playback surface. The Mac
suite checks pause/resume transitions for these surfaces and that standalone-window changes update
the main window's session. Temporary engine tracing used for diagnosis is excluded from sources.

The full-player sheet explicitly gives initial keyboard focus to its transport button. Otherwise
Space can activate the initially focused Collapse button and dismiss the sheet, following native
button activation behavior. A regression verifies that Space toggles playback while the full
player remains visible. UIKit elapsed-time text is read from `label` when its native `value` is
empty; AppKit reports the same visible text in `value`. An empty UIKit text field can expose its
placeholder as `value`, so blank-draft assertions accept that representation while still requiring
Create to remain disabled.
