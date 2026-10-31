import SwiftUI

/// PlaybackDetailsView owns one part of the full-player presentation.
struct PlaybackDetailsView: View {
    /// Current route, media format, and playback options.
    let playback: PlaybackCoordinator
    /// Uses reduced spacing when vertical space is constrained.
    let compact: Bool
    /// Renders this player component using the shared playback session.
    var body: some View {
        VStack(spacing: 6) {
            if compact, let track = playback.track {
                Text(
                    """
                    \(playback.routeName) · \(track.fileExtension.uppercased()) · \
                    \((track.sampleRate / 1_000).formatted()) kHz
                    """
                )
                .font(.caption2).lineLimit(1)
            } else {
                Text(playback.routeName).font(.caption).lineLimit(2)
                if let track = playback.track {
                    Text(
                        """
                        \(track.fileExtension.uppercased()) · \
                        \((track.sampleRate / 1_000).formatted()) kHz
                        """
                    )
                    .font(.caption2).monospacedDigit()
                }
            }
            if playback.rate != 1 {
                Text(
                    """
                    \(L10n.text("Playback Speed")) · \
                    \(Double(playback.rate).formatted())×
                    """
                )
                .font(.caption)
            }
            if playback.loopA != nil {
                Text(playback.loopB != nil ? "A ↔ B" : "A · B?")
                    .font(.caption.monospaced())
                    .accessibilityLabel(L10n.text("Set or Clear A/B Loop"))
            }
            if playback.sleepAtEnd {
                Text(L10n.text("Pause at the end of this song")).font(.caption)
            }
            if let deadline = playback.sleepDeadline {
                Label {
                    Text(deadline, style: .timer).monospacedDigit()
                } icon: {
                    Image(systemName: "moon.zzz")
                }
                .font(.caption)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)

    }
}
