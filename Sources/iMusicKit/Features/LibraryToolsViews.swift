import SwiftUI
import Charts
import ImageIO
import UniformTypeIdentifiers

struct BatchTrackEditor: View {
    /// Shared observable app model providing library snapshots and the actions used by this view.
    let model: AppModel
    /// Selected songs whose metadata will be updated together when Save is chosen.
    let tracks: [Track]
    /// SwiftUI presentation action used to close this sheet or editor.
    @Environment(\.dismiss) private var dismiss
    /// Replacement performer credit, applied only when its edit toggle is enabled.
    @State private var artist = ""
    /// Replacement album title, applied only when its edit toggle is enabled.
    @State private var album = ""
    /// Replacement album artist credit, applied only when its edit toggle is enabled.
    @State private var albumArtist = ""
    /// Replacement genre tag, applied only when its edit toggle is enabled.
    @State private var genre = ""
    /// Whether to replace the artist field on every selected song.
    @State private var editArtist = false
    /// Whether to replace the album field on every selected song.
    @State private var editAlbum = false
    /// Whether to replace the album-artist field on every selected song.
    @State private var editAlbumArtist = false
    /// Whether to replace the genre field on every selected song.
    @State private var editGenre = false
    /// Renders opt-in metadata replacements so unchecked fields retain their existing values.
    var body: some View {
        NavigationStack {
            Form {
                Text(L10n.text("format.batch.instructions", tracks.count)).font(.caption).foregroundStyle(.secondary)
                Toggle(L10n.text("Change Artist"), isOn: $editArtist); if editArtist { TextField(L10n.text("Artist"), text: $artist) }
                Toggle(L10n.text("Change Album"), isOn: $editAlbum); if editAlbum { TextField(L10n.text("Album"), text: $album) }
                Toggle(L10n.text("Change Album Artist"), isOn: $editAlbumArtist); if editAlbumArtist { TextField(L10n.text("Album Artist"), text: $albumArtist) }
                Toggle(L10n.text("Change Genre"), isOn: $editGenre); if editGenre { TextField(L10n.text("Genre"), text: $genre) }
            }.formStyle(.grouped).navigationTitle(L10n.text("Bulk Edit"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Save")) {
                        for var track in tracks {
                            if editArtist { track.artist = artist }; if editAlbum { track.album = album }
                            if editAlbumArtist { track.albumArtist = albumArtist }; if editGenre { track.genre = genre }
                            model.save(track)
                        }; dismiss()
                    }.disabled(!editArtist && !editAlbum && !editAlbumArtist && !editGenre) }
                }
        }.frame(idealWidth: 480, idealHeight: 450)
    }
}

struct PlaylistSongPicker: View {
    /// Shared observable app model providing library snapshots and the actions used by this view.
    let model: AppModel
    /// Playlist receiving the selected song occurrences after confirmation.
    let playlist: Playlist
    /// Selected song identities to append to the destination playlist.
    @State private var selected: Set<UUID> = []
    /// Query local to the song picker, independent of the underlying playlist search.
    @State private var search = ""
    /// SwiftUI presentation action used to close this sheet or editor.
    @Environment(\.dismiss) private var dismiss
    /// Renders searchable songs and selection controls for appending entries to one playlist.
    var body: some View {
        NavigationStack {
            List(model.tracks.filter { LibrarySearch.matches(search, track: $0) }) { track in
                Button { if selected.contains(track.id) { selected.remove(track.id) } else { selected.insert(track.id) } } label: {
                    HStack { Image(systemName: selected.contains(track.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint); VStack(alignment: .leading) { Text(track.title).lineLimit(1); Text(track.displayArtist).font(.caption).foregroundStyle(.secondary) }; Spacer() }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }.searchable(text: $search, prompt: L10n.text("Search Songs")).navigationTitle(L10n.text("format.playlist.add_to", String(describing: playlist.name)))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(L10n.text("format.playlist.add_count", selected.count)) { model.add(model.tracks.filter { selected.contains($0.id) }, to: playlist); dismiss() }.disabled(selected.isEmpty) } }
        }.frame(idealWidth: 500, idealHeight: 600)
    }
}

