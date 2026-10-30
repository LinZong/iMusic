import XCTest

@testable import iMusicKit

final class TrashDeletionTests: XCTestCase {
    private func imported(_ library: TestLibrary) async throws -> (URL, Track) {
        let source = try library.fixture(seconds: 1)
        let report = await library.importer.importFiles([source]) { _ in }
        XCTAssertTrue(report.errors.isEmpty)
        return (source, try XCTUnwrap(library.store.tracks().first))
    }
    private func trash(_ track: Track, in library: TestLibrary) throws {
        var value = track
        value.deletedAt = Date()
        try library.store.save(value)
    }
    func testPermanentDeletionRemovesManagedCopyAndUnsharedArtworkButNeverSource() async throws {
        let library = try TestLibrary()
        let (source, original) = try await imported(library)
        let checksum = try MediaVault.digest(source)
        var track = original
        track.artworkName = "own.image"
        track.deletedAt = Date()
        let artwork = try XCTUnwrap(library.vault.artworkURL(track.artworkName))
        try Data([1, 2, 3]).write(to: artwork)
        try library.store.save(track)
        try await library.importer.permanentlyDeleteTracks([track.id])
        try await library.importer.cleanupPermanentlyDeletedFiles()
        XCTAssertFalse(library.vault.contains(track))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artwork.path))
        XCTAssertEqual(try MediaVault.digest(source), checksum)
        XCTAssertNil(try library.store.track(id: track.id))
        XCTAssertTrue(try library.store.tracks(includeDeleted: true).isEmpty)
        XCTAssertTrue(
            try library.store.pending()
                .contains { $0.0.id == track.id.uuidString && $0.0.isPermanentlyDeletedTrack }
        )
        // Idempotent after missing files.
        try await library.importer.cleanupPermanentlyDeletedFiles()
    }
    func testOnlyTrashedSongsCanBeDeletedAndBatchValidationIsAtomic() async throws {
        let library = try TestLibrary()
        let (_, active) = try await imported(library)
        var trashed = library.track(title: "Trashed")
        trashed.deletedAt = Date()
        try library.store.save(trashed)
        XCTAssertThrowsError(try library.store.permanentlyDeleteTracks([trashed.id, active.id]))
        XCTAssertNotNil(try library.store.track(id: trashed.id))
        XCTAssertNotNil(try library.store.track(id: active.id))
        XCTAssertTrue(library.vault.contains(active))
        XCTAssertTrue(try library.store.permanentlyDeletedTracks().isEmpty)
    }
    func testSharedAudioAndArtworkStayUntilLastReferenceIsGone() async throws {
        let library = try TestLibrary()
        let (_, first) = try await imported(library)
        var duplicate = first
        duplicate.id = UUID()
        duplicate.artworkName = "shared.image"
        duplicate.deletedAt = Date()
        var firstCopy = first
        firstCopy.artworkName = duplicate.artworkName
        firstCopy.deletedAt = Date()
        let artwork = try XCTUnwrap(library.vault.artworkURL(duplicate.artworkName))
        try Data([4, 5]).write(to: artwork)
        try library.store.save(firstCopy)
        try library.store.save(duplicate)
        var playlist = Playlist(name: "Deleted cover")
        playlist.deletedAt = Date()
        playlist.artworkName = duplicate.artworkName
        try library.store.save(playlist)
        try library.store.permanentlyDeleteTracks([first.id])
        try library.store.cleanupPermanentlyDeletedFiles(in: library.vault)
        XCTAssertTrue(library.vault.contains(duplicate))  // A restorable duplicate still owns it.
        try library.store.permanentlyDeleteTracks([duplicate.id])
        try library.store.cleanupPermanentlyDeletedFiles(in: library.vault)
        XCTAssertFalse(library.vault.contains(duplicate))
        XCTAssertTrue(FileManager.default.fileExists(atPath: artwork.path))
        playlist.artworkName = nil
        try library.store.save(playlist)
        try library.store.cleanupPermanentlyDeletedFiles(in: library.vault)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artwork.path))
    }
    func testPlaylistReferencesAndPersistedQueueArePrunedIncludingDuplicates() throws {
        let library = try TestLibrary()
        var removed = library.track()
        removed.deletedAt = Date()
        var retained = library.track(title: "Retained")
        retained.assetHash = String(repeating: "b", count: 64)
        try library.store.save(removed)
        try library.store.save(retained)
        let playlist = Playlist(
            name: "Duplicates",
            entries: [
                QueueEntry(trackID: removed.id), QueueEntry(trackID: retained.id),
                QueueEntry(trackID: removed.id),
            ]
        )
        try library.store.save(playlist)
        var deletedPlaylist = playlist
        deletedPlaylist.id = UUID()
        deletedPlaylist.deletedAt = Date()
        try library.store.save(deletedPlaylist)
        var session = PlaybackSession()
        session.replace(with: [removed.id, retained.id, removed.id])
        session.setShuffle(true)
        session.history = session.entries.map(\.id)
        try library.store.setSetting("playback", value: session)
        try library.store.permanentlyDeleteTracks([removed.id])
        XCTAssertEqual(
            try library.store.playlists(includeDeleted: true).map { $0.entries.map(\.trackID) },
            [[retained.id], [retained.id]]
        )
        let saved = try XCTUnwrap(library.store.setting("playback", as: PlaybackSession.self))
        XCTAssertEqual(saved.entries.map(\.trackID), [retained.id])
        XCTAssertEqual(saved.current?.trackID, retained.id)
        XCTAssertEqual(saved.shuffleOrder.count, 1)
        XCTAssertEqual(saved.history.count, 1)
        try library.store.save(playlist)  // A stale editor cannot re-add references to a purged ID.
        XCTAssertEqual(try library.store.playlists().first?.entries.map(\.trackID), [retained.id])
        XCTAssertThrowsError(try library.store.save(removed))
    }
    func testFutureOfflineEditsAndOldBackupCannotResurrectPermanentDeletion() throws {
        let first = try TestLibrary()
        let second = try TestLibrary()
        var track = first.track()
        track.deletedAt = Date()
        try first.store.save(track)
        let old = try first.store.envelopes()
        try second.store.restore(old)
        try first.store.permanentlyDeleteTracks([track.id])
        let tombstone = try XCTUnwrap(first.store.envelopes().first)
        var stale = old[0]
        stale.versions = stale.versions.mapValues {
            FieldVersion(clock: $0.clock + 1_000_000, device: "offline")
        }
        XCTAssertTrue(try tombstone.merged(with: stale).isPermanentlyDeletedTrack)
        XCTAssertEqual(
            try tombstone.merged(with: stale).payload,
            try stale.merged(with: tombstone).payload
        )
        for pending in try first.store.pending() {
            try first.store.acknowledge(id: pending.0.id, generation: pending.1)
        }
        try first.store.merge(stale)
        XCTAssertNil(try first.store.track(id: track.id))
        XCTAssertFalse(try first.store.pending().isEmpty)  // Repair an old client's cloud value.
        try second.store.merge(tombstone)
        try second.store.restore(old)
        XCTAssertTrue(try second.store.tracks(includeDeleted: true).isEmpty)
        XCTAssertThrowsError(
            try second.store.withAvailableTrack(track.id) { _ in
                XCTFail("Late download was accepted")
            }
        )
    }
    func testExplicitReimportCreatesNewIdentityButAutomaticFolderScanDoesNot() async throws {
        let library = try TestLibrary()
        let (source, track) = try await imported(library)
        try trash(track, in: library)
        try library.store.permanentlyDeleteTracks([track.id])
        try library.store.cleanupPermanentlyDeletedFiles(in: library.vault)
        let scan = await library.importer.importFiles([source], skipUnchanged: true) { _ in }
        XCTAssertEqual(scan.imported, 0)
        XCTAssertTrue(try library.store.tracks().isEmpty)
        XCTAssertFalse(library.vault.contains(track))
        let explicit = await library.importer.importFiles([source]) { _ in }
        XCTAssertEqual(explicit.imported, 1)
        let new = try XCTUnwrap(library.store.tracks().first)
        XCTAssertNotEqual(new.id, track.id)
        XCTAssertEqual(new.assetHash, track.assetHash)
        try library.store.merge(
            try XCTUnwrap(library.store.envelopes().first { $0.id == track.id.uuidString })
        )
        try library.store.cleanupPermanentlyDeletedFiles(in: library.vault)
        XCTAssertTrue(library.vault.contains(new))
        XCTAssertNotNil(try library.store.track(id: new.id))
    }
    func testRestartFinishesFileCleanupAfterTombstoneCommitted() async throws {
        let library = try TestLibrary()
        let (source, track) = try await imported(library)
        try trash(track, in: library)
        try library.store.permanentlyDeleteTracks([track.id])
        XCTAssertTrue(library.vault.contains(track))
        let restartedStore = try LibraryStore(
            url: library.root.appendingPathComponent("Library.sqlite")
        )
        let restarted = ImportCoordinator(store: restartedStore, vault: library.vault)
        let errors = await restarted.recover()
        XCTAssertTrue(errors.isEmpty, errors.joined())
        XCTAssertFalse(library.vault.contains(track))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testOldFullBackupCannotRestoreDeletedAudioAndNewFullBackupOmitsIt() async throws {
        let library = try TestLibrary()
        let (_, track) = try await imported(library)
        let backup = BackupService(store: library.store, vault: library.vault)
        let oldZIP = try await backup.export(includeAudio: true)
        defer { try? FileManager.default.removeItem(at: oldZIP) }
        try trash(track, in: library)
        try library.store.permanentlyDeleteTracks([track.id])
        try library.store.cleanupPermanentlyDeletedFiles(in: library.vault)
        let missing = try await backup.restore(from: oldZIP)
        XCTAssertEqual(missing, 0)
        XCTAssertTrue(try library.store.tracks(includeDeleted: true).isEmpty)
        XCTAssertFalse(library.vault.contains(track))
        let newZIP = try await backup.export(includeAudio: true)
        defer { try? FileManager.default.removeItem(at: newZIP) }
        let other = try TestLibrary()
        let restore = BackupService(store: other.store, vault: other.vault)
        let restoredMissing = try await restore.restore(from: newZIP)
        XCTAssertEqual(restoredMissing, 0)
        XCTAssertTrue(try other.store.tracks(includeDeleted: true).isEmpty)
        XCTAssertTrue(try other.store.wasPermanentlyDeleted(id: track.id))
    }
    func testCleanupNeverFollowsSubstitutedDirectoryAndLeafSymlinkNeverDeletesSource() async throws
    {
        let library = try TestLibrary()
        let (source, track) = try await imported(library)
        let managed = try library.vault.url(for: track)
        let checksum = try MediaVault.digest(source)
        try FileManager.default.removeItem(at: managed)
        try FileManager.default.createSymbolicLink(at: managed, withDestinationURL: source)
        try trash(track, in: library)
        try library.store.permanentlyDeleteTracks([track.id])
        try library.store.cleanupPermanentlyDeletedFiles(in: library.vault)
        XCTAssertEqual(try MediaVault.digest(source), checksum)
        let outside = library.root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let outsideCopy = outside.appendingPathComponent(managed.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: outsideCopy)
        try FileManager.default.removeItem(at: library.vault.media)
        try FileManager.default.createSymbolicLink(
            at: library.vault.media,
            withDestinationURL: outside
        )
        XCTAssertThrowsError(try library.store.cleanupPermanentlyDeletedFiles(in: library.vault))
        XCTAssertEqual(try MediaVault.digest(outsideCopy), checksum)
        XCTAssertNil(library.vault.artworkURL(""))
        XCTAssertNil(library.vault.artworkURL("\0"))
    }
}

@MainActor final class TrashPlaybackTests: XCTestCase {
    func testDeletingCurrentTrackInvalidatesPendingDownloadAndKeepsRemainingSongPaused() throws {
        let library = try TestLibrary()
        let removed = library.track(title: "First")
        let retained = library.track(title: "Second")
        try library.store.save(removed)
        try library.store.save(retained)
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: TestPlaybackEngine()
        )
        var token: UUID?
        playback.resolveMissing = { _, value in token = value }
        playback.play([removed, retained])
        let obsolete = try XCTUnwrap(token)
        playback.removeTracks([removed.id])
        playback.completedDownload(token: obsolete, error: MusicError.missingFile)
        XCTAssertEqual(playback.track?.id, retained.id)
        XCTAssertEqual(playback.status, .paused)
        XCTAssertEqual(playback.session.entries.map(\.trackID), [retained.id])
    }
}
