import SwiftUI

#if os(macOS)
import AppKit

/// Native desktop search input whose lifetime is independent of navigation search controllers.
struct TrashSearchField: NSViewRepresentable {
    /// Query owned by the visible Trash category.
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

    /// Forwards only actual native input changes to the category model.
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        /// Current category binding supplied by the representable.
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
struct TrashSearchField: UIViewRepresentable {
    /// Query owned by the visible Trash category.
    @Binding var text: String
    /// Localized description of the records searched by this field.
    let prompt: String

    /// Creates an edit delegate without coupling query retention to view visibility.
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    /// Creates a system search text field supporting native clear, keyboard, and accessibility UI.
    func makeUIView(context: Context) -> UISearchTextField {
        let field = UISearchTextField()
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

    /// Reflects the category's saved query without firing an editing event.
    func updateUIView(_ field: UISearchTextField, context: Context) {
        context.coordinator.text = $text
        if field.text != text { field.text = text }
        field.placeholder = prompt
        field.accessibilityLabel = prompt
    }

    /// Publishes native edits and ends keyboard editing when the user submits a search.
    final class Coordinator: NSObject, UITextFieldDelegate {
        /// Current category binding supplied by the representable.
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

extension View {
    /// Uses a native toolbar search field for Trash on macOS and leaves touch layout to the page.
    @ViewBuilder func trashToolbarSearch(text: Binding<String>?, prompt: String) -> some View {
        #if os(macOS)
        toolbar {
            if let text {
                ToolbarItem {
                    TrashSearchField(text: text, prompt: prompt)
                        .frame(minWidth: 200, idealWidth: 340, maxWidth: 480)
                }
            }
        }
        #else
        self
        #endif
    }
}
