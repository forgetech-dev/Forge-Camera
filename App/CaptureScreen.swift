import ForgeCapture
import ForgeCore
import SwiftUI

/// The live capture screen.
///
/// The preview is the content; everything else is drawn over it and kept small. The
/// guidance layer sits directly on the image because it is spatial, and the status
/// chrome is pinned to the edges so the centre of the frame stays clear.
struct CaptureScreen: View {
    @State private var model = CaptureModel()
    private let formatter = GuidanceCueFormatter()

    var body: some View {
        Group {
            if case let .failed(error) = model.status {
                // A camera failure must not leave the app useless. The guidance engine
                // needs no camera to be worth looking at, so the offline harness takes
                // over and says plainly why. This is also what a simulator sees, which
                // makes the core loop demonstrable without hardware.
                unavailable(error)
            } else {
                liveCapture
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .task {
            model.start()
        }
        .onDisappear {
            model.stop()
        }
    }

    private var liveCapture: some View {
        ZStack {
            CameraPreviewView(source: model.source)
                .ignoresSafeArea()

            GuidanceOverlayView(guidance: model.guidance)
                .ignoresSafeArea()

            VStack {
                statusBar
                Spacer()
                cues
            }
            .padding()
        }
    }

    private func unavailable(_ error: CaptureError) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "video.slash")
                VStack(alignment: .leading, spacing: 2) {
                    Text("No camera available")
                        .font(.footnote.weight(.semibold))
                    Text(error.recoverySuggestion ?? "Showing the guidance engine on a test scene.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial)

            GuidancePreviewScreen()
        }
    }

    // MARK: Chrome

    /// Status lives at the top edge, where it is readable but out of the way of the
    /// thumb and out of the middle of the photograph.
    private var statusBar: some View {
        HStack(spacing: 8) {
            Label(statusText, systemImage: statusSymbol)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())

            Spacer()

            if case .ready = model.guidance.readiness {
                Text("Ready")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }

    /// At most one row per actor, as the engine already guarantees. Rendering more
    /// would mean the budget was not being respected somewhere upstream.
    private var cues: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(model.guidance.cues.enumerated()), id: \.offset) { _, cue in
                HStack(spacing: 8) {
                    Text(formatter.text(for: cue))
                        .font(.headline)
                    if let rotation = formatter.rotationText(for: cue) {
                        Text(rotation)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: Status presentation

    private var statusText: String {
        switch model.status {
        case .idle: "Idle"
        case .awaitingPermission: "Camera permission"
        case .configuring: "Starting"
        case .running: "\(model.subjectCount) subject\(model.subjectCount == 1 ? "" : "s")"
        case .interrupted: "Interrupted"
        case let .failed(error): error.recoverySuggestion ?? "Camera unavailable"
        }
    }

    /// State is carried by the glyph as well as the words, so it survives being
    /// glanced at over a bright scene.
    private var statusSymbol: String {
        switch model.status {
        case .idle: "camera"
        case .awaitingPermission: "lock"
        case .configuring: "camera.badge.ellipsis"
        case .running: "person.fill.viewfinder"
        case .interrupted: "exclamationmark.triangle"
        case .failed: "xmark.octagon"
        }
    }
}
