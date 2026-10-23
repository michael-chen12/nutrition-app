import Foundation

/// The app's single external boundary for photo suggestions and nutrition lookup.
///
/// Everything that comes from outside the iPhone (documented food records, and later hosted photo
/// suggestions with uncertainty details) arrives through this protocol. The client owns review,
/// deterministic calculation and local persistence. Feature tests fake only this boundary.
///
/// Later work adds photo suggestions here rather than introducing a second boundary.
public protocol MealAnalysisGateway: AnyObject {
    /// Documented food records matching a search, normalized to nutrients per 100 g with their source reference.
    func searchFoods(matching query: String) async throws -> [Food]
}
