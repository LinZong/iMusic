import Foundation
import Observation

@MainActor @Observable
final class LibraryActivity {
    /// Whether an import task is active and the progress footer should be displayed.
    var importing = false
    /// Latest per-file progress snapshot from the active or most recent import.
    var importProgress = ImportProgress()
    /// Optional localized message presented by the root alert.
    var message: String?
    /// Whether a blocking library operation is running and the progress overlay is visible.
    var isWorking = false

}
