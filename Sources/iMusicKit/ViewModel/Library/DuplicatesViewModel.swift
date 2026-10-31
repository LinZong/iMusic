import Foundation

/// Duplicate-content query and merge actions, separate from list presentation.
@MainActor
struct DuplicatesViewModel {
    /// Active library and transactional duplicate-merging commands.
    let library: LibraryViewModel
    /// Stable hash-identified groups; linked originals are deliberately excluded.
    var groups: [DuplicateGroup] {
        Dictionary(grouping: library.tracks.filter { !$0.isLinked }, by: \.assetHash)
            .compactMap { hash, tracks -> DuplicateGroup? in
                guard let hash, tracks.count > 1 else { return nil }
                return DuplicateGroup(id: hash, tracks: tracks)
            }
            .sorted { $0.id < $1.id }
    }
    /// Merges one group into the explicitly selected keeper.
    func keep(_ track: Track, in group: DuplicateGroup) {
        library.commands.mergeDuplicates(keeper: track, duplicates: group.tracks)
    }
}

/// Content-identified duplicate group with stable SwiftUI identity.
struct DuplicateGroup: Identifiable {
    /// Verified content digest shared by the group's managed records.
    let id: String
    /// Candidate records from which the user selects one keeper.
    let tracks: [Track]
}
