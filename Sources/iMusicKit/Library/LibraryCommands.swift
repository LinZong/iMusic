import Foundation

/// Record-editing use cases; does not own queries, page state, or snapshot-loading mechanics.
@MainActor
public final class LibraryCommands {
    /// Transactional library persistence used by record mutations.
    let store: LibraryStore
    /// Managed artwork storage; original audio is never modified by metadata edits.
    let vault: MediaVault
    /// Shared playback references updated after record mutations.
    let playback: PlaybackCoordinator
    /// Optional synchronization triggered only after successful commits.
    let cloud: CloudSyncCoordinator
    /// Shared localized errors and operation gating.
    let activity: LibraryActivity
    /// Independent confirmed-deletion workflow.
    private let deletions: LibraryDeletionWorkflow
    /// Snapshot refresh callback installed by the composition owner without a retain cycle.
    var onChange: (() async -> Void)? {
        didSet { deletions.onChange = onChange }
    }
    /// Creates record commands around the application's existing services.
    init(
        store: LibraryStore,
        vault: MediaVault,
        importer: ImportCoordinator,
        playback: PlaybackCoordinator,
        cloud: CloudSyncCoordinator,
        activity: LibraryActivity
    ) {
        self.store = store
        self.vault = vault
        self.playback = playback
        self.cloud = cloud
        self.activity = activity
        deletions = LibraryDeletionWorkflow(
            store: store,
            importer: importer,
            playback: playback,
            cloud: cloud,
            activity: activity
        )
    }
    /// Publishes committed changes through the snapshot owner.
    private func refresh() async { await onChange?() }
    /// Revokes a folder configuration without deleting original files or managed copies.
    public func removeFolder(_ id: UUID) {
        do {
            playback.removeTracks(
                Set(
                    try store.tracks()
                        .filter {
                            $0.linkedSource?.folderID == id
                        }
                        .map(\.id)
                )
            )
            var folders = try store.setting("folders", as: [FolderSource].self) ?? []
            folders.removeAll { $0.id == id }
            try store.setSetting("folders", value: folders)
            Task { await refresh() }
        } catch { activity.message = error.localizedDescription }
    }
    /// Flips a song's favorite flag through the normal metadata save and refresh path.
    public func toggleFavorite(_ track: Track) {
        var value = track
        value.isFavorite.toggle()
        save(value)
    }
    /// Updates the song's modification time, persists its metadata, refreshes the visible library,
    /// and synchronizes when iCloud is enabled.
    public func save(_ track: Track) {
        var value = track
        value.modifiedAt = Date()
        do {
            try store.save(value)
            Task {
                await refresh()
                if cloud.enabled { await cloud.sync() }
            }
        } catch { activity.message = error.localizedDescription }
    }
    /// Updates the playlist's modification time, persists its metadata, refreshes the visible
    /// library, and synchronizes when iCloud is enabled.
    public func save(_ playlist: Playlist) {
        var value = playlist
        value.modifiedAt = Date()
        do {
            try store.save(value)
            Task {
                await refresh()
                if cloud.enabled { await cloud.sync() }
            }
        } catch { activity.message = error.localizedDescription }
    }
    /// Marks selected songs as recoverably deleted and removes their occurrences from the playback
    /// queue; keeps all source and managed files.
    public func trash(_ tracks: [Track]) {
        for track in tracks {
            var value = track
            value.deletedAt = Date()
            value.modifiedAt = Date()
            do { try store.save(value) } catch {
                activity.message = error.localizedDescription
                return
            }
            for entry in playback.session.entries where entry.trackID == track.id {
                playback.removeEntry(entry.id)
            }
        }
        Task { await refresh() }
    }
    /// Clears the song's Trash timestamp and saves it as an active library record.
    public func restore(_ track: Track) {
        var value = track
        value.deletedAt = nil
        save(value)
    }
    /// Clears the playlist's Trash timestamp and saves it as an active library record.
    public func restore(_ playlist: Playlist) {
        var value = playlist
        value.deletedAt = nil
        save(value)
    }

    /// Trims and validates a playlist name, persists a new record, and returns its identity;
    /// returns nil and presents an error on failure.
    @discardableResult public func createPlaylist(_ name: String) -> UUID? {
        let playlist = Playlist(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try store.save(playlist)
            Task { await refresh() }
            return playlist.id
        } catch {
            activity.message = error.localizedDescription
            return nil
        }
    }
    /// Moves all empty active playlists to Trash without touching songs.
    public func moveEmptyPlaylistsToTrash() {
        for playlist in (try? store.playlists()) ?? [] where playlist.entries.isEmpty {
            delete(playlist)
        }
    }
    /// Moves a playlist to Trash through the metadata save path without deleting its songs or
    /// artwork.
    public func delete(_ playlist: Playlist) {
        var value = playlist
        value.deletedAt = Date()
        save(value)
    }

    /// Merges identical audio records into a keeper, redirects playback occurrences, and refreshes
    /// visible data; validation errors are presented to the user.
    public func mergeDuplicates(keeper: Track, duplicates: [Track]) {
        do {
            let ids = Set(duplicates.map(\.id)).subtracting([keeper.id])
            try store.mergeDuplicates(keeping: keeper.id, removing: ids)
            playback.remapTracks(ids, to: keeper.id)
            Task { await refresh() }
        } catch { activity.message = error.localizedDescription }
    }
    /// Appends fresh queue occurrences for the supplied songs to a playlist, preserving intentional
    /// duplicate songs.
    public func add(_ tracks: [Track], to playlist: Playlist) {
        var value = playlist
        value.entries += tracks.map { QueueEntry(trackID: $0.id) }
        save(value)
    }
    /// Writes a new managed artwork file and saves its reference on the song without modifying the
    /// original audio file.
    public func updateArtwork(_ track: Track, data: Data) {
        do {
            let name = UUID().uuidString + ".image"
            try data.write(to: vault.artwork.appendingPathComponent(name), options: .atomic)
            var value = track
            value.artworkName = name
            save(value)
        } catch { activity.message = error.localizedDescription }
    }
    /// Executes confirmed song deletion through the serialized deletion workflow.
    public func permanentlyDelete(_ tracks: [Track]) { deletions.permanentlyDelete(tracks) }
    /// Executes confirmed playlist deletion without deleting audio files.
    public func permanentlyDelete(_ playlist: Playlist) { deletions.permanentlyDelete(playlist) }

}
