import XCTest

extension XCUIElement {
    /// Clicks with the native Mac pointer or taps with the mobile touch system.
    @MainActor func interact() {
        #if os(macOS)
        click()
        #else
        tap()
        #endif
    }

    /// Finds a stable accessibility identifier independently of native control type.
    @MainActor func element(_ identifier: String) -> XCUIElement {
        descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Matches text exposed as a label on iOS or a value by native AppKit accessibility.
    @MainActor func text(containing title: String) -> XCUIElement {
        staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", title, title)
        )
        .firstMatch
    }

    /// Reads AppKit numeric slider values as well as string values exposed by UIKit.
    @MainActor var numericValue: Double {
        if let number = value as? NSNumber { return number.doubleValue }
        return Double(value as? String ?? "") ?? .nan
    }

    /// Adjusts a native slider without depending on absolute screen coordinates.
    @MainActor func setFraction(_ fraction: CGFloat) {
        #if os(macOS)
        coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5)).click()
        #else
        adjust(toNormalizedSliderPosition: fraction)
        #endif
    }
}
