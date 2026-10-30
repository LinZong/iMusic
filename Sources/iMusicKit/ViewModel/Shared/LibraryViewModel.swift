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
    /// Monotonic refresh token that prevents an older asynchronous snapshot from replacing newer
    /// data.
    @ObservationIgnored private var refreshGeneration = 0
    /// Shared progress and failure reporting for serialized library operations.
    let activity: LibraryActivity
    /// Artist grouping preferences used to derive collection identities.
    let preferences: PreferencesViewModel

    /// Creates the observable library boundary around existing persistence and playback services.
    init(
        store: LibraryStore,
        vault: MediaVault,
        importer: ImportCoordinator,
        playback: PlaybackCoordinator,
        cloud: CloudSyncCoordinator,
        activity: LibraryActivity,
        preferences: PreferencesViewModel
    ) {
        self.store = store
        self.vault = vault
        self.importer = importer
        self.playback = playback
        self.cloud = cloud
        self.activity = activity
        self.preferences = preferences
    }
    /// Loads library snapshots off the main actor, discards stale refresh generations, repairs
    /// purged playback references, and retries pending file cleanup.
    public func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let store = store
        do {
            let snapshot =
                try await Task.detached(priority: .userInitiated) {
                    (
                        try store.tracks(includeDeleted: true),
                        try store.playlists(includeDeleted: true),
                        try store.listenEvents(),
                        try store.setting("folders", as: [FolderSource].self) ?? [],
                        try store.permanentlyDeletedTracks()
                    )
                }
                .value
            guard generation == refreshGeneration else { return }
            tracks = snapshot.0.filter { $0.deletedAt == nil }
            deletedTracks = snapshot.0.filter { $0.deletedAt != nil }
            playlists = snapshot.1.filter { $0.deletedAt == nil }
            deletedPlaylists = snapshot.1.filter { $0.deletedAt != nil }
            events = snapshot.2
            folders = snapshot.3
            if !snapshot.4.isEmpty {
                playback.removeTracks(Set(snapshot.4.map(\.id)))
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
    /// Returns the unfiltered songs belonging to a destination; page-owned queries are applied by
    /// the corresponding child view.
    public func songs(for destination: LibraryDestination) -> [Track] {
        let result: [Track]
        switch destination {
        case .favorites: result = tracks.filter(\.isFavorite)
        case .artist(let artist): result = tracks.filter { artistNames($0).contains(artist) }
        case .album(let key):
            result = tracks.filter { $0.albumKey == key }
                .sorted {
                    ($0.discNumber, $0.trackNumber, $0.title) < (
                        $1.discNumber, $1.trackNumber, $1.title
                    )
                }
        case .genre(let name): result = tracks.filter { $0.genre == name }
        case .playlist(let id):
            result =
                playlists.first { $0.id == id }?.entries
                .compactMap { entry in
                    tracks.first { $0.id == entry.trackID }
                } ?? []
        case .trash: result = deletedTracks
        default: result = tracks
        }
        return result
    }
    /// Returns the localized destination title or resolves the selected playlist or album's current
    /// display name.
    public func title(for destination: LibraryDestination) -> String {
        switch destination {
        case .playlist(let id): playlists.first { $0.id == id }?.name ?? L10n.text("Playlists")
        case .album(let key):
            tracks.first { $0.albumKey == key }?.displayAlbum ?? L10n.text("Albums")
        default: destination.title
        }
    }
    /// Returns performer and album-artist credits using the saved collaborator splitting preference
    /// and separators.
    public func artistNames(_ track: Track) -> [String] {
        let separators = preferences.artistSeparators.components(separatedBy: "|")
            .map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        return ArtistCreditParser.names(
            track.artist,
            split: preferences.splitArtists,
            separators: separators
        )
            + ArtistCreditParser.names(
                track.albumArtist,
                split: preferences.splitArtists,
                separators: separators
            )
    }
    /// Unique sorted performer and album-artist names derived from the unfiltered active library.
    public var artists: [String] {
        Array(Set(tracks.flatMap(artistNames)))
            .sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
    }
    /// One representative track per normalized album identity, sorted by display title.
    public var albums: [Track] {
        var keys = Set<String>()
        return tracks.filter { keys.insert($0.albumKey).inserted }
            .sorted {
                $0.displayAlbum.localizedStandardCompare($1.displayAlbum) == .orderedAscending
            }
    }
    /// Returns a representative playlist song or a placeholder record carrying its custom artwork
    /// file name.
    public func cover(for playlist: Playlist) -> Track? {
        var track = playlist.entries.compactMap { entry in tracks.first { $0.id == entry.trackID } }
            .first
        if let name = playlist.artworkName {
            if track == nil {
                track = Track(
                    assetHash: String(repeating: "0", count: 64),
                    fileExtension: "wav",
                    originalFilename: "",
                    title: playlist.name
                )
            }
            track?.artworkName = name
        }
        return track
    }
    /// Unlinks a saved folder configuration without deleting imported copies or original source
    /// files.
    public func removeFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        do { try store.setSetting("folders", value: folders) } catch {
            activity.message = error.localizedDescription
        }
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
}
