import AVFoundation
import Foundation

/// Whether the user has allowed camera access.
///
/// Mirrors `AVAuthorizationStatus` without exposing it, so the capture lifecycle can
/// be driven from a test without a camera, a device, or a real permission prompt.
public enum CameraAuthorizationStatus: Sendable, Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

/// The camera permission boundary.
///
/// A seam rather than an abstraction for its own sake: permission is the one part of
/// starting the camera that a machine with no camera can still exercise, and every
/// interesting lifecycle race — stopping mid-prompt, backgrounding mid-prompt, two
/// concurrent starts — happens while a prompt is outstanding.
public protocol CameraAuthorization: Sendable {
    /// The current decision, read without prompting.
    var status: CameraAuthorizationStatus { get }

    /// Prompts the user once and reports whether access was granted.
    ///
    /// Only called when `status` is `.notDetermined`. The system prompts once per
    /// install, so a second call resolves immediately with the earlier answer.
    func requestAccess() async -> Bool
}

/// The real permission boundary, backed by AVFoundation.
public struct SystemCameraAuthorization: CameraAuthorization {
    public init() {}

    public var status: CameraAuthorizationStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        // Treated as denied rather than trusted: a status this build does not
        // recognise must not be read as permission to open the camera.
        @unknown default: .denied
        }
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

extension CameraAuthorizationStatus {
    /// The error a start attempt should fail with, or `nil` when it may proceed.
    var blockingError: CaptureError? {
        switch self {
        case .authorized, .notDetermined: nil
        case .denied: .permissionDenied
        case .restricted: .permissionRestricted
        }
    }
}
