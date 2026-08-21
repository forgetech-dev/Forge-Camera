import ForgeCapture
import ForgeCore
import SwiftUI

/// The live capture screen.
///
/// The preview is the content; everything else is drawn over it and kept small. The
/// guidance layer sits directly on the image because it is spatial, and the status
/// chrome is pinned to the edges so the centre of the frame stays clear.
struct CaptureScreen: View {
    /// A deterministic framing proposal used to validate the production preview path.
    /// The next slice replaces this value with the Director's target frame.
    private static let deterministicTargetFrame = NormalizedRect(
        x: 0.15,
        y: 0.16,
        width: 0.7,
        height: 0.68
    )

    @State private var model = CaptureModel()
    private let formatter = GuidanceCueFormatter()

    var body: some View {
        Group {
            if case let .failed(error) = model.status {
                // A camera failure is stated directly. Product guidance belongs on a
                // real image, so this path does not substitute a synthetic composition.
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

            GuidanceOverlayView(
                guidance: model.guidance,
                frameGeometry: model.frameGeometry,
                targetFrame: Self.deterministicTargetFrame,
                previewMirrored: false
            )
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
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "video.slash")
                .font(.system(size: 40, weight: .medium))
                .accessibilityHidden(true)
            Text("No camera available")
                .font(.headline)
            Text(error.recoverySuggestion ?? "Connect or enable a camera, then try again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
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
        case .running: "Camera ready"
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
        case .running: "camera.fill"
        case .interrupted: "exclamationmark.triangle"
        case .failed: "xmark.octagon"
        }
    }
}
