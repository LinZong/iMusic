import Foundation

/// Central source boundary; an external reference can never fall back to application-owned audio.
struct AudioSourceResolver: Sendable {
    /// Device-local grants and portable song records.
    let store: LibraryStore
    /// Validated application-owned audio layout.
    let vault: MediaVault

    /// Resolves only managed sources, preserving the existing synchronous local playback path.
    func managedURL(_ track: Track) throws -> URL { try vault.url(for: track) }
    /// Prepares an original-file decoder and retains its read grant until the backend releases it.
    func prepare(
        _ track: Track,
        position: Double = 0,
        region: ClosedRange<Double>? = nil
    ) async throws -> PreparedSourceAudio {
        try await PreparedSourceAudio.prepare(
            track: track,
            store: store,
            position: position,
            region: region
        )
    }
}
