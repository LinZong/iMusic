import Foundation
import Observation

/// Search and data projection specific to the genres collection.
@MainActor @Observable
final class GenreCollectionViewModel {
    /// Observable active library records.
    let library: LibraryViewModel
    /// Playback dependencies for destinations opened from this collection.
    let player: PlayerViewModel
    /// Query local to this collection page.
    var search = ""
    /// Genre names matching this page's query, including the localized uncategorized label.
    var items: [String] {
        Array(Set(library.tracks.map(\.genre))).sorted()
            .filter {
                LibrarySearch.matches(search, in: [$0.isEmpty ? L10n.text("Uncategorized") : $0])
            }
    }
    /// Creates an independently searchable collection.
    init(library: LibraryViewModel, player: PlayerViewModel) {
        self.library = library
        self.player = player
    }
}
