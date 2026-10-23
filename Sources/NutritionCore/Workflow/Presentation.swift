import Foundation

/// What a person sees for a meal entry, whether it is a draft under review or a saved entry reopened
/// from meal history. Views render these strings as-is.
public struct MealEntryPresentation: Hashable, Identifiable, Sendable {
    public var id: MealEntry.ID
    public var date: Date
    public var photos: [PresentedMealPhoto]
    public var foods: [PresentedReviewedFood]
    public var nutritionEstimate: PresentedNutritionEstimate
    /// Explains what the estimate covers: all pictured food, each food once (see docs/adr/0004).
    public var picturedFoodNote = "This estimate covers all pictured food, including food that was shared or "
        + "left uneaten. Food seen in more than one photo counts once."
}

public struct PresentedMealPhoto: Hashable, Identifiable, Sendable {
    public var id: MealPhoto.ID
    /// Position of the photo in the meal entry, starting at 1.
    public var number: Int
    /// e.g. "Photo 2"; matches the photo references in `PresentedReviewedFood.shownIn`.
    public var label: String
    public var imageData: Data

    init(id: MealPhoto.ID, number: Int, imageData: Data) {
        self.id = id
        self.number = number
        label = "Photo \(number)"
        self.imageData = imageData
    }
}

public struct PresentedReviewedFood: Hashable, Identifiable, Sendable {
    public var id: ReviewedFood.ID
    public var name: String
    /// e.g. "180 g", or "1.5 cup (237 g)" for a serving unit with its effective grams.
    public var portion: String
    /// The unit the portion was entered in, and the amount in that unit (servings or grams).
    public var selectedPortionUnit: PortionUnit
    public var portionQuantity: Double
    /// Units the portion can be corrected in: grams first, then the food's serving units.
    public var portionUnits: [PresentedPortionUnit]
    /// "Custom food", or the documented source's name.
    public var sourceName: String
    /// The documented record's identifier within its source (e.g. an FDC ID); nil for a custom food.
    public var sourceRecordID: String?
    public var nutritionEstimate: PresentedNutritionEstimate
    public var uncertaintyNotes: [String]
    /// The same unresolved details, asked as focused questions (see FocusedQuestions.swift).
    public var focusedQuestions: [PresentedFocusedQuestion]
    /// Which meal photos show this food, e.g. "Photos 1 and 2"; nil when no photo is noted.
    public var shownIn: String?

    init(_ reviewedFood: ReviewedFood, photoNumbers: [MealPhoto.ID: Int] = [:]) {
        focusedQuestions = reviewedFood.uncertaintyNotes.map { PresentedFocusedQuestion($0, about: reviewedFood) }
        shownIn = PhotoReferenceFormat.shownIn(reviewedFood.photoIDs.compactMap { photoNumbers[$0] })
        id = reviewedFood.id
        name = reviewedFood.food.name
        portion = PortionFormat.portion(reviewedFood.portion)
        selectedPortionUnit = reviewedFood.portion.unit
        portionQuantity = reviewedFood.portion.quantity
        portionUnits = PresentedPortionUnit.options(for: reviewedFood.food)
        (sourceName, sourceRecordID) = reviewedFood.food.source.presentedProvenance
        nutritionEstimate = PresentedNutritionEstimate(reviewedFood.nutritionEstimate)
        uncertaintyNotes = reviewedFood.uncertaintyNotes.map(\.detail)
    }
}

/// A unit a food's portion can be entered in, as the person sees it. Pass `unit` back to
/// `MealEntryWorkflow.changePortion(of:quantity:unit:)`.
public struct PresentedPortionUnit: Hashable, Identifiable, Sendable {
    public var id: PortionUnit { unit }
    public var unit: PortionUnit
    /// "g", or the serving unit's name, e.g. "cup".
    public var name: String
    /// The documented conversion, e.g. "1 cup = 158 g"; nil for grams and for units without a known gram weight.
    public var quantityBasis: String?
    /// Shown instead of a quantity basis when the source documents no gram weight for the unit. Such a unit
    /// cannot be chosen: the conversion would be a guess.
    public var conversionUnavailableNote: String?

    init(_ unit: PortionUnit) {
        self.unit = unit
        quantityBasis = nil
        conversionUnavailableNote = nil
        switch unit {
        case .grams:
            name = "g"
        case .serving(let servingUnit):
            name = servingUnit.name
            if servingUnit.gramsPerUnit != nil, let basis = servingUnit.quantityBasis,
               let gramWeight = servingUnit.gramWeight {
                quantityBasis = "\(PortionFormat.quantity(basis)) \(servingUnit.name) = \(NutrientFormat.grams(gramWeight))"
            } else {
                conversionUnavailableNote = "No gram weight is documented for \(servingUnit.name), "
                    + "so it can't be converted. Enter grams instead."
            }
        }
    }

