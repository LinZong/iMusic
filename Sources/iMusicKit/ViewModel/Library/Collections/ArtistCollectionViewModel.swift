import Foundation
import Observation

/// Search and data projection specific to the artists collection.
@MainActor @Observable
final class ArtistCollectionViewModel {
    /// Observable active library records.
    let library: LibraryViewModel
    /// Playback dependencies for destinations opened from this collection.
    let player: PlayerViewModel
    /// Query local to this collection page.
    var search = ""
    /// Artist names matching this page's query, independent of any song-page search.
    var items: [String] {
        library.catalog.artists.filter { LibrarySearch.matches(search, in: [$0]) }
    }
    /// Creates an independently searchable collection.
    init(library: LibraryViewModel, player: PlayerViewModel) {
        self.library = library
        self.player = player
    }
}
