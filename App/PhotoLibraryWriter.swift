import Foundation
import Photos

enum PhotoLibraryWriteError: Error, Sendable, Equatable {
    case permissionDenied
    case saveFailed

    var userMessage: String {
        switch self {
        case .permissionDenied:
            "Allow photo access in Settings to save photographs."
        case .saveFailed:
            "The photo could not be saved. Try again."
        }
    }
}

/// The system-library boundary stays in the app target; ForgeCapture only captures
/// photo data and does not know where a client chooses to store it.
struct PhotoLibraryWriter: Sendable {
    func save(_ data: Data) async throws {
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            throw PhotoLibraryWriteError.permissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
        } catch {
            throw PhotoLibraryWriteError.saveFailed
        }
    }
}
