import Foundation
import GRDB

/// Version-stamped record and outbox writes inside the caller's existing transaction.
/// Never opens a nested writer or commits independently of the surrounding use case.
struct VersionedRecordRepository {
    /// Stable device identity used to resolve equal-clock field updates.
    let deviceID: String
    static func permanentlyDeletedIDs(_ db: Database) throws -> Set<UUID> {
        Set(
            try String.fetchAll(
                db,
                sql:
                    """
                    SELECT id FROM records WHERE kind='track' AND json_extract(CAST(payload AS \
                    TEXT),'$.permanentlyDeletedAt') IS NOT NULL
                    """
            )
            .compactMap(UUID.init(uuidString:))
        )
    }
    func saveRecord<T: Encodable>(id: String, kind: String, value: T, db: Database) throws {
        let data: Data
        if var playlist = value as? Playlist {
            let removed = try Self.permanentlyDeletedIDs(db)
            playlist.entries.removeAll { removed.contains($0.trackID) }
            if playlist.permanentlyDeletedAt != nil { playlist.entries.removeAll() }
            data = try JSONEncoder().encode(playlist)
        } else {
            data = try JSONEncoder().encode(value)
        }
        let old = try Self.fetchEnvelope(db, id: id)
        if old?.isPermanentlyDeletedPlaylist == true,
            (value as? Playlist)?.permanentlyDeletedAt == nil
        {
            throw MusicError.unavailable(
                L10n.text("This playlist was permanently deleted. Create a new playlist instead.")
            )
        }
        if old?.isPermanentlyDeletedTrack == true, (value as? Track)?.permanentlyDeletedAt == nil {
            throw MusicError.unavailable(
                L10n.text("This song was permanently deleted. Import it again to add a new copy.")
            )
        }
        var versions = old?.versions ?? [:]
        let oldFields =
            try old.map { try JSONSerialization.jsonObject(with: $0.payload) as? NSDictionary }
            ?? nil
        let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if let oldFields, oldFields == fields as NSDictionary { return }
        let lastClock = versions.values.map(\.clock).max() ?? 0
        let clock = max(Int64(Date().timeIntervalSince1970 * 1_000), lastClock + 1)
        for key in Set(fields.keys).union(versions.keys) {
            if key.hasPrefix("entry:") || (kind == "playlist" && key == "entries") { continue }
            let previous = oldFields?[key] as? NSObject
            let next = fields[key] as? NSObject
            if previous != next { versions[key] = FieldVersion(clock: clock, device: deviceID) }
        }
        if kind == "playlist" {
            let before = (oldFields?["entries"] as? [[String: Any]]) ?? []
            let after = (fields["entries"] as? [[String: Any]]) ?? []
            let beforeMap = Dictionary(
                uniqueKeysWithValues: before.compactMap { entry in
                    (entry["id"] as? String).map { ($0, entry as NSDictionary) }
                }
            )
            let afterMap = Dictionary(
                uniqueKeysWithValues: after.compactMap { entry in
                    (entry["id"] as? String).map { ($0, entry as NSDictionary) }
                }
            )
            for key in Set(beforeMap.keys).union(afterMap.keys)
            where beforeMap[key] != afterMap[key] {
                versions["entry:" + key] = FieldVersion(clock: clock, device: deviceID)
            }
        }
        let envelope = SyncEnvelope(id: id, kind: kind, payload: data, versions: versions)
        try SyncRecordValidator.validate(envelope)
        try Self.write(envelope, db: db)
        try Self.enqueue(id, db: db)
    }
    static func envelope(_ row: Row) throws -> SyncEnvelope {
        SyncEnvelope(
            id: row["id"],
            kind: row["kind"],
            payload: row["payload"],
            versions: try JSONDecoder().decode([String: FieldVersion].self, from: row["versions"])
        )
    }
    static func fetchEnvelope(_ db: Database, id: String) throws -> SyncEnvelope? {
        try Row.fetchOne(db, sql: "SELECT * FROM records WHERE id=?", arguments: [id]).map(envelope)
    }
    static func write(_ incoming: SyncEnvelope, db: Database) throws {
        var value = incoming
        if value.isPermanentlyDeletedPlaylist {
            var playlist = try JSONDecoder().decode(Playlist.self, from: value.payload)
            playlist.entries.removeAll()
            value.payload = try JSONEncoder().encode(playlist)
        }
        var search = ""
        var hash: String?
        if value.kind == "track" {
            let track = try JSONDecoder().decode(Track.self, from: value.payload)
            if track.permanentlyDeletedAt == nil {
                search =
                    [track.title, track.artist, track.album, track.originalFilename, track.genre]
                    .joined(separator: " ").searchKey
            }
            hash = track.assetHash
        }
        try db.execute(
            sql:
                """
                INSERT INTO records(id,kind,payload,versions,search,hash) VALUES(?,?,?,?,?,?) ON \
                CONFLICT(id) DO UPDATE SET \
                payload=excluded.payload,versions=excluded.versions,\
                search=excluded.search,hash=excluded.hash
                """,
            arguments: [
                value.id, value.kind, value.payload, try JSONEncoder().encode(value.versions),
                search, hash,
            ]
        )
    }
    static func enqueue(_ id: String, db: Database) throws {
        try db.execute(
            sql:
                """
                INSERT INTO outbox(id,generation) VALUES(?,1) ON CONFLICT(id) DO UPDATE SET \
                generation=generation+1
                """,
            arguments: [id]
        )
    }
}
