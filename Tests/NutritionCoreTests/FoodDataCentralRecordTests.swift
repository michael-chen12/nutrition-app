import Foundation
import NutritionCore
import XCTest

/// USDA FoodData Central records, normalized to the shared per-100 g food representation.
/// Fixtures are hand-built from the JSON shapes documented in the FDC API guide
/// (https://fdc.nal.usda.gov/api-guide/); no dataset is downloaded and the live API is never called.
final class FoodDataCentralRecordTests: XCTestCase {
    func test_fullFoodRecordBecomesAFoodPer100gWithItsSourceNameAndFDCID() throws {
        let record = try JSONDecoder().decode(FoodDataCentralRecord.self, from: Data(Self.srLegacyRiceRecord.utf8))

        let food = try record.food()

        XCTAssertEqual(food, Food(
            name: "Rice, white, long-grain, regular, enriched, cooked",
            nutrientsPer100g: NutrientsPer100g(calories: 130, protein: 2.69, carbohydrates: 28.17, fat: 0.28),
            source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "168878"))
        ))
    }

    func test_searchResponseYieldsOnlyRecordsWithAllFourNutrients() throws {
        let response = try JSONDecoder().decode(
            FoodDataCentralSearchResponse.self, from: Data(Self.riceSearchResponse.utf8)
        )

        XCTAssertEqual(response.suitableFoods(), [
            Food(
                name: "Rice, white, cooked, no added fat",
                nutrientsPer100g: NutrientsPer100g(calories: 129, protein: 2.66, carbohydrates: 27.9, fat: 0.28),
                source: .documented(SourceReference(sourceName: "USDA FoodData Central", recordID: "2708346"))
            ),
        ])
    }

    func test_foundationRecordWithoutEnergyUsesAtwaterSpecificFactorEnergy() throws {
        let record = try JSONDecoder().decode(
            FoodDataCentralRecord.self, from: Data(Self.foundationHummusRecord.utf8)
        )

        XCTAssertEqual(try record.food().nutrientsPer100g.calories, 222)
    }

    func test_brandedLiquidReportedPer100mlIsNotAGramBasedRecord() throws {
        for unit in ["ml", "MLT"] {
            let json = Self.brandedLiquidRecord.replacingOccurrences(of: "SERVING_UNIT", with: unit)
            let record = try JSONDecoder().decode(FoodDataCentralRecord.self, from: Data(json.utf8))

            XCTAssertThrowsError(try record.food()) { error in
                XCTAssertEqual(error as? FoodDataCentralError, .notPer100Grams(fdcId: 2041155))
            }
        }
    }

    func test_brandedSolidReportedPer100gIsNormalized() throws {
        let json = Self.brandedLiquidRecord.replacingOccurrences(of: "SERVING_UNIT", with: "g")
        let record = try JSONDecoder().decode(FoodDataCentralRecord.self, from: Data(json.utf8))

        XCTAssertEqual(try record.food().nutrientsPer100g.calories, 42)
    }

    // MARK: Fixtures

    /// Branded food (full format). Branded `foodNutrients` are per 100 g, or per 100 mL when the serving
    /// size unit is a volume. Values are illustrative.
    static let brandedLiquidRecord = """
    {
      "fdcId": 2041155, "description": "ORANGE JUICE", "dataType": "Branded", "brandOwner": "Example Farms",
      "servingSize": 240, "servingSizeUnit": "SERVING_UNIT",
      "foodNutrients": [
        { "type": "FoodNutrient", "nutrient": { "id": 1003, "number": "203", "name": "Protein", "unitName": "g" }, "amount": 0.83 },
        { "type": "FoodNutrient", "nutrient": { "id": 1004, "number": "204", "name": "Total lipid (fat)", "unitName": "g" }, "amount": 0 },
        { "type": "FoodNutrient", "nutrient": { "id": 1005, "number": "205", "name": "Carbohydrate, by difference", "unitName": "g" }, "amount": 10 },
        { "type": "FoodNutrient", "nutrient": { "id": 1008, "number": "208", "name": "Energy", "unitName": "kcal" }, "amount": 42 }
      ]
    }
    """

    /// `GET /v1/food/321358` (Foundation, full format). Foundation records can report energy only via
    /// Atwater general (2047) and specific (2048) factors. Values are illustrative.
    static let foundationHummusRecord = """
    {
      "fdcId": 321358, "description": "Hummus, commercial", "dataType": "Foundation",
      "foodNutrients": [
        { "type": "FoodNutrient", "nutrient": { "id": 1003, "number": "203", "name": "Protein", "unitName": "g" }, "amount": 7.35 },
        { "type": "FoodNutrient", "nutrient": { "id": 1004, "number": "204", "name": "Total lipid (fat)", "unitName": "g" }, "amount": 17.1 },
        { "type": "FoodNutrient", "nutrient": { "id": 1005, "number": "205", "name": "Carbohydrate, by difference", "unitName": "g" }, "amount": 14.9 },
        { "type": "FoodNutrient", "nutrient": { "id": 2047, "number": "957", "name": "Energy (Atwater General Factors)", "unitName": "kcal" }, "amount": 229 },
        { "type": "FoodNutrient", "nutrient": { "id": 2048, "number": "958", "name": "Energy (Atwater Specific Factors)", "unitName": "kcal" }, "amount": 222 }
      ]
    }
    """

    /// `POST /v1/foods/search` response (search-result format). The second record has no fat value.
    /// Values are illustrative.
    static let riceSearchResponse = """
    {
      "totalHits": 2, "currentPage": 1, "totalPages": 1,
      "foodSearchCriteria": { "query": "rice", "pageNumber": 1 },
      "foods": [
        { "fdcId": 2708346, "description": "Rice, white, cooked, no added fat",
          "dataType": "Survey (FNDDS)", "foodCode": "56205005",
          "foodNutrients": [
            { "nutrientId": 1003, "nutrientName": "Protein", "nutrientNumber": "203", "unitName": "G", "value": 2.66 },
            { "nutrientId": 1004, "nutrientName": "Total lipid (fat)", "nutrientNumber": "204", "unitName": "G", "value": 0.28 },
            { "nutrientId": 1005, "nutrientName": "Carbohydrate, by difference", "nutrientNumber": "205", "unitName": "G", "value": 27.9 },
            { "nutrientId": 1008, "nutrientName": "Energy", "nutrientNumber": "208", "unitName": "KCAL", "value": 129 }
          ] },
        { "fdcId": 2708347, "description": "Rice, white, cooked, fat added",
          "dataType": "Survey (FNDDS)", "foodCode": "56205006",
          "foodNutrients": [
            { "nutrientId": 1003, "nutrientName": "Protein", "nutrientNumber": "203", "unitName": "G", "value": 2.6 },
            { "nutrientId": 1005, "nutrientName": "Carbohydrate, by difference", "nutrientNumber": "205", "unitName": "G", "value": 27.3 },
            { "nutrientId": 1008, "nutrientName": "Energy", "nutrientNumber": "208", "unitName": "KCAL", "value": 147 }
          ] }
      ]
    }
    """

    /// `GET /v1/food/168878` (full format), trimmed to a few nutrients.
    static let srLegacyRiceRecord = """
    {
      "fdcId": 168878,
      "description": "Rice, white, long-grain, regular, enriched, cooked",
      "dataType": "SR Legacy",
      "publicationDate": "4/1/2019",
      "foodNutrients": [
        { "type": "FoodNutrient", "id": 1283674,
          "nutrient": { "id": 1003, "number": "203", "name": "Protein", "rank": 600, "unitName": "g" },
          "amount": 2.69 },
        { "type": "FoodNutrient", "id": 1283675,
          "nutrient": { "id": 1004, "number": "204", "name": "Total lipid (fat)", "rank": 800, "unitName": "g" },
          "amount": 0.28 },
        { "type": "FoodNutrient", "id": 1283676,
          "nutrient": { "id": 1005, "number": "205", "name": "Carbohydrate, by difference", "rank": 1110, "unitName": "g" },
          "amount": 28.17 },
        { "type": "FoodNutrient", "id": 1283677,
          "nutrient": { "id": 1008, "number": "208", "name": "Energy", "rank": 300, "unitName": "kcal" },
          "amount": 130 },
        { "type": "FoodNutrient", "id": 1283678,
          "nutrient": { "id": 1062, "number": "268", "name": "Energy", "rank": 400, "unitName": "kJ" },
          "amount": 544 },
        { "type": "FoodNutrient", "id": 1283690,
          "nutrient": { "id": 1087, "number": "301", "name": "Calcium, Ca", "rank": 5300, "unitName": "mg" },
          "amount": 10 }
      ],
      "foodPortions": [
        { "id": 85380, "amount": 1, "modifier": "cup", "gramWeight": 158 }
      ]
    }
    """
}
