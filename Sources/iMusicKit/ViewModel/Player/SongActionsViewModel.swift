import Foundation

/// Selection-scoped song commands; menu presentation does not implement batch mutations.
@MainActor
struct SongActionsViewModel {
    /// Shared playback, metadata, and editor presentation dependencies.
    let player: PlayerViewModel
    /// Selected songs in display order.
    let tracks: [Track]
    /// Appends selected songs without changing the current occurrence.
    func enqueue() { for track in tracks { player.playback.enqueue(track) } }
    /// Inserts selected songs immediately next in their original display order.
    func playNext() {
        for track in tracks.reversed() { player.playback.enqueue(track, next: true) }
    }
    /// Sets a uniform favorite value based on the first selected song.
    func toggleFavorites() {
        guard let first = tracks.first else { return }
        for var track in tracks {
            track.isFavorite = !first.isFavorite
            player.library.commands.save(track)
        }
    }
    /// Requests the single-song editor or the independent batch editor.
    func edit() {
        if tracks.count == 1 {
            player.presentation.editingTrack = tracks.first
        } else {
            player.presentation.batchEditingTracks = tracks
        }
    }
    /// Requests an explicit cloud download for the single selected managed song.
    func download() {
        guard tracks.count == 1, let track = tracks.first, !track.isLinked else { return }
        Task { await player.library.cloud.download(track) }
    }
}
