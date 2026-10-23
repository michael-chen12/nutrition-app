import Foundation

/// The iPhone camera as the capture flow needs it: whether there is one, whether the person allowed
/// access, asking for access, and taking one photo.
///
/// This is a device adapter, not an external boundary: nothing leaves the iPhone. The app implements it
/// with AVFoundation (`iOSApp/NutritionApp/AVFoundationMealPhotoCamera.swift`); feature tests use a
/// camera test substitute because hardware capture is unavailable to them.
public protocol MealPhotoCamera: AnyObject {
    /// False on devices without a usable camera, such as the iOS Simulator.
    var hasCamera: Bool { get }
    var authorizationStatus: CameraAuthorizationStatus { get }
    /// Shows the system camera-access prompt. Returns whether the person allowed access.
    func requestAccess() async -> Bool
    /// Takes one photo through the live viewfinder.
    func capturePhoto() async throws -> CapturedMealPhoto
}

/// Mirrors the system's camera authorization states.
public enum CameraAuthorizationStatus: Hashable, Sendable {
    /// The person has not been asked yet.
    case notDetermined
    case authorized
    /// The person turned camera access off for this app.
    case denied
    /// Camera access is blocked on this device (for example by Screen Time or device management),
    /// and the person cannot change it for this app.
    case restricted
}

/// A photo just taken with the camera, before the person decides to use it.
public struct CapturedMealPhoto: Hashable, Sendable {
    public var imageData: Data
    /// e.g. "jpg" or "heic"; kept so the meal photo file is stored with the right type.
    public var fileExtension: String

    public init(imageData: Data, fileExtension: String) {
        self.imageData = imageData
        self.fileExtension = fileExtension
    }
}
