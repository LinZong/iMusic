import SwiftUI

struct WiFiView: View {
  /// Feature model containing only this page's state and explicit dependencies.
  @Bindable var model: ImportViewModel
  /// SwiftUI presentation action used to close this sheet or editor.
  @Environment(\.dismiss) private var dismiss
  /// Renders the local transfer address and pairing code while managing the upload listener lifetime.
  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Image(systemName: "wifi").font(.system(size: 54)).foregroundStyle(.tint)
        Text(L10n.text("Transfer Music from Your Computer")).font(.title2.bold())
        Text(
          L10n.text(
            "Connect your computer and this device to the same trusted local network, then open the address below in a browser."
          )
        ).foregroundStyle(.secondary).multilineTextAlignment(.center)
        if let address = model.wifi.address {
          Text(address).font(.headline.monospaced()).textSelection(.enabled)
          VStack(spacing: 8) {
            Text(L10n.text("Pairing Code")).font(.caption).foregroundStyle(.secondary)
            Text(model.wifi.code).font(.system(size: 38, weight: .semibold, design: .monospaced))
              .textSelection(.enabled)
          }
          Text(L10n.text("Keep this page open. Uploads stop when the app moves to the background."))
            .font(.caption).foregroundStyle(.secondary)
          if model.activity.importProgress.completed > 0 {
            Text(
              L10n.text(
                "format.import.summary", model.activity.importProgress.imported,
                model.activity.importProgress.duplicates)
            ).font(.caption)
          }
        } else if let error = model.wifi.error {
          Text(error).foregroundStyle(.orange)
          Button(L10n.text("Try Again")) { Task { await model.startWiFi() } }
        } else {
          ProgressView(L10n.text("Starting upload service…"))
        }
        Spacer(minLength: 0)
      }.padding(28).frame(maxWidth: 520).frame(maxWidth: .infinity)
        .navigationTitle(L10n.text("Wi-Fi Transfer")).toolbar {
          ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } }
        }
    }.task { await model.startWiFi() }.frame(idealWidth: 500, idealHeight: 470)
  }
}
