import Foundation
import NutritionCore
import XCTest

/// Ticket #10: a person submits several meal photos for one analysis (other angles and additional dishes),
/// reviews the foods suggested across them, keeps repeated views of one food as one food unless they separate
/// them, keeps distinct dishes, and saves a nutrition estimate for all pictured food, shared food and leftovers
/// included. Cross-photo suggestions are controlled at the external boundary.
final class ReconcileSuggestionsAcrossPhotosFeatureTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var gateway: FakeMealAnalysisGateway!
    private let mealTime = Date(timeIntervalSince1970: 1_792_300_000)
    private let pastaFromAbove = Data([0xFF, 0xD8, 0x01])
    private let pastaFromTheSide = Data([0xFF, 0xD8, 0x02])
    private let breadAndFries = Data([0x00, 0x00, 0x03])

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        gateway = FakeMealAnalysisGateway()
        gateway.foodSearchResults["pasta tomato sauce"] = [Self.pasta]
        gateway.foodSearchResults["bread roll"] = [Self.bread]
        gateway.foodSearchResults["french fries"] = [Self.fries]
        gateway.foodSearchResults["iced tea"] = [Self.icedTea]
    }

    override func tearDown() {
        directory.remove()
    }

    private func makeWorkflow(store: MealHistoryStore = InMemoryMealHistoryStore()) -> MealEntryWorkflow {
        let workflow = MealEntryWorkflow(store: store, gateway: gateway, now: { self.mealTime })
        workflow.acceptPhotoAnalysisDisclosure()
        return workflow
    }

    /// Three meal photos: pasta from above (1), the same pasta from the side (2), and a third photo of a
    /// shared bread basket and leftover fries (3).
    private func importMealPhotos(_ workflow: MealEntryWorkflow) -> (MealPhoto.ID, MealPhoto.ID, MealPhoto.ID) {
        workflow.startNewMealEntry()
        return (
            workflow.importPhoto(pastaFromAbove, fileExtension: "jpg"),
            workflow.importPhoto(pastaFromTheSide, fileExtension: "jpg"),
            workflow.importPhoto(breadAndFries, fileExtension: "heic")
        )
    }

    /// The pasta is suggested once per photo that shows it, hinted as one food seen from two angles.
    private func crossPhotoAnalysis(
        _ above: MealPhoto.ID,
        _ side: MealPhoto.ID,
        _ third: MealPhoto.ID
    ) -> MealPhotoAnalysisResponse {
        MealPhotoAnalysisResponse(
            suggestions: [
                FoodSuggestion(
                    id: "pasta-above", name: "Pasta with tomato sauce", searchQuery: "pasta tomato sauce",
                    photoIDs: [above.uuidString], portion: PortionSuggestion(quantity: 250, unit: "g"),
                    matchConfidence: .high
                ),
                FoodSuggestion(
                    id: "bread", name: "Shared bread basket", searchQuery: "bread roll",
                    photoIDs: [third.uuidString], portion: PortionSuggestion(quantity: 80, unit: "g"),
                    matchConfidence: .high
                ),
                FoodSuggestion(
                    id: "pasta-side", name: "Pasta with tomato sauce", searchQuery: "pasta tomato sauce",
                    photoIDs: [side.uuidString], portion: PortionSuggestion(quantity: 300, unit: "g"),
                    unresolvedDetails: [UnresolvedDetail(kind: .portion, detail: "Plate depth unclear")],
                    matchConfidence: .high
                ),
                FoodSuggestion(
                    id: "fries", name: "Leftover french fries", searchQuery: "french fries",
                    photoIDs: [third.uuidString], portion: PortionSuggestion(quantity: 50, unit: "g"),
                    matchConfidence: .high
                ),
            ],
            duplicateGroups: [
                DuplicateGroupHint(suggestionIDs: ["pasta-above", "pasta-side"], reason: "Same plate from two angles"),
            ]
        )
    }

    // MARK: One analysis for several photos

    func test_oneAnalysisUploadsEveryChosenPhotoTogether() async throws {
        let workflow = makeWorkflow()
        let (above, side, third) = importMealPhotos(workflow)
        gateway.photoAnalysisResult = .success(crossPhotoAnalysis(above, side, third))

        let analysis = try await workflow.analyzePhotos([above, side, third])

        XCTAssertEqual(gateway.photoAnalysisRequests, [MealPhotoAnalysisRequest(photos: [
            PhotoUpload(photoID: above.uuidString, mediaType: "image/jpeg", imageData: pastaFromAbove),
            PhotoUpload(photoID: side.uuidString, mediaType: "image/jpeg", imageData: pastaFromTheSide),
            PhotoUpload(photoID: third.uuidString, mediaType: "image/heic", imageData: breadAndFries),
        ])])
        XCTAssertNil(analysis.message)
        XCTAssertTrue(analysis.suggestions.contains { $0.name == "Shared bread basket" })
    }

    // MARK: Likely duplicates

    func test_likelyDuplicatesAreReviewedAsOneFoodWhileSharedFoodAndLeftoversStayIncluded() async throws {
        let firstLaunch = makeWorkflow(store: try FileMealHistoryStore(directory: directory.url))
        let (above, side, third) = importMealPhotos(firstLaunch)
        gateway.photoAnalysisResult = .success(crossPhotoAnalysis(above, side, third))

        let analysis = try await firstLaunch.analyzePhotos([above, side, third])

        XCTAssertEqual(
            analysis.suggestions.map(\.name),
            ["Pasta with tomato sauce", "Shared bread basket", "Leftover french fries"]
        )
        XCTAssertEqual(analysis.suggestions.map(\.shownIn), ["Photos 1 and 2", "Photo 3", "Photo 3"])
        XCTAssertEqual(analysis.suggestions.map(\.suggestedPortion), ["250 g", "80 g", "50 g"])
        XCTAssertEqual(analysis.suggestions.map(\.uncertaintyNotes), [["Plate depth unclear"], [], []])
        XCTAssertEqual(
            analysis.suggestions.map(\.likelyDuplicateNote),
            [
                "Likely the same food seen in Photos 1 and 2 (Same plate from two angles). "
                    + "It counts once unless you separate it.",
                nil,
                nil,
            ]
        )

        for suggestion in analysis.suggestions {
            try firstLaunch.acceptSuggestion(suggestion.id, as: try XCTUnwrap(suggestion.matches.first))
        }
        XCTAssertEqual(firstLaunch.photoSuggestionReview?.suggestions, [])
        let review = try XCTUnwrap(firstLaunch.draftReview)
        assertShowsPastaOnceWithSharedBreadAndLeftoverFries(review)
        let id = try firstLaunch.saveMealEntry()

        let secondLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url), gateway: FakeMealAnalysisGateway()
        )
        let reopened = try secondLaunch.openMealEntry(id: id)
        assertShowsPastaOnceWithSharedBreadAndLeftoverFries(reopened)
        XCTAssertEqual(reopened.photos.map(\.imageData), [pastaFromAbove, pastaFromTheSide, breadAndFries])
        XCTAssertEqual(try secondLaunch.mealHistory().first?.nutritionEstimate.calories, "768 kcal")
    }

    func test_separatedLikelyDuplicatesAreReviewedAndCountedAsDistinctFoods() async throws {
        let workflow = makeWorkflow()
        let (above, side, third) = importMealPhotos(workflow)
        gateway.photoAnalysisResult = .success(crossPhotoAnalysis(above, side, third))
        let analysis = try await workflow.analyzePhotos([above, side, third])
        let grouped = analysis.suggestions[0]

        // Two people each had a plate of the same pasta.
        let separated = try workflow.separateSuggestion(grouped.id)

        let review = try XCTUnwrap(workflow.photoSuggestionReview)
        XCTAssertEqual(review.suggestions.map(\.id).prefix(2), separated[...])
        XCTAssertEqual(
            review.suggestions.map(\.name),
            ["Pasta with tomato sauce", "Pasta with tomato sauce", "Shared bread basket", "Leftover french fries"]
        )
        XCTAssertEqual(review.suggestions.map(\.shownIn), ["Photo 1", "Photo 2", "Photo 3", "Photo 3"])
        XCTAssertEqual(review.suggestions.map(\.suggestedPortion), ["250 g", "300 g", "80 g", "50 g"])
        XCTAssertEqual(review.suggestions.map(\.uncertaintyNotes), [[], ["Plate depth unclear"], [], []])
        XCTAssertEqual(review.suggestions.map(\.likelyDuplicateNote), [nil, nil, nil, nil])
        XCTAssertThrowsError(try workflow.acceptSuggestion(grouped.id, as: try XCTUnwrap(grouped.matches.first))) {
            XCTAssertEqual($0 as? MealEntryWorkflowError, .suggestionNotFound(grouped.id))
        }

        for suggestion in review.suggestions.prefix(2) {
            try workflow.acceptSuggestion(suggestion.id, as: try XCTUnwrap(suggestion.matches.first))
        }
        try workflow.rejectSuggestion(review.suggestions[2].id)
        try workflow.rejectSuggestion(review.suggestions[3].id)

        // Pasta 250 g (400 kcal, 14.5 g, 77.5 g, 2.25 g) + pasta 300 g (480 kcal, 17.4 g, 93 g, 2.7 g).
        let id = try workflow.saveMealEntry()
        let saved = try workflow.openMealEntry(id: id)
        XCTAssertEqual(saved.foods.map(\.portion), ["250 g", "300 g"])
        XCTAssertEqual(saved.foods.map(\.shownIn), ["Photo 1", "Photo 2"])
        XCTAssertEqual(saved.nutritionEstimate.calories, "880 kcal")
        XCTAssertEqual(saved.nutritionEstimate.protein, "31.9 g")
        XCTAssertEqual(saved.nutritionEstimate.carbohydrates, "170.5 g")
        XCTAssertEqual(saved.nutritionEstimate.fat, "5 g")
    }

    func test_twoOfAFoodInOnePhotoStayDistinctEvenWhenHintedAsDuplicates() async throws {
        let workflow = makeWorkflow()
        workflow.startNewMealEntry()
        let table = workflow.importPhoto(Data([0x01]), fileExtension: "jpg")
        let closeUp = workflow.importPhoto(Data([0x02]), fileExtension: "jpg")
        gateway.photoAnalysisResult = .success(MealPhotoAnalysisResponse(
            suggestions: [
                FoodSuggestion(
                    id: "tea-left", name: "Iced tea", searchQuery: "iced tea", photoIDs: [table.uuidString],
                    portion: PortionSuggestion(quantity: 400, unit: "g")
                ),
                FoodSuggestion(
                    id: "tea-right", name: "Iced tea", searchQuery: "iced tea", photoIDs: [table.uuidString],
                    portion: PortionSuggestion(quantity: 400, unit: "g")
                ),
                FoodSuggestion(
                    id: "tea-close", name: "Iced tea", searchQuery: "iced tea", photoIDs: [closeUp.uuidString],
                    portion: PortionSuggestion(quantity: 400, unit: "g")
                ),
            ],
            duplicateGroups: [
                DuplicateGroupHint(suggestionIDs: ["tea-left", "tea-right"]),
                DuplicateGroupHint(suggestionIDs: ["tea-right", "tea-close"], reason: "Same glass up close"),
            ]
        ))

        let analysis = try await workflow.analyzePhotos([table, closeUp])

        XCTAssertEqual(analysis.suggestions.map(\.shownIn), ["Photo 1", "Photos 1 and 2"])
        XCTAssertEqual(analysis.suggestions.map(\.likelyDuplicateNote), [
            nil,
            "Likely the same food seen in Photos 1 and 2 (Same glass up close). It counts once unless you separate it.",
        ])
        for suggestion in analysis.suggestions {
            try workflow.acceptSuggestion(suggestion.id, as: try XCTUnwrap(suggestion.matches.first))
        }
        // Two glasses of 400 g iced tea (120 kcal, 30 g carbohydrates each).
        XCTAssertEqual(workflow.draftReview?.nutritionEstimate.calories, "240 kcal")
        XCTAssertEqual(workflow.draftReview?.nutritionEstimate.carbohydrates, "60 g")
    }

    // MARK: Failures

    func test_aDuplicateHintThatNamesNoListedFoodIsIgnoredAndEverySuggestionIsKept() async throws {
        let workflow = makeWorkflow()
        let (above, side, third) = importMealPhotos(workflow)
        var analysis = crossPhotoAnalysis(above, side, third)
        analysis.duplicateGroups.insert(DuplicateGroupHint(suggestionIDs: ["pasta-above", "salad"]), at: 0)
        gateway.photoAnalysisResult = .success(analysis)

        let review = try await workflow.analyzePhotos([above, side, third])

        XCTAssertNil(review.message)
        XCTAssertEqual(review.suggestions.map(\.name), ["Pasta with tomato sauce", "Shared bread basket", "Leftover french fries"])
        XCTAssertEqual(review.suggestions.map(\.shownIn), ["Photos 1 and 2", "Photo 3", "Photo 3"], "Valid hints still apply")
    }

    func test_failedMultiPhotoAnalysisLeavesEveryPhotoForManualEntry() async throws {
        let workflow = makeWorkflow()
        let (above, side, third) = importMealPhotos(workflow)
        let photos = [above, side, third]

        gateway.photoAnalysisResult = .failure(MealAnalysisGatewayError.malformedAnalysis)
        let malformed = try await workflow.analyzePhotos(photos)
        XCTAssertEqual(malformed.suggestions, [])
        XCTAssertEqual(malformed.message, "Photo analysis returned results the app couldn't use. Your photos are "
            + "still in this meal entry: search for foods or add a custom food to finish it.")

        gateway.photoAnalysisResult = .failure(MealAnalysisGatewayError.analysisUnavailable)
        let unavailable = try await workflow.analyzePhotos(photos)
        XCTAssertEqual(unavailable.message, "Photo analysis isn't available right now. Your photos are still in this "
            + "meal entry: search for foods or add a custom food to finish it.")

        gateway.photoAnalysisResult = .success(MealPhotoAnalysisResponse(suggestions: []))
        let nothingFound = try await workflow.analyzePhotos(photos)
        XCTAssertEqual(nothingFound.message, "Photo analysis found no food in these photos. Search for foods or add "
            + "a custom food instead.")

        XCTAssertEqual(workflow.draftReview?.photos.count, 3)
        XCTAssertEqual(workflow.draftReview?.foods, [])
    }

    /// Pasta 250 g (400 kcal, 14.5 g protein, 77.5 g carbohydrates, 2.25 g fat) seen in photos 1 and 2
    /// counts once; shared bread 80 g (212 kcal, 7.2 g, 39.2 g, 2.56 g); leftover fries 50 g (156 kcal,
    /// 1.7 g, 20.5 g, 7.5 g).
    private func assertShowsPastaOnceWithSharedBreadAndLeftoverFries(
        _ entry: MealEntryPresentation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(entry.foods.map(\.name), ["Pasta with tomato sauce", "Bread roll", "French fries"],
                       file: file, line: line)
        XCTAssertEqual(entry.foods.map(\.portion), ["250 g", "80 g", "50 g"], file: file, line: line)
        XCTAssertEqual(entry.foods.map(\.shownIn), ["Photos 1 and 2", "Photo 3", "Photo 3"], file: file, line: line)
        // The pasta's portion was already unresolved; bread and fries keep their photo-estimated grams as such.
        XCTAssertEqual(
            entry.foods.map(\.uncertaintyNotes),
            [["Plate depth unclear"], ["Portion estimated from the photo"], ["Portion estimated from the photo"]],
            file: file, line: line
        )
        XCTAssertEqual(entry.foods.map(\.sourceRecordID), ["pasta-1", "bread-1", "fries-1"], file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.label, "Approximate nutrition estimate", file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.calories, "768 kcal", file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.protein, "23.4 g", file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.carbohydrates, "137.2 g", file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.fat, "12.3 g", file: file, line: line)
    }

    // MARK: Known lookup results at the external boundary (test values, not real source records)

    /// 160 kcal, 5.8 g protein, 31 g carbohydrates, 0.9 g fat per 100 g.
    static let pasta = Food(
        name: "Pasta with tomato sauce",
        nutrientsPer100g: NutrientsPer100g(calories: 160, protein: 5.8, carbohydrates: 31, fat: 0.9),
        source: .documented(SourceReference(sourceName: "Test nutrition source", recordID: "pasta-1"))
    )

    /// 265 kcal, 9 g protein, 49 g carbohydrates, 3.2 g fat per 100 g.
    static let bread = Food(
        name: "Bread roll",
        nutrientsPer100g: NutrientsPer100g(calories: 265, protein: 9, carbohydrates: 49, fat: 3.2),
        source: .documented(SourceReference(sourceName: "Test nutrition source", recordID: "bread-1"))
    )

    /// 312 kcal, 3.4 g protein, 41 g carbohydrates, 15 g fat per 100 g.
    static let fries = Food(
        name: "French fries",
        nutrientsPer100g: NutrientsPer100g(calories: 312, protein: 3.4, carbohydrates: 41, fat: 15),
        source: .documented(SourceReference(sourceName: "Test nutrition source", recordID: "fries-1"))
    )

    /// 30 kcal, 0 g protein, 7.5 g carbohydrates, 0 g fat per 100 g.
    static let icedTea = Food(
        name: "Iced tea, sweetened",
        nutrientsPer100g: NutrientsPer100g(calories: 30, protein: 0, carbohydrates: 7.5, fat: 0),
        source: .documented(SourceReference(sourceName: "Test nutrition source", recordID: "tea-1"))
    )
}
