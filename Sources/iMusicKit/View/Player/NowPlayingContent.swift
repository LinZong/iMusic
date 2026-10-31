import SwiftUI

/// NowPlayingContent owns one part of the full-player presentation.
struct NowPlayingContent: View {
    /// Local full-player presentation state and shared playback dependencies.
    let model: NowPlayingViewModel
    #if os(macOS)
    /// Focus binding owned by the full player's navigation scope.
    let playbackFocus: FocusState<Bool>.Binding
    #endif
    /// Accessibility sizes use a scrollable single column.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Renders this player component using the shared playback session.
    var body: some View {
        GeometryReader { geometry in
            // A wide portrait sheet still needs a single column; text accessibility takes
            // priority.
            let columns =
                geometry.size.width >= 680
                && geometry.size.width > geometry.size.height
                && !dynamicTypeSize.isAccessibilitySize
            let inset: CGFloat = columns ? 32 : 24
            let contentWidth = max(0, min(geometry.size.width - inset * 2, columns ? 960 : 420))
            // Reserve vertical space for metadata and controls before allocating artwork on a
            // phone.
            let coverSize =
                columns
                ? min(
                    360,
                    max(160, (contentWidth - 40) * 0.46),
                    max(160, geometry.size.height - 64)
                )
                : min(contentWidth, max(180, geometry.size.height - 390))
            ScrollView {
                Group {
                    if columns {
                        HStack(alignment: .center, spacing: 40) {
                            PlayerArtworkView(player: model.player, size: coverSize)
                            controls(compact: geometry.size.height < 420)
                                .frame(maxWidth: 420)
                        }
                    } else {
                        VStack(spacing: 28) {
                            PlayerArtworkView(player: model.player, size: coverSize)
                            controls(compact: false)
                        }
                    }
                }
                .frame(width: contentWidth)
                .padding(.horizontal, inset)
                .padding(.vertical, columns ? (geometry.size.height < 420 ? 12 : 32) : 20)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .background {
                Rectangle().fill(.background)
                    // Isolate the opaque canvas from transient sheet materials.
                    .environment(\.backgroundMaterial, nil)
                    .overlay {
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.06), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
            }
        }

    }
    /// Passes sheet-owned keyboard focus through the presentation composition boundary.
    private func controls(compact: Bool) -> some View {
        #if os(macOS)
        NowPlayingControls(model: model, compact: compact, playbackFocus: playbackFocus)
        #else
        NowPlayingControls(model: model, compact: compact)
        #endif
    }

}
