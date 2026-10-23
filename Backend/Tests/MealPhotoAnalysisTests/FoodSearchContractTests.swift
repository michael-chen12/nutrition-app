import AnalysisContract
import AUSNUT
import Foundation
import MealPhotoAnalysis
import XCTest

/// The backend's food search contract: the app posts a query; the backend looks it up in USDA FoodData Central
/// with the key only it holds, and in the packaged AUSNUT 2023 data, and answers with documented foods in the
/// shared `AnalysisContract`. FDC replies and AUSNUT data are hand-built fixtures: no test calls the live API.
final class FoodSearchContractTests: XCTestCase {
    private func makeService(
        _ transport: ScriptedFoodDataCentralTransport,
        credential: ProviderCredential? = ProviderCredential(apiKey: FDCFixtures.testKey),
        ausnut: AUSNUTDataset = AUSNUTFixtures.noFoods
    ) -> FoodSearchService {
        FoodSearchService(credential: credential, transport: transport, ausnut: ausnut)
    }

    private var riceTransport: ScriptedFoodDataCentralTransport {
        ScriptedFoodDataCentralTransport(
            search: .response(statusCode: 200, body: FDCFixtures.riceSearchReply),
            foods: .response(statusCode: 200, body: FDCFixtures.riceFoodsReply)
        )
    }

    func test_searchAnswersWithDocumentedFoodsInRelevanceOrderWithSourceFDCIDNutrientsAndServingUnits() async throws {
        let reply = await makeService(riceTransport).handle(requestBody: FDCFixtures.searchRequestBody("rice white cooked"))

        XCTAssertEqual(reply.statusCode, 200)
        XCTAssertEqual(reply.contentType, "application/json")
        let response = try JSONDecoder().decode(FoodSearchResponse.self, from: reply.body)
        XCTAssertEqual(response, FoodSearchResponse(foods: [
            DocumentedFood(
                name: "Rice, white, cooked, no added fat",
                sourceName: "USDA FoodData Central",
                recordID: "2708346",
                nutrientsPer100g: DocumentedNutrients(calories: 129, protein: 2.66, carbohydrates: 27.9, fat: 0.28),
                servingUnits: [DocumentedServingUnit(name: "cup", quantityBasis: 1, gramWeight: 174)]
            ),
            DocumentedFood(
                name: "Rice, white, long-grain, regular, enriched, cooked",
                sourceName: "USDA FoodData Central",
                recordID: "168878",
                nutrientsPer100g: DocumentedNutrients(calories: 130, protein: 2.69, carbohydrates: 28.17, fat: 0.28),
                servingUnits: [DocumentedServingUnit(name: "cup", quantityBasis: 1, gramWeight: 158)]
            ),
            // 2708347 lacks a fat value, so it cannot back a nutrition estimate and is left out.
        ]))
    }

    // MARK: FoodData Central and AUSNUT together

    func test_resultsFromBothSourcesAreInterleavedSoOverlappingFoodsAppearSideBySideWithTheirSource() async throws {
        let reply = await makeService(riceTransport, ausnut: AUSNUTFixtures.rice)
            .handle(requestBody: FDCFixtures.searchRequestBody("rice white cooked"))

        XCTAssertEqual(reply.statusCode, 200)
        let foods = try JSONDecoder().decode(FoodSearchResponse.self, from: reply.body).foods
        XCTAssertEqual(foods.map { "\($0.sourceName) \($0.recordID)" }, [
            "USDA FoodData Central 2708346",
            "FSANZ AUSNUT 2023 F007661",
            "USDA FoodData Central 168878",
            "FSANZ AUSNUT 2023 F007662",
        ])
        XCTAssertEqual(foods.map(\.name), [
            "Rice, white, cooked, no added fat",
            "Rice, white, cooked",
            "Rice, white, long-grain, regular, enriched, cooked",
            "Rice, white, cooked with coconut milk",
        ])
    }

