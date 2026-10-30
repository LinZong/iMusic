import Foundation
import CryptoKit

public struct MediaVault: Sendable {
    /// Application-owned library directory containing persistent media, artwork, and import journals.
    public let root: URL
    /// Persistent directory for content-addressed imported audio copies.
    public var media: URL { root.appendingPathComponent("Media", isDirectory: true) }
    /// Persistent directory for imported or edited cover images.
    public var artwork: URL { root.appendingPathComponent("Artwork", isDirectory: true) }
    /// Working directory for uploads, imports, and backup assembly before they are committed.
    public var staging: URL { root.appendingPathComponent("Staging", isDirectory: true) }
    /// Durable import journal directory used to recover interrupted file operations.
    public var journals: URL { root.appendingPathComponent("Journals", isDirectory: true) }
    /// Creates the managed library directories and applies persistent iOS file protection. Throws on
    /// directory or protection errors without clearing existing media.
    public init(root: URL) throws {
        self.root = root
        for directory in [media, artwork, staging, journals] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        // Originals belong to the library, never to a purgeable cache directory.
        #if os(iOS)
        var resource = root
        var values = URLResourceValues(); values.isExcludedFromBackup = false
        try resource.setResourceValues(values)
        for directory in [root, media, artwork, staging, journals] { try Self.protectPersistentFile(directory) }
        #endif
    }
    /// Copies from file providers or CloudKit can retain their source protection class.
    public static func protectPersistentFile(_ url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
    /// Default iMusic directory within this app's Application Support location.
    public static var defaultRoot: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("iMusic", isDirectory: true) }
    /// Resolves a song to its validated content-addressed managed audio path; throws for an unsafe hash or
    /// extension.
    public func url(for track: Track) throws -> URL { try url(hash: track.assetHash, extension: track.fileExtension) }
    /// Constructs a path inside Media only after validating the supplied lowercase SHA-256 digest and short
    /// alphanumeric extension.
    public func url(hash: String, extension ext: String) throws -> URL {
        guard Self.isValidHash(hash), Self.isValidExtension(ext) else { throw MusicError.invalidBackup(L10n.text("Invalid file path")) }
        return media.appendingPathComponent("\(hash).\(ext)")
    }
    /// Resolves a single safe artwork file name inside the managed Artwork directory, returning nil for
    /// missing or unsafe names.
    public func artworkURL(_ name: String?) -> URL? {
        guard let name, !name.isEmpty, !name.contains("\0"), !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else { return nil }
        return artwork.appendingPathComponent(name)
    }
    /// Only unlink a single managed file. Never follow a substituted media directory.
    func removeManagedFileIfPresent(_ url: URL) throws {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard [media.standardizedFileURL.path, artwork.standardizedFileURL.path].contains(parent.path),
              parent.resolvingSymlinksInPath().path == root.resolvingSymlinksInPath().appendingPathComponent(parent.lastPathComponent).standardizedFileURL.path else {
            throw MusicError.unavailable(L10n.text("Invalid managed file location. The source file was not changed."))
        }
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return }
        guard let type = attributes[.type] as? FileAttributeType, type == .typeRegular || type == .typeSymbolicLink else {
            throw MusicError.unavailable(L10n.text("Invalid managed file location. The source file was not changed."))
        }
        // Removing a leaf symlink unlinks the symlink, never its destination.
        try FileManager.default.removeItem(at: url)
    }
    /// Accepts only a 64-character lowercase hexadecimal SHA-256 digest suitable for a managed file name.
    public static func isValidHash(_ hash: String) -> Bool { hash.count == 64 && hash.allSatisfy { "0123456789abcdef".contains($0) } }
    /// Accepts only a short nonempty ASCII alphanumeric extension that cannot introduce path separators.
    public static func isValidExtension(_ ext: String) -> Bool { !ext.isEmpty && ext.count <= 12 && ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } }
    /// Returns whether the song's validated managed audio path currently exists on this device.
    public func contains(_ track: Track) -> Bool { (try? url(for: track)).map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    /// Streams a file through SHA-256 in bounded chunks and returns its lowercase hexadecimal digest;
    /// propagates file-reading errors.
    public static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    /// Derives the initial song identity from the first 128 bits of a validated SHA-256 digest. Callers
    /// must supply a complete valid hash.
    public static func stableID(hash: String) -> UUID {
        let s = Array(hash.prefix(32)); let text = String(s[0..<8]) + "-" + String(s[8..<12]) + "-" + String(s[12..<16]) + "-" + String(s[16..<20]) + "-" + String(s[20..<32])
        return UUID(uuidString: text)!
    }
}
