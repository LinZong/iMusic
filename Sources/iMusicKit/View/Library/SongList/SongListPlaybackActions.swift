import SwiftUI

/// Reusable summary controls for models explicitly supporting active-song playback.
struct SongListPlaybackActions<Model: PlayableSongList>: View {
    /// Feature model providing an occurrence-preserving queue.
    let model: Model

    /// Starts ordinary or shuffled playback of the current search results.
    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.play(row: model.state.ordered(model.rows).first)
            } label: {
                Image(systemName: "play.fill")
                    #if os(iOS)
                .frame(minWidth: 44, minHeight: 44)
                    #endif
            }
            .disabled(model.rows.isEmpty)
            Button {
                model.shuffle()
            } label: {
                Image(systemName: "shuffle").accessibilityLabel(L10n.text("Shuffle"))
                    #if os(iOS)
                .frame(minWidth: 44, minHeight: 44)
                    #endif
            }
        }
        .disabled(model.rows.isEmpty)
    }
}
