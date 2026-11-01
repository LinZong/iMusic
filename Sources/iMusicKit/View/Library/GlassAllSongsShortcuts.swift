import SwiftUI

#if os(iOS)
/// Native Liquid Glass navigation capsules floating above the All Songs scroll viewport.
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
                    .controlSize(.large)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            }
        }
        .scrollClipDisabled()
    }
}
#endif
