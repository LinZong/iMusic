import XCTest
import GRDB
@testable import iMusicKit

final class SchemaTests: XCTestCase {
    func testFreshSchemaReopensAndMaintainsFullTextIndex() throws {
        let library = try TestLibrary(), url = library.root.appendingPathComponent("Library.sqlite")
        let inspection = try DatabaseQueue(path: url.path)
        XCTAssertEqual(try inspection.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }, ["initial-schema"])

        var track = library.track(title: "Aurora")
        try library.store.save(track)
        XCTAssertEqual(try inspection.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM record_search WHERE record_search MATCH 'aurora*'") }, 1)
        track.title = "Nebula"; try library.store.save(track)
        XCTAssertEqual(try inspection.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM record_search WHERE record_search MATCH 'aurora*'") }, 0)
        XCTAssertEqual(try inspection.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM record_search WHERE record_search MATCH 'nebula*'") }, 1)

        let reopened = try LibraryStore(url: url)
        XCTAssertEqual(reopened.deviceID, library.store.deviceID)
        XCTAssertEqual(try reopened.tracks(query: "nebula").map(\.id), [track.id])
        XCTAssertEqual(try inspection.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }, ["initial-schema"])

        try inspection.write { try $0.execute(sql: "DELETE FROM records WHERE id=?", arguments: [track.id.uuidString]) }
        XCTAssertEqual(try inspection.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM record_search") }, 0)
    }
}
