import AVFAudio
import Foundation
import iMusicKit

/// Drives real player UI state without creating an audio engine or opening speakers.
@MainActor final class UITestPlaybackEngine: PlaybackEngine {
    /// Position retained when playback pauses or seeks.
    private var position: Double?
    /// Monotonic start time used to advance the fake playback clock.
    private var started: TimeInterval?
    /// Speed applied to the monotonic clock.
    private var rate: Float = 1
    /// Duration read from the generated audio file, without rendering audio.
    private(set) var duration: Double?
    /// Whether the test clock is advancing.
    private(set) var isPlaying = false
    /// Announces the queue occurrence selected by the coordinator.
    var onTrack: ((UUID) -> Void)?
    /// Publishes play and pause state to the production coordinator.
    var onState: ((PlaybackStatus) -> Void)?
    /// Required end callback; these short UI scenarios never reach the fixture's end.
    var onEnd: (() -> Void)?
    /// Required error callback; synchronous file errors propagate through play.
    var onError: ((Error) -> Void)?
    /// Current clock position, bounded by the generated file's duration.
    var elapsed: Double? {
        guard let position else { return nil }
        let delta = started.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
        return min(duration ?? .greatestFiniteMagnitude, position + delta * Double(rate))
    }

    /// Validates the requested file and announces playback without using audio hardware.
    func play(
        url: URL,
        entryID: UUID,
        position: Double,
        region: ClosedRange<Double>?,
        sampleRate: Double
    ) throws {
        let file = try AVAudioFile(forReading: url)
        duration = Double(file.length) / file.processingFormat.sampleRate
        self.position = position
        started = ProcessInfo.processInfo.systemUptime
        isPlaying = true
        onState?(.playing)
        onTrack?(entryID)
    }
    /// Validates a preloaded file without scheduling an audio renderer.
    func enqueue(url: URL, entryID: UUID) throws { _ = try AVAudioFile(forReading: url) }
    /// No renderer queue is allocated by this test backend.
    func clearUpcoming() {}
    /// Changes the test clock's rate while preserving its current position.
    func setRate(_ value: Float) {
        position = elapsed
        if isPlaying { started = ProcessInfo.processInfo.systemUptime }
        rate = value
    }
    /// UI tests do not modify device gain or speaker volume.
    func setVolume(_ value: Float) {}
    /// Equalizer settings remain in the coordinator without creating Audio Units.
    func setEqualizer(_ gains: [Float], enabled: Bool) {}
    /// Freezes the clock and publishes the paused state.
    func pause() {
        position = elapsed
        started = nil
        isPlaying = false
        onState?(.paused)
    }
    /// Restarts the retained clock and publishes the playing state.
    func resume() throws {
        started = ProcessInfo.processInfo.systemUptime
        isPlaying = true
        onState?(.playing)
    }
    /// Moves the test clock to the coordinator's validated seek target.
    func seek(to seconds: Double) throws {
        position = seconds
        if isPlaying { started = ProcessInfo.processInfo.systemUptime }
    }
    /// Discards the current clock without touching audio hardware.
    func stop() {
        position = nil
        started = nil
        duration = nil
        isPlaying = false
    }
}
