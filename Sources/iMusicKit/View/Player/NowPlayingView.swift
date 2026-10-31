import SwiftUI

public struct NowPlayingView: View {
    /// Player-specific state and dependencies shared by the player surfaces.
    @State var model: NowPlayingViewModel
    /// Closes the full player without interrupting the current playback session.
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    /// Owns default keyboard focus at the sheet's navigation scope.
    @FocusState private var playbackFocused: Bool
    #endif
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
                    #if os(macOS)
                    NowPlayingContent(model: model, playbackFocus: $playbackFocused)
                    #else
                    NowPlayingContent(model: model)
                    #endif
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
        .defaultFocus($playbackFocused, true)
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
            .accessibilityIdentifier("player.songOptions")
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

}
