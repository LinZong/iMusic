import SwiftUI

/// Shared count, duration, and controls fixed above the song scroller on every platform.
struct SongListSummary<Actions: View>: View {
    /// Number of currently visible song occurrences, including playlist duplicates.
    let songCount: Int
    /// Combined media duration of the visible occurrences, in seconds.
    let duration: TimeInterval
    /// Feature-supplied trailing controls, such as ordinary and shuffled playback.
    @ViewBuilder var actions: () -> Actions

    /// Preserves consistent summary padding and exposes controls as independent actions.
    var body: some View {
        HStack {
            Text(
                L10n.text(
                    "format.song_count.duration",
                    songCount,
                    String(describing: musicTime(duration))
                )
            )
            #if os(macOS)
            .font(.body)
            #else
            .font(.caption)
            #endif
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("library.songSummary")
            Spacer()
            actions()
        }
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.songSummaryBar")
    }
}
