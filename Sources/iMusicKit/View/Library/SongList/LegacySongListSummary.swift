import SwiftUI

/// Preserves the existing summary presentation on older touch systems and desktop.
struct LegacySongListSummary<Summary: View, Actions: View>: View {
    /// Shared localized count and duration.
    @ViewBuilder var summary: () -> Summary
    /// Feature-owned controls remain separate native buttons.
    @ViewBuilder var actions: () -> Actions

    /// Keeps touch spacing compact while preserving the controls' native hit areas.
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
        .padding(.horizontal, 16)
        #if os(iOS)
        .padding(.vertical, 8)
        .background(.background, ignoresSafeAreaEdges: [])
        #else
        .padding(.vertical, 16)
        #endif
    }
}
