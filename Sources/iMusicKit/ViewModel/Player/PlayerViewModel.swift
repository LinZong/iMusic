import Foundation
import Observation

@MainActor @Observable
public final class PlayerViewModel {
    /// Library metadata and mutation boundary used by song actions.
    let library: LibraryViewModel
    /// Single shared playback session; never duplicated by a page.
    let playback: PlaybackCoordinator
    /// Saved preferences used by the player's metadata editor.
    let preferences: PreferencesViewModel
    /// Cross-window requests to show the player, queue, or metadata editor.
    let presentation: PresentationViewModel

    /// Creates the player model without owning search, import, or settings-page state.
    init(
        library: LibraryViewModel,
        playback: PlaybackCoordinator,
        preferences: PreferencesViewModel,
        presentation: PresentationViewModel
    ) {
        self.library = library
        self.playback = playback
        self.preferences = preferences
        self.presentation = presentation
    }

}
