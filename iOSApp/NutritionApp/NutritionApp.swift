import Foundation
import NutritionCore
import SwiftUI

@main
struct NutritionApp: App {
    @State private var model = MealEntryModel(workflow: MealEntryWorkflow(
        store: try! FileMealHistoryStore(directory: .applicationSupportDirectory.appending(path: "MealHistory")),
        // Photo analysis goes through the backend (Backend/), which holds the provider key. Food lookup is not
        // served by the backend yet (USDA FoodData Central records normalized with `FoodDataCentralRecord`; the
        // API key stays on the backend); with no results, search points to a custom food.
        gateway: HTTPMealAnalysisGateway(backendURL: NutritionApp.analysisBackendURL)
    ))

    /// From the `MealAnalysisBackendURL` Info.plist key; defaults to a backend running on this Mac, which the
    /// iOS Simulator reaches as 127.0.0.1.
    static var analysisBackendURL: URL {
        (Bundle.main.object(forInfoDictionaryKey: "MealAnalysisBackendURL") as? String).flatMap(URL.init(string:))
            ?? URL(string: "http://127.0.0.1:8080")!
    }

    var body: some Scene {
        WindowGroup {
            MealHistoryView(model: model)
        }
    }
}
