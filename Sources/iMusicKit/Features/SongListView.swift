import SwiftUI

private struct SongRowData: Identifiable {
    var id: UUID
    var track: Track
    var title: String { track.title }
    var artist: String { track.displayArtist }
    var album: String { track.displayAlbum }
    var duration: Double { track.duration }
}

struct SongListView: View {
    @Bindable var model: AppModel
    let destination: LibraryDestination
    @State private var search = ""
    @State private var selected: Set<UUID> = []
    @State private var sortOrder: [KeyPathComparator<SongRowData>] = []
    @State private var rename = false
    @State private var newName = ""
    @State private var addingTracks = false
    @State private var editingPlaylist = false
    @State private var pendingPermanentDeletion: [Track] = []
    private var deletedPlaylists: [Playlist] { model.deletedPlaylists.filter { LibrarySearch.matches(search, in: [$0.name]) } }
    private var playlist: Playlist? { if case .playlist(let id) = destination { return model.playlists.first { $0.id == id } }; return nil }
    private var rows: [SongRowData] {
        if let playlist {
            return playlist.entries.compactMap { entry in
                guard let track = model.tracks.first(where: { $0.id == entry.trackID }), LibrarySearch.matches(search, track: track) else { return nil }
                return SongRowData(id: entry.id, track: track)
            }
        }
        return model.songs(for: destination).filter { LibrarySearch.matches(search, track: $0) }.map { SongRowData(id: $0.id, track: $0) }
    }
    var body: some View {
        VStack(spacing: 0) {
            if destination == .songs {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        NavigationLink { CollectionGrid(model: model, kind: .artists).navigationTitle(L10n.text("Artists")) } label: { Label(L10n.text("Artists"), systemImage: "person.2") }
                        NavigationLink { CollectionGrid(model: model, kind: .albums).navigationTitle(L10n.text("Albums")) } label: { Label(L10n.text("Albums"), systemImage: "square.stack") }
                        NavigationLink { CollectionGrid(model: model, kind: .genres).navigationTitle(L10n.text("Genres")) } label: { Label(L10n.text("Genres"), systemImage: "guitars") }
                        NavigationLink { SongListView(model: model, destination: .favorites).navigationTitle(L10n.text("Favorites")) } label: { Label(L10n.text("Favorites"), systemImage: "heart") }
                    }.buttonStyle(.bordered).padding(.horizontal).padding(.top, 12)
                }
            }
            HStack {
                Text(L10n.text("format.song_count.duration", rows.count, String(describing: musicTime(rows.reduce(0) { $0 + $1.duration })))).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if destination != .trash {
                    Button { play(row: rows.first) } label: { Label(L10n.text("Play"), systemImage: "play.fill") }.disabled(rows.isEmpty)
                    Button { model.playback.play(rows.map(\.track), shuffled: true) } label: { Image(systemName: "shuffle").accessibilityLabel(L10n.text("Shuffle")) }.disabled(rows.isEmpty)
                }
            }.padding(16)
            #if os(macOS)
            if destination == .trash, !deletedPlaylists.isEmpty {
                VStack(alignment: .leading) {
                    Text(L10n.text("Deleted Playlists")).font(.headline)
                    ForEach(deletedPlaylists) { playlist in HStack { Text(playlist.name); Spacer(); Button(L10n.text("Restore Playlist")) { model.restore(playlist) } } }
                }.padding(16)
            }
            #endif
            if rows.isEmpty && (destination != .trash || deletedPlaylists.isEmpty) && !LibrarySearch.isEmpty(search) {
                ContentUnavailableView.search(text: search)
            } else if rows.isEmpty && (destination != .trash || deletedPlaylists.isEmpty) {
                ContentUnavailableView(destination == .trash ? L10n.text("Trash Is Empty") : L10n.text("No Music Here Yet"), systemImage: destination == .trash ? "trash" : destination == .favorites ? "heart" : "music.note", description: Text(destination == .trash ? L10n.text("Songs moved to Trash appear here until you restore or permanently delete them.") : L10n.text("Import music to start organizing your library.")))
            }
            else {
                #if os(macOS)
                Table(rows.sorted(using: sortOrder), selection: $selected, sortOrder: $sortOrder) {
                    TableColumn(L10n.text("Title"), value: \.title) { row in
                        HStack(spacing: 10) { ArtworkView(track: row.track, vault: model.vault, size: 32); Text(row.title).lineLimit(1); if row.track.isFavorite { Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption) }; if !model.vault.contains(row.track) { Image(systemName: "icloud.and.arrow.down").foregroundStyle(.secondary) } }
                            .draggable(row.track.id.uuidString)
                    }.width(min: 160, ideal: 300)
                    TableColumn(L10n.text("Artists"), value: \.artist).width(min: 80, ideal: 150)
                    TableColumn(L10n.text("Albums"), value: \.album).width(min: 80, ideal: 170)
                    TableColumn(L10n.text("Duration"), value: \.duration) { row in Text(musicTime(row.duration)).monospacedDigit().foregroundStyle(.secondary) }.width(60)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let row = rows.first(where: { ids.contains($0.id) }) {
                        if destination == .trash {
                            Button(L10n.text("Restore")) { ids.forEach { id in if let track = rows.first(where: { $0.id == id })?.track { model.restore(track) } } }
                            Button(L10n.text("Delete Permanently"), role: .destructive) { pendingPermanentDeletion = rows.filter { ids.contains($0.id) }.map(\.track) }
                                .disabled(model.isWorking || model.importing)
                        }
                        else {
                            TrackActions(model: model, tracks: rows.filter { ids.contains($0.id) }.map(\.track))
                            if let playlist { Button(L10n.text("Remove from Playlist"), role: .destructive) { var value = playlist; value.entries.removeAll { ids.contains($0.id) }; model.save(value) } }
                            Button(L10n.text("Play Selected Songs")) { play(row: row) }
                        }
                    }
                } primaryAction: { ids in if let row = rows.first(where: { ids.contains($0.id) }), destination != .trash { play(row: row) } }
                #else
                List {
                    if destination == .trash {
                        ForEach(rows) { row in
                            HStack(spacing: 12) {
                                ArtworkView(track: row.track, vault: model.vault, size: 46)
                                VStack(alignment: .leading, spacing: 4) { Text(row.title).lineLimit(2); Text(row.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                Spacer(minLength: 0)
                                Text(musicTime(row.duration)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { pendingPermanentDeletion = [row.track] } label: { Label(L10n.text("Delete"), systemImage: "trash") }
                                        .accessibilityLabel(L10n.text("Delete Permanently"))
                                        .disabled(model.isWorking || model.importing)
                                    Button { model.restore(row.track) } label: { Label(L10n.text("Restore"), systemImage: "arrow.uturn.backward") }.tint(.blue)
                                        .disabled(model.isWorking || model.importing)
                                }
                        }
                        if !deletedPlaylists.isEmpty {
                            Section(L10n.text("Deleted Playlists")) {
                                ForEach(deletedPlaylists) { playlist in
                                    Text(playlist.name)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button { model.restore(playlist) } label: { Label(L10n.text("Restore Playlist"), systemImage: "arrow.uturn.backward") }.tint(.blue)
                                        }
                                }
                            }
                        }
                    } else {
                        ForEach(rows) { row in
                            TrackRow(model: model, track: row.track) { play(row: row) }
                                .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                                .swipeActions(edge: .trailing) {
                                    if let playlist { Button(L10n.text("Remove from Playlist"), role: .destructive) { var value = playlist; value.entries.removeAll { $0.id == row.id }; model.save(value) } }
                                }
                        }.onMove { offsets, target in
                            guard var value = playlist, LibrarySearch.isEmpty(search) else { return }
                            value.entries.move(fromOffsets: offsets, toOffset: target); model.save(value)
                        }
                    }
                }.listStyle(.plain)
                #endif
            }
        }
        .librarySearch(text: $search, prompt: destination == .trash ? L10n.text("Search Trash") : L10n.text("Search Songs"))
        .toolbar {
            if let playlist {
                ToolbarItem {
                    Menu {
                        Button(L10n.text("Add Songs")) { addingTracks = true }
                        Button(L10n.text("Edit Playlist and Artwork")) { editingPlaylist = true }
                        Button(L10n.text("Rename")) { newName = playlist.name; rename = true }
                        Button(L10n.text("Sort by Song Title")) { var value = playlist; value.entries.sort { a, b in (model.tracks.first { $0.id == a.trackID }?.title ?? "").localizedStandardCompare(model.tracks.first { $0.id == b.trackID }?.title ?? "") == .orderedAscending }; model.save(value) }
                        Button(L10n.text("Reverse Order")) { var value = playlist; value.entries.reverse(); model.save(value) }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                #if os(iOS)
                ToolbarItem { EditButton() }
                #endif
            }
        }
        .alert(L10n.text("Rename Playlist"), isPresented: $rename) { TextField(L10n.text("Name"), text: $newName); Button(L10n.text("Save")) { if var value = playlist { value.name = newName; model.save(value) } }; Button(L10n.text("Cancel"), role: .cancel) {} }
        .alert(L10n.text("Permanently Delete Music?"), isPresented: Binding(get: { !pendingPermanentDeletion.isEmpty }, set: { if !$0 { pendingPermanentDeletion = [] } }), presenting: pendingPermanentDeletion) { tracks in
            Button(L10n.text("Delete Permanently"), role: .destructive) { model.permanentlyDelete(tracks) }
            Button(L10n.text("Cancel"), role: .cancel) { pendingPermanentDeletion = [] }
        } message: { tracks in
            if tracks.count == 1, let track = tracks.first { Text(L10n.text("format.trash.delete_song", track.title)) }
            else { Text(L10n.text("format.trash.delete_count", tracks.count)) }
        }
        .sheet(isPresented: $addingTracks) { if let playlist { PlaylistSongPicker(model: model, playlist: playlist) } }
        .sheet(isPresented: $editingPlaylist) { if let playlist { PlaylistEditor(model: model, playlist: playlist) } }
    }
    private func play(row: SongRowData?) {
        guard let row else { return }
        let ordered = rows.sorted(using: sortOrder)
        model.playback.playEntries(ordered.map { QueueEntry(id: $0.id, trackID: $0.track.id) }, startingAt: row.id)
    }
}

struct TrackRow: View {
    @Bindable var model: AppModel
    let track: Track
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    ArtworkView(track: track, vault: model.vault, size: 46)
                    VStack(alignment: .leading, spacing: 4) { Text(track.title).font(.body.weight(.medium)).lineLimit(1); Text(track.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Spacer(minLength: 0)
                    if model.playback.track?.id == track.id { Image(systemName: model.playback.isPlaying ? "waveform" : "pause.fill").foregroundStyle(Color.accentColor) }
                    Text(musicTime(track.duration)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { model.toggleFavorite(track) } label: { Image(systemName: track.isFavorite ? "heart.fill" : "heart").foregroundStyle(track.isFavorite ? Color.pink : Color.secondary) }.buttonStyle(.plain).accessibilityLabel(track.isFavorite ? L10n.text("Remove from Favorites") : L10n.text("Favorites"))
            Menu { TrackActions(model: model, tracks: [track]) } label: { Image(systemName: "ellipsis").frame(width: 28, height: 32).contentShape(Rectangle()) }.menuStyle(.borderlessButton).fixedSize()
        }.padding(.vertical, 9).padding(.horizontal, 6)
            .contextMenu { TrackActions(model: model, tracks: [track]) }
            .draggable(track.id.uuidString)
    }
}

struct TrackActions: View {
    @Bindable var model: AppModel
    let tracks: [Track]
    var body: some View {
        Button(L10n.text("Play Next"), systemImage: "text.line.first.and.arrowtriangle.forward") { for track in tracks.reversed() { model.playback.enqueue(track, next: true) } }
        Button(L10n.text("Add to Queue"), systemImage: "text.badge.plus") { for track in tracks { model.playback.enqueue(track) } }
        Menu(L10n.text("Add to Playlist"), systemImage: "music.note.list") {
            ForEach(model.playlists) { playlist in Button(playlist.name) { model.add(tracks, to: playlist) } }
            if model.playlists.isEmpty { Text(L10n.text("Create a playlist first")) }
        }
        if let first = tracks.first {
            Button(first.isFavorite ? L10n.text("Remove from Favorites") : L10n.text("Favorites"), systemImage: "heart") { for track in tracks { var value = track; value.isFavorite = !first.isFavorite; model.save(value) } }
            if tracks.count == 1 {
                Button(L10n.text("Edit Tags and Artwork"), systemImage: "pencil") { model.editingTrack = first }
                if !model.vault.contains(first) { Button(L10n.text("Download from iCloud"), systemImage: "icloud.and.arrow.down") { Task { await model.cloud.download(first) } } }
            }
            else { Button(L10n.text("Edit Tags in Bulk"), systemImage: "pencil") { model.batchEditingTracks = tracks } }
        }
        Divider()
        Button(L10n.text("Move to Trash"), systemImage: "trash", role: .destructive) { model.trash(tracks) }
    }
}
