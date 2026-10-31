import XCTest

/// Cross-platform regressions using production views, models, import, and persistence.
@MainActor final class LibraryUITests: UITestCase {
    /// Verifies empty-state presentation and search ownership on the four primary destinations.
    func testEmptyLibraryAndSearchScope() {
        launch(scenario: "empty")
        XCTAssertTrue(app.text(containing: "Start with your first song").exists)
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        navigate("All Songs")
        XCTAssertTrue(app.searchFields["Search Songs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.text(containing: "No Music Here Yet").exists)
        navigate("Playlists")
        XCTAssertTrue(app.searchFields["Search Playlists"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.text(containing: "Nothing Here Yet").exists)
        navigate("Settings")
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        capture("Empty library and Settings")
    }

    /// Checks scoped song filtering, playlist creation, and persistence across process launches.
    func testSongSearchAndPlaylistPersistence() {
        launch()
        navigate("All Songs")
        let alpha = library.track("UI Alpha")
        let beta = library.track("UI Beta")
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertTrue(beta.exists)
        let search = app.searchFields["Search Songs"]
        search.interact()
        search.typeText("Alpha")
        XCTAssertTrue(alpha.exists)
        XCTAssertTrue(beta.waitForNonExistence(timeout: 5))
        library.clearSearch(search)
        navigate("Playlists")
        app.element("library.add").interact()
        app.element("library.newPlaylist").interact()
        let name = app.textFields["playlist.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let create = app.buttons["playlist.commit"]
        XCTAssertFalse(create.isEnabled, "An empty playlist name must not be submitted.")
        name.interact()
        name.typeText("   ")
        XCTAssertFalse(create.isEnabled, "Whitespace must not enable playlist creation.")
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        name.typeText("UI Regression Playlist")
        XCTAssertEqual(name.value as? String, "UI Regression Playlist")
        XCTAssertTrue(create.isEnabled)
        create.interact()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Regression Playlist'"))
                .firstMatch.waitForExistence(timeout: 5)
        )
        app.terminate()
        launch(relaunch: true)
        navigate("Playlists")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Regression Playlist'"))
                .firstMatch.waitForExistence(timeout: 5)
        )
        capture("Playlist persisted after relaunch")
    }

    /// Repeatedly opens song actions, seeks while paused, and changes tracks without audio output.
    func testPlayerMenusSeekingAndTrackChanges() {
        launch()
        navigate("All Songs")
        library.play("UI Alpha")
        let expand = app.element("miniPlayer.expand")
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        expand.interact()
        let toggle = app.buttons["player.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Pause")
        toggle.interact()
        XCTAssertEqual(toggle.label, "Play")
        let slider = app.sliders["player.seek"]
        XCTAssertTrue(slider.isEnabled)
        slider.setFraction(0.5)
        XCTAssertEqual(toggle.label, "Play", "Seeking while paused must not resume playback.")
        XCTAssertEqual(player.elapsedSeconds, 60, accuracy: 5)
        for _ in 0..<3 {
            app.element("player.songOptions").interact()
            let favorite = library.favoriteAction
            XCTAssertTrue(favorite.waitForExistence(timeout: 3))
            library.assertFavoriteAction(isFavorite: false)
            favorite.interact()
            app.element("player.songOptions").interact()
            library.assertFavoriteAction(isFavorite: true)
            library.favoriteAction.interact()
        }
        XCTAssertEqual(toggle.label, "Play")
        app.buttons["player.next"].interact()
        let metadata = app.descendants(matching: .any)
            .matching(identifier: "player.metadata").firstMatch
        expectation(
            for: NSPredicate(format: "label CONTAINS 'UI Beta' OR value CONTAINS 'UI Beta'"),
            evaluatedWith: metadata
        )
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("Now Playing after menu and seek interactions")
    }

    /// Restores one trashed song, then permanently deletes only the generated test-library copy.
    func testTrashSwipeRestoreAndPermanentDelete() {
        launch()
        openTrash()
        library.restoreTrashedTrack("UI Trashed")
        XCTAssertTrue(app.text(containing: "No Deleted Songs").waitForExistence(timeout: 5))
        navigate("All Songs")
        let restored = library.track("UI Trashed")
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        library.showTrackActions("UI Trashed")
        library.trashAction.interact()
        openTrash()
        library.deleteTrashedTrack("UI Trashed")
        let confirm = library.deletionConfirmation
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.interact()
        XCTAssertTrue(app.text(containing: "No Deleted Songs").waitForExistence(timeout: 10))
        capture("Trash empty after deleting generated fixture")
    }

    /// Verifies the native folder picker can be opened and cancelled without library changes.
    func testLinkFolderPickerCanBeCancelled() {
        launch()
        app.element("library.add").interact()
        app.element("library.linkFolder").interact()
        library.cancelPicker()
        XCTAssertTrue(app.element("library.add").waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
