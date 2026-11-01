import SwiftUI

/// Selects platform presentation while retaining a single shared playback session.
struct MiniPlayer: View {
    /// Feature state retained when the bar changes appearance or available width.
    let model: PlayerViewModel

    /// Dispatches presentation without changing the shared playback controls or timeline.
    @ViewBuilder var body: some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            GlassMiniPlayer(model: model)
        } else {
            LegacyMiniPlayer(model: model)
        }
        #else
        LegacyMiniPlayer(model: model)
        #endif
    }
}
