import Foundation

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
    /// Managed-copy admission, independently maintained from scanning and recovery.
    private let managed: ManagedFileImporter
    /// Original-file indexing service; kept separate from managed-copy imports.
    private let linked: LinkedFolderIndexer
    /// Binds serialized import and recovery operations to one library store and its managed media
    /// layout.
    public init(store: LibraryStore, vault: MediaVault) {
        self.store = store
        self.vault = vault
        linked = LinkedFolderIndexer(store: store, vault: vault)
        managed = ManagedFileImporter(store: store, vault: vault)
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
                    let outcome = try managed.importFile(url, allowReimport: !skipUnchanged)
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
    /// Replays durable journals and cleanup through the dedicated recovery service.
    public func recover() -> [String] {
        ManagedImportRecovery(store: store, vault: vault, importer: managed).recover()
    }

    /// Authorizes an original-file folder or explicitly reconnects a portable folder identity.
    public func addFolder(_ url: URL, replacing id: UUID? = nil) async throws {
        try await linked.add(url, replacing: id)
    }
    /// Reconnects an unavailable original to a file explicitly selected by the user.
    public func locateLinkedFile(_ url: URL, trackID: UUID) async throws {
        try await linked.locate(url, trackID: trackID)
    }
    /// Indexes originals without copying audio; incomplete provider listings never remove records.
    public func scanFolders(
        retryFailures: Bool = false,
        progress: @escaping @Sendable (ImportProgress) -> Void
    ) async -> [String] {
        if retryFailures {
            for var binding in (try? store.linkedBindings()) ?? [] where binding.state == .failed {
                binding.attempts = 0
                binding.state = .pending
                try? store.saveLinkedBinding(binding)
            }
        }
        return await linked.scan(progress: progress)
    }
}
