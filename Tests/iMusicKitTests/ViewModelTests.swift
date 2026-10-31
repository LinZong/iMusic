import Observation
import XCTest

@testable import iMusicKit

@MainActor final class ViewModelTests: XCTestCase {
    /// Category switching keeps searches and confirmation drafts scoped to the matching records.
    func testTrashCategoriesKeepQueriesAndConfirmationsIndependent() async throws {
        let fixture = try TestLibrary()
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        var track = fixture.track(title: "Night Song")
        track.deletedAt = Date()
        try app.store.save(track)
        var playlist = Playlist(name: "Weekend Trash", entries: [QueueEntry(trackID: track.id)])
        playlist.deletedAt = Date()
        try app.store.save(playlist)
        await app.library.refresh()
        let trash = TrashViewModel(library: app.library)
        XCTAssertEqual(trash.category, .songs)
        trash.updateSearch("Night", in: .songs)
        trash.category = .playlists
        trash.updateSearch("Weekend", in: .playlists)
        trash.updateSearch("", in: .songs)
        XCTAssertEqual(trash.query(for: .songs), "Night")
        trash.playlists.pendingDeletion = playlist
        trash.category = .playlists
        XCTAssertEqual(trash.playlists.playlists.map(\.id), [playlist.id])
        XCTAssertEqual(trash.songs.rows.map(\.id), [track.id])
        XCTAssertTrue(trash.songs.pendingPermanentDeletion.isEmpty)
        trash.category = .songs
        XCTAssertEqual(trash.query(for: .songs), "Night")
        trash.updateSearch("Missing", in: .songs)
        XCTAssertTrue(trash.songs.rows.isEmpty)
        XCTAssertEqual(trash.playlists.playlists.map(\.id), [playlist.id])
        XCTAssertEqual(trash.playlists.search, "Weekend")
        XCTAssertEqual(trash.playlists.pendingDeletion?.id, playlist.id)
        var restored = playlist
        restored.deletedAt = nil
        try app.store.save(restored)
        await app.library.refresh()
        XCTAssertTrue(trash.playlists.playlists.isEmpty)
        XCTAssertEqual(app.library.deletedTracks.map(\.id), [track.id])
    }

    func testSearchesAndSelectionsAreIsolatedWhileLibraryUpdatesPropagate() async throws {
        let fixture = try TestLibrary()
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        let first = fixture.track(title: "Moonlight")
        let second = fixture.track(title: "Morning")
        try app.store.save(first)
        try app.store.save(second)
        try app.store.save(Playlist(name: "Morning Run", entries: [QueueEntry(trackID: first.id)]))
        await app.library.refresh()
        let songs = SongCollectionViewModel(library: app.library, player: app.player, scope: .all)
        let favorites = SongCollectionViewModel(
            library: app.library,
            player: app.player,
            scope: .favorites
        )
        let playlists = PlaylistCollectionViewModel(
            library: app.library,
            player: app.player
        )
        songs.state.search = "moon"
        songs.state.selected = [first.id]
        playlists.search = "morning"
        XCTAssertEqual(songs.rows.map(\.track.id), [first.id])
        XCTAssertEqual(playlists.items.map(\.name), ["Morning Run"])
        XCTAssertTrue(favorites.state.search.isEmpty)
        XCTAssertTrue(favorites.state.selected.isEmpty)
        XCTAssertEqual(app.library.tracks.count, 2)
        var updated = first
        updated.title = "Sunrise"
        try app.store.save(updated)
        await app.library.refresh()
        XCTAssertTrue(songs.rows.isEmpty)
        XCTAssertEqual(playlists.items.count, 1)
        XCTAssertEqual(songs.state.search, "moon")
    }

    func testDuplicatePlaylistOccurrencesRetainQueueIdentityAndSortedPlayback() async throws {
        let fixture = try TestLibrary()
        let engine = TestPlaybackEngine()
        let url = try fixture.fixture(seconds: 2)
        _ = await fixture.importer.importFiles([url]) { _ in }
        let app = try AppModel(root: fixture.root, engine: engine, integrateWithSystem: false)
        let track = try XCTUnwrap(app.store.tracks().first)
        let entries = [QueueEntry(trackID: track.id), QueueEntry(trackID: track.id)]
        let playlist = Playlist(name: "Duplicates", entries: entries)
        try app.store.save(playlist)
        await app.library.refresh()
        let page = PlaylistDetailViewModel(
            library: app.library,
            player: app.player,
            playlistID: playlist.id
        )
        XCTAssertEqual(page.rows.map(\.id), entries.map(\.id))
        page.play(row: page.rows.last)
        XCTAssertEqual(app.playback.session.entries.map(\.id), entries.map(\.id))
        XCTAssertEqual(app.playback.session.currentID, entries.last?.id)
        XCTAssertEqual(engine.plays.last?.entryID, entries.last?.id)
        app.playback.pause()
    }