struct PlaylistEditor: View {
    /// Shared observable app model providing library snapshots and the actions used by this view.
    let model: AppModel
    /// Editable playlist copy whose name and cover are committed when Save is chosen.
    @State var playlist: Playlist
    /// Whether the custom playlist-cover image importer is presented.
    @State private var chooseCover = false
    /// Most recent custom-cover validation or file-access error shown in this editor.
    @State private var error: String?
    /// SwiftUI presentation action used to close this sheet or editor.
    @Environment(\.dismiss) private var dismiss
    /// Renders playlist name and cover editing before applying the saved draft.
    var body: some View {
        NavigationStack {
            Form {
                Section { ArtworkView(track: model.cover(for: playlist), vault: model.vault, size: 140); Button(L10n.text("Choose Artwork…")) { chooseCover = true }; Button(L10n.text("Use Automatic Artwork")) { playlist.artworkName = nil } }
                TextField(L10n.text("Playlist Name"), text: $playlist.name)
                if let error { Text(error).foregroundStyle(.orange) }
            }.formStyle(.grouped).navigationTitle(L10n.text("Edit Playlist"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Save")) { model.save(playlist); dismiss() }.disabled(playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
        }.frame(idealWidth: 440, idealHeight: 400)
            .fileImporter(isPresented: $chooseCover, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get(), access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= 20_000_000 else { throw MusicError.unavailable(L10n.text("Choose an image smaller than 20 MB.")) }
                    let data = try Data(contentsOf: url)
                    guard CGImageSourceCreateWithData(data as CFData, nil) != nil else { throw MusicError.unavailable(L10n.text("Unable to read this image.")) }
                    let name = UUID().uuidString + ".image"; try data.write(to: model.vault.artwork.appendingPathComponent(name), options: .atomic); playlist.artworkName = name
                } catch { self.error = error.localizedDescription }
            }
    }
}

struct DuplicatesView: View {
    /// Shared observable app model providing library snapshots and the actions used by this view.
    let model: AppModel
    /// Renders groups of identical audio content and lets the user choose which record to keep.
    var body: some View {
        let groups = Dictionary(grouping: model.tracks, by: \.assetHash).values.filter { $0.count > 1 }
        List {
            Text(L10n.text("Imports already remove duplicates by file contents. These copies remain after merging a backup or cloud library. Merging preserves playlist references and favorites, and moves other copies to Trash.")).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(groups.enumerated()), id: \.offset) { _, tracks in
                Section(tracks.first?.title ?? L10n.text("Duplicate Files")) {
                    ForEach(tracks) { track in
                        HStack { VStack(alignment: .leading) { Text(track.title); Text(track.originalFilename).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button(L10n.text("Keep This Copy and Merge")) { model.mergeDuplicates(keeper: track, duplicates: tracks) } }
                    }
                }
            }
            if groups.isEmpty { ContentUnavailableView(L10n.text("No Identical Duplicate Songs"), systemImage: "checkmark.circle", description: Text(L10n.text("Similar titles are never automatically treated as duplicate files."))) }
        }.navigationTitle(L10n.text("Find Duplicate Songs"))
    }
}

struct ListeningStatsView: View {
    /// Shared observable app model providing library snapshots and the actions used by this view.
    let model: AppModel
    /// Number of days included in the report; zero includes the entire listening history.
    @State private var period = 30
    /// Listening segments within the selected reporting period.
    private var events: [ListenEvent] { model.events.filter { period == 0 || $0.startedAt > Calendar.current.date(byAdding: .day, value: -period, to: Date())! } }
    /// Listening seconds aggregated by local calendar day for the statistics chart.
    private var daily: [(date: Date, seconds: Double)] {
        Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.startedAt) }.map { (date: $0.key, seconds: $0.value.reduce(0) { $0 + $1.seconds }) }.sorted { $0.date < $1.date }
    }
    /// Renders period-scoped listening totals, daily activity, and the most played songs.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker(L10n.text("Time Range"), selection: $period) { Text(L10n.text("Last 7 Days")).tag(7); Text(L10n.text("Last 30 Days")).tag(30); Text(L10n.text("All Time")).tag(0) }.pickerStyle(.segmented)
                Text(musicTime(events.reduce(0) { $0 + $1.seconds })).font(.system(.largeTitle, design: .rounded).bold())
                Text(L10n.text("Actual listening time · Pauses and seeks are excluded")).font(.caption).foregroundStyle(.secondary)
                if events.isEmpty { ContentUnavailableView(L10n.text("Listen to a song you love"), systemImage: "chart.bar", description: Text(L10n.text("Your listening history appears here, without an internet connection."))) }
                else {
                    Chart(daily, id: \.date) { day in BarMark(x: .value(L10n.text("Date"), day.date, unit: .day), y: .value(L10n.text("Minutes"), day.seconds / 60)).foregroundStyle(Color.accentColor) }.frame(height: 180)
                    Text(L10n.text("Most Played Songs")).font(.title2.bold())
                    let totals = Dictionary(grouping: events, by: \.trackID).mapValues { $0.reduce(0) { $0 + $1.seconds } }.sorted { $0.value > $1.value }
                    ForEach(Array(totals.prefix(10).enumerated()), id: \.element.key) { index, item in
                        if let track = model.tracks.first(where: { $0.id == item.key }) { HStack { Text("\(index + 1)").foregroundStyle(.secondary).frame(width: 24); Text(track.title).lineLimit(1); Spacer(); Text(musicTime(item.value)).monospacedDigit().foregroundStyle(.secondary) } }
                    }
                    Text(L10n.text("Most Played Artists")).font(.title2.bold())
                    let artistTotals = Dictionary(grouping: events) { event in model.tracks.first(where: { $0.id == event.trackID })?.displayArtist ?? L10n.text("Unknown Artist") }.mapValues { $0.reduce(0) { $0 + $1.seconds } }.sorted { $0.value > $1.value }
                    ForEach(Array(artistTotals.prefix(10).enumerated()), id: \.offset) { _, item in HStack { Text(item.key); Spacer(); Text(musicTime(item.value)).monospacedDigit().foregroundStyle(.secondary) } }
                }
            }.padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.navigationTitle(L10n.text("Listening Statistics")).task { await model.refresh() }
    }
}
