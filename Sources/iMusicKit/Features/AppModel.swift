import Foundation
import Observation

public enum FileImportPurpose { case audio, folder, backup }

public enum LibraryDestination: Hashable {
    case home, songs, artists, albums, genres, playlists, favorites, trash, settings
    case artist(String), album(String), genre(String), playlist(UUID)
    public var title: String {
        switch self {
        case .home: L10n.text("Home"); case .songs: L10n.text("All Songs"); case .artists: L10n.text("Artists"); case .albums: L10n.text("Albums")
        case .playlists: L10n.text("Playlists"); case .favorites: L10n.text("Favorites"); case .trash: L10n.text("Trash"); case .settings: L10n.text("Settings")
        case .artist(let name): name.isEmpty ? L10n.text("Unknown Artist") : name
        case .album: L10n.text("Albums"); case .playlist: L10n.text("Playlists")
        case .genres: L10n.text("Genres"); case .genre(let name): name.isEmpty ? L10n.text("Uncategorized") : name
        }
    }
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
    public let store: LibraryStore, vault: MediaVault
    public let importer: ImportCoordinator, backup: BackupService
    public let playback: PlaybackCoordinator, wifi: WiFiUploadServer, cloud: CloudSyncCoordinator
    public let online = OnlineMetadataService()
    public private(set) var tracks: [Track] = []
    public private(set) var deletedTracks: [Track] = []
    public private(set) var playlists: [Playlist] = []
    public private(set) var deletedPlaylists: [Playlist] = []
    public private(set) var events: [ListenEvent] = []
    public private(set) var folders: [FolderSource] = []
    public var importing = false
    public var importProgress = ImportProgress()
    public var importReport: ImportProgress?
    public var message: String?
    public var fileImportPurpose: FileImportPurpose = .audio
    public var filePickerPresented = false
    public var showImporter: Bool {
        get { filePickerPresented && fileImportPurpose == .audio }
        set { if newValue { fileImportPurpose = .audio; filePickerPresented = true } else if fileImportPurpose == .audio { filePickerPresented = false } }
    }
    public var showFolderPicker: Bool {
        get { filePickerPresented && fileImportPurpose == .folder }
        set { if newValue { fileImportPurpose = .folder; filePickerPresented = true } else if fileImportPurpose == .folder { filePickerPresented = false } }
    }
    public var showRestorePicker: Bool {
        get { filePickerPresented && fileImportPurpose == .backup }
        set { if newValue { fileImportPurpose = .backup; filePickerPresented = true } else if fileImportPurpose == .backup { filePickerPresented = false } }
    }
    public var showPlayer = false
    public var showQueue = false
    public var showWiFi = false
    public var editingTrack: Track?
    public var batchEditingTracks: [Track]?
    public var exportedBackup: URL?
    public var diagnosticsURL: URL?
    public var isWorking = false
    public var onlineEnabled: Bool { didSet { try? store.setSetting("onlineEnabled", value: onlineEnabled) } }
    public var appearance: String { didSet { try? store.setSetting("appearance", value: appearance) } }
    public var vinyl: Bool { didSet { try? store.setSetting("vinyl", value: vinyl) } }
    public var serifFont: Bool { didSet { try? store.setSetting("serifFont", value: serifFont) } }
    public var homeSections: [HomeSectionOption] { didSet { try? store.setSetting("homeSections", value: homeSections) } }
    public var splitArtists: Bool { didSet { try? store.setSetting("splitArtists", value: splitArtists) } }
    public var artistSeparators: String { didSet { try? store.setSetting("artistSeparators", value: artistSeparators) } }
    @ObservationIgnored private var mediaBridge: SystemMediaBridge?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var launchComplete = false
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var lastFolderScan = Date.distantPast

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
    public func launch() async {
        guard !launchComplete else { return }; launchComplete = true
        let errors = await importer.recover()
        if !errors.isEmpty { message = errors.joined(separator: "\n") }
        await refresh()
        if !folders.isEmpty { await scanFolders() }
        if cloud.available, (try? store.setting("cloudEnabled", as: Bool.self)) == true { await cloud.enable(allowAccountChange: false) }
    }
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
    public func title(for destination: LibraryDestination) -> String {
        switch destination {
        case .playlist(let id): playlists.first { $0.id == id }?.name ?? L10n.text("Playlists")
        case .album(let key): tracks.first { $0.albumKey == key }?.displayAlbum ?? L10n.text("Albums")
        default: destination.title
        }
    }
    public func artistNames(_ track: Track) -> [String] {
        let separators = artistSeparators.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        return ArtistCreditParser.names(track.artist, split: splitArtists, separators: separators) + ArtistCreditParser.names(track.albumArtist, split: splitArtists, separators: separators)
    }
    public var artists: [String] { Array(Set(tracks.flatMap(artistNames))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    public var albums: [Track] {
        var keys = Set<String>()
        return tracks.filter { keys.insert($0.albumKey).inserted }.sorted { $0.displayAlbum.localizedStandardCompare($1.displayAlbum) == .orderedAscending }
    }
    public func cover(for playlist: Playlist) -> Track? {
        var track = playlist.entries.compactMap { entry in tracks.first { $0.id == entry.trackID } }.first
        if let name = playlist.artworkName {
            if track == nil { track = Track(assetHash: String(repeating: "0", count: 64), fileExtension: "wav", originalFilename: "", title: playlist.name) }
            track?.artworkName = name
        }
        return track
    }
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
    public func cancelImport() { importTask?.cancel() }
    public func addFolder(_ url: URL) {
        Task {
            do { try await importer.addFolder(url); await scanFolders() } catch { message = error.localizedDescription }
        }
    }
    public func removeFolder(_ id: UUID) { folders.removeAll { $0.id == id }; do { try store.setSetting("folders", value: folders) } catch { message = error.localizedDescription } }
    public func scanFolders() async {
        guard !importing else { return }; importing = true
        lastFolderScan = Date()
        let errors = await importer.scanFolders { [weak self] progress in Task { @MainActor in self?.importProgress = progress } }
        importing = false; if !errors.isEmpty { message = errors.joined(separator: "\n") }; await refresh()
    }
    public func foreground() async {
        await refresh()
        if !folders.isEmpty, Date().timeIntervalSince(lastFolderScan) > 30 { await scanFolders() }
    }
    public func toggleFavorite(_ track: Track) { var value = track; value.isFavorite.toggle(); save(value) }
    public func save(_ track: Track) {
        var value = track; value.modifiedAt = Date()
        do { try store.save(value); Task { await refresh(); if cloud.enabled { await cloud.sync() } } } catch { message = error.localizedDescription }
    }
    public func trash(_ tracks: [Track]) {
        for track in tracks {
            var value = track; value.deletedAt = Date(); value.modifiedAt = Date()
            do { try store.save(value) } catch { message = error.localizedDescription; return }
            for entry in playback.session.entries where entry.trackID == track.id { playback.removeEntry(entry.id) }
        }
        Task { await refresh() }
    }
    public func restore(_ track: Track) { var value = track; value.deletedAt = nil; save(value) }
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
    @discardableResult public func createPlaylist(_ name: String) -> UUID? {
        let playlist = Playlist(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        do { try store.save(playlist); Task { await refresh() }; return playlist.id } catch { message = error.localizedDescription; return nil }
    }
    public func save(_ playlist: Playlist) {
        var value = playlist; value.modifiedAt = Date()
        do { try store.save(value); Task { await refresh(); if cloud.enabled { await cloud.sync() } } } catch { message = error.localizedDescription }
    }
    public func delete(_ playlist: Playlist) { var value = playlist; value.deletedAt = Date(); save(value) }
    public func restore(_ playlist: Playlist) { var value = playlist; value.deletedAt = nil; save(value) }
    public func mergeDuplicates(keeper: Track, duplicates: [Track]) {
        do { let ids = Set(duplicates.map(\.id)).subtracting([keeper.id]); try store.mergeDuplicates(keeping: keeper.id, removing: ids); playback.remapTracks(ids, to: keeper.id); Task { await refresh() } }
        catch { message = error.localizedDescription }
    }
    public func add(_ tracks: [Track], to playlist: Playlist) { var value = playlist; value.entries += tracks.map { QueueEntry(trackID: $0.id) }; save(value) }
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
    public func exportBackup(full: Bool) {
        guard !isWorking else { return }; isWorking = true
        Task { defer { isWorking = false }; do { exportedBackup = try await backup.export(includeAudio: full) } catch { message = error.localizedDescription } }
    }
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
    public func updateArtwork(_ track: Track, data: Data) {
        do {
            let name = UUID().uuidString + ".image"
            try data.write(to: vault.artwork.appendingPathComponent(name), options: .atomic)
            var value = track; value.artworkName = name; save(value)
        } catch { message = error.localizedDescription }
    }
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
