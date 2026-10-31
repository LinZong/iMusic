import Foundation
import Observation

/// Settings-only boundary for audio preferences, independent of library-record transactions.
protocol PlaybackPreferenceStoring: Sendable {
    /// Reads an optional typed preference.
    func setting<T: Decodable>(_ key: String, as: T.Type) throws -> T?
    /// Saves one typed preference atomically.
    func setSetting<T: Encodable>(_ key: String, value: T) throws
}
extension LibraryStore: PlaybackPreferenceStoring {}

/// Owns gain, mute, speed, and equalizer settings independently of queue transitions.
@MainActor @Observable
final class PlaybackAudioSettings {
    /// Linear application gain bounded to the valid engine range.
    private(set) var volume: Float = 1
    /// Last nonzero gain restored after mute, persisted only on this device.
    private var lastAudibleVolume: Float = 1
    /// Playback speed applied to the shared engine.
    var rate: Float = 1 {
        didSet {
            engine.setRate(rate)
            persist()
        }
    }
    /// Equalizer bypass state applied to the shared engine.
    var eqEnabled = false { didSet { applyEQ() } }
    /// Ten equalizer gains in decibels.
    var eqGains: [Float] = Array(repeating: 0, count: 10) { didSet { applyEQ() } }
    /// Whether the application gain is zero, independent of the system output volume.
    var isMuted: Bool { volume == 0 }
    /// Existing engine; preference changes never recreate its playback graph.
    private let engine: any PlaybackEngine
    /// Narrow settings persistence dependency.
    private let store: any PlaybackPreferenceStoring
    /// Restores persisted settings and applies them to the injected engine once.
    init(store: any PlaybackPreferenceStoring, engine: any PlaybackEngine) {
        self.store = store
        self.engine = engine
        if let saved = try? store.setting("audio", as: AudioPreferences.self) {
            rate = saved.rate
            eqEnabled = saved.eqEnabled
            eqGains = saved.gains
        }
        if let saved = try? store.setting("playbackVolume", as: VolumePreferences.self) {
            volume = saved.volume.isFinite ? min(1, max(0, saved.volume)) : 1
            lastAudibleVolume =
                saved.lastAudibleVolume.isFinite && saved.lastAudibleVolume > 0
                ? min(1, saved.lastAudibleVolume) : 1
            if volume > 0 { lastAudibleVolume = volume }
        }
        engine.setRate(rate)
        engine.setVolume(volume)
        engine.setEqualizer(eqGains, enabled: eqEnabled)
    }
    /// Applies finite, bounded gain immediately and saves device-local volume preferences.
    func setVolume(_ value: Float) {
        guard value.isFinite else { return }
        let bounded = min(1, max(0, value))
        guard bounded != volume else { return }
        volume = bounded
        if bounded > 0 { lastAudibleVolume = bounded }
        engine.setVolume(bounded)
        try? store.setSetting(
            "playbackVolume",
            value: VolumePreferences(volume: volume, lastAudibleVolume: lastAudibleVolume)
        )
    }
    /// Mutes without pausing playback or restores the last nonzero application gain.
    func toggleMute() { setVolume(isMuted ? lastAudibleVolume : 0) }
    private func applyEQ() {
        engine.setEqualizer(eqGains, enabled: eqEnabled)
        persist()
    }
    private func persist() {
        try? store.setSetting(
            "audio",
            value: AudioPreferences(rate: rate, eqEnabled: eqEnabled, gains: eqGains)
        )
    }
}

private struct AudioPreferences: Codable {
    /// Persisted playback speed multiplier.
    var rate: Float
    /// Persisted equalizer bypass preference.
    var eqEnabled: Bool
    /// Persisted ten-band gain values in decibels.
    var gains: [Float]
}

private struct VolumePreferences: Codable {
    /// Device-local application gain, intentionally excluded from portable backup preferences.
    var volume: Float
    /// Nonzero gain restored when the user unmutes after reopening the application.
    var lastAudibleVolume: Float
}
