import Foundation
import Observation

@MainActor @Observable
public final class LibraryViewModel {
    /// Persistent library records, settings, and transactional synchronization outbox.
    public let store: LibraryStore
    /// Application-owned media paths and file-integrity helpers.
    public let vault: MediaVault
    /// Actor that copies, decodes, deduplicates, and recovers imported music.
    public let importer: ImportCoordinator
    /// Observable playback state and queue actions shared by all app windows.
    public let playback: PlaybackCoordinator
    /// Optional iCloud metadata and asset synchronization coordinator.
    public let cloud: CloudSyncCoordinator
    /// Active non-trashed song snapshot used to build the visible library.
    public private(set) var tracks: [Track] = []
    /// Songs in Trash, excluding permanently deleted records.
    public private(set) var deletedTracks: [Track] = []
    /// Active playlist snapshot, excluding playlists currently in Trash.
    public private(set) var playlists: [Playlist] = []
    /// Recoverable playlists currently in Trash.
    public private(set) var deletedPlaylists: [Playlist] = []
    /// Persisted listening segments used to calculate local statistics.
    public private(set) var events: [ListenEvent] = []
    /// Saved linked-folder configurations and their latest scan status.
    public private(set) var folders: [FolderSource] = []
    /// Device-local source job snapshot for folder status and recovery controls.
    public private(set) var linkedBindings: [LinkedFileBinding] = []
    /// Cached managed audio and admitted references with a matching local authorization revision.
    /// This snapshot is not a guarantee that a provider has retained its downloaded content.
    public private(set) var availableTrackIDs: Set<UUID> = []
    /// Monotonic refresh token that prevents an older asynchronous snapshot from replacing newer
    /// data.
    @ObservationIgnored private var refreshGeneration = 0
    /// Shared progress and failure reporting for serialized library operations.
    let activity: LibraryActivity
    /// Artist grouping preferences used to derive collection identities.
    let preferences: PreferencesViewModel

    /// Record mutation boundary, independent of snapshot publication and data projections.
    public let commands: LibraryCommands
    /// Narrow snapshot loader, injectable for refresh-generation regression tests.
    private let snapshotReader: any LibrarySnapshotReading
    /// Pure projection of the current active and recoverable records.
    var catalog: LibraryCatalog {
        LibraryCatalog(
            tracks: tracks,
            deletedTracks: deletedTracks,
            playlists: playlists,
            splitArtists: preferences.splitArtists,
            artistSeparators: preferences.artistSeparators
        )
    }

    /// Creates the observable library boundary around existing persistence and playback services.
    init(
        store: LibraryStore,
        vault: MediaVault,
        importer: ImportCoordinator,
        playback: PlaybackCoordinator,
        cloud: CloudSyncCoordinator,
        activity: LibraryActivity,
        preferences: PreferencesViewModel,
        snapshotReader: (any LibrarySnapshotReading)? = nil
    ) {
        self.store = store
        self.vault = vault
        self.importer = importer
        self.playback = playback
        self.cloud = cloud
        self.activity = activity
        self.preferences = preferences
        self.snapshotReader = snapshotReader ?? LibrarySnapshotLoader(store: store, vault: vault)
        commands = LibraryCommands(
            store: store,
            vault: vault,
            importer: importer,
            playback: playback,
            cloud: cloud,
            activity: activity
        )
        commands.onChange = { [weak self] in await self?.refresh() }
    }
    /// Loads library snapshots off the main actor, discards stale refresh generations, repairs
    /// purged playback references, and retries pending file cleanup.
    public func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        do {
            let snapshot = try await snapshotReader.load()
            guard generation == refreshGeneration else { return }
            tracks = snapshot.tracks.filter { $0.deletedAt == nil }
            deletedTracks = snapshot.tracks.filter { $0.deletedAt != nil }
            playlists = snapshot.playlists.filter { $0.deletedAt == nil }
            deletedPlaylists = snapshot.playlists.filter { $0.deletedAt != nil }
            events = snapshot.events
            folders = snapshot.folders
            availableTrackIDs = snapshot.availableTrackIDs
            linkedBindings = snapshot.bindings
            if !snapshot.purgedTracks.isEmpty {
                playback.removeTracks(Set(snapshot.purgedTracks.map(\.id)))
                if !activity.isWorking && !activity.importing {
                    do { try await importer.cleanupPermanentlyDeletedFiles() } catch {
                        activity.message = L10n.text(
                            """
                            Unable to finish cleaning up permanently deleted files. Cleanup will \
                            be retried when iMusic opens again.
                            """
                        )
                    }
                }
            }
            playback.refreshTrack()
        } catch { activity.message = error.localizedDescription }
    }
}
