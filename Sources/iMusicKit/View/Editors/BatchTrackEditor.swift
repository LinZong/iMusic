import SwiftUI

struct BatchTrackEditor: View {
  /// Feature model containing only this page's state and explicit dependencies.
  @State var model: BatchTrackEditorViewModel
  /// SwiftUI presentation action used to close this sheet or editor.
  @Environment(\.dismiss) private var dismiss
  /// Renders opt-in metadata replacements so unchecked fields retain their existing values.
  var body: some View {
    @Bindable var model = model
    NavigationStack {
      Form {
        Text(L10n.text("format.batch.instructions", model.tracks.count)).font(.caption)
          .foregroundStyle(.secondary)
        Toggle(L10n.text("Change Artist"), isOn: $model.editArtist)
        if model.editArtist { TextField(L10n.text("Artist"), text: $model.artist) }
        Toggle(L10n.text("Change Album"), isOn: $model.editAlbum)
        if model.editAlbum { TextField(L10n.text("Album"), text: $model.album) }
        Toggle(L10n.text("Change Album Artist"), isOn: $model.editAlbumArtist)
        if model.editAlbumArtist { TextField(L10n.text("Album Artist"), text: $model.albumArtist) }
        Toggle(L10n.text("Change Genre"), isOn: $model.editGenre)
        if model.editGenre { TextField(L10n.text("Genre"), text: $model.genre) }
      }.formStyle(.grouped).navigationTitle(L10n.text("Bulk Edit"))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button(L10n.text("Save")) {
              model.save()
              dismiss()
            }.disabled(
              !model.editArtist && !model.editAlbum && !model.editAlbumArtist && !model.editGenre)
          }
        }
    }.frame(idealWidth: 480, idealHeight: 450)
  }
}
