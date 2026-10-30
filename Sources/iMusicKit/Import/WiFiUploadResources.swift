import Foundation

/// Only build-manifest entries are exposed; request paths never become filesystem paths.
struct WiFiUploadResources: Sendable {
    struct Asset: Sendable {
        let data: Data
        let contentType: String
    }
    static let maxFileSize = 4_000_000_000
    private let assets: [String: Asset]
    init() throws {
        struct Manifest: Decodable { let files: [String] }
        guard let url = Bundle.module.url(forResource: "upload-assets", withExtension: "json") else {
            throw MusicError.importFailed(L10n.text("Wi-Fi Upload resources are missing. Rebuild iMusic."))
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        var assets: [String: Asset] = [:]
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "css": "text/css; charset=utf-8"]
        for name in manifest.files {
            guard name.hasPrefix("upload-"), !name.contains("/"), !name.contains("\\"), !name.contains("\0"),
                  let type = types[(name as NSString).pathExtension],
                  let file = Bundle.module.url(forResource: name, withExtension: nil) else {
                throw MusicError.importFailed(L10n.text("Wi-Fi Upload resources are missing. Rebuild iMusic."))
            }
            assets["/" + name] = Asset(data: try Data(contentsOf: file), contentType: type)
        }
        guard let index = assets.removeValue(forKey: "/upload-index.html"), !index.data.isEmpty else {
            throw MusicError.importFailed(L10n.text("Wi-Fi Upload resources are missing. Rebuild iMusic."))
        }
        assets["/"] = index; assets["/index.html"] = index
        self.assets = assets
    }
    func asset(for path: String) -> Asset? { assets[path] }
    static func configuration(locale: Locale? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "language": L10n.language(for: locale),
            "extensions": ImportCoordinator.extensions.sorted(),
            "maxFileSize": maxFileSize
        ], options: [.sortedKeys])
    }
}
