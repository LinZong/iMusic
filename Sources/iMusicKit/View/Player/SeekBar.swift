import SwiftUI

struct SeekBar: View {
    /// Playback timeline and seek commands used to keep drag previews separate from engine time.
    @Bindable var playback: PlaybackCoordinator
    /// Whether a slider drag preview is active and must be committed at the end of the gesture.
    @State private var isDragging = false
    /// Renders an accessible progress slider whose preview is committed only after the interaction
    /// ends.
    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { playback.timeline.fraction },
                    set: {
                        playback.beginScrubbing(fraction: $0)
                        // Keyboard and accessibility adjustments may have no drag-end event.
                        if !isDragging { playback.endScrubbing() }
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isDragging = editing
                    if !editing { playback.endScrubbing() }
                }
            )
            .accessibilityIdentifier("player.seek")
            .disabled(!playback.canSeek).accessibilityLabel(L10n.text("Playback Position"))
            .accessibilityValue(
                L10n.text(
                    "format.playback.position",
                    String(describing: musicTime(playback.timeline.displayedTime)),
                    String(describing: musicTime(playback.timeline.duration))
                )
            )
            .accessibilityAdjustableAction { direction in
                guard playback.canSeek else { return }
                switch direction {
                case .increment: playback.skip(seconds: 5)
                case .decrement: playback.skip(seconds: -5)
                @unknown default: break
                }
            }
            HStack {
                Text(musicTime(playback.timeline.displayedTime))
                    .accessibilityIdentifier("player.elapsed")
                Spacer()
                Text(musicTime(playback.timeline.duration))
                    .accessibilityLabel(
                        L10n.text(
                            "format.duration.total",
                            String(describing: musicTime(playback.timeline.duration))
                        )
                    )
            }
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).clipped()
    }
}
