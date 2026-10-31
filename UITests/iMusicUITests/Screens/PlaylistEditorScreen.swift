import XCTest

/// Reuses the production editor and validates its enabled-state transitions on each platform.
@MainActor struct PlaylistEditorScreen {
    /// Isolated host app containing the editor sheet.
    let app: XCUIApplication
    /// Editable playlist name field shared by creation and rename flows.
    var name: XCUIElement { app.textFields["playlist.name"] }
    /// Create or Save action supplied by the editor mode.
    var commit: XCUIElement { app.buttons["playlist.commit"] }

    /// Accepts UIKit's placeholder-as-value representation while requiring an invalid blank draft.
    func assertBlankDraft() {
        let value = name.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == name.placeholderValue, "Unexpected draft: \(value)")
        XCTAssertFalse(commit.isEnabled)
    }

    /// Opens a fresh draft from the native library toolbar.
    func open() {
        app.element("library.add").interact()
        app.element("library.newPlaylist").interact()
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
    }

    /// Creates a named playlist and waits for its editor to disappear.
    func create(_ title: String) {
        open()
        name.interact()
        name.typeText(title)
        XCTAssertTrue(commit.isEnabled)
        commit.interact()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
    }
}
