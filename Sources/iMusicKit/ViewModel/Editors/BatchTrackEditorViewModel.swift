import Foundation
import Observation

@MainActor @Observable
final class BatchTrackEditorViewModel {
    /// Observable library records and record-level actions.
    let library: LibraryViewModel
    /// Selected songs whose metadata will be updated together when Save is chosen.
    let tracks: [Track]
    /// Replacement performer credit, applied only when its edit toggle is enabled.
    var artist = ""
    /// Replacement album title, applied only when its edit toggle is enabled.
    var album = ""
    /// Replacement album artist credit, applied only when its edit toggle is enabled.
    var albumArtist = ""
    /// Replacement genre tag, applied only when its edit toggle is enabled.
    var genre = ""
    /// Whether to replace the artist field on every selected song.
    var editArtist = false
    /// Whether to replace the album field on every selected song.
    var editAlbum = false
    /// Whether to replace the album-artist field on every selected song.
    var editAlbumArtist = false
    /// Whether to replace the genre field on every selected song.
    var editGenre = false
    /// Creates an independent feature model with explicit service and state dependencies.
    init(library: LibraryViewModel, tracks: [Track]) {
        self.library = library
        self.tracks = tracks
    }

    /// Applies only explicitly enabled fields and preserves every unchecked value.
    func save() {
        for var track in tracks {
            if editArtist { track.artist = artist }
            if editAlbum { track.album = album }
            if editAlbumArtist { track.albumArtist = albumArtist }
            if editGenre { track.genre = genre }
            library.save(track)
        }
    }
}
