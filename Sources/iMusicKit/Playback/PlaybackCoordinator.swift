import Foundation
import Observation

@MainActor @Observable
public final class PlaybackCoordinator {
    public private(set) var session: PlaybackSession
    public private(set) var status: PlaybackStatus = .idle
    public private(set) var timeline = PlaybackTimeline()
    public private(set) var track: Track?
    public private(set) var error: String?
    public var rate: Float = 1 { didSet { engine.setRate(rate); persistPreferences() } }
    public var eqEnabled = false { didSet { applyEQ() } }
    public var eqGains: [Float] = Array(repeating: 0, count: 10) { didSet { applyEQ() } }
    public private(set) var loopA: Double?
    public private(set) var loopB: Double?
    public private(set) var sleepDeadline: Date?
    public private(set) var sleepAtEnd = false
    public var routeName = L10n.text("System Output")
    public var onSnapshot: (() -> Void)?
    public var resolveMissing: ((Track, UUID) -> Void)?
    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let vault: MediaVault
    @ObservationIgnored private let engine: any PlaybackEngine
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lastSaved = Date.distantPast
    @ObservationIgnored private var lastTick = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private var listened: Double = 0
    @ObservationIgnored private var listeningStarted = Date()
    @ObservationIgnored private var listeningEventID = UUID()
    @ObservationIgnored private var attempted: Set<UUID> = []
    @ObservationIgnored private var seekFence: (target: Double, started: TimeInterval)?
    @ObservationIgnored private var intentionalPause = false
    @ObservationIgnored private var startingEntryID: UUID?
    @ObservationIgnored private var loadToken = UUID()
    @ObservationIgnored private var loadingAutomatically = false
    public var isPlaying: Bool { status == .playing }
    public var canSeek: Bool { timeline.canSeek && loopB == nil }

