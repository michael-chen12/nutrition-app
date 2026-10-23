import Foundation
import NutritionCore
import SwiftUI

@main
struct NutritionApp: App {
    @State private var model = MealEntryModel(workflow: MealEntryWorkflow(
        store: try! FileMealHistoryStore(directory: .applicationSupportDirectory.appending(path: "MealHistory")),
        // Photo analysis and food search go through the backend (Backend/), which holds the Gemini and USDA
        // FoodData Central keys; no key ships with the app.
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
