import SwiftUI

struct PlaylistSongPicker: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @State var model: PlaylistSongPickerViewModel
    /// SwiftUI presentation action used to close this sheet or editor.
    @Environment(\.dismiss) private var dismiss
    /// Renders searchable songs and selection controls for appending entries to one playlist.
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List(model.visibleTracks) { track in
                Button {
                    model.toggle(track.id)
                } label: {
                    HStack {
                        Image(
                            systemName: model.selected.contains(track.id)
                                ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(track.title).lineLimit(1)
                            Text(track.displayArtist).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("playlistPicker.toggle.\(track.originalFilename)")
            }
            .overlay {
                if model.visibleTracks.isEmpty {
                    if LibrarySearch.isEmpty(model.search) {
                        ContentUnavailableView(
                            L10n.text("No Music Here Yet"),
                            systemImage: "music.note",
                            description: Text(
                                L10n.text("Import music to start organizing your library.")
                            )
                        )
                    } else {
                        ContentUnavailableView.search(text: model.search)
                    }
                }
            }
            .searchable(text: $model.search, prompt: L10n.text("Search Songs"))
            .navigationTitle(
                L10n.text("format.playlist.add_to", String(describing: model.playlist.name))
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("format.playlist.add_count", model.selected.count)) {
                        model.addSelection()
                        dismiss()
                    }
                    .disabled(model.selected.isEmpty)
                    .accessibilityIdentifier("playlistPicker.commit")
                }
            }
        }
        .frame(idealWidth: 500, idealHeight: 600)
    }
}
