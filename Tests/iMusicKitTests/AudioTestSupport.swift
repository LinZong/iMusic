import XCTest
import AVFAudio
@testable import iMusicKit

enum AudioTestSupport {
    static func requireHardwareAudio() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["IMUSIC_AUDIO_TESTS"] == "1" && environment["IMUSIC_SKIP_AUDIO_TESTS"] != "1",
                          "Hardware audio is opt-in. Run with IMUSIC_AUDIO_TESTS=1; fixtures remain silent.")
    }
}

/// Deterministic coordinator test double. Never constructs an AVAudioEngine or opens an audio device.
@MainActor final class TestPlaybackEngine: PlaybackEngine {
    struct PlayCall {
        /// Managed file URL captured from a playback request without opening an audio device.
        let url: URL
        /// Queue occurrence identity requested by the coordinator.
        let entryID: UUID
        /// Requested start position in seconds captured for deterministic assertions.
        let position: Double
    }
    /// Controllable fake engine clock in seconds; nil models a decoder that has not started.
    var elapsed: Double?
    /// Controllable fake duration in seconds; defaults to the generated four-second fixture.
    var duration: Double? = 4
    /// Fake rendering state updated by playback commands without touching audio hardware.
    var isPlaying = false
    /// Callback announcing the queue-entry identity whose decoder became current.
    var onTrack: ((UUID) -> Void)?
    /// Callback publishing backend playback-state transitions.
    var onState: ((PlaybackStatus) -> Void)?
    /// Callback fired when the current audio reaches its end.
    var onEnd: (() -> Void)?
    /// Callback forwarding decoding or audio-engine failures to the coordinator.
    var onError: ((Error) -> Void)?
    /// Whether play immediately emits onTrack or leaves it pending for callback-race tests.
    var announcesStartAutomatically = true
    /// Recorded play calls used to assert queue identity, file selection, and resume position.
    private(set) var plays: [PlayCall] = []
    /// Recorded seek targets in seconds used to verify preview commits and pause behavior.
    private(set) var seeks: [Double] = []
    /// Number of explicit pause calls received by the fake backend.
    private(set) var pauseCount = 0
    /// Number of explicit resume calls received by the fake backend.
    private(set) var resumeCount = 0

    func play(url: URL, entryID: UUID, position: Double, region: ClosedRange<Double>?, sampleRate: Double) throws {
        plays.append(PlayCall(url: url, entryID: entryID, position: position))
        elapsed = position
        if announcesStartAutomatically { announcePlaying(entryID: entryID) }
    }
    func announcePlaying(entryID: UUID) {
        isPlaying = true; onState?(.playing); onTrack?(entryID)
    }
    func pause() { pauseCount += 1; isPlaying = false; onState?(.paused) }
    func resume() throws { resumeCount += 1; isPlaying = true; onState?(.playing) }
    func seek(to seconds: Double) throws { seeks.append(seconds); elapsed = seconds }
    func stop() { isPlaying = false; elapsed = nil }
    func enqueue(url: URL, entryID: UUID) throws {}
    func clearUpcoming() {}
    func setRate(_ value: Float) {}
    func setEqualizer(_ gains: [Float], enabled: Bool) {}
}

final class SilentFixtureTests: XCTestCase {
    func testGeneratedFixtureHasDurationAndNoAudibleSamples() throws {
        let library = try TestLibrary(), url = try library.fixture(seconds: 0.3)
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(Double(file.length) / file.processingFormat.sampleRate, 0.3, accuracy: 0.001)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        XCTAssertGreaterThan(buffer.frameLength, 0)
        for channel in 0..<Int(buffer.format.channelCount) {
            XCTAssertTrue(UnsafeBufferPointer(start: channels[channel], count: Int(buffer.frameLength)).allSatisfy { $0 == 0 })
        }
    }
}
