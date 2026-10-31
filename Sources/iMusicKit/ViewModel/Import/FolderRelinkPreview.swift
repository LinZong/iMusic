import Foundation

/// Reviewable device-local remapping proposed after a user explicitly selects a replacement root.
struct FolderRelinkPreview: Identifiable {
    /// Portable folder identity whose song UUIDs must be preserved.
    let id: UUID
    /// Selected root display name; no absolute path is exported.
    let name: String
    /// Read grant retained locally until the user confirms or cancels the proposed mapping.
    let bookmark: Data
    /// Existing songs whose relative paths will be tested in the selected root.
    let tracks: [Track]
}
