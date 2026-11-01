import SwiftUI

#if os(iOS)
/// Lets the native tab accessory own its glass, safe area, and scroll-content clearance.
@available(iOS 26.0, *)
struct GlassTabFooter<Footer: View>: ViewModifier {
    /// Whether the scene has playback controls to present.
    let isPresented: Bool
    /// Existing scene controls; the layout owns no playback or operation state.
    @ViewBuilder var footer: () -> Footer

    /// Preserves tab and navigation identity when the accessory becomes visible.
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: isPresented, content: footer)
        } else {
            content.tabViewBottomAccessory {
                if isPresented { footer() }
            }
        }
    }
}
#endif
