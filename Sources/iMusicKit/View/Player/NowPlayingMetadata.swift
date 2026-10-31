import SwiftUI

/// NowPlayingMetadata owns one part of the full-player presentation.
struct NowPlayingMetadata: View {
    /// Shared song actions, artwork storage, and playback dependencies.
    let player: PlayerViewModel
    /// Renders this player component using the shared playback session.
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(player.playback.track?.title ?? L10n.text("Nothing Playing"))
                    .font(.title2.weight(.semibold)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    player.playback.track?.displayArtist
                        ?? L10n.text("Choose a song you love")
                )
                .font(.body).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("player.metadata")
            if let track = player.playback.track {
                PlayerControlButton(
                    symbol: track.isFavorite ? "heart.fill" : "heart",
                    label: track.isFavorite
                        ? L10n.text("Remove from Favorites") : L10n.text("Favorites"),
                    isSelected: track.isFavorite
                ) { player.library.commands.toggleFavorite(track) }
            }
        }

    }
}
