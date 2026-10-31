import Foundation

/// Reconciles one coordinated folder listing, independent of authorization UI and scan scheduling.
enum OriginalFolderScanner {
    static func scan(
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
            guard LinkedAudioReference.isSafeRelativePath(relative) else { continue }
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
}
