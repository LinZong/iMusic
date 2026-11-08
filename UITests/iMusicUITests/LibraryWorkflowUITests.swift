import XCTest

/// Additional library workflows beyond the original search and playback smoke scenarios.
@MainActor final class LibraryWorkflowUITests: UITestCase {
    /// Home category cards must keep equal sizes despite different text and song counts.
    func testHomeCategoryCardsHaveEqualDimensions() {
        launch()
        let frames = ["home.artists", "home.albums", "home.favorites"]
            .map { identifier in
                let tile = app.element(identifier)
                XCTAssertTrue(tile.waitForExistence(timeout: 5))
                return tile.frame
            }
        for frame in frames.dropFirst() {
            XCTAssertEqual(frame.width, frames[0].width, accuracy: 1)
            XCTAssertEqual(frame.height, frames[0].height, accuracy: 1)
        }
        capture("Equal Home category cards")
    }

    /// Favorite mutations must filter correctly and survive restarting the host process.
    func testFavoriteFilteringAndPersistence() {
        launch()
        navigate("All Songs")
        library.showTrackActions("UI Alpha")
        library.favoriteAction.interact()
        app.terminate()
        launch(relaunch: true)
        navigate("Favorites")
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        XCTAssertFalse(library.track("UI Beta").exists)
        library.showTrackActions("UI Alpha")
        library.favoriteAction.interact()
        XCTAssertTrue(app.text(containing: "No Music Here Yet").waitForExistence(timeout: 5))
        capture("Favorites empty after removing the generated song")
    }

    /// Native import cancellation must leave the existing generated library unchanged.
    func testImportMusicPickerCanBeCancelled() {
        launch()
        app.element("library.add").interact()
        app.element("library.import").interact()
        library.cancelPicker()
        navigate("All Songs")
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        XCTAssertTrue(library.track("UI Beta").exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    /// Every All Songs shortcut must navigate through an actual pointer click or touch.
    func testAllSongsShortcutsOpenCollectionsAndReturn() {
        launch()
        #if os(macOS)
        library.resizeWindow(width: 1040, height: 740)
        #endif
        assertAllSongsShortcuts()
    }

    #if os(macOS)
    /// Shortcut hit regions must remain valid near the minimum supported desktop width.
    func testAllSongsShortcutsInNarrowWindow() {
        launch()
        library.resizeWindow(width: 700, height: 560)
        assertAllSongsShortcuts()
    }
    #endif

    /// Checks target content and stack return for every shortcut using generated fixtures.
    private func assertAllSongsShortcuts() {
        navigate("All Songs")
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        #if os(macOS)
        library.assertDesktopShortcutsInheritWindowBackground()
        #endif
        #if os(iOS)
        library.assertInitialCollectionNavigation("All Songs")
        library.assertSystemCollectionSearchKeepsTitle("All Songs")
        _ = library.collectionSearch()
        let rowY = app.element("allSongs.artists").frame.midY
        for identifier in ["artists", "albums", "genres", "favorites"] {
            let shortcut = app.element("allSongs." + identifier)
            XCTAssertEqual(shortcut.frame.midY, rowY, accuracy: 2)
            if #available(iOS 26.0, *) {
                XCTAssertGreaterThanOrEqual(shortcut.frame.height, 32)
                XCTAssertLessThan(shortcut.frame.height, 44)
                XCTAssertGreaterThanOrEqual(shortcut.frame.width, 44)
            }
        }
        library.assertSearchDecorationIsContinuous()
        if #available(iOS 26.0, *) {
            let shortcuts = app.scrollViews["allSongs.shortcuts"].firstMatch
            XCTAssertEqual(
                app.element("allSongs.artists").frame.minY - shortcuts.frame.minY,
                12,
                accuracy: 2
            )
            library.assertShortcutDecorationIsContinuous()
        }
        #endif
        capture("All Songs shortcuts")
        let collections = [
            ("artists", "Search Artists", "UI Test Artist"),
            ("albums", "Search Albums", "UI Test Album"),
            ("genres", "Search Genres", "UI Test Genre"),
            ("favorites", "Search Songs", ""),
        ]
        for (identifier, prompt, title) in collections {
            library.openAllSongsShortcut(identifier)
            if identifier == "favorites" { _ = library.collectionSearch() }
            XCTAssertTrue(app.searchFields[prompt].waitForExistence(timeout: 5))
            XCTAssertTrue(app.element("allSongs.artists").waitForNonExistence(timeout: 5))
            if title.isEmpty {
                XCTAssertTrue(app.text(containing: "No Music Here Yet").exists)
            } else {
                let card = app.buttons
                    .matching(
                        NSPredicate(format: "label CONTAINS %@", title)
                    )
                    .firstMatch
                XCTAssertTrue(card.waitForExistence(timeout: 5), app.debugDescription)
            }
            capture("All Songs shortcut " + identifier)
            library.backToAllSongs()
            XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        }
    }

