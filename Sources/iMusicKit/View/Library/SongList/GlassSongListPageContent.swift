import SwiftUI

#if os(iOS)
/// Extends the song viewport beneath fixed feature controls using the system glass-bar layout.
@available(iOS 26.0, *)
struct GlassSongListPageContent<Header: View, Content: View>: View {
    /// Existing song list, including its fixed summary and feature-owned actions.
    @ViewBuilder var content: () -> Content
    /// Native search and optional feature controls without a shared background surface.
    @ViewBuilder var header: () -> Header

    /// Reserves initial content clearance while letting scrolled songs pass beneath the capsules.
    var body: some View {
        content()
            .safeAreaBar(edge: .top, spacing: 0) {
                VStack(spacing: 0, content: header)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
    }
}
#endif
