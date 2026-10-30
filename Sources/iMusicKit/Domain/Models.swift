import Foundation

public struct Track: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var assetHash: String
    public var fileExtension: String
    public var originalFilename: String
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var genre: String
    public var discNumber: Int
    public var trackNumber: Int
    public var duration: Double
    public var sampleRate: Double
    public var channels: Int
    public var artworkName: String?
    public var isFavorite: Bool
    public var addedAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var permanentlyDeletedAt: Date?
    public var originalMetadata: [String: String]

    public init(id: UUID = UUID(), assetHash: String, fileExtension: String,
                originalFilename: String, title: String, artist: String = "",
                album: String = "", albumArtist: String = "", genre: String = "",
                discNumber: Int = 1, trackNumber: Int = 0, duration: Double = 0,
                sampleRate: Double = 0, channels: Int = 2, artworkName: String? = nil,
                isFavorite: Bool = false, addedAt: Date = Date(), modifiedAt: Date = Date(),
                deletedAt: Date? = nil, originalMetadata: [String: String] = [:]) {
        self.id = id; self.assetHash = assetHash; self.fileExtension = fileExtension
        self.originalFilename = originalFilename; self.title = title; self.artist = artist
        self.album = album; self.albumArtist = albumArtist; self.genre = genre
        self.discNumber = discNumber; self.trackNumber = trackNumber; self.duration = duration
        self.sampleRate = sampleRate; self.channels = channels; self.artworkName = artworkName
        self.isFavorite = isFavorite; self.addedAt = addedAt; self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt; self.originalMetadata = originalMetadata
        self.permanentlyDeletedAt = nil
    }
    public var displayArtist: String { artist.isEmpty ? L10n.text("Unknown Artist") : artist }
    public var displayAlbum: String { album.isEmpty ? L10n.text("Unknown Album") : album }
    public var albumKey: String { "\(album.searchKey)\u{1f}\((albumArtist.isEmpty ? artist : albumArtist).searchKey)" }
}

public struct Playlist: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var entries: [QueueEntry] = []
    public var modifiedAt = Date()
    public var deletedAt: Date?
    public var artworkName: String?
    public init(id: UUID = UUID(), name: String, entries: [QueueEntry] = []) {
        self.id = id; self.name = name; self.entries = entries.enumerated().map { index, entry in var value = entry; value.order = Double(index); return value }
    }
}

public struct QueueEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var trackID: UUID
    public var order: Double?
    public init(id: UUID = UUID(), trackID: UUID) { self.id = id; self.trackID = trackID }
}

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one
    public var label: String { switch self { case .off: L10n.text("Play in Order"); case .all: L10n.text("Repeat All"); case .one: L10n.text("Repeat One") } }
    public var symbol: String { self == .one ? "repeat.1" : "repeat" }
    public var next: Self { switch self { case .off: .all; case .all: .one; case .one: .off } }
}

public enum PlaybackStatus: String, Codable, Sendable { case idle, preparing, playing, paused, ended, failed }

public struct HomeSectionOption: Codable, Identifiable, Sendable {
    public var id: String
    public var enabled: Bool
    public var title: String {
        switch id {
        case "continue": L10n.text("Continue Listening")
        case "categories": L10n.text("Categories")
        case "playlists": L10n.text("Playlists")
        case "recent": L10n.text("Recently Added")
        case "statistics": L10n.text("Listening Statistics")
        default: id
        }
    }
    public func canonicalized() -> Self { var value = self; value.id = PreferencesCompatibility.canonicalID(id); return value }
    public static let defaults: [HomeSectionOption] = [
        .init(id: "continue", enabled: true), .init(id: "categories", enabled: true),
        .init(id: "playlists", enabled: true), .init(id: "recent", enabled: true), .init(id: "statistics", enabled: false)
    ]
}

