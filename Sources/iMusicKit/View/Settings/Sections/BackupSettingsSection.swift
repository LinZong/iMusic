import SwiftUI

/// Independent Backup and Restore settings section.
struct BackupSettingsSection: View {
    /// Trash counts and recovery destinations.
    let library: LibraryViewModel
    /// Backup, restore, and export presentation requests.
    let imports: ImportViewModel

    /// Renders controls and routes user actions to this feature's model.
    var body: some View {
        Section(L10n.text("Backup and Restore")) {
            Text(
                L10n.text(
                    """
                    Backups include linked song metadata and artwork, not original audio \
                    or folder permissions. Relink folders after restoring on another \
                    device.
                    """
                )
            )
            .font(.caption).foregroundStyle(.secondary)
            Button(L10n.text("Export Full Backup (Including Music)")) {
                imports.archives.exportBackup(full: true)
            }
            Button(L10n.text("Export Library Information")) {
                imports.archives.exportBackup(full: false)
            }
            Button(L10n.text("Restore from Backup…")) { imports.picker.present(.backup) }
            NavigationLink {
                TrashView(
                    model: TrashViewModel(
                        library: library
                    )
                )
                .navigationTitle(L10n.text("Trash"))
            } label: {
                LabeledContent(
                    L10n.text("Trash"),
                    value: L10n.text(
                        "format.trash.summary",
                        library.deletedTracks.count,
                        library.deletedPlaylists.count
                    )
                )
            }
            .accessibilityIdentifier("settings.trash")
            Text(
                L10n.text(
                    """
                    Restores merge information and preserve newer edits. Deleted music stays \
                    in Trash and is never automatically erased.
                    """
                )
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
