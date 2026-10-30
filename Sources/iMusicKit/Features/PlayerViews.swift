import SwiftUI
import AVKit

struct MiniPlayer: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { model.showPlayer = true } label: {
                    HStack(spacing: 12) { ArtworkView(track: model.playback.track, vault: model.vault, size: 42); VStack(alignment: .leading, spacing: 3) { Text(model.playback.track?.title ?? "iMusic").font(.subheadline.weight(.semibold)).lineLimit(1); Text(model.playback.track?.displayArtist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(minLength: 0) }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(L10n.text("Expand Now Playing"))
                Button { model.playback.toggle() } label: { Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill").font(.title3).frame(width: 36, height: 40) }.buttonStyle(.plain).accessibilityLabel(model.playback.isPlaying ? L10n.text("Pause") : L10n.text("Play"))
                Button { model.playback.next() } label: { Image(systemName: "forward.end.fill").font(.title3).frame(width: 32, height: 40) }.buttonStyle(.plain).accessibilityLabel(L10n.text("Next Track"))
                Button { model.showQueue = true } label: { Image(systemName: "list.bullet").frame(width: 30, height: 40) }.buttonStyle(.plain).accessibilityLabel(L10n.text("Play Queue"))
            }.padding(.horizontal, 16).padding(.vertical, 10)
            GeometryReader { geometry in Rectangle().fill(Color.accentColor).frame(width: geometry.size.width * model.playback.timeline.fraction) }.frame(height: 2).background(.quaternary).clipped().accessibilityHidden(true)
        }.background(.bar)
    }
}

