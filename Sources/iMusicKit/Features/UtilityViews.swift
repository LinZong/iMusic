import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import CoreFoundation

struct WiFiView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "wifi").font(.system(size: 54)).foregroundStyle(.tint)
                Text(L10n.text("Transfer Music from Your Computer")).font(.title2.bold())
                Text(L10n.text("Connect your computer and this device to the same trusted local network, then open the address below in a browser.")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if let address = model.wifi.address {
                    Text(address).font(.headline.monospaced()).textSelection(.enabled)
                    VStack(spacing: 8) { Text(L10n.text("Pairing Code")).font(.caption).foregroundStyle(.secondary); Text(model.wifi.code).font(.system(size: 38, weight: .semibold, design: .monospaced)).textSelection(.enabled) }
                    Text(L10n.text("Keep this page open. Uploads stop when the app moves to the background.")).font(.caption).foregroundStyle(.secondary)
                    if model.importProgress.completed > 0 { Text(L10n.text("format.import.summary", model.importProgress.imported, model.importProgress.duplicates)).font(.caption) }
                } else if let error = model.wifi.error { Text(error).foregroundStyle(.orange); Button(L10n.text("Try Again")) { Task { await model.startWiFi() } } }
                else { ProgressView(L10n.text("Starting upload service…")) }
                Spacer(minLength: 0)
            }.padding(28).frame(maxWidth: 520).frame(maxWidth: .infinity)
                .navigationTitle(L10n.text("Wi-Fi Transfer")).toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } }
        }.task { await model.startWiFi() }.frame(idealWidth: 500, idealHeight: 470)
    }
}

struct ImportReportView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let report = model.importReport {
                    Section(L10n.text("Import Results")) { LabeledContent(L10n.text("Imported"), value: L10n.text("format.song_count.short", report.imported)); LabeledContent(L10n.text("Already Present / Restored"), value: L10n.text("format.song_count.short", report.duplicates)); LabeledContent(L10n.text("Processed"), value: "\(report.completed) / \(report.total)") }
                    if !report.errors.isEmpty { Section(L10n.text("Needs Attention")) { ForEach(Array(report.errors.enumerated()), id: \.offset) { _, error in Text(error).font(.caption).textSelection(.enabled) } } }
                }
            }.navigationTitle(L10n.text("Import Complete")).toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } } }
        }.frame(idealWidth: 480, idealHeight: 400)
    }
}

struct BackupExportView: View {
    let url: URL
    var title = L10n.text("Backup Ready")
    var detail = L10n.text("Save the backup outside the app, such as on an external drive or in iCloud Drive.")
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var saving = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "externaldrive.badge.checkmark").font(.system(size: 50)).foregroundStyle(.tint)
                Text(title).font(.title2.bold())
                Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
                ShareLink(item: url) { Label(L10n.text("Save or Share File"), systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
                #if os(macOS)
                Button(L10n.text("Save As…")) {
                    let panel = NSSavePanel(); panel.nameFieldStringValue = url.lastPathComponent; panel.allowedContentTypes = [UTType(filenameExtension: url.pathExtension) ?? .data]
                    panel.begin { response in
                        guard response == .OK, let destination = panel.url else { return }; saving = true
                        Task {
                            do { try await Task.detached {
                                let temporary = destination.deletingLastPathComponent().appendingPathComponent(".iMusic-" + UUID().uuidString + ".zip")
                                defer { try? FileManager.default.removeItem(at: temporary) }
                                try FileManager.default.copyItem(at: url, to: temporary)
                                if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
                                else { try FileManager.default.moveItem(at: temporary, to: destination) }
                            }.value; message = L10n.text("File saved.") } catch { message = error.localizedDescription }; saving = false
                        }
                    }
                }.disabled(saving)
                #endif
                if saving { ProgressView(L10n.text("Saving…")) }; if let message { Text(message).font(.caption) }
            }.padding(30).navigationTitle(L10n.text("Export File")).toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() }.disabled(saving) } }
        }.frame(idealWidth: 480, idealHeight: 350)
    }
}

