import Foundation
import Observation

/// Recovery-only song model with no playback or playlist-editing capability.
@MainActor @Observable
final class TrashSongsViewModel {
    /// Shared deleted-song records and recovery operations.
    let library: LibraryViewModel
    /// Page-local query, table sorting, and selection.
    let state = SongListState()
    /// Deleted songs awaiting explicit permanent-deletion confirmation.
    var pendingPermanentDeletion: [Track] = []
    /// Matching deleted songs, never including active library records.
    var rows: [SongRowData] {
        state.filter(library.deletedTracks.map { SongRowData(id: $0.id, track: $0) })
    }
    /// Prevents recovery mutations while import or another destructive operation is running.
    var isBusy: Bool { library.activity.isWorking || library.activity.importing }

    /// Creates an independent recovery page without a playback dependency.
    init(library: LibraryViewModel) { self.library = library }

    /// Restores selected deleted songs to the active library.
    func restore(_ ids: Set<UUID>) {
        guard !isBusy else { return }
        for row in state.selection(ids, in: rows) { library.commands.restore(row.track) }
    }

    /// Captures only visible, selected deleted songs for the confirmation dialog.
    func requestDeletion(_ ids: Set<UUID>) {
        guard !isBusy else { return }
        pendingPermanentDeletion = state.selection(ids, in: rows).map(\.track)
    }
}
