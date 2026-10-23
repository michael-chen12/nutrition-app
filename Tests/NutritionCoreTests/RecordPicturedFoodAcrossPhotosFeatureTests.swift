import Foundation
import NutritionCore
import XCTest

/// Ticket #3: a person adds several meal photos to one meal entry (different angles and additional dishes),
/// reviews one list of all pictured food, and counts each food once even when several photos show it.
/// Shared food and leftovers stay included; totals follow the reviewed foods, not the number of photos.
final class RecordPicturedFoodAcrossPhotosFeatureTests: XCTestCase {
    private var directory: TemporaryDirectory!

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
    }

    override func tearDown() {
        directory.remove()
    }

    private let pasta = CustomFood(
        name: "Pasta with tomato sauce",
        nutrientsPer100g: NutrientsPer100g(calories: 160, protein: 5.8, carbohydrates: 31, fat: 0.9)
    )
    private let salad = CustomFood(
        name: "Garden salad",
        nutrientsPer100g: NutrientsPer100g(calories: 20, protein: 1.2, carbohydrates: 3.6, fat: 0.2)
    )
    private let sharedBread = CustomFood(
        name: "Shared bread basket",
        nutrientsPer100g: NutrientsPer100g(calories: 265, protein: 9, carbohydrates: 49, fat: 3.2)
    )

    func test_repeatedViewsCountOnceAndDistinctDishesCountSeparatelyInTheSavedEstimate() throws {
        let mealTime = Date(timeIntervalSince1970: 1_792_100_000)
        let pastaFromAbove = Data([0x01, 0x01])
        let pastaFromTheSide = Data([0x02, 0x02])
        let saladDish = Data([0x03, 0x03])

        let firstLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url),
            gateway: FakeMealAnalysisGateway(),
            now: { mealTime }
        )
        firstLaunch.startNewMealEntry()
        let abovePhoto = firstLaunch.importPhoto(pastaFromAbove, fileExtension: "jpg")
        let sidePhoto = firstLaunch.importPhoto(pastaFromTheSide, fileExtension: "jpg")
        let saladPhoto = firstLaunch.importPhoto(saladDish, fileExtension: "heic")

        let pastaFood = try firstLaunch.addCustomFood(pasta, grams: 250, shownIn: [abovePhoto])
        try firstLaunch.markFood(pastaFood, asAlsoShownIn: sidePhoto)
        try firstLaunch.addCustomFood(salad, grams: 150, shownIn: [saladPhoto])
        try firstLaunch.addCustomFood(sharedBread, grams: 80, shownIn: [abovePhoto])

        let review = try XCTUnwrap(firstLaunch.draftReview)
        XCTAssertEqual(review.photos.map(\.imageData), [pastaFromAbove, pastaFromTheSide, saladDish])
        XCTAssertEqual(review.photos.map(\.label), ["Photo 1", "Photo 2", "Photo 3"])
        assertShowsOnePastaOneSaladAndSharedBread(review)

        try firstLaunch.saveMealEntry()

        let secondLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url),
            gateway: FakeMealAnalysisGateway()
        )
        let row = try XCTUnwrap(try secondLaunch.mealHistory().first)
        XCTAssertEqual(row.foodNames, ["Pasta with tomato sauce", "Garden salad", "Shared bread basket"])
        XCTAssertEqual(row.nutritionEstimate.calories, "642 kcal")

        let reopened = try secondLaunch.openMealEntry(id: row.id)
        XCTAssertEqual(reopened.photos.map(\.imageData), [pastaFromAbove, pastaFromTheSide, saladDish])
        assertShowsOnePastaOneSaladAndSharedBread(reopened)
    }

    func test_foodEnteredOnceForEachAngleCanBeCombinedIntoOneFood() throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: FakeMealAnalysisGateway())
        workflow.startNewMealEntry()
        let abovePhoto = workflow.importPhoto(Data([0x01]), fileExtension: "jpg")
        let sidePhoto = workflow.importPhoto(Data([0x02]), fileExtension: "jpg")
        let pastaFromAbove = try workflow.addCustomFood(pasta, grams: 250, shownIn: [abovePhoto])
        let pastaFromTheSide = try workflow.addCustomFood(pasta, grams: 250, shownIn: [sidePhoto])
        XCTAssertEqual(workflow.draftReview?.nutritionEstimate.calories, "800 kcal", "Two separate foods so far")

        try workflow.combineFood(pastaFromTheSide, into: pastaFromAbove)

        let review = try XCTUnwrap(workflow.draftReview)
        XCTAssertEqual(review.foods.map(\.name), ["Pasta with tomato sauce"])
        XCTAssertEqual(review.foods.map(\.portion), ["250 g"])
        XCTAssertEqual(review.foods.map(\.shownIn), ["Photos 1 and 2"])
        XCTAssertEqual(review.nutritionEstimate.calories, "400 kcal")

        let saved = try workflow.saveMealEntry()
        XCTAssertEqual(try workflow.openMealEntry(id: saved).foods.map(\.shownIn), ["Photos 1 and 2"])
    }

    func test_reviewExplainsThatAllPicturedFoodIncludingSharedFoodAndLeftoversCounts() throws {
        let explanation = "This estimate covers all pictured food, including food that was shared or left uneaten. "
            + "Food seen in more than one photo counts once."
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: FakeMealAnalysisGateway())
        workflow.startNewMealEntry()
        workflow.importPhoto(Data([0x01]), fileExtension: "jpg")

        XCTAssertEqual(workflow.draftReview?.picturedFoodNote, explanation)

        let saved = try workflow.saveMealEntry()
        XCTAssertEqual(try workflow.openMealEntry(id: saved).picturedFoodNote, explanation)
    }

    func test_foodCanOnlyBeNotedInPhotosOfThisMealEntry() throws {
        let workflow = MealEntryWorkflow(store: InMemoryMealHistoryStore(), gateway: FakeMealAnalysisGateway())
        workflow.startNewMealEntry()
        let discardedPhoto = workflow.importPhoto(Data([0x09]), fileExtension: "jpg")
        workflow.startNewMealEntry()
        let photo = workflow.importPhoto(Data([0x01]), fileExtension: "jpg")
        let saladFood = try workflow.addCustomFood(salad, grams: 100, shownIn: [photo])

        XCTAssertThrowsError(try workflow.addCustomFood(pasta, grams: 250, shownIn: [discardedPhoto])) { error in
            XCTAssertEqual(error as? MealEntryWorkflowError, .photoNotInMealEntry(discardedPhoto))
        }
        XCTAssertThrowsError(try workflow.markFood(saladFood, asAlsoShownIn: discardedPhoto)) { error in
            XCTAssertEqual(error as? MealEntryWorkflowError, .photoNotInMealEntry(discardedPhoto))
        }
        XCTAssertEqual(workflow.draftReview?.foods.map(\.name), ["Garden salad"])
        XCTAssertEqual(workflow.draftReview?.foods.map(\.shownIn), ["Photo 1"])
    }

    /// Pasta 250 g (400 kcal, 14.5 P, 77.5 C, 2.25 F) seen in photos 1 and 2 counts once;
    /// salad 150 g (30 kcal, 1.8 P, 5.4 C, 0.3 F) from photo 3; shared bread 80 g (212 kcal, 7.2 P, 39.2 C, 2.56 F).
    private func assertShowsOnePastaOneSaladAndSharedBread(
        _ entry: MealEntryPresentation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            entry.foods.map(\.name),
            ["Pasta with tomato sauce", "Garden salad", "Shared bread basket"],
            file: file, line: line
        )
        XCTAssertEqual(entry.foods.map(\.shownIn), ["Photos 1 and 2", "Photo 3", "Photo 1"], file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.label, "Approximate nutrition estimate", file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.calories, "642 kcal", file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.protein, "23.5 g", file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.carbohydrates, "122.1 g", file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.fat, "5.1 g", file: file, line: line)
    }
}
