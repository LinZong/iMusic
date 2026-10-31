import SwiftUI

/// PlaybackOptionsMenu owns one part of the full-player presentation.
struct PlaybackOptionsMenu: View {
    /// Local full-player presentation state and shared playback dependencies.
    let model: NowPlayingViewModel
    /// Renders this player component using the shared playback session.
    var body: some View {
        Menu {
            Section {
                Button(L10n.text("Back 10 Seconds"), systemImage: "gobackward.10") {
                    model.player.playback.skip(seconds: -10)
                }
                .disabled(!model.player.playback.canSeek)
                Button(L10n.text("Forward 10 Seconds"), systemImage: "goforward.10") {
                    model.player.playback.skip(seconds: 10)
                }
                .disabled(!model.player.playback.canSeek)
            }
            Menu(L10n.text("Sleep Timer"), systemImage: "moon.zzz") {
                Button(L10n.text("Turn Timer Off")) { model.player.playback.setSleep(minutes: nil) }
                ForEach([15, 30, 45, 60], id: \.self) { minute in
                    Button(L10n.text("format.minutes", minute)) {
                        model.player.playback.setSleep(minutes: minute)
                    }
                }
                Button(L10n.text("At the End of This Song")) {
                    model.player.playback.setSleep(minutes: nil, endOfTrack: true)
                }
            }
            Button(L10n.text("Set or Clear A/B Loop")) { model.player.playback.markLoop() }
                .disabled((model.player.playback.track?.sampleRate ?? 0) <= 0)
            Button(L10n.text("Equalizer"), systemImage: "slider.vertical.3") {
                model.equalizer = true
            }
            Menu(L10n.text("Playback Speed")) {
                ForEach([0.5, 0.75, 1, 1.25, 1.5, 2, 3], id: \.self) { rate in
                    Button {
                        model.player.playback.rate = Float(rate)
                    } label: {
                        if model.player.playback.rate == Float(rate) {
                            Label("\(rate.formatted())×", systemImage: "checkmark")
                        } else {
                            Text("\(rate.formatted())×")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3").font(.system(size: 19, weight: .medium))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        #if os(macOS)
        .menuIndicator(.hidden)
        #endif
        .fixedSize()
        .accessibilityLabel(L10n.text("Playback Options"))
        .help(L10n.text("Playback Options"))

    }
}
