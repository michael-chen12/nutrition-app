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

    func addCustomFood(_ customFood: CustomFood, grams: Double) {
        perform { try workflow.addCustomFood(customFood, grams: grams) }
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
