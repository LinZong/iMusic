import Foundation
import Observation

@MainActor @Observable
public final class PlaybackCoordinator {
    /// Queue selection, traversal order, and explicit start/seek position; clock ticks only update
    /// the separate timeline so transport menus do not rebuild ten times per second.
    public private(set) var session: PlaybackSession
    /// Observable playback state used by native controls and system media integration.
    public private(set) var status: PlaybackStatus = .idle
    /// Validated engine position plus independent seek-preview state for the progress control.
    public private(set) var timeline = PlaybackTimeline()
    /// Metadata for the current queue occurrence, retained while playback is paused.
    public private(set) var track: Track?
    /// Localized playback or persistence error currently presented to the user.
    public private(set) var error: String?
    /// Device-local linear application gain; zero is muted and one preserves the source level.
    public private(set) var volume: Float = 1
    /// Whether application gain is zero, independent of playback and device output state.
    public var isMuted: Bool { volume == 0 }
    /// Last nonzero gain restored by Unmute, retained across application launches.
    @ObservationIgnored private var lastAudibleVolume: Float = 1
    /// Playback speed multiplier; changes update the engine and persist audio preferences.
    public var rate: Float = 1 {
        didSet {
            engine.setRate(rate)
            persistPreferences()
        }
    }
    /// Whether the ten-band equalizer is active; changes are applied and persisted immediately.
    public var eqEnabled = false { didSet { applyEQ() } }
    /// Ten equalizer band gains in decibels, applied to the engine and saved as audio preferences.
    public var eqGains: [Float] = Array(repeating: 0, count: 10) { didSet { applyEQ() } }
    /// Optional A/B loop start position in seconds.
    public private(set) var loopA: Double?
    /// Optional A/B loop end position in seconds; an active region disables ordinary seeking.
    public private(set) var loopB: Double?
    /// Wall-clock deadline at which playback should pause, or nil when no timer is scheduled.
    public private(set) var sleepDeadline: Date?
    /// Whether playback should pause after the current track instead of preloading another one.
    public private(set) var sleepAtEnd = false
    /// User-visible description of the current system audio output route.
    public var routeName = L10n.text("System Output")
    /// Callback requesting publication of current playback information to system controls.
    public var onSnapshot: (() -> Void)?
    /// Requests a cloud download with a generation token so stale completions cannot restart
    /// playback.
    public var resolveMissing: ((Track, UUID) -> Void)?
    /// SQLite library store used by this service to read records and persist atomic changes.
    @ObservationIgnored private let store: LibraryStore
    /// Application-owned media layout used to resolve validated files and working directories.
    @ObservationIgnored private let vault: MediaVault
    /// Source dispatch boundary shared by current-track and gapless preparation.
    @ObservationIgnored private let sources: AudioSourceResolver
    /// Foreground-only observer for the active original-file decoder.
    @ObservationIgnored private var sourcePresenter: LinkedFilePresenter?
    /// Identity of the active observation, rejecting delayed events after a gapless transition.
    @ObservationIgnored private var sourceObservationToken = UUID()
    /// Whether this scene may register file presenters with document providers.
    @ObservationIgnored private var observeSources = true
    /// Playback backend; production uses SFBAudioEngine and tests can inject a hardware-free
    /// implementation.
    @ObservationIgnored private let engine: any PlaybackEngine
    /// Cancellable task sampling the engine clock and enforcing sleep and persistence deadlines.
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// Last playback-session save time, used to throttle periodic persistence.
    @ObservationIgnored private var lastSaved = Date.distantPast
    /// Monotonic timestamp of the previous sample, used to accumulate actual listening time.
    @ObservationIgnored private var lastTick = ProcessInfo.processInfo.systemUptime
    /// Real seconds heard in the current listening segment, excluding pauses and seek distance.
    @ObservationIgnored private var listened: Double = 0
    /// Wall-clock start of the listening segment currently being accumulated.
    @ObservationIgnored private var listeningStarted = Date()
    /// Stable record identity reused when saving incremental progress for one listening segment.
    @ObservationIgnored private var listeningEventID = UUID()
    /// Queue occurrence identities already attempted during automatic error recovery.
    @ObservationIgnored private var attempted: Set<UUID> = []
    /// Recent seek target and monotonic start time used to ignore delayed pre-seek engine samples.
    @ObservationIgnored private var seekFence: (target: Double, started: TimeInterval)?
    /// Explicit pause intent that takes precedence over late engine or download callbacks.
    @ObservationIgnored private var intentionalPause = false
    /// Occurrence expected to start, used to distinguish explicit loading from gapless advancement.
    @ObservationIgnored private var startingEntryID: UUID?
    /// Identity of the current load attempt; changing it invalidates pending download callbacks.
    @ObservationIgnored private var loadToken = UUID()
    /// Whether the pending load came from automatic advancement and may skip a failed song.
    @ObservationIgnored private var loadingAutomatically = false
    /// Cancellable original-file preparation; selection tokens reject late provider callbacks.
    @ObservationIgnored private var sourceTask: Task<Void, Never>?
    /// Cancellable preparation for the next original-file decoder.
    @ObservationIgnored private var preloadTask: Task<Void, Never>?
    /// Token invalidating preloads when repeat, queue order, or selection changes.
    @ObservationIgnored private var preloadToken = UUID()
    /// Current prepared source retained even by hardware-free test backends.
    @ObservationIgnored private var currentSource: PreparedSourceAudio?
    /// Next prepared source transferred when the backend advances gaplessly.
    @ObservationIgnored private var upcomingSource: (id: UUID, audio: PreparedSourceAudio)?
    /// Whether the published playback state is currently playing.
    public var isPlaying: Bool { status == .playing }
    /// Whether the duration is valid and no A/B region currently prevents ordinary seeking.
    public var canSeek: Bool { timeline.canSeek && loopB == nil }

