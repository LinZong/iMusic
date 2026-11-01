import Foundation
import Observation

/// Active library scopes; playlist editing and Trash cannot enter this model.
enum SongCollectionScope {
    case all, favorites
    case artist(String)
    case album(String)
    case genre(String)

    /// Existing library query corresponding to this active collection.
    var destination: LibraryDestination {
        switch self {
        case .all: .songs
        case .favorites: .favorites
        case .artist(let name): .artist(name)
        case .album(let key): .album(key)
        case .genre(let name): .genre(name)
        }
    }

    /// Empty-state symbol for this collection.
    var symbol: String { destination.symbol }
}

/// Read-only collection scope with shared active-song playback capabilities.
@MainActor @Observable
final class SongCollectionViewModel: PlayableSongList {
    /// Observable records and record-level actions.
    let library: LibraryViewModel
    /// Shared playback and song actions.
    let player: PlayerViewModel
    /// Active collection selected by the caller.
    let scope: SongCollectionScope
    /// Search, table ordering, and selection local to this page.
    let state = SongListState()
    /// Localized collection heading, including the selected album's current display name.
    var title: String { library.catalog.title(for: scope.destination) }
    /// Matching active tracks represented by stable song identities.
    var rows: [SongRowData] {
        state.filter(
            library.catalog.songs(for: scope.destination)
                .map {
                    SongRowData(id: $0.id, track: $0)
                }
        )
    }

    /// Creates an independent active collection page.
    init(library: LibraryViewModel, player: PlayerViewModel, scope: SongCollectionScope) {
        self.library = library
        self.player = player
        self.scope = scope
    }
}
