import SwiftUI

/// Independent Appearance settings section.
struct AppearanceSettingsSection: View {
    /// Persisted appearance preferences.
    @Bindable var preferences: PreferencesViewModel

    /// Renders controls and routes user actions to this feature's model.
    var body: some View {
        Section(L10n.text("Appearance")) {
            Picker(L10n.text("Display Mode"), selection: $preferences.appearance) {
                Text(L10n.text("System")).tag("system")
                Text(L10n.text("Light")).tag("light")
                Text(L10n.text("Dark")).tag("dark")
            }
            .accessibilityIdentifier("settings.appearance")
            NavigationLink(L10n.text("Customize Home")) {
                HomeLayoutView(model: preferences)
            }
        }
    }
}
