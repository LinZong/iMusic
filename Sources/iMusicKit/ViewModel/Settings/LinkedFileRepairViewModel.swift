import Foundation
import Observation

/// Owns the explicit per-song source picker separately from app-wide import presentation.
@MainActor @Observable
final class LinkedFileRepairViewModel {
    /// Library records, source service, and shared operation feedback.
    private let library: LibraryViewModel
    /// Stable song identity being repaired; never inferred from a selected file's name.
    private var trackID: UUID?
    /// Whether the native original-file picker is presented.
    var presented = false

    init(library: LibraryViewModel) { self.library = library }
    /// Opens a file picker for an already authorized folder's unavailable song.
    func select(_ job: LinkedFileBinding) {
        trackID = job.id
        presented = true
    }
    /// Parses the selected original and atomically replaces its local binding while preserving song
    /// UUID.
    func accept(_ result: Result<[URL], Error>) {
        guard let trackID else { return }
        self.trackID = nil
        do {
            guard let url = try result.get().first else { return }
            guard !library.activity.importing else { return }
            library.activity.importing = true
            library.playback.removeTracks([trackID])
            Task {
                defer { library.activity.importing = false }
                do {
                    try await library.importer.locateLinkedFile(url, trackID: trackID)
                    await library.refresh()
                } catch { library.activity.message = error.localizedDescription }
            }
        } catch {
            if (error as NSError).code != NSUserCancelledError {
                library.activity.message = error.localizedDescription
            }
        }
    }
}
