import SwiftUI

struct EqualizerView: View {
  /// Observable equalizer gain, bypass, and speed preferences applied by the playback coordinator.
  @Bindable var playback: PlaybackCoordinator
  /// SwiftUI presentation action used to close this sheet or editor.
  @Environment(\.dismiss) private var dismiss
  /// Display labels for the ten equalizer bands, ordered from bass to treble.
  private let frequencies = [
    "31 Hz", "62 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz",
  ]
  /// Renders equalizer presets, individual band gains, bypass, and playback-speed controls.
  var body: some View {
    NavigationStack {
      Form {
        Toggle(L10n.text("Enable Equalizer"), isOn: $playback.eqEnabled)
        Menu(L10n.text("Presets")) {
          Button(L10n.text("Flat")) { playback.eqGains = Array(repeating: 0, count: 10) }
          Button(L10n.text("Bass Boost")) { playback.eqGains = [6, 5, 3, 1, 0, 0, 0, 0, 0, 0] }
          Button(L10n.text("Vocals")) { playback.eqGains = [-3, -2, -1, 1, 3, 4, 3, 1, 0, -1] }
          Button(L10n.text("Bright")) { playback.eqGains = [0, 0, 0, 0, 0, 1, 2, 3, 4, 4] }
        }
        ForEach(0..<10) { index in
          HStack {
            Text(frequencies[index]).font(.caption).frame(width: 60, alignment: .leading)
            Slider(
              value: Binding(
                get: { Double(playback.eqGains[index]) },
                set: { playback.eqGains[index] = Float($0) }), in: -12...12
            ).accessibilityLabel(frequencies[index])
            Text("\(Int(playback.eqGains[index])) dB").font(.caption).monospacedDigit().frame(
              width: 48)
          }
        }
        Text(L10n.text("Headroom reduces clipping when enabled. Disabling bypasses the equalizer."))
          .font(.caption).foregroundStyle(.secondary)
      }.formStyle(.grouped).navigationTitle(L10n.text("10-Band Equalizer")).toolbar {
        ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } }
      }
    }.frame(idealWidth: 480, idealHeight: 600)
  }
}
