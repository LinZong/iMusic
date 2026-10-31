import Observation

/// Supplies deleted playlists without filtering or changing the deleted-song page.
@MainActor @Observable
final class TrashPlaylistsViewModel {
    /// Shared recoverable playlist records and library mutations.
    let library: LibraryViewModel
    /// Search text retained when another Trash tab is selected.
    var search = ""
    /// Playlist awaiting explicit confirmation before its entries are permanently removed.
    var pendingDeletion: Playlist?
    /// Recoverable playlists matching this tab's name query.
    var playlists: [Playlist] {
        library.deletedPlaylists.filter { LibrarySearch.matches(search, in: [$0.name]) }
    }

    /// Binds this page to the shared library without sharing search or selection state.
    init(library: LibraryViewModel) {
        self.library = library
    }
}
