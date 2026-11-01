import SwiftUI

#if os(iOS)
/// Floating native Liquid Glass search with space for its out-of-bounds decoration.
@available(iOS 26.0, *)
struct GlassLibrarySearchInput: View {
    /// Query retained by the containing feature model.
    @Binding var text: String
    /// Localized description of the searchable content.
    let prompt: String
    /// Native search height scales with the preferred body text size.
    @ScaledMetric(relativeTo: .body) private var fieldHeight: CGFloat = 36

    /// Leaves the system search field's own glass surface and shadow unobstructed.
    var body: some View {
        LibrarySearchField(text: $text, prompt: prompt)
            .frame(height: fieldHeight)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .zIndex(1)
    }
}
#endif
