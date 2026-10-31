import Foundation
import GRDB

public final class LibraryStore: @unchecked Sendable {
    /// Preference keys allowed in backups; excludes local paths, account state, and device
    /// authorization.
    public static let portableSettings: Set<String> = [
        "audio", "appearance", "vinyl", "homeSections", "splitArtists",
        "artistSeparators",
    ]
    /// Concurrent SQLite pool that serializes writes and keeps record changes atomic with their
    /// sync outbox.
    let database: DatabasePool
    /// Persistent local writer identity used when generating field version stamps.
    public let deviceID: String
    /// Transaction-scoped record/version/outbox writer, independent of typed library use cases.
    private var recordWriter: VersionedRecordRepository {
        VersionedRecordRepository(deviceID: deviceID)
    }
    /// Opens the SQLite pool, creates the initial schema when needed, and loads or generates the
    /// persistent writer identity. Throws on filesystem or database failure.
    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        database = try DatabasePool(path: url.path)
        try LibrarySchema.install(in: database)
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
            .filter { $0.permanentlyDeletedAt == nil && (includeDeleted || $0.deletedAt == nil) }
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
    /// Enqueues an atomic periodic playback checkpoint on GRDB's serial writer, in submission
    /// order with explicit saves; encoding, SQL and completion all run outside the main thread.
    func savePlaybackInBackground(
        _ session: PlaybackSession,
        event: ListenEvent?,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        database.asyncWrite { db in
            if let event {
                try self.recordWriter.saveRecord(
                    id: event.id.uuidString,
                    kind: "listen",
                    value: event,
                    db: db
                )
            }
            let data = try JSONEncoder().encode(session)
            try db.execute(
                sql: """
                    INSERT INTO settings(key,value) VALUES('playback',?) ON CONFLICT(key)
                    DO UPDATE SET value=excluded.value
                    """,
                arguments: [data]
            )
        } completion: { _, result in
            completion(result)
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
                guard
                    let envelope = try VersionedRecordRepository.fetchEnvelope(
                        db,
                        id: id.uuidString
                    ),
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
                try recordWriter.saveRecord(
                    id: track.id.uuidString,
                    kind: "track",
                    value: track,
                    db: db
                )
            }
            try removePermanentlyDeletedReferences(db)
        }
    }
    /// Permanently removes a trashed playlist's entries and queues a durable deletion marker.
    /// Song records, audio files, and the independent playback queue remain untouched.
    public func permanentlyDeletePlaylist(_ id: UUID) throws {
        try database.write { db in
            guard let envelope = try VersionedRecordRepository.fetchEnvelope(db, id: id.uuidString),
                envelope.kind == "playlist"
            else { return }
            var playlist = try JSONDecoder().decode(Playlist.self, from: envelope.payload)
            guard playlist.permanentlyDeletedAt == nil else { return }
            guard playlist.deletedAt != nil else {
                throw MusicError.unavailable(
                    L10n.text("Only playlists in Trash can be permanently deleted.")
                )
            }
            playlist.permanentlyDeletedAt = Date()
            playlist.modifiedAt = Date()
            playlist.entries.removeAll()
            try recordWriter.saveRecord(
                id: id.uuidString,
                kind: "playlist",
                value: playlist,
                db: db
            )
        }
    }
    /// Atomically commits parsed linked metadata and its local locator without syncing bookmarks.
    @discardableResult
    func commitLinkedTrack(_ track: Track, item: LinkedFileBinding) throws -> Bool {
        try database.write { db in
            guard track.isLinked, track.id == item.id else { throw MusicError.missingFile }
            guard
                let folderData = try Data.fetchOne(
                    db,
                    sql: "SELECT value FROM settings WHERE key='folders'"
                ),
                let folders = try? JSONDecoder().decode([FolderSource].self, from: folderData),
                folders.contains(where: {
                    $0.id == item.folderID && $0.usesOriginalFiles == true
                        && $0.bindingGeneration == item.folderGeneration
                })
            else { throw MusicError.permissionDenied }
            var committed = track
            if let existing = try VersionedRecordRepository.fetchEnvelope(
                db,
                id: track.id.uuidString
            ),
                let current = try? JSONDecoder().decode(Track.self, from: existing.payload)
            {
                if current.permanentlyDeletedAt != nil || current.deletedAt != nil { return false }
                LinkedMetadataPipeline.preserveEdits(from: current, in: &committed)
            }
            try recordWriter.saveRecord(
                id: track.id.uuidString,
                kind: "track",
                value: committed,
                db: db
            )
            try db.execute(
                sql: "INSERT OR REPLACE INTO settings(key,value) VALUES(?,?)",
                arguments: [item.storageKey, try JSONEncoder().encode(item)]
            )
            return true
        }
    }
    /// Share the database's writer lock with deletion so a late cloud download cannot recreate a
    /// purged copy.
    func withAvailableTrack(_ id: UUID, perform operation: (Track) throws -> Void) throws {
        try database.write { db in
            guard let envelope = try VersionedRecordRepository.fetchEnvelope(db, id: id.uuidString),
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
            try ManagedMediaCleanup(vault: vault)
                .removeUnreferenced(
                    tracks: tracks,
                    playlists: playlists
                )

        }
    }

    private func removePermanentlyDeletedReferences(_ db: Database) throws {
        let removed = try VersionedRecordRepository.permanentlyDeletedIDs(db)
        guard !removed.isEmpty else { return }
        for data in try Data.fetchAll(db, sql: "SELECT payload FROM records WHERE kind='playlist'")
        {
            var playlist = try JSONDecoder().decode(Playlist.self, from: data)
            guard playlist.entries.contains(where: { removed.contains($0.trackID) }) else {
                continue
            }
            playlist.entries.removeAll { removed.contains($0.trackID) }
            playlist.modifiedAt = Date()
            try recordWriter.saveRecord(
                id: playlist.id.uuidString,
                kind: "playlist",
                value: playlist,
                db: db
            )
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
            try Row.fetchAll(db, sql: "SELECT * FROM records")
                .map(VersionedRecordRepository.envelope)
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
            .map { (try VersionedRecordRepository.envelope($0), $0["generation"]) }
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
        try SyncRecordValidator.validate(envelope)
        try database.write { db in
            let old = try VersionedRecordRepository.fetchEnvelope(db, id: envelope.id)
            let merged = try old?.merged(with: envelope) ?? envelope
            try SyncRecordValidator.validate(merged)
            try VersionedRecordRepository.write(merged, db: db)
            if enqueue
                || (merged.isPermanentlyDeletedRecord && !envelope.isPermanentlyDeletedRecord)
            {
                try VersionedRecordRepository.enqueue(merged.id, db: db)
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
                try SyncRecordValidator.validate(incoming)
                let merged =
                    try VersionedRecordRepository.fetchEnvelope(db, id: incoming.id)?
                    .merged(with: incoming) ?? incoming
                try SyncRecordValidator.validate(merged)
                try VersionedRecordRepository.write(merged, db: db)
                try VersionedRecordRepository.enqueue(merged.id, db: db)
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
        guard !keeper.isLinked,
            duplicates.allSatisfy({ !$0.isLinked && $0.assetHash == keeper.assetHash })
        else {
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
        try database.write { db in
            try recordWriter.saveRecord(id: id, kind: kind, value: value, db: db)
        }
    }

}
