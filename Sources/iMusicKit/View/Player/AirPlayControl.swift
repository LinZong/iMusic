import AVKit
import SwiftUI

#if os(iOS)
struct AirPlayControl: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else
struct AirPlayControl: View {
    /// Opens the macOS system sound settings for choosing AirPlay or another output route.
    var body: some View {
        Button {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!
            )
        } label: {
            Image(systemName: "airplayaudio").font(.system(size: 19, weight: .medium))
                .frame(
                    width: 44,
                    height: 44
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            L10n.text("Choose AirPlay or another output in System Sound Settings")
        )
    }
}
#endif
