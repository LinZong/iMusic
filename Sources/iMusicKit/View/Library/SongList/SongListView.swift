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

    /// Keeps summary controls outside song rows while preserving the primary scroll host.
    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            summary
            if rows.isEmpty {
                placeholder
            } else {
                nativeTable
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #else
        if #available(iOS 26.0, *) {
            GlassSongListContent(content: { touchContent }, summary: { summary })
        } else {
            touchContent.safeAreaInset(edge: .top, spacing: 0) { summary }
        }
        #endif
    }

    #if os(iOS)
    /// Preserves one native song scroller and content-centered empty states on every touch system.
    private var touchContent: some View {
        TouchSongList(rows: rows, rowContent: rowContent, move: move)
            .overlay { if rows.isEmpty { placeholder } }
    }
    #endif

    /// Shared count, duration, and caller-supplied actions without platform scrolling policy.
    private var summary: some View {
        SongListSummary(
            songCount: rows.count,
            duration: rows.reduce(0) { $0 + $1.duration },
            actions: actions
        )
    }

    /// Feature-specific empty content or scoped search results fill the remaining viewport.
    private var placeholder: some View {
        Group {
            if LibrarySearch.isEmpty(state.search) {
                emptyContent()
            } else {
                ContentUnavailableView.search(text: state.search)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.emptyState")
    }

    #if os(macOS)
    /// Retains native table sorting, selection, activation, and feature-supplied context actions.
    private var nativeTable: some View {
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
            .width(80)
        }
        .font(.title3)
        .contextMenu(forSelectionType: UUID.self) { ids in
            let selection = state.selection(ids, in: rows)
            if !selection.isEmpty { contextActions(selection) }
        } primaryAction: { ids in
            primaryAction(state.selection(ids, in: rows))
        }
    }
    #endif
}
