import Foundation
import GRDB

extension LibraryStore {
    /// Reads device-local file jobs and locators without including them in sync envelopes.
    public func linkedBindings() throws -> [LinkedFileBinding] {
        try database.read { db in
            try Data.fetchAll(db, sql: "SELECT value FROM settings WHERE key LIKE 'linked.item.%'")
                .map { try JSONDecoder().decode(LinkedFileBinding.self, from: $0) }
        }
    }
    /// Reads the local locator for one portable song reference.
    public func linkedBinding(id: UUID, folderID: UUID) throws -> LinkedFileBinding? {
        try setting(
            "linked.item." + folderID.uuidString + "." + id.uuidString,
            as: LinkedFileBinding.self
        )
    }
    /// Persists a recoverable source job without changing synchronized music metadata.
    public func saveLinkedBinding(_ binding: LinkedFileBinding) throws {
        try setSetting(binding.storageKey, value: binding)
    }
}
