import GRDB

/// The sole baseline schema for development installations; owns no record or file operations.
enum LibrarySchema {
    /// Creates the current schema using the existing baseline identifier.
    static func install(in database: DatabasePool) throws {
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
    }
}
