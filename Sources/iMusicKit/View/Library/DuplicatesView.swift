import SwiftUI

struct DuplicatesView: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @Bindable var model: LibraryViewModel
    /// Renders groups of identical audio content and lets the user choose which record to keep.
    var body: some View {
        let groups = Dictionary(grouping: model.tracks, by: \.assetHash).values
            .filter { $0.count > 1 }
        Group {
            if groups.isEmpty {
                PageScrollView {
                    VStack(spacing: 0) {
                        explanation.padding(16)
                        ContentUnavailableView(
                            L10n.text("No Identical Duplicate Songs"),
                            systemImage: "checkmark.circle",
                            description: Text(
                                L10n.text(
                                    """
                                    Similar titles are never automatically treated as \
                                    duplicate files.
                                    """
                                )
                            )
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            } else {
                List {
                    explanation
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, tracks in
                        Section(tracks.first?.title ?? L10n.text("Duplicate Files")) {
                            ForEach(tracks) { track in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(track.title)
                                        Text(track.originalFilename).font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(L10n.text("Keep This Copy and Merge")) {
                                        model.mergeDuplicates(keeper: track, duplicates: tracks)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.text("Find Duplicate Songs"))
    }
    /// Explains the duplicate matching rules above either results or the centered empty state.
    private var explanation: some View {
        Text(
            L10n.text(
                """
                Imports already remove duplicates by file contents. These copies remain after \
                merging a backup or cloud library. Merging preserves playlist references and \
                favorites, and moves other copies to Trash.
                """
            )
        )
        .font(.caption).foregroundStyle(.secondary)
    }

}
