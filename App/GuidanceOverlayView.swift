import ForgeCore
import SwiftUI

/// Draws the guidance layer over the frame.
///
/// Renders exactly what it is given and applies no smoothing of its own: the engine
/// owns deadband, hysteresis, and stability. A view-layer animation that disguised
/// jitter would hide a real bug and add latency.
///
/// Shows the target as well as the gap, so the user can solve the framing themselves
/// rather than following corrections one at a time.
struct GuidanceOverlayView: View {
    let guidance: GuidanceState

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack(alignment: .topLeading) {
                ForEach(
                    Array(guidance.overlay.avoidRegions.enumerated()),
                    id: \.offset
                ) { _, region in
                    rectangle(region, in: size)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.red.opacity(0.7))
                }

                if let current = guidance.overlay.currentSubjectBounds {
                    rectangle(current, in: size)
                        .stroke(lineWidth: 1)
                        .foregroundStyle(.white.opacity(0.45))
                }

                // The target is drawn more strongly than the current bounds: it is
                // where the user is going, not where they already are.
                if let target = guidance.overlay.targetSubjectBounds {
                    rectangle(target, in: size)
                        .stroke(lineWidth: 2)
                        .foregroundStyle(.yellow)
                }

                if let y = guidance.overlay.currentHorizonY {
                    horizon(at: y, in: size, dashed: false)
                        .foregroundStyle(.white.opacity(0.45))
                }
                if let y = guidance.overlay.targetHorizonY {
                    horizon(at: y, in: size, dashed: true)
                        .foregroundStyle(.yellow)
                }
            }
            // Contrast cannot come from colour alone over unpredictable live imagery.
            .shadow(color: .black.opacity(0.6), radius: 1)
        }
        .allowsHitTesting(false)
    }

    private func rectangle(_ rect: NormalizedRect, in size: CGSize) -> Path {
        Path(CGRect(
            x: rect.x * size.width,
            y: rect.y * size.height,
            width: rect.width * size.width,
            height: rect.height * size.height
        ))
    }

    private func horizon(at y: Double, in size: CGSize, dashed: Bool) -> some Shape {
        HorizonLine(y: y * size.height, dashed: dashed)
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