    /// Restores the saved queue and audio preferences in a paused state, installs backend
    /// callbacks, and starts clock sampling. An injected backend allows deterministic tests without
    /// audio hardware.
    public init(
        store: LibraryStore,
        vault: MediaVault,
        engine injectedEngine: (any PlaybackEngine)? = nil
    ) {
        self.store = store
        self.vault = vault
        sources = AudioSourceResolver(store: store, vault: vault)
        engine = injectedEngine ?? SFBPlaybackEngine()
        session = (try? store.setting("playback", as: PlaybackSession.self)) ?? PlaybackSession()
        if let current = session.current, let restored = try? store.track(id: current.trackID) {
            track = restored
            status = .paused
            timeline.update(elapsed: session.position, duration: restored.duration)
        }
        if let saved = try? store.setting("audio", as: AudioPreferences.self) {
            rate = saved.rate
            eqEnabled = saved.eqEnabled
            eqGains = saved.gains
        }
        if let saved = try? store.setting("playbackVolume", as: VolumePreferences.self) {
            volume = saved.volume.isFinite ? min(1, max(0, saved.volume)) : 1
            lastAudibleVolume =
                saved.lastAudibleVolume.isFinite && saved.lastAudibleVolume > 0
                ? min(1, saved.lastAudibleVolume) : 1
            if volume > 0 { lastAudibleVolume = volume }
        }
        engine.setRate(rate)
        engine.setVolume(volume)
        engine.setEqualizer(eqGains, enabled: eqEnabled)
        engine.onTrack = { [weak self] id in self?.didBegin(id) }
        engine.onState = { [weak self] state in
            guard let self else { return }
            // End-of-audio is authoritative; the stopped callback can precede its final decoder
            // callback.
            if state != .ended {
                if state == .playing && self.intentionalPause {
                    self.engine.pause()
                    self.status = .paused
                } else {
                    self.status = state
                }
                self.onSnapshot?()
            }
        }
        engine.onEnd = { [weak self] in self?.ended() }
        engine.onError = { [weak self] error in self?.failed(error) }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, self != nil else { break }
                self?.tick()
            }
        }
    }
    deinit {
        sourcePresenter?.unregister()
        sourceTask?.cancel()
        preloadTask?.cancel()
        ticker?.cancel()
    }
    /// Replaces the queue with active songs, selects the requested start, applies shuffle mode,
    /// clears loop state, and begins playback.
    public func play(_ tracks: [Track], startingAt trackID: UUID? = nil, shuffled: Bool = false) {
        let available = tracks.filter { $0.deletedAt == nil }
        guard !available.isEmpty else { return }
        flushListening()
        session.replace(
            with: available.map(\.id),
            startingAt: available.firstIndex { $0.id == trackID } ?? 0
        )
        session.setShuffle(shuffled)
        attempted = []
        loopA = nil
        loopB = nil
        intentionalPause = false
        startCurrent()
    }
    /// Selects a specific queue occurrence and starts it from the beginning after flushing
    /// listening statistics.
    public func selectEntry(_ id: UUID) {
        intentionalPause = false
        flushListening()
        session.select(id)
        attempted = []
        loopA = nil
        loopB = nil
        startCurrent()
    }
    /// Starts a supplied occurrence-preserving queue at an existing entry identity, keeping
    /// duplicate playlist songs distinct.
    public func playEntries(_ entries: [QueueEntry], startingAt id: UUID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        flushListening()
        session.entries = entries
        session.currentID = id
        session.position = 0
        session.history = []
        session.setShuffle(false)
        attempted = []
        intentionalPause = false
        startCurrent()
    }
    /// Pauses active playback or resumes the selected occurrence using the saved position.
    public func toggle() { if isPlaying { pause() } else { resume() } }
    /// Records explicit pause intent, pauses the backend, saves the session, and updates system
    /// playback information.
    public func pause() {
        intentionalPause = true
        engine.pause()
        status = .paused
        persist()
        onSnapshot?()
    }
    /// Commits any pending seek preview and resumes playback; reloads the selected song when its
    /// decoder is missing, failed, or ended.
    public func resume() {
        endScrubbing()
        intentionalPause = false
        if session.current == nil, let first = session.entries.first {
            session.currentID = first.id
        }
        guard session.current != nil else { return }
        if status == .failed || status == .ended || engine.elapsed == nil {
            startCurrent(position: status == .ended ? 0 : timeline.elapsed)
        } else {
            do {
                try engine.resume()
                status = .playing
                error = nil
                onSnapshot?()
            } catch { failed(error, skip: false) }
        }
    }
    /// Manually advances the queue, bypassing repeat-one and ending playback when no next
    /// occurrence exists.
    public func next() {
        guard let id = session.nextID(automatic: false) else {
            pause()
            status = .ended
            return
        }
        intentionalPause = false
        flushListening()
        session.select(id)
        attempted = []
        loopA = nil
        loopB = nil
        startCurrent()
    }
    /// Restarts the current song after three elapsed seconds; otherwise selects the preceding
    /// history occurrence and starts it.
    public func previous() {
        if timeline.displayedTime > 3 {
            seek(to: 0)
            return
        }
        intentionalPause = false
        flushListening()
        _ = session.previous()
        attempted = []
        loopA = nil
        loopB = nil
        startCurrent()
    }
    /// Updates the repeat policy, rebuilds the next decoder preload, and persists the session.
    public func setRepeat(_ mode: RepeatMode) {
        session.repeatMode = mode
        rebuildUpcoming()
        persist()
    }
    /// Toggles the stable shuffle traversal, rebuilds preloading, and persists the session.
    public func toggleShuffle() {
        session.setShuffle(!session.isShuffled)
        rebuildUpcoming()
        persist()
    }
    /// Adds a song occurrence at the end or immediately next; an empty queue becomes selected but
    /// remains paused.
    public func enqueue(_ track: Track, next: Bool = false) {
        session.append(track.id, next: next)
        if session.current == nil {
            session.currentID = session.entries.first?.id
            self.track = track
            status = .paused
            timeline.update(elapsed: 0, duration: track.duration)
        }
        rebuildUpcoming()
        persist()
    }
    /// Removes one occurrence, starting the next available occurrence if the removed entry was
    /// playing, then persists the queue.
    public func removeEntry(_ id: UUID) {
        let wasCurrent = session.currentID == id
        let nextID = session.nextID(automatic: false)
        session.remove(id)
        if wasCurrent {
            flushListening()
            stopSourceWork()
            engine.stop()
            if let nextID, nextID != id {
                session.select(nextID)
                startCurrent()
            } else {
                track = nil
                timeline = PlaybackTimeline()
                status = .idle
            }
        } else {
            rebuildUpcoming()
        }
        persist()
    }
    /// Removes every occurrence of deleted songs, invalidates pending loads, and leaves any
    /// replacement selection paused.
    public func removeTracks(_ ids: Set<UUID>) {
        guard session.entries.contains(where: { ids.contains($0.trackID) }) else { return }
        let removesCurrent = session.current.map { ids.contains($0.trackID) } ?? false
        if removesCurrent {
            flushListening()
            loadToken = UUID()
            intentionalPause = true
            stopSourceWork()
            engine.stop()
        }
        session.removeTracks(ids)
        if removesCurrent {
            track = session.current.flatMap { try? store.track(id: $0.trackID) }
            timeline = PlaybackTimeline()
            timeline.update(elapsed: 0, duration: track?.duration)
            status = track == nil ? .idle : .paused
            loopA = nil
            loopB = nil
            error = nil
        }
        rebuildUpcoming()
        persist()
        onSnapshot?()
    }
    /// Reorders visible queue occurrences using collection-move offsets, then rebuilds preloading
    /// and saves the queue.
    public func moveEntries(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().map { session.entries[$0] }
        let adjusted = destination - offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) { session.entries.remove(at: index) }
        session.entries.insert(contentsOf: moving, at: min(max(0, adjusted), session.entries.count))
        rebuildUpcoming()
        persist()
    }
    /// Retains only the current occurrence, clears the decoder preload, and saves the reduced
    /// queue.
    public func clearUpcoming() {
        session.entries.removeAll { $0.id != session.currentID }
        session.shuffleOrder = session.entries.map(\.id)
        cancelSourcePreload()
        engine.clearUpcoming()
        persist()
    }
    /// Redirects duplicate song references to a keeper while preserving occurrence identities, then
    /// refreshes metadata and persists.
    public func remapTracks(_ ids: Set<UUID>, to keeper: UUID) {
        for index in session.entries.indices where ids.contains(session.entries[index].trackID) {
            session.entries[index].trackID = keeper
        }
        refreshTrack()
        rebuildUpcoming()
        persist()
    }
    /// Updates the slider's temporary fraction preview when seeking is available; does not move the
    /// engine clock.
    public func beginScrubbing(fraction: Double) {
        guard canSeek else { return }
        timeline.beginPreview(fraction: fraction)
    }
    /// Commits the pending slider preview to one seek and clears preview state.
    public func endScrubbing() { if let position = timeline.finishPreview() { seek(to: position) } }
    /// Drops the pending slider preview without moving playback.
    public func cancelScrubbing() { timeline.cancelPreview() }
    /// Clamps a finite target in seconds to the valid track range, preserves pause state, fences
    /// stale clock samples, and persists the committed position.
    public func seek(to seconds: Double) {
        guard canSeek, let duration = timeline.duration, seconds.isFinite else { return }
        let target = min(max(0, seconds), max(0, duration - 0.001))
        if engine.elapsed == nil {
            session.position = target
            timeline.update(elapsed: target, duration: duration)
            persist()
            return
        }
        do {
            cancelSourcePreload()
            engine.clearUpcoming()
            try engine.seek(to: target)
            timeline.update(elapsed: target, duration: duration)
            session.position = target
            seekFence = (target, ProcessInfo.processInfo.systemUptime)
            rebuildUpcoming()
            persist()
            onSnapshot?()
        } catch { self.error = error.localizedDescription }
    }
    /// Seeks by a signed offset in seconds relative to the currently displayed timeline position.
    public func skip(seconds: Double) { seek(to: timeline.displayedTime + seconds) }
    /// Cycles through setting A, setting B, and clearing an A/B region while preserving whether
    /// playback was paused.
    public func markLoop() {
        guard let track, track.sampleRate > 0 else { return }
        let wasPlaying = isPlaying
        if loopA == nil {
            loopA = timeline.elapsed
        } else if loopB == nil, let a = loopA, timeline.elapsed > a + 0.1 {
            loopB = timeline.elapsed
            startCurrent(position: a, clearLoop: false)
        } else {
            loopA = nil
            loopB = nil
            startCurrent(position: timeline.elapsed)
        }
        if !wasPlaying { pause() }
    }
    /// Schedules a timed pause or an end-of-track stop; passing neither option cancels the timer
    /// and restores ordinary preloading.
    public func setSleep(minutes: Int?, endOfTrack: Bool = false) {
        sleepAtEnd = endOfTrack
        sleepDeadline = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        rebuildUpcoming()
    }
    /// Pauses for a system interruption without recording user pause intent, persists the position,
    /// and returns whether playback had been active.
    public func saveAndPauseForInterruption() -> Bool {
        let shouldResume = isPlaying
        engine.pause()
        status = .paused
        persist()
        onSnapshot?()
        return shouldResume
    }
    /// Resumes only when the system allows it and a subsequent explicit user pause has not
    /// overridden that intent.
    public func resumeAfterInterruption(allowed: Bool) {
        if allowed && !intentionalPause { resume() }
    }
    /// Reloads metadata for the current song and republishes system playback information.
    public func refreshTrack() {
        if let id = track?.id {
            track = try? store.track(id: id)
            onSnapshot?()
        }
    }
    /// Recreates playback after an audio-service reset at the last sampled position, preserving the
    /// previous play or pause state.
    public func recoverAudioService() {
        let resume = isPlaying
        let position = timeline.elapsed
        startCurrent(position: position)
        if !resume { pause() }
    }
    /// Publishes a localized external audio or system-integration error without changing the
    /// selected queue occurrence.
    public func report(_ error: Error) { self.error = error.localizedDescription }
    /// Applies finite, bounded gain immediately and saves device-local volume preferences.
    public func setVolume(_ value: Float) {
        guard value.isFinite else { return }
        let bounded = min(1, max(0, value))
        guard bounded != volume else { return }
        volume = bounded
        if bounded > 0 { lastAudibleVolume = bounded }
        engine.setVolume(bounded)
        try? store.setSetting(
            "playbackVolume",
            value: VolumePreferences(volume: volume, lastAudibleVolume: lastAudibleVolume)
        )
    }
    /// Mutes without pausing playback or restores the last nonzero application gain.
    public func toggleMute() { setVolume(isMuted ? lastAudibleVolume : 0) }
    /// Handles a cloud load result only when its token matches the active attempt; stale results
    /// and explicit pause intent cannot restart playback.
    public func completedDownload(token: UUID, error: Error?) {
        guard token == loadToken else { return }
        if let error {
            failed(error, skip: loadingAutomatically)
        } else if intentionalPause {
            status = .paused
            self.error = nil
            onSnapshot?()
        } else {
            startCurrent(position: timeline.elapsed, automatic: loadingAutomatically)
        }
    }
    /// Dismisses the currently presented playback error without changing playback state.
    public func clearError() { error = nil }
    /// Flushes accumulated listening time and saves the queue selection and committed position,
    /// reporting any persistence failure.
    public func persist() {
        flushListening(reset: false)
        var snapshot = session
        snapshot.position = timeline.elapsed
        do { try store.setSetting("playback", value: snapshot) } catch {
            self.error = L10n.text(
                "format.playback.save_error",
                String(describing: error.localizedDescription)
            )
        }
        lastSaved = Date()
    }
    /// Registers source observation only while scenes are active, as required by document
    /// providers.
    public func setSourceObservation(active: Bool) {
        observeSources = active
        updateSourcePresenter()
    }

    private func updateSourcePresenter() {
        sourceObservationToken = UUID()
        sourcePresenter?.unregister()
        sourcePresenter = nil
        guard observeSources, let currentSource else { return }
        let token = sourceObservationToken
        sourcePresenter = LinkedFilePresenter(source: currentSource) { [weak self] completion in
            Task { @MainActor [weak self] in
                defer { completion() }
                guard let self, self.sourceObservationToken == token else { return }
                self.stopSourceWork()
                self.engine.stop()
                self.status = .paused
                self.error = L10n.text(
                    """
                    The source file changed or was removed. Resume to reopen it, or relink its \
                    folder in Settings.
                    """
                )
                self.persist()
                self.onSnapshot?()
            }
        }
    }

    private func startCurrent(position: Double = 0, clearLoop: Bool = true, automatic: Bool = false)
    {
        guard let entry = session.current else { return }
        stopSourceWork()
        engine.stop()
        loadingAutomatically = automatic
        status = .preparing
        error = nil
        timeline = PlaybackTimeline()
        seekFence = nil
        startingEntryID = entry.id
        loadToken = UUID()
        if clearLoop {
            loopA = nil
            loopB = nil
        }
        do {
            guard let selected = try store.track(id: entry.trackID), selected.deletedAt == nil
            else { throw MusicError.missingFile }
            track = selected
            timeline.update(elapsed: position, duration: selected.duration)
            if selected.isLinked {
                prepareSource(selected, entry: entry, position: position, automatic: automatic)
                return
            }
            let url = try sources.managedURL(selected)
            if !FileManager.default.fileExists(atPath: url.path), let resolveMissing {
                stopSourceWork()
                engine.stop()
                self.error = L10n.text("Downloading from iCloud…")
                resolveMissing(selected, loadToken)
                return
            }
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw MusicError.missingFile
            }
            session.position = position
            listeningStarted = Date()
            listened = 0
            lastTick = ProcessInfo.processInfo.systemUptime
            let region: ClosedRange<Double>? = loopA.flatMap { a in loopB.map { a...$0 } }
            engine.setVolume(volume)
            try engine.play(
                url: url,
                entryID: entry.id,
                position: position,
                region: region,
                sampleRate: selected.sampleRate
            )
            persist()
            onSnapshot?()
        } catch { failed(error, skip: automatic) }
    }
    private func prepareSource(
        _ selected: Track,
        entry: QueueEntry,
        position: Double,
        automatic: Bool
    ) {
        let token = loadToken
        let region = loopA.flatMap { a in loopB.map { a...$0 } }
        sourceTask = Task { [weak self] in
            guard let self else { return }
            do {
                let prepared = try await sources.prepare(
                    selected,
                    position: position,
                    region: region
                )
                guard !Task.isCancelled, token == loadToken, session.currentID == entry.id,
                    let current = try store.track(id: selected.id), current.deletedAt == nil,
                    current.permanentlyDeletedAt == nil
                else { return }
                currentSource = prepared
                updateSourcePresenter()
                if intentionalPause {
                    status = .paused
                    return
                }
                session.position = position
                listeningStarted = Date()
                listened = 0
                lastTick = ProcessInfo.processInfo.systemUptime
                engine.setVolume(volume)
                try engine.play(prepared: prepared, entryID: entry.id, region: region)
                persist()
                onSnapshot?()
            } catch {
                guard !Task.isCancelled, token == loadToken else { return }
                failed(error, skip: automatic)
            }
        }
    }

    private func cancelSourcePreload() {
        preloadToken = UUID()
        preloadTask?.cancel()
        preloadTask = nil
        upcomingSource = nil
    }

    private func stopSourceWork() {
        sourceObservationToken = UUID()
        sourcePresenter?.unregister()
        sourcePresenter = nil
        loadToken = UUID()
        sourceTask?.cancel()
        sourceTask = nil
        cancelSourcePreload()
        currentSource = nil
    }

    private func didBegin(_ id: UUID) {
        guard session.entries.contains(where: { $0.id == id }) else { return }
        let changedOccurrence = session.currentID != id
        if startingEntryID != id {
            flushListening()
            session.select(id)
            timeline = PlaybackTimeline()
            seekFence = nil
        }
        if let upcomingSource, upcomingSource.id == id {
            currentSource = upcomingSource.audio
            self.upcomingSource = nil
            updateSourcePresenter()
        } else if changedOccurrence {
            // A managed gapless successor must release the previous original-file observation.
            currentSource = nil
            updateSourcePresenter()
        }
        startingEntryID = nil
        if let entry = session.current { track = try? store.track(id: entry.trackID) }
        if intentionalPause {
            engine.pause()
            status = .paused
        } else {
            status = .playing
        }
        error = nil
        attempted = []
        listeningStarted = Date()
        lastTick = ProcessInfo.processInfo.systemUptime
        rebuildUpcoming()
        persist()
        onSnapshot?()
    }
    private func rebuildUpcoming() {
        cancelSourcePreload()
        engine.clearUpcoming()
        // A restored paused session has no decoder. Enqueuing into an empty backend can start
        // that upcoming song instead of merely changing a playback mode.
        guard engine.elapsed != nil, loopB == nil, !sleepAtEnd,
            let id = session.nextID(automatic: true),
            let entry = session.entries.first(where: { $0.id == id }),
            let selected = try? store.track(id: entry.trackID), selected.deletedAt == nil
        else { return }
        if selected.isLinked {
            let token = preloadToken
            preloadTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let prepared = try await sources.prepare(selected)
                    guard !Task.isCancelled, token == preloadToken,
                        let current = try store.track(id: selected.id), current.deletedAt == nil
                    else { return }
                    upcomingSource = (id, prepared)
                    try engine.enqueue(prepared: prepared, entryID: id)
                } catch {
                    // Preparation failures are retried and surfaced if this occurrence is selected.
                }
            }
            return
        }
        guard let url = try? sources.managedURL(selected),
            FileManager.default.fileExists(atPath: url.path)
        else { return }
        do { try engine.enqueue(url: url, entryID: id) } catch {
            self.error = L10n.text(
                "format.playback.preload_error",
                String(describing: error.localizedDescription)
            )
        }
    }
    private func ended() {
        flushListening()
        if sleepAtEnd {
            sleepAtEnd = false
            pause()
            if track?.isLinked == true {
                stopSourceWork()
                engine.stop()
            }
            status = .ended
            return
        }
        guard let id = session.nextID(automatic: true) else {
            if track?.isLinked == true {
                stopSourceWork()
                engine.stop()
            }
            status = .ended
            persist()
            onSnapshot?()
            return
        }
        session.select(id)
        startCurrent(automatic: true)
    }
    private func failed(_ error: Error, skip: Bool = true) {
        self.error = error.localizedDescription
        status = .failed
        stopSourceWork()
        engine.stop()
        if let id = session.currentID { attempted.insert(id) }
        if skip, let nextID = session.nextID(automatic: false), !attempted.contains(nextID) {
            session.select(nextID)
            startCurrent(automatic: true)
        }
        persist()
        onSnapshot?()
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = min(0.5, max(0, now - lastTick))
        lastTick = now
        if let deadline = sleepDeadline, deadline <= Date() {
            sleepDeadline = nil
            pause()
        }
        if status == .playing { listened += delta }
        if let actual = engine.elapsed {
            let duration = engine.duration ?? track?.duration
            if let fence = seekFence {
                if abs(actual - fence.target) < 1 || now - fence.started > 2 {
                    seekFence = nil
                    timeline.update(elapsed: actual, duration: duration)
                }
            } else {
                timeline.update(elapsed: actual, duration: duration)
            }
        }
        if status == .playing, Date().timeIntervalSince(lastSaved) >= 5 {
            var snapshot = session
            snapshot.position = timeline.elapsed
            lastSaved = Date()
            store.savePlaybackInBackground(snapshot, event: listeningSnapshot) {
                [weak self] result in
                guard case .failure(let error) = result else { return }
                Task { @MainActor [weak self] in
                    self?.error = L10n.text(
                        "format.playback.save_error",
                        error.localizedDescription
                    )
                }
            }
            onSnapshot?()
        }
    }
    /// Immutable progress captured before dispatching periodic SQLite work away from the UI actor.
    private var listeningSnapshot: ListenEvent? {
        guard listened >= 1, let id = track?.id else { return nil }
        return ListenEvent(
            id: listeningEventID,
            trackID: id,
            startedAt: listeningStarted,
            seconds: listened
        )
    }
    private func flushListening(reset: Bool = true) {
        if let event = listeningSnapshot {
            do {
                try store.save(event)
            } catch { self.error = error.localizedDescription }
        }
        if reset {
            listened = 0
            listeningStarted = Date()
            listeningEventID = UUID()
        }
    }
    private func applyEQ() {
        engine.setEqualizer(eqGains, enabled: eqEnabled)
        persistPreferences()
    }
    private func persistPreferences() {
        try? store.setSetting(
            "audio",
            value: AudioPreferences(rate: rate, eqEnabled: eqEnabled, gains: eqGains)
        )
    }
}

private struct AudioPreferences: Codable {
    /// Persisted playback speed multiplier.
    var rate: Float
    /// Persisted equalizer bypass preference.
    var eqEnabled: Bool
    /// Persisted ten-band gain values in decibels.
    var gains: [Float]
}

private struct VolumePreferences: Codable {
    /// Device-local application gain, intentionally excluded from portable backup preferences.
    var volume: Float
    /// Nonzero gain restored when the user unmutes after reopening the application.
    var lastAudibleVolume: Float
}
