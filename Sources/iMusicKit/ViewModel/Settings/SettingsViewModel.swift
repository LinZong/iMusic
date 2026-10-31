import Foundation
import Observation

@MainActor @Observable
final class SettingsViewModel {
    /// Observable library records and record-level actions.
    let library: LibraryViewModel
    /// Persisted preferences used by this feature.
    let preferences: PreferencesViewModel
    /// Import and archive workflows requested from this feature.
    let imports: ImportViewModel
    /// Creates an independent feature model with explicit service and state dependencies.
    init(
        library: LibraryViewModel,
        preferences: PreferencesViewModel,
        imports: ImportViewModel
    ) {
        self.library = library
        self.preferences = preferences
        self.imports = imports
    }
}
