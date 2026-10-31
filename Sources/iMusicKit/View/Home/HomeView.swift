import SwiftUI

struct HomeView: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @State var model: HomeViewModel
    /// Renders the unfiltered library overview and the user-configured home sections.
    var body: some View {
        PageScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(model.preferences.homeSections.filter(\.enabled)) { section in
                    sectionView(section.id)
                }
                if model.library.tracks.isEmpty {
                    ContentUnavailableView(
                        L10n.text("Start with your first song"),
                        systemImage: "music.note",
                        description: Text(
                            L10n.text(
                                """
                                Import music from Files, iCloud Drive, or your computer. Originals \
                                stay intact, and your collection stays available offline.
                                """
                            )
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(24).frame(maxWidth: 1_200, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
    /// Routes saved section identities to independently maintained section components.
    @ViewBuilder private func sectionView(_ name: String) -> some View {
        switch name {
        case "continue": HomeContinueSection(model: model)
        case "categories": HomeCategoriesSection(model: model)
        case "playlists": HomePlaylistsSection(model: model)
        case "recent": HomeRecentSection(model: model)
        case "statistics": HomeStatisticsSection(model: model)
        default: EmptyView()
        }
    }
}
