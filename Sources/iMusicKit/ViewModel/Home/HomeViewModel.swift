import Foundation
import Observation

@MainActor @Observable
final class HomeViewModel {
    /// Observable library records and record-level actions.
    let library: LibraryViewModel
    /// Shared playback and song-action dependencies.
    let player: PlayerViewModel
    /// Persisted preferences used by this feature.
    let preferences: PreferencesViewModel
    /// Import and archive workflows requested from this feature.
    let imports: ImportViewModel

    /// Recently added queue order shared by the preview and playback action.
    var recentTracks: [Track] { library.tracks.sorted { $0.addedAt > $1.addedAt } }
    /// Number of active favorites displayed by the Home tile.
    var favoriteCount: Int { library.tracks.filter(\.isFavorite).count }
    /// Total actual listening seconds displayed by the Home statistics shortcut.
    var listeningSeconds: Double { library.events.reduce(0) { $0 + $1.seconds } }

    /// Creates an independent feature model with explicit service and state dependencies.
    init(
        library: LibraryViewModel,
        player: PlayerViewModel,
        preferences: PreferencesViewModel,
        imports: ImportViewModel
    ) {
        self.library = library
        self.player = player
        self.preferences = preferences
        self.imports = imports
    }
}
