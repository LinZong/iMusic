import PackagePlugin
import Foundation

@main
struct WiFiUploadBuild: BuildToolPlugin {
    /// Builds the React upload client into plugin-owned resources before SwiftPM packages its bundle.
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        [.prebuildCommand(
            displayName: "Build iMusic Wi-Fi Upload (React + TypeScript)",
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [context.package.directoryURL.appending(path: "Scripts/build_wifi_upload.sh").path,
                        context.package.directoryURL.path,
                        context.pluginWorkDirectoryURL.path],
            environment: [
                "IMUSIC_NODE_HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
                "NODE_BINARY": ProcessInfo.processInfo.environment["NODE_BINARY"] ?? ""
            ],
            outputFilesDirectory: context.pluginWorkDirectoryURL.appending(path: "Resources")
        )]
    }
}
