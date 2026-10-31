import Foundation

final class UploadSession: @unchecked Sendable {
    /// Pairing secret shared with the visible native transfer page.
    let code: String
    /// Random bearer credential issued after pairing and scoped to this listener session.
    let token = UUID().uuidString + UUID().uuidString
    /// Protects the pairing failure counter across concurrent HTTP connections.
    private let lock = NSLock()
    /// Number of unsuccessful pairing attempts used to limit repeated guesses.
    private var failures = 0
    /// Bundled upload page resources exposed through a fixed HTTP path allowlist.
    let resources: WiFiUploadResources
    /// Encoded client language, supported extensions, and file-size limits for this session.
    let configuration: Data
    init(code: String, resources: WiFiUploadResources, configuration: Data) {
        self.code = code
        self.resources = resources
        self.configuration = configuration
    }
    func pair(_ candidate: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard failures < 6 else { return nil }
        guard candidate == code else {
            failures += 1
            return nil
        }
        return token
    }
}
