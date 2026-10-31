import SwiftUI

/// Touch recovery row with explicit restoration and permanent-deletion gestures.
struct TrashedSongRow: View {
    /// Deleted occurrence being displayed.
    let row: SongRowData
    /// Recovery actions and confirmation owner.
    let model: TrashSongsViewModel

    /// Presents metadata and trailing actions without making the song playable.
    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(track: row.track, vault: model.library.vault, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title).lineLimit(2)
                Text(row.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(musicTime(row.duration)).font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("trash.track.\(row.track.originalFilename)")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                model.requestDeletion([row.id])
            } label: {
                Label(L10n.text("Delete"), systemImage: "trash")
            }
            .accessibilityLabel(L10n.text("Delete Permanently"))
            .disabled(model.isBusy)
            Button {
                model.restore([row.id])
            } label: {
                Label(L10n.text("Restore"), systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
            .disabled(model.isBusy)
        }
    }
}
