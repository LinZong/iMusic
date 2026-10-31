import SwiftUI

/// NowPlayingControls owns one part of the full-player presentation.
struct NowPlayingControls: View {
    /// Local full-player presentation state and shared playback dependencies.
    let model: NowPlayingViewModel
    /// Uses reduced spacing when vertical space is constrained.
    let compact: Bool
    #if os(macOS)
    /// Focus binding owned by the sheet rather than this nested control panel.
    let playbackFocus: FocusState<Bool>.Binding
    #endif
    /// Renders this player component using the shared playback session.
    var body: some View {
        VStack(spacing: compact ? 8 : 18) {
            NowPlayingMetadata(player: model.player)
            SeekBar(playback: model.player.playback)
            transport
            #if os(macOS)
            VolumeControl(playback: model.player.playback)
            #endif
            NowPlayingUtilities(model: model)
            PlaybackDetailsView(playback: model.player.playback, compact: compact)
            if let error = model.player.playback.error {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

    }
    /// Composes transport controls while preserving the sheet's default keyboard action.
    private var transport: some View {
        #if os(macOS)
        PlayerTransportControls(
            playback: model.player.playback,
            compact: compact,
            playbackFocus: playbackFocus
        )
        #else
        PlayerTransportControls(playback: model.player.playback, compact: compact)
        #endif
    }

}
