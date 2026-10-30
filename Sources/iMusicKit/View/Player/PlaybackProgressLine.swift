import SwiftUI

/// Isolates frequent timeline observations from the playback bar's buttons and metadata.
struct PlaybackProgressLine: View {
    /// Authoritative timeline shared by the compact and full player surfaces.
    let playback: PlaybackCoordinator

    /// Displays a clipped, noninteractive progress indicator without introducing another clock.
    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(Color.accentColor)
                .frame(width: geometry.size.width * playback.timeline.fraction)
        }
        .frame(height: 2).background(.quaternary).clipped().accessibilityHidden(true)
    }
}
