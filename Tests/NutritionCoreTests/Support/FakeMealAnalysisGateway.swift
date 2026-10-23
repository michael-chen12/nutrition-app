import Foundation
import NutritionCore

/// Test double for the single external boundary. Feature tests fake ONLY this boundary;
/// review logic, nutrient calculation and persistence stay real.
final class FakeMealAnalysisGateway: MealAnalysisGateway {
    var foodSearchResults: [String: [Food]] = [:]
    /// What photo analysis answers; unavailable unless a test sets it.
    var photoAnalysisResult: Result<MealPhotoAnalysisResponse, Error> = .failure(
        MealAnalysisGatewayError.analysisUnavailable
    )
    /// Every photo analysis request received, i.e. every upload.
    private(set) var photoAnalysisRequests: [MealPhotoAnalysisRequest] = []

    func searchFoods(matching query: String) async throws -> [Food] {
        foodSearchResults[query] ?? []
    }

    func analyzeMealPhotos(_ request: MealPhotoAnalysisRequest) async throws -> MealPhotoAnalysisResponse {
        photoAnalysisRequests.append(request)
        return try photoAnalysisResult.get()
    }
}
