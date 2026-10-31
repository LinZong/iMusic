import AVFAudio
import Foundation
import XCTest

@testable import iMusicKit

/// Opt-in acceptance against a user-authorized real iCloud folder, without speaker output.
final class ICloudFolderAcceptanceTests: XCTestCase {
    /// Indexes originals, reopens persisted bookmarks, and decodes PCM without an audio engine.
    func testAuthorizedCloudFolder() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["IMUSIC_ICLOUD_FOLDER"],
            let output = environment["IMUSIC_ICLOUD_REPORT_DIRECTORY"]
        else {
            throw XCTSkip("Set the iCloud folder and report directory to enable live acceptance.")
        }
        let source = URL(fileURLWithPath: path, isDirectory: true)
        let reportDirectory = URL(fileURLWithPath: output, isDirectory: true)
        let root = reportDirectory.appendingPathComponent("Library-" + UUID().uuidString)
        let vault = try MediaVault(root: root)
        let database = root.appendingPathComponent("Library.sqlite")
        let store = try LibraryStore(url: database)
        let importer = ImportCoordinator(store: store, vault: vault)
        let started = Date()
        print("ICLOUD_ACCEPTANCE library=\(root.path)")
        try await importer.addFolder(source)
        let errors = await importer.scanFolders { progress in
            print(
                "ICLOUD_PROGRESS \(progress.completed)/\(progress.total) "
                    + "\(progress.currentFilename)"
            )
        }
        let tracks = try store.tracks()
        XCTAssertFalse(tracks.isEmpty, "The authorized folder must admit at least one song.")
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "\n"))
        let reopened = try LibraryStore(url: database)
        var rows: [[String: Any]] = []
        for track in tracks {
            do {
                let prepared = try await PreparedSourceAudio.prepare(track: track, store: reopened)
                let decoder = prepared.decoder
                let buffer = try XCTUnwrap(
                    AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: 4096)
                )
                try decoder.decode(into: buffer, length: 4096)
                XCTAssertGreaterThan(buffer.frameLength, 0)
                XCTAssertTrue(track.isLinked)
                XCTAssertNil(track.assetHash)
                XCTAssertGreaterThan(track.duration, 0)
                XCTAssertGreaterThan(track.sampleRate, 0)
                XCTAssertTrue(prepared.url.path.hasPrefix(source.path + "/"))
                let values = try prepared.url.resourceValues(forKeys: [
                    .ubiquitousItemDownloadingStatusKey, .fileSizeKey,
                ])
                rows.append([
                    "id": track.id.uuidString,
                    "path": prepared.url.path,
                    "title": track.title,
                    "artist": track.artist,
                    "duration": track.duration,
                    "sampleRate": track.sampleRate,
                    "artwork": track.artworkName ?? "",
                    "decodedFrames": buffer.frameLength,
                    "status": values.ubiquitousItemDownloadingStatus?.rawValue ?? "unknown",
                    "size": values.fileSize ?? -1,
                ])
                try decoder.close()
            } catch {
                rows.append(["id": track.id.uuidString, "error": error.localizedDescription])
                XCTFail("\(track.originalFilename): \(error)")
            }
        }
        let media = try FileManager.default.contentsOfDirectory(atPath: vault.media.path)
        let staging = try FileManager.default.contentsOfDirectory(atPath: vault.staging.path)
        XCTAssertTrue(media.isEmpty)
        XCTAssertTrue(staging.isEmpty)
        let identities = Set(tracks.map(\.id))
        let retryErrors = await importer.scanFolders { _ in }
        XCTAssertTrue(retryErrors.isEmpty)
        XCTAssertEqual(Set(try store.tracks().map(\.id)), identities)
        let report: [String: Any] = [
            "source": source.path,
            "library": root.path,
            "started": ISO8601DateFormatter().string(from: started),
            "elapsedSeconds": Date().timeIntervalSince(started),
            "trackCount": tracks.count,
            "errors": errors,
            "mediaFiles": media,
            "stagingFiles": staging,
            "tracks": rows,
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: reportDirectory.appendingPathComponent("acceptance.json"))
        print("ICLOUD_ACCEPTANCE admitted=\(tracks.count) errors=\(errors.count)")
    }
}
