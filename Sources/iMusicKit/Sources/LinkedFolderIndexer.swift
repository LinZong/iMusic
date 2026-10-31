import Foundation

/// Serializes source discovery and recoverable original-file metadata admission on all platforms.
actor LinkedFolderIndexer {
    /// Library records and device-local source jobs.
    private let store: LibraryStore
    /// Destination for derived artwork only; linked audio never enters Media or Staging.
    private let vault: MediaVault
    /// Prevents actor reentrancy from starting overlapping scans.
    private var scanning = false

    init(store: LibraryStore, vault: MediaVault) {
        self.store = store
        self.vault = vault
    }

    /// Saves a read grant; an explicit relink may match portable relative hints in the
    /// selected root.
    func add(_ url: URL, replacing id: UUID? = nil) async throws {
        let store = store
        try await SourceAccess.perform { operation in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try SourceAccess.bookmark(url)
            var folders = try store.setting("folders", as: [FolderSource].self) ?? []
            let previous = folders.first {
                (try? SourceAccess.resolve($0.bookmark).standardizedFileURL)
                    == url.standardizedFileURL
            }
            let folderID = id ?? previous?.id ?? UUID()
            folders.removeAll { $0.id == folderID }
            var folder = FolderSource(name: url.lastPathComponent, bookmark: bookmark)
            folder.id = folderID
            folder.usesOriginalFiles = true
            folder.bindingGeneration =
                id == nil && previous?.usesOriginalFiles == true
                ? previous?.bindingGeneration : UUID()
            try operation.check()
            try store.setSetting("folders", value: folders + [folder])
            if id != nil {
                // Only an explicit picker action permits path-based reconnection on this device.
                for track in try store.tracks(includeDeleted: true)
                where track.linkedSource?.folderID == folderID {
                    guard let reference = track.linkedSource,
                        Self.safeRelativePath(reference.relativePath)
                    else { continue }
                    let file = url.appendingPathComponent(reference.relativePath)
                    guard
                        let values = try? file.resourceValues(forKeys: [
                            .creationDateKey, .isSymbolicLinkKey, .isRegularFileKey,
                        ]), values.isRegularFile == true, values.isSymbolicLink != true
                    else {
                        var missing = LinkedFileBinding(
                            id: track.id,
                            folderID: folderID,
                            folderGeneration: folder.bindingGeneration,
                            bookmark: Data(),
                            relativePath: reference.relativePath
                        )
                        missing.state = .missing
                        missing.error = L10n.text(
                            "Source file is missing. Relink its folder in Settings."
                        )
                        try store.saveLinkedBinding(missing)
                        continue
                    }
                    let binding = LinkedFileBinding(
                        id: track.id,
                        folderID: folderID,
                        folderGeneration: folder.bindingGeneration,
                        bookmark: try SourceAccess.bookmark(file),
                        relativePath: reference.relativePath,
                        created: values.creationDate
                    )
                    try store.saveLinkedBinding(binding)
                }
            }
        }
    }

    /// Reconnects one known song to an explicitly selected file without guessing by filename.
    func locate(_ url: URL, trackID: UUID) async throws {
        let store = store
        let vault = vault
        try await SourceAccess.perform { operation in
            guard let previous = try store.track(id: trackID), previous.deletedAt == nil,
                let reference = previous.linkedSource,
                let folder = try store.setting("folders", as: [FolderSource].self)?
                    .first(where: {
                        $0.id == reference.folderID && $0.usesOriginalFiles == true
                    })
            else { throw MusicError.permissionDenied }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            var binding = LinkedFileBinding(
                id: trackID,
                folderID: folder.id,
                folderGeneration: folder.bindingGeneration,
                bookmark: try SourceAccess.bookmark(url),
                relativePath: url.lastPathComponent
            )
            let track = try operation.read(url) { readable in
                try LinkedMetadataPipeline.parse(
                    readable,
                    id: trackID,
                    reference: reference,
                    vault: vault,
                    previous: previous
                )
            }
            var hydratedURL = url
            hydratedURL.removeAllCachedResourceValues()
            let info = try hydratedURL.resourceValues(forKeys: [
                .creationDateKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey,
            ])
            guard info.isSymbolicLink != true else { throw MusicError.permissionDenied }
            binding.created = info.creationDate
            binding.size = info.fileSize
            binding.modified = info.contentModificationDate
            binding.state = .ready
            try operation.check()
            try store.commitLinkedTrack(track, item: binding)
        }
    }

    /// Retries durable jobs and reconciles complete authorized listings; failures never
    /// delete songs.
    func scan(progress: @escaping @Sendable (ImportProgress) -> Void) async -> [String] {
        guard !scanning else { return [] }
        scanning = true
        defer { scanning = false }
        let store = store
        let vault = vault
        let folders = (try? store.setting("folders", as: [FolderSource].self)) ?? []
        var errors: [String] = []
        for folder in folders {
            if Task.isCancelled { break }
            guard folder.usesOriginalFiles == true else {
                // Legacy links already produced managed copies. Require explicit relinking instead
                // of silently creating a second set of songs or touching those copies.
                continue
            }
            do {
                let result = try await SourceAccess.perform { operation in
                    try Self.scan(
                        folder,
                        store: store,
                        vault: vault,
                        operation: operation,
                        progress: progress
                    )
                }
                errors += result.errors
                try updateFolder(
                    folder.id,
                    generation: folder.bindingGeneration,
                    error: result.errors.first,
                    scanned: true
                )
            } catch {
                let message =
                    error is CancellationError
                    ? L10n.text("Folder scan cancelled. Completed songs have been saved.")
                    : error.localizedDescription
                errors.append(folder.name + ": " + message)
                try? updateFolder(
                    folder.id,
                    generation: folder.bindingGeneration,
                    error: message,
                    scanned: false
                )
            }
        }
        return errors
    }

    private func updateFolder(_ id: UUID, generation: UUID?, error: String?, scanned: Bool) throws {
        var folders = try store.setting("folders", as: [FolderSource].self) ?? []
        guard
            let index = folders.firstIndex(where: {
                $0.id == id && $0.bindingGeneration == generation
            })
        else { return }
        folders[index].error = error
        if scanned { folders[index].lastScan = Date() }
        try store.setSetting("folders", value: folders)
    }

    private static func scan(
        _ folder: FolderSource,
        store: LibraryStore,
        vault: MediaVault,
        operation: SourceOperation,
        progress: @escaping @Sendable (ImportProgress) -> Void
    ) throws -> ImportProgress {
        let root = try SourceAccess.resolve(folder.bookmark)
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw MusicError.permissionDenied
        }
        var listingError: Error?
        let listing: (files: [URL], root: URL) = try operation.read(root) { readable in
            guard
                let enumerator = FileManager.default.enumerator(
                    at: readable,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants],
                    errorHandler: { _, error in
                        listingError = error
                        return false
                    }
                )
            else { throw MusicError.permissionDenied }
            var files: [URL] = []
            while let file = enumerator.nextObject() as? URL {
                try operation.check()
                guard ImportCoordinator.extensions.contains(file.pathExtension.lowercased()) else {
                    continue
                }
                let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if info.isRegularFile == true, info.isSymbolicLink != true { files.append(file) }
            }
            // Do not infer disappearance from a partial provider listing.
            if let listingError { throw listingError }
            return (files, readable)
        }
        let files = listing.files
        var known: [String: LinkedFileBinding] = [:]
        let bindings = try store.linkedBindings().filter { $0.folderID == folder.id }
        for binding in bindings {
            if let resolved = try? SourceAccess.resolve(binding.bookmark),
                let info = try? resolved.resourceValues(forKeys: [.creationDateKey]),
                binding.created == nil || info.creationDate == nil
                    || info.creationDate == binding.created
            {
                known[resolved.standardizedFileURL.path] = binding
            }
        }
        var result = ImportProgress()
        result.total = files.count
        var observed: Set<UUID> = []
        for file in files.sorted(by: { $0.path < $1.path }) {
            try operation.check()
            result.currentFilename = file.lastPathComponent
            progress(result)
            let relative = String(file.path.dropFirst(listing.root.path.count + 1))
            guard safeRelativePath(relative) else { continue }
            var binding =
                try known[file.standardizedFileURL.path]
                ?? LinkedFileBinding(
                    id: UUID(),
                    folderID: folder.id,
                    bookmark: try SourceAccess.bookmark(file),
                    relativePath: relative,
                    created: try file.resourceValues(forKeys: [.creationDateKey]).creationDate
                )
            binding.folderGeneration = folder.bindingGeneration
            observed.insert(binding.id)
            if let existing = try store.track(id: binding.id), existing.deletedAt != nil {
                result.duplicates += 1
                result.completed += 1
                continue
            }
            if try store.wasPermanentlyDeleted(id: binding.id) {
                result.duplicates += 1
                result.completed += 1
                continue
            }
            if binding.attempts >= 3, binding.state == .failed {
                result.errors.append(
                    file.lastPathComponent + ": "
                        + (binding.error ?? L10n.text("Retry failed files in Linked Folders."))
                )
                result.completed += 1
                progress(result)
                continue
            }
            do {
                let info = try file.resourceValues(forKeys: [
                    .fileSizeKey, .contentModificationDateKey,
                ])
                let unchanged =
                    binding.size == info.fileSize
                    && binding.modified == info.contentModificationDate
                binding.relativePath = relative
                binding.bookmark = try SourceAccess.bookmark(file)
                if unchanged, let existing = try store.track(id: binding.id) {
                    binding.state = .ready
                    binding.error = nil
                    // Keep a portable rename hint current without overwriting user-edited tags.
                    var updated = existing
                    updated.linkedSource?.relativePath = relative
                    updated.linkedSource?.folderName = folder.name
                    try operation.check()
                    try store.commitLinkedTrack(updated, item: binding)
                    result.duplicates += 1
                } else {
                    binding.state = .preparing
                    binding.error = nil
                    try store.saveLinkedBinding(binding)
                    let old = try store.track(id: binding.id)
                    var track = try operation.read(file) { readable in
                        try LinkedMetadataPipeline.parse(
                            readable,
                            id: binding.id,
                            reference: LinkedAudioReference(
                                folderID: folder.id,
                                folderName: folder.name,
                                relativePath: relative
                            ),
                            vault: vault,
                            previous: old
                        )
                    }
                    try operation.check()
                    // Fetch current user edits after provider waiting,
                    // rather than writing an old snapshot.
                    if let current = try store.track(id: binding.id) {
                        LinkedMetadataPipeline.preserveEdits(from: current, in: &track)
                    }
                    var hydratedURL = file
                    hydratedURL.removeAllCachedResourceValues()
                    let hydrated = try hydratedURL.resourceValues(forKeys: [
                        .fileSizeKey, .contentModificationDateKey, .creationDateKey,
                    ])
                    binding.created = hydrated.creationDate
                    binding.size = hydrated.fileSize
                    binding.modified = hydrated.contentModificationDate
                    binding.state = .ready
                    binding.attempts = 0
                    if try store.commitLinkedTrack(track, item: binding) {
                        if old == nil { result.imported += 1 } else { result.duplicates += 1 }
                    }
                }
            } catch {
                binding.state = error is CancellationError ? .cancelled : .failed
                if !(error is CancellationError) { binding.attempts += 1 }
                binding.error =
                    error is CancellationError
                    ? L10n.text("Folder scan cancelled. Completed songs have been saved.")
                    : error.localizedDescription
                try store.saveLinkedBinding(binding)
                if error is CancellationError { throw error }
                result.errors.append(file.lastPathComponent + ": " + error.localizedDescription)
            }
            result.completed += 1
            progress(result)
        }
        try operation.check()
        for var binding in bindings where !observed.contains(binding.id) {
            // A bookmark may still resolve after a move outside the enumerated root.
            if let moved = try? SourceAccess.resolve(binding.bookmark),
                let info = try? moved.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey]
                ),
                info.isRegularFile == true,
                binding.created == nil || binding.created == info.creationDate
            {
                continue
            }
            binding.state = .missing
            binding.error = L10n.text("Source file is missing. Relink its folder in Settings.")
            try store.saveLinkedBinding(binding)
        }
        progress(result)
        return result
    }

    /// Validates portable hints before joining them to an explicitly selected root.
    static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0")
            && !path.split(separator: "/").contains("..")
    }

}
