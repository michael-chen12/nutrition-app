import Foundation
import NutritionCore

/// What one calibration trial recorded for a reference meal. Errors are not stored: the report works them out
/// from these estimates and the reference meal, so it can be reproduced from the raw records.
public struct MealEvaluation: Codable, Hashable, Sendable {
    public var referenceMealID: ReferenceMeal.ID
    /// Photo suggestions accepted as offered, before the person reviewed anything (the automatic stage).
    public var preReview: StageResult
    /// The saved meal entry after the person's review.
    public var reviewed: StageResult
    /// Seconds from the photo suggestions being shown to the reviewed meal entry being saved.
    public var correctionTime: TimeInterval
    /// Photo suggestions that added nothing to the pre-review estimate: no documented food was found for them,
    /// or their portion could not be converted without guessing. A sign of nutrition-source coverage gaps.
    public var suggestionsWithoutEstimate: [String]
    /// Custom foods in the reviewed meal entry: food no documented source covered well enough for the person.
    public var customFoodsAfterReview: [String]
    /// Why photo analysis gave no suggestions (unavailable, unusable output, or no food found), as shown to the
    /// person; nil when it gave suggestions. Tells an outage apart from a meal the analysis missed.
    public var photoAnalysisMessage: String?

    public init(
        referenceMealID: ReferenceMeal.ID,
        preReview: StageResult,
        reviewed: StageResult,
        correctionTime: TimeInterval,
        suggestionsWithoutEstimate: [String] = [],
        customFoodsAfterReview: [String] = [],
        photoAnalysisMessage: String? = nil
    ) {
        self.photoAnalysisMessage = photoAnalysisMessage
        self.referenceMealID = referenceMealID
        self.preReview = preReview
        self.reviewed = reviewed
        self.correctionTime = correctionTime
        self.suggestionsWithoutEstimate = suggestionsWithoutEstimate
        self.customFoodsAfterReview = customFoodsAfterReview
    }
}

/// The two stages a meal's nutrition estimate is measured at (ADR 0002).
public enum EstimateStage: String, CaseIterable, Codable, Hashable, Sendable {
    /// Photo suggestions accepted as offered: the automatic estimate.
    case preReview
    /// The final estimate after the person's review.
    case reviewed
}

/// One stage's estimate of a reference meal.
public struct StageResult: Codable, Hashable, Sendable {
    public var nutritionEstimate: NutritionEstimate
    /// Reference foods the stage did not include at all, in ID order.
    public var missedReferenceFoodIDs: [ReferenceFood.ID]

    public init(nutritionEstimate: NutritionEstimate, missedReferenceFoodIDs: Set<ReferenceFood.ID>) {
        self.nutritionEstimate = nutritionEstimate
        self.missedReferenceFoodIDs = missedReferenceFoodIDs.sorted()
    }
}
