import SwiftUI
import AVKit

struct MiniPlayer: View {
    /// Shared observable app model providing library snapshots and the actions used by this view.
    @Bindable var model: AppModel
    /// Renders current-song metadata and compact playback controls below the active page.
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
    /// Shared observable app model providing library snapshots and the actions used by this view.
    @Bindable var model: AppModel
    /// Creates the standalone macOS player window content backed by the shared app model.
    public init(model: AppModel) { self.model = model }
    /// Renders the standalone macOS compact player window and its expanded-player action.
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

struct SeekBar: View {
    /// Playback timeline and seek commands used to keep drag previews separate from engine time.
    @Bindable var playback: PlaybackCoordinator
    /// Whether a slider drag preview is active and must be committed at the end of the gesture.
    @State private var isDragging = false
    /// Renders an accessible progress slider whose preview is committed only after the interaction ends.
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
    /// Shared observable app model providing library snapshots and the actions used by this view.
    @Bindable var model: AppModel
    /// SwiftUI presentation action used to close this sheet or editor.
    @Environment(\.dismiss) private var dismiss
    /// Renders playback occurrences with selection, removal, reordering, and upcoming-queue controls.
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
    /// Observable equalizer gain, bypass, and speed preferences applied by the playback coordinator.
    @Bindable var playback: PlaybackCoordinator
    /// SwiftUI presentation action used to close this sheet or editor.
    @Environment(\.dismiss) private var dismiss
    /// Display labels for the ten equalizer bands, ordered from bass to treble.
    private let frequencies = ["31 Hz", "62 Hz", "125 Hz", "250 Hz", "500 Hz", "1 kHz", "2 kHz", "4 kHz", "8 kHz", "16 kHz"]
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
    /// Opens the macOS system sound settings for choosing AirPlay or another output route.
    var body: some View { Button { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!) } label: { Image(systemName: "airplayaudio").font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44).contentShape(Rectangle()) }.buttonStyle(.plain).help(L10n.text("Choose AirPlay or another output in System Sound Settings")) }
}
#endif
