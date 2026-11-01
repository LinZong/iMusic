import SwiftUI

#if os(iOS)
/// Traditional content search spacing for systems before Liquid Glass.
struct LegacyLibrarySearchInput: View {
    /// Query retained by the containing feature model.
    @Binding var text: String
    /// Localized description of the searchable content.
    let prompt: String
    /// Native input height follows the user's preferred body text size.
    @ScaledMetric(relativeTo: .body) private var fieldHeight: CGFloat = 36

    /// Preserves the existing search-to-summary spacing on older systems.
    var body: some View {
        LibrarySearchField(text: $text, prompt: prompt)
            .frame(height: fieldHeight)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .zIndex(1)
    }
}
#endif
