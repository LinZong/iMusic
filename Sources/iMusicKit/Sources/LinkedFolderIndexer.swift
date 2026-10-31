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
                    try OriginalFolderScanner.scan(
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

    /// Delegates portable hint validation to the domain reference contract.
    static func safeRelativePath(_ path: String) -> Bool {
        LinkedAudioReference.isSafeRelativePath(path)
    }

}
