import Foundation
import Observation

public enum FileImportPurpose { case audio, folder, backup }

public enum LibraryDestination: Hashable {
    case home, songs, artists, albums, genres, playlists, favorites, trash, settings
    case artist(String), album(String), genre(String), playlist(UUID)
    /// Localized navigation title, or the selected category's user-provided name.
    public var title: String {
        switch self {
        case .home: L10n.text("Home"); case .songs: L10n.text("All Songs"); case .artists: L10n.text("Artists"); case .albums: L10n.text("Albums")
        case .playlists: L10n.text("Playlists"); case .favorites: L10n.text("Favorites"); case .trash: L10n.text("Trash"); case .settings: L10n.text("Settings")
        case .artist(let name): name.isEmpty ? L10n.text("Unknown Artist") : name
        case .album: L10n.text("Albums"); case .playlist: L10n.text("Playlists")
        case .genres: L10n.text("Genres"); case .genre(let name): name.isEmpty ? L10n.text("Uncategorized") : name
        }
    }
    /// SF Symbol name used for this destination in sidebars and tab bars.
    public var symbol: String {
        switch self {
        case .home: "house"; case .songs: "music.note"; case .artists, .artist: "person.2"
        case .albums, .album: "square.stack"; case .playlists, .playlist: "music.note.list"
        case .favorites: "heart"; case .trash: "trash"; case .settings: "gearshape"
        case .genres, .genre: "guitars"
        }
    }
}

@MainActor @Observable
public final class AppModel {
    /// Persistent library records, settings, and transactional synchronization outbox.
    public let store: LibraryStore
    /// Application-owned media paths and file-integrity helpers.
    public let vault: MediaVault
    /// Actor that copies, decodes, deduplicates, and recovers imported music.
    public let importer: ImportCoordinator
    /// Actor responsible for exporting and validating restorable library archives.
    public let backup: BackupService
    /// Observable playback state and queue actions shared by all app windows.
    public let playback: PlaybackCoordinator
    /// Local upload listener whose lifetime follows the visible Wi-Fi Transfer page.
    public let wifi: WiFiUploadServer
    /// Optional iCloud metadata and asset synchronization coordinator.
    public let cloud: CloudSyncCoordinator
    /// On-demand online album and cover lookup service, used only after user consent.
    public let online = OnlineMetadataService()
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
    /// Whether an import task is active and the progress footer should be displayed.
    public var importing = false
    /// Latest per-file progress snapshot from the active or most recent import.
    public var importProgress = ImportProgress()
    /// Completed import summary presented in a sheet until dismissed.
    public var importReport: ImportProgress?
    /// Optional localized message presented by the root alert.
    public var message: String?
    /// Operation served by the single native file picker: audio, folder, or backup.
    public var fileImportPurpose: FileImportPurpose = .audio
    /// Presentation state of the shared native importer.
    public var filePickerPresented = false
    /// Audio-import presentation binding; selecting it configures the shared picker for audio.
    public var showImporter: Bool {
        get { filePickerPresented && fileImportPurpose == .audio }
        set { if newValue { fileImportPurpose = .audio; filePickerPresented = true } else if fileImportPurpose == .audio { filePickerPresented = false } }
    }
    /// Folder-link presentation binding; selecting it configures the shared picker for a folder.
    public var showFolderPicker: Bool {
        get { filePickerPresented && fileImportPurpose == .folder }
        set { if newValue { fileImportPurpose = .folder; filePickerPresented = true } else if fileImportPurpose == .folder { filePickerPresented = false } }
    }
    /// Backup-restore presentation binding; selecting it configures the shared picker for a ZIP archive.
    public var showRestorePicker: Bool {
        get { filePickerPresented && fileImportPurpose == .backup }
        set { if newValue { fileImportPurpose = .backup; filePickerPresented = true } else if fileImportPurpose == .backup { filePickerPresented = false } }
    }
    /// Whether the full Now Playing sheet is presented.
    public var showPlayer = false
    /// Whether the playback queue is requested, either inside Now Playing or as its own sheet.
    public var showQueue = false
    /// Whether the Wi-Fi Transfer sheet and its local upload listener are active.
    public var showWiFi = false
    /// Song whose metadata editor is presented, or nil when no song editor is open.
    public var editingTrack: Track?
    /// Songs included in the currently presented bulk metadata editor.
    public var batchEditingTracks: [Track]?
    /// Completed backup archive URL offered by the export sheet.
    public var exportedBackup: URL?
    /// Generated anonymous diagnostics file offered by the export sheet.
    public var diagnosticsURL: URL?
    /// Whether a blocking library operation is running and the progress overlay is visible.
    public var isWorking = false
    /// Persisted consent for manual artwork lookups that send artist and album names online.
    public var onlineEnabled: Bool { didSet { try? store.setSetting("onlineEnabled", value: onlineEnabled) } }
    /// Persisted system, light, or dark appearance identifier; independent of system accent color.
    public var appearance: String { didSet { try? store.setSetting("appearance", value: appearance) } }
    /// Persisted preference for rendering artwork with the vinyl-record appearance.
    public var vinyl: Bool { didSet { try? store.setSetting("vinyl", value: vinyl) } }
    /// Persisted preference for using a serif font design in the native interface.
    public var serifFont: Bool { didSet { try? store.setSetting("serifFont", value: serifFont) } }
    /// Persisted order and visibility of the configurable Home sections.
    public var homeSections: [HomeSectionOption] { didSet { try? store.setSetting("homeSections", value: homeSections) } }
    /// Persisted preference for grouping collaborating artists as separate credits.
    public var splitArtists: Bool { didSet { try? store.setSetting("splitArtists", value: splitArtists) } }
    /// Persisted pipe-delimited separators used when collaborator splitting is enabled.
    public var artistSeparators: String { didSet { try? store.setSetting("artistSeparators", value: artistSeparators) } }
    /// System Now Playing and remote-command integration retained for the app model's lifetime.
    @ObservationIgnored private var mediaBridge: SystemMediaBridge?
    /// Cancellable task owning the currently active import operation.
    @ObservationIgnored private var importTask: Task<Void, Never>?
    /// Prevents initial recovery and library loading from running twice for the same app model.
    @ObservationIgnored private var launchComplete = false
    /// Monotonic refresh token that prevents an older asynchronous snapshot from replacing newer data.
    @ObservationIgnored private var refreshGeneration = 0
    /// Timestamp used to avoid repeatedly rescanning linked folders during rapid foreground transitions.
    @ObservationIgnored private var lastFolderScan = Date.distantPast

