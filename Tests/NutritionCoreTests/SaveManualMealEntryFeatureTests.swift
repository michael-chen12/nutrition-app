import Foundation
import NutritionCore
import XCTest

/// Ticket #2: a person imports a meal photo, enters a custom food with known nutrition and grams,
/// sees an approximate nutrition estimate, saves the meal entry, and reopens it from meal history
/// after the app relaunches.
final class SaveManualMealEntryFeatureTests: XCTestCase {
    private var directory: TemporaryDirectory!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
    }

    override func tearDown() {
        directory.remove()
    }

    func test_savedManualMealEntryReopensFromMealHistoryAfterRelaunch() throws {
        let photoBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02, 0x03, 0x04])
        let mealTime = Date(timeIntervalSince1970: 1_792_000_000)

        // First launch: build and save the meal entry.
        let firstLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url),
            gateway: FakeMealAnalysisGateway(),
            now: { mealTime }
        )
        firstLaunch.startNewMealEntry()
        firstLaunch.importPhoto(photoBytes, fileExtension: "jpg")
        try firstLaunch.addCustomFood(
            CustomFood(
                name: "Grandma's dumplings",
                nutrientsPer100g: NutrientsPer100g(calories: 220, protein: 9.5, carbohydrates: 27, fat: 8.2)
            ),
            grams: 180
        )

        let review = try XCTUnwrap(firstLaunch.draftReview)
        XCTAssertEqual(review.photos.map(\.imageData), [photoBytes])
        XCTAssertEqual(review.foods.map(\.name), ["Grandma's dumplings"])
        XCTAssertEqual(review.foods.map(\.portion), ["180 g"])
        XCTAssertEqual(review.foods.map(\.sourceName), ["Custom food"])
        assertShowsDumplingEstimate(review.nutritionEstimate)

        try firstLaunch.saveMealEntry()
        XCTAssertNil(firstLaunch.draftReview, "Saving closes the draft")

        // Relaunch: a fresh store and workflow over the same on-device directory.
        let secondLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url),
            gateway: FakeMealAnalysisGateway(),
            now: Date.init
        )

        let history = try secondLaunch.dailyMealHistory().flatMap(\.mealEntries)
        XCTAssertEqual(history.count, 1)
        let row = try XCTUnwrap(history.first)
        XCTAssertEqual(row.date, mealTime)
        XCTAssertEqual(row.foodNames, ["Grandma's dumplings"])
        XCTAssertEqual(row.nutritionEstimate.calories, "396 kcal")

        let reopened = try secondLaunch.openMealEntry(id: row.id)
        XCTAssertEqual(reopened.date, mealTime)
        XCTAssertEqual(reopened.photos.map(\.imageData), [photoBytes])
        XCTAssertEqual(reopened.foods.map(\.name), ["Grandma's dumplings"])
        XCTAssertEqual(reopened.foods.map(\.portion), ["180 g"])
        XCTAssertEqual(reopened.foods.map(\.sourceName), ["Custom food"])
        assertShowsDumplingEstimate(reopened.nutritionEstimate)
    }

    func test_customFoodNeedsAPositiveGramAmount() throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: FakeMealAnalysisGateway())
        workflow.startNewMealEntry()
        let toast = CustomFood(
            name: "Toast",
            nutrientsPer100g: NutrientsPer100g(calories: 290, protein: 9, carbohydrates: 50, fat: 4)
        )

        for grams in [0, -20, Double.nan] {
            XCTAssertThrowsError(try workflow.addCustomFood(toast, grams: grams)) { error in
                XCTAssertEqual(error as? MealEntryWorkflowError, .invalidGramAmount)
            }
        }
        XCTAssertEqual(workflow.draftReview?.foods, [])
    }

    /// 220 kcal, 9.5 g protein, 27 g carbohydrates, 8.2 g fat per 100 g, for 180 g.
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
