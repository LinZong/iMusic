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
    struct Request: Equatable {
        /// Managed cover location, including the library that owns it.
        let url: URL?
        /// Longest decoded edge in pixels.
        let pixels: Int
    }
    /// View-local results and generations; native accessory reconstruction can replace this state.
    @State private var loading = LoadingState()

    /// Matches decoded results to requests and rejects cancelled or superseded task completions.
    struct LoadingState {
        /// Last completed request and its optional decoded thumbnail.
        private var result: Result?
        /// Request currently admitted to publish a result.
        private var activeRequest: Request?
        /// Distinguishes successive loads, including returning to the same cover request.
        private var generation: UUID?

        private struct Result {
            /// Cover location and resolution associated with this result.
            let request: Request
            /// Decoded image, or nil when the source has no usable artwork.
            let image: CGImage?
        }

        /// Resolves the first frame using matching local state or a memory-only cache lookup.
        func image(for request: Request, cache: ArtworkCache = .shared) -> CGImage? {
            if let result, result.request == request, let image = result.image { return image }
            guard let url = request.url else { return nil }
            return cache.cachedImage(at: url, size: request.pixels)
        }

        /// Starts a new load without clearing an already displayed result for the same request.
        mutating func begin(_ request: Request) -> UUID {
            let token = UUID()
            activeRequest = request
            generation = token
            return token
        }

        /// Publishes only the active, uncancelled load; an old result never changes a newer cover.
        mutating func finish(_ image: CGImage?, for request: Request, generation: UUID) {
            guard !Task.isCancelled, activeRequest == request, self.generation == generation else {
                return
            }
            result = Result(request: request, image: image)
        }
    }

    /// Renders decoded artwork or a placeholder and reloads when the cover or its size changes.
    var body: some View {
        let request = request
        let image = loading.image(for: request)
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
            let generation = loading.begin(request)
            guard let url = request.url else {
                loading.finish(nil, for: request, generation: generation)
                return
            }
            if let image = loading.image(for: request) {
                loading.finish(image, for: request, generation: generation)
                return
            }
            let loaded =
                await Task.detached {
                    ArtworkCache.shared.image(at: url, size: request.pixels)
                }
                .value
            loading.finish(loaded, for: request, generation: generation)
        }
    }
}
