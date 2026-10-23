import Foundation
import NutritionCalibration
import NutritionCore
import XCTest

/// Ticket #12: a developer runs one consented reference meal through the real meal entry workflow. The trial
/// records the pre-review estimate (photo suggestions accepted as offered) separately from the final reviewed
/// estimate, with the reference foods each stage missed and the time the person spent correcting it.
/// Photo analysis and food search are controlled at the external boundary.
final class CalibrationTrialFeatureTests: XCTestCase {
    private var gateway: FakeMealAnalysisGateway!
    private var store: InMemoryMealHistoryStore!
    private var clock: Date!
    private let platePhoto = Data([0xFF, 0xD8, 0x21])

    override func setUp() {
        gateway = FakeMealAnalysisGateway()
        gateway.foodSearchResults["rice white cooked"] = [Self.rice]
        gateway.foodSearchResults["chicken curry"] = [Self.curry]
        store = InMemoryMealHistoryStore()
        clock = Date(timeIntervalSince1970: 1_792_400_000)
    }

    private func makeTrial(_ meal: ReferenceMeal = ReferenceMeals.riceAndCurry) throws -> CalibrationTrial {
        try CalibrationTrial(
            referenceMeal: meal,
            photos: [TrialPhoto(data: platePhoto, fileExtension: "jpg")],
            gateway: gateway,
            store: store,
            now: { self.clock }
        )
    }

    /// Rice suggested at 200 g and curry at 1 cup (240 g by the source's serving weight).
    private func riceAndCurryAnalysis() -> (MealPhotoAnalysisRequest) -> MealPhotoAnalysisResponse {
        { request in
            let photoID = request.photos[0].photoID
            return MealPhotoAnalysisResponse(suggestions: [
                FoodSuggestion(
                    id: "rice", name: "Steamed white rice", searchQuery: "rice white cooked", photoIDs: [photoID],
                    portion: PortionSuggestion(quantity: 200, unit: "g"), matchConfidence: .high
                ),
                FoodSuggestion(
                    id: "curry", name: "Chicken curry", searchQuery: "chicken curry", photoIDs: [photoID],
                    portion: PortionSuggestion(quantity: 1, unit: "cup"), matchConfidence: .high
                ),
            ])
        }
    }

    func test_preReviewAndReviewedEstimatesAreRecordedSeparately() async throws {
        let trial = try makeTrial()
        gateway.photoAnalysisResponder = riceAndCurryAnalysis()
        let analysis = try await trial.analyzePhotos()
        // The person accepts both suggestions, then corrects the rice to 150 g.
        for suggestion in analysis.suggestions {
            try trial.workflow.acceptSuggestion(suggestion.id, as: suggestion.matches[0])
        }
        let riceID = try XCTUnwrap(trial.workflow.draftReview?.foods.first { $0.name == "Rice, white, cooked" }?.id)
        try trial.workflow.changePortion(of: riceID, grams: 150)

        try trial.workflow.saveMealEntry()
        let evaluation = try trial.finish(missedByAnalysis: [], missedAfterReview: [])

        XCTAssertEqual(evaluation.referenceMealID, "pilot-001")
        XCTAssertNil(evaluation.photoAnalysisMessage)
        // Rice 200 g (260 kcal, 5.4 g protein, 56 g carbohydrates, 0.6 g fat) and curry 240 g (360 kcal,
        // 28.8 g protein, 14.4 g carbohydrates, 21.6 g fat).
        assertEqual(evaluation.preReview.nutritionEstimate, calories: 620, protein: 34.2, carbohydrates: 70.4, fat: 22.2)
        // Rice corrected to 150 g (195 kcal, 4.05 g protein, 42 g carbohydrates, 0.45 g fat).
        assertEqual(evaluation.reviewed.nutritionEstimate, calories: 555, protein: 32.85, carbohydrates: 56.4, fat: 22.05)
    }

    func test_correctionTimeRunsFromTheSuggestionsBeingShownToTheReviewedMealEntryBeingSaved() async throws {
        let trial = try makeTrial()
        gateway.photoAnalysisResponder = riceAndCurryAnalysis()
        let analysis = try await trial.analyzePhotos()
        clock += 30
        try trial.workflow.acceptSuggestion(analysis.suggestions[0].id, as: analysis.suggestions[0].matches[0])
        clock += 65
        try trial.workflow.acceptSuggestion(analysis.suggestions[1].id, as: analysis.suggestions[1].matches[0])

        try trial.workflow.saveMealEntry()
        clock += 40 // The developer labels missed foods; not the person's correction time.
        let evaluation = try trial.finish(missedByAnalysis: [], missedAfterReview: [])

        XCTAssertEqual(evaluation.correctionTime, 95)
    }

