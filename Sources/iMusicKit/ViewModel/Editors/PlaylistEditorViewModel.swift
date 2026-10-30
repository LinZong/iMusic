import Foundation
import ImageIO
import Observation

@MainActor @Observable
final class PlaylistEditorViewModel {
  /// Observable library records and record-level actions.
  let library: LibraryViewModel
  /// Editable playlist copy whose name and cover are committed when Save is chosen.
  var playlist: Playlist
  /// Whether the custom playlist-cover image importer is presented.
  var chooseCover = false
  /// Most recent custom-cover validation or file-access error shown in this editor.
  var error: String?
  /// Creates an independent feature model with explicit service and state dependencies.
  init(library: LibraryViewModel, playlist: Playlist) {
    self.library = library
    self.playlist = playlist
  }
  /// Reads and validates a selected cover into the playlist draft without persisting it.
  func importArtwork(_ result: Result<URL, Error>) {
    do {
      let url = try result.get()
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= 20_000_000 else {
        throw MusicError.unavailable(L10n.text("Choose an image smaller than 20 MB."))
      }
      let data = try Data(contentsOf: url)
      guard CGImageSourceCreateWithData(data as CFData, nil) != nil else {
        throw MusicError.unavailable(L10n.text("Unable to read this image."))
      }
      let name = UUID().uuidString + ".image"
      try data.write(to: library.vault.artwork.appendingPathComponent(name), options: .atomic)
      playlist.artworkName = name
    } catch { self.error = error.localizedDescription }
  }
  /// Commits the edited playlist name and artwork reference.
  func save() { library.save(playlist) }
}
