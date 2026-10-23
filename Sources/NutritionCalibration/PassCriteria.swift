import Foundation
import NutritionCore

/// One numeric pass criterion for broad release, written down after inspecting the calibration results and
/// frozen before any validation meal is scored (ADR 0002).
public struct PassCriterion: Codable, Hashable, Sendable {
    /// What is measured. Percentages are 0–100.
    public enum Metric: String, Codable, Hashable, Sendable {
        /// Mean absolute calorie error as a percentage of the reference.
        case caloriesPercentError
        case proteinPercentError
        case carbohydratesPercentError
        case fatPercentError
        /// Reference foods the stage left out, as a percentage of all reference foods.
        case missingFoodPercent
        /// Median seconds of review; only measured at the reviewed stage.
        case medianCorrectionTime
    }

    /// Which meals the limit applies to.
    public enum Scope: String, Codable, Hashable, Sendable {
        case allMeals
        /// Every cuisine on its own must meet it.
        case eachCuisine
        /// Every dish type on its own must meet it.
        case eachDishType
    }

    public var stage: EstimateStage
    public var metric: Metric
    public var scope: Scope
    /// The highest value that passes.
    public var atMost: Double
    /// Why this limit, in view of the calibration results.
    public var rationale: String

    public init(stage: EstimateStage, metric: Metric, scope: Scope, atMost: Double, rationale: String) {
        self.stage = stage
        self.metric = metric
        self.scope = scope
        self.atMost = atMost
        self.rationale = rationale
    }

    var isValid: Bool {
        atMost.isFinite && atMost >= 0 && !rationale.isBlank && (metric != .medianCorrectionTime || stage == .reviewed)
    }

    /// The criterion's value for each group it covers in `report`.
    func measurements(in report: AccuracyReport) -> [CriterionMeasurement] {
        let groups: [GroupAccuracy]
        switch scope {
        case .allMeals: groups = [report.overall]
        case .eachCuisine: groups = report.byCuisine
        case .eachDishType: groups = report.byDishType
        }
        return groups.map { CriterionMeasurement(group: $0.name, value: value(in: $0)) }
    }

    /// Whether a measured value is within the limit. A value that could not be measured is not.
    func admits(_ value: Double?) -> Bool {
        value.map { $0 <= atMost } ?? false
    }

    func value(in group: GroupAccuracy) -> Double? {
        let accuracy = group[stage]
        switch metric {
        case .caloriesPercentError: return accuracy.calories.meanAbsolutePercentError
        case .proteinPercentError: return accuracy.protein.meanAbsolutePercentError
        case .carbohydratesPercentError: return accuracy.carbohydrates.meanAbsolutePercentError
        case .fatPercentError: return accuracy.fat.meanAbsolutePercentError
        case .missingFoodPercent: return group.mealCount == 0 ? nil : accuracy.missingFoodRate * 100
        case .medianCorrectionTime: return group.medianCorrectionTime
        }
    }
}

/// A stage and nutrient the pass criteria must set a limit for: calories and each macronutrient, for the automatic
/// pre-review estimate and the reviewed estimate separately (ADR 0002). Any scope will do.
public struct RequiredCriterion: Hashable, Sendable {
    public var stage: EstimateStage
    public var metric: PassCriterion.Metric

    public init(stage: EstimateStage, metric: PassCriterion.Metric) {
        self.stage = stage
        self.metric = metric
    }

    static let all: [RequiredCriterion] = EstimateStage.allCases.flatMap { stage in
        [PassCriterion.Metric.caloriesPercentError, .proteinPercentError, .carbohydratesPercentError, .fatPercentError]
            .map { RequiredCriterion(stage: stage, metric: $0) }
    }

    /// The required criteria `criteria` sets no limit for, in stage then nutrient order.
    static func missing(from criteria: [PassCriterion]) -> [RequiredCriterion] {
        let covered = Set(criteria.map { RequiredCriterion(stage: $0.stage, metric: $0.metric) })
        return all.filter { !covered.contains($0) }
    }
}

