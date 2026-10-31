import SwiftUI

/// Composes independent settings sections without performing their business operations.
struct SettingsView: View {
    /// Dependencies used to create each section's focused model.
    @State var model: SettingsViewModel
    /// Renders the settings navigation surface.
    var body: some View {
        Form {
            StatisticsSettingsSection(model: ListeningStatsViewModel(library: model.library))
            AppearanceSettingsSection(preferences: model.preferences)
            MusicSourcesSettingsSection(
                library: model.library,
                imports: model.imports,
                preferences: model.preferences
            )
            BackupSettingsSection(library: model.library, imports: model.imports)
            CloudSettingsSection(model: CloudSettingsViewModel(cloud: model.library.cloud))
            OnlineMetadataSettingsSection(
                model: OnlineMetadataSettingsViewModel(
                    preferences: model.preferences
                )
            )
            AboutSettingsSection(imports: model.imports)
        }
        .formStyle(.grouped)
    }
}
