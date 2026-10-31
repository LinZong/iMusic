import Foundation

/// Owns actual listening accumulation and ordered session checkpoints, not transport decisions.
@MainActor
final class PlaybackHistoryRecorder {
    /// Existing SQLite writer keeps async checkpoints ordered before explicit saves.
    private let store: LibraryStore
    /// Last save deadline used for five-second checkpoints.
    private var lastSaved = Date.distantPast
    /// Monotonic clock of the previous sample, independent of playback position.
    var lastTick = ProcessInfo.processInfo.systemUptime
    /// Actual seconds heard in the current segment.
    var listened: Double = 0
    /// Wall-clock start of the current listening segment.
    var startedAt = Date()
    /// Stable event identity reused by incremental saves until the segment is flushed.
    private var eventID = UUID()
    /// Creates recording around the existing transactional writer.
    init(store: LibraryStore) { self.store = store }
    /// Accumulates bounded monotonic time only while audio is playing.
    func sample(now: TimeInterval, isPlaying: Bool) {
        let delta = min(0.5, max(0, now - lastTick))
        lastTick = now
        if isPlaying { listened += delta }
    }
    /// Captures immutable event progress for synchronous or background persistence.
    func snapshot(trackID: UUID?) -> ListenEvent? {
        guard listened >= 1, let trackID else { return nil }
        return ListenEvent(id: eventID, trackID: trackID, startedAt: startedAt, seconds: listened)
    }
    /// Saves one segment and optionally starts a new event identity.
    func flush(trackID: UUID?, reset: Bool) throws {
        defer {
            if reset {
                listened = 0
                startedAt = Date()
                eventID = UUID()
            }
        }
        if let event = snapshot(trackID: trackID) { try store.save(event) }
    }
    /// Saves an explicit transport checkpoint with the latest sampled timeline position.
    func save(_ session: PlaybackSession, position: Double) throws {
        defer { lastSaved = Date() }
        var snapshot = session
        snapshot.position = position
        try store.setSetting("playback", value: snapshot)
    }
    /// Schedules an atomic background checkpoint when active playback reaches the save deadline.
    @discardableResult
    func checkpoint(
        _ session: PlaybackSession,
        position: Double,
        trackID: UUID?,
        isPlaying: Bool,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) -> Bool {
        guard isPlaying, Date().timeIntervalSince(lastSaved) >= 5 else { return false }
        var captured = session
        captured.position = position
        lastSaved = Date()
        store.savePlaybackInBackground(
            captured,
            event: snapshot(trackID: trackID),
            completion: completion
        )
        return true
    }
}
