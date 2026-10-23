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
    /// Meal history by day, each with its daily pictured-food total.
    private(set) var historyDays: [MealHistoryDay] = []
    var errorMessage: String?

    init(workflow: MealEntryWorkflow) {
        self.workflow = workflow
        refreshHistory()
    }

    func startNewMealEntry() {
        workflow.startNewMealEntry()
        draftReview = workflow.draftReview
        photoAnalysis = workflow.photoSuggestionReview
    }

    /// Reopens a saved meal entry for review; saving replaces that same meal entry.
    func editMealEntry(_ id: MealEntry.ID) {
        perform { try workflow.editMealEntry(id: id) }
        draftReview = workflow.draftReview
        photoAnalysis = workflow.photoSuggestionReview
    }

    /// When the meal took place; decides its day in meal history.
    func changeDate(to date: Date) {
        workflow.changeDate(to: date)
        draftReview = workflow.draftReview
    }

    func changePortion(of foodID: ReviewedFood.ID, grams: Double) {
        perform { try workflow.changePortion(of: foodID, grams: grams) }
        draftReview = workflow.draftReview
    }

    func removeFood(_ foodID: ReviewedFood.ID) {
        perform { try workflow.removeFood(foodID) }
        draftReview = workflow.draftReview
    }

    func importPhoto(_ data: Data, fileExtension: String) {
        workflow.importPhoto(data, fileExtension: fileExtension)
        draftReview = workflow.draftReview
    }

    /// A camera capture that adds its photo to this draft meal entry, the same way as an imported photo.
    func makePhotoCapture() -> MealPhotoCaptureModel {
        let camera = AVFoundationMealPhotoCamera()
        return MealPhotoCaptureModel(camera: camera, capture: MealPhotoCapture(camera: camera, workflow: workflow))
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

    func addFood(_ result: FoodSearchResult, quantity: Double, unit: PortionUnit) {
        perform { _ = try workflow.addFood(result, quantity: quantity, unit: unit) }
        draftReview = workflow.draftReview
    }

    /// Corrects a reviewed food's portion in grams or a serving unit; the estimate updates immediately.
    func changePortion(of foodID: ReviewedFood.ID, quantity: Double, unit: PortionUnit) {
        perform { try workflow.changePortion(of: foodID, quantity: quantity, unit: unit) }
        draftReview = workflow.draftReview
    }

    func save() {
        perform { _ = try workflow.saveMealEntry() }
        draftReview = workflow.draftReview
        photoAnalysis = workflow.photoSuggestionReview
        refreshHistory()
    }

    // MARK: Photo suggestions

    /// Suggestions awaiting review and the latest analysis message; nil before any analysis.
    private(set) var photoAnalysis: PhotoAnalysisPresentation?
    private(set) var isAnalyzingPhoto = false

    /// Shown before every upload; see `PhotoAnalysisDisclosureView`.
    var photoAnalysisDisclosure: PhotoAnalysisDisclosure { workflow.photoAnalysisDisclosure }

    /// The person accepted the disclosure for this photo: upload it and show the suggestions (or why there
    /// are none, with the manual path still open).
    func uploadForAnalysis(_ photoID: MealPhoto.ID) async {
        await uploadForAnalysis([photoID])
    }

    /// The person accepted the disclosure for these photos: upload them together for one analysis, so
    /// repeated views of a food are grouped and distinct dishes kept.
    func uploadForAnalysis(_ photoIDs: [MealPhoto.ID]) async {
        workflow.acceptPhotoAnalysisDisclosure()
        isAnalyzingPhoto = true
        defer { isAnalyzingPhoto = false }
        do {
            photoAnalysis = try await workflow.analyzePhotos(photoIDs)
            errorMessage = nil
        } catch {
            errorMessage = photoIDs.count == 1
                ? "This photo can't be analyzed. You can still add foods yourself."
                : "These photos can't be analyzed. You can still add foods yourself."
        }
    }

    /// The grouped views are different foods after all: review each on its own.
    func separateSuggestion(_ id: PresentedFoodSuggestion.ID) {
        reviewSuggestion { _ = try workflow.separateSuggestion(id) }
    }

    func acceptSuggestion(_ id: PresentedFoodSuggestion.ID, as match: SuggestedFoodMatch) {
        reviewSuggestion { _ = try workflow.acceptSuggestion(id, as: match) }
    }

    func acceptSuggestion(
        _ id: PresentedFoodSuggestion.ID, as result: FoodSearchResult, quantity: Double, unit: PortionUnit
    ) {
        reviewSuggestion { _ = try workflow.acceptSuggestion(id, as: result, quantity: quantity, unit: unit) }
    }

    func acceptSuggestion(_ id: PresentedFoodSuggestion.ID, asCustomFood customFood: CustomFood, grams: Double) {
        reviewSuggestion { _ = try workflow.acceptSuggestion(id, asCustomFood: customFood, grams: grams) }
    }

    func rejectSuggestion(_ id: PresentedFoodSuggestion.ID) {
        reviewSuggestion { try workflow.rejectSuggestion(id) }
    }

    private func reviewSuggestion(_ action: () throws -> Void) {
        perform(action)
        draftReview = workflow.draftReview
        photoAnalysis = workflow.photoSuggestionReview
    }

    // MARK: Focused questions

    /// Answers a focused question by adding a documented food (e.g. the cooking oil).
    func answerQuestion(
        _ id: PresentedFocusedQuestion.ID, byAdding result: FoodSearchResult, quantity: Double, unit: PortionUnit
    ) {
        perform { _ = try workflow.answerQuestion(id, byAdding: result, quantity: quantity, unit: unit) }
        draftReview = workflow.draftReview
    }

    /// Answers a focused question by adding a custom food (e.g. a sauce with no documented match).
    func answerQuestion(_ id: PresentedFocusedQuestion.ID, byAddingCustomFood customFood: CustomFood, grams: Double) {
        perform { _ = try workflow.answerQuestion(id, byAddingCustomFood: customFood, grams: grams) }
        draftReview = workflow.draftReview
    }

    /// Answers a focused question by correcting the portion of the food it is about.
    func answerQuestion(_ id: PresentedFocusedQuestion.ID, byChangingPortionTo quantity: Double, unit: PortionUnit) {
        perform { try workflow.answerQuestion(id, byChangingPortionTo: quantity, unit: unit) }
        draftReview = workflow.draftReview
    }

    /// The detail doesn't apply (e.g. no oil was used).
    func dismissQuestion(_ id: PresentedFocusedQuestion.ID) {
        perform { try workflow.dismissQuestion(id) }
        draftReview = workflow.draftReview
    }

    func open(_ id: MealEntry.ID) -> MealEntryPresentation? {
        var opened: MealEntryPresentation?
        perform { opened = try workflow.openMealEntry(id: id) }
        return opened
    }

    private func refreshHistory() {
        perform { historyDays = try workflow.dailyMealHistory() }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            errorMessage = nil
        } catch MealEntryWorkflowError.invalidGramAmount {
            errorMessage = "Enter a gram amount greater than zero."
        } catch MealEntryWorkflowError.invalidServingQuantity {
            errorMessage = "Enter a serving amount greater than zero."
        } catch MealEntryWorkflowError.servingConversionUnavailable(let unitName) {
            errorMessage = "No gram weight is documented for \(unitName). Enter grams instead."
        } catch MealEntryWorkflowError.suggestedPortionUnavailable {
            errorMessage = "The suggested portion can't be converted for this food. Enter a portion instead."
        } catch MealEntryWorkflowError.questionNotFound {
            errorMessage = "This question has already been answered."
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
    }
}
