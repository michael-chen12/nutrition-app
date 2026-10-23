import Foundation
import NutritionCore

/// Nutrition estimate accuracy for one split of the study, worked out from the recorded evaluations and their
/// reference meals. The same records always give the same report.
///
/// Errors are estimate minus reference. A percent error is the absolute error as a share of the reference
/// value; meals whose reference value for a nutrient is zero (e.g. the fat in black coffee) have no percent
/// error for it and are left out of that mean.
public struct AccuracyReport: Hashable, Sendable {
    public var split: ReferenceMeal.Split
    /// Every evaluated meal of the split.
    public var overall: GroupAccuracy
    /// One group per cuisine, by name.
    public var byCuisine: [GroupAccuracy]
    /// One group per dish type, by name.
    public var byDishType: [GroupAccuracy]
    /// Where coverage is thin or estimates are notably worse, coverage gaps first.
    public var gaps: [AccuracyGap]

    /// A cuisine or dish type with fewer evaluated meals is a coverage gap.
    static let minimumMealsPerGroup = 3
    /// A group whose mean calorie percent error exceeds the split's by this factor is an estimation gap.
    static let highErrorFactor = 1.5

    /// - Parameters:
    ///   - meals: Reference meals; only those in `split` are reported.
    ///   - evaluations: One per evaluated meal. Evaluations of meals in another split are left out.
    public init(split: ReferenceMeal.Split, meals: [ReferenceMeal], evaluations: [MealEvaluation]) throws {
        self.split = split
        let mealsByID = Dictionary(meals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var evaluated: [EvaluatedMeal] = []
        for evaluation in evaluations {
            guard let meal = mealsByID[evaluation.referenceMealID] else {
                throw AccuracyReportError.evaluationOfUnknownMeal(evaluation.referenceMealID)
            }
            if meal.split == split { evaluated.append(EvaluatedMeal(meal: meal, evaluation: evaluation)) }
        }
        evaluated.sort { $0.meal.id < $1.meal.id }
        overall = GroupAccuracy(name: "All meals", meals: evaluated)
        byCuisine = Self.groups(of: evaluated, by: \.meal.cuisine)
        byDishType = Self.groups(of: evaluated, by: \.meal.dishType)

        let splitMeals = meals.filter { $0.split == split }
        let evaluatedIDs = Set(evaluated.map(\.meal.id))
        var gaps: [AccuracyGap] = []
        let cuisineCount = Set(splitMeals.map(\.cuisine)).count
        if cuisineCount < 2 { gaps.append(.fewCuisines(count: cuisineCount)) }
        let dishTypeCount = Set(splitMeals.map(\.dishType)).count
        if dishTypeCount < 2 { gaps.append(.fewDishTypes(count: dishTypeCount)) }
        let grouped: [(ReportGrouping, [GroupAccuracy])] = [(.cuisine, byCuisine), (.dishType, byDishType)]
        for (grouping, groups) in grouped {
            for group in groups where group.mealCount < Self.minimumMealsPerGroup {
                gaps.append(.fewMeals(grouping, name: group.name, mealCount: group.mealCount))
            }
        }
        let notEvaluated = splitMeals.map(\.id).filter { !evaluatedIDs.contains($0) }.sorted()
        if !notEvaluated.isEmpty { gaps.append(.notEvaluated(mealIDs: notEvaluated)) }
        for evaluatedMeal in evaluated {
            if let message = evaluatedMeal.evaluation.photoAnalysisMessage {
                gaps.append(.noPhotoSuggestions(mealID: evaluatedMeal.meal.id, message: message))
            }
        }
        for evaluatedMeal in evaluated {
            let missed = Set(evaluatedMeal.evaluation.reviewed.missedReferenceFoodIDs)
            let names = evaluatedMeal.meal.referenceFoods.filter { missed.contains($0.id) }.map(\.name)
            if !names.isEmpty { gaps.append(.missedAfterReview(mealID: evaluatedMeal.meal.id, foodNames: names)) }
        }
        let withoutEstimate = Set(evaluated.flatMap(\.evaluation.suggestionsWithoutEstimate)).sorted()
        if !withoutEstimate.isEmpty { gaps.append(.suggestionsWithoutEstimate(foodNames: withoutEstimate)) }
        let customFoods = Set(evaluated.flatMap(\.evaluation.customFoodsAfterReview)).sorted()
        if !customFoods.isEmpty { gaps.append(.customFoodsAfterReview(foodNames: customFoods)) }

        for stage in EstimateStage.allCases {
            guard let overallError = overall[stage].calories.meanAbsolutePercentError, overallError > 0 else { continue }
            for (grouping, groups) in grouped {
                for group in groups {
                    if let error = group[stage].calories.meanAbsolutePercentError, error > overallError * Self.highErrorFactor {
                        gaps.append(.highCalorieError(
                            stage, grouping, name: group.name, percentError: error, overallPercentError: overallError
                        ))
                    }
                }
            }
        }
        for (grouping, groups) in grouped {
            for group in groups {
                if let before = group.preReview.calories.meanAbsolutePercentError,
                   let after = group.reviewed.calories.meanAbsolutePercentError,
                   after > 0, after >= before {
                    gaps.append(.reviewDidNotReduceCalorieError(
                        grouping, name: group.name, preReviewPercentError: before, reviewedPercentError: after
                    ))
                }
            }
        }
        self.gaps = gaps
    }

    private static func groups(of meals: [EvaluatedMeal], by name: KeyPath<EvaluatedMeal, String>) -> [GroupAccuracy] {
        Dictionary(grouping: meals) { $0[keyPath: name] }
            .sorted { $0.key < $1.key }
            .map { GroupAccuracy(name: $0.key, meals: $0.value) }
    }
}

/// How the report groups meals.
public enum ReportGrouping: String, Codable, Hashable, Sendable {
    case cuisine
    case dishType
}

/// Something the pilot cannot yet show, or does notably badly, identified from the records.
public enum AccuracyGap: Hashable, Sendable {
    // Coverage gaps
    /// The split has meals from fewer than two cuisines.
    case fewCuisines(count: Int)
    /// The split has meals of fewer than two dish types.
    case fewDishTypes(count: Int)
    /// Too few evaluated meals in a cuisine or dish type to judge it.
    case fewMeals(ReportGrouping, name: String, mealCount: Int)
    /// Reference meals of the split without an evaluation yet.
    case notEvaluated(mealIDs: [ReferenceMeal.ID])
    /// Photo analysis gave a meal no suggestions, with the message the person saw: an outage or unusable output
    /// (worth re-running) rather than foods the analysis missed, or no food found at all.
    case noPhotoSuggestions(mealID: ReferenceMeal.ID, message: String)
    /// Reference foods still missing from a meal after review.
    case missedAfterReview(mealID: ReferenceMeal.ID, foodNames: [String])
    /// Photo suggestions that added nothing to the pre-review estimate (no documented food, or no portion
    /// conversion): candidates for another nutrition source.
    case suggestionsWithoutEstimate(foodNames: [String])
    /// Custom foods people entered because no documented food fit.
    case customFoodsAfterReview(foodNames: [String])

