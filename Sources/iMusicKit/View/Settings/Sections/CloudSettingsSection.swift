import SwiftUI

/// Independent iCloud (Optional) settings section.
struct CloudSettingsSection: View {
    /// Cloud-specific commands and observable presentation state.
    @State var model: CloudSettingsViewModel

    /// Renders controls and routes user actions to this feature's model.
    var body: some View {
        @Bindable var model = model
        Section(L10n.text("iCloud (Optional)")) {
            Toggle(
                L10n.text("Sync Library"),
                isOn: $model.enabled
            )
            .disabled(!model.available || model.busy)
            Toggle(L10n.text("Also Upload Music and Artwork"), isOn: $model.syncAudio)
                .disabled(
                    !model.enabled
                )
            Button(L10n.text("Sync Now")) { model.syncNow() }
                .disabled(
                    !model.enabled || model.busy
                )
            if model.busy { ProgressView() }
            Text(
                model.available
                    ? model.message
                    : L10n.text(
                        """
                        This is a local build. iCloud requires a developer team, a CloudKit \
                        container, and a Cloud build configuration.
                        """
                    )
            )
            .font(.caption).foregroundStyle(.secondary)
            Text(
                L10n.text(
                    """
                    Imported music stays available offline on this device. Download songs from \
                    other devices using the song menu.
                    """
                )
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
