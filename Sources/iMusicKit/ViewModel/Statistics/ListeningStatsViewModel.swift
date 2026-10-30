import Foundation
import Observation

@MainActor @Observable
final class ListeningStatsViewModel {
  /// Observable library records and record-level actions.
  let library: LibraryViewModel
  /// Number of days included in the report; zero includes the entire listening history.
  var period = 30
  /// Listening segments within the selected reporting period.
  var events: [ListenEvent] {
    library.events.filter {
      period == 0
        || $0.startedAt > Calendar.current.date(byAdding: .day, value: -period, to: Date())!
    }
  }
  /// Listening seconds aggregated by local calendar day for the statistics chart.
  var daily: [(date: Date, seconds: Double)] {
    Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.startedAt) }.map {
      (date: $0.key, seconds: $0.value.reduce(0) { $0 + $1.seconds })
    }.sorted { $0.date < $1.date }
  }
  /// Creates an independent feature model with explicit service and state dependencies.
  init(library: LibraryViewModel) {
    self.library = library
  }
}
