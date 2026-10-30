import SwiftUI

enum CollectionKind { case artists, albums, genres, playlists }
struct CollectionGrid: View {
    @Bindable var model: AppModel
    let kind: CollectionKind
    @State private var search = ""
    private var searchPrompt: String {
        switch kind {
        case .artists: L10n.text("Search Artists")
        case .albums: L10n.text("Search Albums")
        case .genres: L10n.text("Search Genres")
        case .playlists: L10n.text("Search Playlists")
        }
    }
    private var artists: [String] { model.artists.filter { LibrarySearch.matches(search, in: [$0]) } }
    private var albums: [Track] { model.albums.filter { LibrarySearch.matches(search, in: [$0.displayAlbum, $0.displayArtist, $0.albumArtist]) } }
    private var genres: [String] { Array(Set(model.tracks.map(\.genre))).sorted().filter { LibrarySearch.matches(search, in: [$0.isEmpty ? L10n.text("Uncategorized") : $0]) } }
    private var playlists: [Playlist] { model.playlists.filter { LibrarySearch.matches(search, in: [$0.name]) } }
    private var isEmpty: Bool {
        switch kind {
        case .artists: artists.isEmpty
        case .albums: albums.isEmpty
        case .genres: genres.isEmpty
        case .playlists: playlists.isEmpty
        }
    }
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145, maximum: 210), spacing: 20)], alignment: .leading, spacing: 24) {
                if kind == .artists {
                    ForEach(artists, id: \.self) { artist in
                        NavigationLink { SongListView(model: model, destination: .artist(artist)).navigationTitle(artist) } label: { card(artist, L10n.text("format.song_count.short", model.songs(for: .artist(artist)).count), model.tracks.first { $0.artist == artist }) }
                    }
                } else if kind == .albums {
                    ForEach(albums) { track in
                        NavigationLink { SongListView(model: model, destination: .album(track.albumKey)).navigationTitle(track.displayAlbum) } label: { card(track.displayAlbum, track.albumArtist.isEmpty ? track.displayArtist : track.albumArtist, track) }
                    }
                } else if kind == .genres {
                    ForEach(genres, id: \.self) { genre in
                        NavigationLink { SongListView(model: model, destination: .genre(genre)).navigationTitle(genre.isEmpty ? L10n.text("Uncategorized") : genre) } label: { card(genre.isEmpty ? L10n.text("Uncategorized") : genre, L10n.text("format.song_count.short", model.tracks.filter { $0.genre == genre }.count), model.tracks.first { $0.genre == genre }) }
                    }
                } else {
                    ForEach(playlists) { playlist in
                        NavigationLink { SongListView(model: model, destination: .playlist(playlist.id)).navigationTitle(playlist.name) } label: { card(playlist.name, L10n.text("format.song_count", playlist.entries.count), model.cover(for: playlist)) }
                            .contextMenu { Button(L10n.text("Delete Playlist"), role: .destructive) { model.delete(playlist) } }
                    }
                }
            }.buttonStyle(.plain).padding(24)
            if isEmpty && !LibrarySearch.isEmpty(search) {
                ContentUnavailableView.search(text: search)
            } else if isEmpty {
                ContentUnavailableView(L10n.text("Nothing Here Yet"), systemImage: "square.stack", description: Text(L10n.text("Import music or create a playlist with the plus button.")))
            }
        }
        .librarySearch(text: $search, prompt: searchPrompt)
    }
    private func card(_ title: String, _ subtitle: String, _ track: Track?) -> some View {
        VStack(alignment: .leading, spacing: 8) { ArtworkView(track: track, vault: model.vault, size: 144); Text(title).font(.headline).lineLimit(2); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
