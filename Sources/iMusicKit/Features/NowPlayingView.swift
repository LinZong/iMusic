import SwiftUI

/// Artwork-led player with a quiet transport hierarchy and native secondary-action menus.
public struct NowPlayingView: View {
    /// Shared library actions and the single playback session used by every app window.
    @Bindable var model: AppModel
    /// Closes the full player without interrupting the current playback session.
    @Environment(\.dismiss) private var dismiss
    /// Accessibility text sizes use a scrollable single column instead of constraining the control panel.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Whether the equalizer editor is presented above the player.
    @State private var equalizer = false

    /// Creates the full player using the existing shared library and playback coordinator.
    public init(model: AppModel) { self.model = model }

    /// Renders adaptive artwork, metadata, transport controls, and optional playback tools.
    public var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                // A wide portrait sheet still needs a single column; text accessibility takes priority.
                let columns = geometry.size.width >= 680
                    && geometry.size.width > geometry.size.height
                    && !dynamicTypeSize.isAccessibilitySize
                let inset: CGFloat = columns ? 32 : 24
                let contentWidth = max(0, min(geometry.size.width - inset * 2, columns ? 960 : 420))
                // Reserve vertical space for metadata and controls before allocating artwork on a phone.
                let coverSize = columns
                    ? min(360, max(160, (contentWidth - 40) * 0.46), max(160, geometry.size.height - 64))
                    : min(contentWidth, max(180, geometry.size.height - 390))
                ScrollView {
                    Group {
                        if columns {
                            HStack(alignment: .center, spacing: 40) {
                                artwork(size: coverSize)
                                controls(compact: geometry.size.height < 420).frame(maxWidth: 420)
                            }
                        } else {
                            VStack(spacing: 28) {
                                artwork(size: coverSize)
                                controls(compact: false)
                            }
                        }
                    }
                    .frame(width: contentWidth)
                    .padding(.horizontal, inset)
                    .padding(.vertical, columns ? (geometry.size.height < 420 ? 12 : 32) : 20)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .background {
                    Rectangle().fill(.background)
                        .overlay {
                            LinearGradient(colors: [Color.accentColor.opacity(0.06), .clear],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                }
            }
            #if os(iOS)
            .navigationTitle(L10n.text("Now Playing"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    PlayerControlButton(symbol: "chevron.down", label: L10n.text("Collapse Player")) { dismiss() }
                }
                ToolbarItem { songOptions }
            }
            #else
            .safeAreaInset(edge: .top, spacing: 0) { desktopHeader }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 600)
        #else
        .frame(idealWidth: 820, idealHeight: 620)
        .presentationDetents([.large])
        #endif
        .sheet(isPresented: $equalizer) { EqualizerView(playback: model.playback) }
        .sheet(isPresented: $model.showQueue) { QueueView(model: model) }
        .sheet(item: $model.editingTrack) { TrackEditor(model: model, original: $0) }
        .onDisappear { model.playback.cancelScrubbing() }
    }

    /// Native track actions shared by the phone navigation bar and the desktop player header.
    @ViewBuilder private var songOptions: some View {
        if let track = model.playback.track {
            Menu { TrackActions(model: model, tracks: [track]) } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            #if os(macOS)
            .menuIndicator(.hidden)
            #endif
            .fixedSize()
            .accessibilityLabel(L10n.text("Song Options"))
            .help(L10n.text("Song Options"))
        } else {
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
        }
    }

