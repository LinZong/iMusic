import SwiftUI

#if os(iOS)
import UIKit

/// Finishes native title layout after compact iOS 26 search dismisses over scrolled content.
@available(iOS 26.0, *)
struct NavigationSearchLayoutRecovery: UIViewControllerRepresentable {
    /// Read below searchable so this adapter follows the system's actual presentation lifetime.
    @Environment(\.isSearching) private var isSearching
    /// Regular-width search does not replace the navigation title with a compact search toolbar.
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Adds a noninteractive child only to access its own enclosing navigation controller.
    func makeUIViewController(context: Context) -> Controller { Controller() }

    /// Forwards presentation changes without retaining queries or observing scroll positions.
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(isSearching: isSearching, enabled: sizeClass == .compact)
    }

    /// Invalidates completions when the page or its native search presentation is removed.
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.invalidate()
    }

    /// Owns a page-scoped transition completion, never a navigation or search delegate.
    final class Controller: UIViewController {
        /// Last native search state; initial installation never requests a recovery layout.
        private var wasSearching = false
        /// Rejects completions from an earlier search or a removed presentation adapter.
        private var generation = 0

        /// Supplies an invisible, noninteractive view that does not enter accessibility navigation.
        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
            view.accessibilityElementsHidden = true
        }

        /// Requests layout once dismissal finishes, preserving native title modes and scroll state.
        func update(isSearching: Bool, enabled: Bool) {
            guard enabled else {
                invalidate()
                return
            }
            guard wasSearching != isSearching else { return }
            wasSearching = isSearching
            generation += 1
            guard !isSearching,
                let navigation = navigationController,
                let page = navigation.topViewController
            else { return }

            let expectedGeneration = generation
            let search = page.navigationItem.searchController
            let recover = { [weak self, weak navigation, weak page, weak search] in
                guard let self, let navigation, let page,
                    self.generation == expectedGeneration,
                    !self.wasSearching,
                    self.viewIfLoaded?.window != nil,
                    navigation.topViewController === page,
                    search?.isActive != true
                else { return }
                navigation.view.setNeedsLayout()
                navigation.navigationBar.setNeedsLayout()
                navigation.view.layoutIfNeeded()
            }
            if let transition = search?.transitionCoordinator ?? navigation.transitionCoordinator {
                transition.animate(alongsideTransition: nil) { context in
                    if !context.isCancelled { recover() }
                }
            } else {
                // Nonanimated dismissal still finishes outside SwiftUI's current update pass.
                DispatchQueue.main.async(execute: recover)
            }
        }

        /// Leaves no pending work capable of affecting a subsequently presented page.
        func invalidate() {
            generation += 1
            wasSearching = false
        }
    }
}
#endif
