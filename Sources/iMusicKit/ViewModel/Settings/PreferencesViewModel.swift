import Foundation
import Observation

@MainActor @Observable
public final class PreferencesViewModel {
    /// Persistent preference storage; contains no navigation state.
    private let store: LibraryStore
    /// Persisted consent for manual artwork lookups that send artist and album names online.
    public var onlineEnabled: Bool {
        didSet { try? store.setSetting("onlineEnabled", value: onlineEnabled) }
    }
    /// Persisted system, light, or dark appearance identifier; independent of system accent color.
    public var appearance: String {
        didSet { try? store.setSetting("appearance", value: appearance) }
    }
    /// Persisted preference for rendering artwork with the vinyl-record appearance.
    public var vinyl: Bool { didSet { try? store.setSetting("vinyl", value: vinyl) } }
    /// Persisted order and visibility of the configurable Home sections.
    public var homeSections: [HomeSectionOption] {
        didSet { try? store.setSetting("homeSections", value: homeSections) }
    }
    /// Persisted preference for grouping collaborating artists as separate credits.
    public var splitArtists: Bool {
        didSet { try? store.setSetting("splitArtists", value: splitArtists) }
    }
    /// Persisted pipe-delimited separators used when collaborator splitting is enabled.
    public var artistSeparators: String {
        didSet { try? store.setSetting("artistSeparators", value: artistSeparators) }
    }
    /// Loads saved display, Home-layout, and metadata preferences from the library.
    init(store: LibraryStore) {
        self.store = store
        onlineEnabled = (try? store.setting("onlineEnabled", as: Bool.self)) ?? false
        appearance = PreferencesCompatibility.canonicalID(
            (try? store.setting("appearance", as: String.self)) ?? "system"
        )
        vinyl = (try? store.setting("vinyl", as: Bool.self)) ?? false
        homeSections =
            ((try? store.setting("homeSections", as: [HomeSectionOption].self))
            ?? HomeSectionOption.defaults)
            .map { $0.canonicalized() }
        splitArtists = (try? store.setting("splitArtists", as: Bool.self)) ?? false
        artistSeparators =
            (try? store.setting("artistSeparators", as: String.self)) ?? " feat. | ft. | & | 、"
    }
    /// Reloads portable preferences after a backup merge without resetting unrelated settings.
    func reload() {
        appearance = PreferencesCompatibility.canonicalID(
            (try? store.setting("appearance", as: String.self)) ?? appearance
        )
        vinyl = (try? store.setting("vinyl", as: Bool.self)) ?? vinyl
        homeSections =
            ((try? store.setting("homeSections", as: [HomeSectionOption].self)) ?? homeSections)
            .map {
                $0.canonicalized()
            }
        splitArtists = (try? store.setting("splitArtists", as: Bool.self)) ?? splitArtists
        artistSeparators =
            (try? store.setting("artistSeparators", as: String.self)) ?? artistSeparators
    }
}
