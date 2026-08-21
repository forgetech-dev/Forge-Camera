import ForgeCapture
import ForgeCore
import SwiftUI

/// Draws the guidance layer over the frame.
///
/// Renders exactly what it is given and applies no smoothing of its own: the engine
/// owns deadband, hysteresis, and stability. A view-layer animation that disguised
/// jitter would hide a real bug and add latency.
///
/// Subject detection rectangles are not part of this presentation model. A detector's
/// bounds explain what it found; they are not a composition recommendation.
struct GuidanceOverlayView: View {
    let guidance: GuidanceState
    let frameGeometry: FrameGeometry?
    let targetFrame: NormalizedRect?
    let previewMirrored: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            if let frameGeometry,
               let geometry = PreviewGeometry(
                   frame: frameGeometry,
                   viewportSize: size,
                   previewMirrored: previewMirrored
               ) {
                ZStack(alignment: .topLeading) {
                    if let targetFrame {
                        targetFrameOverlay(geometry.rect(for: targetFrame), in: size)
                    }

                    ForEach(
                        Array(guidance.overlay.avoidRegions.enumerated()),
                        id: \.offset
                    ) { _, region in
                        rectangle(geometry.rect(for: region))
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(.red.opacity(0.7))
                    }

                    if let y = guidance.overlay.currentHorizonY {
                        horizon(
                            at: geometry.point(for: NormalizedPoint(x: 0, y: y)).y,
                            dashed: false
                        )
                        .foregroundStyle(.secondary.opacity(0.7))
                    }
                    if let y = guidance.overlay.targetHorizonY {
                        horizon(
                            at: geometry.point(for: NormalizedPoint(x: 0, y: y)).y,
                            dashed: true
                        )
                        .foregroundStyle(.yellow)
                    }
                }
                // Contrast cannot come from colour alone over unpredictable live imagery.
                .shadow(color: .black.opacity(0.6), radius: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suggested framing area")
        .accessibilityHidden(frameGeometry == nil || targetFrame == nil)
    }

    private func targetFrameOverlay(_ targetRect: CGRect, in size: CGSize) -> some View {
        ZStack {
            outsideScrim(around: targetRect, in: size)
                .fill(
                    Color(uiColor: .systemBackground).opacity(0.28),
                    style: FillStyle(eoFill: true)
                )
            rectangle(targetRect)
                .stroke(Color(uiColor: .systemBackground).opacity(0.85), lineWidth: 4)
            rectangle(targetRect)
                .stroke(Color(uiColor: .label), lineWidth: 2)
        }
    }

    private func outsideScrim(around targetRect: CGRect, in size: CGSize) -> Path {
        var path = Path(CGRect(origin: .zero, size: size))
        path.addRect(targetRect)
        return path
    }

    private func rectangle(_ rect: CGRect) -> Path {
        Path(rect)
    }

    private func horizon(at y: CGFloat, dashed: Bool) -> some Shape {
        HorizonLine(y: y, dashed: dashed)
    }
}

private struct HorizonLine: Shape {
    let y: CGFloat
    let dashed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: rect.width, y: y))
        return dashed
            ? path.strokedPath(StrokeStyle(lineWidth: 2, dash: [8, 6]))
            : path.strokedPath(StrokeStyle(lineWidth: 1))
    }
}
