import SwiftUI

struct HomeView: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @State var model: HomeViewModel
    /// Shared symbol slot scales with Dynamic Type while keeping tile text vertically aligned.
    @ScaledMetric(relativeTo: .title2) private var categoryIconHeight: CGFloat = 28
    /// Renders the unfiltered library overview and the user-configured home sections.
    var body: some View {
        PageScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(model.preferences.homeSections.filter(\.enabled)) { section in
                    sectionView(section.id)
                }
                if model.library.tracks.isEmpty {
                    ContentUnavailableView(
                        L10n.text("Start with your first song"),
                        systemImage: "music.note",
                        description: Text(
                            L10n.text(
                                """
                                Import music from Files, iCloud Drive, or your computer. Originals \
                                stay intact, and your collection stays available offline.
                                """
                            )
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(24).frame(maxWidth: 1_200, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    @ViewBuilder private func sectionView(_ name: String) -> some View {
        switch name {
        case "continue":
            if let track = model.player.playback.track {
                Button {
                    model.player.presentation.showPlayer = true
                } label: {
                    HStack(spacing: 16) {
                        ArtworkView(track: track, vault: model.library.vault, size: 80)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.text("Continue Listening")).font(.caption)
                                .foregroundStyle(.secondary)
                            Text(track.title).font(.headline).lineLimit(1)
                            Text(track.displayArtist).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .padding(16)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
        case "categories":
            EqualTileRow {
                NavigationLink {
                    CollectionGrid(
                        model: CollectionViewModel(
                            library: model.library,
                            player: model.player,
                            kind: .artists
                        )
                    )
                    .navigationTitle(L10n.text("Artists"))
                } label: {
                    category(L10n.text("Artists"), "person.2", model.library.artists.count)
                }
                .accessibilityIdentifier("home.artists")
                NavigationLink {
                    CollectionGrid(
                        model: CollectionViewModel(
                            library: model.library,
                            player: model.player,
                            kind: .albums
                        )
                    )
                    .navigationTitle(L10n.text("Albums"))
                } label: {
                    category(L10n.text("Albums"), "square.stack", model.library.albums.count)
                }
                .accessibilityIdentifier("home.albums")
                NavigationLink {
                    SongListView(
                        model: SongListViewModel(
                            library: model.library,
                            player: model.player,
                            destination: .favorites
                        )
                    )
                    .navigationTitle(L10n.text("Favorites"))
                } label: {
                    category(
                        L10n.text("Favorites"),
                        "heart",
                        model.library.tracks.filter(\.isFavorite).count
                    )
                }
                .accessibilityIdentifier("home.favorites")
            }
            .buttonStyle(.plain)
        case "playlists":
            if !model.library.playlists.isEmpty {
                Text(L10n.text("My Playlists")).font(.title2.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(model.library.playlists.prefix(12)) { playlist in
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
                                VStack(alignment: .leading, spacing: 8) {
                                    ArtworkView(
                                        track: model.library.cover(for: playlist),
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
        case "recent":
            if !model.library.tracks.isEmpty {
                Text(L10n.text("Recently Added")).font(.title2.bold())
                LazyVStack(spacing: 2) {
                    ForEach(model.library.tracks.sorted { $0.addedAt > $1.addedAt }.prefix(12)) {
                        track in
                        TrackRow(model: model.player, track: track) {
                            model.player.playback.play(
                                model.library.tracks.sorted { $0.addedAt > $1.addedAt },
                                startingAt: track.id
                            )
                        }
                    }
                }
            }
        case "statistics":
            NavigationLink {
                ListeningStatsView(model: ListeningStatsViewModel(library: model.library))
            } label: {
                HStack {
                    Label(L10n.text("Listening Statistics"), systemImage: "chart.bar")
                    Spacer()
                    Text(musicTime(model.library.events.reduce(0) { $0 + $1.seconds }))
                        .monospacedDigit()
                }
                .padding(18)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
        default: EmptyView()
        }
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
