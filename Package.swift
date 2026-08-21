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
        .library(name: "ForgeBridge", targets: ["ForgeBridge"]),
        .library(name: "ForgeDirectorCodex", targets: ["ForgeDirectorCodex"]),
        .library(name: "ForgeTestSupport", targets: ["ForgeTestSupport"]),
        .executable(
            name: "forge-director-codex-spike",
            targets: ["ForgeDirectorCodexSpike"]
        ),
        .executable(name: "forge-server", targets: ["ForgeServer"]),
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

        // Vendor-neutral local wire boundary. It owns HTTP framing and the
        // loopback endpoint, but knows nothing about any concrete AI provider.
        .target(name: "ForgeBridge", dependencies: ["ForgeCore"]),

        // Development-Mac provider boundary. It owns image-to-plan behavior but
        // never HTTP transport or iPhone credentials.
        .target(
            name: "ForgeDirectorCodex",
            dependencies: ["ForgeCore"],
            resources: [.copy("Resources/CompositionPlan.schema.json")]
        ),

        // Explicit external-service spike. Ordinary builds compile it, but ordinary
        // tests never execute it or require a Codex subscription/network connection.
        .executableTarget(
            name: "ForgeDirectorCodexSpike",
            dependencies: ["ForgeDirectorCodex"],
            path: "Tools/ForgeDirectorCodexSpike"
        ),

        // Development-only Mac composition root. The first server slice binds
        // loopback only; LAN exposure and pairing are deliberately deferred.
        .executableTarget(
            name: "ForgeServer",
            dependencies: ["ForgeBridge", "ForgeDirectorCodex"],
            path: "Tools/ForgeServer"
        ),

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
        .testTarget(
            name: "ForgeDirectorCodexTests",
            dependencies: ["ForgeDirectorCodex", "ForgeCore"]
        ),
        .testTarget(
            name: "ForgeBridgeTests",
            dependencies: ["ForgeBridge", "ForgeCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
