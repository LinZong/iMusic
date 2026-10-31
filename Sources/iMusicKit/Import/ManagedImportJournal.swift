import Foundation

struct ImportJournal: Codable {
    /// Unique identity of the recoverable import operation and its journal file.
    var id: UUID
    /// File name of the completed staging copy associated with this operation.
    var stagedName: String
    /// Source file name preserved when reconstructing an interrupted import.
    var originalFilename: String
    /// Prepared song metadata, if decoding completed before the interruption.
    var track: Track?
}
