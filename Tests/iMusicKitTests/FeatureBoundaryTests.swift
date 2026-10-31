import Observation
import XCTest

@testable import iMusicKit

/// Behavior contracts at the new feature and service boundaries; all dependencies stay local.
@MainActor final class FeatureBoundaryTests: XCTestCase {
    /// Collection-specific models keep query scopes independent while sharing live metadata.
    func testTypedCollectionsFilterTheirOwnMetadata() async throws {
        let fixture = try TestLibrary()
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        var alpha = fixture.track(title: "Alpha")
        alpha.artist = "First Artist"
        alpha.album = "First Album"
        alpha.genre = "Rock"
        var beta = fixture.track(title: "Beta")
        beta.artist = "Second Artist"
        beta.album = "Second Album"
        beta.genre = "Jazz"
        try app.store.save(alpha)
        try app.store.save(beta)
        try app.store.save(Playlist(name: "Weekend"))
        await app.library.refresh()
        let artists = ArtistCollectionViewModel(library: app.library, player: app.player)
        let albums = AlbumCollectionViewModel(library: app.library, player: app.player)
        let genres = GenreCollectionViewModel(library: app.library, player: app.player)
        let playlists = PlaylistCollectionViewModel(library: app.library, player: app.player)
        artists.search = "First"
        albums.search = "Second Artist"
        genres.search = "Jazz"
        playlists.search = "Alpha"
        XCTAssertEqual(artists.items, ["First Artist"])
        XCTAssertEqual(albums.items.map(\.id), [beta.id])
        XCTAssertEqual(genres.items, ["Jazz"])
        XCTAssertTrue(playlists.items.isEmpty)
        playlists.search = "Weekend"
        XCTAssertEqual(playlists.items.map(\.name), ["Weekend"])
        XCTAssertEqual(artists.search, "First")
    }

    /// Listening aggregation handles missing metadata without dropping actual heard seconds.
    func testListeningSummarySeparatesRecordsFromPresentation() throws {
        let fixture = try TestLibrary()
        var track = fixture.track(title: "Available")
        track.artist = "Known Artist"
        let events = [
            ListenEvent(trackID: track.id, startedAt: Date(), seconds: 10),
            ListenEvent(trackID: track.id, startedAt: Date(), seconds: 20),
            ListenEvent(trackID: UUID(), startedAt: Date(), seconds: 40),
        ]
        let summary = ListeningSummary(events: events, tracks: [track])
        XCTAssertEqual(summary.totalSeconds, 70)
        XCTAssertEqual(summary.songCount, 2)
        XCTAssertEqual(summary.topTracks.map(\.title), ["Available"])
        XCTAssertEqual(summary.topTracks.first?.seconds, 30)
        XCTAssertEqual(summary.topArtists.map(\.seconds), [40, 30])
    }

    /// Optional online settings require explicit approval and allow immediate revocation.
    func testOnlineMetadataConsentIsIndependentOfOtherSettings() throws {
        let fixture = try TestLibrary()
        let preferences = PreferencesViewModel(store: fixture.store)
        let model = OnlineMetadataSettingsViewModel(preferences: preferences)
        model.enabled = true
        XCTAssertTrue(model.consent)
        XCTAssertFalse(preferences.onlineEnabled)
        model.allow()
        XCTAssertTrue(preferences.onlineEnabled)
        model.enabled = false
        XCTAssertFalse(preferences.onlineEnabled)
        XCTAssertEqual(preferences.appearance, "system")
    }

    /// Cloud settings depend on the narrow service contract and do not contact CloudKit in tests.
    func testCloudSettingsDispatchThroughInjectedService() async throws {
        let service = StubCloudSettingsService()
        let model = CloudSettingsViewModel(cloud: service)
        model.enabled = true
        try await waitUntil { service.enabled }
        XCTAssertEqual(service.enableCount, 1)
        model.syncAudio = true
        XCTAssertTrue(service.syncAudio)
        model.syncNow()
        try await waitUntil { service.syncCount == 1 }
        model.enabled = false
        try await waitUntil { !service.enabled }
        XCTAssertEqual(service.disableCount, 1)
    }

    /// Managed imports can be substituted without a folder, backup, or HTTP implementation.
    func testAudioImportUsesInjectedImporterAndPublishesReport() async throws {
        let fixture = try TestLibrary()
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        let service = StubMusicImporter()
        let activity = LibraryActivity()
        let model = AudioImportViewModel(
            library: app.library,
            activity: activity,
            importer: service
        )
        let source = fixture.root.appendingPathComponent("does-not-need-to-exist.wav")
        model.importURLs([source])
        try await waitUntil { model.importReport != nil }
        let imported = await service.received
        XCTAssertEqual(imported, [source])
        XCTAssertEqual(model.importReport?.imported, 1)
        XCTAssertFalse(activity.importing)
    }

