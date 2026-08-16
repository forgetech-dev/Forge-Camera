import ForgeCore
import SwiftUI

/// A harness that runs the real pipeline against a synthetic scene.
///
/// There is no camera yet, and the simulator has none regardless, so this drives the
/// production `HeuristicDirector`, `GuidanceEngine`, and `GuidanceCueFormatter` from a
/// scene you can drag around. It exists to make the guidance behaviour visible — the
/// deadband, the cue budget, the readiness transition — before AVFoundation lands.
///
/// This is not the capture screen. That arrives with the camera pipeline.
struct GuidancePreviewScreen: View {
    // Held as Double rather than CGPoint: normalized frame space is unitless, and
    // CGPoint's CGFloat components do not bind to a Double slider.
    @State private var subjectX = 0.3
    @State private var subjectY = 0.55
    @State private var subjectHeight = 0.35
    @State private var roll = 0.0

    private let director = HeuristicDirector()
    private let engine = GuidanceEngine()
    private let formatter = GuidanceCueFormatter()

    var body: some View {
        VStack(spacing: 0) {
            frame
            controls
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
    }

    // MARK: Frame

    private var frame: some View {
        ZStack {
            // Stands in for the camera preview.
            LinearGradient(
                colors: [Color(white: 0.28), Color(white: 0.12)],
                startPoint: .top,
                endPoint: .bottom
            )

            GuidanceOverlayView(guidance: guidance)

            VStack {
                readinessBadge
                Spacer()
                cueList
            }
            .padding()
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipped()
    }

    private var readinessBadge: some View {
        HStack {
            Text(formatter.text(for: guidance.readiness))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
            Spacer()
        }
    }

    private var cueList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(guidance.cues.enumerated()), id: \.offset) { _, cue in
                HStack(spacing: 8) {
                    Text(formatter.text(for: cue))
                        .font(.headline)
                    if let rotation = formatter.rotationText(for: cue) {
                        Text(rotation)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.yellow)
                    }
                    Spacer()
                    Text(cue.actor.rawValue)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            slider("Subject x", value: $subjectX, range: 0.1 ... 0.9)
            slider("Subject y", value: $subjectY, range: 0.1 ... 0.9)
            slider("Subject height", value: $subjectHeight, range: 0.1 ... 0.9)
            slider("Roll", value: $roll, range: -20 ... 20, format: "%.0f°")

            Text("Synthetic scene driving the real guidance engine. No camera involved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func slider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String = "%.2f"
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    // MARK: Pipeline

    private var scene: SceneState {
        let width = subjectHeight * 0.45
        return SceneState(
            timestamp: 0,
            frame: FrameGeometry(
                pixelWidth: 1080,
                pixelHeight: 1440,
                appliedRotation: .zero,
                wasMirrored: false
            ),
            subjects: [
                DetectedSubject(
                    id: SubjectID("preview"),
                    bounds: NormalizedRect(
                        x: subjectX - width / 2,
                        y: subjectY - subjectHeight / 2,
                        width: width,
                        height: subjectHeight
                    )
                ),
            ],
            horizon: HorizonEstimate(normalizedY: 0.5, roll: .degrees(roll), confidence: 0.9),
            camera: CameraState(
                focalLength: 35,
                fieldOfView: FieldOfView(horizontal: .degrees(54), aspectRatio: 3.0 / 4.0)
            )
        )
    }

    private var guidance: GuidanceState {
        let current = scene
        let plan = director.makePlan(
            for: DirectorRequest(requestId: "preview", scene: current)
        )
        return engine.guidance(for: current, plan: plan).guidance
    }
}

#Preview {
    GuidancePreviewScreen()
}
