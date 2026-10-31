import SwiftUI

public struct MiniPlayerWindow: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @Bindable var model: PlayerViewModel
    /// Creates the standalone macOS player window content backed by the shared app model.
    public init(model: PlayerViewModel) { self.model = model }
    /// Renders the standalone macOS compact player window and its expanded-player action.
    public var body: some View {
        Group {
            if model.playback.track == nil {
                ContentUnavailableView(
                    L10n.text("Nothing Playing"),
                    systemImage: "music.note",
                    description: Text(L10n.text("Choose music to start playing"))
                )
            } else {
                playerContent
            }
        }
        .frame(minWidth: 280, idealWidth: 340)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    /// Compact artwork and playback controls displayed when a current song is available.
    private var playerContent: some View {
        VStack(spacing: 18) {
            ArtworkView(track: model.playback.track, vault: model.library.vault, size: 220)
            Text(model.playback.track?.title ?? "iMusic").font(.headline).lineLimit(2)
            Text(model.playback.track?.displayArtist ?? L10n.text("Choose music to start playing"))
                .font(
                    .caption
                )
                .foregroundStyle(.secondary)
            SeekBar(playback: model.playback)
            HStack(spacing: 34) {
                Button {
                    model.playback.previous()
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .accessibilityLabel(L10n.text("Previous Track"))
                Button {
                    model.playback.toggle()
                } label: {
                    Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                }
                .accessibilityLabel(
                    model.playback.isPlaying ? L10n.text("Pause") : L10n.text("Play")
                )
                .accessibilityIdentifier("miniWindow.toggle")
                #if os(macOS)
                .keyboardShortcut(.space, modifiers: [])
                #endif
                Button {
                    model.playback.next()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .accessibilityLabel(L10n.text("Next Track"))
            }
            .buttonStyle(.plain)
            #if os(macOS)
            VolumeControl(playback: model.playback)
            #endif
        }
        .padding(24)
    }
}
