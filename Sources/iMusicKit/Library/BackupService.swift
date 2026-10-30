import Foundation
import ZIPFoundation

public struct BackupManifest: Codable {
    public var formatVersion = 1
    public var createdAt = Date()
    public var includesAudio: Bool
    public var records: [SyncEnvelope]
    public var files: [BackupFile]
    public var settings: [String: Data]?
}
public struct BackupFile: Codable {
    public var path: String
    public var hash: String
    public var size: UInt64
}

public actor BackupService {
    private let store: LibraryStore
    private let vault: MediaVault
    public init(store: LibraryStore, vault: MediaVault) { self.store = store; self.vault = vault }
    public func export(includeAudio: Bool) throws -> URL {
        let directory = vault.staging.appendingPathComponent("backup-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = try store.envelopes()
        var files: [BackupFile] = []
        let tracks = try store.tracks(includeDeleted: true)
        if includeAudio {
            for track in tracks {
                let source = try vault.url(for: track)
                guard FileManager.default.fileExists(atPath: source.path) else { throw MusicError.unavailable(L10n.text("format.backup.download_required", String(describing: track.title))) }
                let relative = "Media/" + source.lastPathComponent
                if files.contains(where: { $0.path == relative }) { continue }
                guard try MediaVault.digest(source) == track.assetHash else { throw MusicError.invalidBackup(L10n.text("format.backup.audio_checksum", String(describing: track.originalFilename))) }
                try copy(source, to: directory.appendingPathComponent(relative))
                let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                files.append(BackupFile(path: relative, hash: track.assetHash, size: UInt64(size)))
            }
        }
        let playlists = try store.playlists(includeDeleted: true)
        for name in Set(tracks.compactMap(\.artworkName) + playlists.compactMap(\.artworkName)) {
            guard let source = vault.artworkURL(name), FileManager.default.fileExists(atPath: source.path) else { continue }
            let relative = "Artwork/" + name
            try copy(source, to: directory.appendingPathComponent(relative))
            files.append(BackupFile(path: relative, hash: try MediaVault.digest(source), size: UInt64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)))
        }
        let manifest = BackupManifest(includesAudio: includeAudio, records: records, files: files, settings: try store.exportSettings())
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("iMusic-\(includeAudio ? "Full" : "Library")-\(UUID().uuidString.prefix(8)).zip")
        try FileManager.default.zipItem(at: directory, to: destination, shouldKeepParent: false, compressionMethod: .none)
        return destination
    }
    /// Preflight all paths, sizes and hashes before touching the live library.
    public func restore(from source: URL) throws -> Int {
        let accessed = source.startAccessingSecurityScopedResource(); defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let archive = try Archive(url: source, accessMode: .read)
        var expanded: UInt64 = 0
        for entry in archive {
            guard entry.type != .symlink, Self.safePath(entry.path) else { throw MusicError.invalidBackup(L10n.text("The archive contains an unsafe path")) }
            let (total, overflow) = expanded.addingReportingOverflow(UInt64(entry.uncompressedSize))
            guard !overflow, total <= 1_000_000_000_000 else { throw MusicError.invalidBackup(L10n.text("The expanded archive exceeds the size limit")) }; expanded = total
            if entry.path == "manifest.json", entry.uncompressedSize > 100_000_000 { throw MusicError.invalidBackup(L10n.text("The manifest is too large")) }
        }
        let directory = vault.staging.appendingPathComponent("restore-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.unzipItem(at: source, to: directory)
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        guard manifest.formatVersion == 1 else { throw MusicError.invalidBackup(L10n.text("This version is not supported")) }
        let tracks = try manifest.records.filter { $0.kind == "track" }.map { try JSONDecoder().decode(Track.self, from: $0.payload) }.filter { $0.permanentlyDeletedAt == nil }
        for file in manifest.files {
            guard Self.safePath(file.path), file.path.hasPrefix("Media/") || file.path.hasPrefix("Artwork/") else { throw MusicError.invalidBackup(L10n.text("Invalid file entry")) }
            let url = directory.appendingPathComponent(file.path)
            let size = UInt64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            guard size == file.size, try MediaVault.digest(url) == file.hash else { throw MusicError.invalidBackup(file.path + L10n.text(" has a checksum mismatch")) }
        }
        if manifest.includesAudio {
            for track in tracks {
                let expected = "Media/\(track.assetHash).\(track.fileExtension)"
                guard manifest.files.contains(where: { $0.path == expected && $0.hash == track.assetHash }) else { throw MusicError.invalidBackup(L10n.text("Missing music file")) }
            }
        }
        // Retain a logical pre-restore snapshot, even for metadata-only restores.
        try JSONEncoder().encode(try store.envelopes()).write(to: vault.root.appendingPathComponent("BeforeRestore.json"), options: .atomic)
        for file in manifest.files {
            let destination = vault.root.appendingPathComponent(file.path)
            if FileManager.default.fileExists(atPath: destination.path) {
                guard try MediaVault.digest(destination) == file.hash else { throw MusicError.invalidBackup(L10n.text("Existing file conflict: ") + file.path) }
            } else { try copy(directory.appendingPathComponent(file.path), to: destination) }
        }
        try store.restore(manifest.records, settings: manifest.settings ?? [:])
        try store.cleanupPermanentlyDeletedFiles(in: vault)
        return try tracks.filter { try store.track(id: $0.id) != nil && !vault.contains($0) }.count
    }
    public static func safePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") && !path.split(separator: "/").contains("..")
    }
    private func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        try MediaVault.protectPersistentFile(destination)
    }
}
