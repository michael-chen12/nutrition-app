import Foundation
import NutritionCore
import XCTest

/// Ticket #9: a person submits a non-sensitive test meal photo for hosted analysis after reading how the
/// provider may use it, reviews suggested foods and portions with their uncertainty, accepts, changes or
/// rejects them, and saves a meal entry whose nutrition comes only from documented sources or custom foods.
/// If analysis fails, they get a clear message and finish the meal entry manually.
final class ReviewHostedPhotoSuggestionsFeatureTests: XCTestCase {
    private var directory: TemporaryDirectory!
    private var gateway: FakeMealAnalysisGateway!
    private let mealTime = Date(timeIntervalSince1970: 1_792_200_000)
    private let platePhoto = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01])

    override func setUpWithError() throws {
        directory = try TemporaryDirectory()
        gateway = FakeMealAnalysisGateway()
        gateway.foodSearchResults["rice white cooked"] = [Self.cookedWhiteRice]
        gateway.foodSearchResults["chicken breast cooked"] = [Self.roastedChickenBreast]
    }

    override func tearDown() {
        directory.remove()
    }

    private func makeWorkflow(store: MealHistoryStore = InMemoryMealHistoryStore()) -> MealEntryWorkflow {
        MealEntryWorkflow(store: store, gateway: gateway, now: { self.mealTime })
    }

    /// Rice (1 cup, about 158 g) and stir-fried chicken (120 g) with specific uncertainty, as the
    /// analysis boundary reports them for the given photo.
    private func riceAndChickenAnalysis(photo: MealPhoto.ID) -> MealPhotoAnalysisResponse {
        MealPhotoAnalysisResponse(suggestions: [
            FoodSuggestion(
                id: "food-1",
                name: "Steamed white rice",
                searchQuery: "rice white cooked",
                photoIDs: [photo.uuidString],
                portion: PortionSuggestion(quantity: 1, unit: "cup", grams: 158),
                matchConfidence: .high
            ),
            FoodSuggestion(
                id: "food-2",
                name: "Stir-fried chicken",
                searchQuery: "chicken breast cooked",
                photoIDs: [photo.uuidString],
                portion: PortionSuggestion(quantity: 120, unit: "g"),
                unresolvedDetails: [
                    UnresolvedDetail(kind: .ingredient, detail: "Cooking oil not visible"),
                    UnresolvedDetail(kind: .preparation, detail: "Sauce may contain added sugar"),
                ],
                matchConfidence: .high
            ),
        ])
    }

    // MARK: Disclosure before upload

    func test_beforeUploadThePersonLearnsWherePhotosGoAndHowTheUnpaidTierMayUseThem() throws {
        let disclosure = makeWorkflow().photoAnalysisDisclosure

        let text = ([disclosure.title] + disclosure.paragraphs).joined(separator: "\n")
        XCTAssertTrue(text.contains("uploaded to Google"), text)
        XCTAssertTrue(text.contains("Google may use"), text)
        XCTAssertTrue(text.contains("improve"), text)
        XCTAssertTrue(text.contains("human review"), text)
        XCTAssertTrue(text.contains("non-sensitive test photos"), text)
        XCTAssertTrue(text.contains("stays on this iPhone"), text)
        XCTAssertEqual(disclosure.uploadButtonTitle, "Upload photo for analysis")
        XCTAssertEqual(disclosure.manualEntryButtonTitle, "Enter foods myself")
    }

    func test_noPhotoIsUploadedUntilThePersonAcceptsTheDisclosure() async throws {
        gateway.photoAnalysisResult = .success(MealPhotoAnalysisResponse(suggestions: []))
        let workflow = makeWorkflow()
        workflow.startNewMealEntry()
        let photo = workflow.importPhoto(platePhoto, fileExtension: "jpg")

        do {
            _ = try await workflow.analyzePhoto(photo)
            XCTFail("Analysis must wait for the disclosure")
        } catch {
            XCTAssertEqual(error as? MealEntryWorkflowError, .photoAnalysisDisclosureNotAccepted)
        }
        XCTAssertEqual(gateway.photoAnalysisRequests, [])

        workflow.acceptPhotoAnalysisDisclosure()
        _ = try await workflow.analyzePhoto(photo)

        XCTAssertEqual(gateway.photoAnalysisRequests, [MealPhotoAnalysisRequest(photos: [
            PhotoUpload(photoID: photo.uuidString, mediaType: "image/jpeg", imageData: platePhoto),
        ])])
    }

    // MARK: Reviewing suggestions

    func test_suggestionsShowSourceBackedMatchesSuggestedPortionsAndSpecificUncertainty() async throws {
        let workflow = makeWorkflow()
        workflow.startNewMealEntry()
        let photo = workflow.importPhoto(platePhoto, fileExtension: "jpg")
        gateway.photoAnalysisResult = .success(riceAndChickenAnalysis(photo: photo))
        workflow.acceptPhotoAnalysisDisclosure()

        let analysis = try await workflow.analyzePhoto(photo)

        XCTAssertNil(analysis.message)
        XCTAssertEqual(analysis.reviewNote, "Suggestions from photo analysis are approximate. Check each food and "
            + "portion; nutrition comes only from the documented food or custom food you choose.")
        XCTAssertEqual(analysis.suggestions.map(\.name), ["Steamed white rice", "Stir-fried chicken"])
        XCTAssertEqual(analysis.suggestions.map(\.suggestedPortion), ["1 cup (about 158 g)", "120 g"])
        XCTAssertEqual(analysis.suggestions.map(\.shownIn), ["Photo 1", "Photo 1"])
        XCTAssertEqual(
            analysis.suggestions.map(\.uncertaintyNotes),
            [[], ["Cooking oil not visible", "Sauce may contain added sugar"]]
        )

        let riceMatches = analysis.suggestions[0].matches
        XCTAssertEqual(riceMatches.map(\.result.name), ["Rice, white, long-grain, cooked"])
        XCTAssertEqual(riceMatches.map(\.result.sourceName), ["USDA FoodData Central"])
        XCTAssertEqual(riceMatches.map(\.result.sourceRecordID), ["168878"])
        XCTAssertEqual(riceMatches.map(\.suggestedPortion), ["1 cup (158 g)"], "Converted with the source's cup")
        XCTAssertEqual(analysis.suggestions[1].matches.map(\.result.sourceRecordID), ["171477"])
        XCTAssertEqual(analysis.suggestions[1].matches.map(\.suggestedPortion), ["About 120 g, estimated from the photo"])
        XCTAssertEqual(workflow.photoSuggestionReview, analysis, "Suggestions stay available while reviewing")
        XCTAssertEqual(workflow.draftReview?.foods, [], "Nothing counts until the person accepts it")
    }

    func test_acceptedChangedAndRejectedSuggestionsSaveWithSourceNutritionAndRetainedUncertainty() async throws {
        let firstLaunch = makeWorkflow(store: try FileMealHistoryStore(directory: directory.url))
        firstLaunch.startNewMealEntry()
        let photo = firstLaunch.importPhoto(platePhoto, fileExtension: "jpg")
        var analysisResponse = riceAndChickenAnalysis(photo: photo)
        analysisResponse.suggestions.append(FoodSuggestion(
            id: "food-3", name: "Lime wedge", searchQuery: "lime", photoIDs: [photo.uuidString]
        ))
        gateway.photoAnalysisResult = .success(analysisResponse)
        firstLaunch.acceptPhotoAnalysisDisclosure()
        let analysis = try await firstLaunch.analyzePhoto(photo)
        let (rice, chicken, lime) = (analysis.suggestions[0], analysis.suggestions[1], analysis.suggestions[2])

        try firstLaunch.acceptSuggestion(rice.id, as: try XCTUnwrap(rice.matches.first))
        try firstLaunch.acceptSuggestion(
            chicken.id, as: try XCTUnwrap(chicken.matches.first?.result), quantity: 150, unit: .grams
        )
        try firstLaunch.rejectSuggestion(lime.id)

        XCTAssertEqual(firstLaunch.photoSuggestionReview?.suggestions, [], "Every suggestion has been reviewed")
        let review = try XCTUnwrap(firstLaunch.draftReview)
        assertShowsReviewedRiceAndChicken(review)
        let id = try firstLaunch.saveMealEntry()

        let secondLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: directory.url), gateway: FakeMealAnalysisGateway()
        )
        let reopened = try secondLaunch.openMealEntry(id: id)
        assertShowsReviewedRiceAndChicken(reopened)
        XCTAssertEqual(reopened.photos.map(\.imageData), [platePhoto])
    }

    func test_aMistakenSuggestionCanBeChangedToAnotherSearchedFoodOrACustomFood() async throws {
        let jasmineRice = Food(
            name: "Rice, jasmine, cooked",
            nutrientsPer100g: NutrientsPer100g(calories: 129, protein: 2.9, carbohydrates: 28, fat: 0.2),
            source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "2512381"))
        )
        gateway.foodSearchResults["jasmine rice"] = [jasmineRice]
        let workflow = makeWorkflow()
        workflow.startNewMealEntry()
        let photo = workflow.importPhoto(platePhoto, fileExtension: "jpg")
        gateway.photoAnalysisResult = .success(MealPhotoAnalysisResponse(suggestions: [
            FoodSuggestion(
                id: "1", name: "Steamed white rice", searchQuery: "rice white cooked", photoIDs: [photo.uuidString],
                portion: PortionSuggestion(quantity: 1, unit: "cup", grams: 158)
            ),
            FoodSuggestion(
                id: "2", name: "Sambal", searchQuery: "sambal chili paste", photoIDs: [photo.uuidString],
                unresolvedDetails: [UnresolvedDetail(kind: .portion, detail: "Amount of sambal unclear")]
            ),
        ]))
        workflow.acceptPhotoAnalysisDisclosure()
        let analysis = try await workflow.analyzePhoto(photo)
        let sambal = analysis.suggestions[1]
        XCTAssertEqual(sambal.matches, [])
        XCTAssertEqual(
            sambal.noMatchMessage,
            "No documented food matches Sambal. Search for another name or add it as a custom food."
        )

        let search = try await workflow.searchFoods(matching: "jasmine rice")
        try workflow.acceptSuggestion(
            analysis.suggestions[0].id, as: try XCTUnwrap(search.results.first), quantity: 180, unit: .grams
        )
        try workflow.acceptSuggestion(
            sambal.id,
            asCustomFood: CustomFood(
                name: "Sambal oelek",
                nutrientsPer100g: NutrientsPer100g(calories: 60, protein: 1, carbohydrates: 8, fat: 2.5)
            ),
            grams: 20
        )

        let review = try XCTUnwrap(workflow.draftReview)
        XCTAssertEqual(review.foods.map(\.name), ["Rice, jasmine, cooked", "Sambal oelek"])
        XCTAssertEqual(review.foods.map(\.sourceName), ["USDA FoodData Central", "Custom food"])
        XCTAssertEqual(review.foods.map(\.portion), ["180 g", "20 g"])
        XCTAssertEqual(review.foods.map(\.uncertaintyNotes), [[], ["Amount of sambal unclear"]])
        // 180 g jasmine rice (232.2 kcal, 5.22 g, 50.4 g, 0.36 g) + 20 g sambal (12 kcal, 0.2 g, 1.6 g, 0.5 g).
        XCTAssertEqual(review.nutritionEstimate.calories, "244 kcal")
        XCTAssertEqual(review.nutritionEstimate.protein, "5.4 g")
        XCTAssertEqual(review.nutritionEstimate.carbohydrates, "52 g")
        XCTAssertEqual(review.nutritionEstimate.fat, "0.9 g")
    }

    func test_aSuggestedPortionWithNoDocumentedConversionIsNeverGuessed() async throws {
        let workflow = makeWorkflow()
        workflow.startNewMealEntry()
        let photo = workflow.importPhoto(platePhoto, fileExtension: "jpg")
        gateway.photoAnalysisResult = .success(MealPhotoAnalysisResponse(suggestions: [
            FoodSuggestion(
                id: "1", name: "Grilled chicken", searchQuery: "chicken breast cooked", photoIDs: [photo.uuidString],
                portion: PortionSuggestion(quantity: 2, unit: "pieces")
            ),
        ]))
        workflow.acceptPhotoAnalysisDisclosure()
        let analysis = try await workflow.analyzePhoto(photo)
        let suggestion = try XCTUnwrap(analysis.suggestions.first)

        XCTAssertEqual(suggestion.suggestedPortion, "2 pieces")
        let match = try XCTUnwrap(suggestion.matches.first)
        XCTAssertNil(match.suggestedPortion, "The source documents no weight for a piece")
        XCTAssertThrowsError(try workflow.acceptSuggestion(suggestion.id, as: match)) { error in
            XCTAssertEqual(error as? MealEntryWorkflowError, .suggestedPortionUnavailable)
        }
        XCTAssertEqual(workflow.draftReview?.foods, [])

        try workflow.acceptSuggestion(suggestion.id, as: match.result, quantity: 140, unit: .grams)
        XCTAssertEqual(workflow.draftReview?.foods.map(\.portion), ["140 g"])
        XCTAssertThrowsError(try workflow.rejectSuggestion(suggestion.id), "Already reviewed") { error in
            XCTAssertEqual(error as? MealEntryWorkflowError, .suggestionNotFound(suggestion.id))
        }
    }

    func test_aGramAmountGuessedFromThePhotoIsShownAndKeptAsAnEstimate() async throws {
        let workflow = makeWorkflow(store: try FileMealHistoryStore(directory: directory.url))
        workflow.startNewMealEntry()
        let photo = workflow.importPhoto(platePhoto, fileExtension: "jpg")
        gateway.photoAnalysisResult = .success(MealPhotoAnalysisResponse(suggestions: [
            // Grams as suggested by the analysis.
            FoodSuggestion(id: "1", name: "Stir-fried chicken", searchQuery: "chicken breast cooked",
                           photoIDs: [photo.uuidString], portion: PortionSuggestion(quantity: 120, unit: "g"),
                           matchConfidence: .high),
            // A unit the source documents no weight for, with the analysis's own gram guess.
            FoodSuggestion(id: "2", name: "Grilled chicken", searchQuery: "chicken breast cooked",
                           photoIDs: [photo.uuidString], portion: PortionSuggestion(quantity: 2, unit: "pieces", grams: 90),
                           matchConfidence: .high),
            // A cup converted through the source's documented weight.
            FoodSuggestion(id: "3", name: "Steamed white rice", searchQuery: "rice white cooked",
                           photoIDs: [photo.uuidString], portion: PortionSuggestion(quantity: 1, unit: "cup", grams: 150),
                           matchConfidence: .high),
        ]))
        workflow.acceptPhotoAnalysisDisclosure()
        let analysis = try await workflow.analyzePhoto(photo)
        let matches = try analysis.suggestions.map { try XCTUnwrap($0.matches.first) }

        XCTAssertEqual(matches.map(\.suggestedPortion), [
            "About 120 g, estimated from the photo",
            "About 90 g, estimated from the photo",
            "1 cup (158 g)",
        ])
        for (suggestion, match) in zip(analysis.suggestions, matches) {
            try workflow.acceptSuggestion(suggestion.id, as: match)
        }

        let saved = try workflow.openMealEntry(id: try workflow.saveMealEntry())
        XCTAssertEqual(saved.foods.map(\.portion), ["120 g", "90 g", "1 cup (158 g)"])
        XCTAssertEqual(saved.foods.map(\.uncertaintyNotes), [
            ["Portion estimated from the photo"], ["Portion estimated from the photo"], [],
        ])
        XCTAssertEqual(saved.focusedQuestions.map(\.question), [
            "How much Chicken, broilers or fryers, breast, roasted was there?",
            "How much Chicken, broilers or fryers, breast, roasted was there?",
        ])
        XCTAssertEqual(saved.focusedQuestions.map(\.kind), [.portion, .portion])
    }

    // MARK: Weak matches

    /// Story 34: the app asks for corrections when its match is weak.
    func test_aWeakOrUnratedMatchAsksThePersonToCheckIt() async throws {
        let workflow = makeWorkflow()
        workflow.startNewMealEntry()
        let photo = workflow.importPhoto(platePhoto, fileExtension: "jpg")
        gateway.photoAnalysisResult = .success(MealPhotoAnalysisResponse(suggestions: [
            FoodSuggestion(id: "1", name: "Steamed white rice", searchQuery: "rice white cooked",
                           photoIDs: [photo.uuidString], matchConfidence: .low),
            FoodSuggestion(id: "2", name: "Stir-fried chicken", searchQuery: "chicken breast cooked",
                           photoIDs: [photo.uuidString]),
            FoodSuggestion(id: "3", name: "Steamed white rice", searchQuery: "rice white cooked",
                           photoIDs: [photo.uuidString], matchConfidence: .medium),
            FoodSuggestion(id: "4", name: "Stir-fried chicken", searchQuery: "chicken breast cooked",
                           photoIDs: [photo.uuidString], matchConfidence: .high),
        ]))
        workflow.acceptPhotoAnalysisDisclosure()

        let analysis = try await workflow.analyzePhoto(photo)

        XCTAssertEqual(analysis.suggestions.map(\.checkMatchPrompt), [
            "Check this match: photo analysis isn't sure this is Steamed white rice. Compare it with your photo, "
                + "or choose another food.",
            "Check this match: photo analysis isn't sure this is Stir-fried chicken. Compare it with your photo, "
                + "or choose another food.",
            nil,
            nil,
        ])
    }

    func test_aWeakMatchAcceptedUnchangedKeepsItsUncertaintyButACorrectedOneDoesNot() async throws {
        let jasmineRice = Food(
            name: "Rice, jasmine, cooked",
            nutrientsPer100g: NutrientsPer100g(calories: 129, protein: 2.9, carbohydrates: 28, fat: 0.2),
            source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "2512381"))
        )
        gateway.foodSearchResults["jasmine rice"] = [jasmineRice]
        let workflow = makeWorkflow(store: try FileMealHistoryStore(directory: directory.url))
        workflow.startNewMealEntry()
        let photo = workflow.importPhoto(platePhoto, fileExtension: "jpg")
        gateway.photoAnalysisResult = .success(MealPhotoAnalysisResponse(suggestions: [
            FoodSuggestion(id: "1", name: "Steamed white rice", searchQuery: "rice white cooked",
                           photoIDs: [photo.uuidString], portion: PortionSuggestion(quantity: 1, unit: "cup"),
                           matchConfidence: .low),
            FoodSuggestion(id: "2", name: "Stir-fried chicken", searchQuery: "chicken breast cooked",
                           photoIDs: [photo.uuidString]),
            FoodSuggestion(id: "3", name: "Steamed white rice", searchQuery: "rice white cooked",
                           photoIDs: [photo.uuidString], matchConfidence: .low),
            FoodSuggestion(id: "4", name: "Stir-fried chicken", searchQuery: "chicken breast cooked",
                           photoIDs: [photo.uuidString], matchConfidence: .high),
        ]))
        workflow.acceptPhotoAnalysisDisclosure()
        let analysis = try await workflow.analyzePhoto(photo)
        let (weakRice, unratedChicken, correctedRice, sureChicken) = (
            analysis.suggestions[0], analysis.suggestions[1], analysis.suggestions[2], analysis.suggestions[3]
        )

        // Accepted as suggested: the match stays in doubt.
        try workflow.acceptSuggestion(weakRice.id, as: try XCTUnwrap(weakRice.matches.first))
        try workflow.acceptSuggestion(
            unratedChicken.id, as: try XCTUnwrap(unratedChicken.matches.first?.result), quantity: 100, unit: .grams
        )
        // Corrected to another food the person searched for: the person settled it.
        let jasmine = try await workflow.searchFoods(matching: "jasmine rice")
        try workflow.acceptSuggestion(correctedRice.id, as: try XCTUnwrap(jasmine.results.first), quantity: 100, unit: .grams)
        // A confident match needs no check.
        try workflow.acceptSuggestion(
            sureChicken.id, as: try XCTUnwrap(sureChicken.matches.first?.result), quantity: 100, unit: .grams
        )

        let id = try workflow.saveMealEntry()
        let saved = try workflow.openMealEntry(id: id)
        XCTAssertEqual(saved.foods.map(\.uncertaintyNotes), [
            ["Weak match: photo analysis wasn't sure this is Steamed white rice"],
            ["Weak match: photo analysis wasn't sure this is Stir-fried chicken"],
            [],
            [],
        ])
        XCTAssertEqual(saved.focusedQuestions.map(\.question), [
            "Is Rice, white, long-grain, cooked the right food?",
            "Is Chicken, broilers or fryers, breast, roasted the right food?",
        ])
        XCTAssertEqual(saved.focusedQuestions.map(\.kind), [.identity, .identity])
    }

    // MARK: Failures

    func test_whenAnalysisIsUnavailableThePersonSeesWhyAndFinishesTheMealEntryManually() async throws {
        let workflow = makeWorkflow()
        workflow.startNewMealEntry()
        let photo = workflow.importPhoto(platePhoto, fileExtension: "jpg")
        gateway.photoAnalysisResult = .failure(MealAnalysisGatewayError.analysisUnavailable)
        workflow.acceptPhotoAnalysisDisclosure()

        let analysis = try await workflow.analyzePhoto(photo)

        XCTAssertEqual(analysis.suggestions, [])
        XCTAssertEqual(analysis.message, "Photo analysis isn't available right now. Your photo is still in this "
            + "meal entry: search for foods or add a custom food to finish it.")
        try assertManualEntryStillFinishes(workflow, photo: photo)
    }

    func test_unusableAnalysisOutputShowsAClearMessageAndManualEntryStillWorks() async throws {
        let malformedMessage = "Photo analysis returned results the app couldn't use. Your photo is still in this "
            + "meal entry: search for foods or add a custom food to finish it."
        let workflow = makeWorkflow()
        workflow.startNewMealEntry()
        let photo = workflow.importPhoto(platePhoto, fileExtension: "jpg")
        workflow.acceptPhotoAnalysisDisclosure()

        gateway.photoAnalysisResult = .failure(MealAnalysisGatewayError.malformedAnalysis)
        let reportedMalformed = try await workflow.analyzePhoto(photo)
        XCTAssertEqual(reportedMalformed.message, malformedMessage)

        gateway.photoAnalysisResult = .success(MealPhotoAnalysisResponse(suggestions: [
            FoodSuggestion(id: "1", name: "Rice", searchQuery: "rice white cooked", photoIDs: ["some-other-photo"]),
        ]))
        let refersToAnotherPhoto = try await workflow.analyzePhoto(photo)
        XCTAssertEqual(refersToAnotherPhoto.message, malformedMessage)
        XCTAssertEqual(refersToAnotherPhoto.suggestions, [])

        try assertManualEntryStillFinishes(workflow, photo: photo)
    }

    func test_suggestionsBelongToTheirDraftAndUnreviewedOnesAreNotSaved() async throws {
        let workflow = makeWorkflow()
        workflow.startNewMealEntry()
        let photo = workflow.importPhoto(platePhoto, fileExtension: "jpg")
        gateway.photoAnalysisResult = .success(riceAndChickenAnalysis(photo: photo))
        workflow.acceptPhotoAnalysisDisclosure()
        let analysis = try await workflow.analyzePhoto(photo)
        try workflow.acceptSuggestion(analysis.suggestions[0].id, as: try XCTUnwrap(analysis.suggestions[0].matches.first))

        let id = try workflow.saveMealEntry()

        XCTAssertEqual(try workflow.openMealEntry(id: id).foods.map(\.name), ["Rice, white, long-grain, cooked"])
        XCTAssertNil(workflow.photoSuggestionReview)
        workflow.startNewMealEntry()
        XCTAssertNil(workflow.photoSuggestionReview)
    }

    private func assertManualEntryStillFinishes(
        _ workflow: MealEntryWorkflow,
        photo: MealPhoto.ID,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(workflow.draftReview?.photos.map(\.imageData), [platePhoto], file: file, line: line)
        XCTAssertEqual(workflow.draftReview?.foods, [], file: file, line: line)
        try workflow.addCustomFood(
            CustomFood(
                name: "Rice and chicken plate",
                nutrientsPer100g: NutrientsPer100g(calories: 150, protein: 12, carbohydrates: 17, fat: 3)
            ),
            grams: 300,
            shownIn: [photo]
        )
        let id = try workflow.saveMealEntry()
        let saved = try workflow.openMealEntry(id: id)
        XCTAssertEqual(saved.foods.map(\.name), ["Rice and chicken plate"], file: file, line: line)
        XCTAssertEqual(saved.nutritionEstimate.calories, "450 kcal", file: file, line: line)
    }

    /// Rice: 1 cup = 158 g of FDC 168878 (205.4 kcal, 4.25 g protein, 44.51 g carbohydrates, 0.44 g fat).
    /// Chicken: 150 g of FDC 171477 (247.5 kcal, 46.53 g protein, 0 g carbohydrates, 5.36 g fat).
    private func assertShowsReviewedRiceAndChicken(
        _ entry: MealEntryPresentation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            entry.foods.map(\.name), ["Rice, white, long-grain, cooked", "Chicken, broilers or fryers, breast, roasted"],
            file: file, line: line
        )
        XCTAssertEqual(entry.foods.map(\.portion), ["1 cup (158 g)", "150 g"], file: file, line: line)
        XCTAssertEqual(entry.foods.map(\.sourceName), ["USDA FoodData Central", "USDA FoodData Central"],
                       file: file, line: line)
        XCTAssertEqual(entry.foods.map(\.sourceRecordID), ["168878", "171477"], file: file, line: line)
        XCTAssertEqual(entry.foods.map(\.shownIn), ["Photo 1", "Photo 1"], file: file, line: line)
        XCTAssertEqual(
            entry.foods.map(\.uncertaintyNotes),
            [[], ["Cooking oil not visible", "Sauce may contain added sugar"]],
            file: file, line: line
        )
        XCTAssertEqual(entry.foods.map(\.nutritionEstimate.calories), ["205 kcal", "248 kcal"], file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.label, "Approximate nutrition estimate", file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.calories, "453 kcal", file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.protein, "50.8 g", file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.carbohydrates, "44.5 g", file: file, line: line)
        XCTAssertEqual(entry.nutritionEstimate.fat, "5.8 g", file: file, line: line)
    }

    // MARK: Known lookup results at the external boundary

    static let cup = ServingUnit(name: "cup", quantityBasis: 1, gramWeight: 158)

    /// 130 kcal, 2.69 g protein, 28.17 g carbohydrates, 0.28 g fat per 100 g; 1 cup = 158 g.
    static let cookedWhiteRice = Food(
        name: "Rice, white, long-grain, cooked",
        nutrientsPer100g: NutrientsPer100g(calories: 130, protein: 2.69, carbohydrates: 28.17, fat: 0.28),
        source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "168878")),
        servingUnits: [cup]
    )

    /// 165 kcal, 31.02 g protein, 0 g carbohydrates, 3.57 g fat per 100 g.
    static let roastedChickenBreast = Food(
        name: "Chicken, broilers or fryers, breast, roasted",
        nutrientsPer100g: NutrientsPer100g(calories: 165, protein: 31.02, carbohydrates: 0, fat: 3.57),
        source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "171477"))
    )
}
