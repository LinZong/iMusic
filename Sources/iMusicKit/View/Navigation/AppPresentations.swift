import SwiftUI
import UniformTypeIdentifiers

/// Hosts cross-feature presentations without owning the individual sheets' editable state.
struct AppPresentations: ViewModifier {
    /// Navigation dependencies needed to route global requests to their feature models.
    @Bindable var model: RootViewModel
    /// Attaches import pickers, feature sheets, errors, and operation progress to the navigation
    /// scene.
    func body(content: Content) -> some View {
        @Bindable var picker = model.imports.picker
        @Bindable var transfers = model.imports.transfers
        @Bindable var folders = model.imports.folders
        @Bindable var presentation = model.player.presentation
        content
            .fileImporter(
                isPresented: $picker.presented,
                allowedContentTypes: pickerTypes,
                allowsMultipleSelection: model.imports.picker.purpose == .audio
            ) { model.imports.accept($0) }
            .sheet(item: $folders.relinkPreview) { preview in
                RelinkSourceView(model: model.imports.folders, preview: preview)
            }
            .sheet(isPresented: $presentation.showPlayer) { NowPlayingView(model: model.player) }
            .sheet(
                isPresented: Binding(
                    get: {
                        model.player.presentation.showQueue && !model.player.presentation.showPlayer
                    },
                    set: { model.player.presentation.showQueue = $0 }
                )
            ) { QueueView(model: model.player) }
            .sheet(
                isPresented: $transfers.presented,
                onDismiss: { Task { await model.imports.transfers.server.stop() } }
            ) { WiFiView(model: model.imports.transfers) }
            .sheet(
                item: Binding(
                    get: {
                        model.player.presentation.showPlayer
                            ? nil : model.player.presentation.editingTrack
                    },
                    set: { model.player.presentation.editingTrack = $0 }
                )
            ) {
                TrackEditor(
                    model: TrackEditorViewModel(
                        library: model.library,
                        preferences: model.preferences,
                        original: $0
                    )
                )
            }
            .sheet(
                isPresented: Binding(
                    get: { model.player.presentation.batchEditingTracks != nil },
                    set: { if !$0 { model.player.presentation.batchEditingTracks = nil } }
                )
            ) {
                if let tracks = model.player.presentation.batchEditingTracks {
                    BatchTrackEditor(
                        model: BatchTrackEditorViewModel(library: model.library, tracks: tracks)
                    )
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { model.imports.audio.importReport != nil },
                    set: { if !$0 { model.imports.audio.importReport = nil } }
                )
            ) { ImportReportView(model: model.imports.audio) }
            .sheet(
                isPresented: Binding(
                    get: { model.imports.archives.exportedBackup != nil },
                    set: { if !$0 { model.imports.archives.exportedBackup = nil } }
                )
            ) {
                if let url = model.imports.archives.exportedBackup {
                    BackupExportView(url: url, detail: model.imports.archives.backupDetail)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { model.imports.diagnostics.diagnosticsURL != nil },
                    set: { if !$0 { model.imports.diagnostics.diagnosticsURL = nil } }
                )
            ) {
                if let url = model.imports.diagnostics.diagnosticsURL {
                    BackupExportView(
                        url: url,
                        title: L10n.text("Diagnostics Ready"),
                        detail: L10n.text(
                            """
                            Includes only the system version, counts, and integrity results. Music \
                            names, paths, and account details are excluded.
                            """
                        )
                    )
                }
            }
            .alert(
                "iMusic",
                isPresented: Binding(
                    get: { model.library.activity.message != nil },
                    set: { if !$0 { model.library.activity.message = nil } }
                )
            ) {
                Button(L10n.text("OK"), role: .cancel) { model.library.activity.message = nil }
            } message: {
                Text(model.library.activity.message ?? "")
            }
            .overlay {
                if model.library.activity.isWorking {
                    ProgressView(L10n.text("Processing library…")).padding(28)
                        .background(
                            .regularMaterial,
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                }
            }
    }
    /// Allowed file types for the current audio import, linked-folder, or backup picker operation.
    private var pickerTypes: [UTType] {
        switch model.imports.picker.purpose {
        case .audio: [.audio, .data]
        case .folder: [.folder]
        case .backup: [.zip]
        }
    }
}