    #if os(macOS)
    /// Keeps desktop dismissal and track actions above the wide layout instead of in a dialog footer.
    private var desktopHeader: some View {
        HStack {
            PlayerControlButton(symbol: "chevron.down", label: L10n.text("Collapse Player")) { dismiss() }
            Spacer()
            Text(L10n.text("Now Playing")).font(.headline).accessibilityAddTraits(.isHeader)
            Spacer()
            songOptions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(.bar)
    }
    #endif

    /// Renders the optional vinyl appearance without changing the managed cover or playback state.
    private func artwork(size: CGFloat) -> some View {
        ZStack {
            ArtworkView(track: model.playback.track, vault: model.vault, size: size)
            if model.vinyl {
                Circle().fill(.black.opacity(0.65))
                Circle().stroke(.white.opacity(0.15), lineWidth: 2).padding(18)
                ArtworkView(track: model.playback.track, vault: model.vault, size: size * 0.44).clipShape(Circle())
                Circle().fill(.background).frame(width: 14, height: 14)
            }
        }
        .frame(width: size, height: size)
        .clipShape(model.vinyl ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 18)))
        .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 10)
        .accessibilityHidden(true)
    }

    /// Keeps metadata and primary transport together while less frequent tools remain in a native menu.
    private func controls(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 18) {
            metadata
            SeekBar(playback: model.playback)
            transport(compact: compact)
            utilityBar
            playbackDetails(compact: compact)
            if let error = model.playback.error {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Displays the current title and performer with a separate, full-size favorite target.
    private var metadata: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.playback.track?.title ?? L10n.text("Nothing Playing"))
                    .font(.title2.weight(.semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(model.playback.track?.displayArtist ?? L10n.text("Choose a song you love"))
                    .font(.body).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let track = model.playback.track {
                PlayerControlButton(symbol: track.isFavorite ? "heart.fill" : "heart",
                                    label: track.isFavorite ? L10n.text("Remove from Favorites") : L10n.text("Favorites"),
                                    isSelected: track.isFavorite) { model.toggleFavorite(track) }
            }
        }
    }

    /// Uses three familiar transport symbols with larger play/pause emphasis and no permanent filled disc.
    private func transport(compact: Bool) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            PlayerControlButton(symbol: "backward.fill", label: L10n.text("Previous Track"),
                                symbolSize: compact ? 27 : 30, targetSize: compact ? 56 : 64, isProminent: true) { model.playback.previous() }
            Spacer(minLength: 16)
            PlayerControlButton(symbol: model.playback.isPlaying ? "pause.fill" : "play.fill",
                                label: model.playback.isPlaying ? L10n.text("Pause") : L10n.text("Play"),
                                symbolSize: compact ? 40 : 46, targetSize: compact ? 64 : 76, isProminent: true) { model.playback.toggle() }
            Spacer(minLength: 16)
            PlayerControlButton(symbol: "forward.fill", label: L10n.text("Next Track"),
                                symbolSize: compact ? 27 : 30, targetSize: compact ? 56 : 64, isProminent: true) { model.playback.next() }
            Spacer(minLength: 0)
        }
        .disabled(model.playback.session.entries.isEmpty)
        .padding(.vertical, 2)
    }

    /// Provides direct access to play modes, output routing, playback tools, and the queue.
    private var utilityBar: some View {
        HStack(spacing: 0) {
            PlayerControlButton(symbol: "shuffle",
                                label: model.playback.session.isShuffled ? L10n.text("Turn Shuffle Off") : L10n.text("Turn Shuffle On"),
                                isSelected: model.playback.session.isShuffled) { model.playback.toggleShuffle() }
                .disabled(model.playback.session.entries.isEmpty)
            Spacer(minLength: 4)
            PlayerControlButton(symbol: model.playback.session.repeatMode.symbol,
                                label: model.playback.session.repeatMode.label,
                                isSelected: model.playback.session.repeatMode != .off) {
                model.playback.setRepeat(model.playback.session.repeatMode.next)
            }
            Spacer(minLength: 4)
            AirPlayControl().frame(width: 44, height: 44).accessibilityLabel(L10n.text("Audio Output"))
            Spacer(minLength: 4)
            playbackOptions
            Spacer(minLength: 4)
            PlayerControlButton(symbol: "list.bullet", label: L10n.text("Play Queue")) { model.showQueue = true }
                .disabled(model.playback.session.entries.isEmpty)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }

    /// Preserves seeking, sleep, loop, EQ, and speed features without crowding the primary transport row.
    private var playbackOptions: some View {
        Menu {
            Section {
                Button(L10n.text("Back 10 Seconds"), systemImage: "gobackward.10") { model.playback.skip(seconds: -10) }
                    .disabled(!model.playback.canSeek)
                Button(L10n.text("Forward 10 Seconds"), systemImage: "goforward.10") { model.playback.skip(seconds: 10) }
                    .disabled(!model.playback.canSeek)
            }
            Menu(L10n.text("Sleep Timer"), systemImage: "moon.zzz") {
                Button(L10n.text("Turn Timer Off")) { model.playback.setSleep(minutes: nil) }
                ForEach([15, 30, 45, 60], id: \.self) { minute in
                    Button(L10n.text("format.minutes", minute)) { model.playback.setSleep(minutes: minute) }
                }
                Button(L10n.text("At the End of This Song")) { model.playback.setSleep(minutes: nil, endOfTrack: true) }
            }
            Button(L10n.text("Set or Clear A/B Loop")) { model.playback.markLoop() }
                .disabled((model.playback.track?.sampleRate ?? 0) <= 0)
            Button(L10n.text("Equalizer"), systemImage: "slider.vertical.3") { equalizer = true }
            Menu(L10n.text("Playback Speed")) {
                ForEach([0.5, 0.75, 1, 1.25, 1.5, 2, 3], id: \.self) { rate in
                    Button {
                        model.playback.rate = Float(rate)
                    } label: {
                        if model.playback.rate == Float(rate) {
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

    /// Shows route and format information plus active options so menu-based features retain visible state.
    private func playbackDetails(compact: Bool) -> some View {
        VStack(spacing: 6) {
            if compact, let track = model.playback.track {
                Text("\(model.playback.routeName) · \(track.fileExtension.uppercased()) · \((track.sampleRate / 1_000).formatted()) kHz")
                    .font(.caption2).lineLimit(1)
            } else {
                Text(model.playback.routeName).font(.caption).lineLimit(2)
                if let track = model.playback.track {
                    Text("\(track.fileExtension.uppercased()) · \((track.sampleRate / 1_000).formatted()) kHz")
                        .font(.caption2).monospacedDigit()
                }
            }
            if model.playback.rate != 1 {
                Text("\(L10n.text("Playback Speed")) · \(Double(model.playback.rate).formatted())×").font(.caption)
            }
            if model.playback.loopA != nil {
                Text(model.playback.loopB != nil ? "A ↔ B" : "A · B?").font(.caption.monospaced())
                    .accessibilityLabel(L10n.text("Set or Clear A/B Loop"))
            }
            if model.playback.sleepAtEnd { Text(L10n.text("Pause at the end of this song")).font(.caption) }
            if let deadline = model.playback.sleepDeadline {
                Label { Text(deadline, style: .timer).monospacedDigit() } icon: { Image(systemName: "moon.zzz") }
                    .font(.caption)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}

/// Symbol-only control with a full hit target and explicit state cues for assistive technologies.
private struct PlayerControlButton: View {
    /// Familiar SF Symbol representing the action or its current playback state.
    let symbol: String
    /// Localized action description shared by VoiceOver and pointer tooltips.
    let label: String
    /// Visual symbol size in points, independent of the minimum interactive target.
    var symbolSize: CGFloat = 19
    /// Square hit-region edge length in points; never rendered smaller than 44 points.
    var targetSize: CGFloat = 44
    /// Whether a persistent mode is active and needs a selected background and accessibility trait.
    var isSelected = false
    /// Whether this is a primary transport action rather than a secondary utility action.
    var isProminent = false
    /// Existing playback or library action invoked by the control.
    let action: () -> Void
    /// Renders the symbol and selected state without introducing an always-filled play/pause button.
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : isProminent ? Color.primary : Color.secondary)
                .frame(width: max(44, targetSize), height: max(44, targetSize))
                .background(isSelected ? Color.accentColor.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlayerControlStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(label)
    }
}

/// Quiet press feedback that also respects disabled controls and the system Reduce Motion preference.
private struct PlayerControlStyle: ButtonStyle {
    /// Disables decorative scaling and animation when the user requests reduced motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// System enabled state propagated from the surrounding playback control group.
    @Environment(\.isEnabled) private var isEnabled
    /// Adds a transient press surface while retaining the control's stable layout and hit region.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.07) : .clear,
                        in: RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
