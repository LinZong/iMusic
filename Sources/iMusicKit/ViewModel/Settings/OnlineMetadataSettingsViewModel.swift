import Observation

/// Owns consent for the optional, manually requested online metadata feature.
@MainActor @Observable
final class OnlineMetadataSettingsViewModel {
    /// Persisted metadata permission; no network request is made by this setting.
    let preferences: PreferencesViewModel
    /// Whether the explanation and explicit opt-in choices are visible.
    var consent = false
    /// Enables only after consent, while allowing immediate revocation.
    var enabled: Bool {
        get { preferences.onlineEnabled }
        set {
            if newValue { consent = true } else { preferences.onlineEnabled = false }
        }
    }
    /// Creates an independently owned consent model.
    init(preferences: PreferencesViewModel) { self.preferences = preferences }
    /// Persists explicit approval from the consent dialog.
    func allow() { preferences.onlineEnabled = true }
}
