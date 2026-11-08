import SwiftUI

/// Generic list foundation. Feature pages supply rows, actions, and empty-state content.
struct SongListView<Row: View, Actions: View, Empty: View, Context: View, Header: View>: View {
    #if os(iOS)
    /// Page-owned navigation layout; fixed editing and recovery pages keep their existing inset.
    @Environment(\.touchSongListScrollBehavior) private var scrollBehavior
    /// Empty-state layout excludes scrolling controls without observing scroll offsets.
    @State private var scrollingHeaderHeight: CGFloat = 0
    #endif
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
    /// Optional feature controls, scrolling on touch and above the native desktop table.
    @ViewBuilder var header: () -> Header?

    /// Composes feature-owned content while keeping controls separate from song editing indexes.
    init(
        state: SongListState,
        rows: [SongRowData],
        library: LibraryViewModel,
        @ViewBuilder rowContent: @escaping (SongRowData) -> Row,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder emptyContent: @escaping () -> Empty,
        @ViewBuilder contextActions: @escaping ([SongRowData]) -> Context,
        move: ((IndexSet, Int) -> Void)?,
        primaryAction: @escaping ([SongRowData]) -> Void = { _ in },
        @ViewBuilder header: @escaping () -> Header? = { Optional<EmptyView>.none }
    ) {
        self.state = state
        self.rows = rows
        self.library = library
        self.rowContent = rowContent
        self.actions = actions
        self.emptyContent = emptyContent
        self.contextActions = contextActions
        self.move = move
        self.primaryAction = primaryAction
        self.header = header
    }

    /// Keeps summary controls outside song rows while preserving the primary scroll host.
    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            header()
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
        } else if scrollBehavior == .systemNavigation {
            touchContent
        } else {
            touchContent.safeAreaInset(edge: .top, spacing: 0) { summary }
        }
        #endif
    }

    #if os(iOS)
    /// Preserves one native song scroller and content-centered empty states on every touch system.
    private var touchContent: some View {
        touchScroller
            .onPreferenceChange(SongListHeaderHeightKey.self) { scrollingHeaderHeight = $0 }
            .overlay {
                if rows.isEmpty {
                    placeholder.padding(.top, scrollingHeaderHeight)
                }
            }
    }

    /// Keeps editable lists separate from navigation-driven, nonediting lazy song content.
    @ViewBuilder private var touchScroller: some View {
        if scrollBehavior == .systemNavigation {
            TouchSongScrollView(rows: rows, rowContent: rowContent, header: { scrollingHeader })
        } else {
            TouchSongList(
                rows: rows,
                rowContent: rowContent,
                move: move,
                header: { scrollingHeader }
            )
        }
    }

    /// Keeps feature controls and legacy collection statistics in the same vertical scroller.
    @ViewBuilder private var scrollingHeader: some View {
        if let header = header() {
            measuredHeader(header)
        }
        if #available(iOS 26.0, *) {
            EmptyView()
        } else if scrollBehavior == .systemNavigation {
            measuredHeader(summary.buttonStyle(.borderless))
        }
    }

    /// Measures only empty-state header sizes; list scrolling never feeds presentation state.
    private func measuredHeader<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .background {
                if rows.isEmpty {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: SongListHeaderHeightKey.self,
                            value: geometry.size.height
                        )
                    }
                }
            }
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

#if os(iOS)
/// Adds only the heights of non-song list content when an empty overlay needs its remaining area.
private struct SongListHeaderHeightKey: PreferenceKey {
    /// Pages without scrolling controls have no top exclusion.
    static let defaultValue: CGFloat = 0

    /// Combines optional feature controls and the legacy collection summary.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}
#endif
