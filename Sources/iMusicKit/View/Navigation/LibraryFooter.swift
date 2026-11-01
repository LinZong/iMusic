import SwiftUI

struct LibraryFooter: View {
    /// Shared playback and operation status used by the scene footer.
    let model: RootViewModel
    /// Import progress, playback errors, and the current-song mini player below the main content.
    var body: some View {
        VStack(spacing: 0) {
            LibraryOperationStatus(model: model)
            if model.player.playback.track != nil { MiniPlayer(model: model.player) }
        }
    }
}
