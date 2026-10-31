import SwiftUI

/// Independent Music and Folders settings section.
struct MusicSourcesSettingsSection: View {
    /// Library metadata and maintenance commands.
    let library: LibraryViewModel
    /// Explicit source import and authorization requests.
    let imports: ImportViewModel
    /// Artist grouping preferences.
    @Bindable var preferences: PreferencesViewModel

    /// Renders controls and routes user actions to this feature's model.
    var body: some View {
        Section(L10n.text("Music and Folders")) {
            NavigationLink(L10n.text("Find Duplicate Songs")) {
                DuplicatesView(model: DuplicatesViewModel(library: library))
            }
            Button(L10n.text("Move Empty Playlists to Trash")) {
                library.commands.moveEmptyPlaylistsToTrash()
            }
            Button(L10n.text("Import Music Files…")) { imports.picker.present(.audio) }
            Button(L10n.text("Wi-Fi Transfer…")) { imports.transfers.presented = true }
            Button(L10n.text("Link Folder…")) {
                imports.folders.relinkFolderID = nil
                imports.folders.chooseFolder()
            }
            NavigationLink(L10n.text("Linked Folders")) {
                LinkedFoldersView(library: library, imports: imports)
            }
            .accessibilityIdentifier("settings.linkedFolders")
            Toggle(L10n.text("Split Collaborating Artists"), isOn: $preferences.splitArtists)
            if preferences.splitArtists {
                TextField(
                    L10n.text("Separators (separate with |)"),
                    text: $preferences.artistSeparators
                )
            }
            Text(
                L10n.text(
                    """
                    Linked folders play original files without copying audio into iMusic. \
                    Cloud \
                    files download through the system before metadata is read. Unlinking and \
                    deleting songs never deletes these originals.
                    """
                )
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
