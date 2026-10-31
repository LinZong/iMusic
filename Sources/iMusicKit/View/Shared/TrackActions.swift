import SwiftUI

struct TrackActions: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @Bindable var model: PlayerViewModel
    /// Songs targeted by the shared queue, favorite, metadata, download, and Trash menu actions.
    let tracks: [Track]
    /// Selection-scoped commands separate from menu rendering.
    private var actions: SongActionsViewModel {
        SongActionsViewModel(player: model, tracks: tracks)
    }
    /// Renders actions applying to the supplied song selection, including queue, metadata, and
    /// Trash operations.
    var body: some View {
        Button(L10n.text("Play Next"), systemImage: "text.line.first.and.arrowtriangle.forward") {
            actions.playNext()
        }
        Button(L10n.text("Add to Queue"), systemImage: "text.badge.plus") {
            actions.enqueue()
        }
        Menu(L10n.text("Add to Playlist"), systemImage: "music.note.list") {
            ForEach(model.library.playlists) { playlist in
                Button(playlist.name) { model.library.commands.add(tracks, to: playlist) }
            }
            if model.library.playlists.isEmpty { Text(L10n.text("Create a playlist first")) }
        }
        if let first = tracks.first {
            Button(
                first.isFavorite ? L10n.text("Remove from Favorites") : L10n.text("Favorites"),
                systemImage: "heart"
            ) {
                actions.toggleFavorites()
            }
            .accessibilityIdentifier("trackActions.favorite")
            if tracks.count == 1 {
                Button(L10n.text("Edit Tags and Artwork"), systemImage: "pencil") {
                    actions.edit()
                }
                if !first.isLinked, !model.library.availableTrackIDs.contains(first.id) {
                    Button(L10n.text("Download from iCloud"), systemImage: "icloud.and.arrow.down")
                    {
                        actions.download()
                    }
                }
            } else {
                Button(L10n.text("Edit Tags in Bulk"), systemImage: "pencil") {
                    actions.edit()
                }
            }
        }
        Divider()
        Button(L10n.text("Move to Trash"), systemImage: "trash", role: .destructive) {
            model.library.commands.trash(tracks)
        }
        .accessibilityIdentifier("trackActions.trash")
    }
}