    /// An older snapshot completing after a newer refresh must never replace published records.
    func testSnapshotLoaderSubstitutionPreservesRefreshGenerationGuard() async throws {
        let fixture = try TestLibrary()
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        let reader = ControlledSnapshotReader()
        let library = LibraryViewModel(
            store: app.store,
            vault: app.library.vault,
            importer: app.library.importer,
            playback: app.playback,
            cloud: app.cloud,
            activity: LibraryActivity(),
            preferences: app.preferences,
            snapshotReader: reader
        )
        let first = Task { await library.refresh() }
        try await waitForRequests(1, reader: reader)
        let second = Task { await library.refresh() }
        try await waitForRequests(2, reader: reader)
        let old = fixture.track(title: "Older")
        let new = fixture.track(title: "Newer")
        await reader.resolve(2, snapshot: snapshot([new]))
        await second.value
        await reader.resolve(1, snapshot: snapshot([old]))
        await first.value
        XCTAssertEqual(library.tracks.map(\.title), ["Newer"])
    }

    /// Draft editors substitute cover storage and online lookup independently of record commits.
    func testEditorDependenciesDoNotPersistUntilSaveOrBypassConsent() async throws {
        let fixture = try TestLibrary()
        let app = try AppModel(
            root: fixture.root,
            engine: TestPlaybackEngine(),
            integrateWithSystem: false
        )
        let track = fixture.track(title: "Original")
        try app.store.save(track)
        let online = StubOnlineMetadata()
        let editor = TrackEditorViewModel(
            library: app.library,
            preferences: app.preferences,
            original: track,
            online: online,
            artworkImporter: StubArtworkImporter()
        )
        try editor.setArtwork(Data())
        XCTAssertEqual(editor.draft.artworkName, "stub.image")
        XCTAssertNil(try app.store.track(id: track.id)?.artworkName)
        await editor.searchArtwork()
        let initialCalls = await online.searchCount
        XCTAssertEqual(initialCalls, 0)
        app.preferences.onlineEnabled = true
        await editor.searchArtwork()
        XCTAssertEqual(editor.releases.map(\.id), ["local-release"])
        let playlist = PlaylistEditorViewModel(
            library: app.library,
            playlist: Playlist(name: "Draft"),
            artworkImporter: StubArtworkImporter()
        )
        playlist.importArtwork(.success(fixture.root))
        XCTAssertEqual(playlist.playlist.artworkName, "stub.image")
        XCTAssertTrue(try app.store.playlists().isEmpty)
    }

    /// Pure encoding previews cannot change the persisted library or fail unrelated Unicode tags.
    func testEncodingRepairPreservesUndecodableValues() {
        XCTAssertEqual(
            TagEncodingRepair.preview(["cafÃ©", "音楽"], encodingName: "UTF-8"),
            ["café", "音楽"]
        )
    }

    /// Complete upload ownership transfers to recovery; an interrupted upload is removed.
    func testStagedUploadSeparatesAbortAndCompletionOwnership() throws {
        let fixture = try TestLibrary()
        var interrupted: StagedUpload? = try StagedUpload(
            staging: fixture.vault.staging,
            name: "interrupted.wav"
        )
        let interruptedURL = try XCTUnwrap(interrupted?.url)
        try interrupted?.write(Data([1, 2]))
        interrupted = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: interruptedURL.path))
        var completed: StagedUpload? = try StagedUpload(
            staging: fixture.vault.staging,
            name: "completed.wav"
        )
        try completed?.write(Data([3, 4]))
        let completeURL = try XCTUnwrap(completed?.complete())
        completed = nil
        XCTAssertEqual(try Data(contentsOf: completeURL), Data([3, 4]))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: completeURL.deletingLastPathComponent()
                    .appendingPathComponent(".complete").path
            )
        )
    }

    /// Silent notifications use a weak capability handler rather than a CarPlay application object.
    func testCloudNotificationBridgeDoesNotRetainItsHandler() async {
        let previous = CloudNotificationReceiver.handler
        defer { CloudNotificationReceiver.handler = previous }
        var handler: StubCloudNotificationHandler? = StubCloudNotificationHandler()
        weak var weakHandler = handler
        CloudNotificationReceiver.handler = handler
        let handled = await CloudNotificationReceiver.receive()
        XCTAssertTrue(handled)
        XCTAssertEqual(handler?.calls, 1)
        handler = nil
        XCTAssertNil(weakHandler)
        let unhandled = await CloudNotificationReceiver.receive()
        XCTAssertFalse(unhandled)
    }

    /// Creates an immutable snapshot without I/O for controlled-loader tests.
    private func snapshot(_ tracks: [Track]) -> LibrarySnapshot {
        LibrarySnapshot(
            tracks: tracks,
            playlists: [],
            events: [],
            folders: [],
            bindings: [],
            purgedTracks: [],
            availableTrackIDs: []
        )
    }
    /// Waits for asynchronous command publication without sleeping for a fixed wall-clock delay.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }
    /// Waits until both refreshes have crossed the injected asynchronous boundary.
    private func waitForRequests(_ count: Int, reader: ControlledSnapshotReader) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await reader.requestCount < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let actual = await reader.requestCount
        XCTAssertEqual(actual, count)
    }
}

