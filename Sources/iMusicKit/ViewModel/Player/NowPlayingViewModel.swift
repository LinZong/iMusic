import Observation

@MainActor @Observable
final class NowPlayingViewModel {
  /// Shared playback session and song actions; contains no editor draft or search query.
  let player: PlayerViewModel
  /// Whether this full-player surface presents the equalizer sheet.
  var equalizer = false
  /// Creates local full-player presentation state around the shared session.
  init(player: PlayerViewModel) { self.player = player }
}
