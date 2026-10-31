#if os(iOS)
import CarPlay
import Foundation
import Observation
import UIKit

/// Minimal library and transport contract needed by a vehicle scene.
@MainActor
public protocol CarPlayLibraryProviding: AnyObject {
    /// Published library records used to render vehicle templates.
    var library: LibraryViewModel { get }
    /// Shared playback session controlled by the vehicle.
    var playback: PlaybackCoordinator { get }
    /// Ensures library startup completes before vehicle navigation is rendered.
    func launch() async
}

extension AppModel: CarPlayLibraryProviding {}

@MainActor
public final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    /// CarPlay-only library contract; unrelated application services are not exposed.
    public static weak var session: (any CarPlayLibraryProviding)?
    /// Active CarPlay template controller, held weakly for the connected vehicle scene.
    private weak var controller: CPInterfaceController?
    /// Retains the connected vehicle controller, ensures the shared library has launched, and
    /// renders the CarPlay library.
    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        controller = interfaceController
        Task { @MainActor [weak self] in
            // A CarPlay-only launch may have no SwiftUI window to run its task.
            await Self.session?.launch()
            self?.renderLibrary()
        }
    }
    /// Releases the vehicle template controller when the CarPlay scene disconnects.
    public func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        controller = nil
    }
    private func renderLibrary() {
        guard let interfaceController = controller else { return }
        guard let model = Self.session else { return }
        withObservationTracking {
            _ = model.library.tracks
            _ = model.library.playlists
        } onChange: { [weak self] in
            Task { @MainActor in self?.renderLibrary() }
        }
        let tracks = model.library.tracks
        func list(_ title: String, _ tracks: [Track]) -> CPListTemplate {
            let items = tracks.prefix(CPListTemplate.maximumItemCount)
                .map { track in
                    let item = CPListItem(text: track.title, detailText: track.displayArtist)
                    item.handler = { [weak interfaceController] _, complete in
                        Task { @MainActor in
                            model.playback.play(tracks, startingAt: track.id)
                            interfaceController?
                                .pushTemplate(
                                    CPNowPlayingTemplate.shared,
                                    animated: true,
                                    completion: nil
                                )
                            complete()
                        }
                    }
                    return item
                }
            return CPListTemplate(title: title, sections: [CPListSection(items: items)])
        }
        let recent = list(L10n.text("Recently Added"), tracks.sorted { $0.addedAt > $1.addedAt })
        recent.tabImage = UIImage(systemName: "clock")
        let favorites = list(L10n.text("Favorites"), tracks.filter(\.isFavorite))
        favorites.tabImage = UIImage(systemName: "heart")
        let playlists = CPListTemplate(
            title: L10n.text("Playlists"),
            sections: [
                CPListSection(
                    items: model.library.playlists.prefix(CPListTemplate.maximumItemCount)
                        .map { playlist in
                            let item = CPListItem(
                                text: playlist.name,
                                detailText: L10n.text(
                                    "format.song_count.short",
                                    playlist.entries.count
                                )
                            )
                            item.handler = { _, complete in
                                Task { @MainActor in
                                    let selected = playlist.entries.compactMap { entry in
                                        tracks.first { $0.id == entry.trackID }
                                    }
                                    interfaceController.pushTemplate(
                                        list(playlist.name, selected),
                                        animated: true,
                                        completion: nil
                                    )
                                    complete()
                                }
                            }
                            return item
                        }
                )
            ]
        )
        playlists.tabImage = UIImage(systemName: "music.note.list")
        let library = list(L10n.text("Library"), tracks)
        library.tabImage = UIImage(systemName: "music.note")
        interfaceController.setRootTemplate(
            CPTabBarTemplate(templates: [recent, favorites, playlists, library]),
            animated: false,
            completion: nil
        )
    }
}
#endif
