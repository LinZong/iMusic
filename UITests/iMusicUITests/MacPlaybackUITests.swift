#if os(macOS)
import XCTest

/// Native desktop regressions for persistent gain and the expanded transport bar.
@MainActor final class MacPlaybackUITests: UITestCase {
    /// Gain and mute restoration must survive process launches without touching audio hardware.
    func testVolumeAndMutePersistAcrossLaunches() {
        launch()
        navigate("All Songs")
        library.play("UI Alpha")
        let volume = app.sliders["player.volume"]
        XCTAssertTrue(volume.waitForExistence(timeout: 5))
        volume.setFraction(0.35)
        let saved = volume.numericValue
        XCTAssertGreaterThan(saved, 0.15)
        XCTAssertLessThan(saved, 0.6)
        app.element("player.mute").interact()
        XCTAssertEqual(app.element("player.mute").label, "Unmute")
        app.terminate()
        launch(relaunch: true)
        XCTAssertEqual(app.element("player.mute").label, "Unmute")
        app.element("player.mute").interact()
        let restored = app.sliders["player.volume"].numericValue
        XCTAssertEqual(restored, saved, accuracy: 0.02)
        app.terminate()
        launch(relaunch: true)
        let persisted = app.sliders["player.volume"].numericValue
        XCTAssertEqual(persisted, saved, accuracy: 0.02)
        capture("Desktop persistent application volume")
    }

    /// The desktop bar must expose working previous, next, repeat, shuffle, and favorite controls.
    func testDesktopTransportAndFavoriteControls() {
        launch(scenario: "artwork")
        navigate("All Songs")
        library.play("UI Alpha")
        let repeatMode = app.element("miniPlayer.repeat")
        XCTAssertEqual(repeatMode.label, "Play in Order")
        repeatMode.interact()
        XCTAssertEqual(repeatMode.label, "Repeat All")
        repeatMode.interact()
        XCTAssertEqual(repeatMode.label, "Repeat One")
        let shuffle = app.element("miniPlayer.shuffle")
        shuffle.interact()
        XCTAssertEqual(shuffle.label, "Turn Shuffle Off")
        shuffle.interact()
        XCTAssertEqual(shuffle.label, "Turn Shuffle On")
        let favorite = app.element("miniPlayer.favorite")
        favorite.interact()
        XCTAssertEqual(favorite.label, "Remove from Favorites")
        favorite.interact()
        XCTAssertEqual(favorite.label, "Favorites")
        app.element("miniPlayer.next").interact()
        XCTAssertTrue(
            (app.element("miniPlayer.expand").value as? String ?? "").contains("UI Beta")
        )
        app.element("miniPlayer.previous").interact()
        app.element("miniPlayer.toggle").interact()
        XCTAssertEqual(app.element("miniPlayer.toggle").label, "Play")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        app.typeKey(.space, modifierFlags: [])
        XCTAssertEqual(app.element("miniPlayer.toggle").label, "Pause")
        app.typeKey(.space, modifierFlags: [])
        XCTAssertEqual(app.element("miniPlayer.toggle").label, "Play")
        player.open()
        player.assertSong("UI Alpha")
        app.typeKey(.space, modifierFlags: [])
        XCTAssertEqual(player.toggle.label, "Pause")
        app.typeKey(.space, modifierFlags: [])
        XCTAssertEqual(player.toggle.label, "Play")
        capture("Desktop transport synchronized with full player")
    }

    /// A standalone player window must share playback and handle its own Space shortcut.
    func testStandaloneMiniPlayerSharesPlayback() {
        launch()
        navigate("All Songs")
        library.play("UI Alpha")
        app.menuBars.menuBarItems["Window"].click()
        app.menuItems["Mini Player"].click()
        let mini = app.windows["Mini Player"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        let toggle = mini.element("miniWindow.toggle")
        XCTAssertEqual(toggle.label, "Pause")
        toggle.interact()
        XCTAssertEqual(app.element("miniPlayer.toggle").label, "Play")
        mini.typeKey(.space, modifierFlags: [])
        XCTAssertEqual(toggle.label, "Pause")
        XCTAssertEqual(app.element("miniPlayer.toggle").label, "Pause")
        capture("Standalone mini player shares the desktop session")
        mini.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(mini.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.element("miniPlayer.toggle").label, "Pause")
    }
}
#endif
