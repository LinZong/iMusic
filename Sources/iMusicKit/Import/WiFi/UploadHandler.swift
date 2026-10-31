import Foundation
import NIOCore
import NIOHTTP1

final class UploadHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    /// Application-owned directory receiving streamed upload files before import.
    private let staging: URL
    /// Shared pairing credentials and static resources for this listener session.
    private let session: UploadSession
    /// Callback transferring a completed staging file to the native import flow.
    private let onUpload: @Sendable (URL) -> Void
    /// Validated endpoint currently being processed on this connection.
    private var route: UploadRoute?
    /// One independently owned staged upload; nil for ordinary requests.
    private var upload: StagedUpload?
    /// Small buffered request body used for pairing rather than streaming audio.
    private var payload = Data()
    /// Bytes received for the current request, checked against body size limits.
    private var byteCount = 0
    /// Whether the current request has already failed validation and its remaining body must be
    /// ignored.
    private var rejected = false
    init(staging: URL, session: UploadSession, onUpload: @escaping @Sendable (URL) -> Void) {
        self.staging = staging
        self.session = session
        self.onUpload = onUpload
    }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            cleanup()
            rejected = false
            byteCount = 0
            payload = Data()
            do {
                route = try UploadRequestRouter(session: session).resolve(head)
                if case .upload(let name) = route {
                    upload = try StagedUpload(staging: staging, name: name)
                }
            } catch let error as UploadRequestFailure {
                reject(context, error.status)
            } catch { reject(context, .internalServerError) }
        case .body(var buffer):
            guard !rejected else { return }
            byteCount += buffer.readableBytes
            guard byteCount <= (upload == nil ? 1_024 : WiFiUploadResources.maxFileSize) else {
                reject(context, .payloadTooLarge)
                return
            }
            let data = Data(buffer.readBytes(length: buffer.readableBytes) ?? [])
            if let upload {
                do { try upload.write(data) } catch {
                    reject(context, .internalServerError)
                }
            } else {
                payload.append(data)
            }
        case .end:
            guard !rejected, let route else { return }
            switch route {
            case .asset(let asset):
                respond(context, .ok, contentType: asset.contentType, data: asset.data)
            case .configuration(let data):
                respond(context, .ok, contentType: "application/json; charset=utf-8", data: data)
            case .pair:
                if let token = session.pair(String(data: payload, encoding: .utf8) ?? "") {
                    respond(context, .ok, body: token)
                } else {
                    respond(
                        context,
                        .unauthorized,
                        body: L10n.text(
                            """
                            The pairing code is incorrect or too many attempts were made. Restart \
                            uploads in iMusic.
                            """
                        )
                    )
                }
            case .upload:
                do {
                    guard let upload else { throw MusicError.missingFile }
                    let url = try upload.complete()
                    self.upload = nil
                    onUpload(url)
                    respond(context, .accepted, body: L10n.text("Received. Importing now."))
                } catch { reject(context, .internalServerError) }
            case .notFound:
                respond(context, .notFound, body: "Not found")
            }
            self.route = nil
        }
    }
    func channelInactive(context: ChannelHandlerContext) {
        cleanup()
        context.fireChannelInactive()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        cleanup()
        context.close(promise: nil)
    }
    /// Releases only the incomplete staging operation associated with this connection.
    private func cleanup() {
        upload?.abort()
        upload = nil
        route = nil
    }
    private func reject(_ context: ChannelHandlerContext, _ status: HTTPResponseStatus) {
        cleanup()
        rejected = true
        respond(context, status, body: status.reasonPhrase)
    }
    private func respond(
        _ context: ChannelHandlerContext,
        _ status: HTTPResponseStatus,
        contentType: String = "text/plain; charset=utf-8",
        body: String
    ) {
        respond(context, status, contentType: contentType, data: Data(body.utf8))
    }
    private func respond(
        _ context: ChannelHandlerContext,
        _ status: HTTPResponseStatus,
        contentType: String,
        data: Data
    ) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: contentType)
        headers.add(name: "Content-Length", value: String(data.count))
        headers.add(name: "Cache-Control", value: "no-store")
        headers.add(name: "X-Content-Type-Options", value: "nosniff")
        headers.add(
            name: "Content-Security-Policy",
            value:
                """
                default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; \
                base-uri 'none'; form-action 'self'; frame-ancestors 'none'
                """
        )
        context.write(
            wrapOutboundOut(
                .head(HTTPResponseHead(version: .http1_1, status: status, headers: headers))
            ),
            promise: nil
        )
        var buffer = context.channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
