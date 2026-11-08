import SwiftUI

/// Retains the existing bordered shortcuts on older touch systems and desktop.
struct LegacyAllSongsShortcuts<Links: View>: View {
    /// Feature-owned navigation links shared with the current touch presentation.
    @ViewBuilder var links: () -> Links

    /// Keeps native buttons inside the scroll document's pointer-hit bounds.
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack { links() }
                .buttonStyle(.bordered)
                .padding(.horizontal)
        }
        .padding(.top, 12)
        #if os(iOS)
        // Only legacy touch lists need an opaque row surface; desktop inherits its window surface.
        .background(.background, ignoresSafeAreaEdges: [])
        #endif
        .accessibilityIdentifier("allSongs.shortcuts")
    }
}
