import XCTest
import AVFAudio
import ZIPFoundation
@testable import iMusicKit

final class TestLibrary {
    let root: URL, store: LibraryStore, vault: MediaVault, importer: ImportCoordinator
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("iMusicTests-" + UUID().uuidString)
        vault = try MediaVault(root: root); store = try LibraryStore(url: root.appendingPathComponent("Library.sqlite"))
        importer = ImportCoordinator(store: store, vault: vault)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func fixture(name: String = "会いたい 音乐 🎵.wav", seconds: Double = 0.3) throws -> URL {
        let directory = root.appendingPathComponent("Originals"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = UInt32(48_000 * seconds), buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 { buffer.floatChannelData![channel].update(repeating: 0, count: Int(frames)) }
        try file.write(from: buffer); return url
    }
    func track(title: String = "会いたい 音乐") -> Track { Track(assetHash: String(repeating: "a", count: 64), fileExtension: "wav", originalFilename: "日文 e\u{301} 🎵.wav", title: title, artist: "HIMEHINA", album: "作品", duration: 240) }
}

final class LibraryTests: XCTestCase {
    func testConcurrentPlaylistAddsAndDeletesConverge() throws {
        let first = try TestLibrary(), second = try TestLibrary(), trackID = UUID()
        var playlist = Playlist(name: "Shared", entries: [QueueEntry(trackID: trackID)])
        try first.store.save(playlist)
        try second.store.restore(first.store.envelopes())
        var other = try XCTUnwrap(second.store.playlists().first)
        playlist.entries.append(QueueEntry(trackID: UUID())); try first.store.save(playlist)
        other.entries.append(QueueEntry(trackID: UUID())); try second.store.save(other)
        let a = try first.store.envelopes().first!, b = try second.store.envelopes().first!
        try first.store.merge(b); try second.store.merge(a)
        XCTAssertEqual(try first.store.playlists().first, try second.store.playlists().first)
        XCTAssertEqual(try first.store.playlists().first?.entries.count, 3)
        var removed = try XCTUnwrap(first.store.playlists().first); let old = try second.store.envelopes().first!
        removed.entries.removeFirst(); try first.store.save(removed); try first.store.merge(old)
        XCTAssertEqual(try first.store.playlists().first?.entries.count, 2)
    }
    func testUnicodeNamesAndMetadataSurviveRoundTrip() throws {
        let library = try TestLibrary(), track = library.track(); try library.store.save(track)
        XCTAssertEqual(try library.store.track(id: track.id), track)
        XCTAssertEqual(try library.store.tracks(query: "音楽").count, 0)
        XCTAssertEqual(try library.store.tracks(query: "音乐").count, 1)
        XCTAssertEqual(try library.store.tracks(query: "himehina").count, 1)
    }
    func testSearchWildcardsAreLiteral() throws {
        let library = try TestLibrary(); try library.store.save(library.track(title: "100%_music")); try library.store.save(library.track(title: "other"))
        XCTAssertEqual(try library.store.tracks(query: "%_").count, 1)
    }
    func testLateSyncAcknowledgementCannotLoseNewEdit() throws {
        let library = try TestLibrary(); var track = library.track(); try library.store.save(track)
        let old = try library.store.pending().first!
        track.title = "New title"; try library.store.save(track)
        try library.store.acknowledge(id: old.0.id, generation: old.1)
        XCTAssertEqual(try library.store.pending().count, 1)
    }
    func testTrashRetainsRecordAndFileIdentity() throws {
        let library = try TestLibrary(); var track = library.track(); track.deletedAt = Date(); try library.store.save(track)
        XCTAssertTrue(try library.store.tracks().isEmpty); XCTAssertEqual(try library.store.tracks(includeDeleted: true).count, 1)
        track.deletedAt = nil; try library.store.save(track); XCTAssertEqual(try library.store.tracks().count, 1)
    }
    func testPlaylistSupportsDuplicateTracks() throws {
        let library = try TestLibrary(), track = library.track()
        try library.store.save(track); let playlist = Playlist(name: "作品集", entries: [QueueEntry(trackID: track.id), QueueEntry(trackID: track.id)])
        try library.store.save(playlist); XCTAssertEqual(try library.store.playlists().first, playlist)
        XCTAssertThrowsError(try library.store.save(Playlist(name: "  ")))
    }
    func testPathValidationRejectsTraversal() throws {
        let library = try TestLibrary()
        XCTAssertThrowsError(try library.vault.url(hash: "../../outside", extension: "wav"))
        XCTAssertThrowsError(try library.vault.url(hash: String(repeating: "a", count: 64), extension: "../wav"))
        XCTAssertNil(library.vault.artworkURL("../picture"))
        for path in ["../a", "/tmp/a", "a/../b", "a\\b", ""] { XCTAssertFalse(BackupService.safePath(path)) }
        XCTAssertTrue(BackupService.safePath("Media/song.wav"))
    }
    func testRestoreIsAtomicOnInvalidRecord() throws {
        let library = try TestLibrary(); try library.store.save(library.track())
        let existing = try library.store.envelopes()
        let invalid = SyncEnvelope(id: UUID().uuidString, kind: "unknown", payload: Data("{}".utf8), versions: [:])
        XCTAssertThrowsError(try library.store.restore(existing + [invalid]))
        XCTAssertEqual(try library.store.tracks().count, 1)
    }
}

final class ImportBackupTests: XCTestCase {
    func testImportCopiesWithoutChangingOriginalAndDeduplicates() async throws {
        let library = try TestLibrary(), url = try library.fixture(), hash = try MediaVault.digest(url)
        let first = await library.importer.importFiles([url]) { _ in }
        XCTAssertEqual(first.imported, 1, first.errors.joined()); XCTAssertTrue(first.errors.isEmpty)
        let imported = try XCTUnwrap(library.store.tracks().first)
        XCTAssertEqual(imported.originalFilename, url.lastPathComponent); XCTAssertEqual(imported.assetHash, hash)
        XCTAssertEqual(try MediaVault.digest(url), hash); XCTAssertTrue(library.vault.contains(imported))
        let second = await library.importer.importFiles([url]) { _ in }
        XCTAssertEqual(second.duplicates, 1); XCTAssertEqual(try library.store.tracks().count, 1)
    }
    func testCorruptFileDoesNotProduceReadyTrackOrLoseSource() async throws {
        let library = try TestLibrary(), url = library.root.appendingPathComponent("broken.wav")
        try Data("not audio".utf8).write(to: url)
        let result = await library.importer.importFiles([url]) { _ in }
        XCTAssertEqual(result.imported, 0); XCTAssertEqual(result.errors.count, 1); XCTAssertTrue(try library.store.tracks().isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), Data("not audio".utf8))
    }
    func testRecoveryCompletesJournaledMediaBeforeDatabaseCommit() async throws {
        let library = try TestLibrary(), source = try library.fixture(), hash = try MediaVault.digest(source)
        var track = library.track(); track.assetHash = hash
        let journal = ImportJournal(id: UUID(), stagedName: "pending.wav", originalFilename: track.originalFilename, track: track)
        try FileManager.default.copyItem(at: source, to: library.vault.staging.appendingPathComponent(journal.stagedName))
        try JSONEncoder().encode(journal).write(to: library.vault.journals.appendingPathComponent(journal.id.uuidString + ".json"))
        let errors = await library.importer.recover(); XCTAssertTrue(errors.isEmpty, errors.joined())
        XCTAssertTrue(library.vault.contains(track)); XCTAssertEqual(try library.store.track(id: track.id), track)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: library.vault.journals.path).isEmpty)
    }
    func testFullBackupRestoresMusicAndPlaylistExactly() async throws {
        let source = try TestLibrary(), fixture = try source.fixture()
        _ = await source.importer.importFiles([fixture]) { _ in }
        var track = try XCTUnwrap(source.store.tracks().first); track.isFavorite = true; track.title = "已编辑标题"; try source.store.save(track)
        try source.store.setSetting("appearance", value: "dark"); try source.store.setSetting("cloudEnabled", value: true)
        let playlist = Playlist(name: "我的收藏", entries: [QueueEntry(trackID: track.id), QueueEntry(trackID: track.id)]); try source.store.save(playlist)
        let backup = BackupService(store: source.store, vault: source.vault), url = try await backup.export(includeAudio: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try TestLibrary(), restore = BackupService(store: destination.store, vault: destination.vault)
        let missing = try await restore.restore(from: url)
        XCTAssertEqual(missing, 0); XCTAssertEqual(try destination.store.tracks().first, track)
        XCTAssertEqual(try destination.store.playlists().first, playlist)
        XCTAssertEqual(try destination.store.setting("appearance", as: String.self), "dark")
        XCTAssertNil(try destination.store.setting("cloudEnabled", as: Bool.self))
        XCTAssertEqual(try MediaVault.digest(destination.vault.url(for: track)), track.assetHash)
    }
    func testCompletedWiFiUploadRecoversAfterProcessInterruption() async throws {
        let library = try TestLibrary(), fixture = try library.fixture()
        let directory = library.vault.staging.appendingPathComponent("upload-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: directory.appendingPathComponent(fixture.lastPathComponent))
        try JSONEncoder().encode(fixture.lastPathComponent).write(to: directory.appendingPathComponent(".complete"))
        let errors = await library.importer.recover(); XCTAssertTrue(errors.isEmpty, errors.joined())
        XCTAssertEqual(try library.store.tracks().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }
    func testMetadataOnlyBackupReportsUnavailableAudio() async throws {
        let source = try TestLibrary(); try source.store.save(source.track())
        let url = try await BackupService(store: source.store, vault: source.vault).export(includeAudio: false)
        defer { try? FileManager.default.removeItem(at: url) }
        let target = try TestLibrary()
        let missing = try await BackupService(store: target.store, vault: target.vault).restore(from: url)
        XCTAssertEqual(missing, 1); XCTAssertEqual(try target.store.tracks().count, 1)
    }
}
