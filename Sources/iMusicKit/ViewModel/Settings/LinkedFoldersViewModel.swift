import Foundation

/// Derives source settings from device-local grants and portable song references.
struct LinkedFoldersViewModel {
    /// Shared library snapshots; no file-provider reads occur while rendering settings.
    let library: LibraryViewModel
    /// Authorized roots plus folders whose permission must be restored on this device.
    @MainActor var folders: [FolderSource] {
        var result = library.folders
        for reference in library.tracks.compactMap(\.linkedSource)
        where !result.contains(where: { $0.id == reference.folderID }) {
            var folder = FolderSource(name: reference.folderName, bookmark: Data())
            folder.id = reference.folderID
            folder.usesOriginalFiles = true
            folder.error = L10n.text("Authorize the linked folder in Settings.")
            result.append(folder)
        }
        return result
    }
    /// Pending, failed, cancelled, or missing local jobs associated with a folder.
    @MainActor func problems(_ folder: FolderSource) -> [LinkedFileBinding] {
        library.linkedBindings.filter { $0.folderID == folder.id && $0.state != .ready }
    }
    /// Number of admitted original-file songs associated with a portable folder identity.
    @MainActor func count(_ folder: FolderSource) -> Int {
        library.tracks.filter { $0.linkedSource?.folderID == folder.id }.count
    }
}
