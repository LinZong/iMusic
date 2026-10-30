import Foundation

enum SyncCodec {
    static func encode(_ envelope: SyncEnvelope) throws -> Data {
        let data = try JSONEncoder().encode(envelope)
        let compressed = try (data as NSData).compressed(using: .lzfse) as Data
        guard compressed.count < 900_000 else { throw MusicError.unavailable(L10n.text("This record is too large to sync with iCloud. Your local information has been preserved.")) }
        return compressed
    }
    static func decode(_ data: Data, compressed: Bool) throws -> SyncEnvelope {
        let decoded = compressed ? try (data as NSData).decompressed(using: .lzfse) as Data : data
        guard decoded.count < 32_000_000 else { throw MusicError.invalidBackup(L10n.text("The cloud record is too large")) }
        return try JSONDecoder().decode(SyncEnvelope.self, from: decoded)
    }
}
