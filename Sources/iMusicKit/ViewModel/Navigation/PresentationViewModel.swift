import Foundation
import Observation

@MainActor @Observable
public final class PresentationViewModel {
  /// Whether the full Now Playing sheet is presented.
  public var showPlayer = false
  /// Whether the playback queue is requested, either inside Now Playing or as its own sheet.
  public var showQueue = false
  /// Song whose metadata editor is presented, or nil when no song editor is open.
  public var editingTrack: Track?
  /// Songs included in the currently presented bulk metadata editor.
  public var batchEditingTracks: [Track]?

}
