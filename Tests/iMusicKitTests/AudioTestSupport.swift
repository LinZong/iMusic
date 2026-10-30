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
        let url: URL
        let entryID: UUID
        let position: Double
    }
    var elapsed: Double?
    var duration: Double? = 4
    var isPlaying = false
    var onTrack: ((UUID) -> Void)?
    var onState: ((PlaybackStatus) -> Void)?
    var onEnd: (() -> Void)?
    var onError: ((Error) -> Void)?
    var announcesStartAutomatically = true
    private(set) var plays: [PlayCall] = []
    private(set) var seeks: [Double] = []
    private(set) var pauseCount = 0
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
