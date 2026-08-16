import Foundation

/// A failure from the phone-camera capture boundary.
public enum CaptureError: Error, Sendable, Equatable {
    case permissionDenied
    case permissionRestricted
    case cameraUnavailable
    case sessionPresetUnavailable
    case videoPixelFormatUnavailable
    case deviceInputCreationFailed
    case deviceInputUnavailable
    case videoOutputUnavailable
    case videoConnectionUnavailable
    case sessionFailedToStart
    case runtimeFailure

    /// A concise action the UI can offer when the user can recover.
    public var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            "Allow camera access in Settings."
        case .permissionRestricted:
            "Camera access is restricted on this device."
        case .cameraUnavailable:
            "Connect or enable a camera, then try again."
        case .sessionPresetUnavailable:
            "The selected camera cannot provide the required video format."
        case .videoPixelFormatUnavailable:
            "The selected camera cannot provide a supported analysis format."
        case .deviceInputCreationFailed,
             .deviceInputUnavailable,
             .videoOutputUnavailable,
             .videoConnectionUnavailable,
             .sessionFailedToStart,
             .runtimeFailure:
            "Stop other camera apps and try again."
        }
    }
}

/// Why an otherwise configured capture session is temporarily unavailable.
public enum CaptureInterruption: Sendable, Equatable {
    case anotherClient
    case multipleForegroundApps
    case systemPressure
    case background
    case unknown
}

/// User-visible lifecycle state for native phone capture.
public enum CaptureStatus: Sendable, Equatable {
    case idle
    case awaitingPermission
    case configuring
    case running
    case interrupted(CaptureInterruption)
    case failed(CaptureError)
}
