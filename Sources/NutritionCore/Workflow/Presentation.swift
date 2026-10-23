import Foundation

/// What a person sees for a meal entry, whether it is a draft under review or a saved entry reopened
/// from meal history. Views render these strings as-is.
public struct MealEntryPresentation: Hashable, Identifiable, Sendable {
    public var id: MealEntry.ID
    public var date: Date
    public var photos: [PresentedMealPhoto]
    public var foods: [PresentedReviewedFood]
    public var nutritionEstimate: PresentedNutritionEstimate
}

public struct PresentedMealPhoto: Hashable, Identifiable, Sendable {
    public var id: MealPhoto.ID
    public var imageData: Data
}

public struct PresentedReviewedFood: Hashable, Identifiable, Sendable {
    public var id: ReviewedFood.ID
    public var name: String
    /// e.g. "180 g".
    public var portion: String
    /// "Custom food", or the documented source's name.
    public var sourceName: String
    /// The documented record's identifier within its source (e.g. an FDC ID); nil for a custom food.
    public var sourceRecordID: String?
    public var nutritionEstimate: PresentedNutritionEstimate
    public var uncertaintyNotes: [String]

    init(_ reviewedFood: ReviewedFood) {
        id = reviewedFood.id
        name = reviewedFood.food.name
        portion = NutrientFormat.grams(reviewedFood.portion.grams)
        (sourceName, sourceRecordID) = reviewedFood.food.source.presentedProvenance
        nutritionEstimate = PresentedNutritionEstimate(reviewedFood.nutritionEstimate)
        uncertaintyNotes = reviewedFood.uncertaintyNotes.map(\.detail)
    }
}

/// A nutrition estimate as shown to the person: always labeled approximate, rounded only here.
public struct PresentedNutritionEstimate: Hashable, Sendable {
    public var label: String
    /// Whole kilocalories, e.g. "396 kcal".
    public var calories: String
    /// Grams to one decimal place, e.g. "17.1 g".
    public var protein: String
    public var carbohydrates: String
    public var fat: String

    public init(_ estimate: NutritionEstimate) {
        label = "Approximate nutrition estimate"
        calories = "\(Int(estimate.calories.rounded())) kcal"
        protein = NutrientFormat.grams(estimate.protein)
        carbohydrates = NutrientFormat.grams(estimate.carbohydrates)
        fat = NutrientFormat.grams(estimate.fat)
    }
}

/// The outcome of a food search, as the person sees it.
public struct FoodSearchPresentation: Hashable, Sendable {
    public var results: [FoodSearchResult]
    /// Shown when no documented food matches, pointing the person to a custom food instead.
    public var noMatchMessage: String?

    init(query: String, results: [FoodSearchResult]) {
        self.results = results
        noMatchMessage = results.isEmpty
            ? "No documented food matches \"\(query)\". Add it as a custom food."
            : nil
    }
}

/// One selectable food from a documented nutrition source, with its provenance.
public struct FoodSearchResult: Hashable, Identifiable, Sendable {
    public var id: String { "\(sourceName)#\(sourceRecordID ?? name)" }
    public var name: String
    /// The documented source's name, e.g. "USDA FoodData Central".
    public var sourceName: String
    /// The record's identifier within that source, e.g. an FDC ID.
    public var sourceRecordID: String?
    /// The food the person chooses; handed back to `MealEntryWorkflow.addFood(_:grams:)`.
    let food: Food

    init(_ food: Food) {
        self.food = food
        name = food.name
        (sourceName, sourceRecordID) = food.source.presentedProvenance
    }
}

extension FoodSource {
    /// Source name and record identifier as shown to the person.
    var presentedProvenance: (sourceName: String, recordID: String?) {
        switch self {
        case .custom:
            return ("Custom food", nil)
        case .documented(let reference):
            return (reference.sourceName, reference.recordID)
        }
    }
}

/// One row of meal history.
public struct MealHistoryRow: Hashable, Identifiable, Sendable {
    public var id: MealEntry.ID
    public var date: Date
    public var foodNames: [String]
    public var nutritionEstimate: PresentedNutritionEstimate
}

enum NutrientFormat {
    /// Grams rounded to one decimal place, without a trailing ".0": "17.1 g", "180 g".
    static func grams(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        let whole = tenths / 10
        let fraction = abs(tenths % 10)
        return fraction == 0 ? "\(whole) g" : "\(whole).\(fraction) g"
    }
}
