import SwiftUI

struct SettingsView: View {
  /// Feature model containing only this page's state and explicit dependencies.
  @State var model: SettingsViewModel
  /// Renders playback statistics, appearance, sources, backups, optional network features, and diagnostics.
  var body: some View {
    @Bindable var preferences = model.preferences
    @Bindable var cloud = model.library.cloud
    @Bindable var model = model
    Form {
      Section(L10n.text("Listening Statistics")) {
        NavigationLink(L10n.text("View All Listening Statistics")) {
          ListeningStatsView(model: ListeningStatsViewModel(library: model.library))
        }
        LabeledContent(
          L10n.text("Total Listening Time"),
          value: musicTime(model.library.events.reduce(0) { $0 + $1.seconds }))
        LabeledContent(
          L10n.text("Songs Played"), value: "\(Set(model.library.events.map(\.trackID)).count)")
        let totals = Dictionary(grouping: model.library.events, by: \.trackID).mapValues {
          $0.reduce(0) { $0 + $1.seconds }
        }
        if let favorite = totals.max(by: { $0.value < $1.value }),
          let track = model.library.tracks.first(where: { $0.id == favorite.key })
        {
          LabeledContent(L10n.text("Most Played"), value: track.title)
        }
        Text(
          L10n.text(
            "Statistics stay on this device. No weekly reports, milestones, or other unsolicited notifications are sent."
          )
        ).font(.caption).foregroundStyle(.secondary)
      }
      Section(L10n.text("Appearance")) {
        Picker(L10n.text("Display Mode"), selection: $preferences.appearance) {
          Text(L10n.text("System")).tag("system")
          Text(L10n.text("Light")).tag("light")
          Text(L10n.text("Dark")).tag("dark")
        }
        Toggle(L10n.text("Serif Font"), isOn: $preferences.serifFont)
        Toggle(L10n.text("Vinyl Record Appearance"), isOn: $preferences.vinyl)
        NavigationLink(L10n.text("Customize Home")) { HomeLayoutView(model: model.preferences) }
      }
      Section(L10n.text("Music and Folders")) {
        NavigationLink(L10n.text("Find Duplicate Songs")) { DuplicatesView(model: model.library) }
        Button(L10n.text("Move Empty Playlists to Trash")) {
          for playlist in model.library.playlists where playlist.entries.isEmpty {
            model.library.delete(playlist)
          }
        }
        Button(L10n.text("Import Music Files…")) { model.imports.showImporter = true }
        Button(L10n.text("Wi-Fi Transfer…")) { model.imports.showWiFi = true }
        Button(L10n.text("Link Folder…")) { model.imports.showFolderPicker = true }
        ForEach(model.library.folders) { folder in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Label(folder.name, systemImage: "folder")
              Spacer()
              Button(L10n.text("Unlink"), role: .destructive) {
                model.library.removeFolder(folder.id)
              }
            }
            if let error = folder.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if let date = folder.lastScan {
              Text(L10n.text("format.folder.last_scan", String(describing: date.formatted()))).font(
                .caption
              ).foregroundStyle(.secondary)
            }
          }
        }
        Button(L10n.text("Scan Linked Folders")) { Task { await model.imports.scanFolders() } }
          .disabled(model.library.activity.importing || model.library.folders.isEmpty)
        Toggle(L10n.text("Split Collaborating Artists"), isOn: $preferences.splitArtists)
        if model.preferences.splitArtists {
          TextField(L10n.text("Separators (separate with |)"), text: $preferences.artistSeparators)
        }
        Text(
          L10n.text(
            "Music in linked folders is copied into the managed library. Unlinking never deletes original files. iOS does not continuously monitor folders in the background."
          )
        ).font(.caption).foregroundStyle(.secondary)
      }
      Section(L10n.text("Backup and Restore")) {
        Button(L10n.text("Export Full Backup (Including Music)")) {
          model.imports.exportBackup(full: true)
        }
        Button(L10n.text("Export Library Information")) { model.imports.exportBackup(full: false) }
        Button(L10n.text("Restore from Backup…")) { model.imports.showRestorePicker = true }
        NavigationLink {
          SongListView(
            model: SongListViewModel(
              library: model.library, player: model.player, destination: .trash)
          ).navigationTitle(L10n.text("Trash"))
        } label: {
          LabeledContent(
            L10n.text("Trash"),
            value: L10n.text("format.song_count.short", model.library.deletedTracks.count))
        }
        Text(
          L10n.text(
            "Restores merge information and preserve newer edits. Deleted music stays in Trash and is never automatically erased."
          )
        ).font(.caption).foregroundStyle(.secondary)
      }
      Section(L10n.text("iCloud (Optional)")) {
        Toggle(
          L10n.text("Sync Library"),
          isOn: Binding(
            get: { model.library.cloud.enabled },
            set: { enabled in
              Task {
                if enabled {
                  await model.library.cloud.enable()
                } else {
                  await model.library.cloud.disable()
                }
              }
            })
        ).disabled(!model.library.cloud.available || model.library.cloud.busy)
        Toggle(L10n.text("Also Upload Music and Artwork"), isOn: $cloud.syncAudio).disabled(
          !model.library.cloud.enabled)
        Button(L10n.text("Sync Now")) { Task { await model.library.cloud.sync() } }.disabled(
          !model.library.cloud.enabled || model.library.cloud.busy)
        if model.library.cloud.busy { ProgressView() }
        Text(
          model.library.cloud.available
            ? model.library.cloud.message
            : L10n.text(
              "This is a local build. iCloud requires a developer team, a CloudKit container, and a Cloud build configuration."
            )
        ).font(.caption).foregroundStyle(.secondary)
        Text(
          L10n.text(
            "Imported music stays available offline on this device. Download songs from other devices using the song menu."
          )
        ).font(.caption).foregroundStyle(.secondary)
      }
      Section(L10n.text("Online Metadata (Optional)")) {
        Toggle(
          L10n.text("Allow Online Artwork Search"),
          isOn: Binding(
            get: { model.preferences.onlineEnabled },
            set: {
              if $0 { model.onlineConsent = true } else { model.preferences.onlineEnabled = false }
            }))
        Text(
          L10n.text(
            "Off by default. Search manually from the song editor. Artist and album names are sent to MusicBrainz, and artwork comes from Cover Art Archive. Music files are never uploaded."
          )
        ).font(.caption).foregroundStyle(.secondary)
      }
      Section(L10n.text("About iMusic")) {
        Text(L10n.text("1.0.0 · Local first. No ads, app accounts, or unsolicited notifications."))
        Button(L10n.text("Export Anonymous Diagnostics")) { model.imports.exportDiagnostics() }
        Text("SPM · SwiftUI · SFBAudioEngine · GRDB · ZIPFoundation · SwiftNIO").font(.caption)
          .foregroundStyle(.secondary)
      }
    }.formStyle(.grouped)
      .confirmationDialog(
        L10n.text("Enable Online Metadata Search?"), isPresented: $model.onlineConsent,
        titleVisibility: .visible
      ) {
        Button(L10n.text("Allow Artist and Album Names to Be Sent for Search")) {
          model.preferences.onlineEnabled = true
        }
        Button(L10n.text("Cancel"), role: .cancel) {}
      } message: {
        Text(
          L10n.text(
            "The app connects only when you search manually. MusicBrainz and Cover Art Archive receive the names needed for the query."
          ))
      }
  }
}
