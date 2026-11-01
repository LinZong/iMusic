import AVFAudio
import SFBAudioEngine
import XCTest

@testable import iMusicKit

/// Opt-in hardware checks use generated silent PCM, never the user's music library.
@MainActor final class AudioIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try AudioTestSupport.requireHardwareAudio()
    }
    func testUpstreamPauseSuspendsIOAndRetainsDecoderAcrossRapidResume() async throws {
        let library = try TestLibrary()
        let url = try library.fixture(seconds: 8)
        let player = AudioPlayer()
        defer { player.stop() }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback)
        try session.setActive(true)
        #endif
        try player.play(url)
        try await Task.sleep(for: .milliseconds(350))
        let decoder = try XCTUnwrap(player.currentDecoder)
        let identity = ObjectIdentifier(decoder)
        try player.enqueue(url)
        XCTAssertFalse(player.queueIsEmpty)

        for _ in 0..<12 {
            player.pause()
            try player.play()
        }
        player.pause()
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while player.engineIsRunning && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertFalse(player.engineIsRunning)
        XCTAssertTrue(player.isPaused)
        XCTAssertFalse(player.queueIsEmpty)
        XCTAssertEqual(player.currentDecoder.map(ObjectIdentifier.init), identity)
        let pausedPosition = try XCTUnwrap(player.currentTime)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(try XCTUnwrap(player.currentTime), pausedPosition, accuracy: 0.02)

        try player.play()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(player.engineIsRunning)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.currentDecoder.map(ObjectIdentifier.init), identity)
        XCTAssertGreaterThan(try XCTUnwrap(player.currentTime), pausedPosition + 0.1)
    }
    func testRegionPauseResumePreservesLoopAndOccurrence() async throws {
        let library = try TestLibrary()
        let url = try library.fixture(seconds: 4)
        let engine = SFBPlaybackEngine()
        let occurrence = UUID()
        var announced: [UUID] = []
        var failure: Error?
        engine.onTrack = { announced.append($0) }
        engine.onError = { failure = $0 }
        defer { engine.stop() }
        try engine.play(
            url: url,
            entryID: occurrence,
            region: 1...2,
            sampleRate: 48_000
        )
        try await Task.sleep(for: .milliseconds(350))
        engine.pause()
        try await Task.sleep(for: .milliseconds(200))
        let position = try XCTUnwrap(engine.elapsed)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(try XCTUnwrap(engine.elapsed), position, accuracy: 0.02)

        try engine.resume()
        try await Task.sleep(for: .milliseconds(850))
        let resumed = try XCTUnwrap(engine.elapsed)
        XCTAssertTrue((1...2).contains(resumed))
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(announced, [occurrence])
        XCTAssertNil(failure)
    }
    func testEngineClockPauseSeekAndRate() async throws {
        let library = try TestLibrary()
        let url = try library.fixture(seconds: 4)
        let engine = SFBPlaybackEngine()
        var failure: Error?
        engine.onError = { failure = $0 }
        defer { engine.stop() }
        try engine.play(url: url, entryID: UUID(), sampleRate: 48_000)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertNil(failure)
        XCTAssertGreaterThan(engine.elapsed ?? 0, 0.05)
        XCTAssertEqual(engine.duration ?? 0, 4, accuracy: 0.02)
        engine.pause()
        let position = engine.elapsed ?? 0
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(engine.elapsed ?? 0, position, accuracy: 0.08)
        try engine.seek(to: 1.5)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(engine.elapsed ?? 0, 1.5, accuracy: 0.12)
        engine.setRate(2)
        try engine.resume()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertGreaterThan(engine.elapsed ?? 0, 1.8)
    }
    func testEngineIgnoresCallbacksFromReplacedSong() async throws {
        let library = try TestLibrary()
        let url = try library.fixture(seconds: 2)
        let engine = SFBPlaybackEngine()
        let first = UUID()
        let second = UUID()
        var announced: [UUID] = []
        engine.onTrack = { announced.append($0) }
        defer { engine.stop() }
        try engine.play(url: url, entryID: first, sampleRate: 48_000)
        try engine.play(url: url, entryID: second, position: 1, sampleRate: 48_000)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(announced.last, second)
        XCTAssertFalse(announced.contains(first))
        XCTAssertGreaterThan(engine.elapsed ?? 0, 1)
    }
    func testPreloadedSongAnnouncesItsOwnIdentity() async throws {
        let library = try TestLibrary()
        let url = try library.fixture(seconds: 0.4)
        let engine = SFBPlaybackEngine()
        let first = UUID()
        let next = UUID()
        var announced: [UUID] = []
        engine.onTrack = { announced.append($0) }
        defer { engine.stop() }
        try engine.play(url: url, entryID: first, sampleRate: 48_000)
        try await Task.sleep(for: .milliseconds(100))
        try engine.enqueue(url: url, entryID: next)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(announced, [first, next])
    }

    func testRenderingContinuesWhileTheMainActorIsBusy() async throws {
        let library = try TestLibrary()
        let url = try library.fixture(seconds: 4)
        let engine = SFBPlaybackEngine()
        var failure: Error?
        engine.onError = { failure = $0 }
        defer { engine.stop() }
        try engine.play(url: url, entryID: UUID(), sampleRate: 48_000)
        try await Task.sleep(for: .milliseconds(300))
        let before = try XCTUnwrap(engine.elapsed)
        let started = ProcessInfo.processInfo.systemUptime
        // Deliberately occupy the UI actor longer than the decoder ring buffer can cover.
        // Rendering and decoder refill must not depend on the ticker or queued UI callbacks.
        let formatter = NumberFormatter()
        while ProcessInfo.processInfo.systemUptime - started < 0.6 {
            _ = formatter.string(from: 1_234.567)
        }
        let wallTime = ProcessInfo.processInfo.systemUptime - started
        let advanced = try XCTUnwrap(engine.elapsed) - before
        XCTAssertNil(failure)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(advanced, wallTime, accuracy: 0.12)
    }
}
