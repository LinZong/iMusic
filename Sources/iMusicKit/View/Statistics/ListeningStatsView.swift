import Charts
import SwiftUI

struct ListeningStatsView: View {
    /// Feature model containing only this page's state and explicit dependencies.
    @State var model: ListeningStatsViewModel
    /// Renders period-scoped listening totals, daily activity, and the most played songs.
    var body: some View {
        @Bindable var model = model
        PageScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Picker(L10n.text("Time Range"), selection: $model.period) {
                    Text(L10n.text("Last 7 Days")).tag(7)
                    Text(L10n.text("Last 30 Days")).tag(30)
                    Text(L10n.text("All Time")).tag(0)
                }
                .pickerStyle(.segmented)
                Text(musicTime(model.report.totalSeconds))
                    .font(
                        .system(.largeTitle, design: .rounded).bold()
                    )
                Text(L10n.text("Actual listening time · Pauses and seeks are excluded"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.events.isEmpty {
                    ContentUnavailableView(
                        L10n.text("Listen to a song you love"),
                        systemImage: "chart.bar",
                        description: Text(
                            L10n.text(
                                """
                                Your listening history appears here, without an internet connection.
                                """
                            )
                        )
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Chart(model.daily, id: \.date) { day in
                        BarMark(
                            x: .value(L10n.text("Date"), day.date, unit: .day),
                            y: .value(L10n.text("Minutes"), day.seconds / 60)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    .frame(height: 180)
                    Text(L10n.text("Most Played Songs")).font(.title2.bold())
                    ForEach(
                        Array(model.report.topTracks.prefix(10).enumerated()),
                        id: \.element.id
                    ) { index, item in
                        HStack {
                            Text("\(index + 1)").foregroundStyle(.secondary).frame(width: 24)
                            Text(item.title).lineLimit(1)
                            Spacer()
                            Text(musicTime(item.seconds)).monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(L10n.text("Most Played Artists")).font(.title2.bold())
                    ForEach(model.report.topArtists.prefix(10)) { item in
                        HStack {
                            Text(item.title)
                            Spacer()
                            Text(musicTime(item.seconds)).monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }
        .navigationTitle(L10n.text("Listening Statistics")).task { await model.library.refresh() }
    }
}
