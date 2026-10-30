import XCTest
@testable import iMusicKit

@MainActor final class CoordinatorTests: XCTestCase {
    func testPausedSeekPreviewAndPersistedPosition() async throws {
        let library = try TestLibrary(), url = try library.fixture(seconds: 4), engine = TestPlaybackEngine()
        _ = await library.importer.importFiles([url]) { _ in }
        let track = try XCTUnwrap(library.store.tracks().first)
        let playback = PlaybackCoordinator(store: library.store, vault: library.vault, engine: engine)
        playback.play([track]); playback.pause()
        playback.beginScrubbing(fraction: 0.5)
        XCTAssertEqual(playback.timeline.displayedTime, 2, accuracy: 0.02)
        XCTAssertTrue(engine.seeks.isEmpty)
        playback.endScrubbing()
        XCTAssertEqual(engine.seeks, [2])
        XCTAssertEqual(playback.status, .paused); XCTAssertEqual(playback.timeline.elapsed, 2, accuracy: 0.12)
        playback.persist()
        XCTAssertEqual(try library.store.setting("playback", as: PlaybackSession.self)?.position ?? 0, 2, accuracy: 0.12)
    }
    func testPauseDuringDownloadCannotAutoplayAfterCompletion() async throws {
        let library = try TestLibrary(), fixture = try library.fixture(seconds: 2), engine = TestPlaybackEngine()
        var track = library.track(); track.assetHash = try MediaVault.digest(fixture); track.duration = 2; track.sampleRate = 48_000
        try library.store.save(track)
        let playback = PlaybackCoordinator(store: library.store, vault: library.vault, engine: engine)
        var token: UUID?
        playback.resolveMissing = { _, value in token = value }
        playback.play([track]); XCTAssertEqual(playback.status, .preparing)
        playback.pause(); try FileManager.default.copyItem(at: fixture, to: library.vault.url(for: track))
        playback.completedDownload(token: try XCTUnwrap(token), error: nil)
        XCTAssertEqual(playback.status, .paused); XCTAssertFalse(playback.isPlaying)
        XCTAssertTrue(engine.plays.isEmpty)
    }
    func testStaleDownloadCannotReplaceNewSelection() throws {
        let library = try TestLibrary(); let first = library.track(title: "First"), second = library.track(title: "Second")
        try library.store.save(first); try library.store.save(second)
        let playback = PlaybackCoordinator(store: library.store, vault: library.vault, engine: TestPlaybackEngine())
        var tokens: [UUID] = []; playback.resolveMissing = { _, token in tokens.append(token) }
        playback.play([first, second]); playback.next()
        playback.completedDownload(token: tokens[0], error: MusicError.missingFile)
        XCTAssertEqual(playback.track?.id, second.id); XCTAssertEqual(playback.status, .preparing)
    }
    func testAddingToEmptyQueueCreatesPausedSelection() throws {
        let library = try TestLibrary(), track = library.track(), engine = TestPlaybackEngine(); try library.store.save(track)
        let playback = PlaybackCoordinator(store: library.store, vault: library.vault, engine: engine)
        playback.enqueue(track); XCTAssertEqual(playback.track?.id, track.id); XCTAssertEqual(playback.status, .paused)
        XCTAssertEqual(playback.session.current?.trackID, track.id); XCTAssertTrue(engine.plays.isEmpty)
    }
    func testResumeCommitsPendingProgressBeforeLoadingRestoredSong() async throws {
        let library = try TestLibrary(), url = try library.fixture(seconds: 4), engine = TestPlaybackEngine()
        _ = await library.importer.importFiles([url]) { _ in }
        let track = try XCTUnwrap(library.store.tracks().first)
        let playback = PlaybackCoordinator(store: library.store, vault: library.vault, engine: engine)
        playback.enqueue(track)
        playback.beginScrubbing(fraction: 0.75)
        playback.resume()
        XCTAssertEqual(engine.plays.first?.position, 3)
        XCTAssertGreaterThanOrEqual(playback.timeline.elapsed, 3)
        XCTAssertEqual(playback.status, .playing)
        playback.pause()
    }
    func testImmediatePauseWinsOverPendingStartCallbacks() async throws {
        let library = try TestLibrary(), url = try library.fixture(seconds: 4), engine = TestPlaybackEngine()
        engine.announcesStartAutomatically = false
        _ = await library.importer.importFiles([url]) { _ in }
        let playback = PlaybackCoordinator(store: library.store, vault: library.vault, engine: engine)
        playback.play(try library.store.tracks()); playback.pause()
        engine.announcePlaying(entryID: try XCTUnwrap(engine.plays.first?.entryID))
        XCTAssertEqual(playback.status, .paused); XCTAssertFalse(playback.isPlaying); XCTAssertFalse(engine.isPlaying)
        XCTAssertGreaterThanOrEqual(engine.pauseCount, 2)
    }
    func testExplicitNextAfterPausePlaysDownloadedSongAndCanResumeAfterInterruption() async throws {
        let library = try TestLibrary(), fixture = try library.fixture(seconds: 4), engine = TestPlaybackEngine()
        let first = library.track(title: "First"), hash = try MediaVault.digest(fixture)
        let second = Track(assetHash: hash, fileExtension: "wav", originalFilename: fixture.lastPathComponent, title: "Second", duration: 4, sampleRate: 48_000)
        try library.store.save(first); try library.store.save(second)
        let playback = PlaybackCoordinator(store: library.store, vault: library.vault, engine: engine)
        var token: UUID?
        playback.resolveMissing = { _, value in token = value }
        playback.play([first, second]); playback.pause(); playback.next()
        try FileManager.default.copyItem(at: fixture, to: library.vault.url(for: second))
        playback.completedDownload(token: try XCTUnwrap(token), error: nil)
        XCTAssertEqual(playback.track?.id, second.id); XCTAssertEqual(playback.status, .playing)
        XCTAssertEqual(engine.plays.map(\.url), [try library.vault.url(for: second)])
        let allowed = playback.saveAndPauseForInterruption()
        playback.resumeAfterInterruption(allowed: allowed)
        XCTAssertEqual(playback.status, .playing); XCTAssertEqual(engine.resumeCount, 1)
        playback.pause()
    }
}

