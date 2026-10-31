import SwiftUI

struct DestinationView: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @State var model: DestinationViewModel
    /// Library route whose content, title, and toolbar are currently displayed.
    private var destination: LibraryDestination { model.destination }
    /// Renders the selected library page and shared import and playlist-creation toolbar.
    var body: some View {
        @Bindable var model = model
        Group {
            switch destination {
            case .home:
                HomeView(
                    model: HomeViewModel(
                        library: model.library,
                        player: model.player,
                        preferences: model.preferences,
                        imports: model.imports
                    )
                )
            case .artists:
                ArtistCollectionView(
                    model: ArtistCollectionViewModel(library: model.library, player: model.player)
                )
            case .albums:
                AlbumCollectionView(
                    model: AlbumCollectionViewModel(library: model.library, player: model.player)
                )
            case .genres:
                GenreCollectionView(
                    model: GenreCollectionViewModel(library: model.library, player: model.player)
                )
            case .playlists:
                PlaylistCollectionView(
                    model: PlaylistCollectionViewModel(library: model.library, player: model.player)
                )
            case .settings:
                SettingsView(
                    model: SettingsViewModel(
                        library: model.library,
                        preferences: model.preferences,
                        imports: model.imports
                    )
                )
            case .trash:
                TrashView(model: TrashViewModel(library: model.library))
            case .songs:
                AllSongsView(
                    model: SongCollectionViewModel(
                        library: model.library,
                        player: model.player,
                        scope: .all
                    )
                )
            case .playlist(let id):
                PlaylistDetailView(
                    model: PlaylistDetailViewModel(
                        library: model.library,
                        player: model.player,
                        playlistID: id
                    )
                )
            case .favorites:
                songs(in: .favorites)
            case .artist(let name):
                songs(in: .artist(name))
            case .album(let key):
                songs(in: .album(key))
            case .genre(let name):
                songs(in: .genre(name))
            }
        }
        .id(destination)
        .navigationTitle(model.library.catalog.title(for: destination))
        .toolbar {
            ToolbarItem {
                Menu {
                    Button(L10n.text("Import Music"), systemImage: "square.and.arrow.down") {
                        model.imports.picker.present(.audio)
                    }
                    .accessibilityIdentifier("library.import")
                    Button(L10n.text("Link Folder"), systemImage: "folder.badge.plus") {
                        model.imports.folders.chooseFolder()
                    }
                    .accessibilityIdentifier("library.linkFolder")
                    Button(L10n.text("Wi-Fi Transfer"), systemImage: "wifi") {
                        model.imports.transfers.presented = true
                    }
                    Divider()
                    Button(L10n.text("New Playlist"), systemImage: "plus") {
                        model.newPlaylist = true
                    }
                    .accessibilityIdentifier("library.newPlaylist")
                } label: {
                    Image(systemName: "plus.circle")
                        .accessibilityLabel(L10n.text("Add Music or Playlist"))
                }
                .accessibilityIdentifier("library.add")
            }
        }
        // Use the editor for validated input. On iOS 17.4, the previous alert's dynamically
        // disabled Create button became visibly enabled but dismissed without running its action.
        .sheet(isPresented: $model.newPlaylist) {
            PlaylistEditor(
                model: PlaylistEditorViewModel(
                    library: model.library,
                    playlist: Playlist(name: ""),
                    isCreating: true
                )
            )
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.imports.importURLs(urls)
            return !urls.isEmpty
        }
    }
    /// Resolves only active collection routes to the collection feature.
    private func songs(in scope: SongCollectionScope) -> some View {
        SongCollectionView(
            model: SongCollectionViewModel(
                library: model.library,
                player: model.player,
                scope: scope
            )
        )
    }

}
