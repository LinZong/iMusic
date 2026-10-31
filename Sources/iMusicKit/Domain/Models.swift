import Foundation

public struct Track: Codable, Identifiable, Hashable, Sendable {
    /// Stable library identity; distinct from the content hash so an explicit reimport can create a
    /// new record.
    public var id: UUID
    /// SHA-256 of managed audio for deduplication and file naming; nil for linked originals.
    public var assetHash: String?
    /// External source descriptor; absent in legacy and managed records.
    public var linkedSource: LinkedAudioReference?
    /// Whether this song references an external file instead of an application-owned copy.
    public var isLinked: Bool { linkedSource != nil }
    /// Validated audio file extension used to identify the decoder and managed copy.
    public var fileExtension: String
    /// Source file name retained for display and filename searches.
    public var originalFilename: String
    /// Editable song title stored as library metadata without rewriting the source file.
    public var title: String
    /// Original or user-edited performer credit; collaborator splitting is applied only when
    /// grouping.
    public var artist: String
    /// Album title used for display, searches, and album grouping.
    public var album: String
    /// Album-level artist credit; grouping falls back to the track artist when this is empty.
    public var albumArtist: String
    /// Genre tag used to build the local genre collection.
    public var genre: String
    /// Disc position used when ordering songs within an album.
    public var discNumber: Int
    /// Track position within a disc; zero represents an unspecified position.
    public var trackNumber: Int
    /// Detected full-track duration in seconds; the timeline rejects unknown or invalid values.
    public var duration: Double
    /// Decoded sample rate in hertz, needed to translate A/B loop boundaries into audio frames.
    public var sampleRate: Double
    /// Detected audio channel count retained with the imported file information.
    public var channels: Int
    /// Optional file name inside the managed Artwork directory, never an arbitrary source path.
    public var artworkName: String?
    /// Whether the song belongs to the Favorites collection.
    public var isFavorite: Bool
    /// Date the song entered the library, used by Recently Added.
    public var addedAt: Date
    /// Most recent local metadata edit time carried in backups and synchronization payloads.
    public var modifiedAt: Date
    /// Date the song entered Trash; nil means the record is active.
    public var deletedAt: Date?
    /// Durable deletion tombstone that prevents old backups or sync edits from reviving the song.
    public var permanentlyDeletedAt: Date?
    /// Unmodified imported tags retained for restoring library metadata after edits.
    public var originalMetadata: [String: String]

    /// Creates a library song from detected or edited metadata. Original tags and source names
    /// remain separate from managed audio bytes; permanent deletion starts unset.
    public init(
        id: UUID = UUID(),
        assetHash: String?,
        fileExtension: String,
        originalFilename: String,
        title: String,
        artist: String = "",
        album: String = "",
        albumArtist: String = "",
        genre: String = "",
        discNumber: Int = 1,
        trackNumber: Int = 0,
        duration: Double = 0,
        sampleRate: Double = 0,
        channels: Int = 2,
        artworkName: String? = nil,
        isFavorite: Bool = false,
        addedAt: Date = Date(),
        modifiedAt: Date = Date(),
        deletedAt: Date? = nil,
        originalMetadata: [String: String] = [:],
        linkedSource: LinkedAudioReference? = nil
    ) {
        self.id = id
        self.assetHash = assetHash
        self.linkedSource = linkedSource
        self.fileExtension = fileExtension
        self.originalFilename = originalFilename
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.genre = genre
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.artworkName = artworkName
        self.isFavorite = isFavorite
        self.addedAt = addedAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        self.originalMetadata = originalMetadata
        self.permanentlyDeletedAt = nil
    }
    /// Localized artist label, with an Unknown Artist fallback for an empty tag.
    public var displayArtist: String { artist.isEmpty ? L10n.text("Unknown Artist") : artist }
    /// Localized album label, with an Unknown Album fallback for an empty tag.
    public var displayAlbum: String { album.isEmpty ? L10n.text("Unknown Album") : album }
    /// Normalized album-and-artist identity that keeps same-named albums by different artists
    /// separate.
    public var albumKey: String {
        "\(album.searchKey)\u{1f}\((albumArtist.isEmpty ? artist : albumArtist).searchKey)"
    }
}

