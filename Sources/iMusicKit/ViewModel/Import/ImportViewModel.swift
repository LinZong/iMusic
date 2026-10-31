import Foundation

/// Composition and lifecycle routing for independent import-related workflows.
@MainActor
public final class ImportViewModel {
    /// File-picker presentation only; performs no filesystem work.
    let picker: ImportPickerViewModel
    /// Managed-copy imports and their completion report.
    let audio: AudioImportViewModel
    /// Original-file authorization, reconnection, and cancellable scanning.
    let folders: FolderImportViewModel
    /// Archive export and restore presentation.
    let archives: ArchiveViewModel
    /// Local transfer-page presentation and listener lifetime.
    let transfers: WiFiTransferViewModel
    /// Anonymous diagnostic report presentation.
    let diagnostics: DiagnosticsViewModel
    /// Shared library used only for startup and scene lifecycle coordination.
    private let library: LibraryViewModel
    /// Shared error presentation for native picker failures.
    private let activity: LibraryActivity

    /// Composes focused workflows around existing application services.
    init(
        library: LibraryViewModel,
        backup: BackupService,
        wifi: WiFiUploadServer,
        activity: LibraryActivity,
        preferences: PreferencesViewModel
    ) {
        self.library = library
        self.activity = activity
        let picker = ImportPickerViewModel()
        self.picker = picker
        audio = AudioImportViewModel(
            library: library,
            activity: activity,
            importer: library.importer
        )
        folders = FolderImportViewModel(library: library, activity: activity, picker: picker)
        archives = ArchiveViewModel(
            library: library,
            activity: activity,
            preferences: preferences,
            backup: backup
        )
        transfers = WiFiTransferViewModel(library: library, activity: activity, server: wifi)
        diagnostics = DiagnosticsViewModel(
            exporter: DiagnosticsExporter(store: library.store, vault: library.vault),
            activity: activity
        )
        transfers.onCompleted = { [weak audio] in audio?.importReport = $0 }
    }
    /// Recovers interrupted imports and admits linked originals once at launch.
    func launch() async {
        let errors = await library.importer.recover()
        if !errors.isEmpty { activity.message = errors.joined(separator: "\n") }
        await library.refresh()
        if !library.folders.isEmpty { await folders.scanFolders() }
    }
    /// Refreshes records and applies the folder workflow's foreground throttle.
    func foreground() async {
        await library.refresh()
        await folders.foreground()
    }
    /// Routes the native picker result to the requested workflow.
    func accept(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            switch picker.purpose {
            case .audio: audio.importURLs(urls)
            case .folder: if let url = urls.first { folders.addFolder(url) }
            case .backup: if let url = urls.first { archives.restoreBackup(url) }
            }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                activity.message = error.localizedDescription
            }
        }
    }
    /// Presents the native managed-file picker for application-level menu commands.
    public func presentAudioPicker() { picker.present(.audio) }
    /// Routes drag-and-drop or external URL requests to managed-copy import.
    public func importURLs(_ urls: [URL]) { audio.importURLs(urls) }
    /// Cancels active import and source work while retaining committed records.
    public func cancelImport() {
        audio.cancelImport()
        folders.cancel()
    }
    /// Stops document-provider admission before scene suspension.
    public func background() { folders.background() }
}
