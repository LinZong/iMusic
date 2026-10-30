// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iMusic",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "iMusicKit", targets: ["iMusicKit"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sbooth/SFBAudioEngine.git", exact: "0.14.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        // NIO 2.104.0 traps during HTTP pipeline setup on the iOS 17 runtime.
        // Keep this pin until an upstream fix is released and verified on iOS 17.
        // https://github.com/apple/swift-nio/issues/3764
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.103.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0"),
    ],
    targets: [
        .target(
            name: "iMusicKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            ],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            plugins: [.plugin(name: "WiFiUploadBuild")]
        ),
        .plugin(name: "WiFiUploadBuild", capability: .buildTool()),
        .testTarget(
            name: "iMusicKitTests",
            dependencies: ["iMusicKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
