import Foundation
import Observation

@MainActor @Observable
final class CollectionViewModel {
  /// Observable library records and record-level actions.
  let library: LibraryViewModel
  /// Shared playback and song-action dependencies.
  let player: PlayerViewModel
  /// Collection category displayed by this grid: artists, albums, genres, or playlists.
  let kind: CollectionKind
  /// Query owned by this collection page; never shared with song lists or another tab.
  var search = ""
  /// Localized prompt describing the collection that this page actually searches.
  var searchPrompt: String {
    switch kind {
    case .artists: L10n.text("Search Artists")
    case .albums: L10n.text("Search Albums")
    case .genres: L10n.text("Search Genres")
    case .playlists: L10n.text("Search Playlists")
    }
  }
  /// Artist names matching this page's query, independent of any song-page search.
  var artists: [String] { library.artists.filter { LibrarySearch.matches(search, in: [$0]) } }
  /// Album representatives matching album title or artist information on this page.
  var albums: [Track] {
    library.albums.filter {
      LibrarySearch.matches(search, in: [$0.displayAlbum, $0.displayArtist, $0.albumArtist])
    }
  }
  /// Genre names matching this page's query, including the localized uncategorized label.
  var genres: [String] {
    Array(Set(library.tracks.map(\.genre))).sorted().filter {
      LibrarySearch.matches(search, in: [$0.isEmpty ? L10n.text("Uncategorized") : $0])
    }
  }
  /// Playlists whose names match this page's query; song metadata is not searched here.
  var playlists: [Playlist] {
    library.playlists.filter { LibrarySearch.matches(search, in: [$0.name]) }
  }
  /// Whether the currently selected collection has any visible results.
  var isEmpty: Bool {
    switch kind {
    case .artists: artists.isEmpty
    case .albums: albums.isEmpty
    case .genres: genres.isEmpty
    case .playlists: playlists.isEmpty
    }
  }
  /// Creates an independent feature model with explicit service and state dependencies.
  init(library: LibraryViewModel, player: PlayerViewModel, kind: CollectionKind) {
    self.library = library
    self.player = player
    self.kind = kind
  }
}
