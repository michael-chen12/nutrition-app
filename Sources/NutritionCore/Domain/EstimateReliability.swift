import Foundation

/// What the app tells people about how accurate its nutrition estimates are. It claims only what a held-out
/// validation against weighed meals and known recipes measured (ADR 0002); until one passes its frozen pass
/// criteria, it makes no accuracy claim beyond "approximate".
public enum EstimateReliability: Codable, Hashable, Sendable {
    /// No validation has passed.
    case notValidated
    /// A validation passed every pass criterion, and measured this.
    case validated(accuracy: ValidatedAccuracy)

    /// The claim this build of the app makes. Change it only to the `estimate-reliability.json` that scoring a
    /// passed validation wrote, and record the decision in docs/calibration/launch-decision.md.
    public static let published = EstimateReliability.notValidated

    /// The claim as shown to the person.
    public var statement: String {
        switch self {
        case .notValidated:
            return "These estimates have not yet passed an accuracy test against weighed meals, so the app makes "
                + "no claim about how close they are. Treat them as approximate and check each food and portion."
        case .validated(let accuracy):
            return accuracy.statement
        }
    }
}

/// What a passed validation measured, as far as the app may repeat it.
public struct ValidatedAccuracy: Codable, Hashable, Sendable {
    /// When the validation set was scored.
    public var validatedOn: Date
    public var mealCount: Int
    public var cuisines: [String]
    public var dishTypes: [String]
    /// Mean absolute calorie error as a percentage of the reference: photo suggestions accepted as offered.
    public var preReviewCaloriePercentError: Double
    /// The same for the reviewed nutrition estimate.
    public var reviewedCaloriePercentError: Double
    /// Cuisines and dish types that, on their own, were over a pass criterion's limit although the whole set passed.
    public var lessAccurateCuisines: [String]
    public var lessAccurateDishTypes: [String]

    public init(
        validatedOn: Date,
        mealCount: Int,
        cuisines: [String],
        dishTypes: [String],
        preReviewCaloriePercentError: Double,
        reviewedCaloriePercentError: Double,
        lessAccurateCuisines: [String],
        lessAccurateDishTypes: [String]
    ) {
        self.validatedOn = validatedOn
        self.mealCount = mealCount
        self.cuisines = cuisines
        self.dishTypes = dishTypes
        self.preReviewCaloriePercentError = preReviewCaloriePercentError
        self.reviewedCaloriePercentError = reviewedCaloriePercentError
        self.lessAccurateCuisines = lessAccurateCuisines
        self.lessAccurateDishTypes = lessAccurateDishTypes
    }

    var statement: String {
        func percent(_ value: Double) -> String { "\(Int(value.rounded())) %" }
        var text = "Tested on \(mealCount) new meals with weighed portions or known recipes (cuisines: "
            + "\(cuisines.joined(separator: ", ")); dish types: \(dishTypes.joined(separator: ", "))). Reviewed "
            + "estimates were off by \(percent(reviewedCaloriePercentError)) in calories on average; photo "
            + "suggestions before review, by \(percent(preReviewCaloriePercentError))."
        let lessAccurate = lessAccurateCuisines.map { "\($0) (cuisine)" } + lessAccurateDishTypes.map { "\($0) (dish type)" }
        if !lessAccurate.isEmpty { text += " Less accurate for: \(lessAccurate.joined(separator: ", "))." }
        return text
    }
}
