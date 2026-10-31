import SwiftUI

/// Layout and search foundation; the caller supplies collection-specific cards and navigation.
struct CollectionGrid<Content: View>: View {
    /// Page-local collection query.
    @Binding var search: String
    /// Localized prompt describing the actual collection type.
    let searchPrompt: String
    /// Whether the current source has any matching cards.
    let isEmpty: Bool
    /// Typed feature cards, including their navigation and context actions.
    @ViewBuilder var content: () -> Content

    /// Centers empty states and lays out cards without interpreting a collection kind.
    var body: some View {
        Group {
            if isEmpty && !LibrarySearch.isEmpty(search) {
                ContentUnavailableView.search(text: search)
            } else if isEmpty {
                ContentUnavailableView(
                    L10n.text("Nothing Here Yet"),
                    systemImage: "square.stack",
                    description: Text(
                        L10n.text("Import music or create a playlist with the plus button.")
                    )
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 145, maximum: 210), spacing: 20)],
                        alignment: .leading,
                        spacing: 24,
                        content: content
                    )
                    .buttonStyle(.plain).padding(24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .librarySearch(text: $search, prompt: searchPrompt)
    }
}
