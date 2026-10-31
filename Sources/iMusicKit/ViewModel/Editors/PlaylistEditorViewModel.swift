import Foundation
import Observation

@MainActor @Observable
final class PlaylistEditorViewModel {
    /// Observable library records and record-level actions.
    let library: LibraryViewModel
    /// Editable playlist copy whose name and cover are committed when Save is chosen.
    var playlist: Playlist
    /// Whether this draft creates a new playlist rather than editing an existing one.
    let isCreating: Bool
    /// Whether the custom playlist-cover image importer is presented.
    var chooseCover = false
    /// Most recent custom-cover validation or file-access error shown in this editor.
    var error: String?
    /// Image validation and source access are independent of playlist draft state.
    private let artworkImporter: any ArtworkImporting
    /// Creates an independent feature model with explicit service and state dependencies.
    init(
        library: LibraryViewModel,
        playlist: Playlist,
        isCreating: Bool = false,
        artworkImporter: (any ArtworkImporting)? = nil
    ) {
        self.library = library
        self.playlist = playlist
        self.isCreating = isCreating
        self.artworkImporter = artworkImporter ?? ManagedArtworkImporter(vault: library.vault)
    }
    /// Applies a selected cover to this draft without persisting the playlist.
    func importArtwork(_ result: Result<URL, Error>) {
        do { playlist.artworkName = try artworkImporter.importFile(result.get()) } catch {
            self.error = error.localizedDescription
        }
    }
    /// Commits the edited playlist name and artwork reference.
    func save() { library.commands.save(playlist) }
}
