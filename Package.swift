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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.8.0"),
    ],
    targets: [
        .testTarget(name: "InputMethodChecks", path: "Tests/InputMethodTests",
                    exclude: ["SessionChecks.swift", "ModifierChecks.swift", "PanelChecks.swift", "RimeChecks.swift", "RimeBridge.h", "PanelBridge.h"]),
        .testTarget(name: "MenuIconTests", path: "Tests/MenuIcon",
                    exclude: ["test-menu-icon.swift", "SystemRendererProbe.m", "CompareScreenshot.swift"]),
        .target(
            name: "RoarkTXPCProtocol",
            path: "Shared/XPCProtocol",
            publicHeadersPath: "include"
        ),
        .target(name: "RoarkTCore", path: "Core"),
        .target(name: "RoarkTPlatform", dependencies: ["RoarkTCore"], path: "Platform"),
        .executableTarget(
            name: "RoarkTApp",
            dependencies: ["RoarkTCore", "RoarkTPlatform", "RoarkTXPCProtocol", .product(name: "Sparkle", package: "Sparkle")],
            path: "App",
            exclude: ["Info.plist"]
        ),
        .executableTarget(
            name: "RoarkTTranslationService",
            dependencies: ["RoarkTCore", "RoarkTXPCProtocol"],
            path: "Services/TranslationService"
        ),
        .testTarget(name: "RoarkTScreenshotTests", dependencies: ["RoarkTApp", "RoarkTPlatform"], path: "Tests/ScreenshotTests"),
        .testTarget(name: "RoarkTPlatformTests", dependencies: ["RoarkTPlatform"], path: "Tests/PlatformTests", resources: [.copy("Fixtures")]),
        .testTarget(name: "RoarkTSurfaceTests", dependencies: ["RoarkTApp", "RoarkTCore"], path: "Tests/SurfaceTests"),
        .testTarget(name: "RoarkTSettingsStoreTests", dependencies: ["RoarkTApp", "RoarkTCore"], path: "Tests/SettingsStoreTests"),
        .testTarget(name: "RoarkTSelectionTests", dependencies: ["RoarkTApp", "RoarkTCore", "RoarkTPlatform"], path: "Tests/SelectionTests"),
        .testTarget(name: "RoarkTOperationTests", dependencies: ["RoarkTCore", "RoarkTApp"], path: "Tests/OperationTests"),
        .testTarget(name: "RoarkTPersonalScriptsTests", dependencies: ["RoarkTCore"], path: "Tests/PersonalScriptsTests", exclude: ["checks.py", "CandidateProbe.swift"]),
        .testTarget(name: "RoarkTCoreTests", dependencies: ["RoarkTCore"], path: "Tests/CoreTests"),
        .testTarget(
            name: "RoarkTTranslationServiceTests",
            dependencies: ["RoarkTTranslationService", "RoarkTApp", "RoarkTCore", "RoarkTXPCProtocol"],
            path: "Tests/TranslationServiceTests"
        ),
    ]
)
