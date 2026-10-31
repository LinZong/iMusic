import SwiftUI

/// PlayerTransportControls owns one part of the full-player presentation.
struct PlayerTransportControls: View {
    /// Shared transport state and commands.
    let playback: PlaybackCoordinator
    /// Uses reduced spacing when vertical space is constrained.
    let compact: Bool
    #if os(macOS)
    /// Uses the focus scope owned by the full-player sheet.
    let playbackFocus: FocusState<Bool>.Binding
    #endif
    /// Renders this player component using the shared playback session.
    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            PlayerControlButton(
                symbol: "backward.fill",
                label: L10n.text("Previous Track"),
                symbolSize: compact ? 27 : 30,
                targetSize: compact ? 56 : 64,
                isProminent: true
            ) { playback.previous() }
            .accessibilityIdentifier("player.previous")
            Spacer(minLength: 16)
            PlayerControlButton(
                symbol: playback.isPlaying ? "pause.fill" : "play.fill",
                label: playback.isPlaying ? L10n.text("Pause") : L10n.text("Play"),
                symbolSize: compact ? 40 : 46,
                targetSize: compact ? 64 : 76,
                isProminent: true
            ) { playback.toggle() }
            .accessibilityIdentifier("player.toggle")
            #if os(macOS)
            .focused(playbackFocus)
            .keyboardShortcut(.space, modifiers: [])
            #endif
            Spacer(minLength: 16)
            PlayerControlButton(
                symbol: "forward.fill",
                label: L10n.text("Next Track"),
                symbolSize: compact ? 27 : 30,
                targetSize: compact ? 56 : 64,
                isProminent: true
            ) { playback.next() }
            .accessibilityIdentifier("player.next")
            Spacer(minLength: 0)
        }
        .disabled(playback.session.entries.isEmpty)
        .padding(.vertical, 2)

    }
}
