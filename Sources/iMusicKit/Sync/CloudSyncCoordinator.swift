import CloudKit
import Foundation
import Observation

@MainActor @Observable
public final class CloudSyncCoordinator {
    /// Whether a CloudKit worker has been started for the current account.
    public private(set) var enabled = false
    /// Whether an enable or synchronization operation is in progress.
    public private(set) var busy = false
    /// Localized status or error shown in iCloud settings.
    public private(set) var message = L10n.text("Not Enabled")
    /// Whether explicit synchronization also uploads locally available audio assets.
    public var syncAudio = false
    /// Optional provisioned CloudKit container identifier supplied by the app build.
    public let containerIdentifier: String?
    /// Whether this build declares a nonempty CloudKit container identifier.
    public var available: Bool { containerIdentifier?.isEmpty == false }
    /// SQLite library store used by this service to read records and persist atomic changes.
    private let store: LibraryStore
    /// Application-owned media layout used to resolve validated files and working directories.
    private let vault: MediaVault
    /// Actor owning the current account's CloudKit engine and asset operations.
    private var worker: CloudSyncWorker?
    /// Callback requesting a native library refresh after synchronized data changes.
    public var onChange: (() -> Void)?
    /// Creates a disabled sync coordinator for an optional provisioned container; initialization
    /// does not start network operations.
    public init(store: LibraryStore, vault: MediaVault, containerIdentifier: String?) {
        self.store = store
        self.vault = vault
        self.containerIdentifier = containerIdentifier
    }
    /// Validates the configured iCloud account, starts its isolated sync worker, persists consent,
    /// and performs initial synchronization. Account changes require explicit authorization when
    /// requested by the caller.
    public func enable(allowAccountChange: Bool = true) async {
        guard let identifier = containerIdentifier, !identifier.isEmpty else {
            message = L10n.text(
                """
                iCloud is not configured in this build. Use a developer team with iCloud access \
                and a Cloud build configuration.
                """
            )
            return
        }
        busy = true
        defer { busy = false }
        do {
            let worker = CloudSyncWorker(store: store, vault: vault, identifier: identifier) {
                [weak self] text, changed, accountChanged in
                Task { @MainActor in
                    guard let self else { return }
                    self.message = text
                    if accountChanged {
                        self.enabled = false
                        self.worker = nil
                    }
                    if changed { self.onChange?() }
                }
            }
            try await worker.start(allowAccountChange: allowAccountChange)
            self.worker = worker
            enabled = true
            try store.setSetting("cloudEnabled", value: true)
            await sync()
        } catch {
            message = error.localizedDescription
            enabled = false
        }
    }
    /// Stops the active sync worker and persists the disabled preference while preserving the local
    /// library.
    public func disable() async {
        let old = worker
        worker = nil
        enabled = false
        message = L10n.text("Not Enabled")
        try? store.setSetting("cloudEnabled", value: false)
        await old?.stop()
    }
    /// Synchronizes versioned metadata and referenced artwork, optionally uploading local audio
    /// when syncAudio is enabled; publishes status and refresh callbacks.
    public func sync() async {
        guard let worker else { return }
        busy = true
        message = L10n.text("Syncing…")
        defer { busy = false }
        do {
            try await worker.synchronize()
            let tracks = try store.tracks()
            let playlists = try store.playlists()
            let artworkNames = Set(
                tracks.compactMap(\.artworkName) + playlists.compactMap(\.artworkName)
            )
            // A metadata-only library still needs its artwork. Never fetch audio here.
            for name in artworkNames { try await worker.synchronizeArtwork(name) }
            if syncAudio {
                let tracks = try store.tracks()
                for track in tracks where vault.contains(track) {
                    try Task.checkCancellation()
                    try await worker.upload(track)
                }
            }
            message = L10n.text("Sync Complete")
            onChange?()
        } catch { message = error.localizedDescription }
    }
    /// Explicitly downloads a song's verified cloud assets and publishes completion or an error
    /// through the coordinator status.
    public func download(_ track: Track) async {
        guard let worker else {
            message = L10n.text("Enable iCloud sync first.")
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await worker.download(track)
            message = L10n.text("Download Complete")
            onChange?()
        } catch { message = error.localizedDescription }
    }
    /// Downloads verified assets needed by playback, throwing when synchronization is disabled or
    /// the cloud operation fails.
    public func downloadForPlayback(_ track: Track) async throws {
        guard let worker, enabled else { throw MusicError.missingFile }
        try await worker.download(track)
        onChange?()
    }
}
