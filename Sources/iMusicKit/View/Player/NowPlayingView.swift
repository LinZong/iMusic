import SwiftUI

public struct NowPlayingView: View {
    /// Player-specific state and dependencies shared by the player surfaces.
    @State var model: NowPlayingViewModel
    /// Closes the full player without interrupting the current playback session.
    @Environment(\.dismiss) private var dismiss
    /// Accessibility text sizes use a scrollable single column instead of constraining the control
    /// panel.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Creates the full player using the existing shared library and playback coordinator.
    public init(model: PlayerViewModel) { self.model = NowPlayingViewModel(player: model) }

    /// Renders adaptive artwork, metadata, transport controls, and optional playback tools.
    public var body: some View {
        @Bindable var presentation = model.player.presentation
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.player.playback.track == nil {
                    ContentUnavailableView(
                        L10n.text("Nothing Playing"),
                        systemImage: "music.note",
                        description: Text(L10n.text("Choose music to start playing"))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    playerContent
                }
            }

            #if os(iOS)
            .navigationTitle(L10n.text("Now Playing"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    PlayerControlButton(symbol: "chevron.down", label: L10n.text("Collapse Player"))
                    {
                        dismiss()
                    }
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
        .sheet(isPresented: $model.equalizer) { EqualizerView(playback: model.player.playback) }
        .sheet(isPresented: $presentation.showQueue) { QueueView(model: model.player) }
        .sheet(item: $presentation.editingTrack) {
            TrackEditor(
                model: TrackEditorViewModel(
                    library: model.player.library,
                    preferences: model.player.preferences,
                    original: $0
                )
            )
        }
        .onDisappear { model.player.playback.cancelScrubbing() }
    }

    /// Adaptive artwork and transport layout, shown only when a current track exists.
    private var playerContent: some View {
        GeometryReader { geometry in
            // A wide portrait sheet still needs a single column; text accessibility takes
            // priority.
            let columns =
                geometry.size.width >= 680
                && geometry.size.width > geometry.size.height
                && !dynamicTypeSize.isAccessibilitySize
            let inset: CGFloat = columns ? 32 : 24
            let contentWidth = max(0, min(geometry.size.width - inset * 2, columns ? 960 : 420))
            // Reserve vertical space for metadata and controls before allocating artwork on a
            // phone.
            let coverSize =
                columns
                ? min(
                    360,
                    max(160, (contentWidth - 40) * 0.46),
                    max(160, geometry.size.height - 64)
                )
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
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.06), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
            }
        }
    }

