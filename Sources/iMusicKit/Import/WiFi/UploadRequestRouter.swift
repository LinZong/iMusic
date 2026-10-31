import Foundation
import NIOHTTP1

/// Resolved request intent; upload streaming and socket writes belong to other components.
enum UploadRoute {
    case asset(WiFiUploadResources.Asset)
    case configuration(Data)
    case pair
    case upload(String)
    case notFound
}

/// HTTP validation failure converted to a native response by the transport adapter.
struct UploadRequestFailure: Error {
    /// Rejection status without exposing filesystem or pairing details.
    let status: HTTPResponseStatus
}

/// Stateless request validation and routing, independent of channel lifecycle and file handles.
struct UploadRequestRouter {
    /// Shared credentials and immutable allowlisted resources for this listener generation.
    let session: UploadSession
    /// Resolves supported endpoints after same-origin, credential, and filename validation.
    func resolve(_ head: HTTPRequestHead) throws -> UploadRoute {
        if let origin = head.headers.first(name: "Origin"),
            origin != "http://" + (head.headers.first(name: "Host") ?? "")
        {
            throw UploadRequestFailure(status: .forbidden)
        }
        if head.method == .POST, head.uri.hasPrefix("/upload?") {
            guard head.headers.first(name: "Authorization") == "Bearer " + session.token else {
                throw UploadRequestFailure(status: .unauthorized)
            }
            let components = URLComponents(string: "http://localhost" + head.uri)
            guard let name = components?.queryItems?.first(where: { $0.name == "name" })?.value,
                !name.contains("/"), !name.contains("\\"), !name.contains("\0"),
                name != ".", name != "..",
                ImportCoordinator.extensions.contains(
                    URL(fileURLWithPath: name)
                        .pathExtension.lowercased()
                )
            else {
                throw UploadRequestFailure(status: .badRequest)
            }
            return .upload(name)
        }
        if head.method == .GET, let asset = session.resources.asset(for: head.uri) {
            return .asset(asset)
        }
        if head.method == .GET, head.uri == "/api/config" {
            return .configuration(session.configuration)
        }
        if head.method == .POST, head.uri == "/pair" { return .pair }
        return .notFound
    }
}
