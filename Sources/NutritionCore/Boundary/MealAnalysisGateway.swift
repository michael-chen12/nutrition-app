import Foundation
// The photo analysis wire types (`MealPhotoAnalysisRequest`, `FoodSuggestion`, ...) are part of this boundary.
@_exported import AnalysisContract

/// The app's single external boundary for photo suggestions and nutrition lookup.
///
/// Everything that comes from outside the iPhone (documented food records, and hosted photo suggestions with
/// uncertainty details) arrives through this protocol. The client owns review, deterministic calculation and
/// local persistence. Feature tests fake only this boundary.
///
/// Later work extends this protocol rather than introducing a second boundary.
public protocol MealAnalysisGateway: AnyObject {
    /// Documented food records matching a search, normalized to nutrients per 100 g with their source reference.
    func searchFoods(matching query: String) async throws -> [Food]

    /// Uploads meal photos for hosted analysis and returns suggestions to review: candidate foods, portion
    /// suggestions, cross-photo duplicate hints and specific unresolved details. Never nutrient values.
    ///
    /// Throws `MealAnalysisGatewayError` when analysis is unavailable or its output is unusable.
    func analyzeMealPhotos(_ request: MealPhotoAnalysisRequest) async throws -> MealPhotoAnalysisResponse
}

extension MealAnalysisGateway {
    /// Gateways without hosted analysis (e.g. food lookup only) report it as unavailable.
    public func analyzeMealPhotos(_ request: MealPhotoAnalysisRequest) async throws -> MealPhotoAnalysisResponse {
        throw MealAnalysisGatewayError.analysisUnavailable
    }
}

/// Why photo analysis produced no suggestions. Either way the person can finish the meal entry manually.
public enum MealAnalysisGatewayError: Error, Equatable, Sendable {
    /// The analysis service could not be reached, is not set up, or refused the request.
    case analysisUnavailable
    /// The analysis service answered with output that does not fit the contract.
    case malformedAnalysis
}
