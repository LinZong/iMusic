import SwiftUI

public struct RootView: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @State var model: RootViewModel
    /// SwiftUI scene lifecycle used to persist playback and stop uploads in the background.
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    /// Horizontal size class used to choose compact tabs or adaptive split navigation.
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    /// Creates the adaptive app navigation shell using the shared observable application model.
    public init(model: AppModel) { self.model = model.makeRootViewModel() }
    /// Renders adaptive navigation, native import and editor presentations, alerts, and shared
    /// progress.
    public var body: some View {
        @Bindable var model = model
        content
            .preferredColorScheme(
                model.preferences.appearance == "light"
                    ? .light : model.preferences.appearance == "dark" ? .dark : nil
            )
            .fontDesign(model.preferences.serifFont ? .serif : .default)
            .task { await model.launch() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    model.player.playback.persist()
                    Task { await model.imports.wifi.stop() }
                } else if phase == .active {
                    Task { await model.imports.foreground() }
                }
            }
            .modifier(AppPresentations(model: model))
    }
    /// Platform-adaptive navigation shell containing tabs or the sidebar split view.
    @ViewBuilder private var content: some View {
        #if os(iOS)
        if sizeClass == .compact {
            TabView {
                tab(.home)
                tab(.songs)
                tab(.playlists)
                tab(.settings)
            }
        } else {
            splitView
        }
        #else
        splitView.frame(minWidth: 680, minHeight: 480)
        #endif
    }
    #if os(iOS)
    private func tab(_ destination: LibraryDestination) -> some View {
        NavigationStack {
            DestinationView(
                model: DestinationViewModel(
                    library: model.library,
                    player: model.player,
                    preferences: model.preferences,
                    imports: model.imports,
                    destination: destination
                )
            )
            .safeAreaInset(edge: .bottom, spacing: 0) { LibraryFooter(model: model) }
        }
        .tabItem { Label(destination.title, systemImage: destination.symbol) }
    }
    #endif
    /// Sidebar navigation with a detail stack and a shared playback footer.
    private var splitView: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section("iMusic") {
                    ForEach(
                        [
                            LibraryDestination.home, .songs, .artists, .albums, .genres, .favorites,
                            .playlists,
                        ],
                        id: \.self
                    ) { destination in
                        NavigationLink(value: destination) {
                            Label(destination.title, systemImage: destination.symbol)
                        }
                    }
                }
                if !model.library.playlists.isEmpty {
                    Section(L10n.text("My Playlists")) {
                        ForEach(model.library.playlists) { playlist in
                            NavigationLink(value: LibraryDestination.playlist(playlist.id)) {
                                Label(playlist.name, systemImage: "music.note.list")
                            }
                            .dropDestination(for: String.self) { ids, _ in
                                let tracks = ids.compactMap { value in
                                    model.library.tracks.first { $0.id.uuidString == value }
                                }
                                model.library.add(tracks, to: playlist)
                                return !tracks.isEmpty
                            }
                        }
                    }
                }
                Section {
                    NavigationLink(value: LibraryDestination.trash) {
                        Label(L10n.text("Trash"), systemImage: "trash")
                    }
                    NavigationLink(value: LibraryDestination.settings) {
                        Label(L10n.text("Settings"), systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("iMusic")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            NavigationStack {
                DestinationView(
                    model: DestinationViewModel(
                        library: model.library,
                        player: model.player,
                        preferences: model.preferences,
                        imports: model.imports,
                        destination: model.selection ?? .home
                    )
                )
                .id(model.selection ?? .home)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { LibraryFooter(model: model) }
    }
}
