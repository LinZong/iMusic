import Foundation
import SFBAudioEngine

public struct ImportProgress: Sendable {
    /// Number of source files processed, including duplicates and failures.
    public var completed = 0
    /// Number of source files scheduled for the current import.
    public var total = 0
    /// Number of newly committed songs in the current import.
    public var imported = 0
    /// Number of existing copies skipped or restored instead of importing another copy.
    public var duplicates = 0
    /// Localized per-file failures collected for the import report.
    public var errors: [String] = []
    /// Name of the file currently being processed for progress display.
    public var currentFilename = ""
    /// Creates an empty progress report with zero counters and no per-file failures.
    public init() {}
}

struct ImportJournal: Codable {
    /// Unique identity of the recoverable import operation and its journal file.
    var id: UUID
    /// File name of the completed staging copy associated with this operation.
    var stagedName: String
    /// Source file name preserved when reconstructing an interrupted import.
    var originalFilename: String
    /// Prepared song metadata, if decoding completed before the interruption.
    var track: Track?
}
private struct SourceStamp: Codable {
    /// Source file size in bytes at the last successful folder import.
    var size: Int
    /// Source modification date used with size to skip unchanged folder files.
    var modified: Date
    /// Content digest recorded for the last imported version of the source file.
    var hash: String
}

