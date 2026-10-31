import SwiftUI

/// Dedicated statistics section of the configurable Home feed.
struct HomeStatisticsSection: View {
    /// Home feature projections and navigation dependencies.
    let model: HomeViewModel

    /// Renders this section without changing the home feed's other sections.
    var body: some View {

        NavigationLink {
            ListeningStatsView(model: ListeningStatsViewModel(library: model.library))
        } label: {
            HStack {
                Label(L10n.text("Listening Statistics"), systemImage: "chart.bar")
                Spacer()
                Text(musicTime(model.listeningSeconds))
                    .monospacedDigit()
            }
            .padding(18)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)

    }

}
