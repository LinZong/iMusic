import SwiftUI

#if os(iOS)
/// Places the glass summary at the bottom of the song viewport, above any scene footer.
@available(iOS 26.0, *)
struct GlassSongListContent<Content: View, Summary: View>: View {
    /// Native song scroller with its content-centered placeholder.
    @ViewBuilder var content: () -> Content
    /// Shared statistics and feature actions, without playback or navigation dependencies.
    @ViewBuilder var summary: () -> Summary

    /// Uses the inherited safe area to clear the mini player and keep the last song reachable.
    var body: some View {
        content()
            .safeAreaBar(edge: .bottom, spacing: 0) { summary() }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
    }
}
#endif
