import Foundation

/// Coordinates a bounded, cancellable copy without decoding or mutating library records.
struct CoordinatedFileCopier {
    func copy(_ source: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator()
            .coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                do {
                    let reader = try FileHandle(forReadingFrom: readable)
                    defer { try? reader.close() }
                    guard FileManager.default.createFile(atPath: destination.path, contents: nil)
                    else {
                        throw MusicError.importFailed(
                            L10n.text("Unable to create the staging file.")
                        )
                    }
                    let writer = try FileHandle(forWritingTo: destination)
                    defer { try? writer.close() }
                    while let data = try reader.read(upToCount: 1_048_576), !data.isEmpty {
                        if Task.isCancelled { throw CancellationError() }
                        try writer.write(contentsOf: data)
                    }
                    try writer.synchronize()
                } catch { copyError = error }
            }
        if let error = coordinationError ?? copyError as NSError? { throw error }
    }
}
