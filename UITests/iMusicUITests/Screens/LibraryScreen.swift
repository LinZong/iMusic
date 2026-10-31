import XCTest

#if os(iOS)
import UIKit
#endif

/// Adapts navigation, tables, touch lists, menus, and file pickers to each native platform.
@MainActor struct LibraryScreen {
    /// Isolated host app controlled by this screen object.
    let app: XCUIApplication

    /// Chooses a compact tab or a stable sidebar route without matching content titles.
    func navigate(_ title: String) {
        #if os(iOS)
        let tab = app.tabBars.buttons[title]
        if tab.exists {
            tab.interact()
            return
        }
        #endif
        let routes = [
            "Home": "home", "All Songs": "songs", "Artists": "artists", "Albums": "albums",
            "Genres": "genres", "Favorites": "favorites", "Playlists": "playlists",
            "Settings": "settings", "Trash": "trash",
        ]
        let destination = app.element("navigation.\(routes[title] ?? title)")
        #if os(iOS)
        if !destination.exists, ["Artists", "Albums", "Genres", "Favorites"].contains(title) {
            navigate("All Songs")
            app.buttons[title].firstMatch.interact()
            return
        }
        #endif
        if !destination.isHittable {
            let sidebar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar'"))
                .firstMatch
            if sidebar.exists { sidebar.interact() }
        }
        XCTAssertTrue(destination.waitForExistence(timeout: 5), app.debugDescription)
        destination.interact()
    }

