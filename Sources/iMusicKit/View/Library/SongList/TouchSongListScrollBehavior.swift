import SwiftUI

#if os(iOS)
/// Touch-list layout policies supplied by page-level presentation owners.
enum TouchSongListScrollBehavior {
    /// Retains the zero vertical content margins used by fixed song pages.
    case fixedPage
    /// Uses nonediting lazy content with native navigation insets and scrolling legacy controls.
    case systemNavigation
}

/// Stores the layout policy without coupling the generic list to a feature route.
private struct TouchSongListScrollBehaviorKey: EnvironmentKey {
    /// Existing fixed song pages remain unchanged unless their page opts into system navigation.
    static let defaultValue = TouchSongListScrollBehavior.fixedPage
}

extension EnvironmentValues {
    /// Presentation capability shared by touch list layout and summary placement.
    var touchSongListScrollBehavior: TouchSongListScrollBehavior {
        get { self[TouchSongListScrollBehaviorKey.self] }
        set { self[TouchSongListScrollBehaviorKey.self] = newValue }
    }
}
#endif
