import Foundation
import Observation

/// Focused AudioImportViewModel workflow, independent of other import presentations.
@MainActor @Observable
final class AudioImportViewModel {
    /// Shared record snapshots refreshed after committed changes.
    let library: LibraryViewModel
    /// Shared progress and localized operation errors.
    let activity: LibraryActivity
    /// Narrow managed-copy import service.
    let importer: any MusicFileImporting
    /// Final summary presented independently of the native picker.
    var importReport: ImportProgress?
    /// Cancellable managed-file import task.
    @ObservationIgnored private var importTask: Task<Void, Never>?
    /// Creates a managed-copy workflow with an injectable importer.
    init(library: LibraryViewModel, activity: LibraryActivity, importer: any MusicFileImporting) {
        self.library = library
        self.activity = activity
        self.importer = importer
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
            let result = await importer.importFiles(urls, skipUnchanged: false) {
                [weak self] progress in
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
    }
}
