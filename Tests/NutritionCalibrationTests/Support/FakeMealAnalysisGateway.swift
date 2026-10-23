import Foundation
import NutritionCore

/// Test double for the single external boundary. Calibration tests fake ONLY this boundary;
/// review logic, nutrient calculation and persistence stay real.
final class FakeMealAnalysisGateway: MealAnalysisGateway {
    var foodSearchResults: [String: [Food]] = [:]
    /// Answers photo analysis from the request, since a trial's meal photo IDs are made during the trial;
    /// unavailable unless a test sets it.
    var photoAnalysisResponder: ((MealPhotoAnalysisRequest) throws -> MealPhotoAnalysisResponse)?
    /// Every photo analysis request received, i.e. every upload.
    private(set) var photoAnalysisRequests: [MealPhotoAnalysisRequest] = []

    func searchFoods(matching query: String) async throws -> [Food] {
        foodSearchResults[query] ?? []
    }

    func analyzeMealPhotos(_ request: MealPhotoAnalysisRequest) async throws -> MealPhotoAnalysisResponse {
        photoAnalysisRequests.append(request)
        guard let photoAnalysisResponder else { throw MealAnalysisGatewayError.analysisUnavailable }
        return try photoAnalysisResponder(request)
    }
}
