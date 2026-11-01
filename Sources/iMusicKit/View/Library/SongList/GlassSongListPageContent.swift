import SwiftUI

#if os(iOS)
/// Extends the song viewport beneath fixed feature controls using the system glass-bar layout.
@available(iOS 26.0, *)
struct GlassSongListPageContent<Header: View, Content: View>: View {
    /// Feature-owned controls, such as navigation capsules, with no shared background surface.
    @ViewBuilder var header: () -> Header
    /// Existing song list, including its fixed summary and feature-owned actions.
    @ViewBuilder var content: () -> Content

    /// Reserves initial content clearance while letting scrolled songs pass beneath the capsules.
    var body: some View {
        content()
            .safeAreaBar(edge: .top, spacing: 0) { header() }
            .scrollEdgeEffectStyle(.soft, for: .top)
    }
}
#endif
