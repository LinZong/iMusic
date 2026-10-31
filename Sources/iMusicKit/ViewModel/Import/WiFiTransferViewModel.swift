import Foundation
import Observation

/// Focused WiFiTransferViewModel workflow, independent of other import presentations.
@MainActor @Observable
final class WiFiTransferViewModel {
    /// Shared record snapshots refreshed after committed changes.
    let library: LibraryViewModel
    /// Shared progress and localized operation errors.
    let activity: LibraryActivity
    /// Listener dependency; no HTTP transport details leak into this workflow.
    let server: any WiFiTransferServing
    /// Whether the transfer page is presented.
    var presented = false
    /// Delivers a completed import report after the transfer page has been dismissed.
    var onCompleted: ((ImportProgress) -> Void)?
    /// Creates an independently presentable transfer workflow.
    init(library: LibraryViewModel, activity: LibraryActivity, server: any WiFiTransferServing) {
        self.library = library
        self.activity = activity
        self.server = server
    }
    /// Starts the local upload listener and imports each completed upload through the serialized
    /// importer, then refreshes the library.
    public func startWiFi() async {
        await server.start(staging: library.vault.staging) { [weak self] url in
            Task { @MainActor in
                guard let self else { return }
                // Serial library.importer actor accepts each uploaded file independently of the
                // picker task.
                let result = await self.library.importer.importFiles([url]) { _ in }
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                self.activity.importProgress = result
                if !self.presented { self.onCompleted?(result) }
                await self.library.refresh()
            }
        }
    }
}
