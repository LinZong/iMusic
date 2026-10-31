import Foundation
import Observation

/// Page-local list mechanics shared without sharing any feature's dialogs or mutations.
@MainActor @Observable
final class SongListState {
    /// Query owned by this list instance.
    var search = ""
    /// Selected occurrence identities, including distinct duplicate playlist entries.
    var selected: Set<UUID> = []
    /// Native table comparators, also used when constructing a playback queue.
    var sortOrder: [KeyPathComparator<SongRowData>] = []

    /// Filters occurrences without changing their identities or source order.
    func filter(_ rows: [SongRowData]) -> [SongRowData] {
        rows.filter { LibrarySearch.matches(search, track: $0.track) }
    }

    /// Applies the current table order to visible occurrences.
    func ordered(_ rows: [SongRowData]) -> [SongRowData] {
        rows.sorted(using: sortOrder)
    }

    /// Resolves a native selection in visible order rather than unordered Set order.
    func selection(_ ids: Set<UUID>, in rows: [SongRowData]) -> [SongRowData] {
        ordered(rows).filter { ids.contains($0.id) }
    }
}

/// Playback capability adopted only by lists containing active songs.
@MainActor
protocol PlayableSongList: AnyObject {
    /// Shared playback dependency; no new player is created for a list.
    var player: PlayerViewModel { get }
    /// Page-owned query, selection, and display order.
    var state: SongListState { get }
    /// Filtered occurrences in their source order.
    var rows: [SongRowData] { get }
}

extension PlayableSongList {
    /// Starts the displayed queue at the requested occurrence, preserving duplicates and sorting.
    func play(row: SongRowData?) {
        guard let row, rows.contains(where: { $0.id == row.id }) else { return }
        player.playback.playEntries(
            state.ordered(rows).map { QueueEntry(id: $0.id, trackID: $0.track.id) },
            startingAt: row.id
        )
    }

    /// Starts random playback while retaining playlist occurrence identities.
    func shuffle() {
        guard let first = rows.randomElement() else { return }
        play(row: first)
        player.playback.toggleShuffle()
    }
}
