import SwiftUI

struct ArtworkView: View {
    /// Song supplying the cover file name; nil renders the standard music placeholder.
    let track: Track?
    /// Managed artwork directory used to resolve the cover file.
    let vault: MediaVault
    /// Artwork edge length in points, also used to choose the decoded thumbnail resolution.
    var size: CGFloat = 48
    /// Resolves layout changes as well as cover changes to a distinct thumbnail request.
    private var request: Request {
        Request(
            url: vault.artworkURL(track?.artworkName),
            pixels: Int(max(1, min(1_000, size * 2)))
        )
    }
    private struct Request: Equatable {
        /// Managed cover location, including the library that owns it.
        let url: URL?
        /// Longest decoded edge in pixels.
        let pixels: Int
    }
    /// Asynchronously loaded thumbnail for the currently displayed cover.
    @State private var image: CGImage?
    /// Renders decoded artwork or a placeholder and reloads when the cover or its size changes.
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
                Image(systemName: "music.note")
                    .font(.system(size: max(1, size * 0.32), weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(
            RoundedRectangle(cornerRadius: min(24, size * 0.13))
        )
        .accessibilityHidden(true)
        .task(id: request) {
            let request = request
            image = nil
            guard let url = request.url else { return }
            let loaded =
                await Task.detached {
                    ArtworkCache.shared.image(at: url, size: request.pixels)
                }
                .value
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