    func test_aTrialFinishesOnlyOnceThePersonHasSavedTheReviewedMealEntry() async throws {
        let trial = try makeTrial()
        gateway.photoAnalysisResponder = riceAndCurryAnalysis()
        try await trial.analyzePhotos()
        XCTAssertFalse(trial.isMealEntrySaved)

        XCTAssertThrowsError(try trial.finish(missedByAnalysis: [], missedAfterReview: [])) { error in
            XCTAssertEqual(error as? CalibrationTrialError, .mealEntryNotSaved)
        }
        try trial.workflow.saveMealEntry()
        XCTAssertTrue(trial.isMealEntrySaved)
        XCTAssertNoThrow(try trial.finish(missedByAnalysis: ["curry", "rice"], missedAfterReview: ["curry", "rice"]))
    }

    func test_aMealWhoseConsentDoesNotCoverPhotoUploadIsNeverUploaded() throws {
        var meal = ReferenceMeals.riceAndCurry
        meal.consent.coversPhotoAnalysisUpload = false

        XCTAssertThrowsError(try makeTrial(meal)) { error in
            XCTAssertEqual(error as? CalibrationTrialError, .photoUploadNotConsented(referenceMealID: "pilot-001"))
        }
        XCTAssertTrue(gateway.photoAnalysisRequests.isEmpty)
    }

    func test_missedReferenceFoodsAreRecordedForEachStage() async throws {
        let trial = try makeTrial()
        gateway.photoAnalysisResponder = { request in
            MealPhotoAnalysisResponse(suggestions: [FoodSuggestion(
                id: "rice", name: "Steamed white rice", searchQuery: "rice white cooked",
                photoIDs: [request.photos[0].photoID], portion: PortionSuggestion(quantity: 200, unit: "g"),
                matchConfidence: .high
            )])
        }
        let analysis = try await trial.analyzePhotos()
        try trial.workflow.acceptSuggestion(analysis.suggestions[0].id, as: analysis.suggestions[0].matches[0])
        // The person adds the curry the analysis missed.
        let curry = try await trial.workflow.searchFoods(matching: "chicken curry").results[0]
        try trial.workflow.addFood(curry, grams: 250)

        try trial.workflow.saveMealEntry()
        let evaluation = try trial.finish(missedByAnalysis: ["curry"], missedAfterReview: [])

        XCTAssertEqual(evaluation.preReview.missedReferenceFoodIDs, ["curry"])
        XCTAssertEqual(evaluation.reviewed.missedReferenceFoodIDs, [])
    }

    func test_missedFoodsMustBeFoodsOfTheReferenceMeal() async throws {
        let trial = try makeTrial()
        gateway.photoAnalysisResponder = riceAndCurryAnalysis()
        try await trial.analyzePhotos()
        try trial.workflow.saveMealEntry()

        XCTAssertThrowsError(try trial.finish(missedByAnalysis: ["naan"], missedAfterReview: [])) { error in
            XCTAssertEqual(error as? CalibrationTrialError, .unknownReferenceFood("naan"))
        }
        XCTAssertNoThrow(
            try trial.finish(missedByAnalysis: ["curry", "rice"], missedAfterReview: ["curry", "rice"]),
            "the labels can be corrected"
        )
    }

    func test_coverageGapsAreRecorded_suggestionsWithoutAnEstimateAndCustomFoodsInTheReview() async throws {
        let trial = try makeTrial()
        gateway.photoAnalysisResponder = { request in
            let photoID = request.photos[0].photoID
            return MealPhotoAnalysisResponse(suggestions: [
                FoodSuggestion(
                    id: "rice", name: "Steamed white rice", searchQuery: "rice white cooked", photoIDs: [photoID],
                    portion: PortionSuggestion(quantity: 200, unit: "g"), matchConfidence: .high
                ),
                FoodSuggestion(
                    id: "curry", name: "Chettinad chicken", searchQuery: "chettinad chicken", photoIDs: [photoID],
                    portion: PortionSuggestion(quantity: 250, unit: "g"), matchConfidence: .medium
                ),
            ])
        }
        let analysis = try await trial.analyzePhotos()
        try trial.workflow.acceptSuggestion(analysis.suggestions[0].id, as: analysis.suggestions[0].matches[0])
        try trial.workflow.acceptSuggestion(
            analysis.suggestions[1].id,
            asCustomFood: CustomFood(
                name: "Chettinad chicken",
                nutrientsPer100g: NutrientsPer100g(calories: 160, protein: 13, carbohydrates: 5, fat: 10)
            ),
            grams: 250
        )

        try trial.workflow.saveMealEntry()
        let evaluation = try trial.finish(missedByAnalysis: [], missedAfterReview: [])

        // Only the rice adds to the pre-review estimate: 200 g.
        assertEqual(evaluation.preReview.nutritionEstimate, calories: 260, protein: 5.4, carbohydrates: 56, fat: 0.6)
        XCTAssertEqual(evaluation.suggestionsWithoutEstimate, ["Chettinad chicken"])
        XCTAssertEqual(evaluation.customFoodsAfterReview, ["Chettinad chicken"])
    }

