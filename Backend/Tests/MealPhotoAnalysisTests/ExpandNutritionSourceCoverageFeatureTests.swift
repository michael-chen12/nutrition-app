import AUSNUT
import Foundation
import MealPhotoAnalysis
import NutritionCore
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ticket #13: for dishes FoodData Central covers poorly (the recorded calibration gap: Asian mixed dishes such as
/// sushi, laksa, dumplings and curries; docs/calibration/source-gaps.md), a person finds and chooses a food from
/// FSANZ AUSNUT 2023 and saves it in a meal entry with visible provenance.
///
/// Everything is real except FoodData Central, which answers with hand-built fixtures: the packaged AUSNUT 2023
/// data, the backend's food search, the app's HTTP gateway (its requests are handed to the backend in-process),
/// the meal entry workflow and the file-backed meal history.
final class ExpandNutritionSourceCoverageFeatureTests: XCTestCase {
    private static let ausnut = Result { try AUSNUTDataset.packaged() }
    private var historyDirectory: URL!

    override func setUpWithError() throws {
        historyDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: historyDirectory)
    }

    func test_aDishFDCLacksIsFoundInAUSNUTAddedByServingSavedAndReopenedWithItsSourceAfterRelaunch() async throws {
        let mealTime = Date(timeIntervalSince1970: 1_792_000_000)
        let firstLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: historyDirectory),
            gateway: try gateway(fdcSearchReply: #"{ "totalHits": 0, "foods": [] }"#),
            now: { mealTime }
        )
        firstLaunch.startNewMealEntry()

        let search = try await firstLaunch.searchFoods(matching: "sushi salmon")
        let sushi = try XCTUnwrap(search.results.first)
        XCTAssertEqual(sushi.name, "Sushi, salmon")
        XCTAssertEqual(sushi.sourceName, "FSANZ AUSNUT 2023")
        XCTAssertEqual(sushi.sourceRecordID, "F009009")
        XCTAssertEqual(sushi.portionUnits.map(\.name), ["g", "piece", "roll"])
        XCTAssertEqual(sushi.portionUnits.map(\.quantityBasis), [nil, "1 piece = 33 g", "1 roll = 104 g"])

        let piece = try XCTUnwrap(sushi.portionUnits.first { $0.name == "piece" })
        try firstLaunch.addFood(sushi, quantity: 3, unit: piece.unit)

        let review = try XCTUnwrap(firstLaunch.draftReview)
        XCTAssertEqual(review.foods.map(\.portion), ["3 piece (99 g)"])
        XCTAssertEqual(review.foods.map(\.sourceName), ["FSANZ AUSNUT 2023"])
        XCTAssertEqual(review.foods.map(\.sourceRecordID), ["F009009"])
        assertShowsThreeSalmonSushiPieces(review.nutritionEstimate)

        let id = try firstLaunch.saveMealEntry()

        let secondLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: historyDirectory),
            gateway: try gateway(fdcSearchReply: #"{ "totalHits": 0, "foods": [] }"#)
        )
        let day = try XCTUnwrap(try secondLaunch.dailyMealHistory().first)
        XCTAssertEqual(day.mealEntries.map(\.foodNames), [["Sushi, salmon"]])
        assertShowsThreeSalmonSushiPieces(day.mealEntries[0].nutritionEstimate)
        let reopened = try secondLaunch.openMealEntry(id: id)
        XCTAssertEqual(reopened.foods.map(\.name), ["Sushi, salmon"])
        XCTAssertEqual(reopened.foods.map(\.portion), ["3 piece (99 g)"])
        XCTAssertEqual(reopened.foods.map(\.sourceName), ["FSANZ AUSNUT 2023"])
        XCTAssertEqual(reopened.foods.map(\.sourceRecordID), ["F009009"])
        assertShowsThreeSalmonSushiPieces(reopened.nutritionEstimate)
    }

    func test_aDishDocumentedOnlyInGramsIsAddedInGramsSavedAndReopenedWithItsSourceAfterRelaunch() async throws {
        let firstLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: historyDirectory),
            gateway: try gateway(fdcSearchReply: FDCFixtures.riceSearchReply, fdcFoodsReply: FDCFixtures.riceFoodsReply)
        )
        firstLaunch.startNewMealEntry()

        // FDC answers with foods whose names lack "laksa"; AUSNUT's laksa has it, so it comes first.
        let search = try await firstLaunch.searchFoods(matching: "laksa")
        let laksa = try XCTUnwrap(search.results.first)
        XCTAssertEqual(laksa.name, "Soup, laksa, prawn or seafood, with noodles, made with coconut milk")
        XCTAssertEqual(laksa.sourceName, "FSANZ AUSNUT 2023")
        XCTAssertEqual(laksa.sourceRecordID, "F008589")
        XCTAssertEqual(laksa.portionUnits.map(\.name), ["g"], "AUSNUT documents only its density, in g per mL")

        try firstLaunch.addFood(laksa, quantity: 400, unit: laksa.portionUnits[0].unit)
        let review = try XCTUnwrap(firstLaunch.draftReview)
        XCTAssertEqual(review.foods.map(\.portion), ["400 g"])
        assertShowsFourHundredGramsOfPrawnLaksa(review.nutritionEstimate)
        let id = try firstLaunch.saveMealEntry()

        let secondLaunch = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: historyDirectory),
            gateway: try gateway(fdcSearchReply: #"{ "totalHits": 0, "foods": [] }"#)
        )
        let reopened = try secondLaunch.openMealEntry(id: id)
        XCTAssertEqual(reopened.foods.map(\.name), [laksa.name])
        XCTAssertEqual(reopened.foods.map(\.portion), ["400 g"])
        XCTAssertEqual(reopened.foods.map(\.sourceName), ["FSANZ AUSNUT 2023"])
        XCTAssertEqual(reopened.foods.map(\.sourceRecordID), ["F008589"])
        assertShowsFourHundredGramsOfPrawnLaksa(reopened.nutritionEstimate)
    }

    func test_overlappingFoodsFromBothSourcesAreToldApartByTheirSourceAndThePersonChoosesOne() async throws {
        let workflow = MealEntryWorkflow(
            store: try FileMealHistoryStore(directory: historyDirectory),
            gateway: try gateway(fdcSearchReply: FDCFixtures.riceSearchReply, fdcFoodsReply: FDCFixtures.riceFoodsReply)
        )
        workflow.startNewMealEntry()

        let search = try await workflow.searchFoods(matching: "rice white cooked")
        let shown = search.results.prefix(3).map { "\($0.name) · \($0.sourceName) \($0.sourceRecordID ?? "")" }
        XCTAssertEqual(Array(shown), [
            "Rice, white, cooked, no added fat · USDA FoodData Central 2708346",
            "Rice, white, cooked · FSANZ AUSNUT 2023 F007661",
            "Rice, white, long-grain, regular, enriched, cooked · USDA FoodData Central 168878",
        ])
        XCTAssertEqual(Set(search.results.map(\.id)).count, search.results.count, "Every result is its own choice")

        let ausnutRice = try XCTUnwrap(search.results.first { $0.sourceRecordID == "F007661" })
        let cup = try XCTUnwrap(ausnutRice.portionUnits.first { $0.name == "cup, 250 mL" })
        XCTAssertEqual(cup.quantityBasis, "1 cup, 250 mL = 190 g")
        try workflow.addFood(ausnutRice, quantity: 1, unit: cup.unit)
        let id = try workflow.saveMealEntry()

        let reopened = try workflow.openMealEntry(id: id)
        XCTAssertEqual(reopened.foods.map(\.portion), ["1 cup, 250 mL (190 g)"])
        XCTAssertEqual(reopened.foods.map(\.sourceName), ["FSANZ AUSNUT 2023"])
        XCTAssertEqual(reopened.foods.map(\.sourceRecordID), ["F007661"])
        // 659 kJ (157.5 kcal), 3.1 g protein, 34.7 g available carbohydrate, 0.2 g fat per 100 g, for 190 g.
        XCTAssertEqual(reopened.nutritionEstimate.calories, "299 kcal")
        XCTAssertEqual(reopened.nutritionEstimate.protein, "5.9 g")
        XCTAssertEqual(reopened.nutritionEstimate.carbohydrates, "65.9 g")
        XCTAssertEqual(reopened.nutritionEstimate.fat, "0.4 g")
    }

    /// AUSNUT F009009: 647 kJ (154.6 kcal), 7.2 g protein, 23 g available carbohydrate, 3.2 g fat per 100 g,
    /// for 3 pieces of 33 g.
    private func assertShowsThreeSalmonSushiPieces(
        _ estimate: PresentedNutritionEstimate,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(estimate.label, "Approximate nutrition estimate", file: file, line: line)
        XCTAssertEqual(estimate.calories, "153 kcal", file: file, line: line)
        XCTAssertEqual(estimate.protein, "7.1 g", file: file, line: line)
        XCTAssertEqual(estimate.carbohydrates, "22.8 g", file: file, line: line)
        XCTAssertEqual(estimate.fat, "3.2 g", file: file, line: line)
    }

    /// AUSNUT F008589: 356 kJ (85.1 kcal), 4.8 g protein, 8 g available carbohydrate, 3.5 g fat per 100 g, for
    /// 400 g.
    private func assertShowsFourHundredGramsOfPrawnLaksa(
        _ estimate: PresentedNutritionEstimate,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(estimate.label, "Approximate nutrition estimate", file: file, line: line)
        XCTAssertEqual(estimate.calories, "340 kcal", file: file, line: line)
        XCTAssertEqual(estimate.protein, "19.2 g", file: file, line: line)
        XCTAssertEqual(estimate.carbohydrates, "32 g", file: file, line: line)
        XCTAssertEqual(estimate.fat, "14 g", file: file, line: line)
    }

    /// The app's HTTP gateway, with each request it sends answered by the backend's food search in-process.
    private func gateway(fdcSearchReply: String, fdcFoodsReply: String = "[]") throws -> HTTPMealAnalysisGateway {
        let foodSearch = FoodSearchService(
            credential: ProviderCredential(apiKey: FDCFixtures.testKey),
            transport: ScriptedFoodDataCentralTransport(
                search: .response(statusCode: 200, body: fdcSearchReply),
                foods: .response(statusCode: 200, body: fdcFoodsReply)
            ),
            ausnut: try Self.ausnut.get()
        )
        return HTTPMealAnalysisGateway(backendURL: URL(string: "http://127.0.0.1:8080")!) { request in
            XCTAssertEqual(request.url?.path, FoodSearchEndpoint.path)
            let reply = await foodSearch.handle(requestBody: request.httpBody ?? Data())
            let response = HTTPURLResponse(
                url: request.url!, statusCode: reply.statusCode, httpVersion: nil,
                headerFields: ["Content-Type": reply.contentType]
            )!
            return (reply.body, response)
        }
    }
}
