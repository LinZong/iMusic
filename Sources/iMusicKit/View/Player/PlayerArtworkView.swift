import SwiftUI

/// PlayerArtworkView owns one part of the full-player presentation.
struct PlayerArtworkView: View {
    /// Shared song actions, artwork storage, and playback dependencies.
    let player: PlayerViewModel
    /// Allocated cover dimension in points.
    let size: CGFloat
    /// Renders this player component using the shared playback session.
    var body: some View {
        ArtworkView(
            track: player.playback.track,
            vault: player.library.vault,
            size: size
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        // Composite the finished cover before applying a shadow to its outer silhouette.
        .compositingGroup()
        .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 10)
        .accessibilityHidden(true)
    }
}
