import SwiftUI

/// Exposes native restore and permanent-delete actions for a recoverable playlist.
struct TrashedPlaylistRow: View {
    /// Recoverable playlist displayed in the Trash section.
    let playlist: Playlist
    /// Custom playlist cover or a representative song, if its artwork is available.
    let cover: Track?
    /// Managed artwork location used by the shared cover renderer.
    let vault: MediaVault
    /// Prevents concurrent library mutations while an import or deletion is running.
    let isBusy: Bool
    /// Restores the playlist to the active library.
    let restore: () -> Void
    /// Requests confirmation before permanently deleting the playlist and its entries.
    let requestDeletion: () -> Void

    /// Uses desktop buttons and context actions or touch-native trailing swipe actions.
    var body: some View {
        #if os(macOS)
        HStack {
            label
            Spacer()
            actions
        }
        .contextMenu { actions }
        .disabled(isBusy)
        #else
        label
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive, action: requestDeletion) {
                    Label(L10n.text("Delete"), systemImage: "trash")
                }
                .accessibilityLabel(L10n.text("Delete Permanently"))
                .accessibilityIdentifier("trash.playlist.delete")
                .disabled(isBusy)
                Button(action: restore) {
                    Label(L10n.text("Restore Playlist"), systemImage: "arrow.uturn.backward")
                }
                .tint(.blue)
                .accessibilityIdentifier("trash.playlist.restore")
                .disabled(isBusy)
            }
        #endif
    }

    /// Displays playlist artwork, its name, and entry count consistently across platforms.
    private var label: some View {
        HStack(spacing: 12) {
            ArtworkView(track: cover, vault: vault, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name).lineLimit(2)
                Text(L10n.text("format.song_count", playlist.entries.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    #if os(macOS)
    /// Shares desktop button commands with the playlist row's context menu.
    @ViewBuilder private var actions: some View {
        Button(L10n.text("Restore Playlist"), action: restore)
            .accessibilityIdentifier("trash.playlist.restore")
        Button(L10n.text("Delete Permanently"), role: .destructive, action: requestDeletion)
            .accessibilityIdentifier("trash.playlist.delete")
    }
    #endif
}
