import Foundation
import Observation

@MainActor @Observable
final class BackupExportViewModel {
    /// Native export status or localized failure shown by this sheet only.
    var message: String?
    /// Whether a copy is active and dismissal should be disabled.
    private(set) var saving = false
    /// Copies through a temporary sibling and atomically replaces an existing destination.
    func save(source: URL, destination: URL) async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try await Task.detached {
                let temporary = destination.deletingLastPathComponent()
                    .appendingPathComponent(
                        ".iMusic-" + UUID().uuidString + "." + source.pathExtension
                    )
                defer { try? FileManager.default.removeItem(at: temporary) }
                try FileManager.default.copyItem(at: source, to: temporary)
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: destination)
                }
            }
            .value
            message = L10n.text("File saved.")
        } catch { message = error.localizedDescription }
    }
}
