import SwiftUI
import UniformTypeIdentifiers

struct BackupExportView: View {
    /// Completed backup or diagnostic file to save or share outside the app.
    let url: URL
    /// Localized heading describing the generated file.
    var title = L10n.text("Backup Ready")
    /// Localized instructions explaining how to retain the exported file.
    var detail = L10n.text(
        "Save the backup outside the app, such as on an external drive or in iCloud Drive."
    )
    /// SwiftUI presentation action used to close this sheet or editor.
    @Environment(\.dismiss) private var dismiss
    /// Local export progress and result; independent of other export sheets.
    @State private var model = BackupExportViewModel()
    /// Renders save and share actions for a generated backup or anonymous diagnostics file.
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "externaldrive.badge.checkmark").font(.system(size: 50))
                    .foregroundStyle(
                        .tint
                    )
                Text(title).font(.title2.bold())
                Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
                ShareLink(item: url) {
                    Label(L10n.text("Save or Share File"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                #if os(macOS)
                Button(L10n.text("Save As…")) {
                    let panel = NSSavePanel()
                    panel.nameFieldStringValue = url.lastPathComponent
                    panel.allowedContentTypes = [
                        UTType(filenameExtension: url.pathExtension) ?? .data
                    ]
                    panel.begin { response in
                        guard response == .OK, let destination = panel.url else { return }
                        Task { await model.save(source: url, destination: destination) }
                    }
                }
                .disabled(model.saving)
                #endif
                if model.saving { ProgressView(L10n.text("Saving…")) }
                if let message = model.message { Text(message).font(.caption) }
            }
            .padding(30).navigationTitle(L10n.text("Export File"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Done")) { dismiss() }.disabled(model.saving)
                }
            }
        }
        .frame(idealWidth: 480, idealHeight: 350)
    }
}
