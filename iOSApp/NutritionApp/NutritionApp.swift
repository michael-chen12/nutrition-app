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

/// Placeholder until documented food lookup is wired in; manual meal entry needs no external calls.
final class NoFoodLookupGateway: MealAnalysisGateway {
    func searchFoods(matching query: String) async throws -> [Food] { [] }
}
