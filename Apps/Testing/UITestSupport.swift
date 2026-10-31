import AVFAudio
import Foundation
import iMusicKit

/// Available only in the separate UI-test host target, never in shipping app targets.
@MainActor enum UITestSupport {
    /// Opens a UUID-scoped test library; arbitrary paths and production libraries are rejected.
    static func makeModel() throws -> AppModel {
        let environment = ProcessInfo.processInfo.environment
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing"),
            let value = environment["IMUSIC_UI_TEST_RUN_ID"], let id = UUID(uuidString: value)
        else {
            throw NSError(
                domain: "iMusic.UITesting",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Launch this test host through iMusic UI Tests."
                ]
            )
        }
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("UITesting", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        return try AppModel(root: root, engine: UITestPlaybackEngine(), integrateWithSystem: false)
    }

    /// Imports generated silent WAVs through the production importer once per test run.
    static func prepare(_ model: AppModel) async throws {
        guard let scenario = ProcessInfo.processInfo.environment["IMUSIC_UI_TEST_SCENARIO"],
            ["library", "playlist-scroll", "song-scroll"].contains(scenario),
            try model.store.setting("uiTestSeeded", as: Bool.self) != true
        else { return }
        let vault = try MediaVault(
            root: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("UITesting")
                .appendingPathComponent(
                    UUID(uuidString: ProcessInfo.processInfo.environment["IMUSIC_UI_TEST_RUN_ID"]!)!
                        .uuidString
                )
        )
        let source = vault.root.appendingPathComponent("Fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000)!
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].update(repeating: 0, count: Int(buffer.frameLength))
        var files: [URL] = []
        for (index, title) in ["UI Alpha", "UI Beta", "UI Trashed"].enumerated() {
            let url = source.appendingPathComponent(title + ".wav")
            // Distinct durations prevent the managed importer from deduplicating silent fixtures.
            do {
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                for _ in 0..<(120 + index * 10) { try file.write(from: buffer) }
            }
            files.append(url)
        }
        let importer = ImportCoordinator(store: model.store, vault: vault)
        let result = await importer.importFiles(files) { _ in }
        guard result.errors.isEmpty, result.imported == files.count else {
            throw NSError(
                domain: "iMusic.UITesting",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: result.errors.joined(separator: "\n")]
            )
        }
        for var track in try model.store.tracks() {
            track.artist = "UI Test Artist"
            track.album = "UI Test Album"
            track.genre = "UI Test Genre"
            if track.title == "UI Trashed" { track.deletedAt = Date() }
            try model.store.save(track)
        }
        if scenario == "song-scroll",
            let template = try model.store.tracks()
                .first(where: {
                    $0.deletedAt == nil
                })
        {
            for index in 0..<80 {
                var track = template
                track.id = UUID()
                track.title = String(format: "UI Scroll %02d", index)
                track.originalFilename = track.title + ".wav"
                track.isFavorite = true
                track.deletedAt = index >= 40 ? Date() : nil
                try model.store.save(track)
            }
        }
        if scenario == "playlist-scroll" {
            let active = try model.store.tracks().filter { $0.deletedAt == nil }
            let entries = (0..<40).map { QueueEntry(trackID: active[$0 % active.count].id) }
            try model.store.save(Playlist(name: "UI Scroll Playlist", entries: entries))
        }
        try model.store.setSetting("uiTestSeeded", value: true)
        await model.library.refresh()
    }
}
