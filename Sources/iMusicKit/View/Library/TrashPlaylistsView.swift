import SwiftUI

/// Presents recoverable playlists without song columns or song-only summary information.
struct TrashPlaylistsView: View {
    /// Playlist-only query, deletion confirmation, and library dependencies.
    @State var model: TrashPlaylistsViewModel
    /// Category-aware search binding that rejects native teardown from an inactive tab.
    let searchBinding: Binding<String>

    /// Keeps the summary at the top and centers empty or unmatched content in the remaining area.
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            #if os(iOS)
            LibrarySearchInput(text: searchBinding, prompt: L10n.text("Search Trashed Playlists"))
            #endif
            Text(L10n.text("format.playlist.count", model.playlists.count))
                #if os(macOS)
            .font(.body)
                #else
            .font(.caption)
                #endif
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .accessibilityIdentifier("trash.playlistSummary")

            if model.playlists.isEmpty {
                if LibrarySearch.isEmpty(model.search) {
                    ContentUnavailableView(
                        L10n.text("No Deleted Playlists"),
                        systemImage: "music.note.list",
                        description: Text(
                            L10n.text(
                                """
                                Playlists moved to Trash appear here until you restore or \
                                permanently delete them. Songs and audio files are kept.
                                """
                            )
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: model.search)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                List(model.playlists) { playlist in
                    TrashedPlaylistRow(
                        playlist: playlist,
                        cover: model.library.catalog.cover(for: playlist),
                        vault: model.library.vault,
                        isBusy: model.library.activity.isWorking
                            || model.library.activity.importing,
                        restore: { model.library.commands.restore(playlist) },
                        requestDeletion: { model.pendingDeletion = playlist }
                    )
                    .padding(.vertical, 6)
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .trashToolbarSearch(text: searchBinding, prompt: L10n.text("Search Trashed Playlists"))
        .alert(
            L10n.text("Permanently Delete Playlist?"),
            isPresented: Binding(
                get: { model.pendingDeletion != nil },
                set: { if !$0 { model.pendingDeletion = nil } }
            ),
            presenting: model.pendingDeletion
        ) { playlist in
            Button(L10n.text("Delete Permanently"), role: .destructive) {
                model.library.commands.permanentlyDelete(playlist)
                model.pendingDeletion = nil
            }
            Button(L10n.text("Cancel"), role: .cancel) { model.pendingDeletion = nil }
        } message: { playlist in
            Text(L10n.text("format.trash.delete_playlist", playlist.name))
        }
    }
}
