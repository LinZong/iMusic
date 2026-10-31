import SwiftUI

/// NowPlayingUtilities owns one part of the full-player presentation.
struct NowPlayingUtilities: View {
    /// Local full-player presentation state and shared playback dependencies.
    let model: NowPlayingViewModel
    /// Renders this player component using the shared playback session.
    var body: some View {
        HStack(spacing: 0) {
            PlayerControlButton(
                symbol: "shuffle",
                label: model.player.playback.session.isShuffled
                    ? L10n.text("Turn Shuffle Off") : L10n.text("Turn Shuffle On"),
                isSelected: model.player.playback.session.isShuffled
            ) { model.player.playback.toggleShuffle() }
            .disabled(model.player.playback.session.entries.isEmpty)
            Spacer(minLength: 4)
            PlayerControlButton(
                symbol: model.player.playback.session.repeatMode.symbol,
                label: model.player.playback.session.repeatMode.label,
                isSelected: model.player.playback.session.repeatMode != .off
            ) {
                model.player.playback.setRepeat(model.player.playback.session.repeatMode.next)
            }
            Spacer(minLength: 4)
            AirPlayControl().frame(width: 44, height: 44)
                .accessibilityLabel(L10n.text("Audio Output"))
            Spacer(minLength: 4)
            PlaybackOptionsMenu(model: model)
            Spacer(minLength: 4)
            PlayerControlButton(symbol: "list.bullet", label: L10n.text("Play Queue")) {
                model.player.presentation.showQueue = true
            }
            .disabled(model.player.playback.session.entries.isEmpty)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))

    }
}
