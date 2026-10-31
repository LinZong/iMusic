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
