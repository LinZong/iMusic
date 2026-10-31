import Foundation

/// Generates an anonymous integrity report without exposing library names or account data.
struct DiagnosticsExporter: Sendable {
    /// Local record and integrity queries.
    let store: LibraryStore
    /// Managed-media paths and pending journals.
    let vault: MediaVault
    /// Writes counts and integrity results into a temporary JSON file.
    func export() throws -> URL {
        let all = try store.tracks(includeDeleted: true)
        let report: [String: Any] = [
            "application": "iMusic", "version": "1.0.0",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "tracks": all.filter { $0.deletedAt == nil }.count,
            "recycledTracks": all.filter { $0.deletedAt != nil }.count,
            "missingAudioFiles": all.filter { !vault.contains($0) }.count,
            "playlists": try store.playlists().count,
            "pendingChanges": try store.pending().count,
            "databaseIntegrity": try store.integrityIsOK() ? "ok" : "failed",
            "pendingImportJournals": try FileManager.default
                .contentsOfDirectory(
                    atPath: vault.journals.path
                )
                .count,
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "iMusic-Diagnostics-\(UUID().uuidString.prefix(8)).json"
        )
        try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        .write(to: url, options: .atomic)
        return url
    }
}
