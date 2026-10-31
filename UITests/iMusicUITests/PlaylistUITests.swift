import XCTest

/// Regressions for playlist draft lifetime, filtering, soft deletion, and restoration.
@MainActor final class PlaylistUITests: UITestCase {
    /// Cancelling must not persist a draft or leak its name into the next editor.
    func testCancelledCreationDoesNotPersistOrReuseDraft() {
        launch(scenario: "empty")
        navigate("Playlists")
        editor.open()
        editor.name.interact()
        editor.name.typeText("Discarded Draft")
        app.buttons["Cancel"].interact()
        XCTAssertTrue(app.text(containing: "Nothing Here Yet").waitForExistence(timeout: 5))
        editor.open()
        editor.assertBlankDraft()
        app.buttons["Cancel"].interact()
        app.terminate()
        launch(scenario: "empty", relaunch: true)
        navigate("Playlists")
        XCTAssertTrue(app.text(containing: "Nothing Here Yet").waitForExistence(timeout: 5))
    }

    /// Playlist search filters collection names independently of song-search state.
    func testPlaylistSearchIsScopedToPlaylistNames() {
        launch()
        navigate("Playlists")
        editor.create("Weekend Mix")
        editor.create("Workout Mix")
        let weekend = app.element("playlist.open.Weekend Mix")
        let workout = app.element("playlist.open.Workout Mix")
        XCTAssertTrue(weekend.waitForExistence(timeout: 5))
        XCTAssertTrue(workout.exists)
        let search = app.searchFields["Search Playlists"]
        search.interact()
        search.typeText("Weekend")
        XCTAssertTrue(weekend.exists)
        XCTAssertTrue(workout.waitForNonExistence(timeout: 5))
        library.clearSearch(search)
        navigate("All Songs")
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        XCTAssertTrue(library.track("UI Beta").exists)
        capture("Scoped playlist search")
    }

    /// Deleting a playlist must preserve a recoverable record and allow native restoration.
    func testPlaylistDeletionAndRestoration() {
        launch(scenario: "empty")
        navigate("Playlists")
        editor.create("Recoverable Playlist")
        let card = app.element("playlist.open.Recoverable Playlist")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        #if os(macOS)
        card.rightClick()
        #else
        card.press(forDuration: 1)
        #endif
        app.element("playlist.delete").interact()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        openTrash()
        let title = app.text(containing: "Recoverable Playlist")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        #if os(macOS)
        app.buttons["Restore Playlist"].interact()
        #else
        let row = app.cells.containing(.staticText, identifier: "Recoverable Playlist").firstMatch
        row.swipeLeft()
        app.buttons["Restore Playlist"].interact()
        #endif
        navigate("Playlists")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        capture("Restored playlist")
    }
}