    /// Opens the persistent library and creates its import, backup, playback, transfer, optional cloud, and
    /// system-media services. Loads saved preferences and throws if the library cannot be opened.
    public init(root: URL = MediaVault.defaultRoot, cloudIdentifier: String? = nil) throws {
        vault = try MediaVault(root: root)
        store = try LibraryStore(url: root.appendingPathComponent("Library.sqlite"))
        importer = ImportCoordinator(store: store, vault: vault)
        backup = BackupService(store: store, vault: vault)
        playback = PlaybackCoordinator(store: store, vault: vault)
        wifi = WiFiUploadServer(); cloud = CloudSyncCoordinator(store: store, vault: vault, containerIdentifier: cloudIdentifier)
        onlineEnabled = (try? store.setting("onlineEnabled", as: Bool.self)) ?? false
        appearance = PreferencesCompatibility.canonicalID((try? store.setting("appearance", as: String.self)) ?? "system")
        vinyl = (try? store.setting("vinyl", as: Bool.self)) ?? false
        serifFont = (try? store.setting("serifFont", as: Bool.self)) ?? false
        homeSections = ((try? store.setting("homeSections", as: [HomeSectionOption].self)) ?? HomeSectionOption.defaults).map { $0.canonicalized() }
        splitArtists = (try? store.setting("splitArtists", as: Bool.self)) ?? false
        artistSeparators = (try? store.setting("artistSeparators", as: String.self)) ?? " feat. | ft. | & | 、"
        mediaBridge = SystemMediaBridge(playback: playback, vault: vault)
        cloud.onChange = { [weak self] in Task { await self?.refresh() } }
        playback.resolveMissing = { [weak self] track, token in
            Task { @MainActor in
                guard let self else { return }
                do { try await self.cloud.downloadForPlayback(track); self.playback.completedDownload(token: token, error: nil) }
                catch { self.playback.completedDownload(token: token, error: error) }
            }
        }
        #if os(iOS)
        CarPlaySceneDelegate.model = self
        #endif
    }
    /// Runs one-time import recovery, refreshes persisted snapshots, scans linked folders, and restores
    /// explicitly enabled cloud synchronization.
    public func launch() async {
        guard !launchComplete else { return }; launchComplete = true
        let errors = await importer.recover()
        if !errors.isEmpty { message = errors.joined(separator: "\n") }
        await refresh()
        if !folders.isEmpty { await scanFolders() }
        if cloud.available, (try? store.setting("cloudEnabled", as: Bool.self)) == true { await cloud.enable(allowAccountChange: false) }
    }
    /// Loads library snapshots off the main actor, discards stale refresh generations, repairs purged
    /// playback references, and retries pending file cleanup.
    public func refresh() async {
        refreshGeneration += 1; let generation = refreshGeneration, store = store
        do {
            let snapshot = try await Task.detached(priority: .userInitiated) { (try store.tracks(includeDeleted: true), try store.playlists(includeDeleted: true), try store.listenEvents(), try store.setting("folders", as: [FolderSource].self) ?? [], try store.permanentlyDeletedTracks()) }.value
            guard generation == refreshGeneration else { return }
            tracks = snapshot.0.filter { $0.deletedAt == nil }; deletedTracks = snapshot.0.filter { $0.deletedAt != nil }
            playlists = snapshot.1.filter { $0.deletedAt == nil }; deletedPlaylists = snapshot.1.filter { $0.deletedAt != nil }; events = snapshot.2; folders = snapshot.3
            if !snapshot.4.isEmpty {
                playback.removeTracks(Set(snapshot.4.map(\.id)))
                if !isWorking && !importing {
                    do { try await importer.cleanupPermanentlyDeletedFiles() }
                    catch { message = L10n.text("Unable to finish cleaning up permanently deleted files. Cleanup will be retried when iMusic opens again.") }
                }
            }
            playback.refreshTrack()
        } catch { message = error.localizedDescription }
    }
    /// Returns the unfiltered songs belonging to a destination; page-owned queries are applied by the
    /// corresponding child view.
    public func songs(for destination: LibraryDestination) -> [Track] {
        let result: [Track]
        switch destination {
        case .favorites: result = tracks.filter(\.isFavorite)
        case .artist(let artist): result = tracks.filter { artistNames($0).contains(artist) }
        case .album(let key): result = tracks.filter { $0.albumKey == key }.sorted { ($0.discNumber, $0.trackNumber, $0.title) < ($1.discNumber, $1.trackNumber, $1.title) }
        case .genre(let name): result = tracks.filter { $0.genre == name }
        case .playlist(let id): result = playlists.first { $0.id == id }?.entries.compactMap { entry in tracks.first { $0.id == entry.trackID } } ?? []
        case .trash: result = deletedTracks
        default: result = tracks
        }
        return result
    }
    /// Returns the localized destination title or resolves the selected playlist or album's current display
    /// name.
    public func title(for destination: LibraryDestination) -> String {
        switch destination {
        case .playlist(let id): playlists.first { $0.id == id }?.name ?? L10n.text("Playlists")
        case .album(let key): tracks.first { $0.albumKey == key }?.displayAlbum ?? L10n.text("Albums")
        default: destination.title
        }
    }
    /// Returns performer and album-artist credits using the saved collaborator splitting preference and
    /// separators.
    public func artistNames(_ track: Track) -> [String] {
        let separators = artistSeparators.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        return ArtistCreditParser.names(track.artist, split: splitArtists, separators: separators) + ArtistCreditParser.names(track.albumArtist, split: splitArtists, separators: separators)
    }
    /// Unique sorted performer and album-artist names derived from the unfiltered active library.
    public var artists: [String] { Array(Set(tracks.flatMap(artistNames))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    /// One representative track per normalized album identity, sorted by display title.
    public var albums: [Track] {
        var keys = Set<String>()
        return tracks.filter { keys.insert($0.albumKey).inserted }.sorted { $0.displayAlbum.localizedStandardCompare($1.displayAlbum) == .orderedAscending }
    }
    /// Returns a representative playlist song or a placeholder record carrying its custom artwork file name.
    public func cover(for playlist: Playlist) -> Track? {
        var track = playlist.entries.compactMap { entry in tracks.first { $0.id == entry.trackID } }.first
        if let name = playlist.artworkName {
            if track == nil { track = Track(assetHash: String(repeating: "0", count: 64), fileExtension: "wav", originalFilename: "", title: playlist.name) }
            track?.artworkName = name
        }
        return track
    }
    /// Starts a cancellable import, publishes progress and its final report, refreshes the library, and
    /// syncs after success when enabled.
    public func importURLs(_ urls: [URL]) {
        guard !importing else { message = L10n.text("An import is already running. Please wait for it to finish."); return }
        importing = true; importProgress = ImportProgress()
        importTask = Task {
            let result = await importer.importFiles(urls) { [weak self] progress in Task { @MainActor in self?.importProgress = progress } }
            importProgress = result; importReport = result; importing = false
            await refresh()
            if cloud.enabled { await cloud.sync() }
        }
    }
    /// Requests cancellation of the active import task; already committed songs remain in the library.
    public func cancelImport() { importTask?.cancel() }
    /// Stores access to a selected folder and scans it asynchronously, presenting any linking or scan error.
    public func addFolder(_ url: URL) {
        Task {
            do { try await importer.addFolder(url); await scanFolders() } catch { message = error.localizedDescription }
        }
    }
    /// Unlinks a saved folder configuration without deleting imported copies or original source files.
    public func removeFolder(_ id: UUID) { folders.removeAll { $0.id == id }; do { try store.setSetting("folders", value: folders) } catch { message = error.localizedDescription } }
    /// Scans linked folders when no import is active, publishes progress, saves the last-scan time, and
    /// refreshes library snapshots.
    public func scanFolders() async {
        guard !importing else { return }; importing = true
        lastFolderScan = Date()
        let errors = await importer.scanFolders { [weak self] progress in Task { @MainActor in self?.importProgress = progress } }
        importing = false; if !errors.isEmpty { message = errors.joined(separator: "\n") }; await refresh()
    }
    /// Refreshes persisted data on scene activation and rescans linked folders when the scan interval has
    /// elapsed.
    public func foreground() async {
        await refresh()
        if !folders.isEmpty, Date().timeIntervalSince(lastFolderScan) > 30 { await scanFolders() }
    }
    /// Flips a song's favorite flag through the normal metadata save and refresh path.
    public func toggleFavorite(_ track: Track) { var value = track; value.isFavorite.toggle(); save(value) }
    /// Updates the song's modification time, persists its metadata, refreshes the visible library, and
    /// synchronizes when iCloud is enabled.
    public func save(_ track: Track) {
        var value = track; value.modifiedAt = Date()
        do { try store.save(value); Task { await refresh(); if cloud.enabled { await cloud.sync() } } } catch { message = error.localizedDescription }
    }
    /// Marks selected songs as recoverably deleted and removes their occurrences from the playback queue;
    /// keeps all source and managed files.
    public func trash(_ tracks: [Track]) {
        for track in tracks {
            var value = track; value.deletedAt = Date(); value.modifiedAt = Date()
            do { try store.save(value) } catch { message = error.localizedDescription; return }
            for entry in playback.session.entries where entry.trackID == track.id { playback.removeEntry(entry.id) }
        }
        Task { await refresh() }
    }
    /// Clears the song's Trash timestamp and saves it as an active library record.
    public func restore(_ track: Track) { var value = track; value.deletedAt = nil; save(value) }
    /// Serializes permanent deletion of confirmed trashed songs, commits tombstones before file cleanup,
    /// removes queue references, and syncs committed deletions.
    public func permanentlyDelete(_ tracks: [Track]) {
        guard !tracks.isEmpty else { return }
        guard !isWorking, !importing else { message = L10n.text("Please wait for the current task to finish."); return }
        let ids = Set(tracks.map(\.id)); isWorking = true
        Task {
            var committed = false
            do {
                try await importer.permanentlyDeleteTracks(ids); committed = true
                playback.removeTracks(ids)
                do { try await importer.cleanupPermanentlyDeletedFiles() }
                catch { message = L10n.text("Unable to finish cleaning up permanently deleted files. Cleanup will be retried when iMusic opens again.") }
            } catch { message = error.localizedDescription }
            await refresh(); isWorking = false
            if committed, cloud.enabled { await cloud.sync() }
        }
    }
    /// Trims and validates a playlist name, persists a new record, and returns its identity; returns nil
    /// and presents an error on failure.
    @discardableResult public func createPlaylist(_ name: String) -> UUID? {
        let playlist = Playlist(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        do { try store.save(playlist); Task { await refresh() }; return playlist.id } catch { message = error.localizedDescription; return nil }
    }
    /// Updates the playlist's modification time, persists its metadata, refreshes the visible library, and
    /// synchronizes when iCloud is enabled.
    public func save(_ playlist: Playlist) {
        var value = playlist; value.modifiedAt = Date()
        do { try store.save(value); Task { await refresh(); if cloud.enabled { await cloud.sync() } } } catch { message = error.localizedDescription }
    }
    /// Moves a playlist to Trash through the metadata save path without deleting its songs or artwork.
    public func delete(_ playlist: Playlist) { var value = playlist; value.deletedAt = Date(); save(value) }
    /// Clears the playlist's Trash timestamp and saves it as an active library record.
    public func restore(_ playlist: Playlist) { var value = playlist; value.deletedAt = nil; save(value) }
    /// Merges identical audio records into a keeper, redirects playback occurrences, and refreshes visible
    /// data; validation errors are presented to the user.
    public func mergeDuplicates(keeper: Track, duplicates: [Track]) {
        do { let ids = Set(duplicates.map(\.id)).subtracting([keeper.id]); try store.mergeDuplicates(keeping: keeper.id, removing: ids); playback.remapTracks(ids, to: keeper.id); Task { await refresh() } }
        catch { message = error.localizedDescription }
    }
    /// Appends fresh queue occurrences for the supplied songs to a playlist, preserving intentional
    /// duplicate songs.
    public func add(_ tracks: [Track], to playlist: Playlist) { var value = playlist; value.entries += tracks.map { QueueEntry(trackID: $0.id) }; save(value) }
    /// Starts the local upload listener and imports each completed upload through the serialized importer,
    /// then refreshes the library.
    public func startWiFi() async {
        await wifi.start(staging: vault.staging) { [weak self] url in
            Task { @MainActor in
                guard let self else { return }
                // Serial importer actor accepts each uploaded file independently of the picker task.
                let result = await self.importer.importFiles([url]) { _ in }
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                self.importProgress = result
                if !self.showWiFi { self.importReport = result }
                await self.refresh()
            }
        }
    }
    /// Creates a full or metadata-only archive asynchronously and presents its export URL, showing a
    /// blocking progress state during creation.
    public func exportBackup(full: Bool) {
        guard !isWorking else { return }; isWorking = true
        Task { defer { isWorking = false }; do { exportedBackup = try await backup.export(includeAudio: full) } catch { message = error.localizedDescription } }
    }
    /// Validates and merges a selected backup asynchronously, reloads portable appearance preferences, and
    /// reports any songs still missing audio.
    public func restoreBackup(_ url: URL) {
        guard !isWorking, !importing else { message = L10n.text("Please wait for the current task to finish."); return }; isWorking = true
        Task { defer { isWorking = false }; do {
            let missing = try await backup.restore(from: url); await refresh()
            appearance = PreferencesCompatibility.canonicalID((try? store.setting("appearance", as: String.self)) ?? appearance)
            vinyl = (try? store.setting("vinyl", as: Bool.self)) ?? vinyl
            serifFont = (try? store.setting("serifFont", as: Bool.self)) ?? serifFont
            homeSections = ((try? store.setting("homeSections", as: [HomeSectionOption].self)) ?? homeSections).map { $0.canonicalized() }
            splitArtists = (try? store.setting("splitArtists", as: Bool.self)) ?? splitArtists
            artistSeparators = (try? store.setting("artistSeparators", as: String.self)) ?? artistSeparators
            message = missing == 0 ? L10n.text("Backup restored.") : L10n.text("format.restore.missing", missing)
        } catch { message = error.localizedDescription } }
    }
    /// Writes a new managed artwork file and saves its reference on the song without modifying the original
    /// audio file.
    public func updateArtwork(_ track: Track, data: Data) {
        do {
            let name = UUID().uuidString + ".image"
            try data.write(to: vault.artwork.appendingPathComponent(name), options: .atomic)
            var value = track; value.artworkName = name; save(value)
        } catch { message = error.localizedDescription }
    }
    /// Creates an anonymous JSON report of system version, counts, and integrity results, excluding music
    /// names, paths, and account data.
    public func exportDiagnostics() {
        let store = store, vault = vault
        Task {
            do {
                let url = try await Task.detached {
                    let all = try store.tracks(includeDeleted: true)
                    let report: [String: Any] = [
                        "application": "iMusic", "version": "1.0.0", "os": ProcessInfo.processInfo.operatingSystemVersionString,
                        "tracks": all.filter { $0.deletedAt == nil }.count, "recycledTracks": all.filter { $0.deletedAt != nil }.count,
                        "missingAudioFiles": all.filter { !vault.contains($0) }.count,
                        "playlists": try store.playlists().count, "pendingChanges": try store.pending().count,
                        "databaseIntegrity": try store.integrityIsOK() ? "ok" : "failed",
                        "pendingImportJournals": try FileManager.default.contentsOfDirectory(atPath: vault.journals.path).count
                    ]
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("iMusic-Diagnostics-\(UUID().uuidString.prefix(8)).json")
                    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
                    return url
                }.value
                diagnosticsURL = url
            } catch { message = error.localizedDescription }
        }
    }
}
