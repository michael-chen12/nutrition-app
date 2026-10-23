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
            // Photos of a reopened saved meal entry are already held by the store.
            present(entry) { photo in draftPhotoData[photo.id] ?? (try? store.photoData(for: photo)) ?? Data() }
        }
    }

    /// Begins a new, empty meal entry dated now, discarding any unsaved draft.
    public func startNewMealEntry() {
        draft = MealEntry(date: now())
        draftPhotoData = [:]
    }

    /// Adds an imported meal photo to the draft. It is retained locally when the meal entry is saved.
    /// A meal entry takes any number of photos: other angles of the same food and additional dishes.
    @discardableResult
    public func importPhoto(_ imageData: Data, fileExtension: String) -> MealPhoto.ID {
        let photo = MealPhoto(fileExtension: fileExtension)
        editDraft { $0.photos.append(photo) }
        draftPhotoData[photo.id] = imageData
        return photo.id
    }

    /// Adds a custom food with a gram amount to the draft, optionally noting which meal photos show it.
    @discardableResult
    public func addCustomFood(
        _ customFood: CustomFood,
        grams: Double,
        shownIn photoIDs: [MealPhoto.ID] = []
    ) throws -> ReviewedFood.ID {
        try addReviewedFood(Food(customFood), grams: grams, shownIn: photoIDs)
    }

    /// Adds a food chosen from search results with a gram amount to the draft, optionally noting which
    /// meal photos show it. Its nutrient values and source reference come from the documented record.
    @discardableResult
    public func addFood(
        _ searchResult: FoodSearchResult,
        grams: Double,
        shownIn photoIDs: [MealPhoto.ID] = []
    ) throws -> ReviewedFood.ID {
        try addReviewedFood(searchResult.food, grams: grams, shownIn: photoIDs)
    }

    /// Adds a food chosen from search results with a portion in grams or one of its serving units
    /// (see `FoodSearchResult.portionUnits`). A serving unit without a documented gram weight is refused.
    @discardableResult
    public func addFood(
        _ searchResult: FoodSearchResult,
        quantity: Double,
        unit: PortionUnit,
        shownIn photoIDs: [MealPhoto.ID] = []
    ) throws -> ReviewedFood.ID {
        let portion = try makePortion(quantity: quantity, unit: unit, for: searchResult.food)
        return try addReviewedFood(searchResult.food, portion: portion, shownIn: photoIDs)
    }

    /// Reopens a saved meal entry for review, discarding any unsaved draft. Its meal photos, reviewed foods,
    /// uncertainty notes and source references come along; saving replaces the same meal entry (same
    /// identity, same date) with a nutrition estimate recalculated from its foods at that time.
    public func editMealEntry(id: MealEntry.ID) throws {
        guard let entry = try store.mealEntry(id: id) else { throw MealEntryWorkflowError.mealEntryNotFound(id) }
        draft = entry
        draftPhotoData = [:]
    }

    /// Changes the gram amount of a food in the draft (replacing any serving unit it was entered in).
    /// Its nutrition estimate follows the new portion.
    public func changePortion(of foodID: ReviewedFood.ID, grams: Double) throws {
        try changePortion(of: foodID, quantity: grams, unit: .grams)
    }

    /// Removes a food from the draft; it no longer counts toward the nutrition estimate.
    public func removeFood(_ foodID: ReviewedFood.ID) throws {
        let index = try draftFoodIndex(foodID)
        editDraft { _ = $0.reviewedFoods.remove(at: index) }
    }

    /// Records that a food already in the draft is also visible in another meal photo (a repeated view,
    /// e.g. another angle). The food still counts once; the nutrition estimate does not change.
    public func markFood(_ foodID: ReviewedFood.ID, asAlsoShownIn photoID: MealPhoto.ID) throws {
        try requireDraftPhotos([photoID])
        let index = try draftFoodIndex(foodID)
        editDraft { entry in
            if !entry.reviewedFoods[index].photoIDs.contains(photoID) {
                entry.reviewedFoods[index].photoIDs.append(photoID)
            }
        }
    }

    /// Combines a food the person entered again from another photo (a repeated view) into the food it
    /// duplicates, so it counts once. The kept food keeps its portion; the photos showing either are kept,
    /// along with any uncertainty notes of both.
    public func combineFood(_ repeatedFoodID: ReviewedFood.ID, into keptFoodID: ReviewedFood.ID) throws {
        let repeatedIndex = try draftFoodIndex(repeatedFoodID)
        _ = try draftFoodIndex(keptFoodID)
        guard repeatedFoodID != keptFoodID else { return }
        editDraft { entry in
            let repeated = entry.reviewedFoods.remove(at: repeatedIndex)
            let keptIndex = entry.reviewedFoods.firstIndex { $0.id == keptFoodID }!
            entry.reviewedFoods[keptIndex].photoIDs = (entry.reviewedFoods[keptIndex].photoIDs + repeated.photoIDs)
                .uniqued()
            entry.reviewedFoods[keptIndex].uncertaintyNotes = (
                entry.reviewedFoods[keptIndex].uncertaintyNotes + repeated.uncertaintyNotes
            ).uniqued()
        }
    }

    /// Corrects a reviewed food's portion, in grams or in one of the food's serving units. The nutrition
    /// estimate is recalculated from the effective grams; the food and its source reference are unchanged.
    /// A serving unit without a documented gram weight is refused rather than converted by a guess.
    public func changePortion(of foodID: ReviewedFood.ID, quantity: Double, unit: PortionUnit) throws {
        let index = try draftFoodIndex(foodID)
        let portion = try makePortion(quantity: quantity, unit: unit, for: draft!.reviewedFoods[index].food)
        editDraft { $0.reviewedFoods[index].portion = portion }
    }

    // MARK: Food search

    /// Searches documented nutrition sources through the external boundary. Each result shows where
    /// its values come from.
    public func searchFoods(matching query: String) async throws -> FoodSearchPresentation {
        let foods = try await gateway.searchFoods(matching: query)
        return FoodSearchPresentation(query: query, results: foods.map(FoodSearchResult.init))
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

    private func addReviewedFood(_ food: Food, grams: Double, shownIn photoIDs: [MealPhoto.ID]) throws -> ReviewedFood.ID {
        try addReviewedFood(food, portion: makePortion(quantity: grams, unit: .grams, for: food), shownIn: photoIDs)
    }

    private func addReviewedFood(_ food: Food, portion: Portion, shownIn photoIDs: [MealPhoto.ID]) throws -> ReviewedFood.ID {
        try requireDraftPhotos(photoIDs)
        let reviewedFood = ReviewedFood(food: food, portion: portion, photoIDs: photoIDs.uniqued())
        editDraft { $0.reviewedFoods.append(reviewedFood) }
        return reviewedFood.id
    }

    private func makePortion(quantity: Double, unit: PortionUnit, for food: Food) throws -> Portion {
        switch unit {
        case .grams:
            guard quantity.isFinite, quantity > 0 else { throw MealEntryWorkflowError.invalidGramAmount }
            return Portion(grams: quantity)
        case .serving(let servingUnit):
            guard food.servingUnits.contains(servingUnit) else {
                throw MealEntryWorkflowError.servingUnitNotAvailable(unitName: servingUnit.name)
            }
            guard quantity.isFinite, quantity > 0 else { throw MealEntryWorkflowError.invalidServingQuantity }
            guard let portion = Portion(quantity: quantity, of: servingUnit) else {
                throw MealEntryWorkflowError.servingConversionUnavailable(unitName: servingUnit.name)
            }
            return portion
        }
    }

    private func editDraft(_ change: (inout MealEntry) -> Void) {
        if draft == nil { startNewMealEntry() }
        change(&draft!)
    }

    private func requireDraftPhotos(_ photoIDs: [MealPhoto.ID]) throws {
        let draftPhotoIDs = Set(draft?.photos.map(\.id) ?? [])
        if let unknown = photoIDs.first(where: { !draftPhotoIDs.contains($0) }) {
            throw MealEntryWorkflowError.photoNotInMealEntry(unknown)
        }
    }

    private func draftFoodIndex(_ foodID: ReviewedFood.ID) throws -> Int {
        guard let index = draft?.reviewedFoods.firstIndex(where: { $0.id == foodID }) else {
            throw MealEntryWorkflowError.foodNotInMealEntry(foodID)
        }
        return index
    }

    private func present(_ entry: MealEntry, photoData: (MealPhoto) throws -> Data) rethrows -> MealEntryPresentation {
        let photoNumbers = Dictionary(uniqueKeysWithValues: entry.photos.enumerated().map { ($1.id, $0 + 1) })
        return MealEntryPresentation(
            id: entry.id,
            date: entry.date,
            photos: try entry.photos.enumerated().map { offset, photo in
                PresentedMealPhoto(id: photo.id, number: offset + 1, imageData: try photoData(photo))
            },
            foods: entry.reviewedFoods.map { PresentedReviewedFood($0, photoNumbers: photoNumbers) },
            nutritionEstimate: PresentedNutritionEstimate(entry.nutritionEstimate)
        )
    }
}

public enum MealEntryWorkflowError: Error, Equatable {
    case noMealEntryInProgress
    /// A portion must be a positive, finite number of grams.
    case invalidGramAmount
    case mealEntryNotFound(MealEntry.ID)
    /// The referenced meal photo is not part of the meal entry under review.
    case photoNotInMealEntry(MealPhoto.ID)
    /// The referenced food is not part of the meal entry under review.
    case foodNotInMealEntry(ReviewedFood.ID)
    /// The serving unit has no documented gram weight, so it cannot be converted; enter grams instead.
    case servingConversionUnavailable(unitName: String)
    /// A serving quantity must be a positive, finite number.
    case invalidServingQuantity
    /// The serving unit is not one documented for this food.
    case servingUnitNotAvailable(unitName: String)
}

extension Array where Element: Hashable {
    /// The elements in order, keeping only the first occurrence of each.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
