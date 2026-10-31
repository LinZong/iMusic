import SwiftUI

/// Artist cards own their typed destinations and category-specific actions.
struct ArtistCollectionView: View {
    /// Search and source projection scoped to artists.
    @State var model: ArtistCollectionViewModel
    /// Composes category cards on the shared collection layout.
    var body: some View {
        @Bindable var model = model
        CollectionGrid(
            search: $model.search,
            searchPrompt: L10n.text("Search Artists"),
            isEmpty: model.items.isEmpty
        ) {
            ForEach(model.items, id: \.self) { artist in
                NavigationLink {
                    SongCollectionView(
                        model: SongCollectionViewModel(
                            library: model.library,
                            player: model.player,
                            scope: .artist(artist)
                        )
                    )
                    .navigationTitle(artist)
                } label: {
                    CollectionCard(
                        title: artist,
                        subtitle: L10n.text(
                            "format.song_count.short",
                            model.library.catalog.songs(for: .artist(artist)).count
                        ),
                        track: model.library.tracks.first { $0.artist == artist },
                        vault: model.library.vault
                    )
                }
            }

        }
    }
}
