import SwiftUI

struct SongListView: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @State var model: SongListViewModel
    /// Renders the scoped song table or native list with search, playback, playlist, and Trash
    /// actions.
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if model.destination == .songs {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
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
                            Label(L10n.text("Artists"), systemImage: "person.2")
                        }
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
                            Label(L10n.text("Albums"), systemImage: "square.stack")
                        }
                        NavigationLink {
                            CollectionGrid(
                                model: CollectionViewModel(
                                    library: model.library,
                                    player: model.player,
                                    kind: .genres
                                )
                            )
                            .navigationTitle(L10n.text("Genres"))
                        } label: {
                            Label(L10n.text("Genres"), systemImage: "guitars")
                        }
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
                            Label(L10n.text("Favorites"), systemImage: "heart")
                        }
                    }
                    .buttonStyle(.bordered).padding(.horizontal).padding(.top, 12)
                }
            }
            HStack {
                Text(
                    L10n.text(
                        "format.song_count.duration",
                        model.rows.count,
                        String(describing: musicTime(model.rows.reduce(0) { $0 + $1.duration }))
                    )
                )
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("library.songSummary")
                Spacer()
                if model.destination != .trash {
                    Button {
                        model.play(row: model.rows.first)
                    } label: {
                        Label(L10n.text("Play"), systemImage: "play.fill")
                    }
                    .disabled(model.rows.isEmpty)
                    Button {
                        model.player.playback.play(model.rows.map(\.track), shuffled: true)
                    } label: {
                        Image(systemName: "shuffle").accessibilityLabel(L10n.text("Shuffle"))
                    }
                    .disabled(model.rows.isEmpty)
                }
            }
            .padding(16)
            #if os(macOS)
            if model.destination == .trash, !model.deletedPlaylists.isEmpty {
                VStack(alignment: .leading) {
                    Text(L10n.text("Deleted Playlists")).font(.headline)
                    ForEach(model.deletedPlaylists) { playlist in
                        HStack {
                            Text(playlist.name)
                            Spacer()
                            Button(L10n.text("Restore Playlist")) {
                                model.library.restore(playlist)
                            }
                        }
                    }
                }
                .padding(16)
            }
            #endif
            if model.rows.isEmpty && (model.destination != .trash || model.deletedPlaylists.isEmpty)
                && !LibrarySearch.isEmpty(model.search)
            {
                ContentUnavailableView.search(text: model.search)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.rows.isEmpty
                && (model.destination != .trash || model.deletedPlaylists.isEmpty)
            {
                ContentUnavailableView(
                    model.destination == .trash
                        ? L10n.text("Trash Is Empty") : L10n.text("No Music Here Yet"),
                    systemImage: model.destination == .trash
                        ? "trash" : model.destination == .favorites ? "heart" : "music.note",
                    description: Text(
                        model.destination == .trash
                            ? L10n.text(
                                """
                                Songs moved to Trash appear here until you restore or permanently \
                                delete them.
                                """
                            )
                            : L10n.text("Import music to start organizing your library.")
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(macOS)
                Table(
                    model.rows.sorted(using: model.sortOrder),
                    selection: $model.selected,
                    sortOrder: $model.sortOrder
                ) {
                    TableColumn(L10n.text("Title"), value: \.title) { row in
                        HStack(spacing: 10) {
                            ArtworkView(track: row.track, vault: model.library.vault, size: 32)
                            Text(row.title).lineLimit(1)
                                .accessibilityIdentifier(
                                    "track.title.\(row.track.originalFilename)"
                                )
                            if row.track.isFavorite {
                                Image(systemName: "heart.fill").foregroundStyle(.pink)
                                    .font(.caption)
                            }
                            if !model.library.availableTrackIDs.contains(row.track.id) {
                                Image(
                                    systemName: row.track.isLinked
                                        ? "folder.badge.questionmark" : "icloud.and.arrow.down"
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                        .draggable(row.track.id.uuidString)
                    }
                    .width(min: 160, ideal: 300)
                    TableColumn(L10n.text("Artists"), value: \.artist).width(min: 80, ideal: 150)
                    TableColumn(L10n.text("Albums"), value: \.album).width(min: 80, ideal: 170)
                    TableColumn(L10n.text("Duration"), value: \.duration) { row in
                        Text(musicTime(row.duration)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(60)
                }
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if let row = model.rows.first(where: { ids.contains($0.id) }) {
                        if model.destination == .trash {
                            Button(L10n.text("Restore")) {
                                for id in ids {
                                    if let track = model.rows.first(where: { $0.id == id })?.track {
                                        model.library.restore(track)
                                    }
                                }
                            }
                            .accessibilityIdentifier("trash.restore")
                            Button(L10n.text("Delete Permanently"), role: .destructive) {
                                model.pendingPermanentDeletion = model.rows
                                    .filter { ids.contains($0.id) }
                                    .map(
                                        \.track
                                    )
                            }
                            .accessibilityIdentifier("trash.delete")
                            .disabled(
                                model.library.activity.isWorking || model.library.activity.importing
                            )
                        } else {
                            TrackActions(
                                model: model.player,
                                tracks: model.rows.filter { ids.contains($0.id) }.map(\.track)
                            )
                            if let playlist = model.playlist {
                                Button(L10n.text("Remove from Playlist"), role: .destructive) {
                                    var value = playlist
                                    value.entries.removeAll { ids.contains($0.id) }
                                    model.library.save(value)
                                }
                            }
                            Button(L10n.text("Play Selected Songs")) { model.play(row: row) }
                        }
                    }
                } primaryAction: { ids in
                    if let row = model.rows.first(where: { ids.contains($0.id) }),
                        model.destination != .trash
                    {
                        model.play(row: row)
                    }
                }
                #else
                List {
                    if model.destination == .trash {
                        ForEach(model.rows) { row in
                            HStack(spacing: 12) {
                                ArtworkView(track: row.track, vault: model.library.vault, size: 46)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.title).lineLimit(2)
                                    Text(row.artist).font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Text(musicTime(row.duration)).font(.caption).monospacedDigit()
                                    .foregroundStyle(
                                        .secondary
                                    )
                            }
                            .padding(.vertical, 6)
                            .accessibilityIdentifier("trash.track.\(row.track.originalFilename)")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    model.pendingPermanentDeletion = [row.track]
                                } label: {
                                    Label(L10n.text("Delete"), systemImage: "trash")
                                }
                                .accessibilityLabel(L10n.text("Delete Permanently"))
                                .disabled(
                                    model.library.activity.isWorking
                                        || model.library.activity.importing
                                )
                                Button {
                                    model.library.restore(row.track)
                                } label: {
                                    Label(L10n.text("Restore"), systemImage: "arrow.uturn.backward")
                                }
                                .tint(.blue)
                                .disabled(
                                    model.library.activity.isWorking
                                        || model.library.activity.importing
                                )
                            }
                        }
                        if !model.deletedPlaylists.isEmpty {
                            Section(L10n.text("Deleted Playlists")) {
                                ForEach(model.deletedPlaylists) { playlist in
                                    Text(playlist.name)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button {
                                                model.library.restore(playlist)
                                            } label: {
                                                Label(
                                                    L10n.text("Restore Playlist"),
                                                    systemImage: "arrow.uturn.backward"
                                                )
                                            }
                                            .tint(.blue)
                                        }
                                }
                            }
                        }
                    } else {
                        ForEach(model.rows) { row in
                            TrackRow(model: model.player, track: row.track) { model.play(row: row) }
                                .listRowInsets(
                                    EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
                                )
                                .swipeActions(edge: .trailing) {
                                    if let playlist = model.playlist {
                                        Button(
                                            L10n.text("Remove from Playlist"),
                                            role: .destructive
                                        ) {
                                            var value = playlist
                                            value.entries.removeAll { $0.id == row.id }
                                            model.library.save(value)
                                        }
                                    }
                                }
                        }
                        .onMove { offsets, target in
                            guard var value = model.playlist, LibrarySearch.isEmpty(model.search)
                            else {
                                return
                            }
                            value.entries.move(fromOffsets: offsets, toOffset: target)
                            model.library.save(value)
                        }
                    }
                }
                .listStyle(.plain)
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .librarySearch(
            text: $model.search,
            prompt: model.destination == .trash
                ? L10n.text("Search Trash") : L10n.text("Search Songs")
        )
        .toolbar {
            if let playlist = model.playlist {
                ToolbarItem {
                    Menu {
                        Button(L10n.text("Add Songs")) { model.addingTracks = true }
                        Button(L10n.text("Edit Playlist and Artwork")) {
                            model.editingPlaylist = true
                        }
                        Button(L10n.text("Rename")) {
                            model.newName = playlist.name
                            model.rename = true
                        }
                        Button(L10n.text("Sort by Song Title")) {
                            var value = playlist
                            value.entries.sort { a, b in
                                (model.library.tracks.first { $0.id == a.trackID }?.title ?? "")
                                    .localizedStandardCompare(
                                        model.library.tracks.first { $0.id == b.trackID }?.title
                                            ?? ""
                                    )
                                    == .orderedAscending
                            }
                            model.library.save(value)
                        }
                        Button(L10n.text("Reverse Order")) {
                            var value = playlist
                            value.entries.reverse()
                            model.library.save(value)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                #if os(iOS)
                ToolbarItem { EditButton() }
                #endif
            }
        }
        .alert(L10n.text("Rename Playlist"), isPresented: $model.rename) {
            TextField(L10n.text("Name"), text: $model.newName)
            Button(L10n.text("Save")) {
                if var value = model.playlist {
                    value.name = model.newName
                    model.library.save(value)
                }
            }
            Button(L10n.text("Cancel"), role: .cancel) {}
        }
        .alert(
            L10n.text("Permanently Delete Music?"),
            isPresented: Binding(
                get: { !model.pendingPermanentDeletion.isEmpty },
                set: { if !$0 { model.pendingPermanentDeletion = [] } }
            ),
            presenting: model.pendingPermanentDeletion
        ) { tracks in
            Button(L10n.text("Delete Permanently"), role: .destructive) {
                model.library.permanentlyDelete(tracks)
            }
            Button(L10n.text("Cancel"), role: .cancel) { model.pendingPermanentDeletion = [] }
        } message: { tracks in
            if tracks.allSatisfy(\.isLinked) {
                Text(
                    L10n.text(
                        """
                        Only library entries and derived artwork will be deleted. Original \
                        files in linked folders will remain untouched.
                        """
                    )
                )
            } else if tracks.count == 1, let track = tracks.first {
                Text(L10n.text("format.trash.delete_song", track.title))
            } else {
                Text(L10n.text("format.trash.delete_count", tracks.count))
            }
        }
        .sheet(isPresented: $model.addingTracks) {
            if let playlist = model.playlist {
                PlaylistSongPicker(
                    model: PlaylistSongPickerViewModel(library: model.library, playlist: playlist)
                )
            }
        }
        .sheet(isPresented: $model.editingPlaylist) {
            if let playlist = model.playlist {
                PlaylistEditor(
                    model: PlaylistEditorViewModel(library: model.library, playlist: playlist)
                )
            }
        }
    }

}
