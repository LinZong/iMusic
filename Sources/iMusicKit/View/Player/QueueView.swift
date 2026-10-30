import SwiftUI

struct QueueView: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @Bindable var model: PlayerViewModel
    /// SwiftUI presentation action used to close this sheet or editor.
    @Environment(\.dismiss) private var dismiss
    /// Renders playback occurrences with selection, removal, reordering, and upcoming-queue
    /// controls.
    var body: some View {
        NavigationStack {
            List {
                ForEach(model.playback.session.entries) { entry in
                    if let track = model.library.tracks.first(where: { $0.id == entry.trackID }) {
                        HStack {
                            if entry.id == model.playback.session.currentID {
                                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                            }
                            Button {
                                model.playback.selectEntry(entry.id)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(track.title).lineLimit(1)
                                    Text(track.displayArtist).font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .contextMenu {
                            Button(L10n.text("Remove from Queue"), role: .destructive) {
                                model.playback.removeEntry(entry.id)
                            }
                        }
                    }
                }
                .onMove { model.playback.moveEntries(from: $0, to: $1) }
                .onDelete { offsets in
                    let ids = offsets.map { model.playback.session.entries[$0].id }
                    for id in ids { model.playback.removeEntry(id) }
                }
            }
            .navigationTitle(L10n.text("format.queue.count", model.playback.session.entries.count))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Done")) { dismiss() }
                }
                ToolbarItem {
                    Button(L10n.text("Clear Upcoming")) { model.playback.clearUpcoming() }
                }
                #if os(iOS)
                ToolbarItem { EditButton() }
                #endif
            }
        }
        .frame(idealWidth: 480, idealHeight: 580)
    }
}
