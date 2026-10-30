import Foundation
import Observation

@MainActor @Observable
final class PlaylistSongPickerViewModel {
    /// Observable library records and record-level actions.
    let library: LibraryViewModel
    /// Playlist receiving the selected song occurrences after confirmation.
    let playlist: Playlist
    /// Selected song identities to append to the destination playlist.
    var selected: Set<UUID> = []
    /// Query local to the song picker, independent of the underlying playlist search.
    var search = ""
    /// Creates an independent feature model with explicit service and state dependencies.
    init(library: LibraryViewModel, playlist: Playlist) {
        self.library = library
        self.playlist = playlist
    }

    /// Songs matching this picker's query, independent of the underlying playlist page.
    var visibleTracks: [Track] {
        library.tracks.filter { LibrarySearch.matches(search, track: $0) }
    }
    /// Appends selected songs in library order while preserving existing playlist occurrences.
    func addSelection() {
        library.add(library.tracks.filter { selected.contains($0.id) }, to: playlist)
    }
    /// Toggles one selected song without changing another picker's selection.
    func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}
