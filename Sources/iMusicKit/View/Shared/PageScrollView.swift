import SwiftUI

/// Lets short page content fill the viewport while taller content remains scrollable.
struct PageScrollView<Content: View>: View {
    /// Page sections, including any flexible placeholder below the page header.
    private let content: Content

    /// Builds page content without imposing a fixed height on text or accessibility layouts.
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// Gives flexible placeholders the remaining viewport height instead of an unbounded height.
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content
                    .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
    }
}
