import Foundation
import NutritionCalibration
import NutritionCore

/// Hand-built reference meals. Reference values are worked out from the grams and per-100 g values below.
enum ReferenceMeals {
    static let consent = ParticipantConsent(
        participantCode: "P01",
        consentedOn: Date(timeIntervalSince1970: 1_792_000_000),
        coversPhotoAnalysisUpload: true
    )

    /// Weighed: rice 180 g (234 kcal, 4.86 g protein, 50.4 g carbohydrates, 0.54 g fat) and curry 250 g
    /// (375 kcal, 30 g protein, 15 g carbohydrates, 22.5 g fat). 609 kcal in all.
    static let riceAndCurry = ReferenceMeal(
        id: "pilot-001",
        split: .calibration,
        cuisine: "South Asian",
        dishType: "Rice plate",
        referenceMethod: .weighedPortions,
        consent: consent,
        photoFileNames: ["pilot-001-a.jpg"],
        referenceFoods: [
            ReferenceFood(
                id: "rice", name: "White rice, cooked", grams: 180,
                nutrientsPer100g: NutrientsPer100g(calories: 130, protein: 2.7, carbohydrates: 28, fat: 0.3),
                nutritionSource: "USDA FoodData Central 168878"
            ),
            ReferenceFood(
                id: "curry", name: "Chicken curry (recipe)", grams: 250,
                nutrientsPer100g: NutrientsPer100g(calories: 150, protein: 12, carbohydrates: 6, fat: 9),
                nutritionSource: "Recipe, per 100 g of the cooked pot"
            ),
        ]
    )
}