public struct MiniPlayerWindow: View {
    @Bindable var model: AppModel
    public init(model: AppModel) { self.model = model }
    public var body: some View {
        VStack(spacing: 18) {
            ArtworkView(track: model.playback.track, vault: model.vault, size: 220)
            Text(model.playback.track?.title ?? "iMusic").font(.headline).lineLimit(2)
            Text(model.playback.track?.displayArtist ?? L10n.text("Choose music to start playing")).font(.caption).foregroundStyle(.secondary)
            SeekBar(playback: model.playback)
            HStack(spacing: 34) {
                Button { model.playback.previous() } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel(L10n.text("Previous Track"))
                Button { model.playback.toggle() } label: { Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill").font(.title) }.accessibilityLabel(model.playback.isPlaying ? L10n.text("Pause") : L10n.text("Play"))
                Button { model.playback.next() } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel(L10n.text("Next Track"))
            }.buttonStyle(.plain)
        }.padding(24).frame(minWidth: 280, idealWidth: 340)
    }
}

public struct NowPlayingView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var equalizer = false
    public init(model: AppModel) { self.model = model }
    public var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    let width = min(geometry.size.width - 48, 480)
                    VStack(spacing: 24) {
                        ZStack {
                            ArtworkView(track: model.playback.track, vault: model.vault, size: min(width, max(180, geometry.size.height * 0.43)))
                            if model.vinyl {
                                Circle().fill(.black.opacity(0.65)); Circle().stroke(.white.opacity(0.15), lineWidth: 2).padding(18)
                                ArtworkView(track: model.playback.track, vault: model.vault, size: min(width, max(180, geometry.size.height * 0.43)) * 0.44).clipShape(Circle())
                                Circle().fill(.background).frame(width: 14, height: 14)
                            }
                        }.frame(width: min(width, max(180, geometry.size.height * 0.43)), height: min(width, max(180, geometry.size.height * 0.43)))
                            .clipShape(model.vinyl ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 22)))
                            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
                            .padding(.top, 16)
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 6) { Text(model.playback.track?.title ?? L10n.text("Nothing Playing")).font(.title2.bold()).lineLimit(2); Text(model.playback.track?.displayArtist ?? L10n.text("Choose a song you love")).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer(minLength: 0)
                            if let track = model.playback.track {
                                Button { model.toggleFavorite(track) } label: { Image(systemName: track.isFavorite ? "heart.fill" : "heart").font(.title2).foregroundStyle(track.isFavorite ? Color.pink : .primary) }.buttonStyle(.plain).accessibilityLabel(track.isFavorite ? L10n.text("Remove from Favorites") : L10n.text("Favorites"))
                            }
                        }
                        SeekBar(playback: model.playback)
                        HStack {
                            control("backward.end.fill", L10n.text("Previous Track"), size: 25) { model.playback.previous() }
                            Spacer(); control("gobackward.10", L10n.text("Back 10 Seconds"), size: 23) { model.playback.skip(seconds: -10) }.disabled(!model.playback.canSeek)
                            Spacer()
                            Button { model.playback.toggle() } label: { Image(systemName: model.playback.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 31, weight: .semibold)).frame(width: 78, height: 78).foregroundStyle(.background).background(.primary, in: Circle()) }.buttonStyle(.plain).accessibilityLabel(model.playback.isPlaying ? L10n.text("Pause") : L10n.text("Play"))
                            Spacer(); control("goforward.10", L10n.text("Forward 10 Seconds"), size: 23) { model.playback.skip(seconds: 10) }.disabled(!model.playback.canSeek)
                            Spacer(); control("forward.end.fill", L10n.text("Next Track"), size: 25) { model.playback.next() }
                        }
                        HStack {
                            Button { model.playback.toggleShuffle() } label: { Image(systemName: "shuffle").foregroundStyle(model.playback.session.isShuffled ? Color.accentColor : .secondary) }.accessibilityLabel(model.playback.session.isShuffled ? L10n.text("Turn Shuffle Off") : L10n.text("Turn Shuffle On"))
                            Spacer()
                            Button { model.playback.setRepeat(model.playback.session.repeatMode.next) } label: { Image(systemName: model.playback.session.repeatMode.symbol).foregroundStyle(model.playback.session.repeatMode == .off ? Color.secondary : Color.accentColor) }.accessibilityLabel(model.playback.session.repeatMode.label)
                            Spacer(); AirPlayControl().frame(width: 30, height: 30); Spacer()
                            Button { model.showQueue = true } label: { Image(systemName: "list.bullet") }.accessibilityLabel(L10n.text("Play Queue"))
                        }.font(.title3).buttonStyle(.plain).padding(.horizontal, 12)
                        HStack(spacing: 20) {
                            Menu {
                                Button(L10n.text("Turn Timer Off")) { model.playback.setSleep(minutes: nil) }
                                ForEach([15, 30, 45, 60], id: \.self) { minute in Button(L10n.text("format.minutes", minute)) { model.playback.setSleep(minutes: minute) } }
                                Button(L10n.text("At the End of This Song")) { model.playback.setSleep(minutes: nil, endOfTrack: true) }
                            } label: { Image(systemName: model.playback.sleepDeadline != nil || model.playback.sleepAtEnd ? "moon.zzz.fill" : "moon.zzz").accessibilityLabel(L10n.text("Sleep Timer")) }
                            Button { model.playback.markLoop() } label: { Text(model.playback.loopB != nil ? "A ↔ B" : model.playback.loopA != nil ? "A · B?" : "A · B").font(.caption.bold()) }.accessibilityLabel(L10n.text("Set or Clear A/B Loop"))
                            Button { equalizer = true } label: { Image(systemName: "slider.vertical.3").accessibilityLabel(L10n.text("Equalizer")) }
                            Menu { ForEach([0.5, 0.75, 1, 1.25, 1.5, 2, 3], id: \.self) { rate in Button("\(rate.formatted())×") { model.playback.rate = Float(rate) } } } label: { Text("\(Double(model.playback.rate).formatted())×").monospacedDigit().accessibilityLabel(L10n.text("Playback Speed")) }
                        }.buttonStyle(.plain).foregroundStyle(.secondary)
                        VStack(spacing: 5) {
                            Text(model.playback.routeName).font(.caption).lineLimit(1)
                            if let track = model.playback.track { Text("\(track.fileExtension.uppercased()) · \((track.sampleRate / 1_000).formatted()) kHz").font(.caption2) }
                            if model.playback.sleepAtEnd { Text(L10n.text("Pause at the end of this song")).font(.caption) }
                            if let deadline = model.playback.sleepDeadline { Text(deadline, style: .timer).font(.caption).monospacedDigit() }
                        }.foregroundStyle(.secondary)
                        if let error = model.playback.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    }.frame(width: max(0, width)).padding(.horizontal, 24).padding(.bottom, 24).frame(maxWidth: .infinity)
                }.background(Color.accentColor.opacity(0.04))
            }
            .navigationTitle(L10n.text("Now Playing"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "chevron.down").accessibilityLabel(L10n.text("Collapse Player")) } }; ToolbarItem { if let track = model.playback.track { Menu { TrackActions(model: model, tracks: [track]) } label: { Image(systemName: "ellipsis") } } } }
        }
        .frame(idealWidth: 520, idealHeight: 800)
        .sheet(isPresented: $equalizer) { EqualizerView(playback: model.playback) }
        .sheet(isPresented: $model.showQueue) { QueueView(model: model) }
        .sheet(item: $model.editingTrack) { TrackEditor(model: model, original: $0) }
        .onDisappear { model.playback.cancelScrubbing() }
    }
    private func control(_ symbol: String, _ label: String, size: CGFloat, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: symbol).font(.system(size: size)).frame(minWidth: 36, minHeight: 44) }.buttonStyle(.plain).accessibilityLabel(label) }
}

