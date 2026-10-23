import Foundation

/// The feature seam the SwiftUI views bind to. It drives a meal entry the way a person does
/// (start, import photos, add foods with portions, review, save) and serves meal history.
/// Every decision lives here or below so it is covered by tests on any platform.
public final class MealEntryWorkflow {
    private let store: MealHistoryStore
    private let gateway: MealAnalysisGateway
    private let now: () -> Date

    private var draft: MealEntry?
    private var draftPhotoData: [MealPhoto.ID: Data] = [:]

    public init(store: MealHistoryStore, gateway: MealAnalysisGateway, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.gateway = gateway
        self.now = now
    }

    // MARK: Draft meal entry

    /// The meal entry under review, as the person sees it; nil when no meal entry is in progress.
    public var draftReview: MealEntryPresentation? {
        draft.map { entry in
            present(entry) { photo in draftPhotoData[photo.id] ?? Data() }
        }
    }

    /// Begins a new, empty meal entry dated now, discarding any unsaved draft.
    public func startNewMealEntry() {
        draft = MealEntry(date: now())
        draftPhotoData = [:]
    }

    /// Adds an imported meal photo to the draft. It is retained locally when the meal entry is saved.
    public func importPhoto(_ imageData: Data, fileExtension: String) {
        let photo = MealPhoto(fileExtension: fileExtension)
        editDraft { $0.photos.append(photo) }
        draftPhotoData[photo.id] = imageData
    }

    /// Adds a custom food with a gram amount to the draft.
    public func addCustomFood(_ customFood: CustomFood, grams: Double) throws {
        guard grams.isFinite, grams > 0 else { throw MealEntryWorkflowError.invalidGramAmount }
        editDraft { $0.reviewedFoods.append(ReviewedFood(food: Food(customFood), portion: Portion(grams: grams))) }
    }

    /// Saves the draft to meal history and closes it.
    @discardableResult
    public func saveMealEntry() throws -> MealEntry.ID {
        guard let entry = draft else { throw MealEntryWorkflowError.noMealEntryInProgress }
        try store.save(entry, photoData: draftPhotoData)
        draft = nil
        draftPhotoData = [:]
        return entry.id
    }

    // MARK: Meal history

    /// Saved meal entries, most recent first.
    public func mealHistory() throws -> [MealHistoryRow] {
        try store.mealEntries()
            .sorted { $0.date > $1.date }
            .map { entry in
                MealHistoryRow(
                    id: entry.id,
                    date: entry.date,
                    foodNames: entry.reviewedFoods.map(\.food.name),
                    nutritionEstimate: PresentedNutritionEstimate(entry.nutritionEstimate)
                )
            }
    }

    /// A saved meal entry as the person sees it when reopening it from meal history.
    public func openMealEntry(id: MealEntry.ID) throws -> MealEntryPresentation {
        guard let entry = try store.mealEntry(id: id) else { throw MealEntryWorkflowError.mealEntryNotFound(id) }
        return try present(entry) { try store.photoData(for: $0) }
    }

    // MARK: Private

    private func editDraft(_ change: (inout MealEntry) -> Void) {
        if draft == nil { startNewMealEntry() }
        change(&draft!)
    }

    private func present(_ entry: MealEntry, photoData: (MealPhoto) throws -> Data) rethrows -> MealEntryPresentation {
        MealEntryPresentation(
            id: entry.id,
            date: entry.date,
            photos: try entry.photos.map { PresentedMealPhoto(id: $0.id, imageData: try photoData($0)) },
            foods: entry.reviewedFoods.map(PresentedReviewedFood.init),
            nutritionEstimate: PresentedNutritionEstimate(entry.nutritionEstimate)
        )
    }
}

public enum MealEntryWorkflowError: Error, Equatable {
    case noMealEntryInProgress
    /// A portion must be a positive, finite number of grams.
    case invalidGramAmount
    case mealEntryNotFound(MealEntry.ID)
}
