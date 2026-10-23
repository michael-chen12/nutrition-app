import Foundation
import NutritionCore
import XCTest

/// Ticket #4: a person searches a documented nutrition source, chooses a food, sees its provenance,
/// enters a gram amount, and saves a meal entry whose nutrient values come from that source record.
final class ChooseSourceBackedFoodFeatureTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var gateway: FakeMealAnalysisGateway!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        gateway = FakeMealAnalysisGateway()
        gateway.foodSearchResults["rice"] = [Self.cookedWhiteRice, Self.cookedBrownRice]
    }

    override func tearDown() {
        directory.remove()
    }

    func test_searchShowsEachDocumentedResultWithItsSourceNameAndRecordIdentity() async throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: gateway)

        let search = try await workflow.searchFoods(matching: "rice")

        XCTAssertEqual(search.results.map(\.name), ["Rice, white, long-grain, cooked", "Rice, brown, cooked"])
        XCTAssertEqual(search.results.map(\.sourceName), ["USDA FoodData Central", "USDA FoodData Central"])
        XCTAssertEqual(search.results.map(\.sourceRecordID), ["168878", "169704"])
    }

    func test_chosenFoodIsSavedWithItsSourceAndReopensWithTheSameEstimateAfterRelaunch() async throws {
        let mealTime = Date(timeIntervalSince1970: 1_792_000_000)
        let firstLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url), gateway: gateway, now: { mealTime }
        )
        firstLaunch.startNewMealEntry()

        let search = try await firstLaunch.searchFoods(matching: "rice")
        let whiteRice = try XCTUnwrap(search.results.first { $0.name == "Rice, white, long-grain, cooked" })
        try firstLaunch.addFood(whiteRice, grams: 150)

        let review = try XCTUnwrap(firstLaunch.draftReview)
        XCTAssertEqual(review.foods.map(\.name), ["Rice, white, long-grain, cooked"])
        XCTAssertEqual(review.foods.map(\.portion), ["150 g"])
        XCTAssertEqual(review.foods.map(\.sourceName), ["USDA FoodData Central"])
        XCTAssertEqual(review.foods.map(\.sourceRecordID), ["168878"])
        assertShowsWhiteRiceEstimate(review.nutritionEstimate)

        let id = try firstLaunch.saveMealEntry()

        let secondLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url), gateway: FakeMealAnalysisGateway()
        )
        let reopened = try secondLaunch.openMealEntry(id: id)
        XCTAssertEqual(reopened.foods.map(\.name), ["Rice, white, long-grain, cooked"])
        XCTAssertEqual(reopened.foods.map(\.portion), ["150 g"])
        XCTAssertEqual(reopened.foods.map(\.sourceName), ["USDA FoodData Central"])
        XCTAssertEqual(reopened.foods.map(\.sourceRecordID), ["168878"])
        assertShowsWhiteRiceEstimate(reopened.nutritionEstimate)
    }

    func test_whenNoDocumentedFoodMatchesACustomFoodCanBeAddedAlongsideASourceBackedFood() async throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: gateway)
        workflow.startNewMealEntry()

        let noMatch = try await workflow.searchFoods(matching: "jollof sauce")
        XCTAssertEqual(noMatch.results, [])
        XCTAssertEqual(noMatch.noMatchMessage, "No documented food matches \"jollof sauce\". Add it as a custom food.")

        try workflow.addCustomFood(
            CustomFood(
                name: "Jollof sauce",
                nutrientsPer100g: NutrientsPer100g(calories: 80, protein: 1.5, carbohydrates: 9, fat: 4.2)
            ),
            grams: 120
        )
        let rice = try await workflow.searchFoods(matching: "rice")
        XCTAssertNil(rice.noMatchMessage)
        try workflow.addFood(try XCTUnwrap(rice.results.first), grams: 150)

        let review = try XCTUnwrap(workflow.draftReview)
        XCTAssertEqual(review.foods.map(\.sourceName), ["Custom food", "USDA FoodData Central"])
        XCTAssertEqual(review.foods.map(\.sourceRecordID), [nil, "168878"])
        // 120 g sauce (96 kcal, 1.8 g, 10.8 g, 5.04 g) + 150 g rice (195 kcal, 4.035 g, 42.255 g, 0.42 g).
        XCTAssertEqual(review.nutritionEstimate.calories, "291 kcal")
        XCTAssertEqual(review.nutritionEstimate.protein, "5.8 g")
        XCTAssertEqual(review.nutritionEstimate.carbohydrates, "53.1 g")
        XCTAssertEqual(review.nutritionEstimate.fat, "5.5 g")
    }

    func test_chosenFoodNeedsAPositiveGramAmount() async throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: gateway)
        workflow.startNewMealEntry()
        let search = try await workflow.searchFoods(matching: "rice")
        let rice = try XCTUnwrap(search.results.first)

        for grams in [0, -150, Double.infinity] {
            XCTAssertThrowsError(try workflow.addFood(rice, grams: grams)) { error in
                XCTAssertEqual(error as? MealEntryWorkflowError, .invalidGramAmount)
            }
        }
        XCTAssertEqual(workflow.draftReview?.foods, [])
    }

    /// 130 kcal, 2.69 g protein, 28.17 g carbohydrates, 0.28 g fat per 100 g, for 150 g.
    private func assertShowsWhiteRiceEstimate(
        _ estimate: PresentedNutritionEstimate,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(estimate.label, "Approximate nutrition estimate", file: file, line: line)
        XCTAssertEqual(estimate.calories, "195 kcal", file: file, line: line)
        XCTAssertEqual(estimate.protein, "4 g", file: file, line: line)
        XCTAssertEqual(estimate.carbohydrates, "42.3 g", file: file, line: line)
        XCTAssertEqual(estimate.fat, "0.4 g", file: file, line: line)
    }

    // MARK: Known lookup results at the external boundary

    /// 130 kcal, 2.69 g protein, 28.17 g carbohydrates, 0.28 g fat per 100 g.
    static let cookedWhiteRice = Food(
        name: "Rice, white, long-grain, cooked",
        nutrientsPer100g: NutrientsPer100g(calories: 130, protein: 2.69, carbohydrates: 28.17, fat: 0.28),
        source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "168878"))
    )

    static let cookedBrownRice = Food(
        name: "Rice, brown, cooked",
        nutrientsPer100g: NutrientsPer100g(calories: 123, protein: 2.74, carbohydrates: 25.58, fat: 0.97),
        source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "169704"))
    )
}
