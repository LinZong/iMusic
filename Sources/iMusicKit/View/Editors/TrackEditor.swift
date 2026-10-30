import SwiftUI

struct TrackEditor: View {
  /// Feature model containing only this page's state and explicit dependencies.
  @State var model: TrackEditorViewModel
  /// SwiftUI presentation action used to close this sheet or editor.
  @Environment(\.dismiss) private var dismiss
  /// Renders editable tags, artwork selection, encoding repair, and optional online cover lookup.
  var body: some View {
    @Bindable var model = model
    NavigationStack {
      Form {
        Section {
          HStack(spacing: 18) {
            ArtworkView(track: model.draft, vault: model.library.vault, size: 80)
            VStack(alignment: .leading) {
              Button(L10n.text("Choose Artwork…")) { model.chooseArtwork = true }
              Text(
                L10n.text(
                  "Changes apply only to iMusic library information. Original music files stay intact."
                )
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
          TextField(L10n.text("Title"), text: $model.draft.title)
          TextField(L10n.text("Artist"), text: $model.draft.artist)
          TextField(L10n.text("Album"), text: $model.draft.album)
          TextField(L10n.text("Album Artist"), text: $model.draft.albumArtist)
          TextField(L10n.text("Genre"), text: $model.draft.genre)
          Stepper(
            L10n.text("format.disc_number", model.draft.discNumber), value: $model.draft.discNumber,
            in: 1...999)
          Stepper(
            L10n.text("format.track_number", model.draft.trackNumber),
            value: $model.draft.trackNumber, in: 0...9_999)
        }
        Section(L10n.text("Text Encoding Repair Preview")) {
          Picker(L10n.text("Try Encoding"), selection: $model.encodingName) {
            Text("Shift-JIS").tag("Shift-JIS")
            Text("GB18030").tag("GB18030")
            Text("UTF-8").tag("UTF-8")
          }
          Button(L10n.text("Preview Decoding")) { model.previewDecoding() }
          if let repaired = model.repaired {
            Text(repaired.joined(separator: "\n")).textSelection(.enabled)
            Button(L10n.text("Apply Preview")) { model.applyPreview() }
          }
          Button(L10n.text("Restore Original File Tags")) { model.restoreOriginalTags() }
        }
        if model.preferences.onlineEnabled {
          Section(L10n.text("Online Artwork Matches")) {
            Button(L10n.text("Search for Album Artwork")) { Task { await model.searchArtwork() } }
              .disabled(model.onlineBusy || model.draft.album.isEmpty)
            if model.onlineBusy { ProgressView() }
            ForEach(model.releases) { release in
              Button {
                Task { await model.chooseRelease(release) }
              } label: {
                VStack(alignment: .leading) {
                  Text(release.title)
                  Text([release.date, release.country].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                }
              }.disabled(model.onlineBusy)
            }
          }
        }
        Section(L10n.text("File Information")) {
          LabeledContent(L10n.text("Original Filename"), value: model.original.originalFilename)
          LabeledContent(L10n.text("Format"), value: model.original.fileExtension.uppercased())
          LabeledContent(L10n.text("Duration"), value: musicTime(model.original.duration))
          Text(model.original.assetHash).font(.caption2.monospaced()).textSelection(.enabled)
        }
        if let error = model.error { Text(error).foregroundStyle(.orange) }
      }.formStyle(.grouped).navigationTitle(L10n.text("Edit Song"))
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button(L10n.text("Save")) {
              model.save()
              dismiss()
            }.disabled(model.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }
    }.frame(idealWidth: 540, idealHeight: 680)
      .fileImporter(
        isPresented: $model.chooseArtwork, allowedContentTypes: [.image],
        onCompletion: model.importArtwork)
  }
}
