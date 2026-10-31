import Foundation

/// Managed-copy import boundary, replaceable without exposing folder or backup operations.
protocol MusicFileImporting: Sendable {
    /// Imports selected files and publishes per-file progress.
    func importFiles(
        _ urls: [URL],
        skipUnchanged: Bool,
        progress: @escaping @Sendable (ImportProgress) -> Void
    ) async -> ImportProgress
}
extension ImportCoordinator: MusicFileImporting {}

/// Archive boundary shared by export and restore presentation models.
protocol LibraryArchiving: Sendable {
    /// Produces a validated archive at a temporary location.
    func export(includeAudio: Bool) async throws -> URL
    /// Validates and merges an archive, returning missing managed-audio count.
    func restore(from url: URL) async throws -> Int
}
extension BackupService: LibraryArchiving {}

/// Native transfer-page contract; HTTP/NIO details remain behind the listener implementation.
@MainActor
protocol WiFiTransferServing: AnyObject {
    /// Available local HTTP endpoints.
    var addresses: [String] { get }
    /// Ephemeral pairing code.
    var code: String { get }
    /// Latest localized listener failure.
    var error: String? { get }
    /// Starts accepting complete files into the provided staging directory.
    func start(staging: URL, onUpload: @escaping @Sendable (URL) -> Void) async
    /// Stops the listener and invalidates pending startup.
    func stop() async
}
extension WiFiUploadServer: WiFiTransferServing {}
