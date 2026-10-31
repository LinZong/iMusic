import Foundation

/// Applies a deletion manifest while the caller holds the library writer lock.
/// Database reads and tombstone decisions belong to the repository, not filesystem cleanup.
struct ManagedMediaCleanup {
    /// Application-owned media paths; external originals are never eligible for cleanup.
    let vault: MediaVault
    /// Removes only unreferenced managed audio and derived artwork from the supplied snapshot.
    func removeUnreferenced(tracks: [Track], playlists: [Playlist]) throws {
        let retained = tracks.filter { $0.permanentlyDeletedAt == nil }
        let retainedFiles = try Set(
            retained.filter { !$0.isLinked }.map { try vault.url(for: $0).lastPathComponent }
        )
        let retainedArtwork = Set(
            retained.compactMap(\.artworkName) + playlists.compactMap(\.artworkName)
        )
        for track in tracks where track.permanentlyDeletedAt != nil {
            if !track.isLinked {
                let audio = try vault.url(for: track)
                if !retainedFiles.contains(audio.lastPathComponent) {
                    try vault.removeManagedFileIfPresent(audio)
                }
            }
            if let name = track.artworkName, !retainedArtwork.contains(name),
                let artwork = vault.artworkURL(name)
            {
                try vault.removeManagedFileIfPresent(artwork)
            }
        }
    }
}
