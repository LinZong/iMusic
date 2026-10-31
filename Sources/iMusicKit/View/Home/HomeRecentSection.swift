import SwiftUI

/// Dedicated recent section of the configurable Home feed.
struct HomeRecentSection: View {
    /// Home feature projections and navigation dependencies.
    let model: HomeViewModel

    /// Renders this section without changing the home feed's other sections.
    var body: some View {

        if !model.library.tracks.isEmpty {
            Text(L10n.text("Recently Added")).font(.title2.bold())
            LazyVStack(spacing: 2) {
                ForEach(model.recentTracks.prefix(12)) {
                    track in
                    TrackRow(model: model.player, track: track) {
                        model.player.playback.play(
                            model.recentTracks,
                            startingAt: track.id
                        )
                    }
                }
            }
        }

    }

}
