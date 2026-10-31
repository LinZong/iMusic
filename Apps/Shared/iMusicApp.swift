import SwiftUI
import iMusicKit

#if os(iOS)
import UIKit
#endif

@main @MainActor
struct IMusicApp: App {
    /// Application composition root created at startup, or nil when the persistent library cannot
    /// be opened.
    @State private var model: AppModel?
    /// Localized library initialization failure displayed without deleting the existing library.
    @State private var startupError: String?
    #if IMUSIC_UI_TESTING
    /// Prevents test actions before fixture import and library refresh finish.
    @State private var testReady = false
    #endif
    #if os(iOS)
    /// UIKit lifecycle adapter handling background cloud notifications for the SwiftUI app.
    @UIApplicationDelegateAdaptor(MusicAppDelegate.self) private var appDelegate
    #endif
    /// Opens the configured library and retains any startup failure for presentation without
    /// resetting user data.
    init() {
        do {
            #if IMUSIC_UI_TESTING
            _model = State(initialValue: try UITestSupport.makeModel())
            #else
            let identifier =
                Bundle.main.object(forInfoDictionaryKey: "IMusicCloudContainer") as? String
            let root =
                ProcessInfo.processInfo.environment["IMUSIC_LIBRARY_PATH"]
                .map { URL(fileURLWithPath: $0) } ?? MediaVault.defaultRoot
            _model = State(
                initialValue: try AppModel(
                    root: root,
                    cloudIdentifier: identifier?.isEmpty == false ? identifier : nil
                )
            )
            #endif
        } catch { _startupError = State(initialValue: error.localizedDescription) }
    }
    /// App scenes, feature wiring, macOS playback commands, and the optional mini-player window.
    var body: some Scene {
        WindowGroup {
            mainContent
        }
        #if os(macOS)
        .defaultSize(width: 1_040, height: 740)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L10n.text("Import Music…")) { model?.imports.showImporter = true }
                .keyboardShortcut("o")
            }
            CommandMenu(L10n.text("Play")) {
                Button(L10n.text("Play / Pause")) { model?.playback.toggle() }
                .keyboardShortcut(.space, modifiers: [])
                Button(L10n.text("Next Track")) { model?.playback.next() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                Button(L10n.text("Previous Track")) { model?.playback.previous() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                Button(L10n.text("Now Playing")) { model?.presentation.showPlayer = true }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button(L10n.text("Play Queue")) { model?.presentation.showQueue = true }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
        #endif
        #if os(macOS)
        Window(L10n.text("Mini Player"), id: "mini-player") {
            if let model {
                MiniPlayerWindow(model: model.player)
            } else {
                startupFailure
            }
        }
        .defaultSize(width: 340, height: 420).windowResizability(.contentMinSize)
        #endif
    }
    /// Gates test-host startup until fixtures are ready; normal builds launch directly.
    @ViewBuilder private var mainContent: some View {
        if let model {
            #if IMUSIC_UI_TESTING
            if testReady {
                RootView(model: model)
            } else if startupError != nil {
                startupFailure
            } else {
                ProgressView()
                    .task {
                        do {
                            try await UITestSupport.prepare(model)
                            testReady = true
                        } catch { startupError = error.localizedDescription }
                    }
            }
            #else
            RootView(model: model).onOpenURL { url in model.imports.importURLs([url]) }
            #endif
        } else {
            startupFailure
        }
    }

    /// Shows the same centered library failure in both the main and restored mini-player windows.
    private var startupFailure: some View {
        ContentUnavailableView(
            L10n.text("Unable to Open Library"),
            systemImage: "externaldrive.badge.exclamationmark",
            description: Text(
                startupError
                    ?? L10n.text(
                        """
                        Check disk space and file permissions. The library will not be \
                        cleared automatically.
                        """
                    )
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

#if os(iOS)
final class MusicAppDelegate: NSObject, UIApplicationDelegate {
    /// Registers for silent cloud notifications only when this build declares an iCloud container.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let identifier = Bundle.main.object(forInfoDictionaryKey: "IMusicCloudContainer")
            as? String, !identifier.isEmpty
        {
            application.registerForRemoteNotifications()
        }
        return true
    }
    // SwiftUI owns phone/tablet scene delegates. CarPlay uses the explicit
    // manifest in its build configuration; returning the existing session's
    // SwiftUI delegate here creates a recursive delegate chain on launch.
    /// Handles a silent cloud update, including a cold launch without a visible SwiftUI scene.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            guard let model = CarPlaySceneDelegate.model, model.cloud.available,
                (try? model.store.setting("cloudEnabled", as: Bool.self)) == true
            else {
                completionHandler(.noData)
                return
            }
            // A silent notification can cold-launch without a visible SwiftUI scene.
            if model.cloud.enabled {
                await model.cloud.sync()
            } else {
                await model.cloud.enable(allowAccountChange: false)
            }
            completionHandler(model.cloud.enabled ? .newData : .noData)
        }
    }
}
#endif
