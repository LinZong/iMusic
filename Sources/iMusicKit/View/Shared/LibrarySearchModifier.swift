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