    /// Grams first, then the food's serving units in source order.
    static func options(for food: Food) -> [PresentedPortionUnit] {
        [PresentedPortionUnit(.grams)] + food.servingUnits.map { PresentedPortionUnit(.serving($0)) }
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
    /// Units the food can be added in: grams first, then its documented serving units.
    public var portionUnits: [PresentedPortionUnit]
    /// The food the person chooses; handed back to `MealEntryWorkflow.addFood(_:grams:)`.
    let food: Food

    init(_ food: Food) {
        self.food = food
        name = food.name
        portionUnits = PresentedPortionUnit.options(for: food)
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
    /// The meal entry's uncertainty flag: some detail is still unresolved, so its estimate may be off.
    public var hasUnresolvedUncertainty = false
}

extension MealHistoryRow {
    init(_ entry: MealEntry) {
        self.init(
            id: entry.id,
            date: entry.date,
            foodNames: entry.reviewedFoods.map(\.food.name),
            nutritionEstimate: PresentedNutritionEstimate(entry.nutritionEstimate)
        )
        hasUnresolvedUncertainty = entry.reviewedFoods.contains { !$0.uncertaintyNotes.isEmpty }
    }
}

/// One day of meal history: the meal entries assigned to that day and their daily pictured-food total.
public struct MealHistoryDay: Hashable, Identifiable, Sendable {
    public var id: Date { date }
    /// The start of the day in the calendar and time zone the workflow was given; format it for display.
    public var date: Date
    /// The day's year, month and day in that calendar, e.g. 2026-10-21.
    public var day: DateComponents
    /// The day's meal entries, most recent first.
    public var mealEntries: [MealHistoryRow]
    public var picturedFoodTotal: PresentedDailyPicturedFoodTotal

    init(date: Date, day: DateComponents, mealEntries entries: [MealEntry]) {
        self.date = date
        self.day = day
        mealEntries = entries.map(MealHistoryRow.init)
        picturedFoodTotal = PresentedDailyPicturedFoodTotal(entries.map(\.nutritionEstimate).total())
    }
}

/// The combined nutrition estimates for pictured food in one day's meal entries, as shown to the person.
/// It covers all pictured food, including shared or uneaten food, so it is never presented as what one
/// person consumed (see docs/adr/0004).
public struct PresentedDailyPicturedFoodTotal: Hashable, Sendable {
    public var label = "Daily pictured-food total"
    /// Shown with the total: what it covers and that it is not a personal measure.
    public var note = "Approximate combined nutrition estimates for all pictured food in this day's meal entries, "
        + "including food that was shared or left uneaten. It is not a measure of food consumed by one person."
    /// Whole kilocalories, e.g. "315 kcal".
    public var calories: String
    /// Grams to one decimal place, e.g. "5.1 g".
    public var protein: String
    public var carbohydrates: String
    public var fat: String

    init(_ total: NutritionEstimate) {
        let values = PresentedNutritionEstimate(total)
        calories = values.calories
        protein = values.protein
        carbohydrates = values.carbohydrates
        fat = values.fat
    }
}

enum PhotoReferenceFormat {
    /// "Photo 3", "Photos 1 and 2", "Photos 1, 2 and 4"; nil for no photos.
    static func shownIn(_ numbers: [Int]) -> String? {
        let sorted = numbers.sorted().map(String.init)
        guard let last = sorted.last else { return nil }
        if sorted.count == 1 { return "Photo \(last)" }
        return "Photos \(sorted.dropLast().joined(separator: ", ")) and \(last)"
    }
}

enum PortionFormat {
    /// "180 g" for grams entered directly; "1.5 cup (237 g)" for a serving unit, with its effective grams.
    static func portion(_ portion: Portion) -> String {
        let grams = NutrientFormat.grams(portion.grams)
        guard let serving = portion.serving else { return grams }
        return "\(quantity(serving.quantity)) \(serving.unit.name) (\(grams))"
    }

    /// Up to two decimal places, without trailing zeros: "1", "1.5", "0.25".
    static func quantity(_ value: Double) -> String {
        let hundredths = Int((value * 100).rounded())
        var text = "\(hundredths / 100)"
        let fraction = abs(hundredths % 100)
        if fraction != 0 {
            text += fraction % 10 == 0 ? ".\(fraction / 10)" : (fraction < 10 ? ".0\(fraction)" : ".\(fraction)")
        }
        return text
    }
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
