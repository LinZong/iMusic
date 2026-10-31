import SwiftUI

struct RelinkSourceView: View {
    /// Source workflows that own the pending proposal and final authorization action.
    let model: FolderImportViewModel
    /// Explicitly selected root and existing references presented for review.
    let preview: FolderRelinkPreview

    var body: some View {
        NavigationStack {
            List {
                Section(preview.name) {
                    Text(
                        L10n.text(
                            """
                            Confirm that this is the same music folder. The paths below will \
                            reconnect existing songs; missing files remain unavailable. No \
                            original files will be changed.
                            """
                        )
                    )
                }
                Section(L10n.text("Songs")) {
                    ForEach(preview.tracks) { track in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                            Text(track.linkedSource?.relativePath ?? track.originalFilename)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(L10n.text("Relink Folder…"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Cancel")) { model.relinkPreview = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Reconnect")) { model.confirmFolderRelink() }
                }
            }
        }
        .frame(idealWidth: 560, idealHeight: 460)
    }
}
