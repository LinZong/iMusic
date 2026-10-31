import SwiftUI

/// Independent Listening Statistics settings section.
struct StatisticsSettingsSection: View {
    /// Lifetime statistics and navigation to the detailed report.
    let model: ListeningStatsViewModel

    /// Renders controls and routes user actions to this feature's model.
    var body: some View {
        Section(L10n.text("Listening Statistics")) {
            NavigationLink(L10n.text("View All Listening Statistics")) {
                ListeningStatsView(model: model)
            }
            LabeledContent(
                L10n.text("Total Listening Time"),
                value: musicTime(model.summary.totalSeconds)
            )
            LabeledContent(
                L10n.text("Songs Played"),
                value: "\(model.summary.songCount)"
            )
            if let track = model.summary.topTracks.first {
                LabeledContent(L10n.text("Most Played"), value: track.title)
            }
            Text(
                L10n.text(
                    """
                    Statistics stay on this device. No weekly reports, milestones, or other \
                    unsolicited notifications are sent.
                    """
                )
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}
