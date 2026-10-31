import SwiftUI

/// PlayerArtworkView owns one part of the full-player presentation.
struct PlayerArtworkView: View {
    /// Shared song actions, artwork storage, and playback dependencies.
    let player: PlayerViewModel
    /// Allocated cover dimension in points.
    let size: CGFloat
    /// Renders this player component using the shared playback session.
    var body: some View {
        Group {
            if player.preferences.vinyl {
                ZStack {
                    cover(size: size)
                    Circle().fill(.black.opacity(0.65))
                    Circle().stroke(.white.opacity(0.15), lineWidth: 2).padding(18)
                    cover(size: size * 0.44).clipShape(Circle())
                    Circle().fill(.background).frame(width: 14, height: 14)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                cover(size: size)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        // Composite the finished cover before applying a shadow to its outer silhouette.
        .compositingGroup()
        .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 10)
        .accessibilityHidden(true)

    }
    /// Uses the same managed cover loader for the full-size artwork and the vinyl label.
    private func cover(size: CGFloat) -> some View {
        ArtworkView(
            track: player.playback.track,
            vault: player.library.vault,
            size: size
        )
    }
}