    /// Activates the visible shortcut center, exercising pointer hit testing on macOS.
    func openAllSongsShortcut(_ identifier: String) {
        let shortcut = app.element("allSongs." + identifier)
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5), app.debugDescription)
        #if os(iOS)
        for _ in 0..<3 where !shortcut.isHittable {
            app.element("allSongs.shortcuts").swipeLeft()
        }
        #endif
        XCTAssertTrue(shortcut.isHittable, app.debugDescription)
        #if os(macOS)
        shortcut.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        #else
        shortcut.interact()
        #endif
    }

    /// Returns from a pushed collection without changing the sidebar or selected tab.
    func backToAllSongs() {
        #if os(macOS)
        let back = app.buttons["chevron.backward"]
        #else
        let back = app.navigationBars.buttons.element(boundBy: 0)
        #endif
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        back.interact()
        XCTAssertTrue(app.element("allSongs.artists").waitForExistence(timeout: 5))
    }

    #if os(macOS)
    /// Resizes through the native window border instead of changing application layout state.
    func resizeWindow(width: CGFloat, height: CGFloat) {
        let window = app.windows.firstMatch
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -2, dy: -2))
        let target = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: width - 2, dy: height - 2))
        corner.click(forDuration: 0.1, thenDragTo: target)
        XCTAssertEqual(window.frame.width, width, accuracy: 6)
        XCTAssertEqual(window.frame.height, height, accuracy: 6)
    }
    #endif

    /// Native menu command for toggling the selected song's favorite state.
    var favoriteAction: XCUIElement {
        #if os(macOS)
        app.windows.menuItems
            .matching(
                NSPredicate(format: "title == 'Favorites' OR title == 'Remove from Favorites'")
            )
            .firstMatch
        #else
        app.element("trackActions.favorite")
        #endif
    }

    /// Native menu command for soft-deleting selected generated songs.
    var trashAction: XCUIElement {
        #if os(macOS)
        app.windows.menuItems["Move to Trash"]
        #else
        app.element("trackActions.trash")
        #endif
    }

    /// Checks the current favorite command without treating AppKit menu titles as labels.
    func assertFavoriteAction(isFavorite: Bool) {
        let title = isFavorite ? "Remove from Favorites" : "Favorites"
        #if os(macOS)
        XCTAssertTrue(app.windows.menuItems[title].exists, app.debugDescription)
        #else
        XCTAssertEqual(favoriteAction.label, title)
        #endif
    }

    /// Confirmation button in the native deletion sheet or mobile alert.
    var deletionConfirmation: XCUIElement {
        #if os(macOS)
        app.windows.sheets.buttons["Delete Permanently"]
        #else
        app.alerts.buttons["Delete Permanently"]
        #endif
    }

    /// Opens Trash directly on a Mac or through Settings on a compact phone.
    func openTrash() {
        #if os(macOS)
        navigate("Trash")
        #else
        if app.element("navigation.trash").isHittable {
            navigate("Trash")
            return
        }
        navigate("Settings")
        if app.navigationBars["Trash"].exists { return }
        let link = app.element("settings.trash")
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable, app.debugDescription)
        link.interact()
        #endif
    }

    /// Selects a native Trash segment without interacting with the app's main navigation tabs.
    func selectTrashTab(_ title: String) {
        let tabs = app.element("trash.tabs")
        XCTAssertTrue(tabs.waitForExistence(timeout: 5))
        #if os(macOS)
        tabs.radioButtons[title].interact()
        #else
        let segment = tabs.buttons[title]
        segment.interact()
        // An empty native search presentation can consume the first tap to dismiss itself.
        if !segment.isSelected { segment.interact() }
        XCTAssertTrue(segment.isSelected, app.debugDescription)
        #endif
    }

    /// Locates a song in the desktop table or the mobile playback row.
    func track(_ title: String) -> XCUIElement {
        #if os(macOS)
        app.element("track.title.\(title).wav")
        #else
        app.buttons["track.play.\(title).wav"]
        #endif
    }

    /// Starts the selected song using native table double-click or row tap.
    func play(_ title: String) {
        let song = track(title)
        XCTAssertTrue(song.waitForExistence(timeout: 5), app.debugDescription)
        #if os(macOS)
        // AppKit OutlineRow has no hittable accessibility action. Click its visible row center.
        desktopRow(title).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .doubleClick()
        #else
        song.interact()
        #endif
    }

    /// Opens the same song actions through a context menu or the touch row's More button.
    func showTrackActions(_ title: String) {
        #if os(macOS)
        let song = track(title)
        XCTAssertTrue(song.waitForExistence(timeout: 5))
        song.rightClick()
        #else
        app.element("track.more.\(title).wav").interact()
        #endif
    }

    #if os(macOS)
    /// Targets the native row rather than its selectable text or draggable title content.
    private func desktopRow(_ title: String) -> XCUIElement {
        app.outlines.descendants(matching: .outlineRow)
            .containing(.staticText, identifier: "track.title.\(title).wav").firstMatch
    }
    #endif

    /// Clears only the active page's search, preserving other page state.
    func clearSearch(_ search: XCUIElement) {
        #if os(macOS)
        search.click()
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        #else
        let clear = search.buttons["Clear text"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), app.debugDescription)
        clear.interact()
        if search.identifier == "library.contentSearch" {
            search.interact()
            search.typeText("\n")
            return
        }
        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.interact()
        } else {
            // iOS 26 replaces the navigation search Cancel command with a Close button.
            let close = app.navigationBars.buttons["Close"]
            if close.exists { close.interact() }
        }
        #endif
    }

    #if os(iOS)
    /// Only actual song rows may scroll beneath the fixed content search and summary.
    func assertSongHeaderStaysFixedWhileScrolling(prompt: String = "Search Songs") {
        let list = app.element("library.songList")
        let search = app.searchFields[prompt]
        let summary = app.element("library.songSummary")
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let navigation = app.navigationBars.element(boundBy: app.navigationBars.count - 1)
        let summaryGap = summary.frame.minY - search.frame.maxY
        XCTAssertGreaterThanOrEqual(list.cells.firstMatch.frame.minY, summary.frame.maxY)
        list.swipeUp()
        list.swipeUp()
        XCTAssertTrue(summary.isHittable)
        XCTAssertTrue(search.isHittable)
        // iPad accessibility may exclude the expanded large-title region from the bar frame.
        XCTAssertGreaterThanOrEqual(search.frame.minY, navigation.frame.maxY)
        XCTAssertEqual(summary.frame.minY - search.frame.maxY, summaryGap, accuracy: 1)
    }

    /// Search edits and keyboard dismissal must preserve visible, nonoverlapping page headers.
    func assertContentSearchKeepsTitle(_ title: String, prompt: String = "Search Songs") {
        let fields = app.searchFields.matching(NSPredicate(format: "label == %@", prompt))
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 5))
        guard let search = fields.allElementsBoundByIndex.last(where: { $0.isHittable }) else {
            XCTFail("No visible content search field: " + prompt)
            return
        }
        let heading = app.navigationBars.staticTexts[title].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(heading.isHittable, app.debugDescription)
        assertTitleIsPainted(heading)
        let searchY = search.frame.minY
        for query in ["", "Missing song"] {
            search.interact()
            search.typeText(query + "\n")
            XCTAssertTrue(heading.isHittable, app.debugDescription)
            assertTitleIsPainted(heading)
            XCTAssertEqual(search.frame.minY, searchY, accuracy: 1)
            XCTAssertLessThanOrEqual(heading.frame.maxY, search.frame.minY)
            if !query.isEmpty {
                clearSearch(search)
                search.interact()
                search.typeText("\n")
            }
        }
        XCTAssertTrue(heading.isHittable, app.debugDescription)
        assertTitleIsPainted(heading)
    }
    /// A hittable label can still be painted over by a fixed header's safe-area background.
    private func assertTitleIsPainted(_ title: XCUIElement) {
        let screenshot = app.screenshot().image
        let frame = title.frame.offsetBy(dx: -app.frame.minX, dy: -app.frame.minY)
        let sample = CGRect(
            x: frame.minX * screenshot.scale,
            y: frame.minY * screenshot.scale,
            width: frame.width * screenshot.scale,
            height: frame.height * screenshot.scale
        )
        guard let image = screenshot.cgImage?.cropping(to: sample) else {
            XCTFail("The navigation title must lie inside the rendered window.")
            return
        }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let contrast = pixels.withUnsafeMutableBytes { bytes -> Int in
            guard
                let context = CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return 0 }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var darkest = 255
            var lightest = 0
            for index in stride(from: 0, to: bytes.count, by: 4) {
                let brightness =
                    (Int(bytes[index]) + Int(bytes[index + 1])
                        + Int(bytes[index + 2])) / 3
                darkest = min(darkest, brightness)
                lightest = max(lightest, brightness)
            }
            return lightest - darkest
        }
        XCTAssertGreaterThan(contrast, 100, "The navigation title must be visibly painted.")
    }
    #endif

    /// Restores a generated song through desktop context actions or an iOS swipe action.
    func restoreTrashedTrack(_ title: String) {
        #if os(macOS)
        showTrackActions(title)
        #else
        let row = app.cells.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        #endif
        #if os(macOS)
        app.windows.menuItems["Restore"].interact()
        #else
        app.buttons["Restore"].interact()
        #endif
    }

    /// Requests permanent deletion of a generated fixture; the test confirms separately.
    func deleteTrashedTrack(_ title: String) {
        #if os(macOS)
        showTrackActions(title)
        app.windows.menuItems["Delete Permanently"].interact()
        #else
        let row = app.cells.containing(.staticText, identifier: title).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Delete Permanently"].interact()
        #endif
    }

    /// Waits for the native picker, cancels it, and verifies the library toolbar returns.
    func cancelPicker() {
        #if os(macOS)
        // App-wide queries also include a non-clickable Touch Bar Cancel button.
        let cancel = app.windows.buttons["Cancel"].firstMatch
        #else
        let cancel = app.buttons["Cancel"].firstMatch
        #endif
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
        cancel.interact()
        XCTAssertTrue(app.element("library.add").waitForExistence(timeout: 5))
    }
}
