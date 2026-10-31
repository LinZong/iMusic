import XCTest

/// Full-player interactions shared by the iPhone, iPad, and native Mac regressions.
@MainActor struct PlayerScreen {
    /// Isolated host app containing production player views.
    let app: XCUIApplication
    /// Play/pause control whose accessible label reports current playback state.
    var toggle: XCUIElement { app.element("player.toggle") }
    /// Combined title and artist accessibility element.
    var metadata: XCUIElement { app.element("player.metadata") }

    /// Visible elapsed-time text, independent of native slider accessibility value types.
    var elapsedSeconds: Double {
        let text = app.element("player.elapsed")
        let nativeValue = text.value as? String ?? ""
        let value = nativeValue.isEmpty ? text.label : nativeValue
        let clock = value.split(separator: ":").compactMap { Double($0) }
        guard clock.count == 2 else {
            XCTFail("Unexpected elapsed-time text: \(value)")
            return .nan
        }
        return clock[0] * 60 + clock[1]
    }

    /// Expands the platform mini player without changing playback state.
    func open() {
        let expand = app.element("miniPlayer.expand")
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        expand.interact()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    }

    /// Waits for the selected song to be reflected in player metadata.
    func assertSong(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", title, title)
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: metadata)],
            timeout: 5
        )
        XCTAssertEqual(result, .completed, app.debugDescription, file: file, line: line)
    }
}
