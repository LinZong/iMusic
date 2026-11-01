#if os(iOS)
import UIKit
import XCTest

/// Exercises the production sheet with explicit app appearance and silent playback fixtures.
@MainActor final class PlayerAppearanceUITests: UITestCase {
    /// Keeps a dark player dark through repeated presentations from the mini player.
    func testDarkPlayerAppearance() {
        checkPlayerAppearance("Dark", dark: true)
    }

    /// Keeps a light player light even when the device uses another appearance.
    func testLightPlayerAppearance() {
        checkPlayerAppearance("Light", dark: false)
    }

    /// Exercises recreated tab accessories and changes between distinct or absent cover images.
    func testMiniPlayerArtworkAcrossTabsAndTrackChanges() {
        launch(scenario: "artwork")
        navigate("All Songs")
        library.play("UI Alpha")
        assertMiniPlayerArtwork("red")
        for _ in 0..<2 {
            for destination in ["Home", "All Songs", "Playlists", "Settings"] {
                navigate(destination)
                assertMiniPlayerArtwork("red")
            }
        }
        navigate("All Songs")
        for (title, color) in [
            ("UI Beta", "blue"), ("UI No Artwork", "placeholder"), ("UI Alpha", "red"),
        ] {
            library.play(title)
            assertMiniPlayerArtwork(color)
        }
        capture("Mini player artwork after tab and track changes")
    }

    /// Samples inside the cover's leading edge, away from metadata and the placeholder note.
    private func assertMiniPlayerArtwork(_ color: String) {
        let expand = app.element("miniPlayer.expand")
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        let frame = expand.frame
        let screenshot = app.screenshot().image
        let scale = screenshot.scale
        let rect = CGRect(
            x: (frame.minX + 10) * scale,
            y: (frame.midY - 1) * scale,
            width: 2 * scale,
            height: 2 * scale
        )
        guard let patch = screenshot.cgImage?.cropping(to: rect) else {
            XCTFail("The mini-player cover must be inside the screenshot.")
            return
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(patch, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let red = Double(pixel[0]) / 255
        let green = Double(pixel[1]) / 255
        let blue = Double(pixel[2]) / 255
        switch color {
        case "red":
            XCTAssertGreaterThan(red, 0.85)
            XCTAssertLessThan(green, 0.15)
            XCTAssertLessThan(blue, 0.15)
        case "blue":
            XCTAssertGreaterThan(blue, 0.85)
            XCTAssertLessThan(red, 0.15)
            XCTAssertLessThan(green, 0.15)
        default:
            XCTAssertGreaterThan(red, 0.05)
            XCTAssertGreaterThan(green, 0.02)
            XCTAssertGreaterThan(blue - red, 0.08)
            XCTAssertGreaterThan(blue - green, 0.08)
        }
    }

    /// Selects the saved appearance and checks pixels inside the sheet's unobstructed margin.
    private func checkPlayerAppearance(_ appearance: String, dark: Bool) {
        launch()
        navigate("Settings")
        app.element("settings.appearance").interact()
        app.buttons[appearance].interact()
        navigate("All Songs")
        library.play("UI Alpha")
        if #available(iOS 26.0, *) {
            let miniPlayer = app.element("miniPlayer.bar")
            XCTAssertTrue(miniPlayer.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(miniPlayer.frame.minX - app.frame.minX, 16)
            XCTAssertTrue(app.element("miniPlayer.toggle").isHittable)
            library.assertSearchDecorationIsContinuous()
            capture(appearance + " floating search and mini player")
        }
        for index in 0..<3 {
            player.open()
            assertBackground(dark: dark)
            capture("\(appearance) player presentation \(index + 1)")
            app.buttons["Collapse Player"].interact()
            XCTAssertTrue(app.element("miniPlayer.expand").waitForExistence(timeout: 5))
        }
    }

    /// Samples a small background patch below the navigation bar, away from artwork and controls.
    private func assertBackground(dark: Bool) {
        let navigation = app.navigationBars["Now Playing"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
        let frame = navigation.frame
        let screenshot = app.screenshot().image
        let scale = screenshot.scale
        let rect = CGRect(
            x: (frame.maxX - 18) * scale,
            y: (frame.maxY + 32) * scale,
            width: 4 * scale,
            height: 4 * scale
        )
        guard let patch = screenshot.cgImage?.cropping(to: rect) else {
            XCTFail("The player background sample must be inside the screenshot.")
            return
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let brightness: Double = pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(patch, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return Double(max(bytes[0], bytes[1], bytes[2])) / 255
        }
        if dark {
            XCTAssertLessThan(brightness, 0.2, "Dark player background must stay dark.")
        } else {
            XCTAssertGreaterThan(brightness, 0.85, "Light player background must stay light.")
        }
    }
}
#endif
