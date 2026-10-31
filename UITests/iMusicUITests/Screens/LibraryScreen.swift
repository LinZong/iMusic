import XCTest

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
        app.windows.buttons["Delete Permanently"]
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
        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.interact()
        } else {
            let count = (search.value as? String ?? "").count
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        }
        #endif
    }

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
