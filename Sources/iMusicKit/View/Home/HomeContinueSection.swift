import SwiftUI

/// Dedicated continue section of the configurable Home feed.
struct HomeContinueSection: View {
    /// Home feature projections and navigation dependencies.
    let model: HomeViewModel

    /// Renders this section without changing the home feed's other sections.
    var body: some View {

        if let track = model.player.playback.track {
            Button {
                model.player.presentation.showPlayer = true
            } label: {
                HStack(spacing: 16) {
                    ArtworkView(track: track, vault: model.library.vault, size: 80)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L10n.text("Continue Listening")).font(.caption)
                            .foregroundStyle(.secondary)
                        Text(track.title).font(.headline).lineLimit(1)
                        Text(track.displayArtist).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .padding(16)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
        }

    }

}
