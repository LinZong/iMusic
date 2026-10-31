import SwiftUI

/// Separates deleted songs and playlists into native segmented tabs on every platform.
struct TrashView: View {
    /// Retains the selected category and each child page's independent state.
    @State var model: TrashViewModel

    /// Shows one category's search, summary, empty state, and recovery actions at a time.
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker(L10n.text("Trash Categories"), selection: $model.category) {
                Text(L10n.text("Songs")).tag(TrashViewModel.Category.songs)
                Text(L10n.text("Playlists")).tag(TrashViewModel.Category.playlists)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("trash.tabs")
            .frame(maxWidth: 360)
            .padding(.horizontal, 16)
            .padding(.top, 16)

            switch model.category {
            case .songs:
                TrashSongsView(model: model.songs, searchBinding: searchBinding(for: .songs))
            case .playlists:
                TrashPlaylistsView(
                    model: model.playlists,
                    searchBinding: searchBinding(for: .playlists)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Prevents an outgoing native search control from clearing another tab's retained query.
    private func searchBinding(for category: TrashViewModel.Category) -> Binding<String> {
        Binding(
            get: { model.query(for: category) },
            set: { model.updateSearch($0, in: category) }
        )
    }
}
