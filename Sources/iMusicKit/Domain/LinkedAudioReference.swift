import Foundation

/// Portable identity of an original-file song; permissions and absolute URLs stay on this device.
public struct LinkedAudioReference: Codable, Hashable, Sendable {
    /// Logical folder identity shared by metadata sync and backup.
    public var folderID: UUID
    /// Display name used when the folder must be authorized on another device.
    public var folderName: String
    /// Relative location offered only during an explicit folder relink, never as file identity.
    public var relativePath: String
}

/// Device-local source state, independent of user edits and synchronized song metadata.
public enum LinkedFileState: String, Codable, Sendable {
    case pending, preparing, ready, missing, failed, cancelled
}

/// Durable admission job and local locator; never exported or synchronized.
public struct LinkedFileBinding: Codable, Sendable, Identifiable {
    /// Stable song identity, preserved across source moves and metadata refreshes.
    public var id: UUID
    /// Authorized parent folder identity.
    public var folderID: UUID
    /// Root authorization revision under which this locator was prepared.
    public var folderGeneration: UUID?
    /// File bookmark used to follow moves without guessing by name.
    public var bookmark: Data
    /// Last observed relative path for display and explicit relinking.
    public var relativePath: String
    /// File creation date helps reject a replacement that reuses a deleted path.
    public var created: Date?
    /// Last successfully parsed byte count, used only to detect metadata changes.
    public var size: Int?
    /// Last successfully parsed modification time.
    public var modified: Date?
    /// Admission or last reconciliation state.
    public var state: LinkedFileState = .pending
    /// Number of unsuccessful automatic admissions since the last explicit retry or success.
    public var attempts: Int = 0
    /// Localized explanation of the last failed operation.
    public var error: String?
    /// Namespaced key in the existing device-local settings table.
    var storageKey: String { "linked.item." + folderID.uuidString + "." + id.uuidString }
}
