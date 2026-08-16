// swift-tools-version: 6.0
import PackageDescription

/// Everything that can live in SwiftPM does, so the fast, headless, hardware-free
/// loop (`swift build` / `swift test`) covers as much of the codebase as possible.
/// No Xcode project, no simulator, and no code signing are required to work here.
let package = Package(
    name: "ForgeCamera",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "ForgeCore", targets: ["ForgeCore"]),
        .library(name: "ForgeTestSupport", targets: ["ForgeTestSupport"]),
    ],
    targets: [
        // Pure domain. Foundation only — no AVFoundation, Vision, ARKit, SwiftUI,
        // or vendor SDKs. The module graph is what enforces that, not review.
        .target(name: "ForgeCore"),

        // Mocks, fixtures, and deterministic doubles. Depends on ForgeCore only.
        .target(name: "ForgeTestSupport", dependencies: ["ForgeCore"]),

        .testTarget(
            name: "ForgeCoreTests",
            dependencies: ["ForgeCore", "ForgeTestSupport"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