    #if os(iOS)
    /// Songs and playlist grids share first-presentation and search-focus navigation geometry.
    func testSongCollectionSearchMatchesPlaylists() {
        launch(scenario: "navigation-scroll")
        navigate("Playlists")
        let playlistTitleHeight = app.navigationBars.staticTexts["Playlists"].firstMatch.frame
            .height
        let playlists = library.navigationSearchFrames(prompt: "Search Playlists")
        capture("Playlists after native search dismissal")
        navigate("All Songs")
        library.assertInitialCollectionNavigation("All Songs")
        XCTAssertEqual(
            app.navigationBars.staticTexts["All Songs"].firstMatch.frame.height,
            playlistTitleHeight,
            accuracy: 1
        )
        let songs = library.navigationSearchFrames(prompt: "Search Songs")
        XCTAssertEqual(songs.idle.minY, playlists.idle.minY, accuracy: 2)
        XCTAssertEqual(songs.focused.minY, playlists.focused.minY, accuracy: 2)
        if app.frame.width < 600 {
            XCTAssertLessThan(songs.focused.minY, songs.idle.minY - 20)
        }
        library.assertSystemCollectionSearchKeepsTitle("All Songs")
        capture("All Songs after matching native search dismissal")
    }

    /// Repeated native search dismissal restores titles without moving either collection's rows.
    func testScrolledCollectionSearchDismissalKeepsTitles() {
        launch(scenario: "navigation-scroll")
        for (title, prompt) in [("Playlists", "Search Playlists"), ("All Songs", "Search Songs")] {
            navigate(title)
            let scroller =
                title == "All Songs"
                ? app.scrollViews["library.songList"] : app.scrollViews.firstMatch
            scroller.swipeUp()
            let heading = app.navigationBars.staticTexts[title].firstMatch
            let titleFrame = heading.frame
            let prefix = title == "All Songs" ? "track.play." : "playlist.open."
            let anchor = scroller.buttons
                .matching(
                    NSPredicate(format: "identifier BEGINSWITH %@", prefix)
                )
                .allElementsBoundByIndex
                .first {
                    $0.isHittable && $0.frame.minY > app.searchFields[prompt].frame.maxY
                }
            XCTAssertNotNil(anchor)
            let rowFrame = anchor?.frame ?? .zero
            for _ in 0..<3 {
                let search = library.navigationSearchFrames(prompt: prompt)
                if app.frame.width < 600 {
                    XCTAssertLessThan(search.focused.minY, search.idle.minY - 20)
                    XCTAssertEqual(anchor?.frame.minY ?? 0, rowFrame.minY, accuracy: 2)
                }
                library.assertNavigationTitleRestored(title, frame: titleFrame)
            }
            capture(title + " after search dismissal while scrolled")
        }
    }

    /// Blank and no-match queries restore native titles even when search starts mid-scroll.
    func testScrolledCollectionSearchFilteringKeepsTitles() {
        launch(scenario: "navigation-scroll")
        for (title, prompt) in [("Playlists", "Search Playlists"), ("All Songs", "Search Songs")] {
            navigate(title)
            let scroller =
                title == "All Songs"
                ? app.scrollViews["library.songList"] : app.scrollViews.firstMatch
            scroller.swipeUp()
            library.assertSystemCollectionSearchKeepsTitle(title, prompt: prompt)
            capture(title + " after mid-scroll search filtering")
        }
    }

