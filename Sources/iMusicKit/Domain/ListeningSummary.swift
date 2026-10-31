import Foundation

/// Stable presentation value for one listening-time ranking.
struct ListeningRank: Identifiable {
    /// Song UUID or artist name defining this rank's identity.
    let id: String
    /// Display title resolved from the current library snapshot.
    let title: String
    /// Actual listened seconds, excluding skipped distance and pauses.
    let seconds: Double
}

/// Pure listening aggregation shared by Settings, Home, and the detailed report.
struct ListeningSummary {
    /// Listening segments within the caller's chosen period.
    let events: [ListenEvent]
    /// Active metadata used to resolve song and artist labels.
    let tracks: [Track]
    /// Total actual listening seconds within this snapshot.
    var totalSeconds: Double { events.reduce(0) { $0 + $1.seconds } }
    /// Distinct songs heard, including records subsequently removed from the active library.
    var songCount: Int { Set(events.map(\.trackID)).count }
    /// Song rankings with active metadata, ordered by time then identity for deterministic ties.
    var topTracks: [ListeningRank] {
        let metadata = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return Dictionary(grouping: events, by: \.trackID)
            .compactMap { id, segments in
                metadata[id]
                    .map {
                        ListeningRank(
                            id: id.uuidString,
                            title: $0.title,
                            seconds: segments.reduce(0) { $0 + $1.seconds }
                        )
                    }
            }
            .sorted(by: ranksBefore)
    }
    /// Artist rankings, retaining unknown-artist listening events.
    var topArtists: [ListeningRank] {
        let metadata = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return Dictionary(grouping: events) {
            metadata[$0.trackID]?.displayArtist ?? L10n.text("Unknown Artist")
        }
        .map { name, segments in
            ListeningRank(id: name, title: name, seconds: segments.reduce(0) { $0 + $1.seconds })
        }
        .sorted(by: ranksBefore)
    }
    /// Defines stable order for equal-duration rankings.
    private func ranksBefore(_ lhs: ListeningRank, _ rhs: ListeningRank) -> Bool {
        lhs.seconds == rhs.seconds ? lhs.id < rhs.id : lhs.seconds > rhs.seconds
    }
}