    /// Shared list mechanics sort selections and retain stable identities after filtering.
    func testSongListStateFiltersAndSortsSelectedOccurrences() throws {
        let fixture = try TestLibrary()
        let alpha = fixture.track(title: "Alpha")
        let beta = fixture.track(title: "Beta")
        let rows = [SongRowData(id: UUID(), track: beta), SongRowData(id: UUID(), track: alpha)]
        let state = SongListState()
        state.sortOrder = [KeyPathComparator(\.title)]
        let selection = state.selection(Set(rows.map(\.id) + [UUID()]), in: rows)
        XCTAssertEqual(selection.map(\.title), ["Alpha", "Beta"])
        state.search = "alpha"
        XCTAssertEqual(state.filter(rows).map(\.id), [rows[1].id])
        state.search = "missing"
        XCTAssertTrue(state.filter(rows).isEmpty)
    }

    /// Playlist mutations target occurrences and never alter the underlying library songs.
    func testPlaylistEditingPreservesDuplicatesAndRejectsFilteredMoves() async throws {
        let fixture = try TestLibrary()
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        let alpha = fixture.track(title: "Alpha")
        let beta = fixture.track(title: "Beta")
        try app.store.save(alpha)
        try app.store.save(beta)
        let entries = [
            QueueEntry(trackID: beta.id), QueueEntry(trackID: alpha.id),
            QueueEntry(trackID: alpha.id),
        ]
        let playlist = Playlist(name: "Occurrences", entries: entries)
        try app.store.save(playlist)
        await app.library.refresh()
        let page = PlaylistDetailViewModel(
            library: app.library,
            player: app.player,
            playlistID: playlist.id
        )
        XCTAssertTrue(page.canReorder)
        page.state.search = "Alpha"
        XCTAssertFalse(page.canReorder)
        page.move(from: [0], to: 2)
        XCTAssertEqual(try app.store.playlists().first?.entries.map(\.id), entries.map(\.id))
        page.state.search = ""
        page.state.sortOrder = [KeyPathComparator(\.title)]
        XCTAssertFalse(page.canReorder)
        page.move(from: [0], to: 2)
        XCTAssertEqual(try app.store.playlists().first?.entries.map(\.id), entries.map(\.id))
        page.state.sortOrder = []
        page.move(from: [0], to: 3)
        await waitForLibrary {
            page.rows.map(\.id) == [entries[1].id, entries[2].id, entries[0].id]
        }
        XCTAssertEqual(page.rows.map(\.id), [entries[1].id, entries[2].id, entries[0].id])
        page.remove([entries[1].id])
        await waitForLibrary { page.rows.count == 2 }
        XCTAssertEqual(page.rows.map(\.id), [entries[2].id, entries[0].id])
        XCTAssertEqual(app.library.tracks.count, 2)
        page.reverse()
        await waitForLibrary { page.rows.first?.id == entries[0].id }
        XCTAssertEqual(page.rows.map(\.id), [entries[0].id, entries[2].id])
        page.sortByTitle()
        await waitForLibrary { page.rows.first?.track.id == alpha.id }
        XCTAssertEqual(page.rows.map(\.title), ["Alpha", "Beta"])
        page.newName = "Renamed"
        page.saveName()
        await waitForLibrary { page.playlist?.name == "Renamed" }
        XCTAssertEqual(page.playlist?.name, "Renamed")
    }

    /// Shared playback uses visible table order and keeps duplicate entry IDs during shuffle.
    func testPlaylistSortedAndShuffledPlaybackUsesOccurrenceIdentities() async throws {
        let fixture = try TestLibrary()
        let url = try fixture.fixture(seconds: 2)
        _ = await fixture.importer.importFiles([url]) { _ in }
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        var first = try XCTUnwrap(app.store.tracks().first)
        first.title = "AA Sorted First"
        try app.store.save(first)
        var second = first
        second.id = UUID()
        second.title = "ZZ Sorted Last"
        try app.store.save(second)
        let entries = [
            QueueEntry(trackID: second.id), QueueEntry(trackID: first.id),
            QueueEntry(trackID: first.id),
        ]
        let playlist = Playlist(name: "Sorted", entries: entries)
        try app.store.save(playlist)
        await app.library.refresh()
        let page = PlaylistDetailViewModel(
            library: app.library,
            player: app.player,
            playlistID: playlist.id
        )
        page.state.sortOrder = [KeyPathComparator(\.title)]
        page.play(row: page.rows.first)
        XCTAssertEqual(
            app.playback.session.entries.map(\.id),
            [entries[1].id, entries[2].id, entries[0].id]
        )
        page.shuffle()
        XCTAssertEqual(Set(app.playback.session.entries.map(\.id)), Set(entries.map(\.id)))
        XCTAssertTrue(app.playback.session.isShuffled)
        page.state.search = "ZZ Sorted Last"
        page.play(row: page.rows.first)
        XCTAssertEqual(app.playback.session.entries.map(\.id), [entries[0].id])
        XCTAssertFalse(app.playback.session.isShuffled)
        app.playback.pause()
    }

