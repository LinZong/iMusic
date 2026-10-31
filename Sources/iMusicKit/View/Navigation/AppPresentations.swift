import SwiftUI
import UniformTypeIdentifiers

/// Hosts cross-feature presentations without owning the individual sheets' editable state.
struct AppPresentations: ViewModifier {
    /// Navigation dependencies needed to route global requests to their feature models.
    @Bindable var model: RootViewModel
    /// Attaches import pickers, feature sheets, errors, and operation progress to the navigation
    /// scene.
    func body(content: Content) -> some View {
        @Bindable var imports = model.imports
        @Bindable var presentation = model.player.presentation
        content
            .fileImporter(
                isPresented: $imports.filePickerPresented,
                allowedContentTypes: pickerTypes,
                allowsMultipleSelection: model.imports.fileImportPurpose == .audio
            ) { result in
                switch result {
                case .success(let urls):
                    switch model.imports.fileImportPurpose {
                    case .audio: model.imports.importURLs(urls)
                    case .folder: if let url = urls.first { model.imports.addFolder(url) }
                    case .backup: if let url = urls.first { model.imports.restoreBackup(url) }
                    }
                case .failure(let error):
                    if (error as NSError).code != NSUserCancelledError {
                        model.library.activity.message = error.localizedDescription
                    }
                }
            }
            .sheet(item: $imports.relinkPreview) { preview in
                RelinkSourceView(model: model.imports, preview: preview)
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
                isPresented: $imports.showWiFi,
                onDismiss: { Task { await model.imports.wifi.stop() } }
            ) { WiFiView(model: model.imports) }
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
                    get: { model.imports.importReport != nil },
                    set: { if !$0 { model.imports.importReport = nil } }
                )
            ) { ImportReportView(model: model.imports) }
            .sheet(
                isPresented: Binding(
                    get: { model.imports.exportedBackup != nil },
                    set: { if !$0 { model.imports.exportedBackup = nil } }
                )
            ) {
                if let url = model.imports.exportedBackup {
                    BackupExportView(url: url, detail: model.imports.backupDetail)
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { model.imports.diagnosticsURL != nil },
                    set: { if !$0 { model.imports.diagnosticsURL = nil } }
                )
            ) {
                if let url = model.imports.diagnosticsURL {
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
        switch model.imports.fileImportPurpose {
        case .audio: [.audio, .data]
        case .folder: [.folder]
        case .backup: [.zip]
        }
    }
}
