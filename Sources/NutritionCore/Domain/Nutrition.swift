import Foundation

/// Calories, protein, carbohydrates and fat for 100 grams of a food.
/// Every food (documented source record or custom food) is normalized to this basis.
public struct NutrientsPer100g: Codable, Hashable, Sendable {
    /// Kilocalories per 100 g.
    public var calories: Double
    /// Grams of protein per 100 g.
    public var protein: Double
    /// Grams of carbohydrates per 100 g.
    public var carbohydrates: Double
    /// Grams of fat per 100 g.
    public var fat: Double

    public init(calories: Double, protein: Double, carbohydrates: Double, fat: Double) {
        self.calories = calories
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
    }
}

/// An approximate amount of calories, protein, carbohydrates and fat attributed to pictured food.
/// Values are unrounded; rounding happens only at presentation (`PresentedNutritionEstimate`).
public struct NutritionEstimate: Hashable, Sendable {
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

    public static let zero = NutritionEstimate(calories: 0, protein: 0, carbohydrates: 0, fat: 0)

    /// Deterministic calculation: per-100 g values scaled to the reviewed gram amount.
    public init(_ nutrients: NutrientsPer100g, grams: Double) {
        let factor = grams / 100
        self.init(
            calories: nutrients.calories * factor,
            protein: nutrients.protein * factor,
            carbohydrates: nutrients.carbohydrates * factor,
            fat: nutrients.fat * factor
        )
    }

    public static func + (lhs: NutritionEstimate, rhs: NutritionEstimate) -> NutritionEstimate {
        NutritionEstimate(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbohydrates: lhs.carbohydrates + rhs.carbohydrates,
            fat: lhs.fat + rhs.fat
        )
    }
}

extension Sequence where Element == NutritionEstimate {
    /// The combined estimate of all elements.
    public func total() -> NutritionEstimate {
        reduce(.zero, +)
    }
}
