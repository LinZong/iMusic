import SwiftUI

/// Independent About iMusic settings section.
struct AboutSettingsSection: View {
    /// Anonymous diagnostics export workflow.
    let imports: ImportViewModel

    /// Renders controls and routes user actions to this feature's model.
    var body: some View {
        Section(L10n.text("About iMusic")) {
            Text(
                L10n.text(
                    "1.0.0 · Local first. No ads, app accounts, or unsolicited notifications."
                )
            )
            Button(L10n.text("Export Anonymous Diagnostics")) {
                imports.diagnostics.exportDiagnostics()
            }
            Text("SPM · SwiftUI · SFBAudioEngine · GRDB · ZIPFoundation · SwiftNIO")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
