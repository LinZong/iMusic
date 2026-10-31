import CloudKit
import Foundation
import Observation

@MainActor @Observable
public final class CloudSyncCoordinator {
    /// Whether a CloudKit worker has been started for the current account.
    public private(set) var enabled = false
    /// Whether an enable or synchronization operation is in progress.
    public private(set) var busy = false
    /// Localized status or error shown in iCloud settings.
    public private(set) var message = L10n.text("Not Enabled")
    /// Whether explicit synchronization also uploads locally available audio assets.
    public var syncAudio = false
    /// Optional provisioned CloudKit container identifier supplied by the app build.
    public let containerIdentifier: String?
    /// Whether this build declares a nonempty CloudKit container identifier.
    public var available: Bool { containerIdentifier?.isEmpty == false }
    /// SQLite library store used by this service to read records and persist atomic changes.
    private let store: LibraryStore
    /// Application-owned media layout used to resolve validated files and working directories.
    private let vault: MediaVault
    /// Actor owning the current account's CloudKit engine and asset operations.
    private var worker: CloudSyncWorker?
    /// Callback requesting a native library refresh after synchronized data changes.
    public var onChange: (() -> Void)?
    /// Creates a disabled sync coordinator for an optional provisioned container; initialization
    /// does not start network operations.
    public init(store: LibraryStore, vault: MediaVault, containerIdentifier: String?) {
        self.store = store
        self.vault = vault
        self.containerIdentifier = containerIdentifier
    }
    /// Validates the configured iCloud account, starts its isolated sync worker, persists consent,
    /// and performs initial synchronization. Account changes require explicit authorization when
    /// requested by the caller.
    public func enable(allowAccountChange: Bool = true) async {
        guard let identifier = containerIdentifier, !identifier.isEmpty else {
            message = L10n.text(
                """
                iCloud is not configured in this build. Use a developer team with iCloud access \
                and a Cloud build configuration.
                """
            )
            return
        }
        busy = true
        defer { busy = false }
        do {
            let worker = CloudSyncWorker(store: store, vault: vault, identifier: identifier) {
                [weak self] text, changed, accountChanged in
                Task { @MainActor in
                    guard let self else { return }
                    self.message = text
                    if accountChanged {
                        self.enabled = false
                        self.worker = nil
                    }
                    if changed { self.onChange?() }
                }
            }
            try await worker.start(allowAccountChange: allowAccountChange)
            self.worker = worker
            enabled = true
            try store.setSetting("cloudEnabled", value: true)
            await sync()
        } catch {
            message = error.localizedDescription
            enabled = false
        }
    }
    /// Stops the active sync worker and persists the disabled preference while preserving the local
    /// library.
    public func disable() async {
        let old = worker
        worker = nil
        enabled = false
        message = L10n.text("Not Enabled")
        try? store.setSetting("cloudEnabled", value: false)
        await old?.stop()
    }
    /// Synchronizes versioned metadata and referenced artwork, optionally uploading local audio
    /// when syncAudio is enabled; publishes status and refresh callbacks.
    public func sync() async {
        guard let worker else { return }
        busy = true
        message = L10n.text("Syncing…")
        defer { busy = false }
        do {
            try await worker.synchronize()
            let tracks = try store.tracks()
            let playlists = try store.playlists()
            let artworkNames = Set(
                tracks.compactMap(\.artworkName) + playlists.compactMap(\.artworkName)
            )
            // A metadata-only library still needs its artwork. Never fetch audio here.
            for name in artworkNames { try await worker.synchronizeArtwork(name) }
            if syncAudio {
                let tracks = try store.tracks()
                for track in tracks where vault.contains(track) {
                    try Task.checkCancellation()
                    try await worker.upload(track)
                }
            }
            message = L10n.text("Sync Complete")
            onChange?()
        } catch { message = error.localizedDescription }
    }
    /// Explicitly downloads a song's verified cloud assets and publishes completion or an error
    /// through the coordinator status.
    public func download(_ track: Track) async {
        guard let worker else {
            message = L10n.text("Enable iCloud sync first.")
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await worker.download(track)
            message = L10n.text("Download Complete")
            onChange?()
        } catch { message = error.localizedDescription }
    }
    /// Downloads verified assets needed by playback, throwing when synchronization is disabled or
    /// the cloud operation fails.
    public func downloadForPlayback(_ track: Track) async throws {
        guard let worker, enabled else { throw MusicError.missingFile }
        try await worker.download(track)
        onChange?()
    }
}

