import CloudKit
import Foundation

/// Owns verified audio/artwork transfer independently of metadata conflict resolution
/// and synchronization outbox state.
actor CloudAssetTransfer {
    /// Transactional admission guard prevents a late download from reviving deleted audio.
    private let store: LibraryStore
    /// Validated managed-media destinations.
    private let vault: MediaVault
    /// CloudKit container used only for asset records.
    private let container: CKContainer
    /// Asset zone remains unchanged for existing libraries.
    private let assetZone = CKRecordZone.ID(zoneName: "iMusicAssets")
    /// Creates an asset-only transport for the selected container.
    init(store: LibraryStore, vault: MediaVault, identifier: String) {
        self.store = store
        self.vault = vault
        container = CKContainer(identifier: identifier)
    }
    func upload(_ track: Track) async throws {
        guard !track.isLinked, let hash = track.assetHash else { return }
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
        guard let source = vault.artworkURL(name) else { return }
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
        guard !track.isLinked, let hash = track.assetHash else {
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
