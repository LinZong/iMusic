import Observation

/// Owns the Trash category and retains independent feature state while switching tabs.
@MainActor @Observable
final class TrashViewModel {
    /// Categories presented by the native segmented tab selector.
    enum Category: Hashable {
        case songs, playlists
    }

    /// Currently visible recovery category; opening Trash starts with deleted songs.
    var category: Category = .songs
    /// Deleted-song search, selection, sorting, and confirmation state.
    let songs: TrashSongsViewModel
    /// Deleted-playlist search and confirmation state, independent from deleted songs.
    let playlists: TrashPlaylistsViewModel

    /// Reads a category's retained query independently of native search presentation state.
    func query(for category: Category) -> String {
        category == .songs ? songs.state.search : playlists.search
    }

    /// Accepts edits only from the visible tab; an outgoing search control may clear its binding.
    func updateSearch(_ query: String, in category: Category) {
        guard self.category == category else { return }
        if category == .songs {
            songs.state.search = query
        } else {
            playlists.search = query
        }
    }

    /// Creates persistent child models for the two recovery categories.
    init(library: LibraryViewModel) {
        songs = TrashSongsViewModel(library: library)
        playlists = TrashPlaylistsViewModel(library: library)
    }
}
