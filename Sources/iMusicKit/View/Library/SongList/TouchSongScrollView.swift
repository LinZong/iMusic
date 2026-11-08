import SwiftUI

#if os(iOS)
/// Native lazy song content for pages whose navigation and search follow the system scroll view.
struct TouchSongScrollView<Row: View, Header: View>: View {
    /// Stable song occurrences supplied by the feature, without synthetic control rows.
    let rows: [SongRowData]
    /// Feature-owned row styling and playback actions; this scroller has no editing capability.
    @ViewBuilder var rowContent: (SongRowData) -> Row
    /// Optional controls preceding songs in the same vertical scroll document.
    @ViewBuilder var header: () -> Header

    /// Uses the same scroll primitive as collection grids, including native navigation insets.
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                header()
                ForEach(rows, content: rowContent)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("library.songList")
    }
}
#endif
