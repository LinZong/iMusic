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
  LibraryWorkflowUITests.swift     # Also contains touch-only MiniPlayerUITests
  PlaylistUITests.swift
  PlayerAppearanceUITests.swift     # Compiles only on iOS / iPadOS
  MacPlaybackUITests.swift          # Compiles only on macOS
```

Screen objects own native control differences; test cases state user-visible expectations. Add a
new scenario to the appropriate feature class, reuse screen operations, and rerun both native
schemes. `configure_ui_tests.rb` synchronizes recursive Swift sources into both targets without
replacing production target identities. Running it repeatedly is safe.

| Feature class | Regression coverage | Platforms |
| --- | --- | --- |
| `LibraryUITests` | Empty states/search ownership; song search; name validation and playlist relaunch persistence; player menus, paused seek and next track; Trash restore/permanent deletion; Link Folder picker cancellation | iPhone, iPad, macOS |
| `LibraryWorkflowUITests` | Equal Home card dimensions; favorite filtering and persistence; Import Music picker cancellation; artist collection navigation; all four All Songs shortcuts and stack return; narrow desktop window and inherited background pixels; system collection title/search recovery, native scroll boundaries, scrolling shortcut/legacy statistics rows, and adaptive legacy backgrounds | iPhone, iPad, macOS |
| `PlaylistUITests` | Cancelled drafts do not persist or leak; scoped playlist search; restore and permanent deletion; Trash category tabs with independent searches, summaries, and empty states; playlist-detail add/remove with library-song preservation; touch-only fixed search/summary scrolling boundaries, empty/search layout, independent summary actions, and occurrence reordering | iPhone, iPad, macOS |
| `PlayerAppearanceUITests` | Saved light/dark appearance; background pixel checks across three mini-player expansions | iPhone, iPad |
| `MiniPlayerUITests` | Adaptive compact/wide bars, rotation with paused playback and mode/favorite retention, nonoverlapping 44-point controls, previous/next and queue/full-player access | iPhone, iPad |
| `MacPlaybackUITests` | Persistent volume, mute/unmute restoration; desktop previous/next, repeat, shuffle and favorite controls; Space shortcut; full-player and standalone-window synchronization | macOS |

Native-only scenarios complement the shared workflows; use the runner's actual result summary
for the executed count, including version-dependent skips. Each scenario imports
only generated fixtures through the production importer or starts empty. Screenshots are attached
to the result bundle; failures also attach the accessibility hierarchy. Native AppKit tables expose
Outline rows, and text may be reported in `value` rather than `label`. Mac file-picker queries must
exclude Touch Bar buttons. Context-menu queries stay inside app windows, avoiding hidden Window
menu entries with the same titles as commands. These adaptations belong in `Screens/` and
`Support/`, not feature tests.

Trash tests select the Songs or Playlists segment explicitly and verify independent search text,
summaries, and category empty states. Query clearing uses the native clear-text button on touch
platforms rather than relying on keyboard focus. The combined scenario also navigates away and
returns before testing recovery, covering search-view teardown and recreation. Restoration and
deletion have additional dedicated scenarios.

Mini-player rotation captures use `XCUIScreen.main.screenshot()` because application-bound
screenshots can crop the rotated window on tested runtimes.

Appearance tests sample an unobstructed sheet margin after presentation. They do not measure
individual animation frames. For a presentation-color regression, also record the simulator with
`xcrun simctl io '<UUID>' recordVideo --codec=h264 '<output.mp4>'`, repeat mini-player expansion,
then send SIGINT to the recorder and inspect the opening frames. A settled screenshot alone can
miss a transient background change.

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

## Mini-player artwork across navigation

`testMiniPlayerArtworkAcrossTabsAndTrackChanges` uses the `artwork` scenario: generated red and
blue covers plus an active song without artwork. It checks cover pixels through two cycles of the
four compact tabs, or corresponding sidebar destinations on iPad, then switches between the two
covers and the placeholder. The Mac transport regression uses the same generated covers and opens
the full player. These settled assertions verify request changes; they do not certify animation
frames.

`ArtworkCacheTests` verifies memory-only lookup, library-path and resolution isolation.
`ArtworkViewTests` checks a recreated view's first-frame image decision before a task starts,
retention on reappearance, request matching, A-to-B-to-A generations, and cancelled completions.
Native iOS 26 tab accessories can recreate cover state on each selection; the rendering path must
resolve warm memory images before the lifecycle task runs. The task must not clear matching images
when older per-tab views reappear.

Acceptance on 2026-11-01 passed 3 player appearance/artwork scenarios on iPhone 17 Pro / iOS 26.3.1,
the artwork scenario on iPhone 15 Pro / iOS 17.4 and iPad Pro 11-inch (M5) / iPadOS 26.3.1, and the
native macOS 15.7.4 transport scenario: 6 UI passes in total. Full Swift tests passed with 127 passes,
7 opt-in skips, and no failures. Formatting, architecture, localization, and whitespace checks passed.

Recordings of the actual fixed app also sampled an 8-by-8-pixel patch inside the cover throughout
the warm navigation loops. All 1,307 iOS 26 iPhone samples, 194 iOS 17 samples, and 787 iPad samples
retained the generated red cover. The sampled interval ends before changing to the initially
uncached blue-cover song, where a normal loading placeholder is allowed. No production lifecycle
probes or artificial loading delays are involved. These simulator recordings and the silent desktop
host do not certify physical-device rendering or real audio output.

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

## Now Playing background diagnosis (2026-10-31)

On the iPad Pro 11-inch (M5) simulator with iPadOS 26.3.1, expanding the mini player in Dark
appearance briefly rendered a brighter, tinted player canvas before its normal dark background.
The affected expression was `Rectangle().fill(.background)` inside `NowPlayingView.playerContent`.
Here `.background` is the contextual `BackgroundStyle`, not a fixed system background color.

A read-only probe in an ignored source snapshot sampled the presentation's UIKit traits, geometry,
Core Animation layers, and the SwiftUI environment. Throughout presentation, UIKit stayed Dark and
Elevated, the sheet stayed 580 × 650 points, and the resolved system background RGBA stayed
approximately `(0.1098, 0.1098, 0.1176, 1)`. However, SwiftUI's `backgroundMaterial` contained a Glass
material during presentation and became `nil` after the transition. The canvas's contextual fill
therefore inherited transient material rendering. A settled screenshot missed the problem.

The same generated song, app appearance, and repeated mini-player expansion were used for
single-variable comparisons in that snapshot:

| Change from the original player | Opening background |
| --- | --- |
| None | Brighter/tinted, then dark |
| Add a system-color background outside the navigation stack | Still brighter, then dark |
| Cancel only the native backing layer's background-color animation | Still brighter/tinted, then dark |
| Replace only the canvas fill with `Color(uiColor: .systemBackground)` | Stable |
| Keep the original fill and clear `backgroundMaterial` only on that rectangle | Stable |

The last two independent controls isolate the trigger to the canvas's inherited material rendering.
The fix uses `.environment(\.backgroundMaterial, nil)` only on the background rectangle, preserving
system colors, the accent gradient, native controls, layout, and sheet transitions. No presentation
controller traversal, animation cancellation, color constants, or OS-version branch ships in the app.
The temporary probes and recordings remain under ignored build directories, outside production
sources.

After removing the probes, the dark/light presentation checks and the menu/seek/track-change test
passed on both iOS 17.4 and iPadOS 26.3.1 simulators (6 focused passes). An additional recording
confirmed stable background pixels across all three dark-player expansions. The native macOS app
also built successfully; Swift formatting and localization checks passed.

Apple references: [BackgroundStyle](https://developer.apple.com/documentation/swiftui/backgroundstyle),
[backgroundMaterial](https://developer.apple.com/documentation/swiftui/environmentvalues/backgroundmaterial).

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

## System collection navigation and fixed song details

`SongCollectionView` covers All Songs, Favorites, and artist/album/genre song results. On
iPhone/iPad these pages use adaptive system navigation titles and navigation-bar drawer search.
Their native ScrollView with LazyVStack remains the only vertical scroll host; compact-width titles
collapse while scrolling and expand at the top. Collections retain native bounce: clamping
`contentOffset` conflicts with iOS 26's changing navigation insets, and disabling `bounces` prevents
the large title from expanding again. Native navigation-host inference is used without UIKit
host-registration adapters,
offset observation, search-dismissal scrolling, or scroll-view identity resets. All touch versions
share Playlists' `.always` drawer and default search presentation through `librarySearch`.
The former `.automatic` workaround hid search on iOS 17, while `.avoidHidingContent` prevented
search from moving into the title area on iOS 26. Neither option belongs to the current contract.
Tests assert a large title at compact width, native inline title at regular width, and visible search
immediately after first navigation. The title policy is not forced to `.large`; the direct Playlists
comparison also checks title height on iPad. Assertions run before any drag or search action; there
is no preparatory pull to conceal a missing control.
Desktop toolbar search is unchanged.
Playlist details, Trash, and the song picker retain their previous scroll behavior.
All Songs places its single-row shortcut header inside the vertical scroll document. It scrolls away
with songs and returns at the top. On iOS 17, statistics follow it and also scroll away;
collections without shortcuts start with their statistics. iOS 26 retains the bottom glass summary
using safeAreaInset; fixed-detail pages keep their existing safeAreaBar.
These controls remain separate from the actual song ForEach and never change reorder indexes.
macOS retains its header and statistics above the native Table.

Playlist details continue to use the fixed `LibrarySearchInput` and fixed content-owned large
heading. Trash and the song picker keep the same native input adapter, while macOS retains its
upper-right system search. This split is intentional: collection navigation follows the system,
whereas editing and recovery flows preserve their stable fixed controls.

The earlier iOS 26 regression placed the large title inside the clipped horizontal shortcut
viewport after dismissing navigation search. Collection regressions therefore keep the vertical
scroller present even for zero rows, verify title pixels after blank and no-match searches, and exercise
All Songs with its horizontal shortcut bar. No collection header registers a top safe-area bar or
inset. The header is non-song scrolling content, never an alternative vertical scroll host or
a synthetic song record. Empty overlays exclude the measured height of these scrolling controls
and preserve their hit regions; the measurement does not observe scrolling.

`testPlaylistSearchAndSummaryStayFixedWhileSongsScroll` uses 40 generated playlist occurrences and
keeps the fixed-detail contract. The `song-scroll` fixture adds 40 active and 40 deleted records
sharing only generated silent test assets, so collection scopes and Trash exercise long native
lists. `testSongCollectionsUseSystemNavigationAndSurviveSearchEditing` checks collection title
collapse/expansion and native search across all five scopes, each in a fresh host session to avoid
the iOS 17 injected snapshot logger's high-volume crash;
`testSongCollectionTitlesExpandAtNativeScrollBoundary` covers empty and long boundary behavior,
including the settled expanded title after native rebound.
`testSongCollectionTitleReturnsAfterRepeatedSlowDrags` repeatedly crosses the large/inline threshold
on All Songs and Favorites at 40 points/second, requiring bounded returns and a stable
expanded title. Gestures begin in the non-draggable gutter: a very slow press on a song can start
its supported drag-and-drop action rather than vertical scrolling. These assertions only check
settled states, not continuity during a gesture.
Also record continuous slow drags on the actual song page and inspect title/search/row trajectories;
an endpoint pass must not be used to dismiss a visible jump. The iOS 26.3 minimal comparison showed
a roughly 50-point startup jump with List plus bottom safeAreaBar. Keeping the same glass surface
and soft edge effect but using safeAreaInset removed that jump. A ScrollView plus `.always` also
showed both initial controls on iOS 17.4, unlike List; the old hidden-search compromise was not a
general system limitation. Diagnostic views are not retained in production sources.
`testSongCollectionsUseSystemNavigationAndSurviveSearchEditing` checks first-presentation native
titles and visible search before interaction in all five collection scopes. `collectionSearch()`
does not pull to reveal a hidden drawer. `testSongCollectionSearchMatchesPlaylists` compares initial
and focused search frames against the actual playlist grid. The separate
`testScrolledCollectionSearchDismissalKeepsTitles` checks dismissal while scrolled on both pages.
Their `navigation-scroll` fixture adds long song and playlist collections using generated records
only. `testTrashRetainsFixedNavigationAfterLeavingSongCollection` independently
checks the unchanged Trash title/search/summary contract after entering from All Songs, instead of
chaining the recovery-page regression onto the five-scope navigation test.
`testAllSongsShortcutsScrollWithSongs` verifies scroll-view ancestry, shared vertical displacement with a
song row, scrolling out of the viewport, returning to a shortcut, and searching after stack return.
`testLegacyCollectionSummaryScrollsWithoutFeatureHeader` verifies scrolling Favorites statistics
and empty-content separation. `testLegacyShortcutsHaveOpaqueAdaptiveBackground` samples the
full-width legacy header padding in Light and Dark appearances, then scrolls away and returns to
activate a shortcut. The background is a dynamic system style, not hard-coded white or black.
`testPlaylistSummaryActionsEmptyStatesAndReordering`
checks empty/unmatched layout, independent Play/Shuffle actions, and song-only reorder handles.
`testEmptyAllSongsTitleSurvivesSearchEditing` covers the empty collection route.
`testDesktopPlaylistSummaryStaysFixedWithToolbarSearch` checks desktop table scrolling, fixed
summary coordinates, filtering, and the search field's upper-right toolbar location. It locates the
outline containing song titles, not the first outline (which can be the sidebar), and requires the
first song row to move before asserting that summary coordinates stay fixed.
Native collection search may replace the title while focused; tests require the native title to
return after blank and no-match dismissal. Fixed-search regressions require the title to remain
above their content field. Both crop the title frame from the actual window screenshot and require
foreground/background luminance contrast, detecting labels covered by a flat inset background even
when accessibility reports them as visible. Shortcut regressions continue to exercise actual
pointer clicks on macOS and native touch on iPhone/iPad, revealing offscreen touch shortcuts by
horizontal scrolling. The glass shortcut header keeps 12 points of top padding below navigation
search and 28 points below the capsules for shadow clearance; its top spacing, native regular size,
and lower shadow continuity are checked together. Desktop shortcut regressions compare pixels in
the header padding against the neighboring native summary surface: the iOS-only opaque background
must not paint a separate white strip on macOS. The regular-size/12-point-spacing follow-up passed
the four-destination shortcut regression on both iPhone and iPad iOS 26.3.1 simulators.

The iOS 26 mid-scroll search-dismissal follow-up isolates a native title-layout defect: a minimal
NavigationStack/ScrollView/searchable page also loses its inline title after Close. Removing tabs,
the accessory, feature headers, or outer stacks does not prevent it. Waiting four seconds does not
restore it either. The native scroll host, content offset, adjusted insets, and navigation bar frame
remain unchanged; requesting navigation layout restores the title without moving content.

Deeper root-cause diagnostics on 2026-11-08 reproduced the same failure in a separately compiled
UIKit-only app with its own UIApplicationDelegate/window, UINavigationController, UIScrollView,
and UISearchController. It imports neither SwiftUI nor iMusicKit. The same simulator binary fails
on iOS 26.3.1 and restores the inline title normally on iOS 17.4 (Xcode 26.3, SDK 26.2).
Read-only view/layer snapshots show the mechanism: before search, the inline title's ancestor has
alpha 1 and the offscreen large-title container has alpha 0; after dismissal these become 0 and 1.
The inline label itself still has its original text, alpha 1, and isHidden false. Its wrapper also
moves down 15 points, while the large title remains outside the viewport. After settling, both model
and presentation opacity agree and there are no remaining layer animations, excluding a merely
unfinished animation or an accessibility-only failure. Public title/display mode and pre/post
scroll offsets/insets remain unchanged. Owned UIKit search-delegate callbacks locate the mismatch
at didDismissSearchController; diagnostics do not replace any SwiftUI-owned delegate.

Single-variable controls on iOS 26 distinguish the trigger and recovery:

- Dismiss at the top, disable large titles, or set hidesNavigationBarDuringPresentation false:
  title remains visible. These are diagnostic controls, not product UX changes.
- Explicitly register the content scroll view: the title still disappears.
- Call layoutIfNeeded without invalidation: the title remains missing.
- Invalidate and lay out only the navigation bar: inline/large-title visibility returns to 1/0,
  inline geometry is restored, and scrolling does not move. Invalidating the navigation root also
  recovers it. This supports a UIKit collapse-state/layout-invalidation defect, not a lost query,
  removed title, missing scroll host, shortcut overlap, or a SwiftUI-only integration problem.

This establishes the observable framework failure and its boundary, not the exact missing call
inside Apple's closed-source implementation. The compatibility adapter remains a workaround for
that defect. Diagnostic harnesses deliberately record the broken state rather than count it as a
passing product assertion. Local evidence is retained under `.build-ui-tests/Results/`:
`20261108T060202Z-55f33d52` (SwiftUI/UIKit ancestry), `20261108T060429Z-3ed0c239` (iOS 26 controls),
`20261108T060512Z-85fab849` (iOS 17 controls), `20261108T060701Z-58470c8c` (standalone UIKit iOS 26),
and `20261108T060741Z-57cc59c9` (the same standalone app on iOS 17). The local standalone source is
`.build-ui-tests/Diagnostics/SearchTitleRootCause/NativeProbe.swift`; diagnostic code is excluded
from app and regression-test sources.

`NavigationSearchLayoutRecovery` observes the native searching environment only at compact width
on iOS 26. It requests layout once the search transition completes, with generation, visibility,
and page-identity guards; it does not replace delegates, inspect private types, register a scroll
host, reset view identity, or write offsets. The no-coordinator path defers to the next main-thread
turn, not an arbitrary timed retry. Temporary diagnostic hosts and timers are not shipped.
`testScrolledCollectionSearchDismissalKeepsTitles` now requires three consecutive dismissals on
each page to restore painted title pixels and original title geometry. Compact-width runs also
check that search still moves upward and the same visible song/card keeps its vertical coordinate.
There is no expected-failure exemption. Initial/top-of-list empty-query and no-match dismissal
regressions remain ordinary assertions, and default native search presentation is retained.
`testScrolledCollectionSearchFilteringKeepsTitles` additionally checks blank/no-result editing and
clearing from mid-scroll on both the playlist grid and song collection.

Recovery validation on 2026-11-08 passed seven focused iPhone 17 Pro / iOS 26.3.1 cases across two
runs: repeated mid-scroll dismissal, mid-scroll filtering, reference search geometry, empty songs,
all shortcuts/stack return, repeated slow title transitions, and unchanged fixed playlist details.
iPhone 15 Pro / iOS 17.4 passed two cases (repeated dismissal and reference geometry); iPad Pro
11-inch (M5) / iPadOS 26.3.1 passed those two plus empty-library search. No expected failures remain
in these runs. Native macOS 15.7.4 passed search/persistence and fixed playlist summary/toolbar
search, including actual song-table scrolling. SwiftPM passed 141 tests with 9 opt-in skips;
all 35 Python tests and Swift style,
architecture, localization, and whitespace checks passed.

The Playlists-alignment follow-up on 2026-11-08 validated the actual reference grid's initial title
height and idle/focused search positions against All Songs on iPhone 15 Pro / iOS 17.4, iPhone
17 Pro / iOS 26.3.1, and iPad Pro 11-inch (M5) / iPadOS 26.3.1. Focused iPhone runs also passed
scrolling shortcuts, empty search, all five collection scopes, fixed playlist details, legacy
summary/adaptive background/Trash behavior, and glass summary/MiniPlayer separation. The iOS 17
five-scope test initially hit the injected snapshot logger crash described below; it passed after
each scope received its own host session. iPad passed four focused scenarios: reference navigation,
shortcut scrolling, empty search, and glass summary/MiniPlayer separation. These are focused runs,
not an uninterrupted full-platform suite.
The final iPhone 26 slow-drag rerun passed all three collapse/expand cycles on both All Songs and
Favorites at 40 points/second; recorded frames showed continuous title/search/row movement without
the earlier startup jump. Its then-separate mid-scroll search-dismissal case recorded two explicit
expected title-visibility failures, one for each page, before the recovery described above.
Native macOS 15.7.4 passed shortcut/background/navigation, search/persistence, and fixed playlist
summary/toolbar search. Log review exposed the older table test scrolling the sidebar instead;
the strengthened test then passed a separate rerun with the song outline targeted and actual row
movement required. No desktop presentation changes were needed for this alignment.
SwiftPM executed 141 tests with 9 opt-in skips and zero failures; all 35 Python tests, Swift style,
architecture, localization, and whitespace checks passed.

Earlier validation on 2026-11-08 used macOS 15.7.4, iPhone 15 Pro / iOS 17.4, and iPhone 17 Pro plus
iPad Pro 11-inch (M5) / iOS 26.3. The macOS full run executed 21 tests: 17 passed, and all four
failed cases passed in a separate focused rerun after fixing screenshot-coordinate sampling and
reactivating the test app before desktop shortcut clicks. This is not a single uninterrupted
21/21 pass. Avoid running desktop pointer tests concurrently with simulator UI interactions.
The background regression uses display coordinates with `XCUIScreen.main`, because macOS element
screenshots can include the entire display; scaling such an image against the window frame samples
unrelated pixels. SwiftPM executed 141 tests with 9 opt-in skips and zero failures; all 35 Python
script tests, Swift formatting, architecture, localization, and whitespace checks passed.
Focused touch regressions passed for scrolling shortcuts, empty/search layout, native title
boundaries and repeated slow returns, legacy scrolling statistics and Light/Dark backgrounds,
bottom summary/mini-player separation, fixed playlist details, and picker search. Final iPhone and
iPad iOS 26 shortcut runs also passed the 44-point target, shadow-pixel continuity, all four actual
shortcut activations, and stack-return checks after reserving shadow space inside the List row.

The initial-title follow-up on 2026-11-08 removed all preparatory title-reveal pulls. The iOS 17.4
long/empty initial-title boundary test passed, along with search scope/persistence, all shortcut
activations, scrolling shortcuts, empty-search layout, legacy summary placement, adaptive
backgrounds, repeated slow returns, all five collection scopes, and the independent fixed Trash
contract. These eleven scenarios passed across focused runs, not in one uninterrupted suite.
Earlier attempts crashed inside iOS 17's injected `XCTAutomationSupport` snapshot/logging code
(`runtime_issue_os_log_fault_callback` after logging quarantine), including once after all five
collections had passed and the combined test entered Settings/Trash. Failed runs remain recorded;
bounded reveal helpers now stop querying as soon as the target is available, and the unchanged
Trash assertions run in their own scenario. The scrolling-shortcut rerun and the final two
collection/Trash tests passed. No application logging suppression or scroll-position workaround
was added. iOS 26.3 iPhone passed five focused cases, including first-presentation titles across
all scopes, all shortcut activations, shared scrolling, and slow/native boundary returns.
iPadOS 26.3 passed the three follow-up cases for shared shortcut/song scrolling, empty collection
search, and long/empty first-presentation titles plus native scroll boundaries.
The final macOS run passed both shortcut/background/navigation and fixed playlist summary with
native toolbar search. SwiftPM again executed 141 tests with 9 opt-in skips and zero failures;
all 35 Python tests and the Swift style, architecture, localization, and whitespace checks passed.

Earlier baseline acceptance on 2026-11-01 passed 5 focused scenarios each on iPhone 17 Pro and iPad Pro
11-inch (M5), both running 26.3.1, including actual-window title pixels. Native macOS 15.7.4
passed both shortcut-window scenarios and the fixed-summary/system-toolbar-search scenario.
Formatting, architecture, localization, and whitespace checks passed. The Python script suite
passed 34 of 36 tests; the two existing Dock-refresh failures in `test_build_macos_release.py`
also reproduce at the unchanged `c4c46bf` baseline and are outside this UI change.

## All Songs shortcut hit regions

On native macOS 15.7.4, the four All Songs shortcuts rendered normally but did not respond to
pointer clicks. Accessibility activation could still push Artists, and the sidebar route worked.
The horizontal scroll view's native document and its content wrapper were only 32 points tall,
while their button frames occupied y=59 through y=91. The visible buttons therefore fell outside
the ancestors' pointer-hit bounds. Expanding only those native parent frames in the isolated test
process restored pointer navigation; recreating the original page restored the failure.

The source-level comparison moves only `.padding(.top, 12)` from the shortcut HStack to its
containing horizontal ScrollView. This keeps the scroll content below the toolbar safe area and
restores pointer navigation while preserving the same spacing, horizontal scrolling, and typed
NavigationLinks. The production code does not traverse native view trees or impose a fixed height.
All state ownership and navigation responsibilities remain in their existing feature boundaries.

`testAllSongsShortcutsOpenCollectionsAndReturn` clicks each shortcut's center on macOS, checks its
search prompt and generated content, then uses Back to verify the original songs remain available.
On iPhone/iPad it uses native touch and reveals offscreen shortcuts by horizontal scrolling.
`testAllSongsShortcutsInNarrowWindow` repeats the checks after resizing the native Mac window to
700 × 560 points through its border. The original layout fails the new pointer regression at
Artists; moving the padding outside the scroll view passes all four shortcuts.

Validated with the isolated silent hosts on native macOS 15.7.4 (1040 × 740 and 700 × 560),
iPhone 17 Pro simulator (iOS 26.3.1), and iPad Pro 11-inch (M5) simulator (iPadOS 26.3.1).
The focused suites passed 3 desktop scenarios and 2 scenarios on each touch destination, including
empty-library search ownership; the explicit 1040 × 740 desktop rerun also passed. Swift formatting,
architecture boundaries, localization validation, and whitespace checks passed.
