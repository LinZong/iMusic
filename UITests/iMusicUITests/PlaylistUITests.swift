import XCTest

/// Regressions for playlist drafts, filtering, restoration, and permanent deletion.
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
        library.selectTrashTab("Playlists")
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

    /// Cancellation preserves a trashed playlist; confirmation survives relaunch and keeps songs.
    func testPermanentPlaylistDeletionKeepsSongsAndOtherPlaylists() {
        launch()
        navigate("Playlists")
        editor.create("Keep This Playlist")
        editor.create("Delete This Playlist")
        let card = app.element("playlist.open.Delete This Playlist")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        #if os(macOS)
        card.rightClick()
        #else
        card.press(forDuration: 1)
        #endif
        app.element("playlist.delete").interact()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5))
        openTrash()
        library.selectTrashTab("Playlists")
        requestPlaylistDeletion("Delete This Playlist")
        XCTAssertTrue(library.deletionConfirmation.waitForExistence(timeout: 5))
        #if os(macOS)
        app.windows.sheets.buttons["Cancel"].firstMatch.interact()
        #else
        app.alerts.buttons["Cancel"].interact()
        #endif
        XCTAssertTrue(app.text(containing: "Delete This Playlist").exists)
        requestPlaylistDeletion("Delete This Playlist")
        library.deletionConfirmation.interact()
        XCTAssertTrue(app.text(containing: "Delete This Playlist").waitForNonExistence(timeout: 5))
        app.terminate()
        launch(relaunch: true)
        openTrash()
        library.selectTrashTab("Playlists")
        XCTAssertFalse(app.text(containing: "Delete This Playlist").exists)
        navigate("Playlists")
        XCTAssertTrue(app.element("playlist.open.Keep This Playlist").waitForExistence(timeout: 5))
        XCTAssertFalse(card.exists)
        navigate("All Songs")
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        XCTAssertTrue(library.track("UI Beta").exists)
        library.play("UI Alpha")
        player.open()
        player.assertSong("UI Alpha")
        capture("Songs remain playable after permanent playlist deletion")
    }

    /// Trash categories retain separate searches, summaries, and centered category empty states.
    func testTrashTabsKeepSearchCountsAndEmptyStatesScoped() {
        launch()
        navigate("Playlists")
        editor.create("Weekend Trash")
        let card = app.element("playlist.open.Weekend Trash")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        #if os(macOS)
        card.rightClick()
        #else
        card.press(forDuration: 1)
        #endif
        app.element("playlist.delete").interact()
        openTrash()
        XCTAssertTrue(app.text(containing: "UI Trashed").waitForExistence(timeout: 5))
        XCTAssertFalse(app.text(containing: "Weekend Trash").exists)
        let songSearch = app.searchFields["Search Trashed Songs"]
        songSearch.interact()
        songSearch.typeText("Missing song")
        XCTAssertTrue(app.text(containing: "UI Trashed").waitForNonExistence(timeout: 5))
        library.selectTrashTab("Playlists")
        XCTAssertTrue(app.text(containing: "Weekend Trash").waitForExistence(timeout: 5))
        XCTAssertTrue(app.element("trash.playlistSummary").exists)
        XCTAssertFalse(app.element("library.songSummary").exists)
        let playlistSearch = app.searchFields["Search Trashed Playlists"]
        playlistSearch.interact()
        playlistSearch.typeText("Missing playlist")
        XCTAssertTrue(app.text(containing: "Weekend Trash").waitForNonExistence(timeout: 5))
        library.selectTrashTab("Songs")
        XCTAssertEqual(songSearch.value as? String, "Missing song")
        library.clearSearch(songSearch)
        library.selectTrashTab("Playlists")
        XCTAssertEqual(playlistSearch.value as? String, "Missing playlist")
        library.clearSearch(playlistSearch)
        // Leave the native search presentation before exercising row gestures.
        navigate("Home")
        openTrash()
        library.selectTrashTab("Songs")
        library.restoreTrashedTrack("UI Trashed")
        XCTAssertTrue(app.text(containing: "No Deleted Songs").waitForExistence(timeout: 5))
        capture("Songs tab empty while deleted playlists remain")
        library.selectTrashTab("Playlists")
        XCTAssertTrue(app.text(containing: "Weekend Trash").waitForExistence(timeout: 5))
        capture("Deleted playlists tab without song table")
        #if os(macOS)
        app.buttons["trash.playlist.restore"].interact()
        #else
        let row = app.cells.containing(.staticText, identifier: "Weekend Trash").firstMatch
        row.swipeLeft()
        app.buttons["trash.playlist.restore"].interact()
        #endif
        XCTAssertTrue(app.text(containing: "No Deleted Playlists").waitForExistence(timeout: 5))
        capture("Deleted playlists tab empty")
    }

    /// Playlist detail composes its own add/remove actions and preserves library audio records.
    func testPlaylistDetailAddsAndRemovesSongsWithoutDeletingLibraryTracks() {
        launch()
        navigate("Playlists")
        editor.create("Editable Songs")
        app.element("playlist.open.Editable Songs").interact()
        XCTAssertTrue(app.text(containing: "No Music Here Yet").waitForExistence(timeout: 5))
        app.element("playlist.actions").interact()
        app.element("playlist.addSongs").interact()
        let song = app.element("playlistPicker.toggle.UI Alpha.wav")
        XCTAssertTrue(song.waitForExistence(timeout: 5))
        song.interact()
        app.element("playlistPicker.commit").interact()
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        XCTAssertFalse(library.track("UI Beta").exists)
        library.play("UI Alpha")
        #if os(macOS)
        library.showTrackActions("UI Alpha")
        app.windows.menuItems["Remove from Playlist"].interact()
        #else
        let row = app.cells.containing(.button, identifier: "track.play.UI Alpha.wav").firstMatch
        row.swipeLeft()
        app.buttons["Remove from Playlist"].interact()
        #endif
        XCTAssertTrue(app.text(containing: "No Music Here Yet").waitForExistence(timeout: 5))
        navigate("All Songs")
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        XCTAssertTrue(library.track("UI Beta").exists)
        capture("Playlist removal preserves the active library")
    }

    /// Opens the playlist's destructive action using desktop buttons or mobile left swipe.
    private func requestPlaylistDeletion(_ name: String) {
        #if os(iOS)
        let row = app.cells.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        #endif
        app.buttons["trash.playlist.delete"].interact()
    }
}
