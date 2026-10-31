import Foundation

/// Coordinates confirmed deletion, queue repair, cleanup, refresh, and optional synchronization.
@MainActor
final class LibraryDeletionWorkflow {
    /// Transactional playlist-deletion persistence.
    let store: LibraryStore
    /// Serialized song deletion and managed-file cleanup.
    let importer: ImportCoordinator
    /// Shared queue whose deleted-song references must be removed.
    let playback: PlaybackCoordinator
    /// Optional post-commit synchronization.
    let cloud: CloudSyncCoordinator
    /// Shared destructive-operation gate and localized errors.
    let activity: LibraryActivity
    /// Requests a snapshot refresh after a committed or failed deletion attempt.
    var onChange: (() async -> Void)?
    /// Creates the deletion workflow without any page-owned state.
    init(
        store: LibraryStore,
        importer: ImportCoordinator,
        playback: PlaybackCoordinator,
        cloud: CloudSyncCoordinator,
        activity: LibraryActivity
    ) {
        self.store = store
        self.importer = importer
        self.playback = playback
        self.cloud = cloud
        self.activity = activity
    }
    /// Publishes the result through the library's snapshot boundary.
    private func refresh() async { await onChange?() }
    /// Serializes permanent deletion of confirmed trashed songs, commits tombstones before file
    /// cleanup, removes queue references, and syncs committed deletions.
    public func permanentlyDelete(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard !activity.isWorking, !activity.importing else {
            activity.message = L10n.text("Please wait for the current task to finish.")
            return
        }
        let ids = Set(tracks.map(\.id))
        activity.isWorking = true
        Task {
            var committed = false
            do {
                try await importer.permanentlyDeleteTracks(ids)
                committed = true
                playback.removeTracks(ids)
                do { try await importer.cleanupPermanentlyDeletedFiles() } catch {
                    activity.message = L10n.text(
                        """
                        Unable to finish cleaning up permanently deleted files. Cleanup will be \
                        retried when iMusic opens again.
                        """
                    )
                }
            } catch { activity.message = error.localizedDescription }
            await refresh()
            activity.isWorking = false
            if committed, cloud.enabled { await cloud.sync() }
        }
    }
    /// Permanently deletes a confirmed trashed playlist without changing songs or playback.
    /// Database work runs off the UI actor, then refreshes the library and syncs the deletion.
    public func permanentlyDelete(_ playlist: Playlist) {
        guard !activity.isWorking, !activity.importing else {
            activity.message = L10n.text("Please wait for the current task to finish.")
            return
        }
        activity.isWorking = true
        let store = store
        Task {
            var committed = false
            do {
                try await Task.detached(priority: .userInitiated) {
                    try store.permanentlyDeletePlaylist(playlist.id)
                }
                .value
                committed = true
            } catch { activity.message = error.localizedDescription }
            await refresh()
            activity.isWorking = false
            if committed, cloud.enabled { await cloud.sync() }
        }
    }
}
