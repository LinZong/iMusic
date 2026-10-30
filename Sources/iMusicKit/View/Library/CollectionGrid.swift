import SwiftUI

struct CollectionGrid: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @State var model: CollectionViewModel
    /// Renders the selected collection with its own search scope and appropriate empty state.
    var body: some View {
        @Bindable var model = model
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 145, maximum: 210), spacing: 20)],
                alignment: .leading,
                spacing: 24
            ) {
                if model.kind == .artists {
                    ForEach(model.artists, id: \.self) { artist in
                        NavigationLink {
                            SongListView(
                                model: SongListViewModel(
                                    library: model.library,
                                    player: model.player,
                                    destination: .artist(artist)
                                )
                            )
                            .navigationTitle(artist)
                        } label: {
                            card(
                                artist,
                                L10n.text(
                                    "format.song_count.short",
                                    model.library.songs(for: .artist(artist)).count
                                ),
                                model.library.tracks.first { $0.artist == artist }
                            )
                        }
                    }
                } else if model.kind == .albums {
                    ForEach(model.albums) { track in
                        NavigationLink {
                            SongListView(
                                model: SongListViewModel(
                                    library: model.library,
                                    player: model.player,
                                    destination: .album(track.albumKey)
                                )
                            )
                            .navigationTitle(track.displayAlbum)
                        } label: {
                            card(
                                track.displayAlbum,
                                track.albumArtist.isEmpty ? track.displayArtist : track.albumArtist,
                                track
                            )
                        }
                    }
                } else if model.kind == .genres {
                    ForEach(model.genres, id: \.self) { genre in
                        NavigationLink {
                            SongListView(
                                model: SongListViewModel(
                                    library: model.library,
                                    player: model.player,
                                    destination: .genre(genre)
                                )
                            )
                            .navigationTitle(genre.isEmpty ? L10n.text("Uncategorized") : genre)
                        } label: {
                            card(
                                genre.isEmpty ? L10n.text("Uncategorized") : genre,
                                L10n.text(
                                    "format.song_count.short",
                                    model.library.tracks.filter { $0.genre == genre }.count
                                ),
                                model.library.tracks.first { $0.genre == genre }
                            )
                        }
                    }
                } else {
                    ForEach(model.playlists) { playlist in
                        NavigationLink {
                            SongListView(
                                model: SongListViewModel(
                                    library: model.library,
                                    player: model.player,
                                    destination: .playlist(playlist.id)
                                )
                            )
                            .navigationTitle(playlist.name)
                        } label: {
                            card(
                                playlist.name,
                                L10n.text("format.song_count", playlist.entries.count),
                                model.library.cover(for: playlist)
                            )
                        }
                        .contextMenu {
                            Button(L10n.text("Delete Playlist"), role: .destructive) {
                                model.library.delete(playlist)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain).padding(24)
            if model.isEmpty && !LibrarySearch.isEmpty(model.search) {
                ContentUnavailableView.search(text: model.search)
            } else if model.isEmpty {
                ContentUnavailableView(
                    L10n.text("Nothing Here Yet"),
                    systemImage: "square.stack",
                    description: Text(
                        L10n.text("Import music or create a playlist with the plus button.")
                    )
                )
            }
        }
        .librarySearch(text: $model.search, prompt: model.searchPrompt)
    }
    private func card(_ title: String, _ subtitle: String, _ track: Track?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(track: track, vault: model.library.vault, size: 144)
            Text(title).font(.headline).lineLimit(2)
            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
