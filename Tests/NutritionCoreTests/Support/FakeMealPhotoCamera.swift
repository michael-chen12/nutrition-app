import Foundation
import NutritionCore

/// Camera test substitute for feature tests where hardware capture is unavailable.
/// It plays the device's part only: authorization, the access prompt, and handing back photo bytes.
final class FakeMealPhotoCamera: MealPhotoCamera {
    var hasCamera = true
    var authorizationStatus: CameraAuthorizationStatus
    /// What the person answers when the system asks for camera access.
    var grantsAccessWhenAsked = true
    /// Photos the shutter returns, in order. An error is thrown instead when the queue is empty.
    var photosToCapture: [CapturedMealPhoto] = []
    private(set) var accessRequestCount = 0

    struct CaptureFailed: Error {}

    init(authorizationStatus: CameraAuthorizationStatus) {
        self.authorizationStatus = authorizationStatus
    }

    func requestAccess() async -> Bool {
        accessRequestCount += 1
        authorizationStatus = grantsAccessWhenAsked ? .authorized : .denied
        return grantsAccessWhenAsked
    }

    func capturePhoto() async throws -> CapturedMealPhoto {
        guard !photosToCapture.isEmpty else { throw CaptureFailed() }
        return photosToCapture.removeFirst()
    }
}
