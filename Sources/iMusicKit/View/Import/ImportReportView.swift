import SwiftUI

struct ImportReportView: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @Bindable var model: ImportViewModel
    /// SwiftUI presentation action used to close this sheet or editor.
    @Environment(\.dismiss) private var dismiss
    /// Renders completed import counts and any per-file failures.
    var body: some View {
        NavigationStack {
            List {
                if let report = model.importReport {
                    Section(L10n.text("Import Results")) {
                        LabeledContent(
                            L10n.text("Imported"),
                            value: L10n.text("format.song_count.short", report.imported)
                        )
                        LabeledContent(
                            L10n.text("Already Present / Restored"),
                            value: L10n.text("format.song_count.short", report.duplicates)
                        )
                        LabeledContent(
                            L10n.text("Processed"),
                            value: "\(report.completed) / \(report.total)"
                        )
                    }
                    if !report.errors.isEmpty {
                        Section(L10n.text("Needs Attention")) {
                            ForEach(Array(report.errors.enumerated()), id: \.offset) { _, error in
                                Text(error).font(.caption).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.text("Import Complete"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Done")) { dismiss() }
                }
            }
        }
        .frame(idealWidth: 480, idealHeight: 400)
    }
}
