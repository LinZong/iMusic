import XCTest

/// Owns launch isolation, failure artifacts, and screen objects for each native UI scenario.
@MainActor class UITestCase: XCTestCase {
    /// Application instance whose bundle identifier comes from the generated test configuration.
    var app: XCUIApplication!
    /// Unique library namespace retained only when a scenario intentionally relaunches the app.
    var runID = UUID().uuidString

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
        app?.terminate()
        try super.tearDownWithError()
    }

    /// Starts the test host with isolated fixtures and a predictable UI language.
    func launch(scenario: String = "library", relaunch: Bool = false) {
        continueAfterFailure = false
        if !relaunch { runID = UUID().uuidString }
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        print("UI_TEST_RUN_ID=\(runID)")
        app.launchEnvironment["IMUSIC_UI_TEST_RUN_ID"] = runID
        app.launchEnvironment["IMUSIC_UI_TEST_SCENARIO"] = scenario
        app.launch()
        XCTAssertTrue(app.element("library.add").waitForExistence(timeout: 30))
    }

    /// Platform-specific library interactions shared by feature regression cases.
    var library: LibraryScreen { LibraryScreen(app: app) }
    /// Full-player controls and metadata shared by desktop and mobile tests.
    var player: PlayerScreen { PlayerScreen(app: app) }
    /// Native playlist editor interactions shared by all platforms.
    var editor: PlaylistEditorScreen { PlaylistEditorScreen(app: app) }

    /// Selects a compact tab or native sidebar destination.
    func navigate(_ title: String) { library.navigate(title) }
    /// Opens Trash through the platform's native navigation.
    func openTrash() { library.openTrash() }

    /// Attaches a named real screen capture to the xcresult bundle.
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