    public init(store: LibraryStore, vault: MediaVault, engine injectedEngine: (any PlaybackEngine)? = nil) {
        self.store = store; self.vault = vault; engine = injectedEngine ?? SFBPlaybackEngine()
        session = (try? store.setting("playback", as: PlaybackSession.self)) ?? PlaybackSession()
        if let current = session.current, let restored = try? store.track(id: current.trackID) {
            track = restored; status = .paused
            timeline.update(elapsed: session.position, duration: restored.duration)
        }
        if let saved = try? store.setting("audio", as: AudioPreferences.self) { rate = saved.rate; eqEnabled = saved.eqEnabled; eqGains = saved.gains }
        engine.setRate(rate); engine.setEqualizer(eqGains, enabled: eqEnabled)
        engine.onTrack = { [weak self] id in self?.didBegin(id) }
        engine.onState = { [weak self] state in
            guard let self else { return }
            // End-of-audio is authoritative; the stopped callback can precede its final decoder callback.
            if state != .ended {
                if state == .playing && self.intentionalPause { self.engine.pause(); self.status = .paused }
                else { self.status = state }
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
    public func play(_ tracks: [Track], startingAt trackID: UUID? = nil, shuffled: Bool = false) {
        let available = tracks.filter { $0.deletedAt == nil }
        guard !available.isEmpty else { return }
        flushListening(); session.replace(with: available.map(\.id), startingAt: available.firstIndex { $0.id == trackID } ?? 0)
        session.setShuffle(shuffled); attempted = []; loopA = nil; loopB = nil; intentionalPause = false
        startCurrent()
    }
    public func selectEntry(_ id: UUID) {
        intentionalPause = false
        flushListening(); session.select(id); attempted = []; loopA = nil; loopB = nil; startCurrent()
    }
    public func playEntries(_ entries: [QueueEntry], startingAt id: UUID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        flushListening(); session.entries = entries; session.currentID = id; session.position = 0
        session.history = []; session.setShuffle(false); attempted = []; intentionalPause = false
        startCurrent()
    }
    public func toggle() { if isPlaying { pause() } else { resume() } }
    public func pause() { intentionalPause = true; engine.pause(); status = .paused; persist(); onSnapshot?() }
    public func resume() {
        endScrubbing()
        intentionalPause = false
        if session.current == nil, let first = session.entries.first { session.currentID = first.id }
        guard session.current != nil else { return }
        if status == .failed || status == .ended || engine.elapsed == nil { startCurrent(position: status == .ended ? 0 : session.position) }
        else {
            do { try engine.resume(); status = .playing; error = nil; onSnapshot?() } catch { failed(error, skip: false) }
        }
    }
    public func next() {
        guard let id = session.nextID(automatic: false) else { pause(); status = .ended; return }
        intentionalPause = false
        flushListening(); session.select(id); attempted = []; loopA = nil; loopB = nil; startCurrent()
    }
    public func previous() {
        if timeline.displayedTime > 3 { seek(to: 0); return }
        intentionalPause = false
        flushListening(); _ = session.previous(); attempted = []; loopA = nil; loopB = nil; startCurrent()
    }
    public func setRepeat(_ mode: RepeatMode) { session.repeatMode = mode; rebuildUpcoming(); persist() }
    public func toggleShuffle() { session.setShuffle(!session.isShuffled); rebuildUpcoming(); persist() }
    public func enqueue(_ track: Track, next: Bool = false) {
        session.append(track.id, next: next)
        if session.current == nil {
            session.currentID = session.entries.first?.id; self.track = track; status = .paused
            timeline.update(elapsed: 0, duration: track.duration)
        }
        rebuildUpcoming(); persist()
    }
    public func removeEntry(_ id: UUID) {
        let wasCurrent = session.currentID == id, nextID = session.nextID(automatic: false)
        session.remove(id)
        if wasCurrent {
            flushListening(); engine.stop()
            if let nextID, nextID != id { session.select(nextID); startCurrent() }
            else { track = nil; timeline = PlaybackTimeline(); status = .idle }
        } else { rebuildUpcoming() }
        persist()
    }
    public func removeTracks(_ ids: Set<UUID>) {
        guard session.entries.contains(where: { ids.contains($0.trackID) }) else { return }
        let removesCurrent = session.current.map { ids.contains($0.trackID) } ?? false
        if removesCurrent { flushListening(); loadToken = UUID(); intentionalPause = true; engine.stop() }
        session.removeTracks(ids)
        if removesCurrent {
            track = session.current.flatMap { try? store.track(id: $0.trackID) }
            timeline = PlaybackTimeline(); timeline.update(elapsed: 0, duration: track?.duration)
            status = track == nil ? .idle : .paused; loopA = nil; loopB = nil; error = nil
        }
        rebuildUpcoming(); persist(); onSnapshot?()
    }
    public func moveEntries(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.sorted().map { session.entries[$0] }
        let adjusted = destination - offsets.filter { $0 < destination }.count
        for index in offsets.sorted(by: >) { session.entries.remove(at: index) }
        session.entries.insert(contentsOf: moving, at: min(max(0, adjusted), session.entries.count))
        rebuildUpcoming(); persist()
    }
    public func clearUpcoming() {
        session.entries.removeAll { $0.id != session.currentID }
        session.shuffleOrder = session.entries.map(\.id); engine.clearUpcoming(); persist()
    }
    public func remapTracks(_ ids: Set<UUID>, to keeper: UUID) {
        for index in session.entries.indices where ids.contains(session.entries[index].trackID) { session.entries[index].trackID = keeper }
        refreshTrack(); rebuildUpcoming(); persist()
    }
    public func beginScrubbing(fraction: Double) { guard canSeek else { return }; timeline.beginPreview(fraction: fraction) }
    public func endScrubbing() { if let position = timeline.finishPreview() { seek(to: position) } }
    public func cancelScrubbing() { timeline.cancelPreview() }
    public func seek(to seconds: Double) {
        guard canSeek, let duration = timeline.duration, seconds.isFinite else { return }
        let target = min(max(0, seconds), max(0, duration - 0.001))
        if engine.elapsed == nil { session.position = target; timeline.update(elapsed: target, duration: duration); persist(); return }
        do {
            engine.clearUpcoming(); try engine.seek(to: target)
            timeline.update(elapsed: target, duration: duration); session.position = target
            seekFence = (target, ProcessInfo.processInfo.systemUptime)
            rebuildUpcoming(); persist(); onSnapshot?()
        } catch { self.error = error.localizedDescription }
    }
    public func skip(seconds: Double) { seek(to: timeline.displayedTime + seconds) }
    public func markLoop() {
        guard let track, track.sampleRate > 0 else { return }
        let wasPlaying = isPlaying
        if loopA == nil { loopA = timeline.elapsed }
        else if loopB == nil, let a = loopA, timeline.elapsed > a + 0.1 { loopB = timeline.elapsed; startCurrent(position: a, clearLoop: false) }
        else { loopA = nil; loopB = nil; startCurrent(position: timeline.elapsed) }
        if !wasPlaying { pause() }
    }
    public func setSleep(minutes: Int?, endOfTrack: Bool = false) {
        sleepAtEnd = endOfTrack; sleepDeadline = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        rebuildUpcoming()
    }
    public func saveAndPauseForInterruption() -> Bool {
        let shouldResume = isPlaying; engine.pause(); status = .paused; persist(); onSnapshot?(); return shouldResume
    }
    public func resumeAfterInterruption(allowed: Bool) { if allowed && !intentionalPause { resume() } }
    public func refreshTrack() { if let id = track?.id { track = try? store.track(id: id); onSnapshot?() } }
    public func recoverAudioService() {
        let resume = isPlaying, position = timeline.elapsed
        startCurrent(position: position)
        if !resume { pause() }
    }
    public func report(_ error: Error) { self.error = error.localizedDescription }
    public func completedDownload(token: UUID, error: Error?) {
        guard token == loadToken else { return }
        if let error { failed(error, skip: loadingAutomatically) }
        else if intentionalPause { status = .paused; self.error = nil; onSnapshot?() }
        else { startCurrent(position: session.position, automatic: loadingAutomatically) }
    }
    public func clearError() { error = nil }
    public func persist() {
        flushListening(reset: false)
        do { try store.setSetting("playback", value: session) } catch { self.error = L10n.text("format.playback.save_error", String(describing: error.localizedDescription)) }
        lastSaved = Date()
    }
    private func startCurrent(position: Double = 0, clearLoop: Bool = true, automatic: Bool = false) {
        guard let entry = session.current else { return }
        engine.stop(); loadingAutomatically = automatic
        status = .preparing; error = nil; timeline = PlaybackTimeline(); seekFence = nil
        startingEntryID = entry.id
        loadToken = UUID()
        if clearLoop { loopA = nil; loopB = nil }
        do {
            guard let selected = try store.track(id: entry.trackID), selected.deletedAt == nil else { throw MusicError.missingFile }
            let url = try vault.url(for: selected)
            track = selected; timeline.update(elapsed: position, duration: selected.duration)
            if !FileManager.default.fileExists(atPath: url.path), let resolveMissing {
                engine.stop(); self.error = L10n.text("Downloading from iCloud…"); resolveMissing(selected, loadToken); return
            }
            guard FileManager.default.fileExists(atPath: url.path) else { throw MusicError.missingFile }
            session.position = position; listeningStarted = Date(); listened = 0; lastTick = ProcessInfo.processInfo.systemUptime
            let region: ClosedRange<Double>? = loopA.flatMap { a in loopB.map { a...$0 } }
            try engine.play(url: url, entryID: entry.id, position: position, region: region, sampleRate: selected.sampleRate)
            persist(); onSnapshot?()
        } catch { failed(error, skip: automatic) }
    }
    private func didBegin(_ id: UUID) {
        guard session.entries.contains(where: { $0.id == id }) else { return }
        if startingEntryID != id {
            flushListening(); session.select(id); timeline = PlaybackTimeline(); seekFence = nil
        }
        startingEntryID = nil
        if let entry = session.current { track = try? store.track(id: entry.trackID) }
        if intentionalPause { engine.pause(); status = .paused }
        else { status = .playing }
        error = nil; attempted = []
        listeningStarted = Date(); lastTick = ProcessInfo.processInfo.systemUptime
        rebuildUpcoming(); persist(); onSnapshot?()
    }
    private func rebuildUpcoming() {
        engine.clearUpcoming()
        guard loopB == nil, !sleepAtEnd, let id = session.nextID(automatic: true),
              let entry = session.entries.first(where: { $0.id == id }),
              let selected = try? store.track(id: entry.trackID), selected.deletedAt == nil,
              let url = try? vault.url(for: selected), FileManager.default.fileExists(atPath: url.path) else { return }
        do { try engine.enqueue(url: url, entryID: id) } catch { self.error = L10n.text("format.playback.preload_error", String(describing: error.localizedDescription)) }
    }
    private func ended() {
        flushListening()
        if sleepAtEnd { sleepAtEnd = false; pause(); status = .ended; return }
        guard let id = session.nextID(automatic: true) else { status = .ended; persist(); onSnapshot?(); return }
        session.select(id); startCurrent(automatic: true)
    }
    private func failed(_ error: Error, skip: Bool = true) {
        self.error = error.localizedDescription; status = .failed; engine.stop()
        if let id = session.currentID { attempted.insert(id) }
        if skip, let nextID = session.nextID(automatic: false), !attempted.contains(nextID) {
            session.select(nextID); startCurrent(automatic: true)
        }
        persist(); onSnapshot?()
    }
    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime, delta = min(0.5, max(0, now - lastTick)); lastTick = now
        if let deadline = sleepDeadline, deadline <= Date() { sleepDeadline = nil; pause() }
        if status == .playing { listened += delta }
        if let actual = engine.elapsed {
            let duration = engine.duration ?? track?.duration
            if let fence = seekFence {
                if abs(actual - fence.target) < 1 || now - fence.started > 2 { seekFence = nil; timeline.update(elapsed: actual, duration: duration) }
            } else { timeline.update(elapsed: actual, duration: duration) }
            session.position = timeline.elapsed
        }
        if Date().timeIntervalSince(lastSaved) >= 5 { persist(); onSnapshot?() }
    }
    private func flushListening(reset: Bool = true) {
        if listened >= 1, let id = track?.id {
            do { try store.save(ListenEvent(id: listeningEventID, trackID: id, startedAt: listeningStarted, seconds: listened)) } catch { self.error = error.localizedDescription }
        }
        if reset { listened = 0; listeningStarted = Date(); listeningEventID = UUID() }
    }
    private func applyEQ() { engine.setEqualizer(eqGains, enabled: eqEnabled); persistPreferences() }
    private func persistPreferences() { try? store.setSetting("audio", value: AudioPreferences(rate: rate, eqEnabled: eqEnabled, gains: eqGains)) }
}

private struct AudioPreferences: Codable { var rate: Float; var eqEnabled: Bool; var gains: [Float] }
