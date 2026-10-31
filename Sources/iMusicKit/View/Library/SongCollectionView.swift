import SwiftUI

/// Active library songs, favorites, or metadata-filtered collection with page-owned search.
struct SongCollectionView: View {
    /// Collection data and independent list mechanics.
    @State var model: SongCollectionViewModel

    /// Composes active-song rows and menus using the common native list foundation.
    var body: some View {
        @Bindable var state = model.state
        SongListView(
            state: model.state,
            rows: model.rows,
            library: model.library,
            rowContent: { row in
                TrackRow(model: model.player, track: row.track) { model.play(row: row) }
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
            },
            actions: { SongListPlaybackActions(model: model) },
            emptyContent: {
                ContentUnavailableView(
                    L10n.text("No Music Here Yet"),
                    systemImage: model.scope.symbol,
                    description: Text(L10n.text("Import music to start organizing your library."))
                )
            },
            contextActions: { selection in
                TrackActions(model: model.player, tracks: selection.map(\.track))
                Button(L10n.text("Play Selected Songs")) { model.play(row: selection.first) }
            },
            move: nil,
            primaryAction: { model.play(row: $0.first) }
        )
        .librarySearch(text: $state.search, prompt: L10n.text("Search Songs"))
    }
}
