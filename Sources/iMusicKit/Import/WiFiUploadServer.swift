import Darwin
import Foundation
import NIOCore
import NIOHTTP1
import NIOTransportServices
import Network
import Observation

@MainActor @Observable
public final class WiFiUploadServer {
    /// Unique local IPv4 HTTP endpoints while listening; empty when stopped.
    public private(set) var addresses: [String] = []
    /// Short-lived pairing code displayed only while the transfer page is open.
    public private(set) var code = ""
    /// Most recent listener startup failure presented by the transfer page.
    public private(set) var error: String?
    /// Network.framework-backed event loop group owned by the current listener.
    private var group: NIOTSEventLoopGroup?
    /// Bound server channel closed when the transfer page is dismissed or the app backgrounds.
    private var channel: Channel?
    /// Listener generation token that invalidates a startup finishing after stop was requested.
    private var runID = UUID()
    /// Injected interface discovery; does not own listener or pairing state.
    private let addressProvider: any LocalAddressProviding
    /// Creates a stopped local upload service; the listener is started explicitly by the transfer
    /// page.
    public convenience init() { self.init(addressProvider: InterfaceAddressProvider()) }
    /// Creates a listener using replaceable address discovery.
    init(addressProvider: any LocalAddressProviding) { self.addressProvider = addressProvider }
    /// Starts an ephemeral local HTTP listener, creates fresh pairing credentials, and calls
    /// onUpload for each completed staging file. Startup failures are published through error.
    public func start(staging: URL, onUpload: @escaping @Sendable (URL) -> Void) async {
        guard channel == nil, group == nil else { return }
        let resources: WiFiUploadResources
        let configuration: Data
        do {
            resources = try WiFiUploadResources()
            configuration = try WiFiUploadResources.configuration()
        } catch {
            self.error = error.localizedDescription
            return
        }
        let group = NIOTSEventLoopGroup(loopCount: 1)
        self.group = group
        code = String(format: "%06d", Int.random(in: 0...999_999))
        error = nil
        let session = UploadSession(code: code, resources: resources, configuration: configuration)
        let run = UUID()
        runID = run
        do {
            let listener = try await NIOTSListenerBootstrap(group: group)
                .childChannelInitializer { channel in
                    channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true)
                        .flatMap {
                            channel.pipeline.addHandler(
                                UploadHandler(
                                    staging: staging,
                                    session: session,
                                    onUpload: onUpload
                                )
                            )
                        }
                }
                .bind(host: "0.0.0.0", port: 0).get()
            guard runID == run else {
                try? await listener.close().get()
                return
            }
            channel = listener
            let port = listener.localAddress?.port ?? 0
            addresses = addressProvider.addresses().map { "http://\($0):\(port)" }
        } catch {
            if runID == run {
                self.error = error.localizedDescription
                self.group = nil
            }
            try? await group.shutdownGracefully()
        }
    }
    /// Invalidates pending startup, closes the listener, shuts down its event loop group, and
    /// clears all advertised addresses.
    public func stop() async {
        runID = UUID()
        addresses = []
        let old = channel
        let oldGroup = group
        channel = nil
        group = nil
        try? await old?.close().get()
        try? await oldGroup?.shutdownGracefully()
    }

}
