import Foundation
import AVFAudio
import SFBAudioEngine

@MainActor
public protocol PlaybackEngine: AnyObject {
    /// Current full-track playback position in seconds, or nil when no engine clock is available.
    var elapsed: Double? { get }
    /// Available track duration in seconds, or nil when the backend cannot provide a reliable total.
    var duration: Double? { get }
    /// Whether this backend is actively rendering playback.
    var isPlaying: Bool { get }
    /// Callback announcing the queue-entry identity whose decoder became current.
    var onTrack: ((UUID) -> Void)? { get set }
    /// Callback publishing backend playback-state transitions.
    var onState: ((PlaybackStatus) -> Void)? { get set }
    /// Callback fired when the current audio reaches its end.
    var onEnd: (() -> Void)? { get set }
    /// Callback forwarding decoding or audio-engine failures to the coordinator.
    var onError: ((Error) -> Void)? { get set }
    /// Starts the given file for a queue occurrence at a position in seconds, optionally repeating an A/B
    /// region. The sample rate converts seconds to decoder frames; decoding or startup errors are thrown.
    func play(url: URL, entryID: UUID, position: Double, region: ClosedRange<Double>?, sampleRate: Double) throws
    /// Preloads a file for the specified queue occurrence so the backend can advance without a new explicit
    /// play request; throws on decoder setup failure.
    func enqueue(url: URL, entryID: UUID) throws
    /// Removes preloaded decoders without changing the currently selected occurrence.
    func clearUpcoming()
    /// Applies a playback speed multiplier; the production backend clamps it to the supported 0.5 through 3
    /// range.
    func setRate(_ value: Float)
    /// Applies ten gain values in decibels and the equalizer enabled state; the production backend clamps
    /// gains and compensates positive boost.
    func setEqualizer(_ gains: [Float], enabled: Bool)
    /// Pauses rendering while retaining the current decoder and playback position.
    func pause()
    /// Resumes the current decoder and throws if the audio backend cannot start rendering.
    func resume() throws
    /// Moves to a full-track position in seconds or throws if the backend rejects the seek.
    func seek(to seconds: Double) throws
    /// Stops rendering, detaches callbacks from the old player, and clears decoder identity and preload state.
    func stop()
}

@MainActor
public final class SFBPlaybackEngine: NSObject, PlaybackEngine, AudioPlayer.Delegate {
    /// SFBAudioEngine player responsible for decoder scheduling and audio rendering.
    private var player = AudioPlayer()
    /// Ten-band Audio Unit equalizer inserted into the processing graph.
    private var equalizer = AVAudioUnitEQ(numberOfBands: 10)
    /// Time-pitch Audio Unit used to change playback speed while retaining pitch.
    private var timePitch = AVAudioUnitTimePitch()
    /// Decoder-object to queue-entry mapping used to recognize gapless decoder transitions.
    private var identifiers: [ObjectIdentifier: UUID] = [:]
    /// Last announced decoder identity used to retire the previous decoder-to-entry mapping.
    private var currentDecoderID: ObjectIdentifier?
    /// Queue occurrence already queued for gapless advancement, if any.
    public private(set) var preloadedID: UUID?
    /// A/B region start in full-track seconds, added to the region-relative engine clock.
    private var regionStart: Double = 0
    /// Active A/B region duration in seconds; nil for ordinary full-track playback.
    private var regionLength: Double?
    /// Callback announcing the queue-entry identity whose decoder became current.
    public var onTrack: ((UUID) -> Void)?
    /// Callback publishing backend playback-state transitions.
    public var onState: ((PlaybackStatus) -> Void)?
    /// Callback fired when the current audio reaches its end.
    public var onEnd: (() -> Void)?
    /// Callback forwarding decoding or audio-engine failures to the coordinator.
    public var onError: ((Error) -> Void)?
    /// Current full-track playback position in seconds, or nil when no engine clock is available.
    public var elapsed: Double? {
        guard let current = player.currentTime else { return nil }
        if let length = regionLength, length > 0 { return regionStart + current.truncatingRemainder(dividingBy: length) }
        return current
    }
    /// Full-track duration reported by the engine; nil for regions so callers use track metadata.
    public var duration: Double? { regionLength == nil ? player.totalTime : nil }
    /// Whether this backend is actively rendering playback.
    public var isPlaying: Bool { player.isPlaying }
    /// Creates the production audio player and configures its equalizer and time-pitch graph without
    /// beginning song playback.
    public override init() { super.init(); configurePlayer() }

