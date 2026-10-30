import Foundation

public struct OnlineRelease: Decodable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var date: String?
    public var country: String?
    public var coverURL: URL? { URL(string: "https://coverartarchive.org/release/\(id)/front-500") }
}
private struct ReleaseResponse: Decodable { var releases: [OnlineRelease] }

public actor OnlineMetadataService {
    private var lastRequest = Date.distantPast
    public init() {}
    public func search(album: String, artist: String) async throws -> [OnlineRelease] {
        let delay = 1.1 - Date().timeIntervalSince(lastRequest)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        lastRequest = Date()
        var url = URLComponents(string: "https://musicbrainz.org/ws/2/release/")!
        let escapedAlbum = album.replacingOccurrences(of: "\"", with: ""), escapedArtist = artist.replacingOccurrences(of: "\"", with: "")
        url.queryItems = [URLQueryItem(name: "query", value: "release:\"\(escapedAlbum)\" AND artist:\"\(escapedArtist)\""), URLQueryItem(name: "fmt", value: "json"), URLQueryItem(name: "limit", value: "8")]
        var request = URLRequest(url: url.url!); request.setValue("iMusic/1.0 (personal offline music library)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MusicError.unavailable(L10n.text("The online metadata service is temporarily unavailable. Please try again later.")) }
        return try JSONDecoder().decode(ReleaseResponse.self, from: data).releases
    }
    public func artwork(for release: OnlineRelease) async throws -> Data {
        guard let url = release.coverURL else { throw MusicError.unavailable(L10n.text("No artwork available.")) }
        let (urlOnDisk, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: urlOnDisk) }
        guard (response as? HTTPURLResponse)?.statusCode == 200, response.mimeType?.hasPrefix("image/") == true,
              (try urlOnDisk.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= 20_000_000 else { throw MusicError.unavailable(L10n.text("No usable artwork found.")) }
        return try Data(contentsOf: urlOnDisk)
    }
}
