import Foundation
import Observation

/// Search and data projection specific to the playlists collection.
@MainActor @Observable
final class PlaylistCollectionViewModel {
    /// Observable active library records.
    let library: LibraryViewModel
    /// Playback dependencies for destinations opened from this collection.
    let player: PlayerViewModel
    /// Query local to this collection page.
    var search = ""
    /// Playlists whose names match this page's query; song metadata is not searched here.
    var items: [Playlist] {
        library.playlists.filter { LibrarySearch.matches(search, in: [$0.name]) }
    }
    /// Creates an independently searchable collection.
    init(library: LibraryViewModel, player: PlayerViewModel) {
        self.library = library
        self.player = player
    }
}
