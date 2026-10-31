import Foundation
import Observation

@MainActor @Observable
public final class ImportViewModel {
    /// Actor responsible for exporting and validating restorable library archives.
    public let backup: BackupService
    /// Local upload listener whose lifetime follows the visible Wi-Fi Transfer page.
    public let wifi: WiFiUploadServer
    /// Completed import summary presented in a sheet until dismissed.
    public var importReport: ImportProgress?
    /// Operation served by the single native file picker: audio, folder, or backup.
    public var fileImportPurpose: FileImportPurpose = .audio
    /// Presentation state of the shared native importer.
    public var filePickerPresented = false
    /// Audio-import presentation binding; selecting it configures the shared picker for audio.
    public var showImporter: Bool {
        get { filePickerPresented && fileImportPurpose == .audio }
        set {
            if newValue {
                fileImportPurpose = .audio
                filePickerPresented = true
            } else if fileImportPurpose == .audio {
                filePickerPresented = false
            }
        }
    }
    /// Folder-link presentation binding; selecting it configures the shared picker for a folder.
    public var showFolderPicker: Bool {
        get { filePickerPresented && fileImportPurpose == .folder }
        set {
            if newValue {
                relinkFolderID = nil
                fileImportPurpose = .folder
                filePickerPresented = true
            } else if fileImportPurpose == .folder {
                filePickerPresented = false
            }
        }
    }
    /// Backup-restore presentation binding; selecting it configures the shared picker for a ZIP
    /// archive.
    public var showRestorePicker: Bool {
        get { filePickerPresented && fileImportPurpose == .backup }
        set {
            if newValue {
                fileImportPurpose = .backup
                filePickerPresented = true
            } else if fileImportPurpose == .backup {
                filePickerPresented = false
            }
        }
    }
    /// Whether the Wi-Fi Transfer sheet and its local upload listener are active.
    public var showWiFi = false
    /// Completed backup archive URL offered by the export sheet.
    public var exportedBackup: URL?
    /// Localized source counts and external-audio limitations shown with a completed backup.
    public private(set) var backupDetail = ""
    /// Generated anonymous diagnostics file offered by the export sheet.
    public var diagnosticsURL: URL?
    /// Device-local root proposal reviewed before relative-path hints are used for reconnection.
    var relinkPreview: FolderRelinkPreview?
    /// Folder identity to reconnect when the shared folder picker returns a selection.
    public var relinkFolderID: UUID?
    /// Cancellable task owning original-file scanning and provider hydration.
    @ObservationIgnored private var folderTask: Task<[String], Never>?
    /// Cancellable task owning the currently active import operation.
    @ObservationIgnored private var importTask: Task<Void, Never>?
    /// Timestamp used to avoid repeatedly rescanning linked folders during rapid foreground
    /// transitions.
    @ObservationIgnored private var lastFolderScan = Date.distantPast
    /// Shared records refreshed after imports and archive operations.
    let library: LibraryViewModel
    /// Import and blocking-operation status shared with the navigation footer.
    let activity: LibraryActivity
    /// Portable preferences reloaded after restoring an archive.
    let preferences: PreferencesViewModel