@MainActor final class WiFiServerTests: XCTestCase {
    func testPairingAndStreamingUploadPreserveFilenameAndBytes() async throws {
        let library = try TestLibrary(), server = WiFiUploadServer()
        let received = expectation(description: "received upload")
        let name = "音楽 🎵.wav", data = Data(repeating: 23, count: 130_000)
        await server.start(staging: library.vault.staging) { url in
            XCTAssertEqual(url.lastPathComponent, name); XCTAssertEqual(try? Data(contentsOf: url), data)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent(".complete").path))
            received.fulfill()
        }
        guard let address = server.address, var base = URLComponents(string: address) else { await server.stop(); XCTFail(server.error ?? "No address"); return }
        base.host = "127.0.0.1"; base.path = "/pair"
        var request = URLRequest(url: base.url!); request.httpMethod = "POST"; request.httpBody = Data(server.code.utf8)
        let (tokenData, pairResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((pairResponse as? HTTPURLResponse)?.statusCode, 200)
        let token = String(data: tokenData, encoding: .utf8)!
        base.path = "/upload"; base.queryItems = [URLQueryItem(name: "name", value: name)]
        request = URLRequest(url: base.url!); request.httpMethod = "POST"; request.httpBody = data
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 202)
        await fulfillment(of: [received], timeout: 3); await server.stop(); XCTAssertNil(server.address)
    }
    func testReactBundleAndConfigurationAreServedWithoutInlineScriptsOrPathAccess() async throws {
        let library = try TestLibrary(), server = WiFiUploadServer()
        await server.start(staging: library.vault.staging) { _ in XCTFail("Unexpected upload") }
        guard let address = server.address, var base = URLComponents(string: address) else {
            await server.stop(); XCTFail(server.error ?? "No address"); return
        }
        base.host = "127.0.0.1"; base.path = "/"
        let (htmlData, response) = try await URLSession.shared.data(from: base.url!)
        let html = String(decoding: htmlData, as: UTF8.self), http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Type"), "text/html; charset=utf-8")
        XCTAssertFalse(http.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("unsafe-inline") ?? true)
        XCTAssertTrue(html.contains("type=\"module\"")); XCTAssertFalse(html.contains("{{"))
        let matches = try NSRegularExpression(pattern: #"(?:src|href)="(/upload-[^"]+)""#)
            .matches(in: html, range: NSRange(html.startIndex..., in: html))
        XCTAssertGreaterThanOrEqual(matches.count, 2)
        for match in matches {
            let path = String(html[Range(match.range(at: 1), in: html)!]); base.path = path
            let (data, assetResponse) = try await URLSession.shared.data(from: base.url!)
            let assetHTTP = try XCTUnwrap(assetResponse as? HTTPURLResponse)
            XCTAssertEqual(assetHTTP.statusCode, 200); XCTAssertGreaterThan(data.count, 100)
            XCTAssertEqual(assetHTTP.value(forHTTPHeaderField: "X-Content-Type-Options"), "nosniff")
            XCTAssertTrue(assetHTTP.value(forHTTPHeaderField: "Content-Type")?.hasPrefix(path.hasSuffix(".js") ? "text/javascript" : "text/css") ?? false)
        }
        base.path = "/api/config"
        let (configuration, _) = try await URLSession.shared.data(from: base.url!)
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: configuration) as? [String: Any])
        XCTAssertEqual(config["maxFileSize"] as? Int, WiFiUploadResources.maxFileSize)
        XCTAssertNil(config["token"]); XCTAssertNil(config["code"])
        for path in ["/upload-assets.json", "/upload-missing.js", "/Localizable.strings", "/%2e%2e/Package.swift"] {
            base.percentEncodedPath = path
            let (_, response) = try await URLSession.shared.data(from: base.url!)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404, path)
        }
        base.path = "/"; var crossOrigin = URLRequest(url: base.url!)
        crossOrigin.setValue("http://untrusted.invalid", forHTTPHeaderField: "Origin")
        let (_, forbidden) = try await URLSession.shared.data(for: crossOrigin)
        XCTAssertEqual((forbidden as? HTTPURLResponse)?.statusCode, 403)
        await server.stop()
    }
    func testUploadWithoutPairingIsRejected() async throws {
        let library = try TestLibrary(), server = WiFiUploadServer()
        await server.start(staging: library.vault.staging) { _ in XCTFail("Unauthorized upload accepted") }
        guard let address = server.address, var base = URLComponents(string: address) else { await server.stop(); XCTFail(server.error ?? "No address"); return }
        base.host = "127.0.0.1"; base.path = "/upload"; base.queryItems = [URLQueryItem(name: "name", value: "song.wav")]
        var request = URLRequest(url: base.url!); request.httpMethod = "POST"; request.httpBody = Data("test".utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401); await server.stop()
    }
}

final class SyncCodecTests: XCTestCase {
    func testTenThousandSongPlaylistFitsCloudRecordBudget() throws {
        let library = try TestLibrary(), playlist = Playlist(name: "All songs", entries: (0..<10_000).map { _ in QueueEntry(trackID: UUID()) })
        try library.store.save(playlist)
        let envelope = try XCTUnwrap(library.store.envelopes().first), data = try SyncCodec.encode(envelope)
        XCTAssertLessThan(data.count, 900_000)
        XCTAssertEqual(try SyncCodec.decode(data, compressed: true).payload, envelope.payload)
    }
    func testArtistSplittingIsOptInAndPreservesBandPunctuation() {
        XCTAssertEqual(ArtistCreditParser.names("A, B & C", split: false, separators: ["&"]), ["A, B & C"])
        XCTAssertEqual(ArtistCreditParser.names("A, B & C", split: true, separators: ["&"]), ["A, B", "C"])
    }
}
