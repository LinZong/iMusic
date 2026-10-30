import SwiftUI
import UniformTypeIdentifiers
import ImageIO

public struct RootView: View {
    @Bindable var model: AppModel
    @State private var selection: LibraryDestination? = .home
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    public init(model: AppModel) { self.model = model }
    public var body: some View {
        content
            .preferredColorScheme(model.appearance == "light" ? .light : model.appearance == "dark" ? .dark : nil)
            .fontDesign(model.serifFont ? .serif : .default)
            .task { await model.launch() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.playback.persist(); Task { await model.wifi.stop() } }
                else if phase == .active { Task { await model.foreground() } }
            }
            .fileImporter(isPresented: $model.filePickerPresented, allowedContentTypes: pickerTypes, allowsMultipleSelection: model.fileImportPurpose == .audio) { result in
                switch result {
                case .success(let urls):
                    switch model.fileImportPurpose {
                    case .audio: model.importURLs(urls)
                    case .folder: if let url = urls.first { model.addFolder(url) }
                    case .backup: if let url = urls.first { model.restoreBackup(url) }
                    }
                case .failure(let error): if (error as NSError).code != NSUserCancelledError { model.message = error.localizedDescription }
                }
            }
            .sheet(isPresented: $model.showPlayer) { NowPlayingView(model: model) }
            .sheet(isPresented: Binding(get: { model.showQueue && !model.showPlayer }, set: { model.showQueue = $0 })) { QueueView(model: model) }
            .sheet(isPresented: $model.showWiFi, onDismiss: { Task { await model.wifi.stop() } }) { WiFiView(model: model) }
            .sheet(item: Binding(get: { model.showPlayer ? nil : model.editingTrack }, set: { model.editingTrack = $0 })) { TrackEditor(model: model, original: $0) }
            .sheet(isPresented: Binding(get: { model.batchEditingTracks != nil }, set: { if !$0 { model.batchEditingTracks = nil } })) { if let tracks = model.batchEditingTracks { BatchTrackEditor(model: model, tracks: tracks) } }
            .sheet(isPresented: Binding(get: { model.importReport != nil }, set: { if !$0 { model.importReport = nil } })) { ImportReportView(model: model) }
            .sheet(isPresented: Binding(get: { model.exportedBackup != nil }, set: { if !$0 { model.exportedBackup = nil } })) {
                if let url = model.exportedBackup { BackupExportView(url: url) }
            }
            .sheet(isPresented: Binding(get: { model.diagnosticsURL != nil }, set: { if !$0 { model.diagnosticsURL = nil } })) {
                if let url = model.diagnosticsURL { BackupExportView(url: url, title: L10n.text("Diagnostics Ready"), detail: L10n.text("Includes only the system version, counts, and integrity results. Music names, paths, and account details are excluded.")) }
            }
            .alert("iMusic", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) { Button(L10n.text("OK"), role: .cancel) { model.message = nil } } message: { Text(model.message ?? "") }
            .overlay { if model.isWorking { ProgressView(L10n.text("Processing library…")).padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) } }
    }
    @ViewBuilder private var content: some View {
        #if os(iOS)
        if sizeClass == .compact {
            TabView {
                tab(.home); tab(.songs); tab(.playlists); tab(.settings)
            }
        } else { splitView }
        #else
        splitView.frame(minWidth: 680, minHeight: 480)
        #endif
    }
    #if os(iOS)
    private func tab(_ destination: LibraryDestination) -> some View {
        NavigationStack { DestinationView(model: model, destination: destination).safeAreaInset(edge: .bottom, spacing: 0) { footer } }
            .tabItem { Label(destination.title, systemImage: destination.symbol) }
    }
    #endif
    private var splitView: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("iMusic") {
                    ForEach([LibraryDestination.home, .songs, .artists, .albums, .genres, .favorites, .playlists], id: \.self) { destination in
                        NavigationLink(value: destination) { Label(destination.title, systemImage: destination.symbol) }
                    }
                }
                if !model.playlists.isEmpty {
                    Section(L10n.text("My Playlists")) {
                        ForEach(model.playlists) { playlist in
                            NavigationLink(value: LibraryDestination.playlist(playlist.id)) { Label(playlist.name, systemImage: "music.note.list") }
                                .dropDestination(for: String.self) { ids, _ in
                                    let tracks = ids.compactMap { value in model.tracks.first { $0.id.uuidString == value } }; model.add(tracks, to: playlist); return !tracks.isEmpty
                                }
                        }
                    }
                }
                Section {
                    NavigationLink(value: LibraryDestination.trash) { Label(L10n.text("Trash"), systemImage: "trash") }
                    NavigationLink(value: LibraryDestination.settings) { Label(L10n.text("Settings"), systemImage: "gearshape") }
                }
            }.navigationTitle("iMusic").navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: { NavigationStack { DestinationView(model: model, destination: selection ?? .home) } }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
    }
    private var footer: some View {
        VStack(spacing: 0) {
            if model.importing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(L10n.text("format.import.progress", model.importProgress.completed, model.importProgress.total)).font(.caption); Spacer(); Button(L10n.text("Cancel")) { model.cancelImport() }.font(.caption) }
                    ProgressView(value: Double(model.importProgress.completed), total: Double(max(1, model.importProgress.total)))
                }.padding(12).background(.regularMaterial)
            }
            if let error = model.playback.error {
                HStack { Image(systemName: "exclamationmark.circle"); Text(error).font(.caption).lineLimit(2); Spacer(); Button { model.playback.clearError() } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                    .padding(10).background(.orange.opacity(0.15))
            }
            if model.playback.track != nil { MiniPlayer(model: model) }
        }
    }
    private var pickerTypes: [UTType] { switch model.fileImportPurpose { case .audio: [.audio, .data]; case .folder: [.folder]; case .backup: [.zip] } }
}

