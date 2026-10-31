import SwiftUI

/// Genre cards own their typed destinations and category-specific actions.
struct GenreCollectionView: View {
    /// Search and source projection scoped to genres.
    @State var model: GenreCollectionViewModel
    /// Composes category cards on the shared collection layout.
    var body: some View {
        @Bindable var model = model
        CollectionGrid(
            search: $model.search,
            searchPrompt: L10n.text("Search Genres"),
            isEmpty: model.items.isEmpty
        ) {
            ForEach(model.items, id: \.self) { genre in
                NavigationLink {
                    SongCollectionView(
                        model: SongCollectionViewModel(
                            library: model.library,
                            player: model.player,
                            scope: .genre(genre)
                        )
                    )
                    .navigationTitle(
                        genre.isEmpty ? L10n.text("Uncategorized") : genre
                    )
                } label: {
                    CollectionCard(
                        title: genre.isEmpty ? L10n.text("Uncategorized") : genre,
                        subtitle: L10n.text(
                            "format.song_count.short",
                            model.library.tracks.filter { $0.genre == genre }.count
                        ),
                        track: model.library.tracks.first { $0.genre == genre },
                        vault: model.library.vault
                    )
                }
            }

        }
    }
}
