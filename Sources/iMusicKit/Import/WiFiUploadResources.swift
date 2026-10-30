import Foundation

/// Only build-manifest entries are exposed; request paths never become filesystem paths.
struct WiFiUploadResources: Sendable {
    struct Asset: Sendable {
        /// Static resource bytes read from the app's bundled upload assets.
        let data: Data
        /// Whitelisted MIME type returned with the static HTTP response.
        let contentType: String
    }
    /// Maximum accepted upload size in bytes, shared by server validation and browser
    /// configuration.
    static let maxFileSize = 4_000_000_000
    /// In-memory HTTP path allowlist loaded from the build-generated resource manifest.
    private let assets: [String: Asset]
    /// Loads only manifest-listed static assets and fails startup if required resources or MIME
    /// types are invalid.
    init() throws {
        struct Manifest: Decodable {
            /// Bundled resource file names explicitly authorized by the build-generated upload
            /// manifest.
            let files: [String]
        }
        guard let url = Bundle.module.url(forResource: "upload-assets", withExtension: "json")
        else {
            throw MusicError.importFailed(
                L10n.text("Wi-Fi Upload resources are missing. Rebuild iMusic.")
            )
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        var assets: [String: Asset] = [:]
        let types = [
            "html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
            "css": "text/css; charset=utf-8",
        ]
        for name in manifest.files {
            guard name.hasPrefix("upload-"), !name.contains("/"), !name.contains("\\"),
                !name.contains("\0"),
                let type = types[(name as NSString).pathExtension],
                let file = Bundle.module.url(forResource: name, withExtension: nil)
            else {
                throw MusicError.importFailed(
                    L10n.text("Wi-Fi Upload resources are missing. Rebuild iMusic.")
                )
            }
            assets["/" + name] = Asset(data: try Data(contentsOf: file), contentType: type)
        }
        guard let index = assets.removeValue(forKey: "/upload-index.html"), !index.data.isEmpty
        else {
            throw MusicError.importFailed(
                L10n.text("Wi-Fi Upload resources are missing. Rebuild iMusic.")
            )
        }
        assets["/"] = index
        assets["/index.html"] = index
        self.assets = assets
    }
    /// Looks up an exact allowlisted HTTP path; never resolves request text as a filesystem path.
    func asset(for path: String) -> Asset? { assets[path] }
    /// Encodes the native app language and shared upload limits for the browser configuration
    /// endpoint.
    static func configuration(locale: Locale? = nil) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "language": L10n.language(for: locale),
                "extensions": ImportCoordinator.extensions.sorted(),
                "maxFileSize": maxFileSize,
            ],
            options: [.sortedKeys]
        )
    }
}