/// The pass criteria as frozen, with the calibration records they were set from.
public struct FrozenPassCriteria: Codable, Hashable, Sendable {
    public var criteria: [PassCriterion]
    public var frozenOn: Date
    /// The calibration meals evaluated when the criteria were frozen.
    public var calibrationMealIDs: [ReferenceMeal.ID]
    /// Identifies the calibration meals and evaluations as they were when frozen; validation is not scored if
    /// they have changed since.
    public var calibrationFingerprint: String
}

/// The validation set scored against the frozen pass criteria.
public struct ValidationScore: Hashable, Sendable {
    public var report: AccuracyReport
    public var criteria: FrozenPassCriteria
    public var scoredOn: Date
    /// One per criterion, in the frozen order.
    public var results: [CriterionResult]

    /// Every criterion passed: the accuracy gate for broad launch.
    public var passed: Bool { results.allSatisfy(\.passed) }

    /// Every cuisine and dish type that, on its own, is over a criterion's limit or cannot be measured for it,
    /// whatever the criterion's scope: a criterion for all meals can pass while one cuisine fails it. Cuisines
    /// first, each group's failures in criterion order.
    public var groupFailures: [GroupFailure] {
        let grouped: [(ReportGrouping, [GroupAccuracy])] = [(.cuisine, report.byCuisine), (.dishType, report.byDishType)]
        return grouped.flatMap { grouping, groups in
            groups.flatMap { group in
                criteria.criteria.compactMap { criterion in
                    let value = criterion.value(in: group)
                    return criterion.admits(value)
                        ? nil : GroupFailure(grouping: grouping, group: group.name, criterion: criterion, value: value)
                }
            }
        }
    }

    /// The accuracy claim the app may make from this validation: none unless it passed.
    public var reliability: EstimateReliability {
        let overall = report.overall
        guard passed,
              let preReview = overall.preReview.calories.meanAbsolutePercentError,
              let reviewed = overall.reviewed.calories.meanAbsolutePercentError else { return .notValidated }
        // Only measured nutrient errors make a group less accurate; a missing-food or correction-time limit, or a
        // group that could not be measured, says nothing about how close its estimates were.
        let nutrientMetrics = Set(RequiredCriterion.all.map(\.metric))
        func lessAccurate(_ grouping: ReportGrouping) -> [String] {
            groupFailures
                .filter { $0.grouping == grouping && $0.value != nil && nutrientMetrics.contains($0.criterion.metric) }
                .map(\.group).reduce(into: []) { names, name in
                if !names.contains(name) { names.append(name) }
            }
        }
        return .validated(accuracy: ValidatedAccuracy(
            validatedOn: scoredOn,
            mealCount: overall.mealCount,
            cuisines: report.byCuisine.map(\.name),
            dishTypes: report.byDishType.map(\.name),
            preReviewCaloriePercentError: preReview,
            reviewedCaloriePercentError: reviewed,
            lessAccurateCuisines: lessAccurate(.cuisine),
            lessAccurateDishTypes: lessAccurate(.dishType)
        ))
    }
}

/// A cuisine or dish type over one pass criterion's limit in the validation set.
public struct GroupFailure: Hashable, Sendable {
    public var grouping: ReportGrouping
    /// The cuisine or dish type.
    public var group: String
    public var criterion: PassCriterion
    /// Nil when the group could not be measured for the criterion.
    public var value: Double?

    public init(grouping: ReportGrouping, group: String, criterion: PassCriterion, value: Double?) {
        self.grouping = grouping
        self.group = group
        self.criterion = criterion
        self.value = value
    }
}

public struct CriterionResult: Hashable, Sendable {
    public var criterion: PassCriterion
    /// One per group the criterion covers.
    public var measurements: [CriterionMeasurement]

    /// Every group was measured and is within the limit. A group with no measurable value fails.
    public var passed: Bool {
        !measurements.isEmpty && measurements.allSatisfy { criterion.admits($0.value) }
    }
}

public struct CriterionMeasurement: Hashable, Sendable {
    /// "All meals", a cuisine or a dish type.
    public var group: String
    /// Nil when nothing in the group could be measured (e.g. every reference value was zero).
    public var value: Double?

    public init(group: String, value: Double?) {
        self.group = group
        self.value = value
    }
}
