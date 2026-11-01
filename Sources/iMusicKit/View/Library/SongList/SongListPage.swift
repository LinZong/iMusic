import SwiftUI

/// Shared song-page layout; feature views retain their models, list actions, and presentations.
struct SongListPage<Header: View, Content: View>: View {
    /// Current localized page title supplied by the owning feature.
    let title: String
    /// Query binding retained by the owning feature model.
    @Binding var search: String
    /// Localized description of the records searched on this page.
    let searchPrompt: String
    /// Optional fixed feature controls between search and the song list.
    @ViewBuilder var header: () -> Header
    /// Feature-composed song list, including its summary, rows, and actions.
    @ViewBuilder var content: () -> Content

    /// Composes fixed page controls without owning feature state or interpreting routes.
    init(
        title: String,
        search: Binding<String>,
        searchPrompt: String,
        @ViewBuilder header: @escaping () -> Header = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        _search = search
        self.searchPrompt = searchPrompt
        self.header = header
        self.content = content
    }

    /// Fixes touch headings and search above content while preserving desktop toolbar search.
    var body: some View {
        Group {
            #if os(iOS)
            VStack(spacing: 0) {
                Text(title)
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("library.songPageTitle")
                LibrarySearchInput(text: $search, prompt: searchPrompt)
                header()
                content()
            }
            // Keep native navigation controls while the fixed content owns the large heading.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("").accessibilityHidden(true)
                }
            }
            #else
            VStack(spacing: 0) {
                header()
                content()
            }
            .contentSearch(text: $search, prompt: searchPrompt)
            #endif
        }
        .navigationTitle(title)
    }
}
