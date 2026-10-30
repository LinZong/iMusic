import Foundation
import GRDB

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
            kind == "track"
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
        if let permanentDeletion { fields["permanentlyDeletedAt"] = permanentDeletion }
        result.payload = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return result
    }
}

public final class LibraryStore: @unchecked Sendable {
    /// Preference keys allowed in backups; excludes local paths, account state, and device
    /// authorization.
    public static let portableSettings: Set<String> = [
        "audio", "appearance", "vinyl", "serifFont", "homeSections", "splitArtists",
        "artistSeparators",
    ]
    /// Concurrent SQLite pool that serializes writes and keeps record changes atomic with their
    /// sync outbox.
    private let database: DatabasePool
    /// Persistent local writer identity used when generating field version stamps.
    public let deviceID: String
    /// Opens the SQLite pool, creates the initial schema when needed, and loads or generates the
    /// persistent writer identity. Throws on filesystem or database failure.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        database = try DatabasePool(path: url.path)
        var migrator = DatabaseMigrator()
        // One baseline for the current schema; pre-release development databases are reset.
        migrator.registerMigration("initial-schema") { db in
            try db.execute(
                sql: """
                    CREATE TABLE records (id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload BLOB \
                    NOT NULL,
                      versions BLOB NOT NULL, search TEXT NOT NULL DEFAULT '', hash TEXT);
                    CREATE INDEX records_kind ON records(kind);
                    CREATE INDEX records_hash ON records(hash);
                    CREATE TABLE outbox (id TEXT PRIMARY KEY, generation INTEGER NOT NULL);
                    CREATE TABLE settings (key TEXT PRIMARY KEY, value BLOB NOT NULL);
                    CREATE VIRTUAL TABLE record_search USING fts5(id UNINDEXED, text, \
                    tokenize='unicode61');
                    CREATE TRIGGER records_search_insert AFTER INSERT ON records WHEN \
                    new.kind='track' BEGIN
                      INSERT INTO record_search(id,text) VALUES(new.id,new.search); END;
                    CREATE TRIGGER records_search_update AFTER UPDATE ON records WHEN \
                    new.kind='track' BEGIN
                      DELETE FROM record_search WHERE id=old.id;
                      INSERT INTO record_search(id,text) VALUES(new.id,new.search); END;
                    CREATE TRIGGER records_search_delete AFTER DELETE ON records WHEN \
                    old.kind='track' BEGIN
                      DELETE FROM record_search WHERE id=old.id; END;
                    """
            )
        }
        try migrator.migrate(database)
        deviceID = try database.write { db in
            if let row = try Row.fetchOne(
                db,
                sql: "SELECT value FROM settings WHERE key = 'deviceID'"
            ), let value: String = row["value"] {
                return value
            }
            let value = UUID().uuidString
            try db.execute(
                sql: "INSERT INTO settings(key,value) VALUES('deviceID',?)",
                arguments: [value]
            )
            return value
        }
    }

    /// Loads songs sorted by title, optionally including Trash and applying indexed or escaped
    /// substring search; permanently deleted records are always excluded.
    public func tracks(includeDeleted: Bool = false, query: String = "") throws -> [Track] {
        try database.read { db in
            let rows: [Row]
            if query.isEmpty {
                rows = try Row.fetchAll(db, sql: "SELECT payload FROM records WHERE kind='track'")
            } else {
                let escaped = query.searchKey.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                let terms = query.searchKey.split(whereSeparator: \.isWhitespace)
                if !terms.isEmpty,
                    query.allSatisfy({
                        $0.isASCII && ($0.isLetter || $0.isNumber || $0.isWhitespace)
                    })
                {
                    let match = terms.map { "\"\($0)\"*" }.joined(separator: " AND ")
                    let indexed = try Row.fetchAll(
                        db,
                        sql:
                            """
                            SELECT payload FROM records WHERE kind='track' AND id IN (SELECT id \
                            FROM record_search WHERE record_search MATCH ?)
                            """,
                        arguments: [match]
                    )
                    rows =
                        indexed.isEmpty
                        ? try Row.fetchAll(
                            db,
                            sql:
                                """
                                SELECT payload FROM records WHERE kind='track' AND search LIKE ? \
                                ESCAPE '\\'
                                """,
                            arguments: ["%\(escaped)%"]
                        ) : indexed
                } else {
                    rows = try Row.fetchAll(
                        db,
                        sql:
                            """
                            SELECT payload FROM records WHERE kind='track' AND search LIKE ? \
                            ESCAPE '\\'
                            """,
                        arguments: ["%\(escaped)%"]
                    )
                }
            }
            return try rows.map { try JSONDecoder().decode(Track.self, from: $0["payload"]) }
                .filter {
                    $0.permanentlyDeletedAt == nil && (includeDeleted || $0.deletedAt == nil)
                }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }
    /// Loads a song by its library identity, returning nil for missing or permanently deleted
    /// records; songs in Trash remain queryable.
    public func track(id: UUID) throws -> Track? {
        let track = try record(id: id.uuidString, as: Track.self)
        return track?.permanentlyDeletedAt == nil ? track : nil
    }
    /// Returns durable deletion records used to retry pending managed-file cleanup after
    /// interruption.
    public func permanentlyDeletedTracks() throws -> [Track] {
        try records(kind: "track", as: Track.self).filter { $0.permanentlyDeletedAt != nil }
    }
    /// Checks permanent-deletion history for this library identity before assigning an identity to
    /// an explicit reimport.
    public func wasPermanentlyDeleted(id: UUID) throws -> Bool {
        try record(id: id.uuidString, as: Track.self)?.permanentlyDeletedAt != nil
    }
    /// Checks whether this audio digest was permanently deleted so linked-folder scans do not
    /// silently reimport it.
    public func wasPermanentlyDeleted(hash: String) throws -> Bool {
        try database.read { db in
            try Data.fetchAll(
                db,
                sql: "SELECT payload FROM records WHERE kind='track' AND hash=?",
                arguments: [hash]
            )
            .contains { try JSONDecoder().decode(Track.self, from: $0).permanentlyDeletedAt != nil }
        }
    }
    /// Finds the first non-purged record for a content digest, including a trashed copy that an
    /// import can restore.
    public func track(hash: String) throws -> Track? {
        try database.read { db in
            try Data.fetchAll(
                db,
                sql: "SELECT payload FROM records WHERE kind='track' AND hash=?",
                arguments: [hash]
            )
            .map { try JSONDecoder().decode(Track.self, from: $0) }
            .first { $0.permanentlyDeletedAt == nil }
        }
    }
    /// Loads playlists sorted by name, optionally including recoverable playlists in Trash.
    public func playlists(includeDeleted: Bool = false) throws -> [Playlist] {
        try records(kind: "playlist", as: Playlist.self)
            .filter { includeDeleted || $0.deletedAt == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    /// Loads persisted actual-listening segments for local statistics.
    public func listenEvents() throws -> [ListenEvent] {
        try records(kind: "listen", as: ListenEvent.self)
    }
    /// Persists song metadata with per-field edit stamps and an atomic outbox update; rejects
    /// attempts to revive a permanently deleted identity.
    public func save(_ track: Track) throws {
        try saveRecord(id: track.id.uuidString, kind: "track", value: track)
    }
    /// Validates a nonempty playlist name, normalizes entry order, and persists metadata and outbox
    /// changes atomically.
    public func save(_ playlist: Playlist) throws {
        guard !playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MusicError.invalidName
        }
        var normalized = playlist
        normalized.entries = playlist.entries.enumerated()
            .map { index, entry in
                var entry = entry
                entry.order = Double(index)
                return entry
            }
        try saveRecord(id: playlist.id.uuidString, kind: "playlist", value: normalized)
    }
    /// Persists or updates a listening segment under its stable identity and queues its versioned
    /// record for synchronization.
    public func save(_ event: ListenEvent) throws {
        try saveRecord(id: event.id.uuidString, kind: "listen", value: event)
    }
    /// Decodes a saved preference using the requested Codable type; returns nil when the key does
    /// not exist.
    public func setting<T: Decodable>(_ key: String, as: T.Type) throws -> T? {
        try database.read { db in
            guard
                let data = try Data.fetchOne(
                    db,
                    sql: "SELECT value FROM settings WHERE key=?",
                    arguments: [key]
                )
            else { return nil }
            return try JSONDecoder().decode(T.self, from: data)
        }
    }
    /// JSON-encodes a preference and atomically inserts or replaces its stored value.
    public func setSetting<T: Encodable>(_ key: String, value: T) throws {
        let data = try JSONEncoder().encode(value)
        try database.write { db in
            try db.execute(
                sql:
                    """
                    INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET \
                    value=excluded.value
                    """,
                arguments: [key, data]
            )
        }
    }
    /// Returns only the allowlisted portable preferences, excluding device identity, local paths,
    /// and account authorization.
    public func exportSettings() throws -> [String: Data] {
        try database.read { db in
            var settings: [String: Data] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT key,value FROM settings") {
                let key: String = row["key"]
                if Self.portableSettings.contains(key) { settings[key] = row["value"] }
            }
            return settings
        }
    }
    /// Runs SQLite quick_check and returns whether the database reports a consistent structure.
    public func integrityIsOK() throws -> Bool {
        try database.read { try String.fetchOne($0, sql: "PRAGMA quick_check") == "ok" }
    }
    /// Commit the durable tombstone and reference changes before unlinking files.
    public func permanentlyDeleteTracks(_ ids: Set<UUID>) throws {
        try database.write { db in
            var tracks: [Track] = []
            for id in ids {
                guard let envelope = try Self.fetchEnvelope(db, id: id.uuidString),
                    envelope.kind == "track"
                else { continue }
                let track = try JSONDecoder().decode(Track.self, from: envelope.payload)
                if track.permanentlyDeletedAt != nil { continue }
                guard track.deletedAt != nil else {
                    throw MusicError.unavailable(
                        L10n.text("Only songs in Trash can be permanently deleted.")
                    )
                }
                tracks.append(track)
            }
            for var track in tracks {
                track.permanentlyDeletedAt = Date()
                track.modifiedAt = Date()
                track.isFavorite = false
                try saveRecord(id: track.id.uuidString, kind: "track", value: track, db: db)
            }
            try removePermanentlyDeletedReferences(db)
        }
    }
    /// Share the database's writer lock with deletion so a late cloud download cannot recreate a
    /// purged copy.
    func withAvailableTrack(_ id: UUID, perform operation: (Track) throws -> Void) throws {
        try database.write { db in
            guard let envelope = try Self.fetchEnvelope(db, id: id.uuidString),
                envelope.kind == "track"
            else { throw MusicError.missingFile }
            let track = try JSONDecoder().decode(Track.self, from: envelope.payload)
            guard track.permanentlyDeletedAt == nil, track.deletedAt == nil else {
                throw MusicError.missingFile
            }
            try operation(track)
        }
    }
    /// Tombstones are also a crash-recovery journal for pending local file cleanup.
    public func cleanupPermanentlyDeletedFiles(in vault: MediaVault) throws {
        try database.write { db in
            let tracks =
                try Data.fetchAll(db, sql: "SELECT payload FROM records WHERE kind='track'")
                .map { try JSONDecoder().decode(Track.self, from: $0) }
            let playlists =
                try Data.fetchAll(db, sql: "SELECT payload FROM records WHERE kind='playlist'")
                .map { try JSONDecoder().decode(Playlist.self, from: $0) }
            let retained = tracks.filter { $0.permanentlyDeletedAt == nil }
            let retainedFiles = try Set(retained.map { try vault.url(for: $0).lastPathComponent })
            let retainedArtwork = Set(
                retained.compactMap(\.artworkName) + playlists.compactMap(\.artworkName)
            )
            for track in tracks where track.permanentlyDeletedAt != nil {
                let audio = try vault.url(for: track)
                if !retainedFiles.contains(audio.lastPathComponent) {
                    try vault.removeManagedFileIfPresent(audio)
                }
                if let name = track.artworkName, !retainedArtwork.contains(name),
                    let artwork = vault.artworkURL(name)
                {
                    try vault.removeManagedFileIfPresent(artwork)
                }
            }
        }
    }
    private static func permanentlyDeletedIDs(_ db: Database) throws -> Set<UUID> {
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
    private func removePermanentlyDeletedReferences(_ db: Database) throws {
        let removed = try Self.permanentlyDeletedIDs(db)
        guard !removed.isEmpty else { return }
        for data in try Data.fetchAll(db, sql: "SELECT payload FROM records WHERE kind='playlist'")
        {
            var playlist = try JSONDecoder().decode(Playlist.self, from: data)
            guard playlist.entries.contains(where: { removed.contains($0.trackID) }) else {
                continue
            }
            playlist.entries.removeAll { removed.contains($0.trackID) }
            playlist.modifiedAt = Date()
            try saveRecord(id: playlist.id.uuidString, kind: "playlist", value: playlist, db: db)
        }
        if let data = try Data.fetchOne(db, sql: "SELECT value FROM settings WHERE key='playback'")
        {
            var session = try JSONDecoder().decode(PlaybackSession.self, from: data)
            session.removeTracks(removed)
            try db.execute(
                sql: "UPDATE settings SET value=? WHERE key='playback'",
                arguments: [try JSONEncoder().encode(session)]
            )
        }
    }
    /// Exports every versioned library record, including deletion markers, for backups or
    /// synchronization.
    public func envelopes() throws -> [SyncEnvelope] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM records").map(Self.envelope)
        }
    }
    /// Returns each queued sync envelope with its current outbox generation for conditional
    /// acknowledgement.
    public func pending() throws -> [(SyncEnvelope, Int64)] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT records.*, outbox.generation FROM records JOIN outbox USING(id)"
            )
            .map { (try Self.envelope($0), $0["generation"]) }
        }
    }
    /// Clears an outbox item only if the acknowledged generation still matches, preserving edits
    /// made while an upload was in flight.
    public func acknowledge(id: String, generation: Int64) throws {
        try database.write { db in
            try db.execute(
                sql: "DELETE FROM outbox WHERE id=? AND generation=?",
                arguments: [id, generation]
            )
        }
    }
    /// Queues every current record for upload, increasing generations for records already pending.
    public func markAllForSync() throws {
        try database.write { db in
            try db.execute(
                sql:
                    """
                    INSERT INTO outbox SELECT id,1 FROM records WHERE true ON CONFLICT(id) DO \
                    UPDATE SET generation=generation+1
                    """
            )
        }
    }
    /// Merge and its outbox update commit together; a concurrent local edit cannot be acknowledged
    /// away.
    public func merge(_ envelope: SyncEnvelope, enqueue: Bool = false) throws {
        try validate(envelope)
        try database.write { db in
            let old = try Self.fetchEnvelope(db, id: envelope.id)
            let merged = try old?.merged(with: envelope) ?? envelope
            try validate(merged)
            try Self.write(merged, db: db)
            if enqueue || (merged.isPermanentlyDeletedTrack && !envelope.isPermanentlyDeletedTrack)
            {
                try Self.enqueue(merged.id, db: db)
            }
            if merged.isPermanentlyDeletedTrack || merged.kind == "playlist" {
                try removePermanentlyDeletedReferences(db)
            }
        }
    }
    /// Atomically merges backup envelopes and portable settings, queues restored records for sync,
    /// and removes references to permanently deleted songs.
    public func restore(_ envelopes: [SyncEnvelope], settings: [String: Data] = [:]) throws {
        try database.write { db in
            for incoming in envelopes {
                try validate(incoming)
                let merged =
                    try Self.fetchEnvelope(db, id: incoming.id)?.merged(with: incoming) ?? incoming
                try validate(merged)
                try Self.write(merged, db: db)
                try Self.enqueue(merged.id, db: db)
            }
            try removePermanentlyDeletedReferences(db)
            for (key, value) in settings where Self.portableSettings.contains(key) {
                guard value.count < 1_000_000 else {
                    throw MusicError.invalidBackup(L10n.text("Settings data is too large"))
                }
                try db.execute(
                    sql:
                        """
                        INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET \
                        value=excluded.value
                        """,
                    arguments: [key, value]
                )
            }
        }
    }
    /// Combines identical-content song records into a chosen keeper, redirects playlist references,
    /// preserves favorites and artwork, and trashes duplicate records.
    public func mergeDuplicates(keeping keeperID: UUID, removing ids: Set<UUID>) throws {
        guard var keeper = try track(id: keeperID), !ids.contains(keeperID) else { return }
        let duplicates = try tracks().filter { ids.contains($0.id) }
        guard duplicates.allSatisfy({ $0.assetHash == keeper.assetHash }) else {
            throw MusicError.unavailable(
                L10n.text("Only files with identical contents can be merged.")
            )
        }
        keeper.isFavorite = keeper.isFavorite || duplicates.contains(where: \.isFavorite)
        keeper.artworkName = keeper.artworkName ?? duplicates.compactMap(\.artworkName).first
        var changes: [SyncEnvelope] = []
        let latest = try envelopes().flatMap { $0.versions.values }.map(\.clock).max() ?? 0
        let stamp = FieldVersion(
            clock: max(latest + 1, Int64(Date().timeIntervalSince1970 * 1_000)),
            device: deviceID
        )
        func envelope<T: Encodable>(_ id: UUID, kind: String, value: T) throws -> SyncEnvelope {
            let data = try JSONEncoder().encode(value)
            let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            var versions = Dictionary(uniqueKeysWithValues: fields.keys.map { ($0, stamp) })
            if let playlist = value as? Playlist {
                for entry in playlist.entries { versions["entry:" + entry.id.uuidString] = stamp }
            }
            return SyncEnvelope(id: id.uuidString, kind: kind, payload: data, versions: versions)
        }
        changes.append(try envelope(keeper.id, kind: "track", value: keeper))
        for var duplicate in duplicates {
            duplicate.deletedAt = Date()
            changes.append(try envelope(duplicate.id, kind: "track", value: duplicate))
        }
        for var playlist in try playlists()
        where playlist.entries.contains(where: { ids.contains($0.trackID) }) {
            for index in playlist.entries.indices
            where ids.contains(playlist.entries[index].trackID) {
                playlist.entries[index].trackID = keeperID
            }
            changes.append(try envelope(playlist.id, kind: "playlist", value: playlist))
        }
        try restore(changes)
    }
    private func validate(_ value: SyncEnvelope) throws {
        switch value.kind {
        case "track":
            let track = try JSONDecoder().decode(Track.self, from: value.payload)
            guard value.id == track.id.uuidString, MediaVault.isValidHash(track.assetHash),
                MediaVault.isValidExtension(track.fileExtension)
            else { throw MusicError.invalidBackup(L10n.text("Invalid audio record")) }
        case "playlist":
            let playlist = try JSONDecoder().decode(Playlist.self, from: value.payload)
            guard value.id == playlist.id.uuidString,
                Set(playlist.entries.map(\.id)).count == playlist.entries.count,
                !playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                playlist.entries.allSatisfy({ $0.order?.isFinite ?? true })
            else { throw MusicError.invalidBackup(L10n.text("Invalid playlist record")) }
        case "listen":
            let event = try JSONDecoder().decode(ListenEvent.self, from: value.payload)
            guard value.id == event.id.uuidString else {
                throw MusicError.invalidBackup(L10n.text("Invalid listening record"))
            }
        default: throw MusicError.invalidBackup(L10n.text("Unsupported record type"))
        }
    }
    private func records<T: Decodable>(kind: String, as type: T.Type) throws -> [T] {
        try database.read { db in
            try Data.fetchAll(
                db,
                sql: "SELECT payload FROM records WHERE kind=?",
                arguments: [kind]
            )
            .map { try JSONDecoder().decode(type, from: $0) }
        }
    }
    private func record<T: Decodable>(id: String, as type: T.Type) throws -> T? {
        try database.read { db in
            guard
                let data = try Data.fetchOne(
                    db,
                    sql: "SELECT payload FROM records WHERE id=?",
                    arguments: [id]
                )
            else { return nil }
            return try JSONDecoder().decode(type, from: data)
        }
    }
    private func saveRecord<T: Encodable>(id: String, kind: String, value: T) throws {
        try database.write { db in try saveRecord(id: id, kind: kind, value: value, db: db) }
    }
    private func saveRecord<T: Encodable>(id: String, kind: String, value: T, db: Database) throws {
        let data: Data
        if var playlist = value as? Playlist {
            let removed = try Self.permanentlyDeletedIDs(db)
            playlist.entries.removeAll { removed.contains($0.trackID) }
            data = try JSONEncoder().encode(playlist)
        } else {
            data = try JSONEncoder().encode(value)
        }
        let old = try Self.fetchEnvelope(db, id: id)
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
        try validate(envelope)
        try Self.write(envelope, db: db)
        try Self.enqueue(id, db: db)
    }
    private static func envelope(_ row: Row) throws -> SyncEnvelope {
        SyncEnvelope(
            id: row["id"],
            kind: row["kind"],
            payload: row["payload"],
            versions: try JSONDecoder().decode([String: FieldVersion].self, from: row["versions"])
        )
    }
    private static func fetchEnvelope(_ db: Database, id: String) throws -> SyncEnvelope? {
        try Row.fetchOne(db, sql: "SELECT * FROM records WHERE id=?", arguments: [id]).map(envelope)
    }
    private static func write(_ value: SyncEnvelope, db: Database) throws {
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
    private static func enqueue(_ id: String, db: Database) throws {
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
