import SwiftUI

/// Deleted-song recovery UI; cannot expose playback or playlist-editing controls.
struct TrashSongsView: View {
    /// Recovery data, confirmation state, and page-local list mechanics.
    @State var model: TrashSongsViewModel
    /// Retained query binding coordinated by the Trash category owner.
    let searchBinding: Binding<String>

    /// Composes recovery rows and menus while retaining independent native Trash search.
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            SongListView(
                state: model.state,
                rows: model.rows,
                library: model.library,
                rowContent: { row in
                    TrashedSongRow(row: row, model: model)
                },
                actions: { EmptyView() },
                emptyContent: {
                    ContentUnavailableView(
                        L10n.text("No Deleted Songs"),
                        systemImage: "trash",
                        description: Text(
                            L10n.text(
                                """
                                Songs moved to Trash appear here until you restore or permanently \
                                delete them.
                                """
                            )
                        )
                    )
                },
                contextActions: { selection in
                    Button(L10n.text("Restore")) {
                        model.restore(Set(selection.map(\.id)))
                    }
                    .accessibilityIdentifier("trash.restore")
                    .disabled(model.isBusy)
                    Button(L10n.text("Delete Permanently"), role: .destructive) {
                        model.requestDeletion(Set(selection.map(\.id)))
                    }
                    .accessibilityIdentifier("trash.delete")
                    .disabled(model.isBusy)
                },
                move: nil
            )
        }
        .trashSearch(text: searchBinding, prompt: L10n.text("Search Trashed Songs"))
        .alert(
            L10n.text("Permanently Delete Music?"),
            isPresented: Binding(
                get: { !model.pendingPermanentDeletion.isEmpty },
                set: { if !$0 { model.pendingPermanentDeletion = [] } }
            ),
            presenting: model.pendingPermanentDeletion
        ) { tracks in
            Button(L10n.text("Delete Permanently"), role: .destructive) {
                model.library.commands.permanentlyDelete(tracks)
            }
            Button(L10n.text("Cancel"), role: .cancel) { model.pendingPermanentDeletion = [] }
        } message: { tracks in
            if tracks.allSatisfy(\.isLinked) {
                Text(
                    L10n.text(
                        """
                        Only library entries and derived artwork will be deleted. Original \
                        files in linked folders will remain untouched.
                        """
                    )
                )
            } else if tracks.count == 1, let track = tracks.first {
                Text(L10n.text("format.trash.delete_song", track.title))
            } else {
                Text(L10n.text("format.trash.delete_count", tracks.count))
            }
        }

    }
}
