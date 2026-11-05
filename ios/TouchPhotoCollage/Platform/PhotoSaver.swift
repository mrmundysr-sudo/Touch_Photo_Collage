import Foundation
import Photos

/// Saves a finished image file to the user's photo library. Only *add* access is requested, so the app can never read
/// the library; photo selection goes through the out-of-process system picker and needs no permission at all.
enum PhotoSaver {
    enum Access { case allowed, denied, notDetermined }

    static func currentAccess() -> Access {
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited: return .allowed
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    static func save(fileURL: URL) async throws {
        // lets the UI tests (and screenshots) exercise the "access denied" explanation deterministically
        if UITestSupport.args.contains("-UITestPhotosDenied") { throw ExportError.photosDenied }
        if currentAccess() != .allowed {
            guard await requestAccess() else { throw ExportError.photosDenied }
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: fileURL, options: options)
            }
        } catch {
            throw ExportError.photosUnavailable("Couldn't save to Photos: \(error.localizedDescription)")
        }
    }
}
