import SwiftUI

/// Selects the platform presentation without owning shortcut destinations or navigation state.
struct AllSongsShortcuts<Links: View>: View {
    /// Feature-owned navigation links rendered by the selected presentation.
    @ViewBuilder var links: () -> Links

    /// Keeps version selection separate from the concrete control layouts.
    var body: some View {
        Group {
            #if os(iOS)
            if #available(iOS 26.0, *) {
                GlassAllSongsShortcuts(links: links)
            } else {
                LegacyAllSongsShortcuts(links: links)
            }
            #else
            LegacyAllSongsShortcuts(links: links)
            #endif
        }
    }
}
