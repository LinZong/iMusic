import SwiftUI

/// Traditional edge-to-edge playback surface for desktop and older touch systems.
struct LegacyMiniPlayer: View {
    /// Shared feature state, including the existing playback timeline.
    let model: PlayerViewModel
    /// Width budget scales with metadata text and preserves the previous adaptive threshold.
    @ScaledMetric(relativeTo: .subheadline) private var expandedMinimumWidth: CGFloat = 680

    /// Keeps legacy progress placement and system bar material unchanged.
    var body: some View {
        #if os(macOS)
        expanded.background(.bar)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("miniPlayer.bar")
        #else
        ViewThatFits(in: .horizontal) {
            expanded.frame(minWidth: expandedMinimumWidth)
            VStack(spacing: 0) {
                CompactMiniPlayer(model: model)
                    .padding(.vertical, 10)
                PlaybackProgressLine(playback: model.playback)
            }
        }
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("miniPlayer.bar")
        #endif
    }

    /// Wide controls keep their progress line above the transport region on legacy systems.
    private var expanded: some View {
        VStack(spacing: 0) {
            PlaybackProgressLine(playback: model.playback)
            ExpandedMiniPlayer(model: model)
                .frame(height: 72)
        }
    }
}
