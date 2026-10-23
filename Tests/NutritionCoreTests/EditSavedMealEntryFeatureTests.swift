import Foundation
import NutritionCore
import XCTest

/// Ticket #7: a person reopens a saved meal entry, changes its reviewed foods or portions, and saves a
/// recalculated nutrition estimate while the meal photos, uncertainty notes and source references are kept.
final class EditSavedMealEntryFeatureTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var gateway: FakeMealAnalysisGateway!
    private let mealTime = Date(timeIntervalSince1970: 1_792_000_000)
    private let editTime = Date(timeIntervalSince1970: 1_792_090_000)

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        gateway = FakeMealAnalysisGateway()
        gateway.foodSearchResults["rice"] = [ChooseSourceBackedFoodFeatureTests.cookedWhiteRice]
        gateway.foodSearchResults["brown rice"] = [ChooseSourceBackedFoodFeatureTests.cookedBrownRice]
    }

    override func tearDown() {
        directory.remove()
    }

    func test_changedPortionIsSavedOverTheSameMealEntryWithARecalculatedEstimate() async throws {
        let id = try await saveRiceMealEntry(grams: 150)

        let editing = try launchApp(now: editTime)
        try editing.editMealEntry(id: id)
        let riceID = try XCTUnwrap(editing.draftReview?.foods.first?.id)
        try editing.changePortion(of: riceID, grams: 200)

        let review = try XCTUnwrap(editing.draftReview)
        XCTAssertEqual(review.foods.map(\.portion), ["200 g"])
        // 200 g of rice: 260 kcal, 5.38 g protein, 56.34 g carbohydrates, 0.56 g fat.
        XCTAssertEqual(review.nutritionEstimate.calories, "260 kcal")
        XCTAssertEqual(review.nutritionEstimate.protein, "5.4 g")
        XCTAssertEqual(review.nutritionEstimate.carbohydrates, "56.3 g")
        XCTAssertEqual(review.nutritionEstimate.fat, "0.6 g")

        XCTAssertEqual(try editing.saveMealEntry(), id)

        let relaunched = try launchApp()
        let reopened = try relaunched.openMealEntry(id: id)
        XCTAssertEqual(reopened.date, mealTime)
        XCTAssertEqual(reopened.foods.map(\.portion), ["200 g"])
        XCTAssertEqual(reopened.nutritionEstimate.calories, "260 kcal")
        XCTAssertEqual(reopened.nutritionEstimate.carbohydrates, "56.3 g")
        let history = try relaunched.mealHistory()
        XCTAssertEqual(history.map(\.id), [id])
        XCTAssertEqual(history.map(\.date), [mealTime])
        XCTAssertEqual(history.map(\.nutritionEstimate.calories), ["260 kcal"])
    }

    func test_removedAndAddedFoodsReplaceTheEstimateRatherThanAddingToThePriorTotal() async throws {
        let first = try launchApp()
        first.startNewMealEntry()
        let rice = try await first.searchFoods(matching: "rice")
        try first.addFood(try XCTUnwrap(rice.results.first), grams: 150)
        let sauceID = try first.addCustomFood(Self.jollofSauce, grams: 120)
        XCTAssertEqual(first.draftReview?.nutritionEstimate.calories, "291 kcal")
        let id = try first.saveMealEntry()

        let editing = try launchApp(now: editTime)
        try editing.editMealEntry(id: id)
        try editing.removeFood(sauceID)
        let brownRice = try await editing.searchFoods(matching: "brown rice")
        try editing.addFood(try XCTUnwrap(brownRice.results.first), grams: 100)
        try editing.addCustomFood(Self.friedPlantain, grams: 80)

        // White rice 150 g (195 kcal, 4.035 g, 42.255 g, 0.42 g) + brown rice 100 g (123 kcal, 2.74 g,
        // 25.58 g, 0.97 g) + plantain 80 g (120 kcal, 1.04 g, 25.6 g, 2.4 g); the removed sauce is gone.
        let review = try XCTUnwrap(editing.draftReview)
        XCTAssertEqual(
            review.foods.map(\.name),
            ["Rice, white, long-grain, cooked", "Rice, brown, cooked", "Fried plantain"]
        )
        assertShowsEditedEstimate(review.nutritionEstimate)
        XCTAssertEqual(try editing.saveMealEntry(), id)

        let relaunched = try launchApp()
        let reopened = try relaunched.openMealEntry(id: id)
        XCTAssertEqual(
            reopened.foods.map(\.name),
            ["Rice, white, long-grain, cooked", "Rice, brown, cooked", "Fried plantain"]
        )
        XCTAssertEqual(reopened.foods.map(\.sourceName), ["USDA FoodData Central", "USDA FoodData Central", "Custom food"])
        XCTAssertEqual(reopened.foods.map(\.sourceRecordID), ["168878", "169704", nil])
        XCTAssertEqual(reopened.foods.map(\.portion), ["150 g", "100 g", "80 g"])
        assertShowsEditedEstimate(reopened.nutritionEstimate)
        let history = try relaunched.mealHistory()
        XCTAssertEqual(history.map(\.id), [id])
        XCTAssertEqual(history.first?.foodNames, ["Rice, white, long-grain, cooked", "Rice, brown, cooked", "Fried plantain"])
        XCTAssertEqual(history.first?.nutritionEstimate.calories, "438 kcal")
    }

    func test_editedMealEntryKeepsItsPhotosPhotoLinksUncertaintyAndSourcesAfterRelaunch() throws {
        let overheadPhoto = MealPhoto(fileExtension: "jpg")
        let sidePhoto = MealPhoto(fileExtension: "heic")
        let rice = ReviewedFood(
            food: ChooseSourceBackedFoodFeatureTests.cookedWhiteRice,
            portion: Portion(grams: 150),
            uncertaintyNotes: [UncertaintyNote(detail: "Cooked with oil or plain?")],
            photoIDs: [overheadPhoto.id, sidePhoto.id]
        )
        let sauce = ReviewedFood(
            food: Food(Self.jollofSauce),
            portion: Portion(grams: 120),
            uncertaintyNotes: [UncertaintyNote(detail: "Portion is hard to judge from the photo.")],
            photoIDs: [overheadPhoto.id]
        )
        let saved = MealEntry(date: mealTime, photos: [overheadPhoto, sidePhoto], reviewedFoods: [rice, sauce])
        try FileMealHistoryStore(directory: directory.url).save(
            saved, photoData: [overheadPhoto.id: Data("overhead".utf8), sidePhoto.id: Data("side".utf8)]
        )

        let editing = try launchApp(now: editTime)
        try editing.editMealEntry(id: saved.id)
        let opened = try XCTUnwrap(editing.draftReview)
        XCTAssertEqual(opened.id, saved.id)
        XCTAssertEqual(opened.photos.map(\.label), ["Photo 1", "Photo 2"])
        XCTAssertEqual(opened.photos.map(\.imageData), [Data("overhead".utf8), Data("side".utf8)])
        XCTAssertEqual(opened.foods.map(\.shownIn), ["Photos 1 and 2", "Photo 1"])

        try editing.changePortion(of: rice.id, grams: 200)
        let dessertPhotoID = editing.importPhoto(Data("dessert".utf8), fileExtension: "png")
        try editing.addCustomFood(Self.friedPlantain, grams: 80, shownIn: [dessertPhotoID])
        try editing.saveMealEntry()

        let reopened = try launchApp().openMealEntry(id: saved.id)
        XCTAssertEqual(reopened.date, mealTime)
        XCTAssertEqual(reopened.photos.map(\.label), ["Photo 1", "Photo 2", "Photo 3"])
        XCTAssertEqual(
            reopened.photos.map(\.imageData),
            [Data("overhead".utf8), Data("side".utf8), Data("dessert".utf8)]
        )
        XCTAssertEqual(reopened.foods.map(\.name), ["Rice, white, long-grain, cooked", "Jollof sauce", "Fried plantain"])
        XCTAssertEqual(reopened.foods.map(\.portion), ["200 g", "120 g", "80 g"])
        XCTAssertEqual(reopened.foods.map(\.shownIn), ["Photos 1 and 2", "Photo 1", "Photo 3"])
        XCTAssertEqual(reopened.foods.map(\.sourceName), ["USDA FoodData Central", "Custom food", "Custom food"])
        XCTAssertEqual(reopened.foods.map(\.sourceRecordID), ["168878", nil, nil])
        XCTAssertEqual(
            reopened.foods.map(\.uncertaintyNotes),
            [["Cooked with oil or plain?"], ["Portion is hard to judge from the photo."], []]
        )
        // Rice 200 g (260 kcal, 5.38 g, 56.34 g, 0.56 g) + sauce 120 g (96 kcal, 1.8 g, 10.8 g, 5.04 g)
        // + plantain 80 g (120 kcal, 1.04 g, 25.6 g, 2.4 g).
        XCTAssertEqual(reopened.nutritionEstimate.calories, "476 kcal")
        XCTAssertEqual(reopened.nutritionEstimate.protein, "8.2 g")
        XCTAssertEqual(reopened.nutritionEstimate.carbohydrates, "92.7 g")
        XCTAssertEqual(reopened.nutritionEstimate.fat, "8 g")
    }

    func test_changedPortionNeedsAPositiveGramAmountAndUnsavedEditsLeaveTheSavedEntryAsItWas() async throws {
        let id = try await saveRiceMealEntry(grams: 150)
        let editing = try launchApp(now: editTime)

        XCTAssertThrowsError(try editing.editMealEntry(id: UUID())) { error in
            XCTAssertTrue(error is MealEntryWorkflowError)
        }

        try editing.editMealEntry(id: id)
        let riceID = try XCTUnwrap(editing.draftReview?.foods.first?.id)
        for grams in [0, -50, Double.nan] {
            XCTAssertThrowsError(try editing.changePortion(of: riceID, grams: grams)) { error in
                XCTAssertEqual(error as? MealEntryWorkflowError, .invalidGramAmount)
            }
        }
        XCTAssertEqual(editing.draftReview?.foods.map(\.portion), ["150 g"])

        try editing.removeFood(riceID)
        XCTAssertEqual(editing.draftReview?.nutritionEstimate.calories, "0 kcal")
        editing.startNewMealEntry()

        XCTAssertEqual(try launchApp().openMealEntry(id: id).foods.map(\.portion), ["150 g"])
        XCTAssertEqual(try launchApp().mealHistory().map(\.nutritionEstimate.calories), ["195 kcal"])
    }

    // MARK: Helpers

    private func assertShowsEditedEstimate(
        _ estimate: PresentedNutritionEstimate,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(estimate.label, "Approximate nutrition estimate", file: file, line: line)
        XCTAssertEqual(estimate.calories, "438 kcal", file: file, line: line)
        XCTAssertEqual(estimate.protein, "7.8 g", file: file, line: line)
        XCTAssertEqual(estimate.carbohydrates, "93.4 g", file: file, line: line)
        XCTAssertEqual(estimate.fat, "3.8 g", file: file, line: line)
    }

    static let jollofSauce = CustomFood(
        name: "Jollof sauce",
        nutrientsPer100g: NutrientsPer100g(calories: 80, protein: 1.5, carbohydrates: 9, fat: 4.2)
    )

    static let friedPlantain = CustomFood(
        name: "Fried plantain",
        nutrientsPer100g: NutrientsPer100g(calories: 150, protein: 1.3, carbohydrates: 32, fat: 3)
    )

    private func launchApp(now: Date? = nil) throws -> MealEntryWorkflow {
        let time = now ?? mealTime
        return MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url), gateway: gateway, now: { time }
        )
    }

    private func saveRiceMealEntry(grams: Double) async throws -> MealEntry.ID {
        let workflow = try launchApp()
        workflow.startNewMealEntry()
        let rice = try await workflow.searchFoods(matching: "rice")
        try workflow.addFood(try XCTUnwrap(rice.results.first), grams: grams)
        return try workflow.saveMealEntry()
    }
}
