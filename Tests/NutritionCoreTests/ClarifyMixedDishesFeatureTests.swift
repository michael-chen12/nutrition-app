import Foundation
import NutritionCore
import XCTest

/// Ticket #11: when a photo cannot reveal key details of a mixed dish, the person gets focused questions,
/// answers them by adding or adjusting foods (oil, sauce, unseen drinks) with source-backed or custom nutrition,
/// or dismisses them, and sees any unresolved uncertainty alongside the nutrition estimate, also after saving.
final class ClarifyMixedDishesFeatureTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var gateway: FakeMealAnalysisGateway!
    private let mealTime = Date(timeIntervalSince1970: 1_792_200_000)
    private let bowlPhoto = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x11])

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        gateway = FakeMealAnalysisGateway()
        gateway.foodSearchResults["fried rice vegetable"] = [Self.friedRice]
        gateway.foodSearchResults["oil vegetable"] = [Self.canolaOil]
        gateway.foodSearchResults["iced tea sweetened"] = [Self.sweetenedIcedTea]
    }

    override func tearDown() {
        directory.remove()
    }

    private func makeWorkflow(store: MealHistoryStore = InMemoryMealHistoryStore()) -> MealEntryWorkflow {
        MealEntryWorkflow(store: store, gateway: gateway, now: { self.mealTime })
    }

    /// A bowl of vegetable fried rice (200 g) whose oil, sauce and amount the photo cannot settle.
    private func friedRiceAnalysis(photo: MealPhoto.ID) -> MealPhotoAnalysisResponse {
        MealPhotoAnalysisResponse(suggestions: [
            FoodSuggestion(
                id: "1",
                name: "Vegetable fried rice",
                searchQuery: "fried rice vegetable",
                photoIDs: [photo.uuidString],
                portion: PortionSuggestion(quantity: 200, unit: "g"),
                unresolvedDetails: [
                    UnresolvedDetail(
                        kind: .preparation, detail: "Cooking oil not visible",
                        question: "Was it cooked in oil? How much?", searchQuery: "oil vegetable"
                    ),
                    UnresolvedDetail(
                        kind: .ingredient, detail: "Sauce can't be identified", question: "Which sauce was added?"
                    ),
                    UnresolvedDetail(
                        kind: .portion, detail: "Bowl depth unclear", question: "How much fried rice was there?"
                    ),
                ]
            ),
        ])
    }

    /// Starts a meal entry with the bowl photo and accepts the fried rice suggestion with its 200 g portion.
    private func reviewFriedRice(in workflow: MealEntryWorkflow) async throws -> MealPhoto.ID {
        workflow.startNewMealEntry()
        let photo = workflow.importPhoto(bowlPhoto, fileExtension: "jpg")
        gateway.photoAnalysisResult = .success(friedRiceAnalysis(photo: photo))
        workflow.acceptPhotoAnalysisDisclosure()
        let analysis = try await workflow.analyzePhoto(photo)
        let suggestion = try XCTUnwrap(analysis.suggestions.first)
        try workflow.acceptSuggestion(suggestion.id, as: try XCTUnwrap(suggestion.matches.first))
        return photo
    }

    // MARK: Hidden ingredient

    func test_aMixedDishAsksFocusedQuestionsInsteadOfGuessingItsHiddenDetails() async throws {
        let workflow = makeWorkflow()
        _ = try await reviewFriedRice(in: workflow)

        let review = try XCTUnwrap(workflow.draftReview)
        XCTAssertEqual(review.foods.map(\.name), ["Rice, fried, with vegetables"])
        XCTAssertEqual(review.focusedQuestions.map(\.question), [
            "Was it cooked in oil? How much?", "Which sauce was added?", "How much fried rice was there?",
        ])
        XCTAssertEqual(review.focusedQuestions.map(\.detail), [
            "Cooking oil not visible", "Sauce can't be identified", "Bowl depth unclear",
        ])
        XCTAssertEqual(review.focusedQuestions.map(\.foodName), Array(repeating: "Rice, fried, with vegetables", count: 3))
        XCTAssertEqual(review.focusedQuestions.map(\.kind), [.preparation, .ingredient, .portion])
        XCTAssertEqual(review.focusedQuestions.map(\.suggestedSearch), ["oil vegetable", nil, nil])
        XCTAssertEqual(
            review.uncertaintySummary,
            "3 details are still unresolved, so this estimate may be higher or lower. Answer the questions to refine it."
        )
        // 200 g fried rice only: nothing is added for the oil until the person says so.
        XCTAssertEqual(review.nutritionEstimate.calories, "340 kcal")
    }

    func test_answeringWithAddedOilSauceAndAPortionCorrectionRecalculatesTheEstimate() async throws {
        let workflow = makeWorkflow()
        _ = try await reviewFriedRice(in: workflow)
        let questions = try XCTUnwrap(workflow.draftReview?.focusedQuestions)
        let (oilQuestion, sauceQuestion, portionQuestion) = (questions[0], questions[1], questions[2])

        let oilSearch = try await workflow.searchFoods(matching: try XCTUnwrap(oilQuestion.suggestedSearch))
        let oil = try XCTUnwrap(oilSearch.results.first)
        try workflow.answerQuestion(oilQuestion.id, byAdding: oil, quantity: 1, unit: .serving(Self.tablespoon))

        var review = try XCTUnwrap(workflow.draftReview)
        XCTAssertEqual(review.foods.map(\.name), ["Rice, fried, with vegetables", "Oil, canola"])
        XCTAssertEqual(review.foods.map(\.sourceName), ["USDA FoodData Central", "USDA FoodData Central"])
        XCTAssertEqual(review.foods.map(\.portion), ["200 g", "1 tbsp (14 g)"])
        XCTAssertEqual(review.foods.map(\.shownIn), ["Photo 1", "Photo 1"], "The oil is in the pictured dish")
        XCTAssertEqual(review.focusedQuestions.map(\.question), [
            "Which sauce was added?", "How much fried rice was there?",
        ])
        // 340 kcal fried rice + 123.76 kcal oil (14 g fat).
        XCTAssertEqual(review.nutritionEstimate.calories, "464 kcal")
        XCTAssertEqual(review.nutritionEstimate.fat, "21 g")

        try workflow.answerQuestion(
            sauceQuestion.id,
            byAddingCustomFood: CustomFood(
                name: "Sweet chili sauce",
                nutrientsPer100g: NutrientsPer100g(calories: 230, protein: 1, carbohydrates: 55, fat: 0.7)
            ),
            grams: 30
        )
        try workflow.answerQuestion(portionQuestion.id, byChangingPortionTo: 250, unit: .grams)

        review = try XCTUnwrap(workflow.draftReview)
        XCTAssertEqual(review.foods.map(\.name), ["Rice, fried, with vegetables", "Oil, canola", "Sweet chili sauce"])
        XCTAssertEqual(review.foods.map(\.sourceName), ["USDA FoodData Central", "USDA FoodData Central", "Custom food"])
        XCTAssertEqual(review.foods.map(\.portion), ["250 g", "1 tbsp (14 g)", "30 g"])
        XCTAssertEqual(review.foods.map(\.uncertaintyNotes), [[], [], []])
        XCTAssertEqual(review.focusedQuestions, [])
        XCTAssertNil(review.uncertaintySummary)
        // 250 g fried rice (425 kcal, 10 g, 75 g, 8.75 g) + oil (123.76 kcal, 0 g, 0 g, 14 g)
        // + 30 g sauce (69 kcal, 0.3 g, 16.5 g, 0.21 g).
        XCTAssertEqual(review.nutritionEstimate.calories, "618 kcal")
        XCTAssertEqual(review.nutritionEstimate.protein, "10.3 g")
        XCTAssertEqual(review.nutritionEstimate.carbohydrates, "91.5 g")
        XCTAssertEqual(review.nutritionEstimate.fat, "23 g")
    }

    // MARK: Dismissed and unanswered questions

    func test_unansweredQuestionsStayVisibleWithTheSavedEstimateAfterRelaunch() async throws {
        let firstLaunch = makeWorkflow(store: try FileMealHistoryStore(directory: directory.url))
        _ = try await reviewFriedRice(in: firstLaunch)
        let questions = try XCTUnwrap(firstLaunch.draftReview?.focusedQuestions)
        try firstLaunch.dismissQuestion(questions[0].id) // No oil was used.
        try firstLaunch.answerQuestion(questions[2].id, byChangingPortionTo: 250, unit: .grams)
        // An unseen drink the photo doesn't show, added deliberately.
        let teaSearch = try await firstLaunch.searchFoods(matching: "iced tea sweetened")
        try firstLaunch.addFood(try XCTUnwrap(teaSearch.results.first), grams: 300)
        let id = try firstLaunch.saveMealEntry()

        let secondLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url), gateway: FakeMealAnalysisGateway()
        )
        let saved = try secondLaunch.openMealEntry(id: id)
        XCTAssertEqual(saved.foods.map(\.name), ["Rice, fried, with vegetables", "Tea, iced, sweetened"])
        XCTAssertEqual(saved.foods.map(\.shownIn), ["Photo 1", nil])
        XCTAssertEqual(saved.foods.map(\.uncertaintyNotes), [["Sauce can't be identified"], []])
        XCTAssertEqual(saved.focusedQuestions.map(\.question), ["Which sauce was added?"])
        XCTAssertEqual(
            saved.uncertaintySummary,
            "1 detail is still unresolved, so this estimate may be higher or lower. Answer the question to refine it."
        )
        // 250 g fried rice (425 kcal) + 300 g iced tea (105 kcal); nothing was guessed for the sauce.
        XCTAssertEqual(saved.nutritionEstimate.calories, "530 kcal")
        XCTAssertEqual(saved.nutritionEstimate.carbohydrates, "102 g")
        let historyRow = try XCTUnwrap(secondLaunch.dailyMealHistory().first?.mealEntries.first)
        XCTAssertTrue(historyRow.hasUnresolvedUncertainty)

        // Answered later by editing the saved meal entry.
        try secondLaunch.editMealEntry(id: id)
        try secondLaunch.dismissQuestion(try XCTUnwrap(saved.focusedQuestions.first).id)
        try secondLaunch.saveMealEntry()
        let resolved = try secondLaunch.openMealEntry(id: id)
        XCTAssertEqual(resolved.focusedQuestions, [])
        XCTAssertNil(resolved.uncertaintySummary)
        XCTAssertEqual(resolved.nutritionEstimate.calories, "530 kcal")
        XCTAssertFalse(try XCTUnwrap(secondLaunch.mealHistory().first).hasUnresolvedUncertainty)
    }

    func test_aQuestionCanBeAnsweredOnlyOnce() async throws {
        let workflow = makeWorkflow()
        _ = try await reviewFriedRice(in: workflow)
        let oilQuestion = try XCTUnwrap(workflow.draftReview?.focusedQuestions.first)
        try workflow.dismissQuestion(oilQuestion.id)

        XCTAssertThrowsError(try workflow.answerQuestion(oilQuestion.id, byChangingPortionTo: 1, unit: .grams)) {
            XCTAssertEqual($0 as? MealEntryWorkflowError, .questionNotFound(oilQuestion.id))
        }
        XCTAssertEqual(workflow.draftReview?.foods.map(\.portion), ["200 g"])
        XCTAssertEqual(workflow.draftReview?.focusedQuestions.count, 2)
    }

    func test_combiningARepeatedViewAsksAnUnresolvedDetailOnce() async throws {
        let workflow = makeWorkflow()
        workflow.startNewMealEntry()
        let first = workflow.importPhoto(bowlPhoto, fileExtension: "jpg")
        let second = workflow.importPhoto(bowlPhoto, fileExtension: "jpg")
        let oilDetail = UnresolvedDetail(
            kind: .preparation, detail: "Cooking oil not visible", question: "Was it cooked in oil? How much?"
        )
        workflow.acceptPhotoAnalysisDisclosure()
        var foodIDs: [ReviewedFood.ID] = []
        for photo in [first, second] {
            gateway.photoAnalysisResult = .success(MealPhotoAnalysisResponse(suggestions: [
                FoodSuggestion(id: "1", name: "Fried rice", searchQuery: "fried rice vegetable",
                               photoIDs: [photo.uuidString], portion: PortionSuggestion(quantity: 200, unit: "g"),
                               unresolvedDetails: [oilDetail]),
            ]))
            let analysis = try await workflow.analyzePhoto(photo)
            let suggestion = try XCTUnwrap(analysis.suggestions.first)
            foodIDs.append(try workflow.acceptSuggestion(suggestion.id, as: try XCTUnwrap(suggestion.matches.first)))
        }
        let (kept, repeated) = (foodIDs[0], foodIDs[1])

        try workflow.combineFood(repeated, into: kept)

        XCTAssertEqual(workflow.draftReview?.focusedQuestions.map(\.question), ["Was it cooked in oil? How much?"])
    }

    func test_uncertaintySavedBeforeFocusedQuestionsIsStillAskedAbout() throws {
        let photoID = UUID()
        let legacyJSON = """
        {
          "id": "\(UUID().uuidString)", "date": 0,
          "photos": [ { "id": "\(photoID.uuidString)", "fileExtension": "jpg" } ],
          "reviewedFoods": [ {
            "id": "\(UUID().uuidString)",
            "food": { "name": "Curry", "nutrientsPer100g": { "calories": 120, "protein": 6, "carbohydrates": 8,
                      "fat": 7 }, "source": { "custom": {} } },
            "portion": { "grams": 300 },
            "uncertaintyNotes": [ { "detail": "Cooked with oil or plain?" } ],
            "photoIDs": [ "\(photoID.uuidString)" ]
          } ]
        }
        """
        let entry = try JSONDecoder().decode(MealEntry.self, from: Data(legacyJSON.utf8))
        let store = InMemoryMealHistoryStore()
        try store.save(entry, photoData: [photoID: bowlPhoto])
        let workflow = makeWorkflow(store: store)

        XCTAssertEqual(try workflow.openMealEntry(id: entry.id).focusedQuestions.map(\.question), [
            "Cooked with oil or plain?",
        ])
        try workflow.editMealEntry(id: entry.id)
        let question = try XCTUnwrap(workflow.draftReview?.focusedQuestions.first)
        try workflow.answerQuestion(
            question.id,
            byAddingCustomFood: CustomFood(
                name: "Ghee", nutrientsPer100g: NutrientsPer100g(calories: 900, protein: 0, carbohydrates: 0, fat: 100)
            ),
            grams: 10
        )
        XCTAssertEqual(workflow.draftReview?.foods.map(\.shownIn), ["Photo 1", "Photo 1"])
        // 300 g curry (360 kcal) + 10 g ghee (90 kcal).
        XCTAssertEqual(workflow.draftReview?.nutritionEstimate.calories, "450 kcal")
        XCTAssertNil(workflow.draftReview?.uncertaintySummary)
    }

    // MARK: Known lookup results at the external boundary

    static let tablespoon = ServingUnit(name: "tbsp", quantityBasis: 1, gramWeight: 14)

    /// 170 kcal, 4 g protein, 30 g carbohydrates, 3.5 g fat per 100 g.
    static let friedRice = Food(
        name: "Rice, fried, with vegetables",
        nutrientsPer100g: NutrientsPer100g(calories: 170, protein: 4, carbohydrates: 30, fat: 3.5),
        source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "2708000"))
    )

    /// 884 kcal and 100 g fat per 100 g; 1 tbsp = 14 g.
    static let canolaOil = Food(
        name: "Oil, canola",
        nutrientsPer100g: NutrientsPer100g(calories: 884, protein: 0, carbohydrates: 0, fat: 100),
        source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "172336")),
        servingUnits: [tablespoon]
    )

    /// 35 kcal and 9 g carbohydrates per 100 g.
    static let sweetenedIcedTea = Food(
        name: "Tea, iced, sweetened",
        nutrientsPer100g: NutrientsPer100g(calories: 35, protein: 0, carbohydrates: 9, fat: 0),
        source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "2709000"))
    )
}