/// Controllable snapshot source proving the publication layer is independent of SQLite timing.
private actor ControlledSnapshotReader: LibrarySnapshotReading {
    /// Number of loads started by the publication owner.
    private(set) var requestCount = 0
    /// Pending continuations resolved explicitly by each test.
    private var pending: [Int: CheckedContinuation<LibrarySnapshot, Error>] = [:]
    /// Suspends one load until the test supplies an immutable snapshot.
    func load() async throws -> LibrarySnapshot {
        requestCount += 1
        let request = requestCount
        return try await withCheckedThrowingContinuation { pending[request] = $0 }
    }
    /// Completes one load in a deliberately chosen order.
    func resolve(_ request: Int, snapshot: LibrarySnapshot) {
        pending.removeValue(forKey: request)?.resume(returning: snapshot)
    }
}

/// Local managed-import substitution with no source filesystem dependency.
private actor StubMusicImporter: MusicFileImporting {
    /// URLs routed to this managed-copy service.
    private(set) var received: [URL] = []
    /// Publishes one deterministic completion without creating audio hardware.
    func importFiles(
        _ urls: [URL],
        skipUnchanged: Bool,
        progress: @escaping @Sendable (ImportProgress) -> Void
    ) async -> ImportProgress {
        received = urls
        var result = ImportProgress()
        result.completed = urls.count
        result.total = urls.count
        result.imported = urls.count
        progress(result)
        return result
    }
}

/// Local cloud-setting substitution with observable state and explicit command counts.
@MainActor @Observable
private final class StubCloudSettingsService: CloudSettingsService {
    /// Allows cloud controls in this isolated test.
    let available = true
    /// Simulated synchronization consent.
    var enabled = false
    /// Simulated operation activity.
    var busy = false
    /// Simulated service status.
    var message = "Local stub"
    /// Simulated portable media-sync preference.
    var syncAudio = false
    /// Number of explicit enable actions.
    var enableCount = 0
    /// Number of explicit disable actions.
    var disableCount = 0
    /// Number of explicit synchronize actions.
    var syncCount = 0
    /// Records enable without contacting CloudKit.
    func enable(allowAccountChange: Bool) async {
        enabled = true
        enableCount += 1
    }
    /// Records disable without contacting CloudKit.
    func disable() async {
        enabled = false
        disableCount += 1
    }
    /// Records a requested synchronization.
    func sync() async { syncCount += 1 }
}

/// Cover admission substitution independent of file access and image decoders.
private struct StubArtworkImporter: ArtworkImporting {
    /// Returns a managed filename without writing any bytes.
    func store(_ data: Data) throws -> String { "stub.image" }
    /// Returns a managed filename without reading the supplied URL.
    func importFile(_ url: URL) throws -> String { "stub.image" }
}

/// Consent-gated lookup substitution with no network access.
private actor StubOnlineMetadata: OnlineMetadataProviding {
    /// Number of album lookups performed by the editor.
    private(set) var searchCount = 0
    /// Returns one deterministic local release.
    func search(album: String, artist: String) async throws -> [OnlineRelease] {
        searchCount += 1
        return [OnlineRelease(id: "local-release", title: "Local", date: nil, country: nil)]
    }
    /// Returns unused image bytes without network access.
    func artwork(for release: OnlineRelease) async throws -> Data { Data() }
}

/// Background-notification capability with no cloud transport or vehicle dependency.
@MainActor
private final class StubCloudNotificationHandler: CloudNotificationHandling {
    /// Number of routed silent notifications.
    var calls = 0
    /// Records a notification without contacting CloudKit.
    func handleCloudNotification() async -> Bool {
        calls += 1
        return true
    }
}