    /// Bottom glass statistics clear both the last song and the optional scene mini player.
    func testGlassSummaryFloatsAboveMiniPlayerAndKeepsLastSongReachable() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Requires Liquid Glass.") }
        launch(scenario: "song-scroll")
        navigate("All Songs")
        library.assertInitialCollectionNavigation("All Songs")
        let list = app.element("library.songList")
        let summary = app.element("library.songSummaryBar")
        let miniPlayer = app.element("miniPlayer.bar")
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertFalse(miniPlayer.exists)
        XCTAssertGreaterThan(summary.frame.minY, list.frame.midY)
        if app.tabBars.firstMatch.exists {
            XCTAssertLessThanOrEqual(summary.frame.maxY, app.tabBars.firstMatch.frame.minY)
        }
        let withoutPlayerY = summary.frame.minY
        let heading = app.navigationBars.staticTexts["All Songs"].firstMatch
        let expandedHeadingHeight = heading.frame.height
        capture("Bottom glass summary without mini player")
        for _ in 0..<8 { list.swipeUp() }
        let last = library.track("UI Scroll 39")
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        XCTAssertTrue(last.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxY, summary.frame.minY)
        XCTAssertEqual(summary.frame.minY, withoutPlayerY, accuracy: 1)
        capture("Last song clears the bottom glass summary")
        last.interact()
        XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(miniPlayer.frame.minX - app.frame.minX, 16)
        XCTAssertGreaterThanOrEqual(app.frame.maxX - miniPlayer.frame.maxX, 16)
        let clearsPlayer = NSPredicate { _, _ in summary.frame.maxY <= miniPlayer.frame.minY }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: clearsPlayer, object: summary)],
                timeout: 5
            ),
            .completed
        )
        XCTAssertGreaterThan(summary.frame.minY, list.frame.midY)
        XCTAssertLessThan(summary.frame.minY, withoutPlayerY)
        if expandedHeadingHeight > 30 {
            XCTAssertLessThan(heading.frame.height, expandedHeadingHeight)
        } else {
            XCTAssertEqual(heading.frame.height, expandedHeadingHeight, accuracy: 1)
        }
        list.swipeUp()
        XCTAssertTrue(last.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxY, summary.frame.minY)
        capture("Bottom glass summary above the mini player")
        let search = app.searchFields["Search Songs"]
        search.interact()
        search.typeText("Missing song\n")
        let placeholder = app.element("library.emptyState")
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(placeholder.frame.maxY, summary.frame.minY)
        XCTAssertLessThanOrEqual(summary.frame.maxY, miniPlayer.frame.minY)
        capture("Empty search content above summary and mini player")
    }

    /// Legacy collection statistics scroll with songs and leave empty content below the controls.
    func testLegacyCollectionSummaryScrollsWithoutFeatureHeader() throws {
        if #available(iOS 26.0, *) { throw XCTSkip("Requires the legacy summary presentation.") }
        defer { XCUIDevice.shared.orientation = .portrait }
        for scenario in ["library", "song-scroll"] {
            launch(scenario: scenario)
            if app.frame.width > 680 {
                // Keep the regular-width sidebar visible while selecting the tested collection.
                XCUIDevice.shared.orientation = .landscapeLeft
            }
            navigate("Favorites")
            library.assertInitialCollectionNavigation("Favorites")
            let search = library.collectionSearch()
            XCTAssertTrue(app.navigationBars.staticTexts["Favorites"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["library.songPageTitle"].exists)
            let summary = app.element("library.songSummary")
            XCTAssertTrue(summary.waitForExistence(timeout: 5))
            capture("Legacy Favorites scrolling summary: " + scenario)
            let bar = app.element("library.songSummaryBar")
            let gap = bar.frame.minY - search.frame.maxY
            XCTAssertGreaterThanOrEqual(gap, 0)
            XCTAssertLessThanOrEqual(summary.frame.minY - bar.frame.minY, 24)
            let shuffle = app.buttons["Shuffle"]
            XCTAssertGreaterThanOrEqual(shuffle.frame.height, 44)
            XCTAssertGreaterThanOrEqual(shuffle.frame.width, 44)
            if scenario == "library" {
                let placeholder = app.element("library.emptyState")
                XCTAssertTrue(placeholder.exists)
                XCTAssertGreaterThanOrEqual(placeholder.frame.minY, bar.frame.maxY)
            } else {
                let list = app.element("library.songList")
                XCTAssertTrue(list.descendants(matching: .any)["library.songSummaryBar"].exists)
                list.swipeUp()
                XCTAssertFalse(summary.isHittable, "Collection statistics must scroll away.")
                list.swipeDown()
                XCTAssertTrue(summary.isHittable)
            }
            app.terminate()
        }
    }

    /// Shortcuts are non-song scrolling content and leave the viewport with actual song rows.
    func testAllSongsShortcutsScrollWithSongs() {
        launch(scenario: "song-scroll")
        navigate("All Songs")
        library.assertInitialCollectionNavigation("All Songs")
        let list = app.element("library.songList")
        let shortcuts = app.scrollViews["allSongs.shortcuts"].firstMatch
        let summary = app.element("library.songSummaryBar")
        let search = app.searchFields["Search Songs"]
        XCTAssertTrue(shortcuts.waitForExistence(timeout: 5))
        capture("Shortcuts inside the song list before scrolling")
        XCTAssertTrue(list.scrollViews["allSongs.shortcuts"].exists)
        let firstSong = library.track("UI Alpha")
        XCTAssertGreaterThanOrEqual(firstSong.frame.minY, shortcuts.frame.maxY)
        XCTAssertTrue(search.isHittable)
        XCTAssertGreaterThanOrEqual(app.element("allSongs.artists").frame.minY, search.frame.maxY)
        if #available(iOS 26.0, *) {
            XCTAssertGreaterThan(summary.frame.minY, list.frame.midY)
        } else {
            XCTAssertGreaterThanOrEqual(summary.frame.minY, shortcuts.frame.maxY)
            XCTAssertLessThanOrEqual(summary.frame.maxY, firstSong.frame.minY)
        }
        let heading = app.navigationBars.staticTexts["All Songs"].firstMatch
        let expandedHeadingHeight = heading.frame.height
        let summaryFrame = summary.frame
        let shortcutY = shortcuts.frame.minY
        let songY = firstSong.frame.minY
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65))
        let end = start.withOffset(CGVector(dx: 0, dy: -45))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertLessThan(shortcuts.frame.minY, shortcutY)
        XCTAssertEqual(
            shortcutY - shortcuts.frame.minY,
            songY - firstSong.frame.minY,
            accuracy: 2,
            "Shortcuts and song rows must share the same vertical content movement."
        )
        list.swipeUp()
        if expandedHeadingHeight > 30 {
            XCTAssertLessThan(heading.frame.height, expandedHeadingHeight)
        } else {
            XCTAssertEqual(heading.frame.height, expandedHeadingHeight, accuracy: 1)
        }
        if #available(iOS 26.0, *) {
            XCTAssertEqual(summary.frame.minY, summaryFrame.minY, accuracy: 1)
        } else {
            XCTAssertFalse(summary.isHittable)
        }
        if #available(iOS 26.0, *) { XCTAssertTrue(search.isHittable) }
        XCTAssertFalse(app.element("allSongs.artists").isHittable)
        capture("Shortcuts scrolled out with songs")
        library.openAllSongsShortcut("artists")
        XCTAssertTrue(app.searchFields["Search Artists"].waitForExistence(timeout: 5))
        library.backToAllSongs()
        library.assertSystemCollectionSearchKeepsTitle("All Songs")
    }

    /// The legacy scrolling shortcut row follows the saved system appearance.
    func testLegacyShortcutsHaveOpaqueAdaptiveBackground() throws {
        if #available(iOS 26.0, *) { throw XCTSkip("Requires the legacy shortcut presentation.") }
        launch(scenario: "song-scroll")
        for (appearance, dark) in [("Light", false), ("Dark", true)] {
            navigate("Settings")
            app.element("settings.appearance").interact()
            app.buttons[appearance].interact()
            navigate("All Songs")
            let list = app.element("library.songList")
            library.assertLegacyShortcutBackgroundIsOpaque(dark: dark)
            capture(appearance + " adaptive scrolling shortcuts")
            list.swipeUp()
            XCTAssertFalse(app.element("allSongs.artists").isHittable)
            library.openAllSongsShortcut("artists")
            library.backToAllSongs()
            library.assertLegacyShortcutBackgroundIsOpaque(dark: dark)
        }
    }

    /// Every song-collection scope uses native search and a collapsible system title.
    func testSongCollectionsUseSystemNavigationAndSurviveSearchEditing() {
        launch(scenario: "song-scroll")
        navigate("All Songs")
        library.assertInitialCollectionNavigation("All Songs")
        library.assertSystemCollectionSearchKeepsTitle("All Songs")
        let search = app.searchFields["Search Songs"]
        library.assertSystemSongCollectionNavigation("All Songs")
        let artistsShortcut = app.element("allSongs.artists")
        XCTAssertTrue(artistsShortcut.isHittable)
        XCTAssertGreaterThanOrEqual(artistsShortcut.frame.minY, search.frame.maxY)
        app.terminate()
        for (shortcut, title) in [
            ("artists", "UI Test Artist"), ("albums", "UI Test Album"),
            ("genres", "UI Test Genre"),
        ] {
            // Each scope gets a fresh automation session on runtimes with snapshot logging faults.
            launch(scenario: "song-scroll")
            navigate("All Songs")
            library.openAllSongsShortcut(shortcut)
            let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title))
                .firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.interact()
            library.assertInitialCollectionNavigation(title)
            library.assertSystemCollectionSearchKeepsTitle(title)
            library.assertSystemSongCollectionNavigation(title)
            app.navigationBars.buttons.element(boundBy: 0).interact()
            library.backToAllSongs()
            app.terminate()
        }
        launch(scenario: "song-scroll")
        navigate("All Songs")
        library.openAllSongsShortcut("favorites")
        library.assertInitialCollectionNavigation("Favorites")
        library.assertSystemCollectionSearchKeepsTitle("Favorites")
        library.assertSystemSongCollectionNavigation("Favorites")
        library.backToAllSongs()
        capture("All song collections retain native navigation")
    }

    /// Switching from native collection search must not change the fixed Trash page contract.
    func testTrashRetainsFixedNavigationAfterLeavingSongCollection() {
        launch(scenario: "song-scroll")
        navigate("All Songs")
        library.assertInitialCollectionNavigation("All Songs")
        openTrash()
        library.assertContentSearchKeepsTitle("Trash", prompt: "Search Trashed Songs")
        library.assertSongHeaderStaysFixedWhileScrolling(prompt: "Search Trashed Songs")
        capture("Trash remains fixed after leaving a native song collection")
    }

    /// Empty All Songs retains its title, shortcuts, summary, and scoped query during search.
    func testEmptyAllSongsTitleSurvivesSearchEditing() {
        launch(scenario: "empty")
        navigate("All Songs")
        library.assertInitialCollectionNavigation("All Songs")
        library.assertSystemCollectionSearchKeepsTitle("All Songs")
        library.assertSystemSongCollectionNavigation("All Songs", canCollapse: false)
        XCTAssertTrue(app.element("allSongs.artists").isHittable)
        XCTAssertTrue(app.element("library.songSummary").isHittable)
        XCTAssertTrue(app.element("library.emptyState").exists)
        let headerBottom: CGFloat
        if #available(iOS 26.0, *) {
            headerBottom = app.scrollViews["allSongs.shortcuts"].frame.maxY
        } else {
            headerBottom = app.element("library.songSummaryBar").frame.maxY
        }
        XCTAssertGreaterThanOrEqual(app.element("library.emptyState").frame.minY, headerBottom)
        capture("Empty All Songs after search editing")
    }

    /// Collection titles settle at their expanded position after native edge scrolling.
    func testSongCollectionTitlesExpandAtNativeScrollBoundary() {
        for (scenario, canCollapse) in [("song-scroll", true), ("empty", false)] {
            launch(scenario: scenario)
            navigate("All Songs")
            library.assertSystemSongCollectionNavigation("All Songs", canCollapse: canCollapse)
            capture("System collection navigation with " + scenario + " songs")
            app.terminate()
        }
    }

    /// Slow gestures repeatedly cross the system title transition without trapping it inline.
    func testSongCollectionTitleReturnsAfterRepeatedSlowDrags() {
        launch(scenario: "song-scroll")
        navigate("All Songs")
        library.assertSlowCollectionTitleTransitions("All Songs")
        capture("All Songs after repeated slow title transitions")
        library.openAllSongsShortcut("favorites")
        library.assertSlowCollectionTitleTransitions("Favorites")
        capture("Favorites after repeated slow title transitions")
    }
    #endif

    /// Artist navigation must preserve generated metadata and open the corresponding songs.
    func testArtistCollectionOpensItsSongs() {
        launch()
        navigate("Artists")
        let artist = app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Test Artist'"))
            .firstMatch
        XCTAssertTrue(artist.waitForExistence(timeout: 5), app.debugDescription)
        artist.interact()
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        XCTAssertTrue(library.track("UI Beta").exists)
        capture("Artist collection songs")
    }
}

