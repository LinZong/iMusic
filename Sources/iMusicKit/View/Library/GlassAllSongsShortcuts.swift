import SwiftUI

#if os(iOS)
/// Native Liquid Glass navigation capsules inside the All Songs scrolling header.
@available(iOS 26.0, *)
struct GlassAllSongsShortcuts<Links: View>: View {
    /// Feature-owned destinations; this layout supplies only their appearance and spacing.
    @ViewBuilder var links: () -> Links

    /// Groups glass rendering and reserves drawing space inside the horizontal scroll document.
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 12) { links() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
                    .padding(.horizontal, 16)
                    .padding(.top, 0)
                    .padding(.bottom, 8)
            }
        }
        .scrollClipDisabled()
        .accessibilityIdentifier("allSongs.shortcuts")
    }
}
#endif
