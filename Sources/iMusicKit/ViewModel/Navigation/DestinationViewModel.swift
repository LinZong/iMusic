import Foundation
import Observation

@MainActor @Observable
final class DestinationViewModel {
    /// Observable library records and record-level actions.
    let library: LibraryViewModel
    /// Shared playback and song-action dependencies.
    let player: PlayerViewModel
    /// Persisted preferences used by this feature.
    let preferences: PreferencesViewModel
    /// Import and archive workflows requested from this feature.
    let imports: ImportViewModel
    /// Route owned by this destination model.
    let destination: LibraryDestination
    /// Whether the new-playlist editor is presented.
    var newPlaylist = false
    /// Creates an independent feature model with explicit service and state dependencies.
    init(
        library: LibraryViewModel,
        player: PlayerViewModel,
        preferences: PreferencesViewModel,
        imports: ImportViewModel,
        destination: LibraryDestination
    ) {
        self.library = library
        self.player = player
        self.preferences = preferences
        self.imports = imports
        self.destination = destination
    }
}
