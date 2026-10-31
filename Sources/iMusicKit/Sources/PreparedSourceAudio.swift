import Foundation
import ObjectiveC
import SFBAudioEngine

/// Transfers one opened decoder from a source worker to the main-actor playback backend.
/// The decoder is created before publication and consumed only on MainActor after awaiting
/// the worker.
public final class PreparedSourceAudio: @unchecked Sendable {
    /// Original URL supplied to hardware-free test backends.
    public let url: URL
    /// Requested initial position, also supplied to deterministic URL-only backends.
    public let position: Double
    /// Source sample rate used when translating an initial position into decoder frames.
    public let sampleRate: Double
    /// Opened decoder whose associated lease survives as long as the audio backend retains it.
    let decoder: any PCMDecoding
    /// Balanced source access retained for test backends and decoder preparation failures.
    private let lease: SourceLease

    init(
        url: URL,
        decoder: any PCMDecoding,
        lease: SourceLease,
        position: Double,
        sampleRate: Double
    ) {
        self.url = url
        self.decoder = decoder
        self.lease = lease
        self.position = position
        self.sampleRate = sampleRate
        // Association ownership follows the actual decoder rather than a UI selection or timer.
        objc_setAssociatedObject(
            decoder,
            Unmanaged.passUnretained(lease).toOpaque(),
            lease,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    /// Hydrates and opens the original under coordination before handing ownership to playback.
    static func prepare(
        track: Track,
        store: LibraryStore,
        position: Double = 0,
        region: ClosedRange<Double>? = nil
    ) async throws -> PreparedSourceAudio {
        try await SourceAccess.perform(playback: true) { operation in
            let lease = try SourceAccess.lease(store: store, track: track)
            return try operation.read(lease.url) { readable in
                let values = try readable.resourceValues(forKeys: [
                    .creationDateKey, .isSymbolicLinkKey, .contentModificationDateKey,
                ])
                guard values.isSymbolicLink != true,
                    lease.created == nil || values.creationDate == nil
                        || lease.created == values.creationDate
                else { throw MusicError.missingFile }
                guard
                    lease.modified == nil || values.contentModificationDate == nil
                        || lease.modified == values.contentModificationDate
                else {
                    throw MusicError.unavailable(
                        L10n.text(
                            """
                            The source file changed. Scan Linked Folders in Settings before \
                            playing it again.
                            """
                        )
                    )
                }
                try lease.checkAuthorization(store)
                let decoder: any PCMDecoding
                if let region, track.sampleRate > 0 {
                    decoder = try AudioRegionDecoder(
                        url: readable,
                        startFrame: Int64(region.lowerBound * track.sampleRate),
                        frameLength: Int64(
                            (region.upperBound - region.lowerBound) * track.sampleRate
                        ),
                        repeatCount: -1
                    )
                } else {
                    decoder = try AudioDecoder(url: readable)
                }
                try decoder.open()
                if position > 0, region == nil, track.sampleRate > 0 {
                    try decoder.seek(to: Int64(position * track.sampleRate))
                }
                try operation.check()
                try lease.checkAuthorization(store)
                return PreparedSourceAudio(
                    url: readable,
                    decoder: decoder,
                    lease: lease,
                    position: position,
                    sampleRate: track.sampleRate
                )
            }
        }
    }
}
