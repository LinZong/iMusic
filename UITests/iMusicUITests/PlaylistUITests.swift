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

    #if os(macOS)
    /// Desktop search stays in the upper-right toolbar while the table scrolls below its summary.
    func testDesktopPlaylistSummaryStaysFixedWithToolbarSearch() {
        launch(scenario: "playlist-scroll")
        navigate("Playlists")
        app.element("playlist.open.UI Scroll Playlist").interact()
        let summary = app.element("library.songSummary")
        let search = app.searchFields["Search Songs"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable)
        XCTAssertLessThan(search.frame.maxY, summary.frame.minY)
        XCTAssertGreaterThan(search.frame.midX, app.windows.firstMatch.frame.midX)
        let y = summary.frame.minY
        let table = app.outlines
            .containing(.staticText, identifier: "track.title.UI Alpha.wav").firstMatch
        XCTAssertTrue(table.exists)
        let firstRow = table.descendants(matching: .outlineRow).firstMatch
        let firstRowY = firstRow.frame.minY
        table.scroll(byDeltaX: 0, deltaY: -500)
        XCTAssertLessThan(firstRow.frame.minY, firstRowY - 40)
        XCTAssertTrue(summary.isHittable)
        XCTAssertEqual(summary.frame.minY, y, accuracy: 1)
        search.interact()
        search.typeText("Alpha")
        XCTAssertTrue(library.track("UI Alpha").exists)
        XCTAssertFalse(library.track("UI Beta").exists)
        library.clearSearch(search)
        XCTAssertTrue(library.track("UI Beta").waitForExistence(timeout: 5))
        capture("Desktop toolbar search and fixed playlist summary")
    }
    #endif

    #if os(iOS)
    /// Native search decoration must have room before the song list paints its fixed summary.
    func testSongPageSearchDecorationHasRoomToFade() {
        launch(scenario: "playlist-scroll")
        navigate("Playlists")
        app.element("playlist.open.UI Scroll Playlist").interact()
        capture("Song-page search decoration before scrolling")
        assertSearchDecorationHasRoom(list: app.element("library.songList"))
        library.assertSearchDecorationIsContinuous()
        library.assertSongPageChromeStaysFixed("UI Scroll Playlist")
        library.assertContentSearchKeepsTitle("UI Scroll Playlist")
        library.assertSearchDecorationIsContinuous()
        capture("Song-page search decoration after scrolling and search")
    }

    /// Picker search decoration fades against the native list surface without an opaque band.
    func testSongPickerSearchDecorationHasRoomToFade() {
        launch(scenario: "playlist-scroll")
        navigate("Playlists")
        app.element("playlist.open.UI Scroll Playlist").interact()
        app.element("playlist.actions").interact()
        app.element("playlist.addSongs").interact()
        let list = app.element("playlistPicker.songList")
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        capture("Song-picker search decoration before filtering")
        library.assertSearchDecorationIsContinuous()
        library.assertContentSearchKeepsTitle("Add to “UI Scroll Playlist”")
        library.assertSearchDecorationIsContinuous()
        capture("Song-picker search decoration after filtering")
        app.element("playlistPicker.toggle.UI Alpha.wav").interact()
        app.element("playlistPicker.commit").interact()
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
    }

    /// Glass search floats inside the viewport while older systems keep the search above it.
    private func assertSearchDecorationHasRoom(list: XCUIElement) {
        let search = app.searchFields.matching(NSPredicate(format: "label == 'Search Songs'"))
            .allElementsBoundByIndex
            .last(where: { $0.isHittable })
        guard let search else {
            XCTFail("The active page must expose its own search field.")
            return
        }
        if #available(iOS 26.0, *) {
            XCTAssertLessThanOrEqual(list.frame.minY, search.frame.minY)
            XCTAssertGreaterThanOrEqual(list.cells.firstMatch.frame.minY, search.frame.maxY + 12)
        } else {
            XCTAssertGreaterThanOrEqual(list.frame.minY, search.frame.maxY)
        }
    }

    /// The shared page fixes its large heading, search, and summary while occurrences scroll.
    func testPlaylistSearchAndSummaryStayFixedWhileSongsScroll() {
        launch(scenario: "playlist-scroll")
        navigate("Playlists")
        app.element("playlist.open.UI Scroll Playlist").interact()
        let list = app.element("library.songList")
        let summary = app.element("library.songSummary")
        let search = app.searchFields["Search Songs"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let navigation = app.navigationBars.element(boundBy: app.navigationBars.count - 1)
        let heading = app.staticTexts["library.songPageTitle"]
        XCTAssertEqual(heading.label, "UI Scroll Playlist")
        XCTAssertGreaterThan(heading.frame.height, 35)
        let fixed = [heading, search, summary]
        let fixedFrames = fixed.map(\.frame)
        let summaryGap = summary.frame.minY - search.frame.maxY
        XCTAssertFalse(
            list.cells.containing(.staticText, identifier: "library.songSummary")
                .firstMatch.exists
        )
        let firstRowID = list.cells.firstMatch.identifier
        let firstRowY = list.cells.firstMatch.frame.minY
        list.swipeUp()
        for (element, frame) in zip(fixed, fixedFrames) {
            XCTAssertEqual(element.frame.minY, frame.minY, accuracy: 1)
            XCTAssertEqual(element.frame.height, frame.height, accuracy: 1)
        }
        XCTAssertTrue(summary.isHittable)
        XCTAssertTrue(search.isHittable)
        XCTAssertEqual(summary.frame.minY - search.frame.maxY, summaryGap, accuracy: 1)
        // iPad accessibility may exclude the expanded large-title region from the bar frame.
        XCTAssertGreaterThanOrEqual(search.frame.minY, navigation.frame.maxY)
        XCTAssertTrue(
            list.cells.firstMatch.identifier != firstRowID
                || abs(list.cells.firstMatch.frame.minY - firstRowY) > 5
        )
        capture("Playlist fixed search and summary after scrolling songs")
        list.swipeDown()
        list.swipeDown()
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        for (element, frame) in zip(fixed, fixedFrames) {
            XCTAssertEqual(element.frame.minY, frame.minY, accuracy: 1)
            XCTAssertEqual(element.frame.height, frame.height, accuracy: 1)
        }
        XCTAssertEqual(summary.frame.minY - search.frame.maxY, summaryGap, accuracy: 1)
        // iPad accessibility may exclude the expanded large-title region from the bar frame.
        XCTAssertGreaterThanOrEqual(search.frame.minY, navigation.frame.maxY)
        library.assertContentSearchKeepsTitle("UI Scroll Playlist")
        capture("Playlist fixed header after pull-down and search")
    }

    /// Empty/search layouts stay centered and summary buttons do not acquire row-wide actions.
    func testPlaylistSummaryActionsEmptyStatesAndReordering() {
        launch()
        navigate("Playlists")
        editor.create("Summary Controls")
        app.element("playlist.open.Summary Controls").interact()
        assertSongPlaceholderClearOfFixedSummary()
        let summaryRow = app.element("library.songSummaryBar")
        for title in ["Play", "Shuffle"] {
            let action = summaryRow.buttons[title]
            XCTAssertFalse(action.isEnabled)
            XCTAssertGreaterThanOrEqual(action.frame.width.rounded(), 44)
            XCTAssertGreaterThanOrEqual(action.frame.height.rounded(), 44)
        }
        library.assertSongPageChromeStaysFixed("Summary Controls")
        app.element("playlist.actions").interact()
        app.element("playlist.addSongs").interact()
        library.assertContentSearchKeepsTitle("Add to “Summary Controls”")
        app.element("playlistPicker.toggle.UI Alpha.wav").interact()
        app.element("playlistPicker.toggle.UI Beta.wav").interact()
        app.element("playlistPicker.commit").interact()
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        library.assertSongPageChromeStaysFixed("Summary Controls")
        capture("Short playlist restored after whitespace pull-down")
        let search = app.searchFields["Search Songs"]
        search.interact()
        search.typeText("Missing song")
        XCTAssertTrue(library.track("UI Alpha").waitForNonExistence(timeout: 5))
        assertSongPlaceholderClearOfFixedSummary()
        library.clearSearch(search)
        XCTAssertTrue(library.track("UI Alpha").waitForExistence(timeout: 5))
        app.buttons["Edit"].interact()
        let handles = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reorder'"))
        XCTAssertEqual(handles.count, 2, "Only songs may expose reorder handles.")
        let first = handles.element(boundBy: 0)
        let second = handles.element(boundBy: 1)
        let origin = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.5))
        origin.press(forDuration: 0.5, thenDragTo: destination)
        app.buttons["Done"].interact()
        XCTAssertGreaterThan(
            library.track("UI Alpha").frame.midY,
            library.track("UI Beta").frame.midY
        )
        summaryRow.buttons["Play"].interact()
        // The compact root footer is accessed from a root tab, outside the pushed detail page.
        navigate("All Songs")
        player.open()
        player.assertSong("UI Beta")
        XCTAssertTrue(app.buttons["Turn Shuffle On"].exists, "Play must not trigger Shuffle.")
        app.buttons["Collapse Player"].interact()
        navigate("Playlists")
        let playlist = app.element("playlist.open.Summary Controls")
        if playlist.exists { playlist.interact() }
        summaryRow.buttons["Shuffle"].interact()
        navigate("All Songs")
        player.open()
        XCTAssertTrue(app.buttons["Turn Shuffle Off"].exists)
        capture("Playlist summary controls preserve occurrence editing and independent actions")
    }

    /// Empty and unmatched messages occupy content space clear of either fixed summary position.
    private func assertSongPlaceholderClearOfFixedSummary() {
        let placeholder = app.element("library.emptyState")
        XCTAssertTrue(placeholder.waitForExistence(timeout: 5))
        let summary = app.element("library.songSummary")
        if #available(iOS 26.0, *) {
            XCTAssertLessThanOrEqual(placeholder.frame.maxY, summary.frame.minY)
        } else {
            XCTAssertGreaterThan(placeholder.frame.minY, summary.frame.maxY)
        }
        XCTAssertEqual(app.element("library.songList").cells.count, 0)
        XCTAssertTrue(summary.isHittable)
        capture("Song placeholder in content area clear of the fixed summary")
    }
    #endif

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
