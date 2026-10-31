import SwiftUI

/// Chooses the playback bar from available width rather than device identity or orientation.
struct MiniPlayer: View {
    /// Shared feature state retained when the bar changes between compact and expanded layouts.
    let model: PlayerViewModel
    /// Scales the expanded layout's width budget with the metadata's preferred text size.
    @ScaledMetric(relativeTo: .subheadline) private var expandedMinimumWidth: CGFloat = 680

    /// Uses desktop controls on wide touch layouts and preserves the compact bar on narrow ones.
    var body: some View {
        #if os(macOS)
        ExpandedMiniPlayer(model: model)
        #else
        ViewThatFits(in: .horizontal) {
            ExpandedMiniPlayer(model: model).frame(minWidth: expandedMinimumWidth)
            CompactMiniPlayer(model: model)
        }
        #endif
    }
}
