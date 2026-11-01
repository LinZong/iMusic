import SwiftUI

/// Shared count, duration, and controls fixed above the song scroller on every platform.
struct SongListSummary<Actions: View>: View {
    /// Number of currently visible song occurrences, including playlist duplicates.
    let songCount: Int
    /// Combined media duration of the visible occurrences, in seconds.
    let duration: TimeInterval
    /// Feature-supplied trailing controls, such as ordinary and shuffled playback.
    @ViewBuilder var actions: () -> Actions

    /// Selects only presentation; counts, duration, and feature actions retain one data flow.
    var body: some View {
        Group {
            #if os(iOS)
            if #available(iOS 26.0, *) {
                GlassSongListSummary(summary: { label }, actions: actions)
            } else {
                LegacySongListSummary(summary: { label }, actions: actions)
            }
            #else
            LegacySongListSummary(summary: { label }, actions: actions)
            #endif
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library.songSummaryBar")
    }

    /// Accessible localized statistics shared by every system presentation.
    private var label: some View {
        Text(
            L10n.text(
                "format.song_count.duration",
                songCount,
                String(describing: musicTime(duration))
            )
        )
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("library.songSummary")
    }
}
