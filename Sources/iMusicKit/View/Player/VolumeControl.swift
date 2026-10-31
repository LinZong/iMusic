import SwiftUI

#if os(macOS)
/// Native desktop application volume shared by the full and standalone mini player.
struct VolumeControl: View {
    /// Single playback session supplying gain, mute restoration, and persistence.
    @Bindable var playback: PlaybackCoordinator
    /// Locale-aware percentage announced by accessibility without adding a visible numeric label.
    private var percentage: String {
        Double(playback.volume).formatted(.percent.precision(.fractionLength(0)))
    }
    /// Renders understated speaker symbols surrounding a native, keyboard-accessible volume slider.
    var body: some View {
        HStack(spacing: 8) {
            Button {
                playback.toggleMute()
            } label: {
                Image(
                    systemName: playback.isMuted ? "speaker.slash.fill" : "speaker.wave.1.fill"
                )
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.isMuted ? L10n.text("Unmute") : L10n.text("Mute"))
            .accessibilityIdentifier("player.mute")
            .help(playback.isMuted ? L10n.text("Unmute") : L10n.text("Mute"))
            Slider(
                value: Binding(
                    get: { Double(playback.volume) },
                    set: { playback.setVolume(Float($0)) }
                ),
                in: 0...1
            )
            .controlSize(.small)
            .accessibilityLabel(L10n.text("Volume"))
            .accessibilityIdentifier("player.volume")
            .accessibilityValue(percentage)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: playback.setVolume(playback.volume + 0.05)
                case .decrement: playback.setVolume(playback.volume - 0.05)
                @unknown default: break
                }
            }
            .help(L10n.text("Volume"))
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 28)
    }
}
#endif
