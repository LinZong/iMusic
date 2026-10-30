import XCTest
@testable import iMusicKit

/// Opt-in hardware checks use generated silent PCM, never the user's music library.
@MainActor final class AudioIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try AudioTestSupport.requireHardwareAudio()
    }
    func testEngineClockPauseSeekAndRate() async throws {
        let library = try TestLibrary(), url = try library.fixture(seconds: 4)
        let engine = SFBPlaybackEngine()
        var failure: Error?
        engine.onError = { failure = $0 }
        defer { engine.stop() }
        try engine.play(url: url, entryID: UUID(), sampleRate: 48_000)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertNil(failure)
        XCTAssertGreaterThan(engine.elapsed ?? 0, 0.05)
        XCTAssertEqual(engine.duration ?? 0, 4, accuracy: 0.02)
        engine.pause(); let position = engine.elapsed ?? 0
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(engine.elapsed ?? 0, position, accuracy: 0.08)
        try engine.seek(to: 1.5)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(engine.elapsed ?? 0, 1.5, accuracy: 0.12)
        engine.setRate(2); try engine.resume()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertGreaterThan(engine.elapsed ?? 0, 1.8)
    }
    func testEngineIgnoresCallbacksFromReplacedSong() async throws {
        let library = try TestLibrary(), url = try library.fixture(seconds: 2)
        let engine = SFBPlaybackEngine(), first = UUID(), second = UUID()
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
        let library = try TestLibrary(), url = try library.fixture(seconds: 0.4)
        let engine = SFBPlaybackEngine(), first = UUID(), next = UUID()
        var announced: [UUID] = []
        engine.onTrack = { announced.append($0) }
        defer { engine.stop() }
        try engine.play(url: url, entryID: first, sampleRate: 48_000)
        try await Task.sleep(for: .milliseconds(100))
        try engine.enqueue(url: url, entryID: next)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(announced, [first, next])
    }
}
