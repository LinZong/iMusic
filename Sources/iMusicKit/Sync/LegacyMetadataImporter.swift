import CloudKit
import Foundation

/// Imports the previous metadata zone once, without exposing original-file records to older
/// clients.
enum LegacyMetadataImporter {
    /// Reads the entire old zone with change fetching, requiring no CloudKit query indexes.
    static func fetch(store: LibraryStore, database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            let failures = LegacyFetchFailure()
            let zone = CKRecordZone.ID(zoneName: "iMusicMetadata")
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zone],
                configurationsByRecordZoneID: nil
            )
            operation.fetchAllChanges = true
            operation.recordWasChangedBlock = { _, result in
                do {
                    let record = try result.get()
                    guard let data = record["envelope"] as? Data else { return }
                    let envelope = try SyncCodec.decode(
                        data,
                        compressed: record["encoding"] as? String == "lzfse-v1"
                    )
                    guard envelope.id == record.recordID.recordName else {
                        throw MusicError.invalidBackup(
                            L10n.text("The cloud record identifier does not match")
                        )
                    }
                    try store.merge(envelope)
                } catch { failures.record(error) }
            }
            operation.recordZoneFetchResultBlock = { _, result in
                if case .failure(let error) = result,
                    (error as? CKError)?.code != .zoneNotFound
                {
                    failures.record(error)
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                // Zone absence is normal for a new account. Other partial
                // failures were captured above.
                if let error = failures.error {
                    continuation.resume(throwing: error)
                } else if case .failure(let error) = result,
                    (error as? CKError)?.code != .partialFailure,
                    (error as? CKError)?.code != .zoneNotFound
                {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            database.add(operation)
        }
    }
}

/// Lock-protected callback result shared by CloudKit's private operation queues.
private final class LegacyFetchFailure: @unchecked Sendable {
    /// Serializes independent per-record and per-zone callback failures.
    private let lock = NSLock()
    /// First failure retained so an incomplete import is retried rather than marked complete.
    private var first: Error?
    /// Snapshot of the first failure after CloudKit has completed all record callbacks.
    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return first
    }
    /// Records only the first error while allowing CloudKit to drain remaining callbacks.
    func record(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        if first == nil { first = error }
    }
}