    // Estimation gaps
    /// A group's mean calorie percent error is well above the split's for that stage.
    case highCalorieError(
        EstimateStage, ReportGrouping, name: String, percentError: Double, overallPercentError: Double
    )
    /// Review left a group's mean calorie percent error no lower than before it.
    case reviewDidNotReduceCalorieError(
        ReportGrouping, name: String, preReviewPercentError: Double, reviewedPercentError: Double
    )
}

/// Accuracy of one group of evaluated meals (the whole split, one cuisine or one dish type).
public struct GroupAccuracy: Hashable, Sendable {
    public var name: String
    public var mealCount: Int
    /// Photo suggestions accepted as offered.
    public var preReview: StageAccuracy
    /// The saved meal entry after the person's review.
    public var reviewed: StageAccuracy
    /// Median seconds the person spent reviewing; nil for no meals.
    public var medianCorrectionTime: TimeInterval?

    init(name: String, meals: [EvaluatedMeal]) {
        self.name = name
        mealCount = meals.count
        preReview = StageAccuracy(meals.map { ($0.meal, $0.evaluation.preReview) })
        reviewed = StageAccuracy(meals.map { ($0.meal, $0.evaluation.reviewed) })
        medianCorrectionTime = meals.map(\.evaluation.correctionTime).median
    }

    public subscript(stage: EstimateStage) -> StageAccuracy {
        switch stage {
        case .preReview: return preReview
        case .reviewed: return reviewed
        }
    }
}

/// One stage's errors over a group of meals.
public struct StageAccuracy: Hashable, Sendable {
    public var calories: NutrientAccuracy
    public var protein: NutrientAccuracy
    public var carbohydrates: NutrientAccuracy
    public var fat: NutrientAccuracy
    /// Reference foods the stage missed, as a share of all the group's reference foods.
    public var missingFoodRate: Double

    init(_ results: [(meal: ReferenceMeal, result: StageResult)]) {
        func nutrient(_ value: KeyPath<NutritionEstimate, Double>) -> NutrientAccuracy {
            NutrientAccuracy(results.map { ($0.result.nutritionEstimate[keyPath: value], $0.meal.referenceNutrition[keyPath: value]) })
        }
        calories = nutrient(\.calories)
        protein = nutrient(\.protein)
        carbohydrates = nutrient(\.carbohydrates)
        fat = nutrient(\.fat)
        let referenceFoodCount = results.map(\.meal.referenceFoods.count).reduce(0, +)
        let missedCount = results.map(\.result.missedReferenceFoodIDs.count).reduce(0, +)
        missingFoodRate = referenceFoodCount == 0 ? 0 : Double(missedCount) / Double(referenceFoodCount)
    }
}

/// Errors for one nutrient over a group of meals: kcal for calories, grams otherwise.
public struct NutrientAccuracy: Hashable, Sendable {
    /// Mean of estimate minus reference: positive when estimates run high.
    public var meanError: Double
    public var meanAbsoluteError: Double
    /// Mean absolute error as a percentage of the reference value, over meals with a non-zero reference value;
    /// nil when there are none.
    public var meanAbsolutePercentError: Double?

    init(_ pairs: [(estimate: Double, reference: Double)]) {
        let errors = pairs.map { $0.estimate - $0.reference }
        meanError = errors.mean ?? 0
        meanAbsoluteError = errors.map(abs).mean ?? 0
        meanAbsolutePercentError = pairs.filter { $0.reference > 0 }
            .map { abs($0.estimate - $0.reference) * 100 / $0.reference }
            .mean
    }
}

public enum AccuracyReportError: Error, Equatable {
    /// An evaluation names a reference meal that is not in the pilot.
    case evaluationOfUnknownMeal(ReferenceMeal.ID)
}

struct EvaluatedMeal: Hashable, Sendable {
    var meal: ReferenceMeal
    var evaluation: MealEvaluation
}

extension Array where Element == Double {
    var mean: Double? {
        isEmpty ? nil : reduce(0, +) / Double(count)
    }

    var median: Double? {
        guard !isEmpty else { return nil }
        let sorted = sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
