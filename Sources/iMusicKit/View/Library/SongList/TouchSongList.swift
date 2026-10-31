import SwiftUI

#if os(iOS)
/// Native touch list containing only editable song occurrences.
struct TouchSongList<Row: View>: View {
    /// Visible song occurrences; fixed controls and summaries never enter this collection.
    let rows: [SongRowData]
    /// Feature-owned row presentation, including any native swipe actions.
    @ViewBuilder var rowContent: (SongRowData) -> Row
    /// Optional reordering applied only to song occurrences.
    var move: ((IndexSet, Int) -> Void)?

    /// Keeps native scrolling and editing scoped to actual songs.
    var body: some View {
        List {
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
