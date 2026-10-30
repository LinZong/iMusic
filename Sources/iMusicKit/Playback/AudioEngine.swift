import Foundation
import AVFAudio
import SFBAudioEngine

@MainActor
public protocol PlaybackEngine: AnyObject {
    var elapsed: Double? { get }
    var duration: Double? { get }
    var isPlaying: Bool { get }
    var onTrack: ((UUID) -> Void)? { get set }
    var onState: ((PlaybackStatus) -> Void)? { get set }
    var onEnd: (() -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    func play(url: URL, entryID: UUID, position: Double, region: ClosedRange<Double>?, sampleRate: Double) throws
    func enqueue(url: URL, entryID: UUID) throws
    func clearUpcoming()
    func setRate(_ value: Float)
    func setEqualizer(_ gains: [Float], enabled: Bool)
    func pause()
    func resume() throws
    func seek(to seconds: Double) throws
    func stop()
}

@MainActor
public final class SFBPlaybackEngine: NSObject, PlaybackEngine, AudioPlayer.Delegate {
    private var player = AudioPlayer()
    private var equalizer = AVAudioUnitEQ(numberOfBands: 10)
    private var timePitch = AVAudioUnitTimePitch()
    private var identifiers: [ObjectIdentifier: UUID] = [:]
    private var currentDecoderID: ObjectIdentifier?
    public private(set) var preloadedID: UUID?
    private var regionStart: Double = 0
    private var regionLength: Double?
    public var onTrack: ((UUID) -> Void)?
    public var onState: ((PlaybackStatus) -> Void)?
    public var onEnd: (() -> Void)?
    public var onError: ((Error) -> Void)?
    public var elapsed: Double? {
        guard let current = player.currentTime else { return nil }
        if let length = regionLength, length > 0 { return regionStart + current.truncatingRemainder(dividingBy: length) }
        return current
    }
    public var duration: Double? { regionLength == nil ? player.totalTime : nil }
    public var isPlaying: Bool { player.isPlaying }
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
    public func enqueue(url: URL, entryID: UUID) throws {
        guard preloadedID != entryID else { return }
        player.clearQueue()
        let decoder = try AudioDecoder(url: url)
        identifiers[ObjectIdentifier(decoder)] = entryID
        try player.enqueue(decoder); preloadedID = entryID
    }
    public func clearUpcoming() { player.clearQueue(); preloadedID = nil }
    public func pause() { _ = player.pause() }
    public func resume() throws { try player.play() }
    public func stop() { player.delegate = nil; player.stop(); identifiers = [:]; preloadedID = nil }
    public func seek(to seconds: Double) throws {
        guard seconds.isFinite, player.seek(time: max(0, seconds - regionStart)) else { throw MusicError.playback(L10n.text("Seeking is unavailable. Wait for the music to load and try again.")) }
    }
    public func setRate(_ value: Float) { timePitch.rate = min(3, max(0.5, value)) }
    public func setEqualizer(_ gains: [Float], enabled: Bool) {
        equalizer.bypass = !enabled
        for (band, gain) in zip(equalizer.bands, gains) { band.gain = min(12, max(-12, gain)) }
        equalizer.globalGain = enabled ? -max(0, gains.max() ?? 0) : 0
    }
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
    nonisolated public func audioPlayer(_ audioPlayer: AudioPlayer, playbackStateChanged playbackState: AudioPlayer.PlaybackState) {
        let status: PlaybackStatus = playbackState == .playing ? .playing : playbackState == .paused ? .paused : .ended
        Task { @MainActor [weak self] in guard let self, self.player === audioPlayer else { return }; self.onState?(status) }
    }
    nonisolated public func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        Task { @MainActor [weak self] in guard let self, self.player === audioPlayer else { return }; self.onEnd?() }
    }
    nonisolated public func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        Task { @MainActor [weak self] in guard let self, self.player === audioPlayer else { return }; self.onError?(error) }
    }
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
