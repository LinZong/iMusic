import CloudKit
import Foundation

actor CloudSyncWorker: CKSyncEngineDelegate {
    /// SQLite library store used by this service to read records and persist atomic changes.
    private let store: LibraryStore
    /// Application-owned media layout used to resolve validated files and working directories.
    private let vault: MediaVault
    /// CloudKit container whose private database stores the user's records and assets.
    private let container: CKContainer
    /// Custom record zone for versioned music metadata and listening records.
    private let metadataZone = CKRecordZone.ID(zoneName: "iMusicMetadataV2")
    /// Separate service for content-addressed audio and artwork transfers.
    private let assets: CloudAssetTransfer
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
        assets = CloudAssetTransfer(store: store, vault: vault, identifier: identifier)
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
    /// Uploads managed audio using the independently owned asset-transfer service.
    func upload(_ track: Track) async throws {
        guard engine != nil else { return }
        try await assets.upload(track)
    }
    /// Synchronizes only the referenced artwork, even in metadata-only mode.
    func synchronizeArtwork(_ name: String) async throws {
        guard engine != nil else { return }
        try await assets.synchronizeArtwork(name)
    }
    /// Downloads verified managed audio while retaining transactional deletion guards.
    func download(_ track: Track) async throws {
        guard engine != nil else {
            throw MusicError.unavailable(L10n.text("Authorize the linked folder in Settings."))
        }
        try await assets.download(track)
    }
}
