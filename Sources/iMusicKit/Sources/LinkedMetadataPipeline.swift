import CryptoKit
import Foundation
import SFBAudioEngine

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
        let audio = try AudioFile(readingPropertiesAndMetadataFrom: url)
        let metadata = audio.metadata
        let properties = audio.properties
        let duration = properties.duration ?? 0
        guard duration.isFinite, duration > 0 else { throw MusicError.unsupportedFormat }
        var track = Track(
            id: id,
            assetHash: nil,
            fileExtension: url.pathExtension.lowercased(),
            originalFilename: url.lastPathComponent,
            title: metadata.title?.isEmpty == false
                ? metadata.title! : url.deletingPathExtension().lastPathComponent,
            artist: metadata.artist ?? "",
            album: metadata.albumTitle ?? "",
            albumArtist: metadata.albumArtist ?? "",
            genre: metadata.genre ?? "",
            discNumber: metadata.discNumber ?? 1,
            trackNumber: metadata.trackNumber ?? 0,
            duration: duration,
            sampleRate: properties.sampleRate ?? 0,
            channels: Int(properties.channelCount ?? 2),
            linkedSource: reference
        )
        track.originalMetadata = [
            "title": track.title, "artist": track.artist, "album": track.album,
            "albumArtist": track.albumArtist, "genre": track.genre,
        ]
        if let picture = metadata.attachedPictures.first, picture.imageData.count <= 20_000_000 {
            // Derived artwork is allowed; the source audio is never hashed or copied.
            let hash = SHA256.hash(data: picture.imageData).map { String(format: "%02x", $0) }
                .joined()
            let name = "linked-" + hash + ".image"
            try picture.imageData.write(
                to: vault.artwork.appendingPathComponent(name),
                options: .atomic
            )
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
