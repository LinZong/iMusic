import SwiftUI

struct PlaylistEditor: View {
  /// Feature model containing only this page's state and explicit dependencies.
  @State var model: PlaylistEditorViewModel
  /// SwiftUI presentation action used to close this sheet or editor.
  @Environment(\.dismiss) private var dismiss
  /// Renders playlist name and cover editing before applying the saved draft.
  var body: some View {
    @Bindable var model = model
    NavigationStack {
      Form {
        Section {
          ArtworkView(
            track: model.library.cover(for: model.playlist), vault: model.library.vault, size: 140)
          Button(L10n.text("Choose Artwork…")) { model.chooseCover = true }
          Button(L10n.text("Use Automatic Artwork")) { model.playlist.artworkName = nil }
        }
        TextField(L10n.text("Playlist Name"), text: $model.playlist.name)
        if let error = model.error { Text(error).foregroundStyle(.orange) }
      }.formStyle(.grouped).navigationTitle(L10n.text("Edit Playlist"))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button(L10n.text("Save")) {
              model.save()
              dismiss()
            }.disabled(model.playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
    }.frame(idealWidth: 440, idealHeight: 400)
      .fileImporter(
        isPresented: $model.chooseCover, allowedContentTypes: [.image],
        onCompletion: model.importArtwork)
  }
}
