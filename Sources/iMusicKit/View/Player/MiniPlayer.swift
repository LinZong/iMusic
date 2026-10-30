import SwiftUI

struct MiniPlayer: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @Bindable var model: PlayerViewModel
    /// Renders current-song metadata and compact playback controls below the active page.
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    model.presentation.showPlayer = true
                } label: {
                    HStack(spacing: 12) {
                        ArtworkView(
                            track: model.playback.track,
                            vault: model.library.vault,
                            size: 42
                        )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.playback.track?.title ?? "iMusic")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text(model.playback.track?.displayArtist ?? "").font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(L10n.text("Expand Now Playing"))
                Button {
                    model.playback.toggle()
                } label: {
                    Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    model.playback.isPlaying ? L10n.text("Pause") : L10n.text("Play")
                )
                Button {
                    model.playback.next()
                } label: {
                    Image(systemName: "forward.end.fill").font(.title3).frame(width: 32, height: 40)
                }
                .buttonStyle(.plain).accessibilityLabel(L10n.text("Next Track"))
                Button {
                    model.presentation.showQueue = true
                } label: {
                    Image(systemName: "list.bullet").frame(width: 30, height: 40)
                }
                .buttonStyle(.plain).accessibilityLabel(L10n.text("Play Queue"))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            GeometryReader { geometry in
                Rectangle().fill(Color.accentColor)
                    .frame(
                        width: geometry.size.width * model.playback.timeline.fraction
                    )
            }
            .frame(height: 2).background(.quaternary).clipped().accessibilityHidden(true)
        }
        .background(.bar)
    }
}
