import SwiftUI

/// Reusable summary controls for models explicitly supporting active-song playback.
struct SongListPlaybackActions<Model: PlayableSongList>: View {
    /// Feature model providing an occurrence-preserving queue.
    let model: Model

    /// Starts ordinary or shuffled playback of the current search results.
    var body: some View {
        Button {
            model.play(row: model.state.ordered(model.rows).first)
        } label: {
            Label(L10n.text("Play"), systemImage: "play.fill")
        }
        .disabled(model.rows.isEmpty)
        Button {
            model.shuffle()
        } label: {
            Image(systemName: "shuffle").accessibilityLabel(L10n.text("Shuffle"))
        }
        .disabled(model.rows.isEmpty)
    }
}
