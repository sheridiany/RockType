// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RoarkT",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RoarkTApp", targets: ["RoarkTApp"]),
        .executable(name: "RoarkTTranslationService", targets: ["RoarkTTranslationService"]),
        .library(name: "RoarkTCore", targets: ["RoarkTCore"]),
    ],
    targets: [
        .target(
            name: "RoarkTXPCProtocol",
            path: "Shared/XPCProtocol",
            publicHeadersPath: "include"
        ),
        .target(name: "RoarkTCore", path: "Core"),
        .target(name: "RoarkTPlatform", dependencies: ["RoarkTCore"], path: "Platform"),
        .executableTarget(
            name: "RoarkTApp",
            dependencies: ["RoarkTCore", "RoarkTPlatform", "RoarkTXPCProtocol"],
            path: "App",
            exclude: ["Info.plist"]
        ),
        .executableTarget(
            name: "RoarkTTranslationService",
            dependencies: ["RoarkTCore", "RoarkTXPCProtocol"],
            path: "Services/TranslationService"
        ),
        .testTarget(name: "RoarkTPlatformTests", dependencies: ["RoarkTPlatform"], path: "Tests/PlatformTests", resources: [.copy("Fixtures")]),
        .testTarget(name: "RoarkTSurfaceTests", dependencies: ["RoarkTApp", "RoarkTCore"], path: "Tests/SurfaceTests"),
        .testTarget(name: "RoarkTSettingsStoreTests", dependencies: ["RoarkTApp", "RoarkTCore"], path: "Tests/SettingsStoreTests"),
        .testTarget(name: "RoarkTSelectionTests", dependencies: ["RoarkTApp", "RoarkTCore", "RoarkTPlatform"], path: "Tests/SelectionTests"),
        .testTarget(name: "RoarkTOperationTests", dependencies: ["RoarkTCore", "RoarkTApp"], path: "Tests/OperationTests"),
        .testTarget(name: "RoarkTCoreTests", dependencies: ["RoarkTCore"], path: "Tests/CoreTests"),
        .testTarget(
            name: "RoarkTTranslationServiceTests",
            dependencies: ["RoarkTTranslationService", "RoarkTApp", "RoarkTCore", "RoarkTXPCProtocol"],
            path: "Tests/TranslationServiceTests"
        ),
    ]
)
