import SwiftUI

/// Active library songs, favorites, or metadata-filtered collection with page-owned search.
struct SongCollectionView<Header: View>: View {
    /// Collection data and independent list mechanics.
    @State var model: SongCollectionViewModel

    /// Feature-owned fixed controls displayed between the search field and the summary.
    @ViewBuilder var header: () -> Header

    /// Retains the collection model and composes optional fixed feature controls.
    init(
        model: SongCollectionViewModel,
        @ViewBuilder header: @escaping () -> Header = {
            EmptyView()
        }
    ) {
        _model = State(initialValue: model)
        self.header = header
    }

    /// Composes active-song rows and menus using the common native list foundation.
    var body: some View {
        @Bindable var state = model.state
        let list = SongListView(
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
            primaryAction: { model.play(row: $0.first) }
        )
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                header()
                list
            }
            #else
            list.safeAreaInset(edge: .top, spacing: 0) {
                header().background(.background, ignoresSafeAreaEdges: [])
            }
            #endif
        }
        .contentSearch(text: $state.search, prompt: L10n.text("Search Songs"))
    }
}
