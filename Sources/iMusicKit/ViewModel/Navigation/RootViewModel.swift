import Foundation
import Observation

@MainActor @Observable
final class RootViewModel {
    /// Observable library records and record-level actions.
    let library: LibraryViewModel
    /// Shared playback and song-action dependencies.
    let player: PlayerViewModel
    /// Persisted preferences used by this feature.
    let preferences: PreferencesViewModel
    /// Import and archive workflows requested from this feature.
    let imports: ImportViewModel
    /// Composition-root lifecycle hook; never exposes the application container.
    var launch: () async -> Void = {}
    /// Current sidebar destination; compact iPhone layouts use independent tab navigation instead.
    var selection: LibraryDestination? = .home
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
