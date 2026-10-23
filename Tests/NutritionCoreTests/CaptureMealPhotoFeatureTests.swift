import Foundation
import NutritionCore
import XCTest

/// Ticket #6: a person takes a meal photo with the camera, reviews it, and uses it in the same manual
/// meal-entry flow as an imported photo. The camera is replaced by a test substitute; the meal entry
/// workflow, nutrient calculation and on-device persistence are real.
final class CaptureMealPhotoFeatureTests: XCTestCase {
    private var directory: TemporaryDirectory!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
    }

    override func tearDown() {
        directory.remove()
    }

    private let mealTime = Date(timeIntervalSince1970: 1_792_000_000)
    private let plateShot = CapturedMealPhoto(imageData: Data([0xFF, 0xD8, 0xFF, 0xE1, 0x0A]), fileExtension: "jpg")
    private let dumplings = CustomFood(
        name: "Grandma's dumplings",
        nutrientsPer100g: NutrientsPer100g(calories: 220, protein: 9.5, carbohydrates: 27, fat: 8.2)
    )

    func test_capturedMealPhotoIsReviewedSavedAndReopenedFromMealHistoryAfterRelaunch() async throws {
        let camera = FakeMealPhotoCamera(authorizationStatus: .authorized)
        camera.photosToCapture = [plateShot]
        let mealEntry = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url),
            gateway: FakeMealAnalysisGateway(),
            now: { self.mealTime }
        )
        mealEntry.startNewMealEntry()
        let capture = MealPhotoCapture(camera: camera, mealEntry: mealEntry)

        await capture.open()
        XCTAssertEqual(capture.step, .viewfinder)

        await capture.takePhoto()
        XCTAssertEqual(capture.step, .reviewing(plateShot))
        XCTAssertEqual(mealEntry.draftReview?.photos, [], "A photo under review is not yet part of the meal entry")

        capture.usePhoto()
        XCTAssertEqual(capture.step, .finished)
        XCTAssertEqual(mealEntry.draftReview?.photos.map(\.imageData), [plateShot.imageData])

        try mealEntry.addCustomFood(dumplings, grams: 180)
        assertShowsDumplingEstimate(try XCTUnwrap(mealEntry.draftReview).nutritionEstimate)
        try mealEntry.saveMealEntry()

        let relaunched = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url),
            gateway: FakeMealAnalysisGateway()
        )
        let row = try XCTUnwrap(try relaunched.dailyMealHistory().flatMap(\.mealEntries).first)
        XCTAssertEqual(row.foodNames, ["Grandma's dumplings"])
        let reopened = try relaunched.openMealEntry(id: row.id)
        XCTAssertEqual(reopened.date, mealTime)
        XCTAssertEqual(reopened.photos.map(\.imageData), [plateShot.imageData])
        XCTAssertEqual(reopened.foods.map(\.portion), ["180 g"])
        assertShowsDumplingEstimate(reopened.nutritionEstimate)
    }

    func test_firstUseAsksForCameraAccessAndOpensTheViewfinderWhenAllowed() async {
        let camera = FakeMealPhotoCamera(authorizationStatus: .notDetermined)
        camera.grantsAccessWhenAsked = true
        let capture = MealPhotoCapture(camera: camera, mealEntry: newMealEntry())

        await capture.open()

        XCTAssertEqual(camera.accessRequestCount, 1, "The system camera-access prompt is shown")
        XCTAssertEqual(capture.step, .viewfinder)
    }

    func test_deniedCameraAccessExplainsHowToAllowItAndOffersThePhotoLibraryInstead() async throws {
        let camera = FakeMealPhotoCamera(authorizationStatus: .denied)
        let mealEntry = newMealEntry()
        let capture = MealPhotoCapture(camera: camera, mealEntry: mealEntry)

        await capture.open()

        XCTAssertEqual(camera.accessRequestCount, 0, "iOS shows the access prompt only once; Settings is the way back")
        guard case .cameraUnavailable(let explanation) = capture.step else {
            return XCTFail("Expected an explanation, got \(capture.step)")
        }
        XCTAssertEqual(explanation.title, "Camera access is off")
        XCTAssertEqual(
            explanation.message,
            "To take a meal photo, allow camera access for this app in Settings. "
                + "You can also import a meal photo from your photo library."
        )
        XCTAssertEqual(explanation.settingsActionTitle, "Open Settings")
        XCTAssertEqual(explanation.photoLibraryActionTitle, "Import from Photo Library")

        capture.choosePhotoLibrary()
        XCTAssertEqual(capture.step, .photoLibraryChosen)

        // The person continues with an imported meal photo instead.
        let libraryPhoto = Data([0x89, 0x50, 0x4E, 0x47])
        mealEntry.importPhoto(libraryPhoto, fileExtension: "png")
        try mealEntry.addCustomFood(dumplings, grams: 180)
        let id = try mealEntry.saveMealEntry()
        XCTAssertEqual(try mealEntry.openMealEntry(id: id).photos.map(\.imageData), [libraryPhoto])
    }

    func test_decliningTheCameraAccessPromptExplainsHowToAllowIt() async {
        let camera = FakeMealPhotoCamera(authorizationStatus: .notDetermined)
        camera.grantsAccessWhenAsked = false
        let capture = MealPhotoCapture(camera: camera, mealEntry: newMealEntry())

        await capture.open()

        XCTAssertEqual(camera.accessRequestCount, 1)
        guard case .cameraUnavailable(let explanation) = capture.step else {
            return XCTFail("Expected an explanation, got \(capture.step)")
        }
        XCTAssertEqual(explanation.title, "Camera access is off")
        XCTAssertEqual(explanation.settingsActionTitle, "Open Settings")
        XCTAssertEqual(explanation.photoLibraryActionTitle, "Import from Photo Library")
    }

    func test_restrictedCameraAccessOffersOnlyThePhotoLibrary() async {
        let camera = FakeMealPhotoCamera(authorizationStatus: .restricted)
        let capture = MealPhotoCapture(camera: camera, mealEntry: newMealEntry())

        await capture.open()

        XCTAssertEqual(camera.accessRequestCount, 0)
        guard case .cameraUnavailable(let explanation) = capture.step else {
            return XCTFail("Expected an explanation, got \(capture.step)")
        }
        XCTAssertEqual(explanation.title, "Camera access is restricted")
        XCTAssertEqual(
            explanation.message,
            "Camera access is restricted on this iPhone, for example by Screen Time, and can't be turned on "
                + "for this app. You can import a meal photo from your photo library instead."
        )
        XCTAssertNil(explanation.settingsActionTitle, "Settings for this app can't lift a restriction")
        XCTAssertEqual(explanation.photoLibraryActionTitle, "Import from Photo Library")
    }

    func test_retakeDiscardsThePhotoUnderReviewAndOnlyTheUsedPhotoJoinsTheMealEntry() async {
        let blurry = CapturedMealPhoto(imageData: Data([0x01, 0x01]), fileExtension: "jpg")
        let camera = FakeMealPhotoCamera(authorizationStatus: .authorized)
        camera.photosToCapture = [blurry, plateShot]
        let mealEntry = newMealEntry()
        let capture = MealPhotoCapture(camera: camera, mealEntry: mealEntry)
        await capture.open()

        await capture.takePhoto()
        XCTAssertEqual(capture.step, .reviewing(blurry))
        capture.retake()
        XCTAssertEqual(capture.step, .viewfinder)
        XCTAssertEqual(mealEntry.draftReview?.photos, [])

        await capture.takePhoto()
        capture.usePhoto()

        XCTAssertEqual(mealEntry.draftReview?.photos.map(\.imageData), [plateShot.imageData])
    }

    func test_aFailedCaptureKeepsTheViewfinderOpenAndAsksThePersonToTryAgain() async {
        let camera = FakeMealPhotoCamera(authorizationStatus: .authorized)
        camera.photosToCapture = []
        let capture = MealPhotoCapture(camera: camera, mealEntry: newMealEntry())
        await capture.open()

        await capture.takePhoto()

        XCTAssertEqual(capture.step, .viewfinder)
        XCTAssertEqual(capture.captureErrorMessage, "The photo couldn't be taken. Please try again.")

        camera.photosToCapture = [plateShot]
        await capture.takePhoto()

        XCTAssertEqual(capture.step, .reviewing(plateShot))
        XCTAssertNil(capture.captureErrorMessage)
    }

    func test_aDeviceWithoutACameraOffersThePhotoLibraryWithoutAskingForAccess() async {
        let camera = FakeMealPhotoCamera(authorizationStatus: .notDetermined)
        camera.hasCamera = false
        let capture = MealPhotoCapture(camera: camera, mealEntry: newMealEntry())

        await capture.open()

        XCTAssertEqual(camera.accessRequestCount, 0)
        guard case .cameraUnavailable(let explanation) = capture.step else {
            return XCTFail("Expected an explanation, got \(capture.step)")
        }
        XCTAssertEqual(explanation.title, "No camera available")
        XCTAssertEqual(
            explanation.message,
            "This device has no camera for taking meal photos. You can import a meal photo from your photo library instead."
        )
        XCTAssertNil(explanation.settingsActionTitle)
        XCTAssertEqual(explanation.photoLibraryActionTitle, "Import from Photo Library")
    }

    private func newMealEntry() -> MealEntryWorkflow {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: FakeMealAnalysisGateway())
        workflow.startNewMealEntry()
        return workflow
    }

    /// 220 kcal, 9.5 g protein, 27 g carbohydrates, 8.2 g fat per 100 g, for 180 g:
    /// the same estimate as the imported-photo path, so capture does not change the calculation.
    private func assertShowsDumplingEstimate(
        _ estimate: PresentedNutritionEstimate,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(estimate.label, "Approximate nutrition estimate", file: file, line: line)
        XCTAssertEqual(estimate.calories, "396 kcal", file: file, line: line)
        XCTAssertEqual(estimate.protein, "17.1 g", file: file, line: line)
        XCTAssertEqual(estimate.carbohydrates, "48.6 g", file: file, line: line)
        XCTAssertEqual(estimate.fat, "14.8 g", file: file, line: line)
    }
}
