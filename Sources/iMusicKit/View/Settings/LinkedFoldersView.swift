import SwiftUI
import UniformTypeIdentifiers

struct LinkedFoldersView: View {
    /// Settings dependencies used to invoke explicit authorization and scan actions.
    let model: SettingsViewModel
    /// Feature-local picker state for explicitly locating a moved or replaced source file.
    @State private var repair: LinkedFileRepairViewModel

    /// Creates source management with a dedicated per-file repair model.
    init(model: SettingsViewModel) {
        self.model = model
        _repair = State(initialValue: LinkedFileRepairViewModel(library: model.library))
    }
    /// Pure snapshot projection that keeps file-provider work out of the view body.
    private var viewModel: LinkedFoldersViewModel { LinkedFoldersViewModel(library: model.library) }

    var body: some View {
        @Bindable var repair = repair
        Form {
            Section {
                Text(
                    L10n.text(
                        """
                        Linked folders play original files without copying audio into iMusic. \
                        Cloud files download through the system before metadata is read. \
                        Unlinking and deleting songs never deletes these originals.
                        """
                    )
                )
                Button(L10n.text("Link Folder…")) {
                    model.imports.relinkFolderID = nil
                    model.imports.showFolderPicker = true
                }
                Button(L10n.text("Scan Linked Folders")) {
                    Task { await model.imports.scanFolders(retryFailures: true) }
                }
                .disabled(model.library.activity.importing || model.library.folders.isEmpty)
            }
            ForEach(viewModel.folders) { folder in
                Section(folder.name) {
                    LabeledContent(L10n.text("Songs"), value: String(viewModel.count(folder)))
                    if folder.usesOriginalFiles != true {
                        Text(
                            L10n.text(
                                """
                                This legacy folder imported copies. Relink to index originals; \
                                existing copies will be kept.
                                """
                            )
                        )
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = folder.error {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    if let date = folder.lastScan {
                        Text(L10n.text("format.folder.last_scan", date.formatted()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button(L10n.text("Relink Folder…")) { model.imports.relinkFolder(folder.id) }
                        .disabled(model.library.activity.importing)
                    if !folder.bookmark.isEmpty {
                        Button(L10n.text("Unlink"), role: .destructive) {
                            model.library.removeFolder(folder.id)
                        }
                    }
                    ForEach(viewModel.problems(folder)) { job in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.relativePath).lineLimit(2)
                            if !folder.bookmark.isEmpty,
                                model.library.tracks.contains(where: { $0.id == job.id })
                            {
                                Button(L10n.text("Locate File…")) { repair.select(job) }
                                    .disabled(model.library.activity.importing)
                            }
                            if let error = job.error {
                                Text(error).font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(L10n.text("Waiting for source file…")).font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $repair.presented,
            allowedContentTypes: [.audio, .data],
            allowsMultipleSelection: false
        ) { repair.accept($0) }
        .formStyle(.grouped)
        .navigationTitle(L10n.text("Linked Folders"))
    }
}
