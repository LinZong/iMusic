import SwiftUI

/// Shared artwork and metadata presentation for native song-table title cells.
struct SongTableTitle: View {
    /// Occurrence represented by this cell.
    let row: SongRowData
    /// Artwork storage and cached file-availability information.
    let library: LibraryViewModel

    /// Renders title, favorite, and availability without performing any filesystem work.
    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(track: row.track, vault: library.vault, size: 32)
            Text(row.title).lineLimit(1)
                .accessibilityIdentifier("track.title.\(row.track.originalFilename)")
            if row.track.isFavorite {
                Image(systemName: "heart.fill").foregroundStyle(.pink).font(.caption)
            }
            if !library.availableTrackIDs.contains(row.track.id) {
                Image(
                    systemName: row.track.isLinked
                        ? "folder.badge.questionmark" : "icloud.and.arrow.down"
                )
                .foregroundStyle(.secondary)
            }
        }
        .draggable(row.track.id.uuidString)
    }
}
