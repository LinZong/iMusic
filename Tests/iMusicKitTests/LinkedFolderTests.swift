import Foundation
import XCTest
import ZIPFoundation

@testable import iMusicKit

final class LinkedFolderTests: XCTestCase {
    private func link(_ library: TestLibrary, file: URL) async throws -> Track {
        try await library.importer.addFolder(file.deletingLastPathComponent())
        let errors = await library.importer.scanFolders { _ in }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
        return try XCTUnwrap(library.store.tracks().first)
    }

    func testAdmissionDoesNotCopyAudioAndPreservesSource() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        let bytes = try Data(contentsOf: file)
        let track = try await link(library, file: file)
        XCTAssertTrue(track.isLinked)
        XCTAssertNil(track.assetHash)
        XCTAssertEqual(track.duration, 0.3, accuracy: 0.001)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: library.vault.media.path),
            []
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: library.vault.staging.path),
            []
        )
        XCTAssertThrowsError(try library.vault.url(for: track))
        let prepared = try await PreparedSourceAudio.prepare(track: track, store: library.store)
        XCTAssertEqual(prepared.url.standardizedFileURL, file.standardizedFileURL)
    }

    func testRestartAndFileRenamePreserveIdentityAndUserEdits() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        var track = try await link(library, file: file)
        track.title = "User title"
        track.isFavorite = true
        try library.store.save(track)
        let renamed = file.deletingLastPathComponent().appendingPathComponent("Renamed.wav")
        try FileManager.default.moveItem(at: file, to: renamed)
        let reopened = try LibraryStore(url: library.root.appendingPathComponent("Library.sqlite"))
        let importer = ImportCoordinator(store: reopened, vault: library.vault)
        let errors = await importer.scanFolders { _ in }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
        let updated = try XCTUnwrap(reopened.tracks().first)
        XCTAssertEqual(try reopened.tracks().count, 1)
        XCTAssertEqual(updated.id, track.id)
        XCTAssertEqual(updated.title, "User title")
        XCTAssertTrue(updated.isFavorite)
        XCTAssertEqual(updated.linkedSource?.relativePath, "Renamed.wav")
        let prepared = try await PreparedSourceAudio.prepare(track: updated, store: reopened)
        XCTAssertEqual(prepared.url.standardizedFileURL, renamed.standardizedFileURL)
    }

    func testRootRenameResolvesThroughBookmark() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        let track = try await link(library, file: file)
        let moved = library.root.appendingPathComponent("Moved source")
        try FileManager.default.moveItem(at: file.deletingLastPathComponent(), to: moved)
        let errors = await library.importer.scanFolders { _ in }
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
        XCTAssertEqual(try library.store.tracks().map(\.id), [track.id])
        let audio = try await PreparedSourceAudio.prepare(track: track, store: library.store)
        XCTAssertEqual(
            audio.url.deletingLastPathComponent().standardizedFileURL,
            moved.standardizedFileURL
        )
    }

    func testIdenticalFilesAreDistinctReferencesAndUnchangedScanIsIdempotent() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        try FileManager.default.copyItem(
            at: file,
            to: file.deletingLastPathComponent().appendingPathComponent("Copy.wav")
        )
        _ = try await link(library, file: file)
        let before = try library.store.tracks()
        XCTAssertEqual(before.count, 2)
        _ = await library.importer.scanFolders { _ in }
        XCTAssertEqual(Set(try library.store.tracks().map(\.id)), Set(before.map(\.id)))
        XCTAssertEqual(try library.store.linkedBindings().count, 2)
    }

    func testMissingSourceRetainsMetadataAndFailsWithoutManagedFallback() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        let track = try await link(library, file: file)
        try FileManager.default.removeItem(at: file)
        _ = await library.importer.scanFolders { _ in }
        XCTAssertNotNil(try library.store.track(id: track.id))
        XCTAssertEqual(try library.store.linkedBindings().first?.state, .missing)
        do {
            _ = try await PreparedSourceAudio.prepare(track: track, store: library.store)
            XCTFail("A deleted original must not resolve to managed or cloud audio")
        } catch {}
    }

    func testSamePathReplacementDoesNotHijackOldSong() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        let track = try await link(library, file: file)
        let replacement = try library.fixture(name: "Replacement.wav", seconds: 0.6)
        try FileManager.default.setAttributes(
            [.creationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: replacement.path
        )
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: replacement, to: file)
        _ = await library.importer.scanFolders { _ in }
        XCTAssertEqual(
            try XCTUnwrap(library.store.track(id: track.id)).duration,
            0.3,
            accuracy: 0.001
        )
        XCTAssertEqual(try library.store.tracks().count, 2)
        do {
            _ = try await PreparedSourceAudio.prepare(track: track, store: library.store)
            XCTFail("A new file at the old path must not silently replace the original")
        } catch {}
    }

    func testPermanentDeletionOnlyRemovesLibraryEntryAndNeverReimportsTombstone() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        var track = try await link(library, file: file)
        let bytes = try Data(contentsOf: file)
        track.deletedAt = Date()
        try library.store.save(track)
        try await library.importer.permanentlyDeleteTracks([track.id])
        try await library.importer.cleanupPermanentlyDeletedFiles()
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        _ = await library.importer.scanFolders { _ in }
        XCTAssertTrue(try library.store.tracks(includeDeleted: true).isEmpty)
        XCTAssertEqual(try library.store.permanentlyDeletedTracks().map(\.id), [track.id])
    }

    func testFullBackupExcludesOriginalAudioAndDevicePermissionsAndCanRelink() async throws {
        let original = try TestLibrary()
        let file = try original.fixture()
        let track = try await link(original, file: file)
        let backup = BackupService(store: original.store, vault: original.vault)
        let zip = try await backup.export(includeAudio: true)
        defer { try? FileManager.default.removeItem(at: zip) }
        let archive = try Archive(url: zip, accessMode: .read)
        XCTAssertFalse(archive.contains { $0.path.hasPrefix("Media/") })
        let destination = try TestLibrary()
        let restore = BackupService(store: destination.store, vault: destination.vault)
        let missing = try await restore.restore(from: zip)
        XCTAssertEqual(missing, 1)
        XCTAssertNil(try destination.store.setting("folders", as: [FolderSource].self))
        XCTAssertTrue(try destination.store.linkedBindings().isEmpty)
        let restored = try XCTUnwrap(destination.store.track(id: track.id))
        XCTAssertEqual(restored, track)
        let reference = try XCTUnwrap(track.linkedSource)
        try await destination.importer.addFolder(
            file.deletingLastPathComponent(),
            replacing: reference.folderID
        )
        _ = await destination.importer.scanFolders { _ in }
        XCTAssertEqual(try destination.store.tracks().map(\.id), [track.id])
        _ = try await PreparedSourceAudio.prepare(track: restored, store: destination.store)
    }

    func testPartialAdmissionIsRecoverableAndDoesNotCountFailedAudio() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        let bad = file.deletingLastPathComponent().appendingPathComponent("Invalid.mp3")
        try Data("not audio".utf8).write(to: bad)
        try await library.importer.addFolder(file.deletingLastPathComponent())
        let errors = await library.importer.scanFolders { _ in }
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(try library.store.tracks().count, 1)
        XCTAssertEqual(try library.store.linkedBindings().filter { $0.state == .failed }.count, 1)
        let importer = ImportCoordinator(store: library.store, vault: library.vault)
        _ = await importer.scanFolders { _ in }
        XCTAssertEqual(try library.store.tracks().count, 1)
        XCTAssertEqual(try library.store.linkedBindings().count, 2)
    }

    func testRevokedFolderCannotCommitLateMetadata() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        let track = try await link(library, file: file)
        let binding = try XCTUnwrap(library.store.linkedBindings().first)
        try library.store.setSetting("folders", value: [FolderSource]())
        XCTAssertThrowsError(try library.store.commitLinkedTrack(track, item: binding))
        do {
            _ = try await PreparedSourceAudio.prepare(track: track, store: library.store)
            XCTFail("Unlinking must revoke future opens on this device")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testLinkingTheSameFolderTwiceDoesNotDuplicateSongs() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        let track = try await link(library, file: file)
        try await library.importer.addFolder(file.deletingLastPathComponent())
        _ = await library.importer.scanFolders { _ in }
        XCTAssertEqual(try library.store.tracks().map(\.id), [track.id])
        XCTAssertEqual(try library.store.setting("folders", as: [FolderSource].self)?.count, 1)
    }

    func testSourceMetadataRefreshPreservesEditedTagsArtworkAndPlaylistIdentity() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        var track = try await link(library, file: file)
        track.title = "Edited title"
        track.artworkName = "user-cover.image"
        track.discNumber = 3
        try library.store.save(track)
        let playlist = Playlist(name: "References", entries: [QueueEntry(trackID: track.id)])
        try library.store.save(playlist)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: file.path
        )
        _ = await library.importer.scanFolders { _ in }
        let updated = try XCTUnwrap(library.store.track(id: track.id))
        XCTAssertEqual(updated.title, track.title)
        XCTAssertEqual(updated.artworkName, track.artworkName)
        XCTAssertEqual(updated.discNumber, 3)
        XCTAssertEqual(try library.store.playlists().first?.entries.first?.trackID, track.id)
    }

    func testAutomaticRetriesAreBoundedAndExplicitRetryResetsTheBudget() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        try Data("invalid".utf8)
            .write(
                to: file.deletingLastPathComponent().appendingPathComponent("Bad.mp3")
            )
        try await library.importer.addFolder(file.deletingLastPathComponent())
        for _ in 0..<5 { _ = await library.importer.scanFolders { _ in } }
        let failed = try XCTUnwrap(library.store.linkedBindings().first { $0.state == .failed })
        XCTAssertEqual(failed.attempts, 3)
        _ = await library.importer.scanFolders(retryFailures: true) { _ in }
        XCTAssertEqual(
            try library.store.linkedBinding(id: failed.id, folderID: failed.folderID)?.attempts,
            1
        )
    }

    @MainActor func testBackgroundUnregistersPresenterAndCoordinatedDeletionStopsPlayback()
        async throws
    {
        let library = try TestLibrary()
        let file = try library.fixture(seconds: 4)
        let track = try await link(library, file: file)
        let engine = TestPlaybackEngine()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: engine
        )
        playback.play([track])
        for _ in 0..<100 where engine.plays.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        playback.setSourceObservation(active: false)
        XCTAssertFalse(NSFileCoordinator.filePresenters.contains { $0.presentedItemURL == file })
        XCTAssertEqual(playback.status, .playing)
        playback.setSourceObservation(active: true)
        let removed = try await SourceAccess.perform { _ in
            var error: NSError?
            var removed = false
            NSFileCoordinator()
                .coordinate(writingItemAt: file, options: .forDeleting, error: &error) { url in
                    removed = (try? FileManager.default.removeItem(at: url)) != nil
                }
            if let error { throw error }
            return removed
        }
        XCTAssertTrue(removed)
        XCTAssertEqual(playback.status, .paused)
        XCTAssertNotNil(playback.error)
        XCTAssertNotNil(try library.store.track(id: track.id))
    }

    func testExplicitFileRepairPreservesSongIdentityAfterAnUnrecoverableMove() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        var track = try await link(library, file: file)
        track.title = "Keep my title"
        track.isFavorite = true
        try library.store.save(track)
        try FileManager.default.removeItem(at: file)
        _ = await library.importer.scanFolders { _ in }
        let replacement = try library.fixture(name: "Different name.wav", seconds: 0.7)
        try await library.importer.locateLinkedFile(replacement, trackID: track.id)
        let repaired = try XCTUnwrap(library.store.track(id: track.id))
        XCTAssertEqual(repaired.id, track.id)
        XCTAssertEqual(repaired.title, track.title)
        XCTAssertTrue(repaired.isFavorite)
        XCTAssertEqual(repaired.duration, 0.7, accuracy: 0.001)
        let prepared = try await PreparedSourceAudio.prepare(track: repaired, store: library.store)
        XCTAssertEqual(
            prepared.url.resolvingSymlinksInPath(),
            replacement.resolvingSymlinksInPath()
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: library.vault.media.path),
            []
        )
    }

    func testRelinkingInvalidatesAnOlderScanGeneration() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        let track = try await link(library, file: file)
        let binding = try XCTUnwrap(library.store.linkedBindings().first)
        try await library.importer.addFolder(
            file.deletingLastPathComponent(),
            replacing: binding.folderID
        )
        XCTAssertThrowsError(try library.store.commitLinkedTrack(track, item: binding))
        _ = await library.importer.scanFolders { _ in }
        XCTAssertEqual(try library.store.tracks().map(\.id), [track.id])
    }

    func testRealM4ACoverIsReadDirectlyWithoutCreatingManagedAudio() async throws {
        guard let path = ProcessInfo.processInfo.environment["IMUSIC_LINKED_FIXTURE"] else {
            throw XCTSkip("Set IMUSIC_LINKED_FIXTURE to exercise a real external M4A file.")
        }
        let library = try TestLibrary()
        let url = URL(fileURLWithPath: path)
        let before = try MediaVault.digest(url)
        let track = try await SourceAccess.perform { operation in
            try operation.read(url) { readable in
                try LinkedMetadataPipeline.parse(
                    readable,
                    id: UUID(),
                    reference: LinkedAudioReference(
                        folderID: UUID(),
                        folderName: "Fixture",
                        relativePath: url.lastPathComponent
                    ),
                    vault: library.vault,
                    previous: nil
                )
            }
        }
        XCTAssertTrue(track.isLinked)
        XCTAssertGreaterThan(track.duration, 0)
        XCTAssertGreaterThan(track.sampleRate, 0)
        let artwork = try XCTUnwrap(library.vault.artworkURL(track.artworkName))
        XCTAssertGreaterThan(try Data(contentsOf: artwork).count, 0)
        XCTAssertEqual(try MediaVault.digest(url), before)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: library.vault.media.path),
            []
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: library.vault.staging.path),
            []
        )
    }

    @MainActor func testLibraryAvailabilityRejectsAnObsoleteAuthorizationRevision() async throws {
        let library = try TestLibrary()
        let file = try library.fixture()
        let track = try await link(library, file: file)
        let app = try AppModel(
            root: library.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        await app.library.refresh()
        XCTAssertTrue(app.library.availableTrackIDs.contains(track.id))
        var folders = try XCTUnwrap(library.store.setting("folders", as: [FolderSource].self))
        folders[0].bindingGeneration = UUID()
        try library.store.setSetting("folders", value: folders)
        await app.library.refresh()
        XCTAssertFalse(app.library.availableTrackIDs.contains(track.id))
    }

    @MainActor func testGaplessManagedSuccessorIgnoresDelayedOriginalFileEvents() async throws {
        let library = try TestLibrary()
        let file = try library.fixture(name: "Linked.wav", seconds: 4)
        let linked = try await link(library, file: file)
        let managedFile = try library.fixture(name: "Managed.wav", seconds: 5)
        _ = await library.importer.importFiles([managedFile]) { _ in }
        let managed = try XCTUnwrap(library.store.tracks().first { !$0.isLinked })
        let engine = TestPlaybackEngine()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: engine
        )
        playback.play([linked, managed])
        for _ in 0..<100 where engine.plays.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        engine.announcePlaying(entryID: try XCTUnwrap(playback.session.currentID))
        let observer = try XCTUnwrap(
            NSFileCoordinator.filePresenters.first {
                $0.presentedItemURL?.resolvingSymlinksInPath() == file.resolvingSymlinksInPath()
            }
        )
        let next = try XCTUnwrap(playback.session.entries.last)
        engine.announcePlaying(entryID: next.id)
        let acknowledged = expectation(description: "Delayed source deletion was acknowledged")
        observer.accommodatePresentedItemDeletion? { _ in acknowledged.fulfill() }
        await fulfillment(of: [acknowledged], timeout: 2)
        XCTAssertEqual(playback.track?.id, managed.id)
        XCTAssertEqual(playback.status, .playing)
        XCTAssertFalse(NSFileCoordinator.filePresenters.contains { $0 === observer })
        playback.pause()
    }

    func testCancellationRejectsLateWorkerResult() async throws {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let task = Task {
            try await SourceAccess.perform { _ in
                entered.signal()
                release.wait()
                return 42
            }
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.global()
                .async {
                    entered.wait()
                    continuation.resume()
                }
        }
        task.cancel()
        release.signal()
        do {
            _ = try await task.value
            XCTFail("A cancelled worker must not publish a late result")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    @MainActor func testPausedSourcePreparationCannotRestartPlayback() async throws {
        let library = try TestLibrary()
        let file = try library.fixture(seconds: 4)
        let track = try await link(library, file: file)
        let engine = TestPlaybackEngine()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: engine
        )
        playback.play([track])
        playback.pause()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(playback.status, .paused)
        XCTAssertTrue(engine.plays.isEmpty)
        playback.resume()
        for _ in 0..<100 where engine.plays.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(engine.plays.first?.url.standardizedFileURL, file.standardizedFileURL)
        XCTAssertEqual(playback.status, .playing)
        playback.pause()
    }

    @MainActor func testRapidSelectionOnlyPlaysLatestOriginal() async throws {
        let library = try TestLibrary()
        let file = try library.fixture(name: "First.wav", seconds: 4)
        _ = try library.fixture(name: "Second.wav", seconds: 4)
        _ = try await link(library, file: file)
        let tracks = try library.store.tracks()
        let engine = TestPlaybackEngine()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: engine
        )
        playback.play([tracks[0]])
        playback.play([tracks[1]])
        for _ in 0..<100 where engine.plays.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(engine.plays.count, 1)
        XCTAssertEqual(playback.track?.id, tracks[1].id)
        playback.pause()
    }
}
