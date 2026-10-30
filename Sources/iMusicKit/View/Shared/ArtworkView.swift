import SwiftUI

struct ArtworkView: View {
    /// Song supplying the cover file name; nil renders the standard music placeholder.
    let track: Track?
    /// Managed artwork directory used to resolve the cover file.
    let vault: MediaVault
    /// Artwork edge length in points, also used to choose the decoded thumbnail resolution.
    var size: CGFloat = 48
    /// Asynchronously loaded thumbnail for the currently displayed cover.
    @State private var image: CGImage?
    /// Renders decoded artwork or a placeholder and reloads it when the cover file name changes.
    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else {
                LinearGradient(
                    colors: [.indigo.opacity(0.55), .purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note").font(.system(size: size * 0.32, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(cornerRadius: min(24, size * 0.13))
        )
        .accessibilityHidden(true)
        .task(id: track?.artworkName) {
            image = nil
            guard let url = vault.artworkURL(track?.artworkName) else { return }
            let pixels = Int(min(1_000, size * 2))
            image = await Task.detached { ArtworkCache.shared.image(at: url, size: pixels) }.value
        }
    }
}
