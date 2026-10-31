import Foundation
import Observation

/// Focused ArchiveViewModel workflow, independent of other import presentations.
@MainActor @Observable
final class ArchiveViewModel {
    /// Shared record snapshots refreshed after committed changes.
    let library: LibraryViewModel
    /// Shared progress and localized operation errors.
    let activity: LibraryActivity
    /// Archive operations independent of storage and ZIP implementation details.
    let backup: any LibraryArchiving
    /// Portable preferences reloaded after restoring metadata.
    let preferences: PreferencesViewModel
    /// Completed archive offered by the export presentation.
    var exportedBackup: URL?
    /// Localized source counts and external-audio limitations for the archive.
    private(set) var backupDetail = ""
    /// Creates independent archive and restore presentation state.
    init(
        library: LibraryViewModel,
        activity: LibraryActivity,
        preferences: PreferencesViewModel,
        backup: any LibraryArchiving
    ) {
        self.library = library
        self.activity = activity
        self.preferences = preferences
        self.backup = backup
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
}