    func test_whenFDCHasNoMatchAUSNUTFoodsAreAnsweredUpToTheResultLimit() async throws {
        let transport = ScriptedFoodDataCentralTransport(
            search: .response(statusCode: 200, body: #"{ "totalHits": 0, "foods": [] }"#)
        )

        let reply = await makeService(transport, ausnut: AUSNUTFixtures.sushi(count: 12))
            .handle(requestBody: FDCFixtures.searchRequestBody("sushi"))

        XCTAssertEqual(reply.statusCode, 200)
        let foods = try JSONDecoder().decode(FoodSearchResponse.self, from: reply.body).foods
        XCTAssertEqual(foods.map(\.recordID), (1...10).map { String(format: "F9%05d", $0) })
        XCTAssertEqual(Set(foods.map(\.sourceName)), ["FSANZ AUSNUT 2023"])
        XCTAssertEqual(transport.sentRequests.count, 1, "No FDC records to fetch")
    }

    func test_searchThenFetchesFullRecordsWithTheKeyOnlyInARequestHeader() async throws {
        let transport = riceTransport

        _ = await makeService(transport).handle(requestBody: FDCFixtures.searchRequestBody("  rice white cooked "))

        XCTAssertEqual(transport.sentRequests.count, 2)
        let (search, foods) = (transport.sentRequests[0], transport.sentRequests[1])
        XCTAssertEqual(search.method, "POST")
        XCTAssertEqual(search.url.absoluteString, "https://api.nal.usda.gov/fdc/v1/foods/search")
        XCTAssertEqual(foods.method, "POST")
        XCTAssertEqual(foods.url.absoluteString, "https://api.nal.usda.gov/fdc/v1/foods")
        for request in [search, foods] {
            XCTAssertEqual(request.headers["X-Api-Key"], FDCFixtures.testKey)
            XCTAssertEqual(request.headers["Content-Type"], "application/json")
            XCTAssertFalse(request.url.absoluteString.contains(FDCFixtures.testKey), "The key never goes in a URL")
            XCTAssertFalse(String(decoding: request.body, as: UTF8.self).contains(FDCFixtures.testKey))
        }
        let searchBody = try XCTUnwrap(JSONSerialization.jsonObject(with: search.body) as? [String: Any])
        XCTAssertEqual(searchBody["query"] as? String, "rice white cooked")
        XCTAssertEqual(searchBody["pageSize"] as? Int, FoodSearchService.maximumResults)
        XCTAssertEqual(searchBody["dataType"] as? [String], ["Foundation", "SR Legacy", "Survey (FNDDS)"])
        let foodsBody = try XCTUnwrap(JSONSerialization.jsonObject(with: foods.body) as? [String: Any])
        XCTAssertEqual(foodsBody["fdcIds"] as? [Int], [2708346, 168878, 2708347])
        XCTAssertEqual(foodsBody["format"] as? String, "full")
    }

    func test_noHitsAnswerWithNoFoodsWithoutFetchingRecords() async throws {
        let transport = ScriptedFoodDataCentralTransport(
            search: .response(statusCode: 200, body: #"{ "totalHits": 0, "foods": [] }"#)
        )

        let reply = await makeService(transport).handle(requestBody: FDCFixtures.searchRequestBody("zzzz"))

        XCTAssertEqual(reply.statusCode, 200)
        XCTAssertEqual(try JSONDecoder().decode(FoodSearchResponse.self, from: reply.body), FoodSearchResponse(foods: []))
        XCTAssertEqual(transport.sentRequests.count, 1)
    }

    // MARK: Failures

    func test_unusableQueriesAreRefusedWithoutCallingTheSource() async throws {
        let transport = riceTransport
        let service = makeService(transport)
        let bodies = [
            Data("not json".utf8),
            FDCFixtures.searchRequestBody("   "),
            FDCFixtures.searchRequestBody(String(repeating: "rice ", count: 40)),
        ]

        for body in bodies {
            let reply = await service.handle(requestBody: body)
            XCTAssertEqual(reply.statusCode, 400)
            XCTAssertEqual(try JSONDecoder().decode(AnalysisErrorResponse.self, from: reply.body).code, .invalidRequest)
        }
        XCTAssertTrue(transport.sentRequests.isEmpty)
    }

    func test_withoutAKeyAndNoAUSNUTMatchTheBackendAnswersNotConfiguredAndCallsNothing() async throws {
        let transport = riceTransport

        let reply = await makeService(transport, credential: nil).handle(requestBody: FDCFixtures.searchRequestBody("rice"))

        XCTAssertEqual(reply.statusCode, 503)
        XCTAssertEqual(try JSONDecoder().decode(AnalysisErrorResponse.self, from: reply.body).code, .notConfigured)
        XCTAssertTrue(transport.sentRequests.isEmpty)
    }

    func test_withoutAKeyAUSNUTFoodsAreAnsweredWithoutCallingFDC() async throws {
        let transport = riceTransport

        let reply = await makeService(transport, credential: nil, ausnut: AUSNUTFixtures.rice)
            .handle(requestBody: FDCFixtures.searchRequestBody("rice white cooked"))

        XCTAssertEqual(reply.statusCode, 200)
        let foods = try JSONDecoder().decode(FoodSearchResponse.self, from: reply.body).foods
        XCTAssertEqual(foods.map(\.recordID), ["F007661", "F007662"])
        XCTAssertTrue(transport.sentRequests.isEmpty)
    }

    func test_whenFDCFailsAUSNUTFoodsAreAnsweredWithoutEchoingTheKeyOrTheSourceReply() async throws {
        for (transport, _, _) in fdcFailures {
            let reply = await makeService(transport, ausnut: AUSNUTFixtures.rice)
                .handle(requestBody: FDCFixtures.searchRequestBody("rice white cooked"))

            XCTAssertEqual(reply.statusCode, 200)
            let foods = try JSONDecoder().decode(FoodSearchResponse.self, from: reply.body).foods
            XCTAssertEqual(foods.map(\.recordID), ["F007661", "F007662"])
            let text = String(decoding: reply.body, as: UTF8.self)
            XCTAssertFalse(text.contains(FDCFixtures.testKey), "Reply leaked the key: \(text)")
            XCTAssertFalse(text.contains("API_KEY_INVALID"), "Reply forwarded the source's reply: \(text)")
        }
    }

    func test_whenFDCFailsAndAUSNUTHasNoMatchFailuresAreMappedWithoutEchoingTheKeyOrTheSourceReply() async throws {
        for (transport, status, code) in fdcFailures {
            let reply = await makeService(transport).handle(requestBody: FDCFixtures.searchRequestBody("rice"))

            XCTAssertEqual(reply.statusCode, status)
            XCTAssertEqual(try JSONDecoder().decode(AnalysisErrorResponse.self, from: reply.body).code, code)
            let text = String(decoding: reply.body, as: UTF8.self)
            XCTAssertFalse(text.contains(FDCFixtures.testKey), "Reply leaked the key: \(text)")
            XCTAssertFalse(text.contains("API_KEY_INVALID"), "Reply forwarded the source's reply: \(text)")
        }
    }

    /// FDC failing in each way, with the reply the backend gives when nothing else matches. Some carry the key.
    private var fdcFailures: [(ScriptedFoodDataCentralTransport, Int, AnalysisErrorCode)] {
        let keyInError = SimulatedNetworkError(description: "connection reset; X-Api-Key: \(FDCFixtures.testKey)")
        let keyInReply = #"{ "error": { "code": "API_KEY_INVALID", "message": "\#(FDCFixtures.testKey) is invalid" } }"#
        return [
            (ScriptedFoodDataCentralTransport(search: .transportError(keyInError)), 502, .providerUnavailable),
            (ScriptedFoodDataCentralTransport(search: .response(statusCode: 403, body: keyInReply)), 502, .providerUnavailable),
            (ScriptedFoodDataCentralTransport(search: .response(statusCode: 429, body: keyInReply)), 502, .providerUnavailable),
            (
                ScriptedFoodDataCentralTransport(
                    search: .response(statusCode: 200, body: FDCFixtures.riceSearchReply),
                    foods: .response(statusCode: 500, body: keyInReply)
                ),
                502, .providerUnavailable
            ),
            (ScriptedFoodDataCentralTransport(search: .response(statusCode: 200, body: keyInReply)), 502, .malformedProviderOutput),
            (
                ScriptedFoodDataCentralTransport(
                    search: .response(statusCode: 200, body: FDCFixtures.riceSearchReply),
                    foods: .response(statusCode: 200, body: #"{ "not": "a list" }"#)
                ),
                502, .malformedProviderOutput
            ),
        ]
    }

    func test_keyComesFromTheBackendEnvironmentAndIsNeverPrinted() {
        let configuration = FoodDataCentralConfiguration(environment: ["FDC_API_KEY": FDCFixtures.testKey])

        XCTAssertNotNil(configuration.credential)
        XCTAssertFalse(String(describing: configuration).contains(FDCFixtures.testKey))
        XCTAssertNil(FoodDataCentralConfiguration(environment: [:]).credential)
        XCTAssertNil(FoodDataCentralConfiguration(environment: ["FDC_API_KEY": " "]).credential)
    }
}
