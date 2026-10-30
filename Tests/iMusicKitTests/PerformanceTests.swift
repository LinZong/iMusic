import XCTest
@testable import iMusicKit

final class PerformanceTests: XCTestCase {
    func testIndexedAndCJKSearchAcrossTenThousandTracks() throws {
        guard ProcessInfo.processInfo.environment["IMUSIC_PERFORMANCE_TESTS"] == "1" else { throw XCTSkip("Run with IMUSIC_PERFORMANCE_TESTS=1 for the 10,000-track benchmark.") }
        let library = try TestLibrary()
        for index in 0..<10_000 {
            var track = library.track(title: "Track\(index) 音乐\(index)")
            track.assetHash = String(format: "%064x", index); try library.store.save(track)
        }
        var times: [Double] = []
        for query in ["Track9999", "Track5000", "音乐9999", "音乐5000", "Track7000", "音乐7000", "Track1234", "音乐1234", "Track3210", "音乐3210"] {
            let start = ProcessInfo.processInfo.systemUptime
            let result = try library.store.tracks(query: query)
            times.append(ProcessInfo.processInfo.systemUptime - start)
            XCTAssertEqual(result.count, 1)
        }
        let p95 = times.sorted()[Int(Double(times.count - 1) * 0.95)]
        print("iMusic synthetic 10,000-track search P95: \(String(format: "%.2f", p95 * 1000)) ms")
        XCTAssertLessThan(p95, 0.2)
    }
}