private actor CloudSyncWorker: CKSyncEngineDelegate {
    /// SQLite library store used by this service to read records and persist atomic changes.
    private let store: LibraryStore
    /// Application-owned media layout used to resolve validated files and working directories.
    private let vault: MediaVault
    /// CloudKit container whose private database stores the user's records and assets.
    private let container: CKContainer
    /// Custom record zone for versioned music metadata and listening records.
    private let metadataZone = CKRecordZone.ID(zoneName: "iMusicMetadataV2")
    /// Separate custom record zone for content-addressed audio and artwork assets.
    private let assetZone = CKRecordZone.ID(zoneName: "iMusicAssets")
    /// CloudKit synchronization engine; nil until the account is validated and the worker starts.
    private var engine: CKSyncEngine?
    /// Account-specific settings prefix that isolates cached sync state between iCloud users.
    private var namespace = ""
    /// Validated iCloud user record identity for the active worker.
    private var accountID: CKRecord.ID?
    /// Outbox generations attached to outgoing records, used for safe acknowledgements.
    private var submitted: [String: Int64] = [:]
    /// Archived CloudKit system fields used to preserve record change tags during uploads.
    private var systemFields: [String: Data] = [:]
    /// Thread-safe status and change callback delivered to the main-actor coordinator.
    private let notify: @Sendable (String, Bool, Bool) -> Void
    init(
        store: LibraryStore,
        vault: MediaVault,
        identifier: String,
        notify: @escaping @Sendable (String, Bool, Bool) -> Void
    ) {
        self.store = store
        self.vault = vault
        container = CKContainer(identifier: identifier)
        self.notify = notify
    }
    func start(allowAccountChange: Bool) async throws {
        guard try await container.accountStatus() == .available else {
            throw MusicError.unavailable(L10n.text("Sign in to iCloud in System Settings."))
        }
        let user = try await container.userRecordID()
        accountID = user
        let bindingKey = "cloud.boundAccount." + (container.containerIdentifier ?? "")
        if let previous = try store.setting(bindingKey, as: String.self),
            previous != user.recordName, !allowAccountChange
        {
            throw MusicError.unavailable(
                L10n.text(
                    """
                    The account changed. Your local library has been preserved. Explicitly enable \
                    sync again to link the new account.
                    """
                )
            )
        }
        try store.setSetting(bindingKey, value: user.recordName)
        namespace = "cloud.v2.\(container.containerIdentifier ?? "").\(user.recordName)"
        // Import the old zone once; original-file records are written only into the v2 zone.
        if try store.setting(namespace + ".legacyImported", as: Bool.self) != true {
            try await LegacyMetadataImporter.fetch(
                store: store,
                database: container.privateCloudDatabase
            )
            try store.setSetting(namespace + ".legacyImported", value: true)
        }
        // An account change needs an explicit enable action; local data is retained.
        let state = try store.setting(
            namespace + ".state",
            as: CKSyncEngine.State.Serialization.self
        )
        systemFields = try store.setting(namespace + ".fields", as: [String: Data].self) ?? [:]
        var config = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: state,
            delegate: self
        )
        config.automaticallySync = true
        let engine = CKSyncEngine(config)
        self.engine = engine
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: metadataZone))])
        try store.markAllForSync()
    }
    func stop() async {
        let old = engine
        engine = nil
        await old?.cancelOperations()
    }
    func synchronize() async throws {
        guard let engine else { return }
        let user = try await container.userRecordID()
        guard user == accountID else {
            await stop()
            notify(
                L10n.text("The account changed. Turn sync off and explicitly enable it again."),
                false,
                true
            )
            return
        }
        try await engine.fetchChanges(
            CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([metadataZone]))
        )
        let pending = try store.pending()
        engine.state.add(
            pendingRecordZoneChanges: pending.map {
                .saveRecord(CKRecord.ID(recordName: $0.0.id, zoneID: metadataZone))
            }
        )
        try await engine.sendChanges()
    }
    func nextFetchChangesOptions(
        _ context: CKSyncEngine.FetchChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([metadataZone]))
    }
    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard syncEngine === engine else { return nil }
        do {
            let records = try store.pending()
                .filter {
                    context.options.scope.contains(
                        CKRecord.ID(recordName: $0.0.id, zoneID: metadataZone)
                    )
                }
                .prefix(100)
            return try CKSyncEngine.RecordZoneChangeBatch(
                recordsToSave: records.map { envelope, generation in
                    let record: CKRecord
                    if let data = systemFields[envelope.id] {
                        let coder = try NSKeyedUnarchiver(forReadingFrom: data)
                        coder.requiresSecureCoding = true
                        record =
                            CKRecord(coder: coder)
                            ?? CKRecord(
                                recordType: "LibraryRecord",
                                recordID: CKRecord.ID(recordName: envelope.id, zoneID: metadataZone)
                            )
                        coder.finishDecoding()
                    } else {
                        record = CKRecord(
                            recordType: "LibraryRecord",
                            recordID: CKRecord.ID(recordName: envelope.id, zoneID: metadataZone)
                        )
                    }
                    record["envelope"] = try SyncCodec.encode(envelope) as CKRecordValue
                    record["encoding"] = "lzfse-v1" as CKRecordValue
                    submitted[envelope.id] = generation
                    return record
                }
            )
        } catch {
            notify(error.localizedDescription, false, false)
            return nil
        }
    }
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard engine === syncEngine else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                try store.setSetting(namespace + ".state", value: update.stateSerialization)
            case .accountChange(let change):
                switch change.changeType {
                case .signIn(let current) where current == accountID: break
                default:
                    engine = nil
                    try store.setSetting("cloudEnabled", value: false)
                    notify(
                        L10n.text(
                            """
                            The account changed. Your local library has been preserved. Explicitly \
                            enable sync again.
                            """
                        ),
                        false,
                        true
                    )
                }
            case .fetchedRecordZoneChanges(let changes):
                for modification in changes.modifications { try receive(modification.record) }
                // App deletions are synced as tombstones. Physical server deletions never erase
                // originals.
                try store.setSetting(namespace + ".fields", value: systemFields)
                notify(L10n.text("Cloud Changes Received"), true, false)
            case .sentRecordZoneChanges(let changes):
                for record in changes.savedRecords {
                    cacheFields(record)
                    if let generation = submitted.removeValue(forKey: record.recordID.recordName) {
                        try store.acknowledge(
                            id: record.recordID.recordName,
                            generation: generation
                        )
                    }
                }
                for failed in changes.failedRecordSaves {
                    if failed.error.code == .serverRecordChanged,
                        let server = failed.error.userInfo[CKRecordChangedErrorServerRecordKey]
                            as? CKRecord
                    {
                        try receive(server)
                        syncEngine.state.add(pendingRecordZoneChanges: [
                            .saveRecord(server.recordID)
                        ])
                    } else if failed.error.code == .zoneNotFound {
                        syncEngine.state.add(pendingDatabaseChanges: [
                            .saveZone(CKRecordZone(zoneID: metadataZone))
                        ])
                        syncEngine.state.add(pendingRecordZoneChanges: [
                            .saveRecord(failed.record.recordID)
                        ])
                    } else {
                        notify(failed.error.localizedDescription, false, false)
                    }
                }
                try store.setSetting(namespace + ".fields", value: systemFields)
            default: break
            }
        } catch { notify(error.localizedDescription, false, false) }
    }
    private func receive(_ record: CKRecord) throws {
        guard record.recordID.zoneID == metadataZone, let data = record["envelope"] as? Data else {
            return
        }
        let envelope = try SyncCodec.decode(
            data,
            compressed: record["encoding"] as? String == "lzfse-v1"
        )
        guard envelope.id == record.recordID.recordName else {
            throw MusicError.invalidBackup(L10n.text("The cloud record identifier does not match"))
        }
        try store.merge(envelope)
        cacheFields(record)
    }
    private func cacheFields(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        systemFields[record.recordID.recordName] = coder.encodedData
    }
    func upload(_ track: Track) async throws {
        guard engine != nil, !track.isLinked, let hash = track.assetHash else { return }
        let db = container.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: hash, zoneID: assetZone)
        if try await exists(recordID) { return }
        _ = try await db.save(CKRecordZone(zoneID: assetZone))
        let source = try vault.url(for: track)
        guard try MediaVault.digest(source) == track.assetHash else {
            throw MusicError.invalidBackup(L10n.text("Verification failed before upload"))
        }
        let record = CKRecord(recordType: "AudioAsset", recordID: recordID)
        record["audio"] = CKAsset(fileURL: source)
        record["extension"] = track.fileExtension as CKRecordValue
        _ = try await db.save(record)
    }
    private func exists(_ id: CKRecord.ID) async throws -> Bool {
        let result = try await container.privateCloudDatabase.records(for: [id], desiredKeys: [])
        guard let entry = result[id] else { return false }
        switch entry {
        case .success: return true
        case .failure(let error):
            if let error = error as? CKError,
                error.code == .unknownItem || error.code == .zoneNotFound
            {
                return false
            }
            throw error
        }
    }
    func synchronizeArtwork(_ name: String) async throws {
        guard engine != nil, let source = vault.artworkURL(name) else { return }
        let id = CKRecord.ID(recordName: "art." + name, zoneID: assetZone)
        guard FileManager.default.fileExists(atPath: source.path) else {
            do {
                let record = try await container.privateCloudDatabase.record(for: id)
                guard let asset = record["artwork"] as? CKAsset, let temporary = asset.fileURL,
                    (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max)
                        <= 20_000_000
                else { return }
                try FileManager.default.copyItem(at: temporary, to: source)
            } catch let error as CKError
                where error.code == .unknownItem || error.code == .zoneNotFound
            {
                // Another device may not have uploaded the referenced asset yet.
            }
            return
        }
        if try await exists(id) { return }
        let db = container.privateCloudDatabase
        _ = try await db.save(CKRecordZone(zoneID: assetZone))
        let record = CKRecord(recordType: "ArtworkAsset", recordID: id)
        record["artwork"] = CKAsset(fileURL: source)
        _ = try await db.save(record)
    }
    func download(_ track: Track) async throws {
        guard engine != nil, !track.isLinked, let hash = track.assetHash else {
            throw MusicError.unavailable(L10n.text("Authorize the linked folder in Settings."))
        }
        let record = try await container.privateCloudDatabase.record(
            for: CKRecord.ID(recordName: hash, zoneID: assetZone)
        )
        guard let asset = record["audio"] as? CKAsset, let source = asset.fileURL,
            try MediaVault.digest(source) == track.assetHash
        else { throw MusicError.invalidBackup(L10n.text("Downloaded music failed verification")) }
        let destination = try vault.url(for: track)
        try store.withAvailableTrack(track.id) { _ in
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: source, to: destination)
            }
            try MediaVault.protectPersistentFile(destination)
        }
        if let name = track.artworkName, let destination = vault.artworkURL(name),
            !FileManager.default.fileExists(atPath: destination.path),
            let artworkRecord = try? await container.privateCloudDatabase.record(
                for: CKRecord.ID(recordName: "art." + name, zoneID: assetZone)
            ),
            let asset = artworkRecord["artwork"] as? CKAsset, let source = asset.fileURL
        {
            try store.withAvailableTrack(track.id) { _ in
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.copyItem(at: source, to: destination)
                }
            }
        }
    }
}
