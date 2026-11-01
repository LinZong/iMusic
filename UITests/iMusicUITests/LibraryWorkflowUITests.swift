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
        #if os(iOS)
        library.assertContentSearchKeepsTitle("All Songs")
        let rowY = app.element("allSongs.artists").frame.midY
        for identifier in ["artists", "albums", "genres", "favorites"] {
            let shortcut = app.element("allSongs." + identifier)
            XCTAssertEqual(shortcut.frame.midY, rowY, accuracy: 2)
            if #available(iOS 26.0, *) {
                XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44)
                XCTAssertGreaterThanOrEqual(shortcut.frame.width, 44)
            }
        }
        library.assertSearchDecorationIsContinuous()
        if #available(iOS 26.0, *) {
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
    /// Bottom glass statistics clear both the last song and the optional scene mini player.
    func testGlassSummaryFloatsAboveMiniPlayerAndKeepsLastSongReachable() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Requires Liquid Glass.") }
        launch(scenario: "song-scroll")
        navigate("All Songs")
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
        let heading = app.staticTexts["library.songPageTitle"]
        let headingY = heading.frame.minY
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
        XCTAssertEqual(heading.frame.minY, headingY, accuracy: 1)
        list.swipeUp()
        XCTAssertTrue(last.isHittable)
        XCTAssertLessThanOrEqual(last.frame.maxY, summary.frame.minY)
        library.assertSongPageChromeStaysFixed("All Songs")
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

    /// Legacy song pages keep summaries close to search with empty and populated collections.
    func testLegacySongSummarySpacingWithoutFeatureHeader() throws {
        if #available(iOS 26.0, *) { throw XCTSkip("Requires the legacy summary presentation.") }
        defer { XCUIDevice.shared.orientation = .portrait }
        for scenario in ["library", "song-scroll"] {
            launch(scenario: scenario)
            if app.frame.width > 680 {
                // Keep the regular-width sidebar visible while selecting the tested collection.
                XCUIDevice.shared.orientation = .landscapeLeft
            }
            navigate("Favorites")
            XCTAssertEqual(app.staticTexts["library.songPageTitle"].label, "Favorites")
            let summary = app.element("library.songSummary")
            XCTAssertTrue(summary.waitForExistence(timeout: 5))
            capture("Legacy Favorites summary spacing: " + scenario)
            let gap = summary.frame.minY - app.searchFields["Search Songs"].frame.maxY
            XCTAssertGreaterThanOrEqual(gap, 0)
            XCTAssertLessThanOrEqual(
                gap,
                28,
                "Legacy search and summary must not accumulate glass and summary padding."
            )
            let shuffle = app.buttons["Shuffle"]
            XCTAssertGreaterThanOrEqual(shuffle.frame.height, 44)
            XCTAssertGreaterThanOrEqual(shuffle.frame.width, 44)
            if scenario == "library" {
                XCTAssertTrue(app.element("library.emptyState").exists)
            } else {
                XCTAssertTrue(app.element("library.songList").cells.firstMatch.exists)
            }
            app.terminate()
        }
    }

    /// Liquid Glass shortcuts float over scrolling songs while page controls retain their frames.
    func testAllSongsShortcutsFloatAboveScrollingSongs() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Requires Liquid Glass.") }
        launch(scenario: "song-scroll")
        navigate("All Songs")
        let list = app.element("library.songList")
        let shortcuts = app.element("allSongs.shortcuts")
        let summary = app.element("library.songSummaryBar")
        let search = app.searchFields["Search Songs"]
        XCTAssertTrue(shortcuts.waitForExistence(timeout: 5))
        capture("Floating shortcuts before scrolling")
        XCTAssertLessThanOrEqual(
            list.frame.minY,
            shortcuts.frame.minY + 1,
            "The song scroll viewport must extend beneath the floating shortcuts."
        )
        XCTAssertGreaterThanOrEqual(list.cells.firstMatch.frame.minY, shortcuts.frame.maxY)
        XCTAssertLessThanOrEqual(list.frame.minY, search.frame.minY)
        XCTAssertGreaterThan(summary.frame.minY, list.frame.midY)
        let fixed = [
            app.staticTexts["library.songPageTitle"], app.searchFields["Search Songs"],
            app.element("allSongs.artists"), app.element("library.songSummary"),
        ]
        let frames = fixed.map(\.frame)
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65))
        let end = start.withOffset(CGVector(dx: 0, dy: -145))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        for (element, frame) in zip(fixed, frames) {
            XCTAssertEqual(element.frame.minY, frame.minY, accuracy: 1)
            XCTAssertTrue(element.isHittable)
        }
        XCTAssertTrue(
            list.cells.allElementsBoundByIndex.contains { $0.frame.intersects(shortcuts.frame) },
            "Songs must scroll beneath the shortcut capsules."
        )
        XCTAssertTrue(
            list.cells.allElementsBoundByIndex.contains { $0.frame.intersects(search.frame) },
            "Songs must scroll beneath the floating native search field."
        )
        capture("Songs scrolling beneath floating shortcuts")
        library.openAllSongsShortcut("artists")
        XCTAssertTrue(app.searchFields["Search Artists"].waitForExistence(timeout: 5))
        library.backToAllSongs()
        library.assertSongPageChromeStaysFixed("All Songs")
    }

    /// Every song-collection scope shares fixed search without losing its navigation title.
    func testSongCollectionTitlesSurviveSearchEditing() {
        launch(scenario: "song-scroll")
        navigate("All Songs")
        library.assertContentSearchKeepsTitle("All Songs")
        let search = app.searchFields["Search Songs"]
        let shortcutGap = app.element("allSongs.artists").frame.minY - search.frame.maxY
        library.assertSongPageChromeStaysFixed("All Songs")
        XCTAssertTrue(app.element("allSongs.artists").isHittable)
        XCTAssertEqual(
            app.element("allSongs.artists").frame.minY - search.frame.maxY,
            shortcutGap,
            accuracy: 1
        )
        for (shortcut, title) in [
            ("artists", "UI Test Artist"), ("albums", "UI Test Album"),
            ("genres", "UI Test Genre"),
        ] {
            library.openAllSongsShortcut(shortcut)
            let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title))
                .firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.interact()
            library.assertContentSearchKeepsTitle(title)
            library.assertSongPageChromeStaysFixed(title)
            app.navigationBars.buttons.element(boundBy: 0).interact()
            library.backToAllSongs()
        }
        library.openAllSongsShortcut("favorites")
        library.assertContentSearchKeepsTitle("Favorites")
        library.assertSongPageChromeStaysFixed("Favorites")
        library.backToAllSongs()
        openTrash()
        library.assertContentSearchKeepsTitle("Trash", prompt: "Search Trashed Songs")
        library.assertSongHeaderStaysFixedWhileScrolling(prompt: "Search Trashed Songs")
        capture("Song scopes retain titles after fixed content search")
    }

    /// Empty All Songs retains its title, shortcuts, summary, and scoped query during search.
    func testEmptyAllSongsTitleSurvivesSearchEditing() {
        launch(scenario: "empty")
        navigate("All Songs")
        library.assertContentSearchKeepsTitle("All Songs")
        XCTAssertTrue(app.element("allSongs.artists").isHittable)
        XCTAssertTrue(app.element("library.songSummary").isHittable)
        XCTAssertTrue(app.element("library.emptyState").exists)
        capture("Empty All Songs after search editing")
    }

    /// Pulling blank list space cannot move collection titles or any fixed header controls.
    func testSongCollectionChromeStaysFixedWhenDraggingBlankSpace() {
        for scenario in ["empty", "library"] {
            launch(scenario: scenario)
            navigate("All Songs")
            library.assertSongPageChromeStaysFixed("All Songs")
            capture("Fixed collection chrome with " + scenario + " songs")
            app.terminate()
        }
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