public struct Playlist: Codable, Identifiable, Hashable, Sendable {
    /// Stable identity shared by local records, backups, and cloud synchronization.
    public var id: UUID = UUID()
    /// User-visible playlist name, validated as nonempty before persistence.
    public var name: String
    /// Ordered queue entries; separate entry identities allow repeated songs in the same playlist.
    public var entries: [QueueEntry] = []
    /// Last playlist edit timestamp included in persisted metadata.
    public var modifiedAt = Date()
    /// Trash timestamp; nil means the playlist is active.
    public var deletedAt: Date?
    /// Durable marker preventing old backups or offline edits from restoring a deleted playlist.
    public var permanentlyDeletedAt: Date?
    /// Optional custom cover file name inside the managed Artwork directory.
    public var artworkName: String?
    /// Creates a named playlist and normalizes supplied occurrence ordering while preserving their
    /// entry identities.
    public init(id: UUID = UUID(), name: String, entries: [QueueEntry] = []) {
        self.id = id
        self.name = name
        self.entries = entries.enumerated()
            .map { index, entry in
                var value = entry
                value.order = Double(index)
                return value
            }
    }
}

public struct QueueEntry: Codable, Identifiable, Hashable, Sendable {
    /// Identity of this occurrence, allowing one track to appear multiple times in a queue or
    /// playlist.
    public var id: UUID
    /// Library song referenced by this occurrence.
    public var trackID: UUID
    /// Optional numeric ordering key used to merge independently edited playlist entries.
    public var order: Double?
    /// Creates one distinct queue occurrence referencing a library song.
    public init(id: UUID = UUID(), trackID: UUID) {
        self.id = id
        self.trackID = trackID
    }
}

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one
    /// Localized description of the current repeat behavior.
    public var label: String {
        switch self {
        case .off: L10n.text("Play in Order")
        case .all: L10n.text("Repeat All")
        case .one: L10n.text("Repeat One")
        }
    }
    /// SF Symbol name for repeat-one or general repeat controls.
    public var symbol: String { self == .one ? "repeat.1" : "repeat" }
    /// Next repeat mode in the off, all, one control cycle.
    public var next: Self {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

public enum PlaybackStatus: String, Codable, Sendable {
    case idle, preparing, playing, paused, ended, failed
}

public struct HomeSectionOption: Codable, Identifiable, Sendable {
    /// Language-independent section identifier persisted with the home layout.
    public var id: String
    /// Whether this section is displayed on Home.
    public var enabled: Bool
    /// Localized section title resolved from the stable identifier.
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
    /// Returns a copy whose saved section identifier is normalized from legacy display values.
    public func canonicalized() -> Self {
        var value = self
        value.id = PreferencesCompatibility.canonicalID(id)
        return value
    }
    /// Initial home section order and visibility for a new library.
    public static let defaults: [HomeSectionOption] = [
        .init(id: "continue", enabled: true), .init(id: "categories", enabled: true),
        .init(id: "playlists", enabled: true), .init(id: "recent", enabled: true),
        .init(id: "statistics", enabled: false),
    ]
}

public enum ArtistCreditParser {
    /// Returns unique nonempty artist credits; optionally splits using the configured literal
    /// separators and trims each result.
    public static func names(_ raw: String, split: Bool, separators: [String]) -> [String] {
        guard !raw.isEmpty else { return [] }
        guard split else { return [raw] }
        let fragments = separators.filter { !$0.isEmpty }
            .reduce([raw]) { parts, separator in
                parts.flatMap { $0.components(separatedBy: separator) }
            }
        var seen = Set<String>()
        return fragments.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

public struct PlaybackSession: Codable, Equatable, Sendable {
    /// Queue occurrences in their user-arranged order, including duplicate track references.
    public var entries: [QueueEntry] = []
    /// Selected queue-entry identity; nil means no occurrence is selected.
    public var currentID: UUID?
    /// Last committed playback position in seconds for the selected occurrence.
    public var position: Double = 0
    /// Repeat policy applied when computing the next queue occurrence.
    public var repeatMode: RepeatMode = .off
    /// Whether playback follows the stored shuffle order rather than the visible queue order.
    public var isShuffled = false
    /// Stable shuffled sequence of entry identities, rebuilt only by queue or shuffle actions.
    public var shuffleOrder: [UUID] = []
    /// Previously selected entry identities used to navigate backward through listening history.
    public var history: [UUID] = []
    /// Creates an empty queue with sequential playback, no selection, and no committed position.
    public init() {}
    /// Selected queue occurrence, or nil if its identity no longer exists.
    public var current: QueueEntry? { entries.first { $0.id == currentID } }
    /// Effective traversal order, taking the shuffle setting into account.
    public var orderedIDs: [UUID] { isShuffled ? shuffleOrder : entries.map(\.id) }

    /// Replaces the queue with fresh occurrence identities, chooses the requested starting index,
    /// and clears position and history.
    public mutating func replace(with tracks: [UUID], startingAt index: Int = 0) {
        entries = tracks.map { QueueEntry(trackID: $0) }
        currentID = entries.indices.contains(index) ? entries[index].id : entries.first?.id
        position = 0
        history = []
        rebuildShuffle()
    }
    /// Changes shuffle mode and rebuilds its stable traversal order with the current occurrence
    /// first.
    public mutating func setShuffle(_ enabled: Bool) {
        isShuffled = enabled
        rebuildShuffle()
    }
    private mutating func rebuildShuffle() {
        shuffleOrder = entries.map(\.id).filter { $0 != currentID }.shuffled()
        if let currentID { shuffleOrder.insert(currentID, at: 0) }
    }
    /// Returns the next occurrence without changing selection. Automatic advancement honors
    /// repeat-one; manual Next bypasses it.
    public func nextID(automatic: Bool) -> UUID? {
        guard let currentID else { return orderedIDs.first }
        if automatic && repeatMode == .one { return currentID }
        let order = orderedIDs
        guard let index = order.firstIndex(of: currentID) else { return order.first }
        if index + 1 < order.count { return order[index + 1] }
        return repeatMode == .all ? order.first : nil
    }
    /// Selects an existing occurrence, records the previous selection in history, and resets the
    /// committed position.
    public mutating func select(_ id: UUID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        if let currentID, currentID != id { history.append(currentID) }
        currentID = id
        position = 0
    }
    /// Selects the latest surviving history occurrence, falling back to the preceding traversal
    /// entry, and returns its identity.
    public mutating func previous() -> UUID? {
        while let id = history.popLast() {
            if entries.contains(where: { $0.id == id }) {
                currentID = id
                position = 0
                return id
            }
        }
        guard let currentID, let index = orderedIDs.firstIndex(of: currentID), index > 0 else {
            return currentID
        }
        let id = orderedIDs[index - 1]
        self.currentID = id
        position = 0
        return id
    }
    /// Appends a new occurrence or inserts it immediately after the current one in both normal and
    /// shuffled orders.
    public mutating func append(_ trackID: UUID, next: Bool = false) {
        let entry = QueueEntry(trackID: trackID)
        if next, let index = entries.firstIndex(where: { $0.id == currentID }) {
            entries.insert(entry, at: index + 1)
        } else {
            entries.append(entry)
        }
        if next, let index = shuffleOrder.firstIndex(where: { $0 == currentID }) {
            shuffleOrder.insert(entry.id, at: index + 1)
        } else {
            shuffleOrder.append(entry.id)
        }
    }
    /// Removes one queue occurrence from entries, shuffle order, and history; clears selection if
    /// that occurrence was current.
    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        shuffleOrder.removeAll { $0 == id }
        history.removeAll { $0 == id }
        if currentID == id {
            currentID = nil
            position = 0
        }
    }
    /// Removes every occurrence of the supplied songs and repairs selection, shuffle order,
    /// history, and position.
    public mutating func removeTracks(_ trackIDs: Set<UUID>) {
        let removed = Set(entries.filter { trackIDs.contains($0.trackID) }.map(\.id))
        entries.removeAll { removed.contains($0.id) }
        shuffleOrder.removeAll { removed.contains($0) }
        history.removeAll { removed.contains($0) }
        if let currentID, removed.contains(currentID) {
            self.currentID = entries.first?.id
            position = 0
        }
    }
}

/// UI preview state never writes back into the engine clock until a seek is committed.
public struct PlaybackTimeline: Equatable, Sendable {
    /// Validated engine-clock position in seconds; independent of a pending drag preview.
    public private(set) var elapsed: Double = 0
    /// Finite positive track duration in seconds, or nil while duration is unknown.
    public private(set) var duration: Double?
    /// Temporary slider preview in seconds that is not written to the audio engine until committed.
    public private(set) var preview: Double?
    /// Creates a zero-position timeline with unknown duration and no slider preview.
    public init() {}
    /// Whether a valid duration is available for calculating a seek target.
    public var canSeek: Bool { duration.map { $0.isFinite && $0 > 0 } ?? false }
    /// Drag preview when present, otherwise the authoritative elapsed time.
    public var displayedTime: Double { preview ?? elapsed }
    /// Normalized slider position clamped to zero through one; zero when duration is unavailable.
    public var fraction: Double {
        guard let duration, canSeek else { return 0 }
        return min(1, max(0, displayedTime / duration))
    }
    /// Nonnegative remaining seconds calculated from the displayed position, if duration is known.
    public var remaining: Double? { duration.map { max(0, $0 - displayedTime) } }
    /// Accepts an engine-clock sample in seconds, discards invalid durations, and clamps elapsed
    /// time without changing a drag preview.
    public mutating func update(elapsed: Double, duration: Double?) {
        self.duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.elapsed =
            elapsed.isFinite ? max(0, min(elapsed, self.duration ?? .greatestFiniteMagnitude)) : 0
    }
    /// Updates the temporary slider preview from a finite fraction, clamped to zero through one,
    /// without seeking the engine.
    public mutating func beginPreview(fraction: Double) {
        guard let duration, fraction.isFinite else { return }
        preview = min(1, max(0, fraction)) * duration
    }
    /// Returns the pending preview in seconds and clears it so the caller can commit exactly one
    /// seek.
    public mutating func finishPreview() -> Double? {
        defer { preview = nil }
        return preview
    }
    /// Discards a pending slider preview and returns the display to the authoritative engine clock.
    public mutating func cancelPreview() { preview = nil }
}

public struct FolderSource: Codable, Identifiable, Sendable {
    /// Stable identity of the linked folder configuration.
    public var id: UUID = UUID()
    /// Folder display name shown in music source settings.
    public var name: String
    /// Security-scoped bookmark used to regain access to the user-selected folder.
    public var bookmark: Data
    /// Last completed scan time shown in folder settings.
    public var lastScan: Date?
    /// Most recent scan or access error for this folder, if any.
    public var error: String?
    /// Local authorization revision, changed on explicit relink to reject older scan commits.
    public var bindingGeneration: UUID?
    /// True for original-file links; absent on legacy folders that imported managed copies.
    public var usesOriginalFiles: Bool?
}

public struct ListenEvent: Codable, Identifiable, Sendable {
    /// Stable event identity so periodic listening updates replace the same record instead of
    /// double-counting.
    public var id: UUID = UUID()
    /// Song whose actual listening time is recorded.
    public var trackID: UUID
    /// Start of this listening segment, used to group statistics by date.
    public var startedAt: Date
    /// Accumulated real listening seconds, excluding pauses and seek jumps.
    public var seconds: Double
}

public enum MusicError: LocalizedError, Sendable {
    case missingFile, unsupportedFormat
    case invalidBackup(String)
    case permissionDenied, invalidName
    case playback(String)
    case importFailed(String)
    case unavailable(String)
    /// Localized user-facing explanation of the library or playback failure.
    public var errorDescription: String? {
        switch self {
        case .missingFile:
            L10n.text(
                "The music file is unavailable. Import it again or download it from the cloud."
            )
        case .unsupportedFormat:
            L10n.text("This file cannot be decoded. It may be damaged or in an unsupported format.")
        case .invalidBackup(let reason):
            L10n.text("format.backup.verification_error", String(describing: reason))
        case .permissionDenied: L10n.text("Folder access has expired. Select the folder again.")
        case .invalidName: L10n.text("The name cannot be empty.")
        case .playback(let text), .importFailed(let text), .unavailable(let text): text
        }
    }
}

extension String {
    /// Case-, diacritic-, and width-insensitive normalized value used for consistent music
    /// searches.
    public var searchKey: String {
        folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .precomposedStringWithCanonicalMapping
    }
}

/// Formats nonnegative seconds as m:ss or h:mm:ss; returns --:-- for unknown or invalid values and
/// caps excessively large totals.
public func musicTime(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
    let value = Int(min(seconds, 359_999))
    return value >= 3600
        ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
        : String(format: "%d:%02d", value / 60, value % 60)
}
