import SwiftUI

/// Playlist cards own their typed destinations and category-specific actions.
struct PlaylistCollectionView: View {
    /// Search and source projection scoped to playlists.
    @State var model: PlaylistCollectionViewModel
    /// Composes category cards on the shared collection layout.
    var body: some View {
        @Bindable var model = model
        CollectionGrid(
            search: $model.search,
            searchPrompt: L10n.text("Search Playlists"),
            isEmpty: model.items.isEmpty
        ) {
            ForEach(model.items) { playlist in
                NavigationLink {
                    PlaylistDetailView(
                        model: PlaylistDetailViewModel(
                            library: model.library,
                            player: model.player,
                            playlistID: playlist.id
                        )
                    )
                    .navigationTitle(playlist.name)
                } label: {
                    CollectionCard(
                        title: playlist.name,
                        subtitle: L10n.text("format.song_count", playlist.entries.count),
                        track: model.library.catalog.cover(for: playlist),
                        vault: model.library.vault
                    )
                }
                .accessibilityIdentifier("playlist.open.\(playlist.name)")
                .contextMenu {
                    Button(L10n.text("Delete Playlist"), role: .destructive) {
                        model.library.commands.delete(playlist)
                    }
                    .accessibilityIdentifier("playlist.delete")
                }
            }
        }
    }
}
