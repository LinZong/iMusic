import Foundation
import Observation

/// Search and data projection specific to the albums collection.
@MainActor @Observable
final class AlbumCollectionViewModel {
    /// Observable active library records.
    let library: LibraryViewModel
    /// Playback dependencies for destinations opened from this collection.
    let player: PlayerViewModel
    /// Query local to this collection page.
    var search = ""
    /// Album representatives matching album title or artist information on this page.
    var items: [Track] {
        library.catalog.albums.filter {
            LibrarySearch.matches(search, in: [$0.displayAlbum, $0.displayArtist, $0.albumArtist])
        }
    }
    /// Creates an independently searchable collection.
    init(library: LibraryViewModel, player: PlayerViewModel) {
        self.library = library
        self.player = player
    }
}
