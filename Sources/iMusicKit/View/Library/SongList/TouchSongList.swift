import SwiftUI

#if os(iOS)
/// Native touch list with a scrolling summary and occurrence-only editing capabilities.
struct TouchSongList<Row: View, Summary: View, Placeholder: View>: View {
    /// Visible song occurrences; the summary never enters this collection.
    let rows: [SongRowData]
    /// Feature-owned row presentation, including any native swipe actions.
    @ViewBuilder var rowContent: (SongRowData) -> Row
    /// Ordinary leading content that scrolls and rebounds with the song rows.
    @ViewBuilder var summary: () -> Summary
    /// Empty or unmatched content centered below the summary without a fixed text height.
    @ViewBuilder var placeholder: () -> Placeholder
    /// Optional reordering applied only to song occurrences, excluding the summary row.
    var move: ((IndexSet, Int) -> Void)?

    /// Uses one scroll owner for short lists, long lists, and viewport-filling empty states.
    var body: some View {
        GeometryReader { viewport in
            List {
                if rows.isEmpty {
                    VStack(spacing: 0) {
                        summary().buttonStyle(.borderless)
                        placeholder()
                    }
                    .frame(minHeight: viewport.size.height)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    summary()
                        .buttonStyle(.borderless)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    ForEach(rows) { row in rowContent(row) }
                        .onMove(perform: move)
                }
            }
            .listStyle(.plain)
            .listRowSpacing(0)
            .environment(\.defaultMinListRowHeight, 0)
            .contentMargins(.vertical, 0, for: .scrollContent)
            .accessibilityIdentifier("library.songList")
        }
    }
}
#endif
