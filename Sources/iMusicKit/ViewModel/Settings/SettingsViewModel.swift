import Foundation
import Observation

@MainActor @Observable
final class SettingsViewModel {
    /// Observable library records and record-level actions.
    let library: LibraryViewModel
    /// Shared playback and song-action dependencies.
    let player: PlayerViewModel
    /// Persisted preferences used by this feature.
    let preferences: PreferencesViewModel
    /// Import and archive workflows requested from this feature.
    let imports: ImportViewModel
    /// Whether the consent dialog for manual online artwork search is presented.
    var onlineConsent = false
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
