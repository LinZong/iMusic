import Foundation
import Observation

/// Focused ImportPickerViewModel workflow, independent of other import presentations.
@MainActor @Observable
final class ImportPickerViewModel {
    /// Native picker purpose selected before presentation.
    var purpose: FileImportPurpose = .audio
    /// Whether the shared native picker is visible.
    var presented = false
    /// Presents an explicit file operation without starting any I/O.
    func present(_ purpose: FileImportPurpose) {
        self.purpose = purpose
        presented = true
    }

}
