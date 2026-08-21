import AVFoundation
import Foundation

public extension AVFoundationFrameSource {
    /// Whether this native phone session currently supports full-quality still capture.
    ///
    /// The value is queried on the session queue because an unavailable photo output
    /// degrades to preview-only capture instead of failing the entire camera session.
    var isPhotoCaptureAvailable: Bool {
        get async {
            await withCheckedContinuation { continuation in
                sessionQueue.async { [self] in
                    continuation.resume(returning: isConfigured && photoOutput.connection(
                        with: .video
                    ) != nil)
                }
            }
        }
    }

    /// Captures one still photograph without interrupting the live video-data output.
    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                guard isConfigured,
                      requestedRunning,
                      session.isRunning,
                      !isApplicationInBackground,
                      photoOutput.connection(with: .video) != nil
                else {
                    continuation.resume(throwing: CaptureError.photoCaptureUnavailable)
                    return
                }
                guard photoCaptureProcessor == nil else {
                    continuation.resume(throwing: CaptureError.photoCaptureInProgress)
                    return
                }

                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .quality
                let processor = PhotoCaptureProcessor { [self] result in
                    sessionQueue.async { [self] in
                        photoCaptureProcessor = nil
                        continuation.resume(with: result)
                    }
                }
                photoCaptureProcessor = processor
                photoOutput.capturePhoto(with: settings, delegate: processor)
            }
        }
    }
}

extension AVFoundationFrameSource {
    /// Adds still capture when the current device supports it. Preview and analysis
    /// remain usable when this optional output cannot be installed.
    func configurePhotoOutput() {
        guard session.canAddOutput(photoOutput) else {
            Self.logger.notice("Still-photo output is unavailable; continuing preview-only")
            return
        }
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .quality
    }
}

/// Owns one AVFoundation photo callback sequence and converts it into one typed result.
/// AVFoundation invokes the callbacks as a serial sequence, and the source retains this
/// processor until the final callback completes.
final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate,
    @unchecked Sendable {
    private let completion: @Sendable (Result<Data, CaptureError>) -> Void
    private var result: Result<Data, CaptureError>?

    init(completion: @escaping @Sendable (Result<Data, CaptureError>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        if error != nil {
            result = .failure(.photoProcessingFailed)
        } else if let data = photo.fileDataRepresentation() {
            result = .success(data)
        } else {
            result = .failure(.photoDataUnavailable)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: (any Error)?
    ) {
        if error != nil {
            completion(.failure(.photoProcessingFailed))
        } else {
            completion(result ?? .failure(.photoDataUnavailable))
        }
    }
}
