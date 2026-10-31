import Foundation
import Observation

/// Playlist-only editing and presentation state, independent of collection and Trash pages.
@MainActor @Observable
final class PlaylistDetailViewModel: PlayableSongList {
    /// Current library records and persistence operations.
    let library: LibraryViewModel
    /// Shared playback and song-action dependencies.
    let player: PlayerViewModel
    /// Stable identity of the playlist being edited.
    let playlistID: UUID
    /// Page-local query, occurrence selection, and table order.
    let state = SongListState()
    /// Whether the rename alert is visible.
    var rename = false
    /// Draft name, committed only by Save.
    var newName = ""
    /// Whether the song picker is visible.
    var addingTracks = false
    /// Whether the name and artwork editor is visible.
    var editingPlaylist = false
    /// Latest active playlist snapshot; never stores a stale editable copy.
    var playlist: Playlist? { library.playlists.first { $0.id == playlistID } }
    /// Matching entries retain their own identities even when a song occurs multiple times.
    var rows: [SongRowData] {
        let tracks = Dictionary(uniqueKeysWithValues: library.tracks.map { ($0.id, $0) })
        return state.filter(
            (playlist?.entries ?? [])
                .compactMap { entry in
                    tracks[entry.trackID].map { SongRowData(id: entry.id, track: $0) }
                }
        )
    }
    /// Reordering requires an unfiltered, unsorted view of every playlist occurrence.
    var canReorder: Bool {
        LibrarySearch.isEmpty(state.search) && state.sortOrder.isEmpty
            && rows.map(\.id) == playlist?.entries.map(\.id)
    }

    /// Opens one playlist using explicit shared dependencies.
    init(library: LibraryViewModel, player: PlayerViewModel, playlistID: UUID) {
        self.library = library
        self.player = player
        self.playlistID = playlistID
    }

    /// Removes selected occurrences, preserving duplicate songs and the underlying audio files.
    func remove(_ ids: Set<UUID>) {
        guard var playlist else { return }
        playlist.entries.removeAll { ids.contains($0.id) }
        library.commands.save(playlist)
        state.selected.subtract(ids)
    }

    /// Moves occurrences only when visible indexes exactly match the persisted entry order.
    func move(from offsets: IndexSet, to target: Int) {
        guard canReorder, var playlist, (0...playlist.entries.count).contains(target),
            offsets.allSatisfy({ playlist.entries.indices.contains($0) })
        else { return }
        let moved = offsets.map { playlist.entries[$0] }
        for index in offsets.reversed() { playlist.entries.remove(at: index) }
        let insertion = target - offsets.filter { $0 < target }.count
        playlist.entries.insert(contentsOf: moved, at: insertion)
        library.commands.save(playlist)
    }

    /// Commits the current rename draft to the latest playlist snapshot.
    func saveName() {
        guard var playlist else { return }
        playlist.name = newName
        library.commands.save(playlist)
    }

    /// Sorts playlist occurrences by the latest localized song titles.
    func sortByTitle() {
        guard var playlist else { return }
        let titles = Dictionary(uniqueKeysWithValues: library.tracks.map { ($0.id, $0.title) })
        playlist.entries.sort {
            (titles[$0.trackID] ?? "").localizedStandardCompare(titles[$1.trackID] ?? "")
                == .orderedAscending
        }
        library.commands.save(playlist)
    }

    /// Reverses the persisted playlist sequence without changing any occurrence identities.
    func reverse() {
        guard var playlist else { return }
        playlist.entries.reverse()
        library.commands.save(playlist)
    }
}
