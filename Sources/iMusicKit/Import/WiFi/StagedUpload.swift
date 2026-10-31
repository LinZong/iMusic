import Foundation

/// Owns exactly one upload file and its completion marker, independent of HTTP routing.
final class StagedUpload {
    /// Fully contained application-owned upload path.
    let url: URL
    /// Open writer, cleared before completion or abortion.
    private var file: FileHandle?
    /// Whether ownership has transferred to native import/recovery.
    private var completed = false
    /// Creates an isolated staging directory for a previously validated basename.
    init(staging: URL, name: String) throws {
        let directory = staging.appendingPathComponent("upload-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(name)
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            try? FileManager.default.removeItem(at: directory)
            throw MusicError.importFailed(L10n.text("Unable to stage the file"))
        }
        do { file = try FileHandle(forWritingTo: url) } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
    /// Streams a bounded chunk without buffering the full audio file in memory.
    func write(_ data: Data) throws { try file?.write(contentsOf: data) }
    /// Durably marks a complete file before handing its ownership to the importer.
    func complete() throws -> URL {
        try file?.synchronize()
        try file?.close()
        file = nil
        try JSONEncoder().encode(url.lastPathComponent)
            .write(
                to: url.deletingLastPathComponent().appendingPathComponent(".complete"),
                options: .atomic
            )
        completed = true
        return url
    }
    /// Removes only this incomplete staging file; completed uploads remain recoverable.
    func abort() {
        try? file?.close()
        file = nil
        if !completed { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }
    deinit { abort() }
}
