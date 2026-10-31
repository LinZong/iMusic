import Foundation

/// Admits one managed copy through staging, verification, decoding, and a durable journal.
/// The ImportCoordinator actor serializes calls; this type creates no independent tasks.
struct ManagedFileImporter {
    /// Transactional metadata and permanent-deletion queries.
    let store: LibraryStore
    /// Validated managed directories and integrity helpers.
    let vault: MediaVault
    /// Source coordination and bounded copying without metadata responsibility.
    private let copier = CoordinatedFileCopier()
    func importFile(_ source: URL, allowReimport: Bool = true) throws -> (
        imported: Bool, hash: String
    ) {
        let ext = source.pathExtension.lowercased()
        guard ImportCoordinator.extensions.contains(ext) else { throw MusicError.unsupportedFormat }
        let id = UUID()
        let stagedName = UUID().uuidString + "." + ext
        let journalURL = vault.journals.appendingPathComponent(id.uuidString + ".json")
        let stagedURL = vault.staging.appendingPathComponent(stagedName)
        var journal = ImportJournal(
            id: id,
            stagedName: stagedName,
            originalFilename: source.lastPathComponent
        )
        try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
        do {
            try copier.copy(source, to: stagedURL)
            let hash = try MediaVault.digest(stagedURL)
            if var existing = try store.track(hash: hash) {
                if !vault.contains(existing) {
                    try FileManager.default.moveItem(at: stagedURL, to: vault.url(for: existing))
                }
                if existing.deletedAt != nil {
                    existing.deletedAt = nil
                    existing.modifiedAt = Date()
                    try store.save(existing)
                }
                try? FileManager.default.removeItem(at: stagedURL)
                try FileManager.default.removeItem(at: journalURL)
                return (false, hash)
            }
            if !allowReimport, try store.wasPermanentlyDeleted(hash: hash) {
                try FileManager.default.removeItem(at: stagedURL)
                try FileManager.default.removeItem(at: journalURL)
                return (false, hash)
            }
            let stableID = MediaVault.stableID(hash: hash)
            let trackID = try store.wasPermanentlyDeleted(id: stableID) ? UUID() : stableID
            let decoded = try AudioMetadataReader.read(
                stagedURL,
                id: trackID,
                assetHash: hash,
                originalFilename: source.lastPathComponent
            )
            var track = decoded.track
            if let artwork = decoded.artwork {
                let name = hash + ".image"
                try artwork.write(to: vault.artwork.appendingPathComponent(name), options: .atomic)
                track.artworkName = name
            }
            journal.track = track
            try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
            let destination = try vault.url(for: track)
            if FileManager.default.fileExists(atPath: destination.path) {
                guard try MediaVault.digest(destination) == hash else {
                    throw MusicError.importFailed(
                        L10n.text(
                            """
                            An existing library file failed verification. Keep the file and check \
                            your disk.
                            """
                        )
                    )
                }
                try FileManager.default.removeItem(at: stagedURL)
            } else {
                try FileManager.default.moveItem(at: stagedURL, to: destination)
            }
            try store.save(track)
            try FileManager.default.removeItem(at: journalURL)
            return (true, hash)
        } catch {
            // Once metadata is journaled the media can be recovered without reopening its source.
            if journal.track == nil {
                try? FileManager.default.removeItem(at: stagedURL)
                try? FileManager.default.removeItem(at: journalURL)
            }
            throw error
        }
    }
}
