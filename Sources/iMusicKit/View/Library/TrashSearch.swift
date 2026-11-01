import SwiftUI

extension View {
    /// Keeps desktop Trash search in its toolbar and shares native content search on touch systems.
    @ViewBuilder func trashSearch(text: Binding<String>?, prompt: String) -> some View {
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
        if let text {
            contentSearch(text: text, prompt: prompt)
        } else {
            self
        }
        #endif
    }
}
