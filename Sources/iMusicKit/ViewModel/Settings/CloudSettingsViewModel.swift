import Observation

/// Minimal cloud configuration contract, independent of CloudKit transport details.
@MainActor
protocol CloudSettingsService: AnyObject {
    /// Whether cloud integration is configured for this build.
    var available: Bool { get }
    /// Whether synchronization is enabled.
    var enabled: Bool { get }
    /// Whether a cloud operation is active.
    var busy: Bool { get }
    /// Current localized service status.
    var message: String { get }
    /// Whether media assets are included in synchronization.
    var syncAudio: Bool { get set }
    /// Enables cloud synchronization after explicit user action.
    func enable(allowAccountChange: Bool) async
    /// Stops cloud synchronization.
    func disable() async
    /// Sends and fetches library changes.
    func sync() async
}

extension CloudSyncCoordinator: CloudSettingsService {}

/// Owns cloud-setting commands; SwiftUI controls do not create synchronization tasks.
@MainActor @Observable
final class CloudSettingsViewModel {
    /// Narrow observable cloud service; replaceable in tests.
    let cloud: any CloudSettingsService
    /// Whether cloud integration is configured.
    var available: Bool { cloud.available }
    /// Whether cloud controls must wait for a service operation.
    var busy: Bool { cloud.busy }
    /// Localized cloud status.
    var message: String { cloud.message }
    /// Explicit user enable/disable action.
    var enabled: Bool {
        get { cloud.enabled }
        set {
            Task {
                if newValue {
                    await cloud.enable(allowAccountChange: true)
                } else {
                    await cloud.disable()
                }
            }
        }
    }
    /// Portable asset-upload preference.
    var syncAudio: Bool {
        get { cloud.syncAudio }
        set { cloud.syncAudio = newValue }
    }
    /// Creates a cloud-only settings model.
    init(cloud: any CloudSettingsService) { self.cloud = cloud }
    /// Requests explicit synchronization without exposing task orchestration to the view.
    func syncNow() { Task { await cloud.sync() } }
}
