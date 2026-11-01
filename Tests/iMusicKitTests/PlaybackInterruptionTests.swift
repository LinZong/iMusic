import XCTest

@testable import iMusicKit

@MainActor
final class PlaybackInterruptionTests: XCTestCase {
    func testBackendPauseBeforeInterruptionPreservesResumeIntentAndOccurrence() async throws {
        let library = try TestLibrary()
        let url = try library.fixture(seconds: 4)
        _ = await library.importer.importFiles([url]) { _ in }
        let engine = TestPlaybackEngine()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: engine
        )
        let track = try XCTUnwrap(library.store.tracks().first)
        playback.play([track, track])
        let currentID = playback.session.currentID
        engine.elapsed = 1.25

        // SFB reports paused before its audio-session interruption notification is delivered.
        engine.isPlaying = false
        engine.onState?(.paused)
        engine.onState?(.paused)
        XCTAssertEqual(playback.status, .paused)
        let allowed = playback.saveAndPauseForInterruption()
        XCTAssertTrue(allowed)
        playback.resumeAfterInterruption(allowed: allowed)

        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(engine.resumeCount, 1)
        XCTAssertEqual(engine.plays.count, 1)
        XCTAssertEqual(playback.session.currentID, currentID)
        XCTAssertEqual(engine.elapsed, 1.25)
        XCTAssertEqual(playback.session.entries.count, 2)
    }

    func testExplicitPauseAfterBackendPauseCancelsInterruptionResumeIntent() async throws {
        let library = try TestLibrary()
        let url = try library.fixture(seconds: 4)
        _ = await library.importer.importFiles([url]) { _ in }
        let engine = TestPlaybackEngine()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: engine
        )
        playback.play(try library.store.tracks())
        engine.isPlaying = false
        engine.onState?(.paused)
        playback.pause()

        let allowed = playback.saveAndPauseForInterruption()
        XCTAssertFalse(allowed)
        playback.resumeAfterInterruption(allowed: true)

        XCTAssertFalse(playback.isPlaying)
        XCTAssertEqual(engine.resumeCount, 0)
    }

    func testSystemDeniedResumeLeavesRetainedDecoderPaused() async throws {
        let library = try TestLibrary()
        let url = try library.fixture(seconds: 4)
        _ = await library.importer.importFiles([url]) { _ in }
        let engine = TestPlaybackEngine()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: engine
        )
        playback.play(try library.store.tracks())
        XCTAssertTrue(playback.saveAndPauseForInterruption())
        playback.resumeAfterInterruption(allowed: false)

        XCTAssertEqual(playback.status, .paused)
        XCTAssertEqual(engine.resumeCount, 0)
        XCTAssertNotNil(engine.elapsed)
        XCTAssertFalse(playback.saveAndPauseForInterruption())
    }

    func testDiscardedDecoderDoesNotReuseEarlierBackendPauseEligibility() async throws {
        let library = try TestLibrary()
        let url = try library.fixture(seconds: 4)
        _ = await library.importer.importFiles([url]) { _ in }
        let engine = TestPlaybackEngine()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: engine
        )
        playback.play(try library.store.tracks())
        engine.isPlaying = false
        engine.onState?(.paused)
        engine.stop()

        let allowed = playback.saveAndPauseForInterruption()
        XCTAssertFalse(allowed)
        playback.resumeAfterInterruption(allowed: allowed)
        XCTAssertEqual(engine.resumeCount, 0)
        XCTAssertEqual(engine.plays.count, 1)
    }
}
