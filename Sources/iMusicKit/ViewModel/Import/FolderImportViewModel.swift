import Foundation
import Observation

/// Focused FolderImportViewModel workflow, independent of other import presentations.
@MainActor @Observable
final class FolderImportViewModel {
    /// Shared record snapshots refreshed after committed changes.
    let library: LibraryViewModel
    /// Shared progress and localized operation errors.
    let activity: LibraryActivity
    /// Shared native file-picker request state.
    let picker: ImportPickerViewModel
    /// Explicit root proposal reviewed before applying relative-path hints.
    var relinkPreview: FolderRelinkPreview?
    /// Portable folder identity awaiting explicit authorization.
    var relinkFolderID: UUID?
    /// Cancellable scan and cloud-hydration task.
    @ObservationIgnored private var folderTask: Task<[String], Never>?
    /// Last scan start, used to throttle foreground admission.
    @ObservationIgnored private var lastFolderScan = Date.distantPast
    /// Creates a source-only import workflow.
    init(library: LibraryViewModel, activity: LibraryActivity, picker: ImportPickerViewModel) {
        self.library = library
        self.activity = activity
        self.picker = picker
    }
    /// Requests a new folder rather than reconnecting an old identity.
    func chooseFolder() {
        relinkFolderID = nil
        picker.present(.folder)
    }
    /// Refreshes linked originals only when the foreground throttle permits it.
    func foreground() async {
        if !library.folders.isEmpty, Date().timeIntervalSince(lastFolderScan) > 30 {
            await scanFolders()
        }
    }
    /// Requests cancellation without discarding committed records or durable source jobs.
    func cancel() { folderTask?.cancel() }
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
        picker.present(.folder)
        relinkFolderID = id
    }
    /// Stops folder admission before suspension; committed songs and durable jobs remain
    /// recoverable.
    public func background() { folderTask?.cancel() }
}
