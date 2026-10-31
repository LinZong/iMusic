import SwiftUI

/// Dedicated categories section of the configurable Home feed.
struct HomeCategoriesSection: View {
    /// Home feature projections and navigation dependencies.
    let model: HomeViewModel
    /// Shared icon height for equal category tiles at every text size.
    @ScaledMetric(relativeTo: .title2) private var categoryIconHeight: CGFloat = 28

    /// Renders this section without changing the home feed's other sections.
    var body: some View {

        EqualTileRow {
            NavigationLink {
                ArtistCollectionView(
                    model: ArtistCollectionViewModel(library: model.library, player: model.player)
                )
                .navigationTitle(L10n.text("Artists"))
            } label: {
                category(L10n.text("Artists"), "person.2", model.library.catalog.artists.count)
            }
            .accessibilityIdentifier("home.artists")
            NavigationLink {
                AlbumCollectionView(
                    model: AlbumCollectionViewModel(library: model.library, player: model.player)
                )
                .navigationTitle(L10n.text("Albums"))
            } label: {
                category(L10n.text("Albums"), "square.stack", model.library.catalog.albums.count)
            }
            .accessibilityIdentifier("home.albums")
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
                category(
                    L10n.text("Favorites"),
                    "heart",
                    model.favoriteCount
                )
            }
            .accessibilityIdentifier("home.favorites")
        }
        .buttonStyle(.plain)

    }
    private func category(_ label: String, _ symbol: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor)
                .frame(height: categoryIconHeight)
            Text(label).font(.headline)
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(18)
        .background(
            .quaternary.opacity(0.5),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }
}
