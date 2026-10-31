import Foundation
import SFBAudioEngine

/// Decoder result independent of managed-copy versus original-file ownership.
struct DecodedAudioMetadata {
    /// Validated audio metadata before artwork storage or user-override restoration.
    let track: Track
    /// Bounded embedded cover, if present; never includes source audio.
    let artwork: Data?
}

/// Reads supported audio tags and technical properties once for both admission paths.
enum AudioMetadataReader {
    /// Decodes one already-readable file; cloud hydration and copy policy remain caller-owned.
    static func read(
        _ url: URL,
        id: UUID,
        assetHash: String?,
        originalFilename: String,
        reference: LinkedAudioReference? = nil
    ) throws -> DecodedAudioMetadata {
        let audio = try AudioFile(readingPropertiesAndMetadataFrom: url)
        let metadata = audio.metadata
        let properties = audio.properties
        let duration = properties.duration ?? 0
        guard duration.isFinite, duration > 0 else { throw MusicError.unsupportedFormat }
        var track = Track(
            id: id,
            assetHash: assetHash,
            fileExtension: url.pathExtension.lowercased(),
            originalFilename: originalFilename,
            title: metadata.title?.isEmpty == false
                ? metadata.title!
                : URL(fileURLWithPath: originalFilename).deletingPathExtension().lastPathComponent,
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
        let artwork = metadata.attachedPictures.first?.imageData
        return DecodedAudioMetadata(
            track: track,
            artwork: artwork.flatMap { $0.count <= 20_000_000 ? $0 : nil }
        )
    }
}