#if os(iOS)
/// Touch-platform regressions for shared desktop controls and width-driven layout transitions.
@MainActor final class MiniPlayerUITests: UITestCase {
    /// Rotation changes presentation only; transport modes and favorite state remain shared.
    func testAdaptiveControlsAndPlaybackStateSurviveRotation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        launch()
        navigate("All Songs")
        library.play("UI Alpha")
        let toggle = app.element("miniPlayer.toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.interact()
        XCTAssertEqual(toggle.label, "Play")
        if #available(iOS 26.0, *) {
            player.open()
            app.sliders["player.seek"].setFraction(0.5)
            app.buttons["Collapse Player"].interact()
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            library.assertMiniPlayerProgressIsPainted()
        }
        let compactPortrait = app.frame.width < 680
        if compactPortrait {
            XCTAssertFalse(app.element("miniPlayer.previous").exists)
            XCTAssertFalse(app.element("miniPlayer.favorite").exists)
            captureMiniPlayer("Compact portrait mini player")
        } else {
            assertExpandedControls()
            captureMiniPlayer("Expanded tablet portrait mini player")
        }

        XCUIDevice.shared.orientation = .landscapeLeft
        let repeatMode = app.element("miniPlayer.repeat")
        XCTAssertTrue(repeatMode.waitForExistence(timeout: 5))
        assertExpandedControls()
        XCTAssertEqual(toggle.label, "Play", "Rotation must not resume paused playback.")
        XCTAssertEqual(repeatMode.label, "Play in Order")
        repeatMode.interact()
        XCTAssertEqual(repeatMode.label, "Repeat All")
        repeatMode.interact()
        XCTAssertEqual(repeatMode.label, "Repeat One")
        let shuffle = app.element("miniPlayer.shuffle")
        shuffle.interact()
        XCTAssertEqual(shuffle.label, "Turn Shuffle Off")
        shuffle.interact()
        XCTAssertEqual(shuffle.label, "Turn Shuffle On")
        let favorite = app.element("miniPlayer.favorite")
        favorite.interact()
        XCTAssertEqual(favorite.label, "Remove from Favorites")
        captureMiniPlayer("Expanded landscape mini player")

