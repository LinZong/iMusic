import Foundation

/// Owns cancellable original-file preparation, preload resources, and foreground observation.
/// Queue selection, pause intent, error recovery, and engine transport remain coordinator-owned.
@MainActor
final class PlaybackSourceController {
    /// Original-file preparation and managed-path validation.
    private let resolver: AudioSourceResolver
    /// Current records used to reject a source deleted during asynchronous preparation.
    private let store: LibraryStore
    /// Requests a transport pause when the observed original changes or disappears.
    var onInvalidated: (() -> Void)?
    /// Current prepared source retains its read authorization until playback releases it.
    private var current: PreparedSourceAudio?
    /// Prepared successor retained until its queue occurrence begins.
    private var upcoming: (id: UUID, audio: PreparedSourceAudio)?
    /// Foreground observer for the active original file.
    private var presenter: LinkedFilePresenter?
    /// Whether document-provider observations may be installed.
    private var observing = true
    /// Rejects delayed file-presenter callbacks after a source transition.
    private var observationToken = UUID()
    /// Rejects delayed current-source preparations after selection changes.
    private var currentToken = UUID()
    /// Rejects delayed preloads after queue or playback-mode changes.
    private var preloadToken = UUID()
    /// Current original-file preparation task.
    private var currentTask: Task<Void, Never>?
    /// Upcoming original-file preparation task.
    private var preloadTask: Task<Void, Never>?

    /// Creates source lifecycle management without starting I/O or playback.
    init(store: LibraryStore, vault: MediaVault) {
        self.store = store
        resolver = AudioSourceResolver(store: store, vault: vault)
    }
    /// Resolves managed files without changing their ownership or falling back from originals.
    func managedURL(_ track: Track) throws -> URL { try resolver.managedURL(track) }
    /// Prepares the current original and delivers only a still-valid, active source.
    func prepare(
        _ track: Track,
        position: Double,
        region: ClosedRange<Double>?,
        ready: @escaping (PreparedSourceAudio) -> Void,
        failed: @escaping (Error) -> Void
    ) {
        let token = currentToken
        let resolver = resolver
        currentTask = Task { [weak self] in
            do {
                let prepared = try await resolver.prepare(track, position: position, region: region)
                guard !Task.isCancelled, let self, currentToken == token,
                    let latest = try store.track(id: track.id), latest.deletedAt == nil,
                    latest.permanentlyDeletedAt == nil
                else { return }
                current = prepared
                updatePresenter()
                ready(prepared)
            } catch {
                guard !Task.isCancelled, let self, currentToken == token else { return }
                failed(error)
            }
        }
    }
    /// Prepares one successor without surfacing transient failures before it is selected.
    func preload(
        _ track: Track,
        entryID: UUID,
        enqueue: @escaping (PreparedSourceAudio) throws -> Void
    ) {
        let token = preloadToken
        let resolver = resolver
        preloadTask = Task { [weak self] in
            do {
                let prepared = try await resolver.prepare(track)
                guard !Task.isCancelled, let self, preloadToken == token,
                    let latest = try store.track(id: track.id), latest.deletedAt == nil
                else { return }
                upcoming = (entryID, prepared)
                try enqueue(prepared)
            } catch {
                // The coordinator retries and reports failures when this occurrence is selected.
            }
        }
    }
    /// Transfers a prepared successor or releases the previous original after a managed transition.
    func didBegin(_ id: UUID, changedOccurrence: Bool) {
        if let upcoming, upcoming.id == id {
            current = upcoming.audio
            self.upcoming = nil
            updatePresenter()
        } else if changedOccurrence {
            current = nil
            updatePresenter()
        }
    }
    /// Invalidates only upcoming work when repeat, seek, or queue order changes.
    func cancelPreload() {
        preloadToken = UUID()
        preloadTask?.cancel()
        preloadTask = nil
        upcoming = nil
    }
    /// Releases all original-file work and observation after a selection or stop transition.
    func stop() {
        observationToken = UUID()
        presenter?.unregister()
        presenter = nil
        currentToken = UUID()
        currentTask?.cancel()
        currentTask = nil
        cancelPreload()
        current = nil
    }
    /// Registers presenters only while scenes are active.
    func setObservation(active: Bool) {
        observing = active
        updatePresenter()
    }
    /// Observes the active original using a token scoped to its current occurrence.
    private func updatePresenter() {
        observationToken = UUID()
        presenter?.unregister()
        presenter = nil
        guard observing, let current else { return }
        let token = observationToken
        presenter = LinkedFilePresenter(source: current) { [weak self] completion in
            Task { @MainActor [weak self] in
                defer { completion() }
                guard let self, observationToken == token else { return }
                onInvalidated?()
            }
        }
    }
    deinit {
        presenter?.unregister()
        currentTask?.cancel()
        preloadTask?.cancel()
    }
}
