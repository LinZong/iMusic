import Foundation

/// Silent-notification capability independent of the application container and vehicle scenes.
@MainActor
public protocol CloudNotificationHandling: AnyObject {
    /// Handles a configured, consented cloud update and reports whether synchronization
    /// was enabled.
    func handleCloudNotification() async -> Bool
}

extension AppModel: CloudNotificationHandling {}

/// Weak lifecycle bridge used only by the native background-notification adapter.
@MainActor
public enum CloudNotificationReceiver {
    /// Application-lifetime handler registered by the composition root.
    public static weak var handler: (any CloudNotificationHandling)?
    /// Routes a silent update without retaining an application or depending on CarPlay startup.
    public static func receive() async -> Bool {
        await handler?.handleCloudNotification() ?? false
    }
}