        XCUIDevice.shared.orientation = .portrait
        if compactPortrait {
            XCTAssertTrue(repeatMode.waitForNonExistence(timeout: 5))
            XCTAssertTrue(toggle.isHittable)
            XCTAssertEqual(toggle.label, "Play")
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(repeatMode.waitForExistence(timeout: 5))
        }
        XCTAssertEqual(repeatMode.label, "Repeat One")
        XCTAssertEqual(favorite.label, "Remove from Favorites")
        app.element("miniPlayer.next").interact()
        let metadata = app.element("miniPlayer.expand")
        let beta = NSPredicate(format: "value CONTAINS %@", "UI Beta")
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: beta, object: metadata)],
            timeout: 5
        )
        XCTAssertEqual(result, .completed)
        app.element("miniPlayer.previous").interact()
        let alpha = NSPredicate(format: "value CONTAINS %@", "UI Alpha")
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: alpha, object: metadata)],
                timeout: 5
            ),
            .completed
        )
        app.element("miniPlayer.queue").interact()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.interact()
        player.open()
        player.assertSong("UI Alpha")
    }

    /// Captures the display because application-bound screenshots can crop rotated windows.
    private func captureMiniPlayer(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// All expanded controls must have distinct, visible touch targets within the current window.
    private func assertExpandedControls() {
        let identifiers = [
            "expand", "favorite", "repeat", "previous", "toggle", "next", "shuffle", "queue",
        ]
        var previousFrame: CGRect?
        for identifier in identifiers {
            let control = app.element("miniPlayer." + identifier)
            XCTAssertTrue(control.waitForExistence(timeout: 5), identifier)
            XCTAssertTrue(control.isHittable, identifier)
            let frame = control.frame
            XCTAssertGreaterThanOrEqual(frame.width, 43.5, identifier)
            XCTAssertGreaterThanOrEqual(frame.height, 43.5, identifier)
            XCTAssertGreaterThanOrEqual(frame.minX, app.frame.minX, identifier)
            XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX, identifier)
            if let previousFrame {
                XCTAssertLessThanOrEqual(previousFrame.maxX, frame.minX + 1, identifier)
            }
            previousFrame = frame
        }
    }
}
#endif
