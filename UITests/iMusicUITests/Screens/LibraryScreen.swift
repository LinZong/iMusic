import XCTest

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
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
            // Glass tabs can expose an invalid native activation point despite a visible frame.
            tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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
            openAllSongsShortcut(routes[title]!)
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
        #if os(macOS)
        app.activate()
        #endif
        let shortcut = app.element("allSongs." + identifier)
        #if os(iOS)
        let shortcuts = app.scrollViews["allSongs.shortcuts"].firstMatch
        for _ in 0..<10 {
            if shortcuts.isHittable { break }
            app.element("library.songList").swipeDown()
        }
        // Fully offscreen glass buttons can have no accessibility activation point.
        // Reveal their center before asking the system to resolve native hit testing.
        for _ in 0..<3
        where !shortcuts.frame.contains(CGPoint(x: shortcut.frame.midX, y: shortcut.frame.midY)) {
            shortcuts.swipeLeft()
        }
        #endif
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5), app.debugDescription)
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
        for _ in 0..<6 {
            if link.isHittable { break }
            app.swipeUp()
        }
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
    /// Desktop shortcut padding inherits the same window surface as the adjacent summary.
    func assertDesktopShortcutsInheritWindowBackground() {
        app.activate()
        let shortcuts = app.element("allSongs.shortcuts")
        let summary = app.element("library.songSummaryBar")
        XCTAssertTrue(shortcuts.waitForExistence(timeout: 5))
        // macOS element screenshots can include the entire display; use display coordinates.
        let screen = CGDisplayBounds(CGMainDisplayID())
        let screenshot = XCUIScreen.main.screenshot().image
        guard let data = screenshot.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: data)
        else {
            XCTFail("The native window must supply readable background pixels.")
            return
        }
        let scale = CGFloat(bitmap.pixelsWide) / screen.width
        let x = shortcuts.frame.midX - screen.minX
        let ys = [shortcuts.frame.minY - 6, summary.frame.minY + 4]
        let colors = ys.compactMap { y in
            bitmap.colorAt(
                x: Int(x * scale),
                y: Int((y - screen.minY) * scale)
            )?
            .usingColorSpace(.deviceRGB)
        }
        XCTAssertEqual(colors.count, 2)
        guard colors.count == 2 else { return }
        for (header, surrounding) in zip(
            [colors[0].redComponent, colors[0].greenComponent, colors[0].blueComponent],
            [colors[1].redComponent, colors[1].greenComponent, colors[1].blueComponent]
        ) {
            XCTAssertEqual(
                header,
                surrounding,
                accuracy: 0.02,
                "Desktop shortcuts must not paint a separate white or black strip."
            )
        }
    }

    /// Targets the native row rather than its selectable text or draggable title content.
    private func desktopRow(_ title: String) -> XCUIElement {
        app.outlines.descendants(matching: .outlineRow)
            .containing(.staticText, identifier: "track.title.\(title).wav").firstMatch
    }
    #endif

    /// Requires the native collection drawer without a compensating pull-to-reveal gesture.
    func collectionSearch(prompt: String = "Search Songs") -> XCUIElement {
        let search = app.searchFields[prompt].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable)
        return search
    }

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
        dismissNavigationSearch(search)
        #endif
    }

    #if os(iOS)
    /// Ends native navigation search across compact Cancel and regular-width focus behavior.
    private func dismissNavigationSearch(_ search: XCUIElement) {
        let cancel = app.buttons["Cancel"]
        if cancel.exists {
            cancel.interact()
            return
        }
        let close = app.navigationBars.buttons["Close"]
        if close.exists {
            close.interact()
            return
        }
        // Regular-width iOS 26 keeps search inline without an explicit dismissal command.
        let songs = app.element("library.songList")
        (songs.exists ? songs : app.scrollViews.firstMatch).swipeDown()
    }
    #endif

    #if os(iOS)
    /// Samples the scrolling header's semantic background in both saved appearances.
    func assertLegacyShortcutBackgroundIsOpaque(dark: Bool) {
        let shortcuts = app.scrollViews["allSongs.shortcuts"].firstMatch
        let frame = shortcuts.frame.offsetBy(dx: -app.frame.minX, dy: -app.frame.minY)
        let screenshot = app.screenshot().image
        guard let image = screenshot.cgImage else {
            XCTFail("The shortcut background must be present in the rendered window.")
            return
        }
        for x in stride(from: frame.minX + 16, through: frame.maxX - 24, by: 12) {
            let color = meanRenderedColor(
                image,
                rect: CGRect(x: x, y: frame.minY - 8, width: 8, height: 4),
                scale: screenshot.scale
            )
            for channel in color {
                if dark {
                    XCTAssertLessThan(channel, 35, "The header must use a dark system background.")
                } else {
                    XCTAssertGreaterThan(
                        channel,
                        240,
                        "The header must use a light system background."
                    )
                }
            }
        }
    }

    /// Glass shadows must fade across the shortcut scroller's lower drawing boundary.
    func assertShortcutDecorationIsContinuous() {
        let shortcuts = app.scrollViews["allSongs.shortcuts"].firstMatch
        let screenshot = app.screenshot().image
        guard let image = screenshot.cgImage else {
            XCTFail("Shortcut decoration must be present in the rendered window.")
            return
        }
        let edge = shortcuts.frame.maxY - app.frame.minY
        for identifier in ["artists", "albums"] {
            let x = app.element("allSongs." + identifier).frame.midX - app.frame.minX
            let above = meanRenderedColor(
                image,
                rect: CGRect(x: x - 1, y: edge - 1, width: 2, height: 1),
                scale: screenshot.scale
            )
            let below = meanRenderedColor(
                image,
                rect: CGRect(x: x - 1, y: edge + 1, width: 2, height: 1),
                scale: screenshot.scale
            )
            for (upper, lower) in zip(above, below) {
                XCTAssertLessThanOrEqual(
                    abs(upper - lower),
                    3,
                    "Shortcut shadows must not end at a rectangular scroll-view clip."
                )
            }
        }
    }

    /// Native shadow pixels must fade across both lower corners without a rectangular paint edge.
    func assertSearchDecorationIsContinuous() {
        let search = app.searchFields.matching(NSPredicate(format: "label == 'Search Songs'"))
            .allElementsBoundByIndex.last(where: { $0.isHittable })
        guard let search else {
            XCTFail("The active page must expose its own search field.")
            return
        }
        let screenshot = app.screenshot().image
        guard let image = screenshot.cgImage else {
            XCTFail("Search decoration must be present in the rendered window.")
            return
        }
        let frame = search.frame.offsetBy(dx: -app.frame.minX, dy: -app.frame.minY)
        for x in [frame.minX + 1, frame.maxX - 3] {
            let above = meanRenderedColor(
                image,
                rect: CGRect(x: x, y: frame.maxY - 2, width: 2, height: 1),
                scale: screenshot.scale
            )
            let below = meanRenderedColor(
                image,
                rect: CGRect(x: x, y: frame.maxY + 1, width: 2, height: 1),
                scale: screenshot.scale
            )
            for (upper, lower) in zip(above, below) {
                XCTAssertLessThanOrEqual(
                    abs(upper - lower),
                    5,
                    "Search decoration must fade smoothly across its lower corners."
                )
            }
        }
    }

    /// A paused half-track progress line remains painted inside the floating player's glass.
    func assertMiniPlayerProgressIsPainted() {
        let bar = app.element("miniPlayer.bar")
        let frame = bar.frame.offsetBy(dx: -app.frame.minX, dy: -app.frame.minY)
        let screenshot = app.screenshot().image
        guard let image = screenshot.cgImage else {
            XCTFail("The mini player must be present in the rendered window.")
            return
        }
        let x = frame.minX + frame.width * 0.25
        let hasProgress = (1...12)
            .contains { offset in
                let color = meanRenderedColor(
                    image,
                    rect: CGRect(x: x, y: frame.maxY - CGFloat(offset), width: 2, height: 1),
                    scale: screenshot.scale
                )
                return color.count == 3 && color[2] - color[0] > 50 && color[2] - color[1] > 40
            }
        XCTAssertTrue(
            hasProgress,
            "Progress must not be clipped outside the native glass accessory."
        )
    }

    /// Samples a small rendered patch in window coordinates without relying on a fixed theme.
    private func meanRenderedColor(_ image: CGImage, rect: CGRect, scale: CGFloat) -> [Double] {
        let sample = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard let patch = image.cropping(to: sample) else {
            XCTFail("Search decoration samples must lie inside the rendered window.")
            return []
        }
        var pixels = [UInt8](repeating: 0, count: patch.width * patch.height * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard
                let context = CGContext(
                    data: bytes.baseAddress,
                    width: patch.width,
                    height: patch.height,
                    bitsPerComponent: 8,
                    bytesPerRow: patch.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                XCTFail("Search decoration samples must be readable.")
                return []
            }
            context.draw(patch, in: CGRect(x: 0, y: 0, width: patch.width, height: patch.height))
            let count = Double(patch.width * patch.height)
            return (0..<3)
                .map { channel in
                    stride(from: channel, to: bytes.count, by: 4)
                        .reduce(0.0) { $0 + Double(bytes[$1]) } / count
                }
        }
    }

    /// Checks both native controls on first presentation without scrolling or activating search.
    func assertInitialCollectionNavigation(_ title: String) {
        let heading = app.navigationBars.staticTexts[title].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5), app.debugDescription)
        if app.frame.width < 600 {
            XCTAssertGreaterThan(
                heading.frame.height,
                30,
                "Compact pages start with a large title."
            )
        } else {
            XCTAssertLessThan(
                heading.frame.height,
                30,
                "Regular width follows the native inline title."
            )
        }
        XCTAssertTrue(heading.isHittable)
        assertTitleIsPainted(heading)
        let search = collectionSearch()
        if app.frame.width < 600 {
            XCTAssertGreaterThanOrEqual(search.frame.minY, heading.frame.maxY)
        }
    }

    /// Measures native search activation and dismissal without assuming a compact-width toolbar.
    func navigationSearchFrames(prompt: String) -> (idle: CGRect, focused: CGRect) {
        let search = app.searchFields[prompt].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable)
        let idle = search.frame
        search.interact()
        let focused = search.frame
        dismissNavigationSearch(search)
        return (idle, focused)
    }

    /// Requires both restored native title geometry and painted pixels after search transitions.
    func assertNavigationTitleRestored(_ title: String, frame: CGRect) {
        let heading = app.navigationBars.staticTexts[title].firstMatch
        let restored = NSPredicate { _, _ in
            heading.exists && heading.isHittable
                && abs(heading.frame.minY - frame.minY) < 2
                && abs(heading.frame.height - frame.height) < 2
        }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: restored, object: heading)],
                timeout: 4
            ),
            .completed
        )
        assertTitleIsPainted(heading)
    }

    /// System collection titles collapse with their List and expand again at the top boundary.
    func assertSystemSongCollectionNavigation(_ title: String, canCollapse: Bool = true) {
        let list = app.element("library.songList")
        let heading = app.navigationBars.staticTexts[title].firstMatch
        let customHeading = app.staticTexts.matching(identifier: "library.songPageTitle")
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(heading.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(customHeading.firstMatch.exists)
        if app.frame.width < 600 {
            XCTAssertGreaterThan(heading.frame.height, 30)
        }
        assertTitleIsPainted(heading)
        let expandedFrame = heading.frame

        if canCollapse {
            list.swipeUp()
            if expandedFrame.height <= 30 {
                XCTAssertEqual(heading.frame.height, expandedFrame.height, accuracy: 1)
                list.swipeDown()
                list.swipeDown()
                assertTitleIsPainted(heading)
                return
            }
            let collapsed = NSPredicate { _, _ in
                heading.exists && heading.frame.height < expandedFrame.height - 4
            }
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [XCTNSPredicateExpectation(predicate: collapsed, object: heading)],
                    timeout: 5
                ),
                .completed,
                "The system title must collapse into the navigation bar."
            )
            let collapsedHeight = heading.frame.height
            for _ in 0..<10
            where heading.frame.height < expandedFrame.height - 1
                || abs(heading.frame.minY - expandedFrame.minY) > 1
            {
                list.swipeDown()
            }
            XCTAssertGreaterThan(
                heading.frame.height,
                collapsedHeight + 4,
                "Returning to the top must restore the large system title."
            )
            XCTAssertEqual(heading.frame.minY, expandedFrame.minY, accuracy: 1)
        }

        let topFrame = heading.frame
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(heading.frame.minY, topFrame.minY, accuracy: 1)
        XCTAssertEqual(heading.frame.height, topFrame.height, accuracy: 1)
        assertTitleIsPainted(heading)
    }

    /// Short held gestures exercise repeated movement through the large/inline threshold.
    func assertSlowCollectionTitleTransitions(_ title: String) {
        let list = app.element("library.songList")
        let heading = app.navigationBars.staticTexts[title].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        let expanded = heading.frame
        if app.frame.width < 600 { XCTAssertGreaterThan(expanded.height, 30) }
        for _ in 0..<3 {
            // Start in the non-draggable gutter; an extremely slow row press initiates song drag.
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.55))
            start.press(
                forDuration: 0.05,
                thenDragTo: start.withOffset(CGVector(dx: 0, dy: -145)),
                withVelocity: XCUIGestureVelocity(rawValue: 40),
                thenHoldForDuration: 0.3
            )
            if expanded.height <= 30 {
                XCTAssertEqual(heading.frame.height, expanded.height, accuracy: 1)
                list.swipeDown()
                assertTitleIsPainted(heading)
                continue
            }
            XCTAssertLessThan(heading.frame.height, expanded.height - 4)
            for _ in 0..<10
            where heading.frame.height < expanded.height - 1
                || abs(heading.frame.minY - expanded.minY) > 1
            {
                start.press(
                    forDuration: 0.05,
                    // Complete the native title snap threshold within one continuous slow drag.
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: 145)),
                    withVelocity: XCUIGestureVelocity(rawValue: 40),
                    thenHoldForDuration: 0.3
                )
            }
            for _ in 0..<3 {
                XCTAssertEqual(heading.frame.height, expanded.height, accuracy: 1)
                XCTAssertEqual(heading.frame.minY, expanded.minY, accuracy: 1)
            }
            assertTitleIsPainted(heading)
        }
    }

    /// Native collection search edits retain the system title and never install a fixed heading.
    func assertSystemCollectionSearchKeepsTitle(_ title: String, prompt: String = "Search Songs") {
        let customHeading = app.staticTexts.matching(identifier: "library.songPageTitle")
        XCTAssertFalse(customHeading.firstMatch.exists)
        let heading = app.navigationBars.staticTexts[title].firstMatch
        XCTAssertTrue(heading.isHittable, app.debugDescription)
        assertTitleIsPainted(heading)
        for query in ["", "Missing song"] {
            let search = collectionSearch(prompt: prompt)
            search.interact()
            if !query.isEmpty { search.typeText(query) }
            XCTAssertTrue(search.isHittable)
            if query.isEmpty {
                dismissNavigationSearch(search)
            } else {
                clearSearch(search)
            }
            XCTAssertTrue(heading.waitForExistence(timeout: 5), app.debugDescription)
            XCTAssertTrue(heading.isHittable, app.debugDescription)
            assertTitleIsPainted(heading)
            if #available(iOS 26.0, *), app.frame.width < 600 {
                XCTAssertTrue(search.isHittable)
                XCTAssertGreaterThanOrEqual(search.frame.minY, heading.frame.maxY)
            } else if app.frame.width < 600, search.exists, search.isHittable {
                XCTAssertGreaterThanOrEqual(search.frame.minY, heading.frame.maxY)
            }
        }
    }

    /// Fixed song-page titles and controls keep absolute frames through scrolling and rebound.
    func assertSongPageChromeStaysFixed(_ title: String) {
        let list = app.element("library.songList")
        let heading = app.staticTexts["library.songPageTitle"]
        let search = app.searchFields["Search Songs"]
        let summary = app.element("library.songSummary")
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let fixed = [heading, search, summary]
        let frames = fixed.map(\.frame)
        XCTAssertTrue(heading.isHittable)
        XCTAssertEqual(heading.label, title)
        XCTAssertGreaterThan(heading.frame.height, 35, "Keep the large song-page heading.")
        XCTAssertLessThanOrEqual(heading.frame.maxY, search.frame.minY)
        for direction in ["up", "down", "blank pull"] {
            switch direction {
            case "up": list.swipeUp()
            case "down": list.swipeDown()
            default:
                let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            for (element, frame) in zip(fixed, frames) {
                XCTAssertTrue(element.isHittable)
                XCTAssertEqual(element.frame.minY, frame.minY, accuracy: 1, direction)
                XCTAssertEqual(element.frame.height, frame.height, accuracy: 1, direction)
            }
            XCTAssertLessThanOrEqual(heading.frame.maxY, search.frame.minY)
            assertTitleIsPainted(heading)
        }
    }

    /// Only actual song rows may scroll beneath the fixed content search and summary.
    func assertSongHeaderStaysFixedWhileScrolling(prompt: String = "Search Songs") {
        let list = app.element("library.songList")
        let search = app.searchFields[prompt]
        let summary = app.element("library.songSummary")
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let navigation = app.navigationBars.element(boundBy: app.navigationBars.count - 1)
        let summaryGap = summary.frame.minY - search.frame.maxY
        if #available(iOS 26.0, *) {
            XCTAssertLessThan(list.cells.firstMatch.frame.minY, summary.frame.minY)
        } else {
            XCTAssertGreaterThanOrEqual(list.cells.firstMatch.frame.minY, summary.frame.maxY)
        }
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
        let pageHeading = app.staticTexts.matching(identifier: "library.songPageTitle")
            .matching(NSPredicate(format: "label == %@", title)).firstMatch
        let heading =
            pageHeading.exists
            ? pageHeading : app.navigationBars.staticTexts[title].firstMatch
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
        XCTAssertGreaterThan(contrast, 20, "The navigation title must be visibly painted.")
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
