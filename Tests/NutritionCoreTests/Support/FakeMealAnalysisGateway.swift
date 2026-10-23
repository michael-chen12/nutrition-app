import Foundation
import NutritionCore

/// Test double for the single external boundary. Feature tests fake ONLY this boundary;
/// review logic, nutrient calculation and persistence stay real.
final class FakeMealAnalysisGateway: MealAnalysisGateway {
    var foodSearchResults: [String: [Food]] = [:]

    func searchFoods(matching query: String) async throws -> [Food] {
        foodSearchResults[query] ?? []
    }
}
