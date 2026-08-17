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
        .library(name: "ForgeCapture", targets: ["ForgeCapture"]),
        .library(name: "ForgeVision", targets: ["ForgeVision"]),
        .library(name: "ForgeTestSupport", targets: ["ForgeTestSupport"]),
    ],
    targets: [
        // Pure domain. Foundation only — no AVFoundation, Vision, ARKit, SwiftUI,
        // or vendor SDKs. The module graph is what enforces that, not review.
        .target(name: "ForgeCore"),

        // Shared immutable CoreVideo frame ownership. This narrow target prevents
        // ForgeVision and ForgeCapture from depending on one another.
        .target(name: "ForgeFrame"),

        // Native phone-camera capture. Borrowed buffers are copied into ForgeFrame
        // ownership and never leak into the Foundation-only domain module.
        .target(name: "ForgeCapture", dependencies: ["ForgeCore", "ForgeFrame"]),

        // On-device perception. Consumes ForgeFrame storage and produces domain
        // scene state; never talks to the capture session or the network.
        .target(name: "ForgeVision", dependencies: ["ForgeCore", "ForgeFrame"]),

        // Mocks, fixtures, and deterministic doubles. Depends on ForgeCore only.
        .target(name: "ForgeTestSupport", dependencies: ["ForgeCore"]),

        .testTarget(
            name: "ForgeCoreTests",
            dependencies: ["ForgeCore", "ForgeTestSupport"]
        ),
        .testTarget(
            name: "ForgeCaptureTests",
            dependencies: ["ForgeCapture", "ForgeCore", "ForgeFrame"]
        ),
        .testTarget(
            name: "ForgeVisionTests",
            dependencies: ["ForgeVision", "ForgeCore", "ForgeFrame"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