    /// Native track actions shared by the phone navigation bar and the desktop player header.
    @ViewBuilder private var songOptions: some View {
        if let track = model.player.playback.track {
            Menu {
                TrackActions(model: model.player, tracks: [track])
            } label: {
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
    /// Keeps desktop dismissal and track actions above the wide layout instead of in a dialog
    /// footer.
    private var desktopHeader: some View {
        HStack {
            PlayerControlButton(symbol: "chevron.down", label: L10n.text("Collapse Player")) {
                dismiss()
            }
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
        Group {
            if model.player.preferences.vinyl {
                ZStack {
                    cover(size: size)
                    Circle().fill(.black.opacity(0.65))
                    Circle().stroke(.white.opacity(0.15), lineWidth: 2).padding(18)
                    cover(size: size * 0.44).clipShape(Circle())
                    Circle().fill(.background).frame(width: 14, height: 14)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                cover(size: size)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        // Composite the finished cover before applying a shadow to its outer silhouette.
        .compositingGroup()
        .shadow(color: .black.opacity(0.14), radius: 20, x: 0, y: 10)
        .accessibilityHidden(true)
    }

    /// Uses the same managed cover loader for the full-size artwork and the vinyl label.
    private func cover(size: CGFloat) -> some View {
        ArtworkView(
            track: model.player.playback.track,
            vault: model.player.library.vault,
            size: size
        )
    }

    /// Keeps metadata and primary transport together while less frequent tools remain in a native
    /// menu.
    private func controls(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 18) {
            metadata
            SeekBar(playback: model.player.playback)
            transport(compact: compact)
            #if os(macOS)
            VolumeControl(playback: model.player.playback)
            #endif
            utilityBar
            playbackDetails(compact: compact)
            if let error = model.player.playback.error {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Displays the current title and performer with a separate, full-size favorite target.
    private var metadata: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.player.playback.track?.title ?? L10n.text("Nothing Playing"))
                    .font(.title2.weight(.semibold)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    model.player.playback.track?.displayArtist
                        ?? L10n.text("Choose a song you love")
                )
                .font(.body).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if let track = model.player.playback.track {
                PlayerControlButton(
                    symbol: track.isFavorite ? "heart.fill" : "heart",
                    label: track.isFavorite
                        ? L10n.text("Remove from Favorites") : L10n.text("Favorites"),
                    isSelected: track.isFavorite
                ) { model.player.library.toggleFavorite(track) }
            }
        }
    }

    /// Uses three familiar transport symbols with larger play/pause emphasis and no permanent
    /// filled disc.
    private func transport(compact: Bool) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            PlayerControlButton(
                symbol: "backward.fill",
                label: L10n.text("Previous Track"),
                symbolSize: compact ? 27 : 30,
                targetSize: compact ? 56 : 64,
                isProminent: true
            ) { model.player.playback.previous() }
            Spacer(minLength: 16)
            PlayerControlButton(
                symbol: model.player.playback.isPlaying ? "pause.fill" : "play.fill",
                label: model.player.playback.isPlaying ? L10n.text("Pause") : L10n.text("Play"),
                symbolSize: compact ? 40 : 46,
                targetSize: compact ? 64 : 76,
                isProminent: true
            ) { model.player.playback.toggle() }
            Spacer(minLength: 16)
            PlayerControlButton(
                symbol: "forward.fill",
                label: L10n.text("Next Track"),
                symbolSize: compact ? 27 : 30,
                targetSize: compact ? 56 : 64,
                isProminent: true
            ) { model.player.playback.next() }
            Spacer(minLength: 0)
        }
        .disabled(model.player.playback.session.entries.isEmpty)
        .padding(.vertical, 2)
    }

    /// Provides direct access to play modes, output routing, playback tools, and the queue.
    private var utilityBar: some View {
        HStack(spacing: 0) {
            PlayerControlButton(
                symbol: "shuffle",
                label: model.player.playback.session.isShuffled
                    ? L10n.text("Turn Shuffle Off") : L10n.text("Turn Shuffle On"),
                isSelected: model.player.playback.session.isShuffled
            ) { model.player.playback.toggleShuffle() }
            .disabled(model.player.playback.session.entries.isEmpty)
            Spacer(minLength: 4)
            PlayerControlButton(
                symbol: model.player.playback.session.repeatMode.symbol,
                label: model.player.playback.session.repeatMode.label,
                isSelected: model.player.playback.session.repeatMode != .off
            ) {
                model.player.playback.setRepeat(model.player.playback.session.repeatMode.next)
            }
            Spacer(minLength: 4)
            AirPlayControl().frame(width: 44, height: 44)
                .accessibilityLabel(L10n.text("Audio Output"))
            Spacer(minLength: 4)
            playbackOptions
            Spacer(minLength: 4)
            PlayerControlButton(symbol: "list.bullet", label: L10n.text("Play Queue")) {
                model.player.presentation.showQueue = true
            }
            .disabled(model.player.playback.session.entries.isEmpty)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
    }

    /// Preserves seeking, sleep, loop, EQ, and speed features without crowding the primary
    /// transport row.
    private var playbackOptions: some View {
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

    /// Shows route and format information plus active options so menu-based features retain visible
    /// state.
    private func playbackDetails(compact: Bool) -> some View {
        VStack(spacing: 6) {
            if compact, let track = model.player.playback.track {
                Text(
                    """
                    \(model.player.playback.routeName) · \(track.fileExtension.uppercased()) · \
                    \((track.sampleRate / 1_000).formatted()) kHz
                    """
                )
                .font(.caption2).lineLimit(1)
            } else {
                Text(model.player.playback.routeName).font(.caption).lineLimit(2)
                if let track = model.player.playback.track {
                    Text(
                        """
                        \(track.fileExtension.uppercased()) · \
                        \((track.sampleRate / 1_000).formatted()) kHz
                        """
                    )
                    .font(.caption2).monospacedDigit()
                }
            }
            if model.player.playback.rate != 1 {
                Text(
                    """
                    \(L10n.text("Playback Speed")) · \
                    \(Double(model.player.playback.rate).formatted())×
                    """
                )
                .font(.caption)
            }
            if model.player.playback.loopA != nil {
                Text(model.player.playback.loopB != nil ? "A ↔ B" : "A · B?")
                    .font(.caption.monospaced())
                    .accessibilityLabel(L10n.text("Set or Clear A/B Loop"))
            }
            if model.player.playback.sleepAtEnd {
                Text(L10n.text("Pause at the end of this song")).font(.caption)
            }
            if let deadline = model.player.playback.sleepDeadline {
                Label {
                    Text(deadline, style: .timer).monospacedDigit()
                } icon: {
                    Image(systemName: "moon.zzz")
                }
                .font(.caption)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }
}
