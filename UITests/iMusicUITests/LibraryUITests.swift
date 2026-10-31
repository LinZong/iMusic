import XCTest

/// Exercises the production SwiftUI flows inside a separately installed, silent test host.
@MainActor final class LibraryUITests: XCTestCase {
    /// Application instance whose bundle identifier comes from the generated test configuration.
    private var app: XCUIApplication!
    /// Unique library namespace retained only when a scenario intentionally relaunches the app.
    private var runID = UUID().uuidString

    /// Retains failure screenshots and accessibility trees before the next scenario launches.
    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            let application = XCUIApplication()
            let screenshot = XCTAttachment(screenshot: application.screenshot())
            screenshot.name = "Failure screen"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: application.debugDescription)
            hierarchy.name = "Failure accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        try super.tearDownWithError()
    }

    /// Starts the test host with isolated fixtures and a predictable UI language.
    private func launch(scenario: String = "library", relaunch: Bool = false) {
        continueAfterFailure = false
        if !relaunch { runID = UUID().uuidString }
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        print("UI_TEST_RUN_ID=\(runID)")
        app.launchEnvironment["IMUSIC_UI_TEST_RUN_ID"] = runID
        app.launchEnvironment["IMUSIC_UI_TEST_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(app.buttons["library.add"].firstMatch.waitForExistence(timeout: 30))
    }

    /// Uses compact tabs on phones or the native split-view sidebar on tablets.
    private func navigate(_ title: String) {
        let tab = app.tabBars.buttons[title]
        if tab.exists {
            tab.tap()
            return
        }
        var destination = app.buttons[title].firstMatch
        if !destination.isHittable {
            let sidebar = app.buttons
                .matching(
                    NSPredicate(format: "label CONTAINS[c] 'sidebar'")
                )
                .firstMatch
            if sidebar.exists { sidebar.tap() }
            destination = app.buttons[title].firstMatch
        }
        if !destination.exists {
            destination = app.cells.containing(.staticText, identifier: title).firstMatch
        }
        XCTAssertTrue(destination.waitForExistence(timeout: 5), app.debugDescription)
        destination.tap()
    }

    /// Scrolls a form only when its destination is outside the visible viewport.
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    /// Opens Trash while respecting the navigation stack retained by the Settings tab.
    private func openTrash() {
        navigate("Settings")
        if app.navigationBars["Trash"].exists { return }
        let link = app.buttons["settings.trash"]
        reveal(link)
        link.tap()
    }

    /// Attaches a named real screen capture to the xcresult bundle.
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Verifies empty-state presentation and search ownership on the four primary destinations.
    func testEmptyLibraryAndSearchScope() {
        launch(scenario: "empty")
        XCTAssertTrue(app.staticTexts["Start with your first song"].exists)
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        navigate("All Songs")
        XCTAssertTrue(app.searchFields["Search Songs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Music Here Yet"].exists)
        navigate("Playlists")
        XCTAssertTrue(app.searchFields["Search Playlists"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing Here Yet"].exists)
        navigate("Settings")
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        capture("Empty library and Settings")
    }

    /// Checks scoped song filtering, playlist creation, and persistence across process launches.
    func testSongSearchAndPlaylistPersistence() {
        launch()
        navigate("All Songs")
        let alpha = app.buttons["track.play.UI Alpha.wav"]
        let beta = app.buttons["track.play.UI Beta.wav"]
        XCTAssertTrue(alpha.waitForExistence(timeout: 5))
        XCTAssertTrue(beta.exists)
        let search = app.searchFields["Search Songs"]
        search.tap()
        search.typeText("Alpha")
        XCTAssertTrue(alpha.exists)
        XCTAssertFalse(beta.exists)
        let cancelSearch = app.buttons["Cancel"]
        if cancelSearch.exists {
            cancelSearch.tap()
        } else {
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
        }
        navigate("Playlists")
        app.buttons["library.add"].firstMatch.tap()
        app.buttons["library.newPlaylist"].tap()
        let name = app.textFields["playlist.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let create = app.buttons["playlist.commit"]
        XCTAssertFalse(create.isEnabled, "An empty playlist name must not be submitted.")
        name.tap()
        name.typeText("   ")
        XCTAssertFalse(create.isEnabled, "Whitespace must not enable playlist creation.")
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3))
        name.typeText("UI Regression Playlist")
        XCTAssertEqual(name.value as? String, "UI Regression Playlist")
        XCTAssertTrue(create.isEnabled)
        create.tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Regression Playlist'"))
                .firstMatch.waitForExistence(timeout: 5)
        )
        app.terminate()
        launch(relaunch: true)
        navigate("Playlists")
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'UI Regression Playlist'"))
                .firstMatch.waitForExistence(timeout: 5)
        )
        capture("Playlist persisted after relaunch")
    }

    /// Repeatedly opens song actions, seeks while paused, and changes tracks without audio output.
    func testPlayerMenusSeekingAndTrackChanges() {
        launch()
        navigate("All Songs")
        app.buttons["track.play.UI Alpha.wav"].tap()
        let expand = app.buttons["miniPlayer.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        expand.tap()
        let toggle = app.buttons["player.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.label, "Pause")
        toggle.tap()
        XCTAssertEqual(toggle.label, "Play")
        let slider = app.sliders["player.seek"]
        XCTAssertTrue(slider.isEnabled)
        slider.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertEqual(toggle.label, "Play", "Seeking while paused must not resume playback.")
        let value = slider.value as? String ?? ""
        let clock = value.split(separator: " ").first?.split(separator: ":") ?? []
        XCTAssertEqual(clock.count, 2, value)
        if clock.count == 2 {
            let seconds = (Double(clock[0]) ?? 0) * 60 + (Double(clock[1]) ?? 0)
            XCTAssertEqual(seconds, 60, accuracy: 5, value)
        }
        for _ in 0..<3 {
            app.buttons["player.songOptions"].tap()
            let favorite = app.buttons["trackActions.favorite"]
            XCTAssertTrue(favorite.waitForExistence(timeout: 3))
            XCTAssertEqual(favorite.label, "Favorites")
            favorite.tap()
            app.buttons["player.songOptions"].tap()
            XCTAssertEqual(app.buttons["trackActions.favorite"].label, "Remove from Favorites")
            app.buttons["trackActions.favorite"].tap()
        }
        XCTAssertEqual(toggle.label, "Play")
        app.buttons["player.next"].tap()
        let metadata = app.descendants(matching: .any)
            .matching(identifier: "player.metadata").firstMatch
        expectation(for: NSPredicate(format: "label CONTAINS 'UI Beta'"), evaluatedWith: metadata)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("Now Playing after menu and seek interactions")
    }

    /// Restores one trashed song, then permanently deletes only the generated test-library copy.
    func testTrashSwipeRestoreAndPermanentDelete() {
        launch()
        openTrash()
        var row = app.cells.containing(.staticText, identifier: "UI Trashed").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Restore"].tap()
        XCTAssertTrue(app.staticTexts["Trash Is Empty"].waitForExistence(timeout: 5))
        navigate("All Songs")
        let restored = app.buttons["track.play.UI Trashed.wav"]
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        app.buttons["track.more.UI Trashed.wav"].tap()
        app.buttons["trackActions.trash"].tap()
        openTrash()
        row = app.cells.containing(.staticText, identifier: "UI Trashed").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Delete Permanently"].tap()
        let confirm = app.alerts.buttons["Delete Permanently"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Trash Is Empty"].waitForExistence(timeout: 10))
        capture("Trash empty after deleting generated fixture")
    }

    /// Verifies the native folder picker can be opened and cancelled without library changes.
    func testLinkFolderPickerCanBeCancelled() {
        launch()
        app.buttons["library.add"].firstMatch.tap()
        app.buttons["library.linkFolder"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        capture("Native folder picker")
        cancel.tap()
        XCTAssertTrue(app.buttons["library.add"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
}
