import Observation
import XCTest

@testable import iMusicKit

@MainActor
final class PlaybackIsolationTests: XCTestCase {
    func testClockAdvancesWithoutInvalidatingQueueObserversAndSavesLatestPosition() async throws {
        let fixture = try TestLibrary()
        let url = try fixture.fixture(seconds: 4)
        _ = await fixture.importer.importFiles([url]) { _ in }
        let track = try XCTUnwrap(fixture.store.tracks().first)
        let engine = TestPlaybackEngine()
        let playback = PlaybackCoordinator(
            store: fixture.store,
            vault: fixture.vault,
            engine: engine
        )
        playback.play([track])
        let queueChanged = expectation(description: "Clock ticks must not rebuild transport menus")
        queueChanged.isInverted = true
        withObservationTracking {
            _ = playback.session.entries
            _ = playback.session.repeatMode
            _ = playback.session.isShuffled
        } onChange: {
            queueChanged.fulfill()
        }
        engine.elapsed = 0.75
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(playback.timeline.elapsed, 0.75, accuracy: 0.01)
        playback.persist()
        await fulfillment(of: [queueChanged], timeout: 0.15)
        XCTAssertEqual(
            try fixture.store.setting("playback", as: PlaybackSession.self)?.position,
            0.75
        )
        playback.pause()
    }

    func testBackgroundCheckpointsStayOrderedBeforeExplicitSaves() async throws {
        let fixture = try TestLibrary()
        let firstSaved = expectation(description: "First checkpoint")
        let secondSaved = expectation(description: "Second checkpoint")
        var session = PlaybackSession()
        var event = ListenEvent(trackID: UUID(), startedAt: Date(), seconds: 1)
        session.position = 1
        fixture.store.savePlaybackInBackground(session, event: event) { result in
            XCTAssertFalse(Thread.isMainThread)
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            firstSaved.fulfill()
        }
        session.position = 2
        event.seconds = 2
        fixture.store.savePlaybackInBackground(session, event: event) { result in
            XCTAssertFalse(Thread.isMainThread)
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            secondSaved.fulfill()
        }
        session.position = 3
        try fixture.store.setSetting("playback", value: session)
        await fulfillment(of: [firstSaved, secondSaved], timeout: 2)
        XCTAssertEqual(try fixture.store.setting("playback", as: PlaybackSession.self)?.position, 3)
        XCTAssertEqual(try fixture.store.listenEvents().map(\.seconds), [2])
    }

    func testFailedCheckpointRollsBackItsListeningRecord() async throws {
        let fixture = try TestLibrary()
        var session = PlaybackSession()
        session.position = 12
        try fixture.store.setSetting("playback", value: session)
        session.position = .infinity
        let failed = expectation(description: "Invalid snapshot fails atomically")
        let event = ListenEvent(trackID: UUID(), startedAt: Date(), seconds: 3)
        fixture.store.savePlaybackInBackground(session, event: event) { result in
            XCTAssertFalse(Thread.isMainThread)
            if case .success = result { XCTFail("Invalid JSON must roll back the checkpoint") }
            failed.fulfill()
        }
        await fulfillment(of: [failed], timeout: 2)
        XCTAssertEqual(
            try fixture.store.setting("playback", as: PlaybackSession.self)?.position,
            12
        )
        XCTAssertTrue(try fixture.store.listenEvents().isEmpty)
    }

    func testMenuAvailabilityUsesTheBackgroundLibrarySnapshot() async throws {
        let fixture = try TestLibrary()
        let url = try fixture.fixture()
        _ = await fixture.importer.importFiles([url]) { _ in }
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        await app.library.refresh()
        let track = try XCTUnwrap(app.library.tracks.first)
        XCTAssertTrue(app.library.availableTrackIDs.contains(track.id))
        let managed = try fixture.vault.url(for: track)
        try FileManager.default.removeItem(at: managed)
        // Rendering retains the previous snapshot instead of synchronously probing the disk.
        XCTAssertTrue(app.library.availableTrackIDs.contains(track.id))
        await app.library.refresh()
        XCTAssertFalse(app.library.availableTrackIDs.contains(track.id))
        try FileManager.default.copyItem(at: url, to: managed)
        await app.library.refresh()
        XCTAssertTrue(app.library.availableTrackIDs.contains(track.id))
    }
}
