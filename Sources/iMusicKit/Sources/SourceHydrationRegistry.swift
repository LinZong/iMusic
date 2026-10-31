import Foundation

/// Coalesces system download requests while each reader keeps its own cancellable coordination.
final class SourceHydrationRegistry: @unchecked Sendable {
    /// Shared process-local request registry; it never owns downloaded audio or folder grants.
    static let shared = SourceHydrationRegistry()
    /// Protects the active consumer counts against independent source worker queues.
    private let lock = NSLock()
    /// Number of active coordinated readers per canonical provider URL.
    private var readers: [URL: Int] = [:]

    /// Requests hydration once; cancelling one reader does not cancel another reader's download.
    func acquire(_ url: URL) throws {
        let key = url.standardizedFileURL
        lock.lock()
        defer { lock.unlock() }
        if readers[key] == nil {
            let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
            if values.isUbiquitousItem == true {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
        readers[key, default: 0] += 1
    }
    /// Retires one consumer while leaving system-managed cached content untouched.
    func release(_ url: URL) {
        let key = url.standardizedFileURL
        lock.lock()
        defer { lock.unlock() }
        guard let count = readers[key] else { return }
        if count == 1 { readers.removeValue(forKey: key) } else { readers[key] = count - 1 }
    }
}
