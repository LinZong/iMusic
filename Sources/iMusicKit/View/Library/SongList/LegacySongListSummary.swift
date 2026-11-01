import SwiftUI

/// Preserves the existing summary presentation on older touch systems and desktop.
struct LegacySongListSummary<Summary: View, Actions: View>: View {
    /// Shared localized count and duration.
    @ViewBuilder var summary: () -> Summary
    /// Feature-owned controls remain separate native buttons.
    @ViewBuilder var actions: () -> Actions

    /// Keeps the older opaque touch surface scoped to its own inset bounds.
    var body: some View {
        HStack {
            summary()
                #if os(macOS)
            .font(.body)
                #else
            .font(.caption)
                #endif
            Spacer()
            actions()
        }
        .padding(16)
        #if os(iOS)
        .background(.background, ignoresSafeAreaEdges: [])
        #endif
    }
}
