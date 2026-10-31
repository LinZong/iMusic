import CryptoKit
import Foundation

/// Reads tags, technical metadata, and derived artwork directly from coordinated source files.
enum LinkedMetadataPipeline {
    /// Validates readable audio and stores only a bounded derived cover image.
    static func parse(
        _ url: URL,
        id: UUID,
        reference: LinkedAudioReference,
        vault: MediaVault,
        previous: Track?
    ) throws -> Track {
        let decoded = try AudioMetadataReader.read(
            url,
            id: id,
            assetHash: nil,
            originalFilename: url.lastPathComponent,
            reference: reference
        )
        var track = decoded.track
        if let artwork = decoded.artwork {
            // Derived artwork is allowed; original audio is never hashed or copied.
            let hash = SHA256.hash(data: artwork).map { String(format: "%02x", $0) }.joined()
            let name = "linked-" + hash + ".image"
            try artwork.write(to: vault.artwork.appendingPathComponent(name), options: .atomic)
            track.artworkName = name
        }
        track.originalMetadata["artworkName"] = track.artworkName ?? ""
        track.originalMetadata["discNumber"] = String(track.discNumber)
        track.originalMetadata["trackNumber"] = String(track.trackNumber)
        if let previous { preserveEdits(from: previous, in: &track) }
        return track
    }

    /// Keeps user overrides and library relationships while refreshing original source metadata.
    static func preserveEdits(from old: Track, in track: inout Track) {
        if (old.artworkName ?? "") != (old.originalMetadata["artworkName"] ?? "") {
            track.artworkName = old.artworkName
        }
        if String(old.discNumber) != old.originalMetadata["discNumber"] {
            track.discNumber = old.discNumber
        }
        if String(old.trackNumber) != old.originalMetadata["trackNumber"] {
            track.trackNumber = old.trackNumber
        }
        track.isFavorite = old.isFavorite
        track.addedAt = old.addedAt
        track.deletedAt = old.deletedAt
        track.permanentlyDeletedAt = old.permanentlyDeletedAt
        for (key, field) in [
            ("title", \Track.title), ("artist", \Track.artist),
            ("album", \Track.album), ("albumArtist", \Track.albumArtist), ("genre", \Track.genre),
        ] {
            if old[keyPath: field] != old.originalMetadata[key] {
                track[keyPath: field] = old[keyPath: field]
            }
        }
    }
}
