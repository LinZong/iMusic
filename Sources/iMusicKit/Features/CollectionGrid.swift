import SwiftUI

enum CollectionKind { case artists, albums, genres, playlists }
struct CollectionGrid: View {
    /// Shared observable app model providing library snapshots and the actions used by this view.
    @Bindable var model: AppModel
    /// Collection category displayed by this grid: artists, albums, genres, or playlists.
    let kind: CollectionKind
    /// Query owned by this collection page; never shared with song lists or another tab.
    @State private var search = ""
    /// Localized prompt describing the collection that this page actually searches.
    private var searchPrompt: String {
        switch kind {
        case .artists: L10n.text("Search Artists")
        case .albums: L10n.text("Search Albums")
        case .genres: L10n.text("Search Genres")
        case .playlists: L10n.text("Search Playlists")
        }
    }
    /// Artist names matching this page's query, independent of any song-page search.
    private var artists: [String] { model.artists.filter { LibrarySearch.matches(search, in: [$0]) } }
    /// Album representatives matching album title or artist information on this page.
    private var albums: [Track] { model.albums.filter { LibrarySearch.matches(search, in: [$0.displayAlbum, $0.displayArtist, $0.albumArtist]) } }
    /// Genre names matching this page's query, including the localized uncategorized label.
    private var genres: [String] { Array(Set(model.tracks.map(\.genre))).sorted().filter { LibrarySearch.matches(search, in: [$0.isEmpty ? L10n.text("Uncategorized") : $0]) } }
    /// Playlists whose names match this page's query; song metadata is not searched here.
    private var playlists: [Playlist] { model.playlists.filter { LibrarySearch.matches(search, in: [$0.name]) } }
    /// Whether the currently selected collection has any visible results.
    private var isEmpty: Bool {
        switch kind {
        case .artists: artists.isEmpty
        case .albums: albums.isEmpty
        case .genres: genres.isEmpty
        case .playlists: playlists.isEmpty
        }
    }
    /// Renders the selected collection with its own search scope and appropriate empty state.
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
