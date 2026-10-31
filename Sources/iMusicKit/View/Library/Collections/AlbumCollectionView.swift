import SwiftUI

/// Album cards own their typed destinations and category-specific actions.
struct AlbumCollectionView: View {
    /// Search and source projection scoped to albums.
    @State var model: AlbumCollectionViewModel
    /// Composes category cards on the shared collection layout.
    var body: some View {
        @Bindable var model = model
        CollectionGrid(
            search: $model.search,
            searchPrompt: L10n.text("Search Albums"),
            isEmpty: model.items.isEmpty
        ) {
            ForEach(model.items) { track in
                NavigationLink {
                    SongCollectionView(
                        model: SongCollectionViewModel(
                            library: model.library,
                            player: model.player,
                            scope: .album(track.albumKey)
                        )
                    )
                    .navigationTitle(track.displayAlbum)
                } label: {
                    CollectionCard(
                        title: track.displayAlbum,
                        subtitle: track.albumArtist.isEmpty
                            ? track.displayArtist : track.albumArtist,
                        track: track,
                        vault: model.library.vault
                    )
                }
            }

        }
    }
}
