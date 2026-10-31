import Foundation
import ImageIO

/// Cover admission boundary shared by song and playlist draft editors.
protocol ArtworkImporting: Sendable {
    /// Validates and stores bounded image bytes, returning only their managed filename.
    func store(_ data: Data) throws -> String
    /// Reads a user-selected security-scoped cover and stores a validated managed copy.
    func importFile(_ url: URL) throws -> String
}

/// Owns image validation and file access; editors own only the resulting draft reference.
struct ManagedArtworkImporter: ArtworkImporting {
    /// Validated application-owned artwork directory.
    let vault: MediaVault
    /// Admits a decodable image no larger than the shared twenty-megabyte limit.
    func store(_ data: Data) throws -> String {
        guard data.count <= 20_000_000 else {
            throw MusicError.unavailable(L10n.text("Choose an image smaller than 20 MB."))
        }
        guard CGImageSourceCreateWithData(data as CFData, nil) != nil else {
            throw MusicError.unavailable(L10n.text("Unable to read this image."))
        }
        let name = UUID().uuidString + ".image"
        try data.write(to: vault.artwork.appendingPathComponent(name), options: .atomic)
        return name
    }
    /// Bounds the file before reading and balances the explicit source authorization.
    func importFile(_ url: URL) throws -> String {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= 20_000_000
        else {
            throw MusicError.unavailable(L10n.text("Choose an image smaller than 20 MB."))
        }
        return try store(Data(contentsOf: url))
    }
}
