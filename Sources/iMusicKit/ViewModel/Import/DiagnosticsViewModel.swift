import Foundation
import Observation

/// Focused DiagnosticsViewModel workflow, independent of other import presentations.
@MainActor @Observable
final class DiagnosticsViewModel {
    /// Anonymous diagnostics generation service.
    let exporter: DiagnosticsExporter
    /// Shared error presentation.
    let activity: LibraryActivity
    /// Completed report offered by the export sheet.
    var diagnosticsURL: URL?
    /// Creates independent diagnostic-export presentation state.
    init(exporter: DiagnosticsExporter, activity: LibraryActivity) {
        self.exporter = exporter
        self.activity = activity
    }
    /// Generates the report off the UI actor and publishes its export location.
    func exportDiagnostics() {
        let exporter = exporter
        Task {
            do { diagnosticsURL = try await Task.detached { try exporter.export() }.value } catch {
                activity.message = error.localizedDescription
            }
        }
    }
}