public enum ArtistCreditParser {
    public static func names(_ raw: String, split: Bool, separators: [String]) -> [String] {
        guard !raw.isEmpty else { return [] }
        guard split else { return [raw] }
        let fragments = separators.filter { !$0.isEmpty }.reduce([raw]) { parts, separator in parts.flatMap { $0.components(separatedBy: separator) } }
        var seen = Set<String>()
        return fragments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

public struct PlaybackSession: Codable, Equatable, Sendable {
    public var entries: [QueueEntry] = []
    public var currentID: UUID?
    public var position: Double = 0
    public var repeatMode: RepeatMode = .off
    public var isShuffled = false
    public var shuffleOrder: [UUID] = []
    public var history: [UUID] = []
    public init() {}
    public var current: QueueEntry? { entries.first { $0.id == currentID } }
    public var orderedIDs: [UUID] { isShuffled ? shuffleOrder : entries.map(\.id) }

    public mutating func replace(with tracks: [UUID], startingAt index: Int = 0) {
        entries = tracks.map { QueueEntry(trackID: $0) }
        currentID = entries.indices.contains(index) ? entries[index].id : entries.first?.id
        position = 0; history = []
        rebuildShuffle()
    }
    public mutating func setShuffle(_ enabled: Bool) {
        isShuffled = enabled; rebuildShuffle()
    }
    private mutating func rebuildShuffle() {
        shuffleOrder = entries.map(\.id).filter { $0 != currentID }.shuffled()
        if let currentID { shuffleOrder.insert(currentID, at: 0) }
    }
    public func nextID(automatic: Bool) -> UUID? {
        guard let currentID else { return orderedIDs.first }
        if automatic && repeatMode == .one { return currentID }
        let order = orderedIDs
        guard let index = order.firstIndex(of: currentID) else { return order.first }
        if index + 1 < order.count { return order[index + 1] }
        return repeatMode == .all ? order.first : nil
    }
    public mutating func select(_ id: UUID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        if let currentID, currentID != id { history.append(currentID) }
        currentID = id; position = 0
    }
    public mutating func previous() -> UUID? {
        while let id = history.popLast() {
            if entries.contains(where: { $0.id == id }) { currentID = id; position = 0; return id }
        }
        guard let currentID, let index = orderedIDs.firstIndex(of: currentID), index > 0 else { return currentID }
        let id = orderedIDs[index - 1]; self.currentID = id; position = 0; return id
    }
    public mutating func append(_ trackID: UUID, next: Bool = false) {
        let entry = QueueEntry(trackID: trackID)
        if next, let index = entries.firstIndex(where: { $0.id == currentID }) { entries.insert(entry, at: index + 1) }
        else { entries.append(entry) }
        if next, let index = shuffleOrder.firstIndex(where: { $0 == currentID }) { shuffleOrder.insert(entry.id, at: index + 1) }
        else { shuffleOrder.append(entry.id) }
    }
    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }; shuffleOrder.removeAll { $0 == id }
        history.removeAll { $0 == id }
        if currentID == id { currentID = nil; position = 0 }
    }
    public mutating func removeTracks(_ trackIDs: Set<UUID>) {
        let removed = Set(entries.filter { trackIDs.contains($0.trackID) }.map(\.id))
        entries.removeAll { removed.contains($0.id) }
        shuffleOrder.removeAll { removed.contains($0) }; history.removeAll { removed.contains($0) }
        if let currentID, removed.contains(currentID) { self.currentID = entries.first?.id; position = 0 }
    }
}

/// UI preview state never writes back into the engine clock until a seek is committed.
public struct PlaybackTimeline: Equatable, Sendable {
    public private(set) var elapsed: Double = 0
    public private(set) var duration: Double?
    public private(set) var preview: Double?
    public init() {}
    public var canSeek: Bool { duration.map { $0.isFinite && $0 > 0 } ?? false }
    public var displayedTime: Double { preview ?? elapsed }
    public var fraction: Double { guard let duration, canSeek else { return 0 }; return min(1, max(0, displayedTime / duration)) }
    public var remaining: Double? { duration.map { max(0, $0 - displayedTime) } }
    public mutating func update(elapsed: Double, duration: Double?) {
        self.duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.elapsed = elapsed.isFinite ? max(0, min(elapsed, self.duration ?? .greatestFiniteMagnitude)) : 0
    }
    public mutating func beginPreview(fraction: Double) {
        guard let duration, fraction.isFinite else { return }
        preview = min(1, max(0, fraction)) * duration
    }
    public mutating func finishPreview() -> Double? { defer { preview = nil }; return preview }
    public mutating func cancelPreview() { preview = nil }
}

public struct FolderSource: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var bookmark: Data
    public var lastScan: Date?
    public var error: String?
}

public struct ListenEvent: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var trackID: UUID
    public var startedAt: Date
    public var seconds: Double
}

public enum MusicError: LocalizedError, Sendable {
    case missingFile, unsupportedFormat, invalidBackup(String), permissionDenied, invalidName
    case playback(String), importFailed(String), unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .missingFile: L10n.text("The music file is unavailable. Import it again or download it from the cloud.")
        case .unsupportedFormat: L10n.text("This file cannot be decoded. It may be damaged or in an unsupported format.")
        case .invalidBackup(let reason): L10n.text("format.backup.verification_error", String(describing: reason))
        case .permissionDenied: L10n.text("Folder access has expired. Select the folder again.")
        case .invalidName: L10n.text("The name cannot be empty.")
        case .playback(let text), .importFailed(let text), .unavailable(let text): text
        }
    }
}

extension String {
    public var searchKey: String { folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).precomposedStringWithCanonicalMapping }
}

public func musicTime(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
    let value = Int(min(seconds, 359_999))
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%d:%02d", value / 60, value % 60)
}
