import Foundation
import NutritionCore
import XCTest

/// Deterministic nutrient calculation: per-100 g values × reviewed grams, summed per meal entry,
/// rounded only when presented.
final class NutritionEstimateTests: XCTestCase {
    func test_mealEntryEstimateSumsEachReviewedFoodScaledToItsGrams() {
        let rice = ReviewedFood(
            food: Food(CustomFood(
                name: "Steamed rice",
                nutrientsPer100g: NutrientsPer100g(calories: 130, protein: 2.6, carbohydrates: 28, fat: 0.4)
            )),
            portion: Portion(grams: 150)
        )
        let egg = ReviewedFood(
            food: Food(CustomFood(
                name: "Fried egg",
                nutrientsPer100g: NutrientsPer100g(calories: 196, protein: 13.6, carbohydrates: 0.8, fat: 15)
            )),
            portion: Portion(grams: 50)
        )
        let entry = MealEntry(date: Date(timeIntervalSince1970: 0), reviewedFoods: [rice, egg])

        // Rice 195 kcal, 3.9 P, 42 C, 0.6 F; egg 98 kcal, 6.8 P, 0.4 C, 7.5 F.
        let shown = PresentedNutritionEstimate(entry.nutritionEstimate)
        XCTAssertEqual(shown.calories, "293 kcal")
        XCTAssertEqual(shown.protein, "10.7 g")
        XCTAssertEqual(shown.carbohydrates, "42.4 g")
        XCTAssertEqual(shown.fat, "8.1 g")
    }

    func test_presentationRoundsCaloriesToWholeKilocaloriesAndGramsToOneDecimal() {
        let shown = PresentedNutritionEstimate(
            NutritionEstimate(calories: 247.5, protein: 0, carbohydrates: 12.04, fat: 0.05)
        )

        XCTAssertEqual(shown.label, "Approximate nutrition estimate")
        XCTAssertEqual(shown.calories, "248 kcal")
        XCTAssertEqual(shown.protein, "0 g")
        XCTAssertEqual(shown.carbohydrates, "12 g")
        XCTAssertEqual(shown.fat, "0.1 g")
    }
}