    /// Creates file-import, Wi-Fi, backup, and diagnostics workflows with explicit dependencies.
    init(
        library: LibraryViewModel,
        backup: BackupService,
        wifi: WiFiUploadServer,
        activity: LibraryActivity,
        preferences: PreferencesViewModel
    ) {
        self.library = library
        self.backup = backup
        self.wifi = wifi
        self.activity = activity
        self.preferences = preferences
    }
    /// Recovers interrupted imports and scans linked folders once during application startup.
    func launch() async {
        let errors = await library.importer.recover()
        if !errors.isEmpty { activity.message = errors.joined(separator: "\n") }
        await library.refresh()
        if !library.folders.isEmpty { await scanFolders() }
    }
    /// Refreshes records and throttles folder scanning when a scene returns to the foreground.
    func foreground() async {
        await library.refresh()
        if !library.folders.isEmpty, Date().timeIntervalSince(lastFolderScan) > 30 {
            await scanFolders()
        }
    }
    /// Starts a cancellable import, publishes progress and its final report, refreshes the library,
    /// and syncs after success when enabled.
    public func importURLs(_ urls: [URL]) {
        guard !activity.importing else {
            activity.message = L10n.text(
                "An import is already running. Please wait for it to finish."
            )
            return
        }
        activity.importing = true
        activity.importProgress = ImportProgress()
        importTask = Task {
            let result = await library.importer.importFiles(urls) { [weak self] progress in
                Task { @MainActor in self?.activity.importProgress = progress }
            }
            activity.importProgress = result
            importReport = result
            activity.importing = false
            await library.refresh()
            if library.cloud.enabled { await library.cloud.sync() }
        }
    }
    /// Requests cancellation of the active import task; already committed songs remain in the
    /// library.
    public func cancelImport() {
        importTask?.cancel()
        folderTask?.cancel()
    }
    /// Stores access to a selected folder and scans it asynchronously, presenting any linking or
    /// scan error.
    public func addFolder(_ url: URL) {
        let replacing = relinkFolderID
        relinkFolderID = nil
        Task {
            do {
                if let replacing {
                    let bookmark = try await SourceAccess.perform { _ in
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        return try SourceAccess.bookmark(url)
                    }
                    relinkPreview = FolderRelinkPreview(
                        id: replacing,
                        name: url.lastPathComponent,
                        bookmark: bookmark,
                        tracks: (library.tracks + library.deletedTracks)
                            .filter {
                                $0.linkedSource?.folderID == replacing
                            }
                    )
                } else {
                    try await library.importer.addFolder(url)
                    await scanFolders()
                }
            } catch { activity.message = error.localizedDescription }
        }
    }
    /// Applies a reviewed relative-path remapping while retaining existing song and playlist
    /// identities.
    func confirmFolderRelink() {
        guard let preview = relinkPreview else { return }
        relinkPreview = nil
        Task {
            do {
                let root = try await SourceAccess.perform { _ in
                    try SourceAccess.resolve(preview.bookmark)
                }
                try await library.importer.addFolder(root, replacing: preview.id)
                await scanFolders()
            } catch { activity.message = error.localizedDescription }
        }
    }
    /// Scans linked folders when no import is active, publishes progress, saves the last-scan time,
    /// and refreshes library snapshots.
    public func scanFolders(retryFailures: Bool = false) async {
        guard !activity.importing else { return }
        activity.importing = true
        lastFolderScan = Date()
        let task = Task { [library, weak self] in
            await library.importer.scanFolders(retryFailures: retryFailures) {
                [weak self] progress in
                Task { @MainActor in self?.activity.importProgress = progress }
            }
        }
        folderTask = task
        let errors = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        folderTask = nil
        activity.importing = false
        if !errors.isEmpty { activity.message = errors.joined(separator: "\n") }
        await library.refresh()
    }
    /// Requests an explicit read grant for an existing portable folder identity.
    public func relinkFolder(_ id: UUID) {
        showFolderPicker = true
        relinkFolderID = id
    }
    /// Stops folder admission before suspension; committed songs and durable jobs remain
    /// recoverable.
    public func background() { folderTask?.cancel() }
    /// Starts the local upload listener and imports each completed upload through the serialized
    /// importer, then refreshes the library.
    public func startWiFi() async {
        await wifi.start(staging: library.vault.staging) { [weak self] url in
            Task { @MainActor in
                guard let self else { return }
                // Serial library.importer actor accepts each uploaded file independently of the
                // picker task.
                let result = await self.library.importer.importFiles([url]) { _ in }
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                self.activity.importProgress = result
                if !self.showWiFi { self.importReport = result }
                await self.library.refresh()
            }
        }
    }
    /// Creates a full or metadata-only archive asynchronously and presents its export URL, showing
    /// a blocking progress state during creation.
    public func exportBackup(full: Bool) {
        guard !activity.isWorking else { return }
        activity.isWorking = true
        Task {
            defer { activity.isWorking = false }
            do {
                exportedBackup = try await backup.export(includeAudio: full)
                let tracks = library.tracks + library.deletedTracks
                backupDetail = L10n.text(
                    "format.backup.sources",
                    tracks.filter { !$0.isLinked }.count,
                    tracks.filter(\.isLinked).count
                )
            } catch {
                activity.message = error.localizedDescription
            }
        }
    }
    /// Validates and merges a selected backup asynchronously, reloads portable appearance
    /// preferences, and reports any songs still missing audio.
    public func restoreBackup(_ url: URL) {
        guard !activity.isWorking, !activity.importing else {
            activity.message = L10n.text("Please wait for the current task to finish.")
            return
        }
        activity.isWorking = true
        Task {
            defer { activity.isWorking = false }
            do {
                let missing = try await backup.restore(from: url)
                await library.refresh()
                preferences.reload()
                activity.message =
                    missing == 0
                    ? L10n.text("Backup restored.") : L10n.text("format.restore.missing", missing)
            } catch { activity.message = error.localizedDescription }
        }
    }
    /// Creates an anonymous JSON report of system version, counts, and integrity results, excluding
    /// music names, paths, and account data.
    public func exportDiagnostics() {
        let store = library.store
        let vault = library.vault
        Task {
            do {
                let url =
                    try await Task.detached {
                        let all = try store.tracks(includeDeleted: true)
                        let report: [String: Any] = [
                            "application": "iMusic", "version": "1.0.0",
                            "os": ProcessInfo.processInfo.operatingSystemVersionString,
                            "tracks": all.filter { $0.deletedAt == nil }.count,
                            "recycledTracks": all.filter { $0.deletedAt != nil }.count,
                            "missingAudioFiles": all.filter { !vault.contains($0) }.count,
                            "playlists": try store.playlists().count,
                            "pendingChanges": try store.pending().count,
                            "databaseIntegrity": try store.integrityIsOK() ? "ok" : "failed",
                            "pendingImportJournals": try FileManager.default
                                .contentsOfDirectory(
                                    atPath: vault.journals.path
                                )
                                .count,
                        ]
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                            "iMusic-Diagnostics-\(UUID().uuidString.prefix(8)).json"
                        )
                        try JSONSerialization.data(
                            withJSONObject: report,
                            options: [.prettyPrinted, .sortedKeys]
                        )
                        .write(to: url, options: .atomic)
                        return url
                    }
                    .value
                diagnosticsURL = url
            } catch { activity.message = error.localizedDescription }
        }
    }
}
