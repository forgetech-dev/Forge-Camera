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
    @State private var pinchStartZoomFactor: Double?

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
                targetFrame: model.directorTargetFrame,
                previewMirrored: false
            )
            .ignoresSafeArea()

            VStack {
                statusBar
                directorAdvice
                Spacer()
                bottomControls
            }
            .padding()
        }
        .simultaneousGesture(zoomGesture)
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

            Label(directorStatusText, systemImage: directorStatusSymbol)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())

            directorPlanButton
        }
    }

    private var directorPlanButton: some View {
        Button {
            model.requestDirectorPlan()
        } label: {
            Group {
                if model.directorStatus == .analyzing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: model.directorPlan == nil ? "lightbulb" : "lightbulb.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Circle())
        .disabled(!model.canRequestDirectorPlan)
        .opacity(model.canRequestDirectorPlan || model.directorStatus == .analyzing ? 1 : 0.45)
        .accessibilityLabel("Analyze composition")
        .accessibilityHint("Sends one camera frame to the connected Mac for a composition plan")
    }

    @ViewBuilder
    private var zoomControl: some View {
        if let zoomState = model.zoomState {
            Button {
                model.resetZoom()
            } label: {
                Text("\(zoomState.factor, specifier: "%.1f")×")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .background(.regularMaterial, in: Capsule())
            .accessibilityLabel("Camera zoom")
            .accessibilityValue("\(zoomState.factor, specifier: "%.1f") times")
            .accessibilityHint("Pinch the viewfinder to zoom, or tap to return to one times")
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            zoomControl

            if model.isPhonePhotoCaptureAvailable {
                photoCaptureFeedback
                shutterButton
            }
        }
    }

    private var shutterButton: some View {
        Button {
            model.capturePhoto()
        } label: {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 76, height: 76)

                Circle()
                    .fill(.white)
                    .frame(width: 64, height: 64)
                    .scaleEffect(model.photoCaptureStatus == .capturing ? 0.86 : 1)

                if model.photoCaptureStatus == .capturing {
                    ProgressView()
                        .tint(.black)
                }
            }
            .frame(width: 80, height: 80)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canCapturePhoto)
        .opacity(model.canCapturePhoto || model.photoCaptureStatus == .capturing ? 1 : 0.5)
        .animation(.easeOut(duration: 0.12), value: model.photoCaptureStatus)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.captureFeedbackCount)
        .accessibilityLabel("Take photo")
        .accessibilityHint("Captures with the iPhone camera and saves to Photos")
    }

    @ViewBuilder
    private var photoCaptureFeedback: some View {
        switch model.photoCaptureStatus {
        case .idle, .capturing:
            EmptyView()
        case .saved:
            Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .accessibilityAddTraits(.isStaticText)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard let currentFactor = model.zoomState?.factor else { return }
                let startFactor = pinchStartZoomFactor ?? currentFactor
                if pinchStartZoomFactor == nil {
                    pinchStartZoomFactor = currentFactor
                }
                model.setZoomFactor(startFactor * Double(value.magnification))
            }
            .onEnded { _ in
                pinchStartZoomFactor = nil
            }
    }

    @ViewBuilder
    private var directorAdvice: some View {
        let advice = Array((model.directorPlan?.displayAdvice ?? []).prefix(2))
        if !advice.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.callout.weight(.semibold))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(advice.enumerated()), id: \.offset) { _, suggestion in
                        Text(suggestion)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Composition advice")
            .accessibilityValue(advice.joined(separator: ". "))
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

    private var directorStatusText: String {
        switch model.directorStatus {
        case .disabled: "Mac disabled"
        case .checking: "Checking Mac"
        case .connected: "Mac connected"
        case .analyzing: "AI analyzing"
        case .planReceived: "Plan received"
        case .planFailed: "Plan failed"
        case .unavailable: "Mac unavailable"
        }
    }

    private var directorStatusSymbol: String {
        switch model.directorStatus {
        case .disabled: "desktopcomputer"
        case .checking: "network"
        case .connected: "desktopcomputer"
        case .analyzing: "viewfinder"
        case .planReceived: "checkmark.circle"
        case .planFailed: "xmark.circle"
        case .unavailable: "exclamationmark.triangle"
        }
    }
}
