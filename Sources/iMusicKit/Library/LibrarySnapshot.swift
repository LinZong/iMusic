import Foundation

/// Immutable library records and local availability loaded together for publication.
struct LibrarySnapshot: Sendable {
    /// Active and recoverable songs, excluding permanent deletions.
    let tracks: [Track]
    /// Active and recoverable playlists, excluding permanent deletions.
    let playlists: [Playlist]
    /// Actual listening-time records.
    let events: [ListenEvent]
    /// Local authorized folder configurations.
    let folders: [FolderSource]
    /// Durable local original-file admission records.
    let bindings: [LinkedFileBinding]
    /// Tombstoned songs requiring queue-reference and cleanup recovery.
    let purgedTracks: [Track]
    /// Cached available managed files or admitted original-file references.
    let availableTrackIDs: Set<UUID>
}

/// Narrow snapshot contract supports deterministic loading and refresh-generation tests.
protocol LibrarySnapshotReading: Sendable {
    /// Loads a complete snapshot without performing UI or playback operations.
    func load() async throws -> LibrarySnapshot
}

/// Loads persistence and availability away from the UI actor.
struct LibrarySnapshotLoader: LibrarySnapshotReading {
    /// Local library record queries.
    let store: LibraryStore
    /// Managed-file existence checks.
    let vault: MediaVault
    /// Builds the immutable publication snapshot off the main actor.
    func load() async throws -> LibrarySnapshot {
        let store = store
        let vault = vault
        return
            try await Task.detached(priority: .userInitiated) {
                let tracks = try store.tracks(includeDeleted: true)
                let bindings = try store.linkedBindings()
                let folders = try store.setting("folders", as: [FolderSource].self) ?? []
                let ready = Set(
                    bindings.filter { binding in
                        binding.state == .ready
                            && folders.contains { folder in
                                folder.id == binding.folderID && folder.usesOriginalFiles == true
                                    && folder.bindingGeneration == binding.folderGeneration
                            }
                    }
                    .map(\.id)
                )
                return LibrarySnapshot(
                    tracks: tracks,
                    playlists: try store.playlists(includeDeleted: true),
                    events: try store.listenEvents(),
                    folders: folders,
                    bindings: bindings,
                    purgedTracks: try store.permanentlyDeletedTracks(),
                    availableTrackIDs: Set(
                        tracks.filter {
                            vault.contains($0) || ready.contains($0.id)
                        }
                        .map(\.id)
                    )
                )
            }
            .value
    }
}
