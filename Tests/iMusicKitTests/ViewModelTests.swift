import Observation
import XCTest

@testable import iMusicKit

@MainActor final class ViewModelTests: XCTestCase {
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
        let songs = SongListViewModel(library: app.library, player: app.player, destination: .songs)
        let favorites = SongListViewModel(
            library: app.library,
            player: app.player,
            destination: .favorites
        )
        let playlists = CollectionViewModel(
            library: app.library,
            player: app.player,
            kind: .playlists
        )
        songs.search = "moon"
        songs.selected = [first.id]
        playlists.search = "morning"
        XCTAssertEqual(songs.rows.map(\.track.id), [first.id])
        XCTAssertEqual(playlists.playlists.map(\.name), ["Morning Run"])
        XCTAssertTrue(favorites.search.isEmpty)
        XCTAssertTrue(favorites.selected.isEmpty)
        XCTAssertEqual(app.library.tracks.count, 2)
        var updated = first
        updated.title = "Sunrise"
        try app.store.save(updated)
        await app.library.refresh()
        XCTAssertTrue(songs.rows.isEmpty)
        XCTAssertEqual(playlists.playlists.count, 1)
        XCTAssertEqual(songs.search, "moon")
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
        let page = SongListViewModel(
            library: app.library,
            player: app.player,
            destination: .playlist(playlist.id)
        )
        XCTAssertEqual(page.rows.map(\.id), entries.map(\.id))
        page.play(row: page.rows.last)
        XCTAssertEqual(app.playback.session.entries.map(\.id), entries.map(\.id))
        XCTAssertEqual(app.playback.session.currentID, entries.last?.id)
        XCTAssertEqual(engine.plays.last?.entryID, entries.last?.id)
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
        let songs = SongListViewModel(library: app.library, player: app.player, destination: .songs)
        songs.search = "keep me"
        app.preferences.vinyl = true
        XCTAssertEqual(try app.store.setting("vinyl", as: Bool.self), true)
        try app.store.setSetting("appearance", value: "dark")
        app.preferences.reload()
        XCTAssertEqual(app.preferences.appearance, "dark")
        XCTAssertEqual(songs.search, "keep me")
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
}
