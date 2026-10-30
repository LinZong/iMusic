import Foundation
import Observation

@MainActor @Observable
final class SongListViewModel {
  /// Observable library records and record-level actions.
  let library: LibraryViewModel
  /// Shared playback and song-action dependencies.
  let player: PlayerViewModel
  /// Song collection or playlist whose entries form the unfiltered scope of this page.
  let destination: LibraryDestination
  /// Query local to this song page; does not filter another tab or the Home feed.
  var search = ""
  /// Selected row occurrence identities used for macOS table selection and bulk actions.
  var selected: Set<UUID> = []
  /// macOS table comparators applied to the visible playback order.
  var sortOrder: [KeyPathComparator<SongRowData>] = []
  /// Whether the playlist rename alert is presented.
  var rename = false
  /// Draft playlist name entered in the rename alert.
  var newName = ""
  /// Whether the picker for adding songs to this playlist is presented.
  var addingTracks = false
  /// Whether the playlist name and cover editor is presented.
  var editingPlaylist = false
  /// Trashed songs awaiting confirmation before deleting their managed copies.
  var pendingPermanentDeletion: [Track] = []
  /// Trashed playlists matching this page's local Trash query.
  var deletedPlaylists: [Playlist] {
    library.deletedPlaylists.filter { LibrarySearch.matches(search, in: [$0.name]) }
  }
  /// Active playlist record for a playlist destination, or nil for a general song collection.
  var playlist: Playlist? {
    if case .playlist(let id) = destination { return library.playlists.first { $0.id == id } }
    return nil
  }
  /// Visible song occurrences after page-local filtering; preserves duplicate playlist entries.
  var rows: [SongRowData] {
    if let playlist {
      return playlist.entries.compactMap { entry in
        guard let track = library.tracks.first(where: { $0.id == entry.trackID }),
          LibrarySearch.matches(search, track: track)
        else { return nil }
        return SongRowData(id: entry.id, track: track)
      }
    }
    return library.songs(for: destination).filter { LibrarySearch.matches(search, track: $0) }.map {
      SongRowData(id: $0.id, track: $0)
    }
  }
  /// Creates an independent feature model with explicit service and state dependencies.
  init(library: LibraryViewModel, player: PlayerViewModel, destination: LibraryDestination) {
    self.library = library
    self.player = player
    self.destination = destination
  }
  /// Starts the visible sorted queue using occurrence identities, preserving duplicate playlist entries.
  func play(row: SongRowData?) {
    guard let row else { return }
    let ordered = rows.sorted(using: sortOrder)
    player.playback.playEntries(
      ordered.map { QueueEntry(id: $0.id, trackID: $0.track.id) }, startingAt: row.id)
  }
}
