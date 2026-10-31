import Foundation

public struct FieldVersion: Codable, Comparable, Sendable, Equatable {
    /// Monotonic logical edit clock used to resolve individual field conflicts.
    public var clock: Int64
    /// Stable writer identity used to break ties when edit clocks are equal.
    public var device: String
    /// Orders logical edit clocks first, then writer identities, so all devices resolve equal-time
    /// edits consistently.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.clock == rhs.clock ? lhs.device < rhs.device : lhs.clock < rhs.clock
    }
}

public struct SyncEnvelope: Codable, Sendable {
    /// Record identity shared by SQLite, backup manifests, and CloudKit record names.
    public var id: String
    /// Record discriminator: track, playlist, or listen.
    public var kind: String
    /// JSON-encoded domain record whose fields are merged using their version stamps.
    public var payload: Data
    /// Per-field edit stamps, including entry-prefixed stamps for playlist occurrence changes.
    public var versions: [String: FieldVersion]
    /// Whether this envelope contains a track with a durable permanent-deletion tombstone.
    public var isPermanentlyDeletedTrack: Bool {
        guard kind == "track", let track = try? JSONDecoder().decode(Track.self, from: payload)
        else { return false }
        return track.permanentlyDeletedAt != nil
    }
    /// Whether this envelope contains a permanently deleted playlist.
    public var isPermanentlyDeletedPlaylist: Bool {
        guard kind == "playlist",
            let playlist = try? JSONDecoder().decode(Playlist.self, from: payload)
        else { return false }
        return playlist.permanentlyDeletedAt != nil
    }
    /// Whether a song or playlist deletion must survive stale synchronization and backup records.
    public var isPermanentlyDeletedRecord: Bool {
        isPermanentlyDeletedTrack || isPermanentlyDeletedPlaylist
    }

    /// Merges matching records field by field using version stamps, merges playlist occurrences
    /// independently, and preserves permanent deletion. Throws for mismatched identities or
    /// malformed JSON.
    public func merged(with other: Self) throws -> Self {
        guard id == other.id, kind == other.kind else {
            throw MusicError.invalidBackup(L10n.text("Record identifiers do not match"))
        }
        var fields = try JSONSerialization.jsonObject(with: payload) as? [String: Any] ?? [:]
        let incoming =
            try JSONSerialization.jsonObject(with: other.payload) as? [String: Any] ?? [:]
        let permanentDeletion =
            kind == "track" || kind == "playlist"
            ? [fields["permanentlyDeletedAt"], incoming["permanentlyDeletedAt"]]
                .compactMap { $0 as? Double }.min() : nil
        var result = self
        for (key, version) in other.versions
        where !key.hasPrefix("entry:") && !(kind == "playlist" && key == "entries")
            && (versions[key].map({ $0 < version }) ?? true)
        {
            fields[key] = incoming[key] ?? NSNull()
            result.versions[key] = version
        }
        if kind == "playlist" {
            let localEntries = (fields["entries"] as? [[String: Any]]) ?? []
            let remoteEntries = (incoming["entries"] as? [[String: Any]]) ?? []
            var entries: [String: [String: Any]] = [:]
            var remote: [String: [String: Any]] = [:]
            for entry in localEntries { if let id = entry["id"] as? String { entries[id] = entry } }
            for entry in remoteEntries { if let id = entry["id"] as? String { remote[id] = entry } }
            for (key, version) in other.versions
            where key.hasPrefix("entry:") && (versions[key].map({ $0 < version }) ?? true) {
                let entryID = String(key.dropFirst(6))
                entries[entryID] = remote[entryID]
                result.versions[key] = version
            }
            fields["entries"] = entries.values.sorted { a, b in
                let lhs = a["order"] as? Double ?? 0
                let rhs = b["order"] as? Double ?? 0
                return lhs == rhs
                    ? (a["id"] as? String ?? "") < (b["id"] as? String ?? "") : lhs < rhs
            }
        }
        // Permanent deletion is monotonic. An old backup or offline edit cannot restore it.
        // An explicit import creates a new identity for the same audio instead.
        if let permanentDeletion {
            fields["permanentlyDeletedAt"] = permanentDeletion
            if kind == "playlist" { fields["entries"] = [] }
        }
        result.payload = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return result
    }
}
