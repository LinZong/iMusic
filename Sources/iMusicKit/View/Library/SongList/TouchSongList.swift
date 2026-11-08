import SwiftUI

#if os(iOS)
/// Native touch list with optional scrolling controls and independently editable song occurrences.
struct TouchSongList<Row: View, Header: View>: View {
    /// Visible song occurrences; non-song controls never enter this collection or its indexes.
    let rows: [SongRowData]
    /// Feature-owned row presentation, including any native swipe actions.
    @ViewBuilder var rowContent: (SongRowData) -> Row
    /// Optional reordering applied only to song occurrences.
    var move: ((IndexSet, Int) -> Void)?
    /// Non-song content that scrolls before the editable song occurrences.
    @ViewBuilder var header: () -> Header

    /// Keeps native scrolling and editing scoped to actual songs.
    var body: some View {
        List {
            header()
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(rows) { row in rowContent(row) }
                .onMove(perform: move)
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .accessibilityIdentifier("library.songList")
    }
}
#endif
