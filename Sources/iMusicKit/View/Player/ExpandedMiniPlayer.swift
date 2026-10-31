import SwiftUI

/// Wide playback bar shared by desktop and touch layouts with sufficient horizontal space.
struct ExpandedMiniPlayer: View {
    /// Shared library mutations, playback state, and presentation actions.
    let model: PlayerViewModel
    /// Fixed transport width keeps its center independent of metadata and volume widths.
    private let transportWidth: CGFloat = 244

    /// Balances metadata and output regions around the shared transport controls.
    var body: some View {
        VStack(spacing: 0) {
            PlaybackProgressLine(playback: model.playback)
            GeometryReader { geometry in
                let sideWidth = max(0, (geometry.size.width - transportWidth - 56) / 2)
                HStack(spacing: 12) {
                    songInformation.frame(width: sideWidth, alignment: .leading)
                    transport.frame(width: transportWidth)
                    outputControls.frame(width: sideWidth, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .frame(height: geometry.size.height)
            }
            .frame(height: 72)
        }
        .background(.bar)
    }

    /// Artwork and truncated metadata open the full player; the adjacent heart acts independently.
    private var songInformation: some View {
        HStack(spacing: 8) {
            Button {
                model.presentation.showPlayer = true
            } label: {
                HStack(spacing: 12) {
                    ArtworkView(track: model.playback.track, vault: model.library.vault, size: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.playback.track?.title ?? "iMusic")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(model.playback.track?.displayArtist ?? "")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("Expand Now Playing"))
            .accessibilityIdentifier("miniPlayer.expand")
            .accessibilityValue(model.playback.track?.title ?? "iMusic")
            .help(model.playback.track?.title ?? "iMusic")
            .layoutPriority(1)
            if let track = model.playback.track {
                Button {
                    model.library.commands.toggleFavorite(track)
                } label: {
                    Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(track.isFavorite ? Color.red : Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlayerControlStyle())
                .accessibilityIdentifier("miniPlayer.favorite")
                .accessibilityLabel(
                    track.isFavorite ? L10n.text("Remove from Favorites") : L10n.text("Favorites")
                )
                .accessibilityAddTraits(track.isFavorite ? .isSelected : [])
                .help(
                    track.isFavorite ? L10n.text("Remove from Favorites") : L10n.text("Favorites")
                )
            }
            Spacer(minLength: 0)
        }
    }

    /// Repeat, previous, play/pause, next, and shuffle share the full player's state.
    private var transport: some View {
        HStack(spacing: 4) {
            PlayerControlButton(
                symbol: model.playback.session.repeatMode.symbol,
                label: model.playback.session.repeatMode.label,
                symbolSize: 16,
                isSelected: model.playback.session.repeatMode != .off
            ) {
                model.playback.setRepeat(model.playback.session.repeatMode.next)
            }
            .accessibilityIdentifier("miniPlayer.repeat")
            PlayerControlButton(
                symbol: "backward.end.fill",
                label: L10n.text("Previous Track"),
                symbolSize: 18,
                isProminent: true
            ) { model.playback.previous() }
            .accessibilityIdentifier("miniPlayer.previous")
            PlayerControlButton(
                symbol: model.playback.isPlaying ? "pause.fill" : "play.fill",
                label: model.playback.isPlaying ? L10n.text("Pause") : L10n.text("Play"),
                symbolSize: 23,
                targetSize: 52,
                isProminent: true
            ) { model.playback.toggle() }
            .accessibilityIdentifier("miniPlayer.toggle")
            .keyboardShortcut(.space, modifiers: [])
            .background(Color.primary.opacity(0.06), in: Circle())
            PlayerControlButton(
                symbol: "forward.end.fill",
                label: L10n.text("Next Track"),
                symbolSize: 18,
                isProminent: true
            ) { model.playback.next() }
            .accessibilityIdentifier("miniPlayer.next")
            PlayerControlButton(
                symbol: "shuffle",
                label: model.playback.session.isShuffled
                    ? L10n.text("Turn Shuffle Off") : L10n.text("Turn Shuffle On"),
                symbolSize: 16,
                isSelected: model.playback.session.isShuffled
            ) { model.playback.toggleShuffle() }
            .accessibilityIdentifier("miniPlayer.shuffle")
        }
        .disabled(model.playback.session.entries.isEmpty)
    }

    /// Queue access is shared; persistent application gain remains a desktop-only control.
    private var outputControls: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            VolumeControl(playback: model.playback).frame(width: 132)
            #endif
            PlayerControlButton(
                symbol: "list.bullet",
                label: L10n.text("Play Queue"),
                symbolSize: 18
            ) { model.presentation.showQueue = true }
            .accessibilityIdentifier("miniPlayer.queue")
        }
    }
}