struct SeekBar: View {
    @Bindable var playback: PlaybackCoordinator
    @State private var isDragging = false
    var body: some View {
        VStack(spacing: 4) {
            Slider(value: Binding(get: { playback.timeline.fraction }, set: {
                playback.beginScrubbing(fraction: $0)
                // Keyboard and accessibility adjustments may have no drag-end event.
                if !isDragging { playback.endScrubbing() }
            }), in: 0...1, onEditingChanged: { editing in
                isDragging = editing
                if !editing { playback.endScrubbing() }
            })
                .disabled(!playback.canSeek).accessibilityLabel(L10n.text("Playback Position"))
                .accessibilityValue(L10n.text("format.playback.position", String(describing: musicTime(playback.timeline.displayedTime)), String(describing: musicTime(playback.timeline.duration))))
                .accessibilityAdjustableAction { direction in
                    guard playback.canSeek else { return }
                    switch direction {
                    case .increment: playback.skip(seconds: 5)
                    case .decrement: playback.skip(seconds: -5)
                    @unknown default: break
                    }
                }
            HStack { Text(musicTime(playback.timeline.displayedTime)); Spacer(); Text(musicTime(playback.timeline.duration)).accessibilityLabel(L10n.text("format.duration.total", String(describing: musicTime(playback.timeline.duration)))) }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).clipped()
    }
}

struct QueueView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(model.playback.session.entries) { entry in
                    if let track = model.tracks.first(where: { $0.id == entry.trackID }) {
                        HStack { if entry.id == model.playback.session.currentID { Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint) }; Button { model.playback.selectEntry(entry.id) } label: { VStack(alignment: .leading) { Text(track.title).lineLimit(1); Text(track.displayArtist).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }.buttonStyle(.plain) }
                            .contextMenu { Button(L10n.text("Remove from Queue"), role: .destructive) { model.playback.removeEntry(entry.id) } }
                    }
                }.onMove { model.playback.moveEntries(from: $0, to: $1) }
                    .onDelete { offsets in let ids = offsets.map { model.playback.session.entries[$0].id }; ids.forEach { model.playback.removeEntry($0) } }
            }.navigationTitle(L10n.text("format.queue.count", model.playback.session.entries.count))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Done")) { dismiss() } }; ToolbarItem { Button(L10n.text("Clear Upcoming")) { model.playback.clearUpcoming() } }
                    #if os(iOS)
                    ToolbarItem { EditButton() }
                    #endif
                }
        }.frame(idealWidth: 480, idealHeight: 580)
    }
}

struct EqualizerView: View {
    @Bindable var playback: PlaybackCoordinator
    @Environment(\.dismiss) private var dismiss
    private let frequencies = ["31 Hz", "62 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz"]
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
                ForEach(0..<10) { index in HStack { Text(frequencies[index]).font(.caption).frame(width: 60, alignment: .leading); Slider(value: Binding(get: { Double(playback.eqGains[index]) }, set: { playback.eqGains[index] = Float($0) }), in: -12...12).accessibilityLabel(frequencies[index]); Text("\(Int(playback.eqGains[index])) dB").font(.caption).monospacedDigit().frame(width: 48) } }
                Text(L10n.text("Headroom reduces clipping when enabled. Disabling bypasses the equalizer.")).font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped).navigationTitle(L10n.text("10-Band Equalizer")).toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } }
        }.frame(idealWidth: 480, idealHeight: 600)
    }
}

#if os(iOS)
struct AirPlayControl: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.prioritizesVideoDevices = false; return view }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else
struct AirPlayControl: View {
    var body: some View { Button { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!) } label: { Image(systemName: "airplayaudio") }.help(L10n.text("Choose AirPlay or another output in System Sound Settings")) }
}
#endif
