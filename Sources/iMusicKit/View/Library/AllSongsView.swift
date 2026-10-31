import SwiftUI

/// All Songs owns its collection shortcuts; other song pages never render them.
struct AllSongsView: View {
    /// Active library collection with its own search and selection.
    @State var model: SongCollectionViewModel

    /// Places navigation shortcuts above the reusable active-song collection.
    var body: some View {
        VStack(spacing: 0) {
            shortcuts
            SongCollectionView(model: model)
        }
    }

    /// Navigation affordances specific to the All Songs page.
    private var shortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                NavigationLink {
                    ArtistCollectionView(
                        model: ArtistCollectionViewModel(
                            library: model.library,
                            player: model.player
                        )
                    )
                    .navigationTitle(L10n.text("Artists"))
                } label: {
                    Label(L10n.text("Artists"), systemImage: "person.2")
                }
                NavigationLink {
                    AlbumCollectionView(
                        model: AlbumCollectionViewModel(
                            library: model.library,
                            player: model.player
                        )
                    )
                    .navigationTitle(L10n.text("Albums"))
                } label: {
                    Label(L10n.text("Albums"), systemImage: "square.stack")
                }
                NavigationLink {
                    GenreCollectionView(
                        model: GenreCollectionViewModel(
                            library: model.library,
                            player: model.player
                        )
                    )
                    .navigationTitle(L10n.text("Genres"))
                } label: {
                    Label(L10n.text("Genres"), systemImage: "guitars")
                }
                NavigationLink {
                    SongCollectionView(
                        model: SongCollectionViewModel(
                            library: model.library,
                            player: model.player,
                            scope: .favorites
                        )
                    )
                    .navigationTitle(L10n.text("Favorites"))
                } label: {
                    Label(L10n.text("Favorites"), systemImage: "heart")
                }
            }
            .buttonStyle(.bordered).padding(.horizontal).padding(.top, 12)
        }
    }
}
