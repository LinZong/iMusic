import SwiftUI

struct TrackRow: View {
  /// Feature model containing only this page's state and explicit dependencies.
  @Bindable var model: PlayerViewModel
  /// Song displayed by this reusable row.
  let track: Track
  /// Playback action supplied by the containing collection to preserve its queue order.
  let action: () -> Void
  /// Renders a song occurrence with its playback action, favorite toggle, and contextual menu.
  var body: some View {
    HStack(spacing: 12) {
      Button(action: action) {
        HStack(spacing: 12) {
          ArtworkView(track: track, vault: model.library.vault, size: 46)
          VStack(alignment: .leading, spacing: 4) {
            Text(track.title).font(.body.weight(.medium)).lineLimit(1)
            Text(track.displayArtist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          }
          Spacer(minLength: 0)
          if model.playback.track?.id == track.id {
            Image(systemName: model.playback.isPlaying ? "waveform" : "pause.fill").foregroundStyle(
              Color.accentColor)
          }
          Text(musicTime(track.duration)).font(.caption).monospacedDigit().foregroundStyle(
            .secondary)
        }.contentShape(Rectangle())
      }.buttonStyle(.plain)
      Button {
        model.library.toggleFavorite(track)
      } label: {
        Image(systemName: track.isFavorite ? "heart.fill" : "heart").foregroundStyle(
          track.isFavorite ? Color.pink : Color.secondary)
      }.buttonStyle(.plain).accessibilityLabel(
        track.isFavorite ? L10n.text("Remove from Favorites") : L10n.text("Favorites"))
      Menu {
        TrackActions(model: model, tracks: [track])
      } label: {
        Image(systemName: "ellipsis").frame(width: 28, height: 32).contentShape(Rectangle())
      }.menuStyle(.borderlessButton).fixedSize()
    }.padding(.vertical, 9).padding(.horizontal, 6)
      .contextMenu { TrackActions(model: model, tracks: [track]) }
      .draggable(track.id.uuidString)
  }
}
