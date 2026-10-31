import SwiftUI

extension View {
    /// Applies native search presentation to a child page; the caller owns both its query binding
    /// and contextual prompt.
    @ViewBuilder func librarySearch(
        text: Binding<String>,
        prompt: String,
        enabled: Bool = true
    ) -> some View {
        if enabled {
            #if os(iOS)
            searchable(
                text: text,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(prompt)
            )
            #else
            searchable(text: text, prompt: Text(prompt))
            #endif
        } else {
            self
        }
    }
}

extension View {
    /// Fixes song-page search above content on touch platforms; retains desktop toolbar search.
    @ViewBuilder func contentSearch(text: Binding<String>, prompt: String) -> some View {
        #if os(iOS)
        safeAreaInset(edge: .top, spacing: 0) {
            // A safe-area-filling background can paint over the navigation bar's large title.
            LibrarySearchInput(text: text, prompt: prompt)
                .background(.background, ignoresSafeAreaEdges: [])
        }
        #else
        librarySearch(text: text, prompt: prompt)
        #endif
    }
}