struct TrackEditor: View {
    @Bindable var model: AppModel
    let original: Track
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Track
    @State private var chooseArtwork = false
    @State private var releases: [OnlineRelease] = []
    @State private var onlineBusy = false
    @State private var error: String?
    @State private var encodingName = "Shift-JIS"
    @State private var repaired: [String]?
    init(model: AppModel, original: Track) { self.model = model; self.original = original; _draft = State(initialValue: original) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 18) { ArtworkView(track: draft, vault: model.vault, size: 80); VStack(alignment: .leading) { Button(L10n.text("Choose Artwork…")) { chooseArtwork = true }; Text(L10n.text("Changes apply only to iMusic library information. Original music files stay intact.")).font(.caption).foregroundStyle(.secondary) } }
                    TextField(L10n.text("Title"), text: $draft.title); TextField(L10n.text("Artist"), text: $draft.artist); TextField(L10n.text("Album"), text: $draft.album); TextField(L10n.text("Album Artist"), text: $draft.albumArtist); TextField(L10n.text("Genre"), text: $draft.genre)
                    Stepper(L10n.text("format.disc_number", draft.discNumber), value: $draft.discNumber, in: 1...999)
                    Stepper(L10n.text("format.track_number", draft.trackNumber), value: $draft.trackNumber, in: 0...9_999)
                }
                Section(L10n.text("Text Encoding Repair Preview")) {
                    Picker(L10n.text("Try Encoding"), selection: $encodingName) { Text("Shift-JIS").tag("Shift-JIS"); Text("GB18030").tag("GB18030"); Text("UTF-8").tag("UTF-8") }
                    Button(L10n.text("Preview Decoding")) {
                        let encoding: String.Encoding = encodingName == "Shift-JIS" ? .shiftJIS : encodingName == "UTF-8" ? .utf8 : String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
                        repaired = [draft.title, draft.artist, draft.album].map { value in
                            guard let bytes = value.data(using: .isoLatin1) ?? value.data(using: .windowsCP1252), let text = String(data: bytes, encoding: encoding), !text.contains("\u{fffd}") else { return value }; return text
                        }
                    }
                    if let repaired { Text(repaired.joined(separator: "\n")).textSelection(.enabled); Button(L10n.text("Apply Preview")) { draft.title = repaired[0]; draft.artist = repaired[1]; draft.album = repaired[2]; self.repaired = nil } }
                    Button(L10n.text("Restore Original File Tags")) { draft.title = original.originalMetadata["title"] ?? original.title; draft.artist = original.originalMetadata["artist"] ?? original.artist; draft.album = original.originalMetadata["album"] ?? original.album; draft.albumArtist = original.originalMetadata["albumArtist"] ?? original.albumArtist; draft.genre = original.originalMetadata["genre"] ?? original.genre }
                }
                if model.onlineEnabled {
                    Section(L10n.text("Online Artwork Matches")) {
                        Button(L10n.text("Search for Album Artwork")) {
                            onlineBusy = true; error = nil
                            Task { defer { onlineBusy = false }; do { releases = try await model.online.search(album: draft.album, artist: draft.artist); if releases.isEmpty { error = L10n.text("No matching album found. Please choose artwork manually.") } } catch { self.error = error.localizedDescription } }
                        }.disabled(onlineBusy || draft.album.isEmpty)
                        if onlineBusy { ProgressView() }
                        ForEach(releases) { release in
                            Button { onlineBusy = true; Task { defer { onlineBusy = false }; do { let data = try await model.online.artwork(for: release); try setArtwork(data) } catch { self.error = error.localizedDescription } } } label: { VStack(alignment: .leading) { Text(release.title); Text([release.date, release.country].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) } }.disabled(onlineBusy)
                        }
                    }
                }
                Section(L10n.text("File Information")) { LabeledContent(L10n.text("Original Filename"), value: original.originalFilename); LabeledContent(L10n.text("Format"), value: original.fileExtension.uppercased()); LabeledContent(L10n.text("Duration"), value: musicTime(original.duration)); Text(original.assetHash).font(.caption2.monospaced()).textSelection(.enabled) }
                if let error { Text(error).foregroundStyle(.orange) }
            }.formStyle(.grouped).navigationTitle(L10n.text("Edit Song"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Save")) { model.save(draft); dismiss() }.disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                }
        }.frame(idealWidth: 540, idealHeight: 680)
        .fileImporter(isPresented: $chooseArtwork, allowedContentTypes: [.image]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= 20_000_000 else { throw MusicError.unavailable(L10n.text("Choose an image smaller than 20 MB.")) }
                try setArtwork(Data(contentsOf: url))
            } catch { self.error = error.localizedDescription }
        }
    }
    private func setArtwork(_ data: Data) throws {
        guard CGImageSourceCreateWithData(data as CFData, nil) != nil else { throw MusicError.unavailable(L10n.text("Unable to read this image.")) }
        let name = UUID().uuidString + ".image"; try data.write(to: model.vault.artwork.appendingPathComponent(name), options: .atomic); draft.artworkName = name
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var onlineConsent = false
    var body: some View {
        Form {
            Section(L10n.text("Listening Statistics")) {
                NavigationLink(L10n.text("View All Listening Statistics")) { ListeningStatsView(model: model) }
                LabeledContent(L10n.text("Total Listening Time"), value: musicTime(model.events.reduce(0) { $0 + $1.seconds }))
                LabeledContent(L10n.text("Songs Played"), value: "\(Set(model.events.map(\.trackID)).count)")
                let totals = Dictionary(grouping: model.events, by: \.trackID).mapValues { $0.reduce(0) { $0 + $1.seconds } }
                if let favorite = totals.max(by: { $0.value < $1.value }), let track = model.tracks.first(where: { $0.id == favorite.key }) { LabeledContent(L10n.text("Most Played"), value: track.title) }
                Text(L10n.text("Statistics stay on this device. No weekly reports, milestones, or other unsolicited notifications are sent.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("Appearance")) {
                Picker(L10n.text("Display Mode"), selection: $model.appearance) { Text(L10n.text("System")).tag("system"); Text(L10n.text("Light")).tag("light"); Text(L10n.text("Dark")).tag("dark") }
                Toggle(L10n.text("Serif Font"), isOn: $model.serifFont); Toggle(L10n.text("Vinyl Record Appearance"), isOn: $model.vinyl)
                NavigationLink(L10n.text("Customize Home")) { HomeLayoutView(model: model) }
            }
            Section(L10n.text("Music and Folders")) {
                NavigationLink(L10n.text("Find Duplicate Songs")) { DuplicatesView(model: model) }
                Button(L10n.text("Move Empty Playlists to Trash")) { for playlist in model.playlists where playlist.entries.isEmpty { model.delete(playlist) } }
                Button(L10n.text("Import Music Files…")) { model.showImporter = true }; Button(L10n.text("Wi-Fi Transfer…")) { model.showWiFi = true }; Button(L10n.text("Link Folder…")) { model.showFolderPicker = true }
                ForEach(model.folders) { folder in VStack(alignment: .leading, spacing: 4) { HStack { Label(folder.name, systemImage: "folder"); Spacer(); Button(L10n.text("Unlink"), role: .destructive) { model.removeFolder(folder.id) } }; if let error = folder.error { Text(error).font(.caption).foregroundStyle(.orange) }; if let date = folder.lastScan { Text(L10n.text("format.folder.last_scan", String(describing: date.formatted()))).font(.caption).foregroundStyle(.secondary) } } }
                Button(L10n.text("Scan Linked Folders")) { Task { await model.scanFolders() } }.disabled(model.importing || model.folders.isEmpty)
                Toggle(L10n.text("Split Collaborating Artists"), isOn: $model.splitArtists)
                if model.splitArtists { TextField(L10n.text("Separators (separate with |)"), text: $model.artistSeparators) }
                Text(L10n.text("Music in linked folders is copied into the managed library. Unlinking never deletes original files. iOS does not continuously monitor folders in the background.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("Backup and Restore")) {
                Button(L10n.text("Export Full Backup (Including Music)")) { model.exportBackup(full: true) }; Button(L10n.text("Export Library Information")) { model.exportBackup(full: false) }; Button(L10n.text("Restore from Backup…")) { model.showRestorePicker = true }
                NavigationLink { SongListView(model: model, destination: .trash).navigationTitle(L10n.text("Trash")) } label: { LabeledContent(L10n.text("Trash"), value: L10n.text("format.song_count.short", model.deletedTracks.count)) }
                Text(L10n.text("Restores merge information and preserve newer edits. Deleted music stays in Trash and is never automatically erased.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("iCloud (Optional)")) {
                Toggle(L10n.text("Sync Library"), isOn: Binding(get: { model.cloud.enabled }, set: { enabled in Task { if enabled { await model.cloud.enable() } else { await model.cloud.disable() } } })).disabled(!model.cloud.available || model.cloud.busy)
                Toggle(L10n.text("Also Upload Music and Artwork"), isOn: Binding(get: { model.cloud.syncAudio }, set: { model.cloud.syncAudio = $0 })).disabled(!model.cloud.enabled)
                Button(L10n.text("Sync Now")) { Task { await model.cloud.sync() } }.disabled(!model.cloud.enabled || model.cloud.busy)
                if model.cloud.busy { ProgressView() }
                Text(model.cloud.available ? model.cloud.message : L10n.text("This is a local build. iCloud requires a developer team, a CloudKit container, and a Cloud build configuration.")).font(.caption).foregroundStyle(.secondary)
                Text(L10n.text("Imported music stays available offline on this device. Download songs from other devices using the song menu.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("Online Metadata (Optional)")) {
                Toggle(L10n.text("Allow Online Artwork Search"), isOn: Binding(get: { model.onlineEnabled }, set: { if $0 { onlineConsent = true } else { model.onlineEnabled = false } }))
                Text(L10n.text("Off by default. Search manually from the song editor. Artist and album names are sent to MusicBrainz, and artwork comes from Cover Art Archive. Music files are never uploaded.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L10n.text("About iMusic")) { Text(L10n.text("1.0.0 · Local first. No ads, app accounts, or unsolicited notifications.")); Button(L10n.text("Export Anonymous Diagnostics")) { model.exportDiagnostics() }; Text("SPM · SwiftUI · SFBAudioEngine · GRDB · ZIPFoundation · SwiftNIO").font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped)
            .confirmationDialog(L10n.text("Enable Online Metadata Search?"), isPresented: $onlineConsent, titleVisibility: .visible) { Button(L10n.text("Allow Artist and Album Names to Be Sent for Search")) { model.onlineEnabled = true }; Button(L10n.text("Cancel"), role: .cancel) {} } message: { Text(L10n.text("The app connects only when you search manually. MusicBrainz and Cover Art Archive receive the names needed for the query.")) }
    }
}

struct HomeLayoutView: View {
    @Bindable var model: AppModel
    var body: some View {
        List {
            ForEach($model.homeSections) { $section in
                HStack {
                    Toggle(section.title, isOn: $section.enabled)
                    #if os(macOS)
                    Button { move(section.id, delta: -1) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless)
                    Button { move(section.id, delta: 1) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless)
                    #endif
                }
            }.onMove { model.homeSections.move(fromOffsets: $0, toOffset: $1) }
            Button(L10n.text("Restore Default Layout")) { model.homeSections = HomeSectionOption.defaults }
        }.navigationTitle(L10n.text("Customize Home"))
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
    }
    private func move(_ id: String, delta: Int) {
        guard let index = model.homeSections.firstIndex(where: { $0.id == id }), model.homeSections.indices.contains(index + delta) else { return }
        model.homeSections.swapAt(index, index + delta)
    }
}
