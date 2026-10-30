import XCTest

@testable import iMusicKit

@MainActor final class PlaybackVolumeTests: XCTestCase {
    func testVolumeIsBoundedAndAppliedWithoutStartingPlayback() throws {
        let library = try TestLibrary()
        let engine = TestPlaybackEngine()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: engine
        )
        XCTAssertEqual(playback.volume, 1)
        XCTAssertEqual(engine.volume, 1)
        playback.setVolume(-0.5)
        XCTAssertEqual(playback.volume, 0)
        XCTAssertTrue(playback.isMuted)
        playback.setVolume(2)
        XCTAssertEqual(playback.volume, 1)
        playback.setVolume(0.37)
        for invalid in [Float.nan, .infinity, -.infinity] { playback.setVolume(invalid) }
        XCTAssertEqual(playback.volume, 0.37, accuracy: 0.0001)
        XCTAssertEqual(engine.volume, 0.37, accuracy: 0.0001)
        XCTAssertTrue(engine.plays.isEmpty)
        XCTAssertEqual(engine.pauseCount, 0)
        XCTAssertEqual(engine.resumeCount, 0)
    }

    func testVolumeAndMuteRestoreFromAnIndependentlyReopenedDatabase() throws {
        let library = try TestLibrary()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: TestPlaybackEngine()
        )
        playback.setVolume(0.28)
        let reopened = try LibraryStore(url: library.root.appendingPathComponent("Library.sqlite"))
        let engine = TestPlaybackEngine()
        let restored = PlaybackCoordinator(store: reopened, vault: library.vault, engine: engine)
        XCTAssertEqual(restored.volume, 0.28, accuracy: 0.0001)
        XCTAssertEqual(engine.volume, 0.28, accuracy: 0.0001)
        restored.toggleMute()
        XCTAssertEqual(restored.volume, 0)
        let thirdStore = try LibraryStore(
            url: library.root.appendingPathComponent("Library.sqlite")
        )
        let thirdEngine = TestPlaybackEngine()
        let muted = PlaybackCoordinator(
            store: thirdStore,
            vault: library.vault,
            engine: thirdEngine
        )
        XCTAssertTrue(muted.isMuted)
        XCTAssertEqual(thirdEngine.volume, 0)
        muted.toggleMute()
        XCTAssertEqual(muted.volume, 0.28, accuracy: 0.0001)
        XCTAssertEqual(thirdEngine.volume, 0.28, accuracy: 0.0001)
    }

    func testMuteSurvivesTrackChangesAndAudioRecoveryWithoutChangingPauseIntent() async throws {
        let library = try TestLibrary()
        let url = try library.fixture(seconds: 2)
        _ = await library.importer.importFiles([url]) { _ in }
        let first = try XCTUnwrap(library.store.tracks().first)
        var second = first
        second.id = UUID()
        second.title = "Second"
        try library.store.save(second)
        let engine = TestPlaybackEngine()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: engine
        )
        playback.setVolume(0.33)
        playback.play([first, second])
        XCTAssertEqual(engine.plays.last?.volume, 0.33)
        let pauses = engine.pauseCount
        playback.toggleMute()
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(engine.pauseCount, pauses)
        playback.next()
        XCTAssertEqual(engine.plays.last?.volume, 0)
        playback.pause()
        playback.recoverAudioService()
        XCTAssertEqual(engine.plays.last?.volume, 0)
        XCTAssertEqual(playback.status, .paused)
        playback.toggleMute()
        XCTAssertEqual(engine.volume, 0.33, accuracy: 0.0001)
        XCTAssertEqual(playback.status, .paused)
    }

    func testVolumeIsDeviceLocalAndDoesNotChangePortableAudioPreferences() throws {
        let library = try TestLibrary()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: TestPlaybackEngine()
        )
        playback.rate = 1.25
        let audio = try library.store.exportSettings()["audio"]
        playback.setVolume(0.42)
        playback.toggleMute()
        XCTAssertEqual(try library.store.exportSettings()["audio"], audio)
        XCTAssertNil(try library.store.exportSettings()["playbackVolume"])
        XCTAssertNotNil(try library.store.setting("playbackVolume", as: [String: Float].self))
    }

    func testInvalidSavedGainIsClampedAndUnmuteAlwaysRestoresAudibleGain() throws {
        let library = try TestLibrary()
        try library.store.setSetting(
            "playbackVolume",
            value: ["volume": Float(-2), "lastAudibleVolume": Float(0)]
        )
        let engine = TestPlaybackEngine()
        let playback = PlaybackCoordinator(
            store: library.store,
            vault: library.vault,
            engine: engine
        )
        XCTAssertTrue(playback.isMuted)
        XCTAssertEqual(engine.volume, 0)
        playback.toggleMute()
        XCTAssertEqual(playback.volume, 1)
        XCTAssertEqual(engine.volume, 1)
    }
}