    func testEditorDraftsAreIsolatedAndOnlySaveCommitsChanges() async throws {
        let fixture = try TestLibrary()
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        let track = fixture.track(title: "Original")
        try app.store.save(track)
        let first = TrackEditorViewModel(
            library: app.library,
            preferences: app.preferences,
            original: track
        )
        let second = TrackEditorViewModel(
            library: app.library,
            preferences: app.preferences,
            original: track
        )
        first.draft.title = "Edited"
        first.encodingName = "UTF-8"
        XCTAssertEqual(second.draft.title, "Original")
        XCTAssertEqual(try app.store.track(id: track.id)?.title, "Original")
        first.save()
        XCTAssertEqual(try app.store.track(id: track.id)?.title, "Edited")
        XCTAssertEqual(second.draft.title, "Original")
        await app.library.refresh()
    }

    func testBulkEditPreservesUncheckedFieldsAndPlaylistPickerSelectionIsLocal() async throws {
        let fixture = try TestLibrary()
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        let first = fixture.track(title: "One")
        let second = fixture.track(title: "Two")
        try app.store.save(first)
        try app.store.save(second)
        let playlist = Playlist(name: "Set", entries: [QueueEntry(trackID: first.id)])
        try app.store.save(playlist)
        await app.library.refresh()
        let editor = BatchTrackEditorViewModel(library: app.library, tracks: [first, second])
        editor.artist = "New Artist"
        editor.editArtist = true
        editor.album = "Ignored"
        editor.save()
        XCTAssertEqual(try app.store.track(id: first.id)?.artist, "New Artist")
        XCTAssertEqual(try app.store.track(id: second.id)?.album, second.album)
        let picker = PlaylistSongPickerViewModel(library: app.library, playlist: playlist)
        let otherPicker = PlaylistSongPickerViewModel(library: app.library, playlist: playlist)
        picker.toggle(first.id)
        picker.addSelection()
        XCTAssertTrue(otherPicker.selected.isEmpty)
        XCTAssertEqual(try app.store.playlists().first?.entries.count, 2)
        await app.library.refresh()
    }

    func testSceneNavigationAndPlayerToolStateAreLocalButPlaybackIsShared() throws {
        let fixture = try TestLibrary()
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        let first = app.makeRootViewModel()
        let second = app.makeRootViewModel()
        first.selection = .settings
        XCTAssertEqual(second.selection, .home)
        XCTAssertTrue(first.player.playback === second.player.playback)
        let playerA = NowPlayingViewModel(player: app.player)
        let playerB = NowPlayingViewModel(player: app.player)
        playerA.equalizer = true
        XCTAssertFalse(playerB.equalizer)
    }

    func testPreferencesReloadPersistedValuesWithoutSharingPageSearch() throws {
        let fixture = try TestLibrary()
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        let songs = SongCollectionViewModel(library: app.library, player: app.player, scope: .all)
        songs.state.search = "keep me"
        app.preferences.vinyl = true
        XCTAssertEqual(try app.store.setting("vinyl", as: Bool.self), true)
        try app.store.setSetting("appearance", value: "dark")
        app.preferences.reload()
        XCTAssertEqual(app.preferences.appearance, "dark")
        XCTAssertEqual(songs.state.search, "keep me")
    }

    func testExportStateAndAtomicReplacementAreIndependent() async throws {
        let fixture = try TestLibrary()
        let source = fixture.root.appendingPathComponent("source.json")
        let target = fixture.root.appendingPathComponent("target.json")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: target)
        let first = BackupExportViewModel()
        let second = BackupExportViewModel()
        await first.save(source: source, destination: target)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "new")
        XCTAssertNotNil(first.message)
        XCTAssertNil(second.message)
        XCTAssertFalse(first.saving)
        XCTAssertFalse(second.saving)
    }
    /// Waits for the library's scheduled refresh to publish after synchronous persistence.
    private func waitForLibrary(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "The library did not publish the saved playlist")
    }

}