private final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()
    let cache = NSCache<NSString, ImageBox>()
    init() { cache.totalCostLimit = 32 * 1_024 * 1_024 }
    final class ImageBox { let image: CGImage; init(_ image: CGImage) { self.image = image } }
    func image(at url: URL, size: Int) -> CGImage? {
        let key = (url.path + String(size)) as NSString
        if let image = cache.object(forKey: key) { return image.image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0,
            [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: size, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        cache.setObject(ImageBox(image), forKey: key, cost: image.bytesPerRow * image.height); return image
    }
}

struct ArtworkView: View {
    let track: Track?
    let vault: MediaVault
    var size: CGFloat = 48
    @State private var image: CGImage?
    var body: some View {
        ZStack {
            if let image { Image(decorative: image, scale: 1).resizable().scaledToFill() }
            else {
                LinearGradient(colors: [.indigo.opacity(0.55), .purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: size * 0.32, weight: .medium)).foregroundStyle(.white.opacity(0.8))
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: min(24, size * 0.13)))
            .accessibilityHidden(true)
            .task(id: track?.artworkName) {
                image = nil
                guard let url = vault.artworkURL(track?.artworkName) else { return }
                let pixels = Int(min(1_000, size * 2))
                image = await Task.detached { ArtworkCache.shared.image(at: url, size: pixels) }.value
            }
    }
}

struct DestinationView: View {
    @Bindable var model: AppModel
    let destination: LibraryDestination
    @State private var newPlaylist = false
    @State private var playlistName = ""
    var body: some View {
        Group {
            switch destination {
            case .home: HomeView(model: model)
            case .artists: CollectionGrid(model: model, kind: .artists)
            case .albums: CollectionGrid(model: model, kind: .albums)
            case .genres: CollectionGrid(model: model, kind: .genres)
            case .playlists: CollectionGrid(model: model, kind: .playlists)
            case .settings: SettingsView(model: model)
            default: SongListView(model: model, destination: destination)
            }
        }
        .id(destination)
        .navigationTitle(model.title(for: destination))
        .toolbar {
            ToolbarItem {
                Menu {
                    Button(L10n.text("Import Music"), systemImage: "square.and.arrow.down") { model.showImporter = true }
                    Button(L10n.text("Link Folder"), systemImage: "folder.badge.plus") { model.showFolderPicker = true }
                    Button(L10n.text("Wi-Fi Transfer"), systemImage: "wifi") { model.showWiFi = true }
                    Divider()
                    Button(L10n.text("New Playlist"), systemImage: "plus") { playlistName = ""; newPlaylist = true }
                } label: { Image(systemName: "plus.circle").accessibilityLabel(L10n.text("Add Music or Playlist")) }
            }
        }
        .alert(L10n.text("New Playlist"), isPresented: $newPlaylist) {
            TextField(L10n.text("Playlist Name"), text: $playlistName)
            Button(L10n.text("Create")) { _ = model.createPlaylist(playlistName) }.disabled(playlistName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(L10n.text("Cancel"), role: .cancel) {}
        }
        .dropDestination(for: URL.self) { urls, _ in model.importURLs(urls); return !urls.isEmpty }
    }
}

struct HomeView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("Your music, always with you.")).font(.largeTitle.bold())
                    Text(L10n.text("format.library.summary", model.tracks.count)).foregroundStyle(.secondary)
                    HStack {
                        Button { model.showImporter = true } label: { Label(L10n.text("Import Music"), systemImage: "plus") }.buttonStyle(.borderedProminent)
                        if !model.tracks.isEmpty { Button { model.playback.play(model.tracks, shuffled: true) } label: { Label(L10n.text("Shuffle"), systemImage: "shuffle") }.buttonStyle(.bordered) }
                    }.padding(.top, 8)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
                ForEach(model.homeSections.filter(\.enabled)) { section in sectionView(section.id) }
                if model.tracks.isEmpty {
                    ContentUnavailableView(L10n.text("Start with your first song"), systemImage: "music.note", description: Text(L10n.text("Import music from Files, iCloud Drive, or your computer. Originals stay intact, and your collection stays available offline.")))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }.padding(24).frame(maxWidth: 1_200, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    @ViewBuilder private func sectionView(_ name: String) -> some View {
        switch name {
        case "continue":
            if let track = model.playback.track {
                Button { model.showPlayer = true } label: {
                    HStack(spacing: 16) { ArtworkView(track: track, vault: model.vault, size: 80); VStack(alignment: .leading, spacing: 5) { Text(L10n.text("Continue Listening")).font(.caption).foregroundStyle(.secondary); Text(track.title).font(.headline).lineLimit(1); Text(track.displayArtist).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Image(systemName: "arrow.up.right") }.padding(16).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain)
            }
        case "categories":
            HStack {
                NavigationLink { CollectionGrid(model: model, kind: .artists).navigationTitle(L10n.text("Artists")) } label: { category(L10n.text("Artists"), "person.2", model.artists.count) }
                NavigationLink { CollectionGrid(model: model, kind: .albums).navigationTitle(L10n.text("Albums")) } label: { category(L10n.text("Albums"), "square.stack", model.albums.count) }
                NavigationLink { SongListView(model: model, destination: .favorites).navigationTitle(L10n.text("Favorites")) } label: { category(L10n.text("Favorites"), "heart", model.tracks.filter(\.isFavorite).count) }
            }.buttonStyle(.plain)
        case "playlists":
            if !model.playlists.isEmpty {
                Text(L10n.text("My Playlists")).font(.title2.bold())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) { ForEach(model.playlists.prefix(12)) { playlist in
                        NavigationLink { SongListView(model: model, destination: .playlist(playlist.id)).navigationTitle(playlist.name) } label: {
                            VStack(alignment: .leading, spacing: 8) { ArtworkView(track: model.cover(for: playlist), vault: model.vault, size: 128); Text(playlist.name).font(.headline).lineLimit(1); Text(L10n.text("format.song_count", playlist.entries.count)).font(.caption).foregroundStyle(.secondary) }.frame(width: 128)
                        }.buttonStyle(.plain)
                    } }
                }
            }
        case "recent":
            if !model.tracks.isEmpty {
                Text(L10n.text("Recently Added")).font(.title2.bold())
                LazyVStack(spacing: 2) { ForEach(model.tracks.sorted { $0.addedAt > $1.addedAt }.prefix(12)) { track in TrackRow(model: model, track: track) { model.playback.play(model.tracks.sorted { $0.addedAt > $1.addedAt }, startingAt: track.id) } } }
            }
        case "statistics":
            NavigationLink { ListeningStatsView(model: model) } label: { HStack { Label(L10n.text("Listening Statistics"), systemImage: "chart.bar"); Spacer(); Text(musicTime(model.events.reduce(0) { $0 + $1.seconds })).monospacedDigit() }.padding(18).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18)) }.buttonStyle(.plain)
        default: EmptyView()
        }
    }
    private func category(_ label: String, _ symbol: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) { Image(systemName: symbol).font(.title2).foregroundStyle(Color.accentColor); Text(label).font(.headline); Text("\(count)").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
    }
}

