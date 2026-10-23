import Foundation
import NutritionCalibration
import NutritionCore

// Hand-built reference meals and evaluations shared by the report and pilot tests.

/// A calibration meal whose reference foods each weigh 100 g, so their per-100 g values are their nutrition.
func meal(
    _ id: String,
    split: ReferenceMeal.Split = .calibration,
    cuisine: String,
    dishType: String,
    foods: [ReferenceFood]
) -> ReferenceMeal {
    ReferenceMeal(
        id: id, split: split, cuisine: cuisine, dishType: dishType, referenceMethod: .weighedPortions,
        consent: ReferenceMeals.consent, photoFileNames: ["\(id).jpg"], referenceFoods: foods
    )
}

func food(_ id: String, calories: Double, protein: Double, carbohydrates: Double, fat: Double) -> ReferenceFood {
    ReferenceFood(
        id: id, name: id.capitalized, grams: 100,
        nutrientsPer100g: NutrientsPer100g(calories: calories, protein: protein, carbohydrates: carbohydrates, fat: fat),
        nutritionSource: "Test values"
    )
}

typealias Nutrients = (calories: Double, protein: Double, carbohydrates: Double, fat: Double)

func evaluation(
    _ mealID: String,
    preReview: Nutrients,
    missedByAnalysis: Set<String> = [],
    reviewed: Nutrients,
    missedAfterReview: Set<String> = [],
    correctionTime: TimeInterval,
    suggestionsWithoutEstimate: [String] = [],
    customFoodsAfterReview: [String] = [],
    photoAnalysisMessage: String? = nil
) -> MealEvaluation {
    func estimate(_ n: Nutrients) -> NutritionEstimate {
        NutritionEstimate(calories: n.calories, protein: n.protein, carbohydrates: n.carbohydrates, fat: n.fat)
    }
    return MealEvaluation(
        referenceMealID: mealID,
        preReview: StageResult(nutritionEstimate: estimate(preReview), missedReferenceFoodIDs: missedByAnalysis),
        reviewed: StageResult(nutritionEstimate: estimate(reviewed), missedReferenceFoodIDs: missedAfterReview),
        correctionTime: correctionTime,
        suggestionsWithoutEstimate: suggestionsWithoutEstimate,
        customFoodsAfterReview: customFoodsAfterReview,
        photoAnalysisMessage: photoAnalysisMessage
    )
}
