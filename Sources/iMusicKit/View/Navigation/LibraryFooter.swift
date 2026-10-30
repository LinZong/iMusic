import SwiftUI

struct LibraryFooter: View {
    /// Shared playback and operation status used by the scene footer.
    let model: RootViewModel
    /// Import progress, playback errors, and the current-song mini player below the main content.
    var body: some View {
        VStack(spacing: 0) {
            if model.library.activity.importing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(
                            L10n.text(
                                "format.import.progress",
                                model.library.activity.importProgress.completed,
                                model.library.activity.importProgress.total
                            )
                        )
                        .font(.caption)
                        Spacer()
                        Button(L10n.text("Cancel")) { model.imports.cancelImport() }.font(.caption)
                    }
                    ProgressView(
                        value: Double(model.library.activity.importProgress.completed),
                        total: Double(max(1, model.library.activity.importProgress.total))
                    )
                }
                .padding(12).background(.regularMaterial)
            }
            if let error = model.player.playback.error {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).font(.caption).lineLimit(2)
                    Spacer()
                    Button {
                        model.player.playback.clearError()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
                .padding(10).background(.orange.opacity(0.15))
            }
            if model.player.playback.track != nil { MiniPlayer(model: model.player) }
        }
    }
}
