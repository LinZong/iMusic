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
            library: model.library, player: model.player, preferences: model.preferences,
            imports: model.imports))
      case .artists:
        CollectionGrid(
          model: CollectionViewModel(library: model.library, player: model.player, kind: .artists))
      case .albums:
        CollectionGrid(
          model: CollectionViewModel(library: model.library, player: model.player, kind: .albums))
      case .genres:
        CollectionGrid(
          model: CollectionViewModel(library: model.library, player: model.player, kind: .genres))
      case .playlists:
        CollectionGrid(
          model: CollectionViewModel(library: model.library, player: model.player, kind: .playlists)
        )
      case .settings:
        SettingsView(
          model: SettingsViewModel(
            library: model.library, player: model.player, preferences: model.preferences,
            imports: model.imports))
      default:
        SongListView(
          model: SongListViewModel(
            library: model.library, player: model.player, destination: destination))
      }
    }
    .id(destination)
    .navigationTitle(model.library.title(for: destination))
    .toolbar {
      ToolbarItem {
        Menu {
          Button(L10n.text("Import Music"), systemImage: "square.and.arrow.down") {
            model.imports.showImporter = true
          }
          Button(L10n.text("Link Folder"), systemImage: "folder.badge.plus") {
            model.imports.showFolderPicker = true
          }
          Button(L10n.text("Wi-Fi Transfer"), systemImage: "wifi") { model.imports.showWiFi = true }
          Divider()
          Button(L10n.text("New Playlist"), systemImage: "plus") {
            model.playlistName = ""
            model.newPlaylist = true
          }
        } label: {
          Image(systemName: "plus.circle").accessibilityLabel(L10n.text("Add Music or Playlist"))
        }
      }
    }
    .alert(L10n.text("New Playlist"), isPresented: $model.newPlaylist) {
      TextField(L10n.text("Playlist Name"), text: $model.playlistName)
      Button(L10n.text("Create")) { _ = model.library.createPlaylist(model.playlistName) }.disabled(
        model.playlistName.trimmingCharacters(in: .whitespaces).isEmpty)
      Button(L10n.text("Cancel"), role: .cancel) {}
    }
    .dropDestination(for: URL.self) { urls, _ in
      model.imports.importURLs(urls)
      return !urls.isEmpty
    }
  }
}
