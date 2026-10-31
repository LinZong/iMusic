import Foundation

/// Pure library projections, independent of SQLite, playback, cloud, and presentation state.
struct LibraryCatalog {
    /// Active song metadata.
    let tracks: [Track]
    /// Recoverable song metadata.
    let deletedTracks: [Track]
    /// Active playlist metadata.
    let playlists: [Playlist]
    /// Whether collaboration credits are split into individual artists.
    let splitArtists: Bool
    /// Persisted artist separator list.
    let artistSeparators: String
    /// Returns the unfiltered songs belonging to a destination; page-owned queries are applied by
    /// the corresponding child view.
    func songs(for destination: LibraryDestination) -> [Track] {
        let result: [Track]
        switch destination {
        case .favorites: result = tracks.filter(\.isFavorite)
        case .artist(let artist): result = tracks.filter { artistNames($0).contains(artist) }
        case .album(let key):
            result = tracks.filter { $0.albumKey == key }
                .sorted {
                    ($0.discNumber, $0.trackNumber, $0.title) < (
                        $1.discNumber, $1.trackNumber, $1.title
                    )
                }
        case .genre(let name): result = tracks.filter { $0.genre == name }
        case .playlist(let id):
            result =
                playlists.first { $0.id == id }?.entries
                .compactMap { entry in
                    tracks.first { $0.id == entry.trackID }
                } ?? []
        case .trash: result = deletedTracks
        default: result = tracks
        }
        return result
    }
    /// Returns the localized destination title or resolves the selected playlist or album's current
    /// display name.
    func title(for destination: LibraryDestination) -> String {
        switch destination {
        case .playlist(let id): playlists.first { $0.id == id }?.name ?? L10n.text("Playlists")
        case .album(let key):
            tracks.first { $0.albumKey == key }?.displayAlbum ?? L10n.text("Albums")
        default: destination.title
        }
    }
    /// Returns performer and album-artist credits using the saved collaborator splitting preference
    /// and separators.
    func artistNames(_ track: Track) -> [String] {
        let separators = artistSeparators.components(separatedBy: "|")
            .map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        return ArtistCreditParser.names(
            track.artist,
            split: splitArtists,
            separators: separators
        )
            + ArtistCreditParser.names(
                track.albumArtist,
                split: splitArtists,
                separators: separators
            )
    }
    /// Unique sorted performer and album-artist names derived from the unfiltered active library.
    var artists: [String] {
        Array(Set(tracks.flatMap(artistNames)))
            .sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
    }
    /// One representative track per normalized album identity, sorted by display title.
    var albums: [Track] {
        var keys = Set<String>()
        return tracks.filter { keys.insert($0.albumKey).inserted }
            .sorted {
                $0.displayAlbum.localizedStandardCompare($1.displayAlbum) == .orderedAscending
            }
    }
    /// Returns a representative playlist song or a placeholder record carrying its custom artwork
    /// file name.
    func cover(for playlist: Playlist) -> Track? {
        var track = playlist.entries.compactMap { entry in tracks.first { $0.id == entry.trackID } }
            .first
        if let name = playlist.artworkName {
            if track == nil {
                track = Track(
                    assetHash: String(repeating: "0", count: 64),
                    fileExtension: "wav",
                    originalFilename: "",
                    title: playlist.name
                )
            }
            track?.artworkName = name
        }
        return track
    }

}
