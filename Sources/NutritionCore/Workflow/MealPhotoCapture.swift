import Foundation

/// The camera path into a meal entry, as the capture view sees it: open the camera (asking for access
/// when needed), take a photo, review it, then retake or use it. A used photo joins the draft meal entry
/// through the same path as an imported photo, so the meal entry and its nutrition estimate are unchanged
/// by how the photo arrived. When the camera can't be used, the person gets an explanation and the
/// photo library instead.
public final class MealPhotoCapture {
    private let camera: MealPhotoCamera
    private let mealEntry: MealEntryWorkflow

    /// Where the person is in the capture flow.
    public private(set) var step: MealPhotoCaptureStep = .notStarted

    public init(camera: MealPhotoCamera, mealEntry: MealEntryWorkflow) {
        self.camera = camera
        self.mealEntry = mealEntry
    }

    /// Opens the camera, asking for camera access first if the person has not been asked yet.
    public func open() async {
        guard camera.hasCamera else {
            step = .cameraUnavailable(.noCamera)
            return
        }
        var status = camera.authorizationStatus
        if status == .notDetermined {
            status = await camera.requestAccess() ? .authorized : .denied
        }
        switch status {
        case .authorized:
            step = .viewfinder
        case .denied, .notDetermined:
            step = .cameraUnavailable(.accessDenied)
        case .restricted:
            step = .cameraUnavailable(.accessRestricted)
        }
    }

    /// Shown over the viewfinder when the last attempt to take a photo failed; nil otherwise.
    public private(set) var captureErrorMessage: String?

    /// Takes a photo and shows it for review. If the camera fails, the viewfinder stays open with a message.
    public func takePhoto() async {
        guard case .viewfinder = step else { return }
        do {
            step = .reviewing(try await camera.capturePhoto())
            captureErrorMessage = nil
        } catch {
            captureErrorMessage = "The photo couldn't be taken. Please try again."
        }
    }

    /// Discards the photo under review and returns to the viewfinder.
    public func retake() {
        guard case .reviewing = step else { return }
        step = .viewfinder
    }

    /// Adds the photo under review to the draft meal entry, exactly as an imported meal photo.
    public func usePhoto() {
        guard case .reviewing(let photo) = step else { return }
        mealEntry.importPhoto(photo.imageData, fileExtension: photo.fileExtension)
        step = .finished
    }

    /// The person chose to import a meal photo from the photo library instead of using the camera.
    public func choosePhotoLibrary() {
        step = .photoLibraryChosen
    }
}

public enum MealPhotoCaptureStep: Hashable, Sendable {
    case notStarted
    /// The live camera view with a shutter button.
    case viewfinder
    /// The camera can't be used; the explanation is shown with a way to the photo library.
    case cameraUnavailable(CameraUnavailableExplanation)
    /// The captured photo is shown with "Retake" and "Use Photo".
    case reviewing(CapturedMealPhoto)
    /// The photo was added to the draft meal entry; the capture view closes.
    case finished
    /// The capture view closes and the photo library picker opens.
    case photoLibraryChosen
}

/// Why the camera can't be used right now, and what the person can do instead. Views show these strings as-is.
public struct CameraUnavailableExplanation: Hashable, Sendable {
    public var title: String
    public var message: String
    /// Present only when changing a setting would let the person use the camera.
    public var settingsActionTitle: String?
    public var photoLibraryActionTitle: String

    static let accessDenied = CameraUnavailableExplanation(
        title: "Camera access is off",
        message: "To take a meal photo, allow camera access for this app in Settings. "
            + "You can also import a meal photo from your photo library.",
        settingsActionTitle: "Open Settings",
        photoLibraryActionTitle: "Import from Photo Library"
    )

    static let accessRestricted = CameraUnavailableExplanation(
        title: "Camera access is restricted",
        message: "Camera access is restricted on this iPhone, for example by Screen Time, and can't be turned on "
            + "for this app. You can import a meal photo from your photo library instead.",
        settingsActionTitle: nil,
        photoLibraryActionTitle: "Import from Photo Library"
    )

    static let noCamera = CameraUnavailableExplanation(
        title: "No camera available",
        message: "This device has no camera for taking meal photos. "
            + "You can import a meal photo from your photo library instead.",
        settingsActionTitle: nil,
        photoLibraryActionTitle: "Import from Photo Library"
    )
}
