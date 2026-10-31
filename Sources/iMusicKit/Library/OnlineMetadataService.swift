import Foundation

public struct OnlineRelease: Decodable, Identifiable, Sendable {
    /// MusicBrainz release identifier used to retrieve the corresponding cover image.
    public var id: String
    /// Release title returned by the online album search.
    public var title: String
    /// Optional release date as provided by MusicBrainz.
    public var date: String?
    /// Optional release country code returned by MusicBrainz.
    public var country: String?
    /// Cover Art Archive URL for the release's front cover at the requested preview size.
    public var coverURL: URL? { URL(string: "https://coverartarchive.org/release/\(id)/front-500") }
}
private struct ReleaseResponse: Decodable {
    /// Release candidates decoded from a MusicBrainz search response.
    var releases: [OnlineRelease]
}

/// Explicit online lookup boundary; editor tests can substitute a local, network-free service.
protocol OnlineMetadataProviding: Sendable {
    /// Searches release metadata after the caller checks user consent.
    func search(album: String, artist: String) async throws -> [OnlineRelease]
    /// Retrieves the selected release's cover after explicit user action.
    func artwork(for release: OnlineRelease) async throws -> Data
}

public actor OnlineMetadataService {
    /// Start time of the last metadata request, used to space MusicBrainz searches apart.
    private var lastRequest = Date.distantPast
    /// Creates an on-demand metadata client with no previous request; initialization does not
    /// perform a network lookup.
    public init() {}
    /// Performs an explicit rate-limited MusicBrainz release lookup using album and artist names;
    /// returns candidates or throws a network or response error.
    public func search(album: String, artist: String) async throws -> [OnlineRelease] {
        let delay = 1.1 - Date().timeIntervalSince(lastRequest)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        lastRequest = Date()
        var url = URLComponents(string: "https://musicbrainz.org/ws/2/release/")!
        let escapedAlbum = album.replacingOccurrences(of: "\"", with: "")
        let escapedArtist = artist.replacingOccurrences(of: "\"", with: "")
        url.queryItems = [
            URLQueryItem(
                name: "query",
                value: "release:\"\(escapedAlbum)\" AND artist:\"\(escapedArtist)\""
            ), URLQueryItem(name: "fmt", value: "json"), URLQueryItem(name: "limit", value: "8"),
        ]
        var request = URLRequest(url: url.url!)
        request.setValue(
            "iMusic/1.0 (personal offline music library)",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw MusicError.unavailable(
                L10n.text(
                    """
                    The online metadata service is temporarily unavailable. Please try again later.
                    """
                )
            )
        }
        return try JSONDecoder().decode(ReleaseResponse.self, from: data).releases
    }
    /// Downloads a selected release's front cover, requires an image response no larger than 20 MB,
    /// and returns its bytes without retaining the temporary download.
    public func artwork(for release: OnlineRelease) async throws -> Data {
        guard let url = release.coverURL else {
            throw MusicError.unavailable(L10n.text("No artwork available."))
        }
        let (urlOnDisk, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: urlOnDisk) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            response.mimeType?.hasPrefix("image/") == true,
            (try urlOnDisk.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= 20_000_000
        else { throw MusicError.unavailable(L10n.text("No usable artwork found.")) }
        return try Data(contentsOf: urlOnDisk)
    }
}

extension OnlineMetadataService: OnlineMetadataProviding {}
