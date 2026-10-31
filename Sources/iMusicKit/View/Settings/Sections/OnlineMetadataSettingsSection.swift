import SwiftUI

/// Independent Online Metadata (Optional) settings section.
struct OnlineMetadataSettingsSection: View {
    /// Consent state scoped to the optional online-metadata setting.
    @State var model: OnlineMetadataSettingsViewModel

    /// Renders controls and routes user actions to this feature's model.
    var body: some View {
        @Bindable var model = model
        Section(L10n.text("Online Metadata (Optional)")) {
            Toggle(
                L10n.text("Allow Online Artwork Search"),
                isOn: $model.enabled
            )
            Text(
                L10n.text(
                    """
                    Off by default. Search manually from the song editor. Artist and album \
                    names are sent to MusicBrainz, and artwork comes from Cover Art Archive. \
                    Music files are never uploaded.
                    """
                )
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .confirmationDialog(
            L10n.text("Enable Online Metadata Search?"),
            isPresented: $model.consent,
            titleVisibility: .visible
        ) {
            Button(L10n.text("Allow Artist and Album Names to Be Sent for Search")) {
                model.allow()
            }
            Button(L10n.text("Cancel"), role: .cancel) {}
        } message: {
            Text(
                L10n.text(
                    """
                    The app connects only when you search manually. MusicBrainz and Cover Art \
                    Archive receive the names needed for the query.
                    """
                )
            )
        }
    }
}
