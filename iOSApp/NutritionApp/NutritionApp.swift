import NutritionCore
import SwiftUI

@main
struct NutritionApp: App {
    @State private var model = MealEntryModel(workflow: MealEntryWorkflow(
        store: try! FileMealHistoryStore(directory: .applicationSupportDirectory.appending(path: "MealHistory")),
        gateway: NoFoodLookupGateway()
    ))

    var body: some Scene {
        WindowGroup {
            MealHistoryView(model: model)
        }
    }
}

/// Placeholder until the backend serves documented food lookup (USDA FoodData Central records normalized with
/// `FoodDataCentralRecord`; the API key stays on the backend). With no results, search points to a custom food.
final class NoFoodLookupGateway: MealAnalysisGateway {
    func searchFoods(matching query: String) async throws -> [Food] { [] }
}
