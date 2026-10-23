import Foundation

// Food search in the wire contract: the app asks the backend for documented food records matching a query.
// The backend looks them up in its documented nutrition sources: USDA FoodData Central, which needs an API key
// (so the key stays on the backend), and the packaged FSANZ AUSNUT 2023 data. Unlike photo analysis, these
// replies do carry nutrient values: each comes from a documented record, named with its source and record ID.

/// Where the backend serves food search: `POST` a `FoodSearchRequest` as JSON; the reply is a
/// `FoodSearchResponse` (HTTP 200) or an `AnalysisErrorResponse` (any other status).
public enum FoodSearchEndpoint {
    public static let path = "/v1/food-searches"
    public static let method = "POST"
}

public struct FoodSearchRequest: Codable, Hashable, Sendable {
    /// What the person (or a photo suggestion's search query) is looking for, e.g. "rice white cooked".
    public var query: String

    public init(query: String) {
        self.query = query
    }
}

/// Documented food records matching a search, most relevant first. Records the source has that cannot back a
/// nutrition estimate (e.g. missing a nutrient, or reported per 100 mL) are left out.
public struct FoodSearchResponse: Codable, Hashable, Sendable {
    public var foods: [DocumentedFood]

    public init(foods: [DocumentedFood]) {
        self.foods = foods
    }
}

/// One record from a documented nutrition source, normalized to nutrients per 100 g.
public struct DocumentedFood: Codable, Hashable, Sendable {
    public var name: String
    /// The source's name, shown to the person, e.g. "USDA FoodData Central".
    public var sourceName: String
    /// The record's identifier within that source, e.g. an FDC ID.
    public var recordID: String
    public var nutrientsPer100g: DocumentedNutrients
    /// Household measures the source documents for this food, in the source's order.
    public var servingUnits: [DocumentedServingUnit]

    public init(
        name: String,
        sourceName: String,
        recordID: String,
        nutrientsPer100g: DocumentedNutrients,
        servingUnits: [DocumentedServingUnit] = []
    ) {
        self.name = name
        self.sourceName = sourceName
        self.recordID = recordID
        self.nutrientsPer100g = nutrientsPer100g
        self.servingUnits = servingUnits
    }
}

/// Calories (kcal) and grams of protein, carbohydrates and fat in 100 g of a documented food.
public struct DocumentedNutrients: Codable, Hashable, Sendable {
    public var calories: Double
    public var protein: Double
    public var carbohydrates: Double
    public var fat: Double

    public init(calories: Double, protein: Double, carbohydrates: Double, fat: Double) {
        self.calories = calories
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
    }
}

/// A household measure as the source documents it: `quantityBasis` of the unit weighs `gramWeight` grams.
/// Either is nil when the source does not give it; it is never filled in.
public struct DocumentedServingUnit: Codable, Hashable, Sendable {
    /// e.g. "cup" or "cup, chopped".
    public var name: String
    public var quantityBasis: Double?
    public var gramWeight: Double?

    public init(name: String, quantityBasis: Double?, gramWeight: Double?) {
        self.name = name
        self.quantityBasis = quantityBasis
        self.gramWeight = gramWeight
    }
}
