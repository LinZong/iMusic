import XCTest
@testable import iMusicKit

final class TimelineTests: XCTestCase {
    func testUnknownAndInvalidDurationNeverMakesFullBar() {
        for value: Double? in [nil, 0, -.infinity, .infinity, .nan, -1] {
            var timeline = PlaybackTimeline(); timeline.update(elapsed: 7, duration: value)
            XCTAssertFalse(timeline.canSeek); XCTAssertEqual(timeline.fraction, 0); XCTAssertNil(timeline.remaining)
            timeline.beginPreview(fraction: 1); XCTAssertNil(timeline.preview)
        }
    }
    func testClockIsClampedAndFinite() {
        var timeline = PlaybackTimeline(); timeline.update(elapsed: 7, duration: 240)
        XCTAssertEqual(timeline.fraction, 7 / 240.0, accuracy: 0.0001)
        timeline.update(elapsed: 500, duration: 240); XCTAssertEqual(timeline.fraction, 1)
        timeline.update(elapsed: -.infinity, duration: 240); XCTAssertEqual(timeline.elapsed, 0)
        timeline.update(elapsed: -1, duration: 240); XCTAssertEqual(timeline.fraction, 0)
    }
    func testDraggingDoesNotSnapBackToClock() {
        var timeline = PlaybackTimeline(); timeline.update(elapsed: 7, duration: 200)
        timeline.beginPreview(fraction: 0.75); timeline.update(elapsed: 8, duration: 200)
        XCTAssertEqual(timeline.displayedTime, 150); XCTAssertEqual(timeline.elapsed, 8)
        XCTAssertEqual(timeline.finishPreview(), 150); XCTAssertNil(timeline.preview)
    }
    func testPreviewIsBoundedAndCancelable() {
        var timeline = PlaybackTimeline(); timeline.update(elapsed: 7, duration: 200)
        timeline.beginPreview(fraction: 5); XCTAssertEqual(timeline.displayedTime, 200)
        timeline.beginPreview(fraction: -5); XCTAssertEqual(timeline.displayedTime, 0)
        timeline.cancelPreview(); XCTAssertEqual(timeline.displayedTime, 7)
    }
    func testTimeFormatting() {
        XCTAssertEqual(musicTime(nil), "--:--"); XCTAssertEqual(musicTime(.nan), "--:--")
        XCTAssertEqual(musicTime(7), "0:07"); XCTAssertEqual(musicTime(240), "4:00"); XCTAssertEqual(musicTime(3_661), "1:01:01")
    }
}

final class QueueTests: XCTestCase {
    /// Stable per-test song identities used to exercise queue order and repeated occurrences.
    let tracks = [UUID(), UUID(), UUID()]
    func testSequentialStopsAtEnd() {
        var queue = PlaybackSession(); queue.replace(with: tracks, startingAt: 2)
        XCTAssertNil(queue.nextID(automatic: true)); XCTAssertNil(queue.nextID(automatic: false))
    }
    func testRepeatAllWraps() {
        var queue = PlaybackSession(); queue.replace(with: tracks, startingAt: 2); queue.repeatMode = .all
        XCTAssertEqual(queue.nextID(automatic: true), queue.entries.first?.id)
    }
    func testSingleRepeatDoesNotBlockManualNext() {
        var queue = PlaybackSession(); queue.replace(with: tracks); queue.repeatMode = .one
        XCTAssertEqual(queue.nextID(automatic: true), queue.currentID)
        XCTAssertEqual(queue.nextID(automatic: false), queue.entries[1].id)
    }
    func testShuffleKeepsCurrentAndHistory() {
        var queue = PlaybackSession(); queue.replace(with: tracks); let first = queue.currentID
        queue.setShuffle(true); XCTAssertEqual(queue.shuffleOrder.first, first)
        XCTAssertEqual(Set(queue.shuffleOrder).count, 3)
        let next = queue.nextID(automatic: false)!; queue.select(next)
        XCTAssertEqual(queue.previous(), first)
        XCTAssertEqual(Set(queue.shuffleOrder), Set(queue.entries.map(\.id)))
    }
    func testDuplicateTrackHasIndependentQueueIdentity() {
        var queue = PlaybackSession(); queue.replace(with: [tracks[0], tracks[0]])
        XCTAssertNotEqual(queue.entries[0].id, queue.entries[1].id)
        let remaining = queue.entries[1].id; queue.remove(queue.entries[0].id)
        XCTAssertEqual(queue.entries.map(\.id), [remaining])
    }
    func testPlayNextAndAppendPreserveShuffleMembership() {
        var queue = PlaybackSession(); queue.replace(with: tracks); queue.setShuffle(true)
        let extra = UUID(); queue.append(extra, next: true)
        XCTAssertEqual(queue.entries[1].trackID, extra); XCTAssertEqual(queue.shuffleOrder[1], queue.entries[1].id)
        queue.append(UUID()); XCTAssertEqual(Set(queue.entries.map(\.id)), Set(queue.shuffleOrder))
    }
    func testUnknownEntryCannotReplaceCurrent() {
        var queue = PlaybackSession(); queue.replace(with: tracks); let current = queue.currentID
        queue.select(UUID()); XCTAssertEqual(queue.currentID, current)
    }
}

final class MergeTests: XCTestCase {
    func testIndependentFieldChangesConvergeRegardlessOfOrder() throws {
        let first = SyncEnvelope(id: "record", kind: "track", payload: Data(#"{"title":"New title","artist":"Old artist"}"#.utf8), versions: ["title": .init(clock: 2, device: "A"), "artist": .init(clock: 1, device: "A")])
        let second = SyncEnvelope(id: "record", kind: "track", payload: Data(#"{"title":"Old title","artist":"New artist"}"#.utf8), versions: ["title": .init(clock: 1, device: "A"), "artist": .init(clock: 2, device: "B")])
        let a = try first.merged(with: second), b = try second.merged(with: first)
        XCTAssertEqual(a.payload, b.payload)
        let object = try JSONSerialization.jsonObject(with: a.payload) as! [String: String]
        XCTAssertEqual(object["title"], "New title"); XCTAssertEqual(object["artist"], "New artist")
    }
    func testTieUsesStableDeviceOrder() {
        XCTAssertLessThan(FieldVersion(clock: 42, device: "A"), FieldVersion(clock: 42, device: "B"))
    }
    func testRejectsMismatchedRecordIdentity() {
        let a = SyncEnvelope(id: "a", kind: "track", payload: Data("{}".utf8), versions: [:])
        let b = SyncEnvelope(id: "b", kind: "track", payload: Data("{}".utf8), versions: [:])
        XCTAssertThrowsError(try a.merged(with: b))
    }
}
