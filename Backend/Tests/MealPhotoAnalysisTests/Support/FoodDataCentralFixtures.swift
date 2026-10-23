import AnalysisContract
import Foundation
import MealPhotoAnalysis

/// Stands in for USDA FoodData Central over HTTP: answers each request by its path (`/foods/search` or
/// `/foods`) with a fixture and records what the backend sent, so no test reaches the live API or needs a key.
final class ScriptedFoodDataCentralTransport: ProviderTransport, @unchecked Sendable {
    var searchReply: RecordingProviderTransport.Reply
    var foodsReply: RecordingProviderTransport.Reply
    private(set) var sentRequests: [ProviderRequest] = []

    init(
        search: RecordingProviderTransport.Reply,
        foods: RecordingProviderTransport.Reply = .response(statusCode: 200, body: "[]")
    ) {
        searchReply = search
        foodsReply = foods
    }

    func send(_ request: ProviderRequest) async throws -> ProviderResponse {
        sentRequests.append(request)
        switch request.url.path.hasSuffix("/foods/search") ? searchReply : foodsReply {
        case .response(let statusCode, let body):
            return ProviderResponse(statusCode: statusCode, body: Data(body.utf8))
        case .transportError(let error):
            throw error
        }
    }
}

/// Hand-built from the JSON shapes in the FDC API guide (https://fdc.nal.usda.gov/api-guide/).
/// Values are illustrative, not copied from live records.
enum FDCFixtures {
    static let testKey = "FDC-TEST-not-a-real-key-456"

    static func searchRequestBody(_ query: String) -> Data {
        try! JSONEncoder().encode(FoodSearchRequest(query: query))
    }

    /// `POST /v1/foods/search` reply (abridged search-result format) for "rice white cooked": three hits in
    /// relevance order.
    static let riceSearchReply = """
    {
      "totalHits": 3, "currentPage": 1, "totalPages": 1,
      "foodSearchCriteria": { "query": "rice white cooked", "pageNumber": 1 },
      "foods": [
        { "fdcId": 2708346, "description": "Rice, white, cooked, no added fat", "dataType": "Survey (FNDDS)",
          "foodNutrients": [ { "nutrientId": 1008, "nutrientName": "Energy", "unitName": "KCAL", "value": 129 } ] },
        { "fdcId": 168878, "description": "Rice, white, long-grain, regular, enriched, cooked",
          "dataType": "SR Legacy", "foodNutrients": [] },
        { "fdcId": 2708347, "description": "Rice, white, cooked, fat added", "dataType": "Survey (FNDDS)",
          "foodNutrients": [] }
      ]
    }
    """

    /// `POST /v1/foods` reply (full format) for those three FDC IDs, in a different order than the search.
    /// 2708347 has no fat value, so it cannot back a nutrition estimate.
    static let riceFoodsReply = """
    [
      { "fdcId": 168878, "description": "Rice, white, long-grain, regular, enriched, cooked", "dataType": "SR Legacy",
        "foodNutrients": [
          \(nutrient(1003, 2.69)), \(nutrient(1004, 0.28)), \(nutrient(1005, 28.17)), \(nutrient(1008, 130))
        ],
        "foodPortions": [ { "id": 85380, "amount": 1, "modifier": "cup", "gramWeight": 158 } ] },
      { "fdcId": 2708347, "description": "Rice, white, cooked, fat added", "dataType": "Survey (FNDDS)",
        "foodNutrients": [ \(nutrient(1003, 2.6)), \(nutrient(1005, 27.3)), \(nutrient(1008, 147)) ],
        "foodPortions": [] },
      { "fdcId": 2708346, "description": "Rice, white, cooked, no added fat", "dataType": "Survey (FNDDS)",
        "foodNutrients": [
          \(nutrient(1003, 2.66)), \(nutrient(1004, 0.28)), \(nutrient(1005, 27.9)), \(nutrient(1008, 129))
        ],
        "foodPortions": [
          { "id": 1, "amount": 1, "gramWeight": 174, "sequenceNumber": 1, "modifier": "cup",
            "measureUnit": { "id": 9999, "name": "undetermined", "abbreviation": "undetermined" } },
          { "id": 2, "modifier": "90000", "portionDescription": "Quantity not specified", "gramWeight": 174,
            "sequenceNumber": 2, "measureUnit": { "id": 9999, "name": "undetermined", "abbreviation": "undetermined" } }
        ] }
    ]
    """

    private static func nutrient(_ id: Int, _ amount: Double) -> String {
        #"{ "type": "FoodNutrient", "nutrient": { "id": \#(id) }, "amount": \#(amount) }"#
    }
}
