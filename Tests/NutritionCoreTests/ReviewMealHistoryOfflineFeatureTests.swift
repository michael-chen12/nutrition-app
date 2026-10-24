import Foundation
import NutritionCore
import XCTest

/// Spec #1, story 30: without a network connection a person still browses meal history by day, reopens a saved
/// meal entry with its photos and sources, and edits it. Food search and photo analysis are unavailable, but
/// nothing else in history needs the external boundary, so the edit saves and the day's total is recalculated.
final class ReviewMealHistoryOfflineFeatureTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var utc: Calendar!
    private let lunchTime = Date(timeIntervalSince1970: 1_792_000_000)
    private let snackTime = Date(timeIntervalSince1970: 1_792_003_600)
    private let photoBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x0A, 0x0B])

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        utc = try DailyPicturedFoodTotalsFeatureTests.gregorianCalendar(timeZoneIdentifier: "UTC")
    }

    override func tearDown() {
        directory.remove()
    }

    func test_offlineThePersonBrowsesReopensAndEditsSavedMealEntriesAndTheDaysTotalIsRecalculated() async throws {
        let lunchID = try await saveLunchAndSnackWhileOnline()

        let offline = OfflineGateway()
        let app = try launchApp(gateway: offline)

        // Browse: the day and its daily pictured-food total come from the iPhone alone.
        // Lunch: rice 150 g (195 kcal) + sauce 120 g (96 kcal); snack: plantain 80 g (120 kcal).
        let day = try XCTUnwrap(try app.dailyMealHistory().first)
        XCTAssertEqual(day.mealEntries.map(\.id).last, lunchID)
        XCTAssertEqual(day.picturedFoodTotal.calories, "411 kcal")

        // Reopen: photos, foods and sources are kept locally.
        let lunch = try app.openMealEntry(id: lunchID)
        XCTAssertEqual(lunch.photos.map(\.imageData), [photoBytes])
        XCTAssertEqual(lunch.foods.map(\.name), ["Rice, white, long-grain, cooked", "Jollof sauce"])
        XCTAssertEqual(lunch.foods.map(\.sourceName), ["USDA FoodData Central", "Custom food"])
        XCTAssertEqual(lunch.foods.map(\.sourceRecordID), ["168878", nil])

        // Edit: search and photo analysis fail clearly and leave the draft as it was.
        try app.editMealEntry(id: lunchID)
        do {
            _ = try await app.searchFoods(matching: "plantain")
            XCTFail("Food search should be unavailable offline")
        } catch {
            XCTAssertEqual(error as? MealAnalysisGatewayError, .foodSearchUnavailable)
        }
        app.acceptPhotoAnalysisDisclosure()
        let analysis = try await app.analyzePhoto(try XCTUnwrap(lunch.photos.first).id)
        XCTAssertEqual(
            analysis.message,
            "Photo analysis isn't available right now. Your photo is still in this meal entry: "
                + "search for foods or add a custom food to finish it."
        )
        XCTAssertEqual(app.draftReview?.foods.map(\.name), ["Rice, white, long-grain, cooked", "Jollof sauce"])

        // ...while portions, removals and custom foods still work.
        let riceID = try XCTUnwrap(lunch.foods.first).id
        let sauceID = try XCTUnwrap(lunch.foods.last).id
        try app.changePortion(of: riceID, grams: 200)
        try app.removeFood(sauceID)
        try app.addCustomFood(EditSavedMealEntryFeatureTests.friedPlantain, grams: 80)
        XCTAssertEqual(try app.saveMealEntry(), lunchID)

        // Rice 200 g (260 kcal, 5.38 g, 56.34 g, 0.56 g) + plantain 80 g (120 kcal, 1.04 g, 25.6 g, 2.4 g).
        let relaunched = try launchApp(gateway: OfflineGateway())
        let edited = try relaunched.openMealEntry(id: lunchID)
        XCTAssertEqual(edited.date, lunchTime)
        XCTAssertEqual(edited.photos.map(\.imageData), [photoBytes])
        XCTAssertEqual(edited.foods.map(\.name), ["Rice, white, long-grain, cooked", "Fried plantain"])
        XCTAssertEqual(edited.foods.map(\.portion), ["200 g", "80 g"])
        XCTAssertEqual(edited.nutritionEstimate.calories, "380 kcal")
        XCTAssertEqual(edited.nutritionEstimate.protein, "6.4 g")
        XCTAssertEqual(edited.nutritionEstimate.carbohydrates, "81.9 g")
        XCTAssertEqual(edited.nutritionEstimate.fat, "3 g")
        let days = try relaunched.dailyMealHistory()
        XCTAssertEqual(days.count, 1)
        // Edited lunch 380 kcal + unchanged snack 120 kcal.
        XCTAssertEqual(days.first?.picturedFoodTotal.calories, "500 kcal")

        // Only the person's own search and analysis attempts reached the boundary.
        XCTAssertEqual(offline.searchQueries, ["plantain"])
        XCTAssertEqual(offline.analysisRequestCount, 1)
    }

    // MARK: Helpers

    /// Saves a lunch (with a meal photo) and a snack on the same day while the boundary answers.
    private func saveLunchAndSnackWhileOnline() async throws -> MealEntry.ID {
        let online = FakeMealAnalysisGateway()
        online.foodSearchResults["rice"] = [ChooseSourceBackedFoodFeatureTests.cookedWhiteRice]

        let lunchApp = try launchApp(gateway: online, now: lunchTime)
        lunchApp.startNewMealEntry()
        let photoID = lunchApp.importPhoto(photoBytes, fileExtension: "jpg")
        let rice = try await lunchApp.searchFoods(matching: "rice")
        try lunchApp.addFood(try XCTUnwrap(rice.results.first), grams: 150, shownIn: [photoID])
        try lunchApp.addCustomFood(EditSavedMealEntryFeatureTests.jollofSauce, grams: 120, shownIn: [photoID])
        let lunchID = try lunchApp.saveMealEntry()

        let snackApp = try launchApp(gateway: online, now: snackTime)
        snackApp.startNewMealEntry()
        try snackApp.addCustomFood(EditSavedMealEntryFeatureTests.friedPlantain, grams: 80)
        try snackApp.saveMealEntry()
        return lunchID
    }

    private func launchApp(gateway: MealAnalysisGateway, now: Date? = nil) throws -> MealEntryWorkflow {
        let time = now ?? lunchTime
        return MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url), gateway: gateway, now: { time }, calendar: utc
        )
    }
}

/// The boundary with no network connection: food search and photo analysis both fail, as
/// `HTTPMealAnalysisGateway` reports an unreachable backend.
private final class OfflineGateway: MealAnalysisGateway {
    private(set) var searchQueries: [String] = []
    private(set) var analysisRequestCount = 0

    func searchFoods(matching query: String) async throws -> [Food] {
        searchQueries.append(query)
        throw MealAnalysisGatewayError.foodSearchUnavailable
    }

    func analyzeMealPhotos(_ request: MealPhotoAnalysisRequest) async throws -> MealPhotoAnalysisResponse {
        analysisRequestCount += 1
        throw MealAnalysisGatewayError.analysisUnavailable
    }
}