    func test_likelyDuplicateViewsCountOnceInThePreReviewEstimate() async throws {
        let trial = try CalibrationTrial(
            referenceMeal: ReferenceMeals.riceAndCurry,
            photos: [
                TrialPhoto(data: platePhoto, fileExtension: "jpg"),
                TrialPhoto(data: Data([0xFF, 0xD8, 0x22]), fileExtension: "jpg"),
            ],
            gateway: gateway,
            store: store,
            now: { self.clock }
        )
        gateway.photoAnalysisResponder = { request in
            MealPhotoAnalysisResponse(
                suggestions: request.photos.enumerated().map { index, photo in
                    FoodSuggestion(
                        id: "rice-\(index)", name: "Steamed white rice", searchQuery: "rice white cooked",
                        photoIDs: [photo.photoID], portion: PortionSuggestion(quantity: 200, unit: "g"),
                        matchConfidence: .high
                    )
                },
                duplicateGroups: [DuplicateGroupHint(suggestionIDs: ["rice-0", "rice-1"], reason: "Same bowl")]
            )
        }
        try await trial.analyzePhotos()
        XCTAssertEqual(gateway.photoAnalysisRequests.map(\.photos.count), [2], "one analysis for both photos")

        try trial.workflow.saveMealEntry()
        let evaluation = try trial.finish(missedByAnalysis: ["curry"], missedAfterReview: ["curry", "rice"])

        assertEqual(evaluation.preReview.nutritionEstimate, calories: 260, protein: 5.4, carbohydrates: 56, fat: 0.6)
        assertEqual(evaluation.reviewed.nutritionEstimate, calories: 0, protein: 0, carbohydrates: 0, fat: 0)
    }

    func test_aFailedAnalysisRecordsAnEmptyPreReviewEstimateAndTheManuallyReviewedMeal() async throws {
        let trial = try makeTrial()
        let analysis = try await trial.analyzePhotos()
        XCTAssertNotNil(analysis.message)
        let rice = try await trial.workflow.searchFoods(matching: "rice white cooked").results[0]
        try trial.workflow.addFood(rice, grams: 180)

        try trial.workflow.saveMealEntry()
        let evaluation = try trial.finish(missedByAnalysis: ["curry", "rice"], missedAfterReview: ["curry"])

        assertEqual(evaluation.preReview.nutritionEstimate, calories: 0, protein: 0, carbohydrates: 0, fat: 0)
        XCTAssertEqual(evaluation.preReview.missedReferenceFoodIDs, ["curry", "rice"])
        XCTAssertEqual(evaluation.photoAnalysisMessage, analysis.message, "an outage is told apart from a model miss")
        assertEqual(evaluation.reviewed.nutritionEstimate, calories: 234, protein: 4.86, carbohydrates: 50.4, fat: 0.54)
    }

    // MARK: Fixtures

    static let rice = Food(
        name: "Rice, white, cooked",
        nutrientsPer100g: NutrientsPer100g(calories: 130, protein: 2.7, carbohydrates: 28, fat: 0.3),
        source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "168878"))
    )
    static let curry = Food(
        name: "Chicken curry",
        nutrientsPer100g: NutrientsPer100g(calories: 150, protein: 12, carbohydrates: 6, fat: 9),
        source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "2341420")),
        servingUnits: [ServingUnit(name: "cup", quantityBasis: 1, gramWeight: 240)]
    )
}

func assertEqual(
    _ estimate: NutritionEstimate,
    calories: Double, protein: Double, carbohydrates: Double, fat: Double,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(estimate.calories, calories, accuracy: 0.0001, "calories", file: file, line: line)
    XCTAssertEqual(estimate.protein, protein, accuracy: 0.0001, "protein", file: file, line: line)
    XCTAssertEqual(estimate.carbohydrates, carbohydrates, accuracy: 0.0001, "carbohydrates", file: file, line: line)
    XCTAssertEqual(estimate.fat, fat, accuracy: 0.0001, "fat", file: file, line: line)
}
