import SwiftUI

/// Playlist-only list composition with occurrence editing and playlist presentation.
struct PlaylistDetailView: View {
    /// Editing state and actions scoped to one playlist identity.
    @State var model: PlaylistDetailViewModel

    /// Composes editable rows without adding playlist conditions to the base list.
    var body: some View {
        @Bindable var model = model
        @Bindable var state = model.state
        SongListPage(
            title: model.title,
            search: $state.search,
            searchPrompt: L10n.text("Search Songs")
        ) {
            SongListView(
                state: model.state,
                rows: model.rows,
                library: model.library,
                rowContent: { row in
                    TrackRow(model: model.player, track: row.track) { model.play(row: row) }
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                        .swipeActions(edge: .trailing) {
                            Button(L10n.text("Remove from Playlist"), role: .destructive) {
                                model.remove([row.id])
                            }
                        }
                },
                actions: { SongListPlaybackActions(model: model) },
                emptyContent: {
                    ContentUnavailableView(
                        L10n.text("No Music Here Yet"),
                        systemImage: "music.note.list",
                        description: Text(
                            L10n.text("Import music to start organizing your library.")
                        )
                    )
                },
                contextActions: { selection in
                    TrackActions(model: model.player, tracks: selection.map(\.track))
                    Button(L10n.text("Remove from Playlist"), role: .destructive) {
                        model.remove(Set(selection.map(\.id)))
                    }
                    Button(L10n.text("Play Selected Songs")) { model.play(row: selection.first) }
                },
                move: model.canReorder ? { model.move(from: $0, to: $1) } : nil,
                primaryAction: { model.play(row: $0.first) }
            )
        }
        .toolbar {
            if let playlist = model.playlist {
                ToolbarItem {
                    Menu {
                        Button(L10n.text("Add Songs")) { model.addingTracks = true }
                            .accessibilityIdentifier("playlist.addSongs")
                        Button(L10n.text("Edit Playlist and Artwork")) {
                            model.editingPlaylist = true
                        }
                        Button(L10n.text("Rename")) {
                            model.newName = playlist.name
                            model.rename = true
                        }
                        Button(L10n.text("Sort by Song Title")) { model.sortByTitle() }
                        Button(L10n.text("Reverse Order")) { model.reverse() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("playlist.actions")
                }
                #if os(iOS)
                ToolbarItem { EditButton() }
                #endif
            }
        }
        .alert(L10n.text("Rename Playlist"), isPresented: $model.rename) {
            TextField(L10n.text("Name"), text: $model.newName)
            Button(L10n.text("Save")) { model.saveName() }
            Button(L10n.text("Cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $model.addingTracks) {
            if let playlist = model.playlist {
                PlaylistSongPicker(
                    model: PlaylistSongPickerViewModel(library: model.library, playlist: playlist)
                )
            }
        }
        .sheet(isPresented: $model.editingPlaylist) {
            if let playlist = model.playlist {
                PlaylistEditor(
                    model: PlaylistEditorViewModel(library: model.library, playlist: playlist)
                )
            }
        }
    }
}
