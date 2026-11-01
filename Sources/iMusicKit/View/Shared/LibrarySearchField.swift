import SwiftUI

#if os(macOS)
import AppKit

/// Native desktop search input whose lifetime is independent of navigation search controllers.
struct LibrarySearchField: NSViewRepresentable {
    /// Query owned by the containing page.
    @Binding var text: String
    /// Localized description of the records searched by this field.
    let prompt: String

    /// Creates a delegate for user edits without treating view teardown as an empty query.
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    /// Creates a standard system search field suitable for the native window toolbar.
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }

    /// Reflects saved query and placeholder changes without generating a user-edit callback.
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
        field.setAccessibilityLabel(prompt)
    }

    /// Forwards only actual native input changes to the page model.
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        /// Current page binding supplied by the representable.
        var text: Binding<String>

        /// Retains the query binding used by native editing callbacks.
        init(text: Binding<String>) { self.text = text }

        /// Publishes typed text and the search field's native clear action.
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
#else
import UIKit

/// Native touch search input without navigation-controller presentation or dismissal side effects.
struct LibrarySearchField: UIViewRepresentable {
    /// Query owned by the containing page.
    @Binding var text: String
    /// Localized description of the records searched by this field.
    let prompt: String

    /// Creates an edit delegate without coupling query retention to view visibility.
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    /// Creates a system search text field supporting native clear, keyboard, and accessibility UI.
    func makeUIView(context: Context) -> UISearchTextField {
        // The system supplies Liquid Glass on iOS 26; an extra material would stack two surfaces.
        let field = UISearchTextField()
        field.accessibilityIdentifier = "library.contentSearch"
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .search
        field.clearButtonMode = .always
        field.accessibilityTraits.insert(.searchField)
        return field
    }

    /// Reflects the page's saved query without firing an editing event.
    func updateUIView(_ field: UISearchTextField, context: Context) {
        context.coordinator.text = $text
        if field.text != text { field.text = text }
        field.placeholder = prompt
        field.accessibilityLabel = prompt
    }

    /// Publishes native edits and ends keyboard editing when the user submits a search.
    final class Coordinator: NSObject, UITextFieldDelegate {
        /// Current page binding supplied by the representable.
        var text: Binding<String>

        /// Retains the query binding used by native editing callbacks.
        init(text: Binding<String>) { self.text = text }

        /// Publishes actual typed or pasted text.
        @objc func editingChanged(_ field: UITextField) { text.wrappedValue = field.text ?? "" }

        /// Publishes the native clear-button action even when the keyboard has no focus.
        func textFieldShouldClear(_ textField: UITextField) -> Bool {
            text.wrappedValue = ""
            return true
        }

        /// Dismisses the keyboard while keeping both the query and visible search results.
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
#endif

#if os(iOS)
/// Fixed content search layout shared by song pages, pickers, and Trash categories.
struct LibrarySearchInput: View {
    /// Query retained by the containing feature model.
    @Binding var text: String
    /// Localized description of the searchable content.
    let prompt: String
    /// Native input height follows the user's preferred body text size.
    @ScaledMetric(relativeTo: .body) private var fieldHeight: CGFloat = 36

    /// Keeps the native field outside scrolling content and navigation search presentation.
    var body: some View {
        LibrarySearchField(text: $text, prompt: prompt)
            .frame(height: fieldHeight)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            // Native glass decoration extends beyond the text field's layout bounds.
            .padding(.bottom, 16)
            .zIndex(1)
    }
}
#endif
