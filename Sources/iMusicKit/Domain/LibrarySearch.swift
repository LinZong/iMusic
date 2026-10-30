import Foundation

enum LibrarySearch {
  /// Treats whitespace-only input as no query so empty-state and filtering behavior remain consistent.
  static func isEmpty(_ query: String) -> Bool {
    query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Matches a trimmed, case-, diacritic-, and width-insensitive query against the supplied page-owned fields.
  static func matches(_ query: String, in values: [String]) -> Bool {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).searchKey
    return normalized.isEmpty || values.contains { $0.searchKey.contains(normalized) }
  }

  /// Searches one song's title, performer, album credits, filename, and genre without accessing another page's state.
  static func matches(_ query: String, track: Track) -> Bool {
    matches(
      query,
      in: [
        track.title, track.artist, track.album, track.albumArtist, track.originalFilename,
        track.genre,
      ])
  }
}
