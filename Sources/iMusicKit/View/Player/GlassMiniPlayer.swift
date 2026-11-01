import SwiftUI

#if os(iOS)
/// Floating playback controls on one native glass surface, independent of the song viewport.
@available(iOS 26.0, *)
struct GlassMiniPlayer: View {
    /// Existing feature state; no extra queue, clock, or playback observation is introduced.
    let model: PlayerViewModel
    /// Native tab accessories already supply a glass surface and surrounding spacing.
    @Environment(\.tabViewBottomAccessoryPlacement) private var accessoryPlacement
    /// Wide controls use the same text-scaled width budget as the legacy player.
    @ScaledMetric(relativeTo: .subheadline) private var expandedMinimumWidth: CGFloat = 680

    /// Insets the glass from screen edges and keeps progress rendering in its timeline child.
    @ViewBuilder var body: some View {
        if accessoryPlacement != nil {
            accessoryControls
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("miniPlayer.bar")
        } else {
            controls
                .glassEffect(.regular, in: .rect(cornerRadius: 32))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("miniPlayer.bar")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
    }

    /// Both system and custom surfaces use adaptive controls and isolated progress rendering.
    private var controls: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                ExpandedMiniPlayer(model: model)
                    .frame(minWidth: expandedMinimumWidth, minHeight: 72, maxHeight: 72)
                CompactMiniPlayer(model: model).padding(.vertical, 10)
            }
            PlaybackProgressLine(playback: model.playback)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
    }

    /// Fits the native accessory height and draws progress inside its glass boundary.
    private var accessoryControls: some View {
        ViewThatFits(in: .horizontal) {
            ExpandedMiniPlayer(model: model)
                .frame(minWidth: expandedMinimumWidth, minHeight: 52, maxHeight: 52)
            CompactMiniPlayer(model: model).padding(.vertical, 4)
        }
        .overlay(alignment: .bottom) {
            PlaybackProgressLine(playback: model.playback)
                .padding(.horizontal, 24)
                .padding(.bottom, 2)
        }
    }
}
#endif
