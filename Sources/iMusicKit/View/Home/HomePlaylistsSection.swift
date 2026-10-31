import SwiftUI

/// Dedicated playlists section of the configurable Home feed.
struct HomePlaylistsSection: View {
    /// Home feature projections and navigation dependencies.
    let model: HomeViewModel

    /// Renders this section without changing the home feed's other sections.
    var body: some View {

        if !model.library.playlists.isEmpty {
            Text(L10n.text("My Playlists")).font(.title2.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(model.library.playlists.prefix(12)) { playlist in
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
                            VStack(alignment: .leading, spacing: 8) {
                                ArtworkView(
                                    track: model.library.catalog.cover(for: playlist),
                                    vault: model.library.vault,
                                    size: 128
                                )
                                Text(playlist.name).font(.headline).lineLimit(1)
                                Text(L10n.text("format.song_count", playlist.entries.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 128)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

    }

}
