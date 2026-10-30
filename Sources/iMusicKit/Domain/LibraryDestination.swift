import Foundation

public enum FileImportPurpose { case audio, folder, backup }

public enum LibraryDestination: Hashable {
  case home, songs, artists, albums, genres, playlists, favorites, trash, settings
  case artist(String)
  case album(String)
  case genre(String)
  case playlist(UUID)
  /// Localized navigation title, or the selected category's user-provided name.
  public var title: String {
    switch self {
    case .home: L10n.text("Home")
    case .songs: L10n.text("All Songs")
    case .artists: L10n.text("Artists")
    case .albums: L10n.text("Albums")
    case .playlists: L10n.text("Playlists")
    case .favorites: L10n.text("Favorites")
    case .trash: L10n.text("Trash")
    case .settings: L10n.text("Settings")
    case .artist(let name): name.isEmpty ? L10n.text("Unknown Artist") : name
    case .album: L10n.text("Albums")
    case .playlist: L10n.text("Playlists")
    case .genres: L10n.text("Genres")
    case .genre(let name): name.isEmpty ? L10n.text("Uncategorized") : name
    }
  }
  /// SF Symbol name used for this destination in sidebars and tab bars.
  public var symbol: String {
    switch self {
    case .home: "house"
    case .songs: "music.note"
    case .artists, .artist: "person.2"
    case .albums, .album: "square.stack"
    case .playlists, .playlist: "music.note.list"
    case .favorites: "heart"
    case .trash: "trash"
    case .settings: "gearshape"
    case .genres, .genre: "guitars"
    }
  }
}
