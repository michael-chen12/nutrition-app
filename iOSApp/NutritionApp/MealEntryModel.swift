import Foundation
import NutritionCore
import Observation

/// Observable mirror of `MealEntryWorkflow` for SwiftUI. Holds no decisions of its own:
/// every call forwards to the workflow and republishes what the person should now see.
@Observable
@MainActor
final class MealEntryModel {
    private let workflow: MealEntryWorkflow

    private(set) var draftReview: MealEntryPresentation?
    private(set) var history: [MealHistoryRow] = []
    var errorMessage: String?

    init(workflow: MealEntryWorkflow) {
        self.workflow = workflow
        refreshHistory()
    }

    func startNewMealEntry() {
        workflow.startNewMealEntry()
        draftReview = workflow.draftReview
    }

    func importPhoto(_ data: Data, fileExtension: String) {
        workflow.importPhoto(data, fileExtension: fileExtension)
        draftReview = workflow.draftReview
    }

    /// A camera capture that adds its photo to this draft meal entry, the same way as an imported photo.
    func makePhotoCapture() -> MealPhotoCaptureModel {
        let camera = AVFoundationMealPhotoCamera()
        return MealPhotoCaptureModel(camera: camera, capture: MealPhotoCapture(camera: camera, mealEntry: workflow))
    }

    /// Republishes the draft after the camera capture closes.
    func refreshDraftReview() {
        draftReview = workflow.draftReview
    }

    func addCustomFood(_ customFood: CustomFood, grams: Double, shownIn photoIDs: [MealPhoto.ID] = []) {
        perform { _ = try workflow.addCustomFood(customFood, grams: grams, shownIn: photoIDs) }
        draftReview = workflow.draftReview
    }

    /// The same food seen from another angle: note the photo without counting the food again.
    func markFood(_ foodID: ReviewedFood.ID, asAlsoShownIn photoID: MealPhoto.ID) {
        perform { try workflow.markFood(foodID, asAlsoShownIn: photoID) }
        draftReview = workflow.draftReview
    }

    /// A food entered again from another photo is the same food: combine so it counts once.
    func combineFood(_ repeatedFoodID: ReviewedFood.ID, into keptFoodID: ReviewedFood.ID) {
        perform { try workflow.combineFood(repeatedFoodID, into: keptFoodID) }
        draftReview = workflow.draftReview
    }

    private(set) var foodSearch: FoodSearchPresentation?

    func searchFoods(matching query: String) async {
        do {
            foodSearch = try await workflow.searchFoods(matching: query)
            errorMessage = nil
        } catch {
            errorMessage = "Food search is unavailable. You can add a custom food instead."
        }
    }

    func addFood(_ result: FoodSearchResult, grams: Double) {
        perform { _ = try workflow.addFood(result, grams: grams) }
        draftReview = workflow.draftReview
    }

    func save() {
        perform { _ = try workflow.saveMealEntry() }
        draftReview = workflow.draftReview
        refreshHistory()
    }

    func open(_ id: MealEntry.ID) -> MealEntryPresentation? {
        var opened: MealEntryPresentation?
        perform { opened = try workflow.openMealEntry(id: id) }
        return opened
    }

    private func refreshHistory() {
        perform { history = try workflow.mealHistory() }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch MealEntryWorkflowError.invalidGramAmount {
            errorMessage = "Enter a gram amount greater than zero."
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
    }
}
