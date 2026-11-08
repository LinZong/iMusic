import SwiftUI

/// Active library songs, favorites, or metadata-filtered collection with page-owned search.
struct SongCollectionView<Header: View>: View {
    /// Collection data and independent list mechanics.
    @State var model: SongCollectionViewModel

    /// Feature-owned list header; absent for collections without shortcut navigation.
    @ViewBuilder var header: () -> Header?

    /// Retains the collection model and composes optional scrolling feature controls.
    init(
        model: SongCollectionViewModel,
        @ViewBuilder header: @escaping () -> Header? = {
            Optional<EmptyView>.none
        }
    ) {
        _model = State(initialValue: model)
        self.header = header
    }

    /// Shares the same native drawer and search presentation as the collection grids.
    var body: some View {
        @Bindable var state = model.state
        collectionContent
            .librarySearch(text: $state.search, prompt: L10n.text("Search Songs"))
    }

    /// Lets the native song scroller drive title transitions without changing identity or offset.
    @ViewBuilder
    private var collectionContent: some View {
        songList
            .navigationTitle(model.title)
            #if os(iOS)
        .environment(\.touchSongListScrollBehavior, .systemNavigation)
            #endif
    }

    /// Supplies collection rows and actions without imposing a navigation presentation policy.
    private var songList: some View {
        SongListView(
            state: model.state,
            rows: model.rows,
            library: model.library,
            rowContent: { row in
                TrackRow(model: model.player, track: row.track) { model.play(row: row) }
                    .overlay(alignment: .bottom) {
                        Divider().padding(.leading, 64).padding(.trailing, 6)
                    }
                    .padding(.horizontal, 12)
            },
            actions: { SongListPlaybackActions(model: model) },
            emptyContent: {
                ContentUnavailableView(
                    L10n.text("No Music Here Yet"),
                    systemImage: model.scope.symbol,
                    description: Text(
                        L10n.text("Import music to start organizing your library.")
                    )
                )
            },
            contextActions: { selection in
                TrackActions(model: model.player, tracks: selection.map(\.track))
                Button(L10n.text("Play Selected Songs")) { model.play(row: selection.first) }
            },
            move: nil,
            primaryAction: { model.play(row: $0.first) },
            header: header
        )
    }
}
