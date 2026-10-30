import Foundation

struct SongRowData: Identifiable {
    /// Row occurrence identity; playlist duplicates use distinct entry identities rather than track
    /// identities.
    var id: UUID
    /// Song metadata and managed-file reference represented by this row.
    var track: Track
    /// Song title used for table display and title sorting.
    var title: String { track.title }
    /// Localized performer label used by the artist table column.
    var artist: String { track.displayArtist }
    /// Localized album label used by the album table column.
    var album: String { track.displayAlbum }
    /// Full-track duration in seconds used for sorting and aggregate list totals.
    var duration: Double { track.duration }
}
