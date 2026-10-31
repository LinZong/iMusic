import Foundation

/// Replays interrupted staging operations without scanning external original-file folders.
struct ManagedImportRecovery {
    /// Record validation and recovered metadata commits.
    let store: LibraryStore
    /// Durable staging and journal locations.
    let vault: MediaVault
    /// Same one-file admission path used by ordinary imports.
    let importer: ManagedFileImporter
    /// Replays durable import journals and pending deletion cleanup after an interrupted run;
    /// returns recoverable error messages for presentation.
    func recover() -> [String] {
        var errors: [String] = []
        for directory
            in (try? FileManager.default.contentsOfDirectory(
                at: vault.staging,
                includingPropertiesForKeys: nil
            )) ?? [] where directory.lastPathComponent.hasPrefix("upload-")
        {
            let marker = directory.appendingPathComponent(".complete")
            guard let data = try? Data(contentsOf: marker),
                let name = try? JSONDecoder().decode(String.self, from: data), !name.contains("/"),
                !name.contains("\\")
            else { continue }
            do {
                _ = try importer.importFile(
                    directory.appendingPathComponent(name),
                    allowReimport: false
                )
                try FileManager.default.removeItem(at: directory)
            } catch {
                errors.append(
                    L10n.text(
                        "format.import.wifi_recovery",
                        String(describing: error.localizedDescription)
                    )
                )
            }
        }
        for url
            in (try? FileManager.default.contentsOfDirectory(
                at: vault.journals,
                includingPropertiesForKeys: nil
            )) ?? []
        {
            do {
                let journal = try JSONDecoder()
                    .decode(ImportJournal.self, from: Data(contentsOf: url))
                guard !journal.stagedName.contains("/"), !journal.stagedName.contains("\\") else {
                    throw MusicError.invalidBackup(L10n.text("Invalid import journal"))
                }
                let staged = vault.staging.appendingPathComponent(journal.stagedName)
                guard let track = journal.track else {
                    try? FileManager.default.removeItem(at: staged)
                    try FileManager.default.removeItem(at: url)
                    errors.append(
                        L10n.text(
                            "format.import.copy_incomplete",
                            String(describing: journal.originalFilename)
                        )
                    )
                    continue
                }
                if try store.wasPermanentlyDeleted(id: track.id) {
                    try? FileManager.default.removeItem(at: staged)
                    try FileManager.default.removeItem(at: url)
                    continue
                }
                let destination = try vault.url(for: track)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    guard try MediaVault.digest(staged) == track.assetHash else {
                        throw MusicError.importFailed(L10n.text("Staged file verification failed"))
                    }
                    try FileManager.default.moveItem(at: staged, to: destination)
                }
                guard try MediaVault.digest(destination) == track.assetHash else {
                    throw MusicError.importFailed(L10n.text("Music file verification failed"))
                }
                if try store.track(id: track.id) == nil { try store.save(track) }
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.removeItem(at: url)
            } catch {
                errors.append(
                    L10n.text(
                        "format.import.recovery",
                        String(describing: error.localizedDescription)
                    )
                )
            }
        }
        do { try store.cleanupPermanentlyDeletedFiles(in: vault) } catch {
            errors.append(
                L10n.text(
                    """
                    Unable to finish cleaning up permanently deleted files. Cleanup will be \
                    retried when iMusic opens again.
                    """
                )
            )
        }
        return errors
    }
}
