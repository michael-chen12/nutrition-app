import Foundation
import NutritionCore
import XCTest

/// Ticket #5: a person corrects a source-backed food's portion using a familiar serving unit or grams and
/// immediately sees the updated nutrition estimate, including after saving and reopening the meal entry.
final class CorrectPortionWithServingUnitsFeatureTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var gateway: FakeMealAnalysisGateway!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        gateway = FakeMealAnalysisGateway()
        gateway.foodSearchResults["rice"] = [Self.cookedWhiteRice]
    }

    override func tearDown() {
        directory.remove()
    }

    func test_correctingAPortionToServingsConvertsThroughTheGramWeightAndRecalculatesKeepingTheSource() async throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: gateway)
        let riceID = try await addWhiteRice(grams: 150, to: workflow)

        try workflow.changePortion(of: riceID, quantity: 1.5, unit: .serving(Self.cup))

        let rice = try XCTUnwrap(workflow.draftReview?.foods.first)
        // 1.5 cups × 158 g per cup = 237 g.
        XCTAssertEqual(rice.portion, "1.5 cup (237 g)")
        XCTAssertEqual(rice.sourceName, "USDA FoodData Central")
        XCTAssertEqual(rice.sourceRecordID, "168878")
        // 130 kcal, 2.69 g protein, 28.17 g carbohydrates, 0.28 g fat per 100 g, for 237 g.
        let estimate = try XCTUnwrap(workflow.draftReview?.nutritionEstimate)
        XCTAssertEqual(estimate.label, "Approximate nutrition estimate")
        XCTAssertEqual(estimate.calories, "308 kcal")
        XCTAssertEqual(estimate.protein, "6.4 g")
        XCTAssertEqual(estimate.carbohydrates, "66.8 g")
        XCTAssertEqual(estimate.fat, "0.7 g")
    }

    func test_reviewedFoodOffersGramsAndEachServingUnitWithItsQuantityBasis() async throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: gateway)
        _ = try await addWhiteRice(grams: 150, to: workflow)

        let rice = try XCTUnwrap(workflow.draftReview?.foods.first)
        XCTAssertEqual(rice.portionUnits.map(\.name), ["g", "cup", "scoop"])
        XCTAssertEqual(rice.portionUnits.map(\.quantityBasis), [nil, "1 cup = 158 g", nil])
        XCTAssertEqual(rice.portionUnits.map(\.unit), [.grams, .serving(Self.cup), .serving(Self.scoop)])
        XCTAssertEqual(rice.selectedPortionUnit, .grams)
        XCTAssertEqual(rice.portionQuantity, 150)
    }

    func test_correctingAPortionInGramsRecalculatesTheEstimate() async throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: gateway)
        let riceID = try await addWhiteRice(grams: 150, to: workflow)
        try workflow.changePortion(of: riceID, quantity: 1, unit: .serving(Self.cup))

        try workflow.changePortion(of: riceID, quantity: 200, unit: .grams)

        let rice = try XCTUnwrap(workflow.draftReview?.foods.first)
        XCTAssertEqual(rice.portion, "200 g")
        XCTAssertEqual(rice.selectedPortionUnit, .grams)
        XCTAssertEqual(rice.portionQuantity, 200)
        // 130 kcal, 2.69 g protein, 28.17 g carbohydrates, 0.28 g fat per 100 g, for 200 g.
        let estimate = try XCTUnwrap(workflow.draftReview?.nutritionEstimate)
        XCTAssertEqual(estimate.calories, "260 kcal")
        XCTAssertEqual(estimate.protein, "5.4 g")
        XCTAssertEqual(estimate.carbohydrates, "56.3 g")
        XCTAssertEqual(estimate.fat, "0.6 g")
    }

    func test_servingUnitWithoutAKnownGramWeightIsShownAsUnavailableAndNeverConverted() async throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: gateway)
        let riceID = try await addWhiteRice(grams: 150, to: workflow)

        let units = try XCTUnwrap(workflow.draftReview?.foods.first?.portionUnits)
        XCTAssertEqual(units.map(\.conversionUnavailableNote), [
            nil,
            nil,
            "No gram weight is documented for scoop, so it can't be converted. Enter grams instead.",
        ])

        XCTAssertThrowsError(try workflow.changePortion(of: riceID, quantity: 1, unit: .serving(Self.scoop))) { error in
            XCTAssertEqual(error as? MealEntryWorkflowError, .servingConversionUnavailable(unitName: "scoop"))
        }
        let rice = try XCTUnwrap(workflow.draftReview?.foods.first)
        XCTAssertEqual(rice.portion, "150 g")
        XCTAssertEqual(workflow.draftReview?.nutritionEstimate.calories, "195 kcal")
    }

    func test_chosenServingUnitAndEffectiveGramsSurviveSaveAndRelaunch() async throws {
        let firstLaunch = MealEntryWorkflow(store: try FileMealHistoryStore(directory: directory.url), gateway: gateway)
        let riceID = try await addWhiteRice(grams: 150, to: firstLaunch)
        try firstLaunch.changePortion(of: riceID, quantity: 1.5, unit: .serving(Self.cup))
        let id = try firstLaunch.saveMealEntry()

        let secondLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url), gateway: FakeMealAnalysisGateway()
        )
        let reopened = try secondLaunch.openMealEntry(id: id)
        let rice = try XCTUnwrap(reopened.foods.first)
        XCTAssertEqual(rice.portion, "1.5 cup (237 g)")
        XCTAssertEqual(rice.selectedPortionUnit, .serving(Self.cup))
        XCTAssertEqual(rice.portionQuantity, 1.5)
        XCTAssertEqual(rice.portionUnits.map(\.quantityBasis), [nil, "1 cup = 158 g", nil])
        XCTAssertEqual(rice.sourceRecordID, "168878")
        XCTAssertEqual(reopened.nutritionEstimate.calories, "308 kcal")
        XCTAssertEqual(reopened.nutritionEstimate.carbohydrates, "66.8 g")
        XCTAssertEqual(try secondLaunch.mealHistory().map(\.nutritionEstimate.calories), ["308 kcal"])
    }

    func test_servingQuantityMustBePositiveAndTheUnitMustBeOneOfTheFoods() async throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: gateway)
        let riceID = try await addWhiteRice(grams: 150, to: workflow)

        for quantity in [0, -1, Double.nan] {
            XCTAssertThrowsError(try workflow.changePortion(of: riceID, quantity: quantity, unit: .serving(Self.cup))) {
                XCTAssertEqual($0 as? MealEntryWorkflowError, .invalidServingQuantity)
            }
        }
        let slice = ServingUnit(name: "slice", quantityBasis: 1, gramWeight: 30)
        XCTAssertThrowsError(try workflow.changePortion(of: riceID, quantity: 1, unit: .serving(slice))) {
            XCTAssertEqual($0 as? MealEntryWorkflowError, .servingUnitNotAvailable(unitName: "slice"))
        }
        XCTAssertEqual(workflow.draftReview?.foods.first?.portion, "150 g")
    }

    func test_chosenSearchResultCanBeAddedInAServingUnit() async throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: gateway)
        workflow.startNewMealEntry()
        let search = try await workflow.searchFoods(matching: "rice")
        let result = try XCTUnwrap(search.results.first)
        XCTAssertEqual(result.portionUnits.map(\.name), ["g", "cup", "scoop"])

        let cup = try XCTUnwrap(result.portionUnits.first { $0.name == "cup" })
        try workflow.addFood(result, quantity: 0.5, unit: cup.unit)

        let rice = try XCTUnwrap(workflow.draftReview?.foods.first)
        XCTAssertEqual(rice.portion, "0.5 cup (79 g)")
        XCTAssertEqual(rice.sourceRecordID, "168878")
        // 130 kcal per 100 g, for 79 g.
        XCTAssertEqual(workflow.draftReview?.nutritionEstimate.calories, "103 kcal")
    }

    func test_changingAServingPortionToGramsOnASavedMealEntryDropsTheServingUnit() async throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: gateway)
        let riceID = try await addWhiteRice(grams: 150, to: workflow)
        try workflow.changePortion(of: riceID, quantity: 1.5, unit: .serving(Self.cup))
        let id = try workflow.saveMealEntry()

        try workflow.editMealEntry(id: id)
        try workflow.changePortion(of: riceID, grams: 200)

        let rice = try XCTUnwrap(workflow.draftReview?.foods.first)
        XCTAssertEqual(rice.portion, "200 g")
        XCTAssertEqual(rice.selectedPortionUnit, .grams)
        XCTAssertEqual(workflow.draftReview?.nutritionEstimate.calories, "260 kcal")
    }

    // MARK: Helpers

    private func addWhiteRice(grams: Double, to workflow: MealEntryWorkflow) async throws -> ReviewedFood.ID {
        workflow.startNewMealEntry()
        let search = try await workflow.searchFoods(matching: "rice")
        return try workflow.addFood(try XCTUnwrap(search.results.first), grams: grams)
    }

    // MARK: Known lookup results at the external boundary

    /// 1 cup weighs 158 g in the source record.
    static let cup = ServingUnit(name: "cup", quantityBasis: 1, gramWeight: 158)
    /// The source names this unit but gives no gram weight for it.
    static let scoop = ServingUnit(name: "scoop", quantityBasis: 1, gramWeight: nil)

    /// 130 kcal, 2.69 g protein, 28.17 g carbohydrates, 0.28 g fat per 100 g.
    static let cookedWhiteRice = Food(
        name: "Rice, white, long-grain, cooked",
        nutrientsPer100g: NutrientsPer100g(calories: 130, protein: 2.69, carbohydrates: 28.17, fat: 0.28),
        source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "168878")),
        servingUnits: [cup, scoop]
    )
}
