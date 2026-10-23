import Foundation

/// A USDA FoodData Central food record, as documented in the FDC API guide
/// (https://fdc.nal.usda.gov/api-guide/).
///
/// This adapter is how FDC records enter the app's shared food representation: `food()` normalizes a record
/// to `Food` (nutrients per 100 g plus a `SourceReference` naming the source and its FDC ID). Additional
/// regional sources get their own record adapter producing the same `Food`, so review, calculation,
/// persistence and source display never depend on a particular source's format.
public struct FoodDataCentralRecord: Decodable, Hashable, Sendable {
    /// Name shown to the person for every food from this source.
    public static let sourceName = "USDA FoodData Central"

    public var fdcId: Int
    public var description: String
    public var foodNutrients: [Nutrient]
    /// Branded foods only. When it is a volume ("ml" in the API, "MLT" in downloads), `foodNutrients`
    /// are per 100 mL instead of per 100 g.
    public var servingSizeUnit: String?
    /// Documented household measures with their gram weight (Foundation, SR Legacy and Survey records).
    public var foodPortions: [FoodPortion]?

    /// One `foodPortions` entry: `amount` of a unit (named by `measureUnit`, or by `modifier` when the measure
    /// unit is "undetermined") weighs `gramWeight` grams.
    public struct FoodPortion: Decodable, Hashable, Sendable {
        public var amount: Double?
        public var modifier: String?
        public var gramWeight: Double?
        public var measureUnit: MeasureUnit?

        public struct MeasureUnit: Decodable, Hashable, Sendable {
            public var name: String?
        }

        /// The portion as a serving unit, or nil when it names no familiar unit (e.g. Survey records'
        /// numeric modifier codes). A missing amount or gram weight is kept unknown, never filled in.
        var servingUnit: ServingUnit? {
            let measureName = measureUnit?.name.map(Self.trimmed).flatMap { $0.isEmpty ? nil : $0 }
            let modifierText = modifier.map(Self.trimmed).flatMap { text -> String? in
                text.isEmpty || Double(text) != nil ? nil : text
            }
            let name: String
            if let measureName, measureName.lowercased() != "undetermined" {
                name = modifierText.map { "\(measureName), \($0)" } ?? measureName
            } else if let modifierText {
                name = modifierText
            } else {
                return nil
            }
            return ServingUnit(name: name, quantityBasis: amount, gramWeight: gramWeight)
        }

        private static func trimmed(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// One `foodNutrients` entry. Accepts both documented shapes: the full food format
    /// (`nutrient.id` + `amount`) and the search-result format (`nutrientId` + `value`).
    public struct Nutrient: Decodable, Hashable, Sendable {
        /// FDC nutrient id, e.g. 1003 for protein.
        public var nutrientID: Int
        public var amount: Double

        private enum CodingKeys: String, CodingKey {
            case nutrient, amount, nutrientId, value
        }

        private struct NutrientDefinition: Decodable {
            var id: Int
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let definition = try container.decodeIfPresent(NutrientDefinition.self, forKey: .nutrient) {
                nutrientID = definition.id
                amount = try container.decode(Double.self, forKey: .amount)
            } else {
                nutrientID = try container.decode(Int.self, forKey: .nutrientId)
                amount = try container.decode(Double.self, forKey: .value)
            }
        }
    }

    /// The record normalized to the shared per-100 g representation with its source reference.
    public func food() throws -> Food {
        if let unit = servingSizeUnit?.lowercased(), unit == "ml" || unit == "mlt" {
            throw FoodDataCentralError.notPer100Grams(fdcId: fdcId)
        }
        return Food(
            name: description,
            nutrientsPer100g: NutrientsPer100g(
                calories: try amount(ofFirstOf: NutrientID.energyInPreferenceOrder),
                protein: try amount(ofFirstOf: [NutrientID.protein]),
                carbohydrates: try amount(ofFirstOf: [NutrientID.carbohydrateByDifference]),
                fat: try amount(ofFirstOf: [NutrientID.totalFat])
            ),
            source: .documented(SourceReference(sourceName: Self.sourceName, recordID: String(fdcId))),
            servingUnits: (foodPortions ?? []).compactMap(\.servingUnit)
        )
    }

    /// FDC nutrient ids used for a nutrition estimate. FDC reports these per 100 g of food.
    private enum NutrientID {
        static let protein = 1003
        static let totalFat = 1004
        static let carbohydrateByDifference = 1005
        /// "Energy" (kcal); Foundation records may instead report only Atwater specific (2048)
        /// or general (2047) factor energy, in kcal.
        static let energyInPreferenceOrder = [1008, 2048, 2047]
    }

    private func amount(ofFirstOf nutrientIDs: [Int]) throws -> Double {
        for id in nutrientIDs {
            if let nutrient = foodNutrients.first(where: { $0.nutrientID == id }) { return nutrient.amount }
        }
        throw FoodDataCentralError.missingNutrient(fdcId: fdcId, nutrientID: nutrientIDs[0])
    }
}

/// A `POST /v1/foods/search` (or `GET /v1/foods/search`) response from FoodData Central.
public struct FoodDataCentralSearchResponse: Decodable, Hashable, Sendable {
    public var foods: [FoodDataCentralRecord]

    /// The records that can back a nutrition estimate, normalized to the shared representation.
    /// Records that cannot be normalized (e.g. missing a needed nutrient) are not suitable matches and are left out.
    public func suitableFoods() -> [Food] {
        foods.compactMap { try? $0.food() }
    }
}

public enum FoodDataCentralError: Error, Equatable {
    /// The record lacks a nutrient needed for a nutrition estimate, so it is not a suitable match.
    case missingNutrient(fdcId: Int, nutrientID: Int)
    /// The record's nutrients are per 100 mL (a branded liquid), so they cannot be normalized per 100 g.
    case notPer100Grams(fdcId: Int)
}
