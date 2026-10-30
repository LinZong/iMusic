import XCTest

@testable import iMusicKit

final class LibrarySearchTests: XCTestCase {
    func testSongMetadataAndUnicodeQueries() {
        var track = Track(
            assetHash: "test",
            fileExtension: "mp3",
            originalFilename: "夜曲 Live.mp3",
            title: "Café"
        )
        track.albumArtist = "Various Artists"
        track.album = "Concert"
        for query in ["  CAFE\n", "夜曲", "LIVE.MP3", "various", "concert", " \n"] {
            XCTAssertTrue(LibrarySearch.matches(query, track: track), query)
        }
        XCTAssertFalse(LibrarySearch.matches("unrelated", track: track))
    }

    func testPlaylistNameSearchDoesNotSearchItsSongMetadata() {
        let song = Track(
            assetHash: "test",
            fileExtension: "mp3",
            originalFilename: "Moonlight.mp3",
            title: "Moonlight"
        )
        let playlist = Playlist(name: "Morning Run", entries: [QueueEntry(trackID: song.id)])
        XCTAssertTrue(LibrarySearch.matches("moon", track: song))
        XCTAssertFalse(LibrarySearch.matches("moon", in: [playlist.name]))
        XCTAssertTrue(LibrarySearch.matches("morning", in: [playlist.name]))
        XCTAssertFalse(LibrarySearch.matches("morning", track: song))
        XCTAssertTrue(LibrarySearch.isEmpty(" \n"))
    }
}
