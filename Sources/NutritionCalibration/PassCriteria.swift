import Foundation

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

    private func value(in group: GroupAccuracy) -> Double? {
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
    /// One per criterion, in the frozen order.
    public var results: [CriterionResult]

    /// Every criterion passed.
    public var passed: Bool { results.allSatisfy(\.passed) }
}

public struct CriterionResult: Hashable, Sendable {
    public var criterion: PassCriterion
    /// One per group the criterion covers.
    public var measurements: [CriterionMeasurement]

    /// Every group was measured and is within the limit. A group with no measurable value fails.
    public var passed: Bool {
        !measurements.isEmpty && measurements.allSatisfy { $0.value.map { $0 <= criterion.atMost } ?? false }
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
