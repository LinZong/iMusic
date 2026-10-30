import Foundation
import Observation
import NIOCore
import NIOHTTP1
import NIOTransportServices
import Network
import Darwin

@MainActor @Observable
public final class WiFiUploadServer {
    public private(set) var address: String?
    public private(set) var code = ""
    public private(set) var error: String?
    private var group: NIOTSEventLoopGroup?
    private var channel: Channel?
    private var runID = UUID()
    public init() {}
    public func start(staging: URL, onUpload: @escaping @Sendable (URL) -> Void) async {
        guard channel == nil, group == nil else { return }
        let resources: WiFiUploadResources, configuration: Data
        do { resources = try WiFiUploadResources(); configuration = try WiFiUploadResources.configuration() }
        catch { self.error = error.localizedDescription; return }
        let group = NIOTSEventLoopGroup(loopCount: 1); self.group = group
        code = String(format: "%06d", Int.random(in: 0...999_999)); error = nil
        let session = UploadSession(code: code, resources: resources, configuration: configuration), run = UUID(); runID = run
        do {
            let listener = try await NIOTSListenerBootstrap(group: group).childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                    channel.pipeline.addHandler(UploadHandler(staging: staging, session: session, onUpload: onUpload))
                }
            }.bind(host: "0.0.0.0", port: 0).get()
            guard runID == run else { try? await listener.close().get(); return }
            channel = listener
            address = "http://\(Self.localAddress()):\(listener.localAddress?.port ?? 0)"
        } catch { if runID == run { self.error = error.localizedDescription; self.group = nil }; try? await group.shutdownGracefully() }
    }
    public func stop() async {
        runID = UUID(); address = nil
        let old = channel, oldGroup = group; channel = nil; group = nil
        try? await old?.close().get(); try? await oldGroup?.shutdownGracefully()
    }
    private static func localAddress() -> String {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return "localhost" }
        defer { freeifaddrs(addresses) }
        var pointer = addresses
        while let value = pointer {
            defer { pointer = value.pointee.ifa_next }
            guard let addr = value.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), String(cString: value.pointee.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 { return String(cString: host) }
        }
        return "localhost"
    }
}

private final class UploadSession: @unchecked Sendable {
    let code: String, token = UUID().uuidString + UUID().uuidString
    private let lock = NSLock()
    private var failures = 0
    let resources: WiFiUploadResources
    let configuration: Data
    init(code: String, resources: WiFiUploadResources, configuration: Data) {
        self.code = code; self.resources = resources; self.configuration = configuration
    }
    func pair(_ candidate: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard failures < 6 else { return nil }
        guard candidate == code else { failures += 1; return nil }
        return token
    }
}

private final class UploadHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    private let staging: URL, session: UploadSession
    private let onUpload: @Sendable (URL) -> Void
    private var request: HTTPRequestHead?
    private var file: FileHandle?
    private var fileURL: URL?
    private var payload = Data()
    private var byteCount = 0
    private var rejected = false
    init(staging: URL, session: UploadSession, onUpload: @escaping @Sendable (URL) -> Void) { self.staging = staging; self.session = session; self.onUpload = onUpload }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            request = head; rejected = false; byteCount = 0; payload = Data()
            if let origin = head.headers.first(name: "Origin"), origin != "http://" + (head.headers.first(name: "Host") ?? "") { reject(context, .forbidden); return }
            if head.method == .POST, head.uri.hasPrefix("/upload?") {
                guard head.headers.first(name: "Authorization") == "Bearer " + session.token else { reject(context, .unauthorized); return }
                let components = URLComponents(string: "http://localhost" + head.uri)
                guard let name = components?.queryItems?.first(where: { $0.name == "name" })?.value,
                      !name.contains("/"), !name.contains("\\"), !name.contains("\0"), name != ".", name != "..",
                      ImportCoordinator.extensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased()) else { reject(context, .badRequest); return }
                do {
                    let directory = staging.appendingPathComponent("upload-" + UUID().uuidString)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let url = directory.appendingPathComponent(name)
                    guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw MusicError.importFailed(L10n.text("Unable to stage the file")) }
                    fileURL = url; file = try FileHandle(forWritingTo: url)
                } catch { reject(context, .internalServerError) }
            }
        case .body(var buffer):
            guard !rejected else { return }
            byteCount += buffer.readableBytes
            guard byteCount <= (file == nil ? 1_024 : WiFiUploadResources.maxFileSize) else { reject(context, .payloadTooLarge); return }
            let data = Data(buffer.readBytes(length: buffer.readableBytes) ?? [])
            if let file { do { try file.write(contentsOf: data) } catch { reject(context, .internalServerError) } }
            else { payload.append(data) }
        case .end:
            guard !rejected, let request else { return }
            if request.method == .GET, let asset = session.resources.asset(for: request.uri) {
                respond(context, .ok, contentType: asset.contentType, data: asset.data)
            } else if request.method == .GET, request.uri == "/api/config" {
                respond(context, .ok, contentType: "application/json; charset=utf-8", data: session.configuration)
            }
            else if request.method == .POST, request.uri == "/pair" {
                if let token = session.pair(String(data: payload, encoding: .utf8) ?? "") { respond(context, .ok, body: token) }
                else { respond(context, .unauthorized, body: L10n.text("The pairing code is incorrect or too many attempts were made. Restart uploads in iMusic.")) }
            } else if let url = fileURL {
                do {
                    try file?.synchronize(); try file?.close(); file = nil
                    try JSONEncoder().encode(url.lastPathComponent).write(to: url.deletingLastPathComponent().appendingPathComponent(".complete"), options: .atomic)
                    fileURL = nil; onUpload(url); respond(context, .accepted, body: L10n.text("Received. Importing now."))
                }
                catch { reject(context, .internalServerError) }
            } else { respond(context, .notFound, body: "Not found") }
            self.request = nil
        }
    }
    func channelInactive(context: ChannelHandlerContext) { cleanup(); context.fireChannelInactive() }
    func errorCaught(context: ChannelHandlerContext, error: Error) { cleanup(); context.close(promise: nil) }
    private func cleanup() { try? file?.close(); file = nil; if let fileURL { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }; fileURL = nil }
    private func reject(_ context: ChannelHandlerContext, _ status: HTTPResponseStatus) { cleanup(); rejected = true; respond(context, status, body: status.reasonPhrase) }
    private func respond(_ context: ChannelHandlerContext, _ status: HTTPResponseStatus, contentType: String = "text/plain; charset=utf-8", body: String) {
        respond(context, status, contentType: contentType, data: Data(body.utf8))
    }
    private func respond(_ context: ChannelHandlerContext, _ status: HTTPResponseStatus, contentType: String, data: Data) {
        var headers = HTTPHeaders(); headers.add(name: "Content-Type", value: contentType); headers.add(name: "Content-Length", value: String(data.count))
        headers.add(name: "Cache-Control", value: "no-store"); headers.add(name: "X-Content-Type-Options", value: "nosniff")
        headers.add(name: "Content-Security-Policy", value: "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'")
        context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: status, headers: headers))), promise: nil)
        var buffer = context.channel.allocator.buffer(capacity: data.count); buffer.writeBytes(data)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil); context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