    private func configurePlayer() {
        player.delegate = self
        let frequencies: [Float] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
        for (band, frequency) in zip(equalizer.bands, frequencies) {
            band.filterType = .parametric; band.frequency = frequency; band.bandwidth = 1; band.gain = 0; band.bypass = false
        }
        equalizer.bypass = true; timePitch.rate = 1
        let eq = equalizer, pitch = timePitch, source = player.sourceNode
        player.modifyProcessingGraph { engine in
            engine.attach(eq); engine.attach(pitch)
            engine.disconnectNodeOutput(source)
            engine.connect(source, to: eq, format: nil)
            engine.connect(eq, to: pitch, format: nil)
            engine.connect(pitch, to: engine.mainMixerNode, format: nil)
        }
    }
    /// Starts the given file for a queue occurrence at a position in seconds, optionally repeating an A/B
    /// region. The sample rate converts seconds to decoder frames; decoding or startup errors are thrown.
    public func play(url: URL, entryID: UUID, position: Double = 0, region: ClosedRange<Double>? = nil, sampleRate: Double = 0) throws {
        // New player identity fences all callbacks belonging to the previous session.
        let gains = equalizer.bands.map(\.gain), bypass = equalizer.bypass, rate = timePitch.rate
        player.delegate = nil; player.stop(); player = AudioPlayer()
        equalizer = AVAudioUnitEQ(numberOfBands: 10); timePitch = AVAudioUnitTimePitch()
        identifiers = [:]; preloadedID = nil; currentDecoderID = nil; regionStart = region?.lowerBound ?? 0; regionLength = region.map { $0.upperBound - $0.lowerBound }
        configurePlayer(); setEqualizer(gains, enabled: !bypass); setRate(rate)
        let decoder: any PCMDecoding
        if let region, sampleRate > 0 {
            decoder = try AudioRegionDecoder(url: url, startFrame: Int64(region.lowerBound * sampleRate), frameLength: Int64((region.upperBound - region.lowerBound) * sampleRate), repeatCount: -1)
        } else { decoder = try AudioDecoder(url: url) }
        identifiers[ObjectIdentifier(decoder)] = entryID
        try decoder.open()
        if position > 0, region == nil, sampleRate > 0 { try decoder.seek(to: Int64(position * sampleRate)) }
        try player.play(decoder)
    }
    /// Preloads a file for the specified queue occurrence so the backend can advance without a new explicit
    /// play request; throws on decoder setup failure.
    public func enqueue(url: URL, entryID: UUID) throws {
        guard preloadedID != entryID else { return }
        player.clearQueue()
        let decoder = try AudioDecoder(url: url)
        identifiers[ObjectIdentifier(decoder)] = entryID
        try player.enqueue(decoder); preloadedID = entryID
    }
    /// Removes preloaded decoders without changing the currently selected occurrence.
    public func clearUpcoming() { player.clearQueue(); preloadedID = nil }
    /// Pauses rendering while retaining the current decoder and playback position.
    public func pause() { _ = player.pause() }
    /// Resumes the current decoder and throws if the audio backend cannot start rendering.
    public func resume() throws { try player.play() }
    /// Stops rendering, detaches callbacks from the old player, and clears decoder identity and preload state.
    public func stop() { player.delegate = nil; player.stop(); identifiers = [:]; preloadedID = nil }
    /// Moves to a full-track position in seconds or throws if the backend rejects the seek.
    public func seek(to seconds: Double) throws {
        guard seconds.isFinite, player.seek(time: max(0, seconds - regionStart)) else { throw MusicError.playback(L10n.text("Seeking is unavailable. Wait for the music to load and try again.")) }
    }
    /// Applies a playback speed multiplier; the production backend clamps it to the supported 0.5 through 3
    /// range.
    public func setRate(_ value: Float) { timePitch.rate = min(3, max(0.5, value)) }
    /// Applies ten gain values in decibels and the equalizer enabled state; the production backend clamps
    /// gains and compensates positive boost.
    public func setEqualizer(_ gains: [Float], enabled: Bool) {
        equalizer.bypass = !enabled
        for (band, gain) in zip(equalizer.bands, gains) { band.gain = min(12, max(-12, gain)) }
        equalizer.globalGain = enabled ? -max(0, gains.max() ?? 0) : 0
    }
    /// Recognizes a decoder transition from the current player, rejects stale callbacks, and announces its
    /// queue occurrence on the main actor.
    nonisolated public func audioPlayer(_ audioPlayer: AudioPlayer, nowPlayingChanged nowPlaying: (any PCMDecoding)?) {
        let decoderID = nowPlaying.map { ObjectIdentifier($0) }
        Task { @MainActor [weak self] in
            guard let self, self.player === audioPlayer, let decoderID, let id = self.identifiers[decoderID] else { return }
            if let previous = self.currentDecoderID, previous != decoderID { self.identifiers.removeValue(forKey: previous) }
            self.currentDecoderID = decoderID
            if self.preloadedID == id { self.preloadedID = nil }
            self.onTrack?(id)
        }
    }
    /// Maps a current-player state callback to the domain playback state and forwards it on the main actor.
    nonisolated public func audioPlayer(_ audioPlayer: AudioPlayer, playbackStateChanged playbackState: AudioPlayer.PlaybackState) {
        let status: PlaybackStatus = playbackState == .playing ? .playing : playbackState == .paused ? .paused : .ended
        Task { @MainActor [weak self] in guard let self, self.player === audioPlayer else { return }; self.onState?(status) }
    }
    /// Forwards end-of-audio to the coordinator on the main actor only if the callback belongs to the
    /// current player instance.
    nonisolated public func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        Task { @MainActor [weak self] in guard let self, self.player === audioPlayer else { return }; self.onEnd?() }
    }
    /// Forwards a current-player decoding or rendering error to the main-actor callback, ignoring replaced
    /// player instances.
    nonisolated public func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        Task { @MainActor [weak self] in guard let self, self.player === audioPlayer else { return }; self.onError?(error) }
    }
    /// Reconnects the equalizer and time-pitch processing nodes after an audio format change, falling back
    /// to the main mixer if nodes are unavailable.
    nonisolated public func audioPlayer(_ audioPlayer: AudioPlayer, reconfigureProcessingGraph engine: AVAudioEngine, with format: AVAudioFormat) -> AVAudioNode {
        // This callback runs inside the engine's graph serialization context, never hop queues here.
        let nodes = engine.attachedNodes
        guard let eq = nodes.compactMap({ $0 as? AVAudioUnitEQ }).first,
              let pitch = nodes.compactMap({ $0 as? AVAudioUnitTimePitch }).first else { return engine.mainMixerNode }
        engine.connect(eq, to: pitch, format: format)
        engine.connect(pitch, to: engine.mainMixerNode, format: format)
        return eq
    }
}
