import Foundation

/// Validates imported or synchronized domain records without reading or changing the database.
enum SyncRecordValidator {
    static func validate(_ value: SyncEnvelope) throws {
        switch value.kind {
        case "track":
            let track = try JSONDecoder().decode(Track.self, from: value.payload)
            guard value.id == track.id.uuidString,
                track.isLinked
                    ? track.assetHash == nil : track.assetHash.map(MediaVault.isValidHash) == true,
                MediaVault.isValidExtension(track.fileExtension),
                track.linkedSource.map({ LinkedAudioReference.isSafeRelativePath($0.relativePath) })
                    ?? true
            else { throw MusicError.invalidBackup(L10n.text("Invalid audio record")) }
        case "playlist":
            let playlist = try JSONDecoder().decode(Playlist.self, from: value.payload)
            guard value.id == playlist.id.uuidString,
                Set(playlist.entries.map(\.id)).count == playlist.entries.count,
                !playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                playlist.entries.allSatisfy({ $0.order?.isFinite ?? true })
            else { throw MusicError.invalidBackup(L10n.text("Invalid playlist record")) }
        case "listen":
            let event = try JSONDecoder().decode(ListenEvent.self, from: value.payload)
            guard value.id == event.id.uuidString else {
                throw MusicError.invalidBackup(L10n.text("Invalid listening record"))
            }
        default: throw MusicError.invalidBackup(L10n.text("Unsupported record type"))
        }
    }
}
