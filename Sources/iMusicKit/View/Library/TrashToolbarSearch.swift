import SwiftUI

extension View {
    /// Uses a native toolbar search field for Trash on macOS and leaves touch layout to the page.
    @ViewBuilder func trashToolbarSearch(text: Binding<String>?, prompt: String) -> some View {
        #if os(macOS)
        toolbar {
            if let text {
                ToolbarItem {
                    LibrarySearchField(text: text, prompt: prompt)
                        .frame(minWidth: 200, idealWidth: 340, maxWidth: 480)
                }
            }
        }
        #else
        self
        #endif
    }
}
