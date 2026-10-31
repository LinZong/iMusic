import SwiftUI

/// Generic list foundation. Feature pages supply rows, actions, and empty-state content.
struct SongListView<Row: View, Actions: View, Empty: View, Context: View>: View {
    /// Query, native table selection, and sorting owned by the containing feature.
    @Bindable var state: SongListState
    /// Visible occurrences supplied by the feature's data source.
    let rows: [SongRowData]
    /// Artwork storage and availability snapshot used by native table cells.
    let library: LibraryViewModel
    /// Touch row supplied by the feature, including any swipe actions.
    @ViewBuilder var rowContent: (SongRowData) -> Row
    /// Trailing summary actions supplied by the feature.
    @ViewBuilder var actions: () -> Actions
    /// Category-specific placeholder supplied by the feature.
    @ViewBuilder var emptyContent: () -> Empty
    /// Native table menu supplied with the selected occurrences in display order.
    @ViewBuilder var contextActions: ([SongRowData]) -> Context
    /// Optional native row-reordering capability; absent for noneditable lists.
    var move: ((IndexSet, Int) -> Void)?
    /// Native table activation; recovery pages use the default no-op.
    var primaryAction: ([SongRowData]) -> Void = { _ in }

    /// Keeps the summary at the content origin and centers placeholders in the remaining area.
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(
                    L10n.text(
                        "format.song_count.duration",
                        rows.count,
                        String(describing: musicTime(rows.reduce(0) { $0 + $1.duration }))
                    )
                )
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("library.songSummary")
                Spacer()
                actions()
            }
            .padding(16)
            if rows.isEmpty {
                Group {
                    if LibrarySearch.isEmpty(state.search) {
                        emptyContent()
                    } else {
                        ContentUnavailableView.search(text: state.search)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                nativeList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Shares platform presentation without knowing the page's route or mutation semantics.
    @ViewBuilder private var nativeList: some View {
        #if os(macOS)
        Table(state.ordered(rows), selection: $state.selected, sortOrder: $state.sortOrder) {
            TableColumn(L10n.text("Title"), value: \.title) { row in
                SongTableTitle(row: row, library: library)
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
            let selection = state.selection(ids, in: rows)
            if !selection.isEmpty { contextActions(selection) }
        } primaryAction: { ids in
            primaryAction(state.selection(ids, in: rows))
        }
        #else
        List {
            ForEach(rows) { row in rowContent(row) }
                .onMove(perform: move)
        }
        .listStyle(.plain)
        #endif
    }
}
