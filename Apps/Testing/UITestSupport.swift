import AVFAudio
import Foundation
import ImageIO
import UniformTypeIdentifiers
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
            ["library", "playlist-scroll", "song-scroll", "artwork"].contains(scenario),
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
        var titles = ["UI Alpha", "UI Beta", "UI Trashed"]
        if scenario == "artwork" { titles.append("UI No Artwork") }
        for (index, title) in titles.enumerated() {
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
        let artwork = scenario == "artwork" ? try makeArtwork(in: vault) : [:]
        for var track in try model.store.tracks() {
            track.artist = "UI Test Artist"
            track.album = "UI Test Album"
            track.genre = "UI Test Genre"
            track.artworkName = artwork[track.title]
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

    /// Stores distinct generated covers so tests can detect stale images and placeholders.
    private static func makeArtwork(in vault: MediaVault) throws -> [String: String] {
        var names: [String: String] = [:]
        for (title, red, blue) in [("UI Alpha", 1.0, 0.0), ("UI Beta", 0.0, 1.0)] {
            let name = title + ".png"
            guard
                let context = CGContext(
                    data: nil,
                    width: 256,
                    height: 256,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                let destination = CGImageDestinationCreateWithURL(
                    vault.artwork.appendingPathComponent(name) as CFURL,
                    UTType.png.identifier as CFString,
                    1,
                    nil
                )
            else { throw NSError(domain: "iMusic.UITesting", code: 3) }
            context.setFillColor(red: red, green: 0, blue: blue, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            guard let image = context.makeImage() else {
                throw NSError(domain: "iMusic.UITesting", code: 3)
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw NSError(domain: "iMusic.UITesting", code: 3)
            }
            names[title] = name
        }
        return names
    }
}
