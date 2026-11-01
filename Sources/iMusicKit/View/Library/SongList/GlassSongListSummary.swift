import SwiftUI

#if os(iOS)
/// A single glass control surface for statistics and independent feature actions.
@available(iOS 26.0, *)
struct GlassSongListSummary<Summary: View, Actions: View>: View {
    /// Localized statistics derived by the shared summary owner.
    @ViewBuilder var summary: () -> Summary
    /// Feature-supplied controls; the glass surface never gains a row-wide action.
    @ViewBuilder var actions: () -> Actions

    /// Uses regular adaptive glass with clear space around its native decoration.
    var body: some View {
        HStack(spacing: 12) {
            summary().font(.subheadline)
            Spacer(minLength: 8)
            actions().buttonStyle(.borderless)
        }
        .frame(minHeight: 44)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }
}
#endif
