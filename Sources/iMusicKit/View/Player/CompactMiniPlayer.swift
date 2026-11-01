import SwiftUI

/// Phone-sized playback bar retaining metadata, playback, next-track, and queue access.
struct CompactMiniPlayer: View {
    /// Shared playback state and presentation actions; resizing never creates a new session.
    let model: PlayerViewModel
    /// Insets artwork within its existing slot without moving metadata or reducing touch targets.
    var artworkInset: CGFloat = 0

    /// Keeps transport targets accessible while letting long metadata truncate naturally.
    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.presentation.showPlayer = true
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(
                        track: model.playback.track,
                        vault: model.library.vault,
                        size: 42 - artworkInset * 2
                    )
                    .padding(artworkInset)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.playback.track?.title ?? "iMusic")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(model.playback.track?.displayArtist ?? "").font(.caption)
                            .foregroundStyle(
                                .secondary
                            )
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(L10n.text("Expand Now Playing"))
            .accessibilityIdentifier("miniPlayer.expand")
            .accessibilityValue(model.playback.track?.title ?? "iMusic")
            PlayerControlButton(
                symbol: model.playback.isPlaying ? "pause.fill" : "play.fill",
                label: model.playback.isPlaying ? L10n.text("Pause") : L10n.text("Play"),
                isProminent: true
            ) {
                model.playback.toggle()
            }
            .accessibilityIdentifier("miniPlayer.toggle")
            PlayerControlButton(
                symbol: "forward.end.fill",
                label: L10n.text("Next Track"),
                isProminent: true
            ) { model.playback.next() }
            .accessibilityIdentifier("miniPlayer.next")
            PlayerControlButton(symbol: "list.bullet", label: L10n.text("Play Queue")) {
                model.presentation.showQueue = true
            }
            .accessibilityIdentifier("miniPlayer.queue")
        }
        .padding(.horizontal, 16)
    }
}