public actor ImportCoordinator {
    /// Supported source extensions advertised to folder scanning and the browser upload client.
    public static let extensions: Set<String> = [
        "mp3", "m4a", "aac", "alac", "flac", "wav", "aif", "aiff", "ogg", "oga", "opus", "caf",
    ]
    /// SQLite library store used by this service to read records and persist atomic changes.
    private let store: LibraryStore
    /// Application-owned media layout used to resolve validated files and working directories.
    private let vault: MediaVault
    /// Binds serialized import and recovery operations to one library store and its managed media
    /// layout.
    public init(store: LibraryStore, vault: MediaVault) {
        self.store = store
        self.vault = vault
    }

    /// Copies selected files or folder contents into the managed library, decodes tags,
    /// deduplicates content, and reports per-file progress. Cancellation retains completed imports
    /// and failures are returned in the summary.
    public func importFiles(
        _ urls: [URL],
        skipUnchanged: Bool = false,
        progress: @escaping @Sendable (ImportProgress) -> Void
    ) async -> ImportProgress {
        var result = ImportProgress()
        var stamps = (try? store.setting("sourceStamps", as: [String: SourceStamp].self)) ?? [:]
        var files: [URL] = []
        let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for url in accessed { url.stopAccessingSecurityScopedResource() }
        }
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory == true {
                let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                while let candidate = enumerator?.nextObject() as? URL {
                    guard Self.extensions.contains(candidate.pathExtension.lowercased()),
                        let info = try? candidate.resourceValues(forKeys: [
                            .isRegularFileKey, .isSymbolicLinkKey,
                        ]), info.isRegularFile == true, info.isSymbolicLink != true
                    else { continue }
                    files.append(candidate)
                }
            } else {
                files.append(url)
            }
        }
        result.total = files.count
        progress(result)
        for url in files {
            if Task.isCancelled {
                result.errors.append(
                    L10n.text("Import cancelled. Completed songs have been saved safely.")
                )
                break
            }
            result.currentFilename = url.lastPathComponent
            progress(result)
            do {
                let attributes = try url.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey,
                ])
                let size = attributes.fileSize ?? 0
                let modified = attributes.contentModificationDate ?? .distantPast
                if skipUnchanged, let previous = stamps[url.path], previous.size == size,
                    previous.modified == modified,
                    let track = try store.track(hash: previous.hash), vault.contains(track)
                {
                    result.duplicates += 1
                } else {
                    let outcome = try importOne(url, allowReimport: !skipUnchanged)
                    if outcome.imported { result.imported += 1 } else { result.duplicates += 1 }
                    stamps[url.path] = SourceStamp(
                        size: size,
                        modified: modified,
                        hash: outcome.hash
                    )
                }
            } catch {
                result.errors.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
            result.completed += 1
            progress(result)
            await Task.yield()
        }
        do { try store.setSetting("sourceStamps", value: stamps) } catch {
            result.errors.append(
                L10n.text(
                    "format.import.index_error",
                    String(describing: error.localizedDescription)
                )
            )
        }
        return result
    }

    private func importOne(_ source: URL, allowReimport: Bool = true) throws -> (
        imported: Bool, hash: String
    ) {
        let ext = source.pathExtension.lowercased()
        guard Self.extensions.contains(ext) else { throw MusicError.unsupportedFormat }
        let id = UUID()
        let stagedName = UUID().uuidString + "." + ext
        let journalURL = vault.journals.appendingPathComponent(id.uuidString + ".json")
        let stagedURL = vault.staging.appendingPathComponent(stagedName)
        var journal = ImportJournal(
            id: id,
            stagedName: stagedName,
            originalFilename: source.lastPathComponent
        )
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        do {
            try coordinatedCopy(source, to: stagedURL)
            let hash = try MediaVault.digest(stagedURL)
            if var existing = try store.track(hash: hash) {
                if !vault.contains(existing) {
                    try FileManager.default.moveItem(at: stagedURL, to: vault.url(for: existing))
                }
                if existing.deletedAt != nil {
                    existing.deletedAt = nil
                    existing.modifiedAt = Date()
                    try store.save(existing)
                }
                try? FileManager.default.removeItem(at: stagedURL)
                try FileManager.default.removeItem(at: journalURL)
                return (false, hash)
            }
            if !allowReimport, try store.wasPermanentlyDeleted(hash: hash) {
                try FileManager.default.removeItem(at: stagedURL)
                try FileManager.default.removeItem(at: journalURL)
                return (false, hash)
            }
            let audio = try AudioFile(readingPropertiesAndMetadataFrom: stagedURL)
            let meta = audio.metadata
            let properties = audio.properties
            let duration = properties.duration ?? 0
            guard duration.isFinite, duration > 0 else { throw MusicError.unsupportedFormat }
            let stableID = MediaVault.stableID(hash: hash)
            let trackID = try store.wasPermanentlyDeleted(id: stableID) ? UUID() : stableID
            var track = Track(
                id: trackID,
                assetHash: hash,
                fileExtension: ext,
                originalFilename: source.lastPathComponent,
                title: meta.title?.isEmpty == false
                    ? meta.title! : source.deletingPathExtension().lastPathComponent,
                artist: meta.artist ?? "",
                album: meta.albumTitle ?? "",
                albumArtist: meta.albumArtist ?? "",
                genre: meta.genre ?? "",
                discNumber: meta.discNumber ?? 1,
                trackNumber: meta.trackNumber ?? 0,
                duration: duration,
                sampleRate: properties.sampleRate ?? 0,
                channels: Int(properties.channelCount ?? 2)
            )
            track.originalMetadata = [
                "title": track.title, "artist": track.artist, "album": track.album,
                "albumArtist": track.albumArtist, "genre": track.genre,
            ]
            if let picture = meta.attachedPictures.first, picture.imageData.count <= 20_000_000 {
                let name = hash + ".image"
                try picture.imageData.write(
                    to: vault.artwork.appendingPathComponent(name),
                    options: .atomic
                )
                track.artworkName = name
            }
            journal.track = track
            try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
            let destination = try vault.url(for: track)
            if FileManager.default.fileExists(atPath: destination.path) {
                guard try MediaVault.digest(destination) == hash else {
                    throw MusicError.importFailed(
                        L10n.text(
                            """
                            An existing library file failed verification. Keep the file and check \
                            your disk.
                            """
                        )
                    )
                }
                try FileManager.default.removeItem(at: stagedURL)
            } else {
                try FileManager.default.moveItem(at: stagedURL, to: destination)
            }
            try store.save(track)
            try FileManager.default.removeItem(at: journalURL)
            return (true, hash)
        } catch {
            // Once metadata is journaled the media can be recovered without reopening its source.
            if journal.track == nil {
                try? FileManager.default.removeItem(at: stagedURL)
                try? FileManager.default.removeItem(at: journalURL)
            }
            throw error
        }
    }
    private func coordinatedCopy(_ source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator()
            .coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                do {
                    let reader = try FileHandle(forReadingFrom: readable)
                    defer { try? reader.close() }
                    guard FileManager.default.createFile(atPath: destination.path, contents: nil)
                    else {
                        throw MusicError.importFailed(
                            L10n.text("Unable to create the staging file.")
                        )
                    }
                    let writer = try FileHandle(forWritingTo: destination)
                    defer { try? writer.close() }
                    while let data = try reader.read(upToCount: 1_048_576), !data.isEmpty {
                        if Task.isCancelled { throw CancellationError() }
                        try writer.write(contentsOf: data)
                    }
                    try writer.synchronize()
                } catch { copyError = error }
            }
        if let error = coordinationError ?? copyError as NSError? { throw error }
    }

    /// Commits permanent-deletion tombstones and reference cleanup for the selected trashed songs
    /// before any files are unlinked.
    public func permanentlyDeleteTracks(_ ids: Set<UUID>) throws {
        try store.permanentlyDeleteTracks(ids)
    }
    /// Retries deletion of unreferenced managed copies recorded by permanent-deletion tombstones,
    /// without touching source files.
    public func cleanupPermanentlyDeletedFiles() throws {
        try store.cleanupPermanentlyDeletedFiles(in: vault)
    }
    /// Replays durable import journals and pending deletion cleanup after an interrupted run;
    /// returns recoverable error messages for presentation.
    public func recover() -> [String] {
        var errors: [String] = []
        for directory
            in (try? FileManager.default.contentsOfDirectory(
                at: vault.staging,
                includingPropertiesForKeys: nil
            )) ?? [] where directory.lastPathComponent.hasPrefix("upload-")
        {
            let marker = directory.appendingPathComponent(".complete")
            guard let data = try? Data(contentsOf: marker),
                let name = try? JSONDecoder().decode(String.self, from: data), !name.contains("/"),
                !name.contains("\\")
            else { continue }
            do {
                _ = try importOne(directory.appendingPathComponent(name), allowReimport: false)
                try FileManager.default.removeItem(at: directory)
            } catch {
                errors.append(
                    L10n.text(
                        "format.import.wifi_recovery",
                        String(describing: error.localizedDescription)
                    )
                )
            }
        }
        for url
            in (try? FileManager.default.contentsOfDirectory(
                at: vault.journals,
                includingPropertiesForKeys: nil
            )) ?? []
        {
            do {
                let journal = try JSONDecoder()
                    .decode(ImportJournal.self, from: Data(contentsOf: url))
                guard !journal.stagedName.contains("/"), !journal.stagedName.contains("\\") else {
                    throw MusicError.invalidBackup(L10n.text("Invalid import journal"))
                }
                let staged = vault.staging.appendingPathComponent(journal.stagedName)
                guard let track = journal.track else {
                    try? FileManager.default.removeItem(at: staged)
                    try FileManager.default.removeItem(at: url)
                    errors.append(
                        L10n.text(
                            "format.import.copy_incomplete",
                            String(describing: journal.originalFilename)
                        )
                    )
                    continue
                }
                if try store.wasPermanentlyDeleted(id: track.id) {
                    try? FileManager.default.removeItem(at: staged)
                    try FileManager.default.removeItem(at: url)
                    continue
                }
                let destination = try vault.url(for: track)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    guard try MediaVault.digest(staged) == track.assetHash else {
                        throw MusicError.importFailed(L10n.text("Staged file verification failed"))
                    }
                    try FileManager.default.moveItem(at: staged, to: destination)
                }
                guard try MediaVault.digest(destination) == track.assetHash else {
                    throw MusicError.importFailed(L10n.text("Music file verification failed"))
                }
                if try store.track(id: track.id) == nil { try store.save(track) }
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.removeItem(at: url)
            } catch {
                errors.append(
                    L10n.text(
                        "format.import.recovery",
                        String(describing: error.localizedDescription)
                    )
                )
            }
        }
        do { try cleanupPermanentlyDeletedFiles() } catch {
            errors.append(
                L10n.text(
                    """
                    Unable to finish cleaning up permanently deleted files. Cleanup will be \
                    retried when iMusic opens again.
                    """
                )
            )
        }
        return errors
    }

    /// Stores a security-scoped bookmark for a selected folder without moving or modifying its
    /// source files.
    public func addFolder(_ url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        let bookmark = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
        var folders = try store.setting("folders", as: [FolderSource].self) ?? []
        folders.append(FolderSource(name: url.lastPathComponent, bookmark: bookmark))
        try store.setSetting("folders", value: folders)
    }
    /// Resolves saved folder bookmarks and imports changed audio while reporting progress; records
    /// scan times and access failures for settings.
    public func scanFolders(progress: @escaping @Sendable (ImportProgress) -> Void) async
        -> [String]
    {
        var folders = (try? store.setting("folders", as: [FolderSource].self)) ?? []
        var errors: [String] = []
        for index in folders.indices {
            do {
                var stale = false
                #if os(macOS)
                let url = try URL(
                    resolvingBookmarkData: folders[index].bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                #else
                let url = try URL(
                    resolvingBookmarkData: folders[index].bookmark,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                #endif
                guard url.startAccessingSecurityScopedResource() else {
                    throw MusicError.permissionDenied
                }
                defer { url.stopAccessingSecurityScopedResource() }
                let result = await importFiles([url], skipUnchanged: true, progress: progress)
                folders[index].lastScan = Date()
                folders[index].error = result.errors.first
                errors += result.errors
            } catch {
                folders[index].error = error.localizedDescription
                errors.append("\(folders[index].name)：\(error.localizedDescription)")
            }
        }
        try? store.setSetting("folders", value: folders)
        return errors
    }
}
