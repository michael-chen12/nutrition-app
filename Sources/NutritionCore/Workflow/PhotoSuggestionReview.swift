import Foundation

// Hosted photo suggestions in the meal entry workflow (ticket #9).
//
// A person accepts the photo analysis disclosure, uploads a meal photo for analysis, and reviews the suggested
// foods. A suggestion becomes a reviewed food only when the person accepts it as a documented food (looked up
// through `MealAnalysisGateway.searchFoods`) or a custom food; the analysis never supplies nutrient values.
// Failures leave the draft untouched with a clear message, so the person can finish manually.

extension MealEntryWorkflow {
    /// Shown before any photo is uploaded. Accept it with `acceptPhotoAnalysisDisclosure()`.
    public var photoAnalysisDisclosure: PhotoAnalysisDisclosure { PhotoAnalysisDisclosure() }

    /// Records that the person read and accepted the disclosure; photo analysis is refused until then.
    public func acceptPhotoAnalysisDisclosure() {
        photoAnalysisDisclosureAccepted = true
    }

    /// The suggestions awaiting review for the draft, with the latest analysis message; nil before analysis.
    public var photoSuggestionReview: PhotoAnalysisPresentation? {
        photoSuggestions.map(present)
    }

    /// Uploads one draft meal photo for hosted analysis and looks up documented foods for each suggestion.
    ///
    /// New suggestions join any still awaiting review. When analysis is unavailable or its output unusable,
    /// the returned presentation carries a message and the draft is unchanged, so the person can add foods
    /// manually. Throws only when the disclosure was not accepted or the photo is not in the draft.
    @discardableResult
    public func analyzePhoto(_ photoID: MealPhoto.ID) async throws -> PhotoAnalysisPresentation {
        try await analyzePhotos([photoID])
    }

    /// Accepts a suggestion as one of its documented matches with the suggested portion, converted for that
    /// food (see `SuggestedFoodMatch.suggestedPortion`). Throws `suggestedPortionUnavailable` when the
    /// suggestion's portion cannot be converted for that food; accept it with a portion instead.
    @discardableResult
    public func acceptSuggestion(_ suggestionID: PresentedFoodSuggestion.ID, as match: SuggestedFoodMatch) throws
        -> ReviewedFood.ID {
        let pending = try pendingSuggestion(suggestionID)
        guard let portion = Self.suggestedPortion(pending.suggestion.portion, for: match.result.food) else {
            throw MealEntryWorkflowError.suggestedPortionUnavailable
        }
        return try accept(pending, as: match.result.food, portion: portion)
    }

    /// Accepts a suggestion as a documented food — one of its matches or any food the person searched for —
    /// with the portion the person chose in grams or one of the food's serving units.
    @discardableResult
    public func acceptSuggestion(
        _ suggestionID: PresentedFoodSuggestion.ID,
        as searchResult: FoodSearchResult,
        quantity: Double,
        unit: PortionUnit
    ) throws -> ReviewedFood.ID {
        let pending = try pendingSuggestion(suggestionID)
        let portion = try makePortion(quantity: quantity, unit: unit, for: searchResult.food)
        return try accept(pending, as: searchResult.food, portion: portion)
    }

    /// Accepts a suggestion as a custom food with nutrition the person provides, when no documented food fits.
    @discardableResult
    public func acceptSuggestion(
        _ suggestionID: PresentedFoodSuggestion.ID,
        asCustomFood customFood: CustomFood,
        grams: Double
    ) throws -> ReviewedFood.ID {
        let pending = try pendingSuggestion(suggestionID)
        let food = Food(customFood)
        return try accept(pending, as: food, portion: try makePortion(quantity: grams, unit: .grams, for: food))
    }

    /// Rejects a suggestion: it is not added to the meal entry.
    public func rejectSuggestion(_ suggestionID: PresentedFoodSuggestion.ID) throws {
        _ = try pendingSuggestion(suggestionID)
        photoSuggestions?.pending.removeAll { $0.id == suggestionID }
    }

    // MARK: Analysis

    /// One analysis of the given draft photos. Multi-photo reconciliation can build on this.
    func analyzePhotos(_ photoIDs: [MealPhoto.ID]) async throws -> PhotoAnalysisPresentation {
        guard photoAnalysisDisclosureAccepted else { throw MealEntryWorkflowError.photoAnalysisDisclosureNotAccepted }
        try requireDraftPhotos(photoIDs)
        guard let entry = draft, !photoIDs.isEmpty else { throw MealEntryWorkflowError.noMealEntryInProgress }
        let photos = photoIDs.uniqued().compactMap { id in entry.photos.first { $0.id == id } }
        let request = MealPhotoAnalysisRequest(photos: try photos.map { photo in
            PhotoUpload(
                photoID: photo.id.uuidString,
                mediaType: Self.mediaType(forFileExtension: photo.fileExtension),
                imageData: try draftPhotoData[photo.id] ?? store.photoData(for: photo)
            )
        })

        var newSuggestions: [PendingSuggestion] = []
        var message: String?
        do {
            let response = try await gateway.analyzeMealPhotos(request)
            let suggestions = try Self.validated(response, photos: photos)
            for (suggestion, suggestionPhotoIDs) in suggestions {
                newSuggestions.append(await lookUp(suggestion, photoIDs: suggestionPhotoIDs))
            }
            if newSuggestions.isEmpty { message = PhotoAnalysisMessage.noFoodFound }
        } catch MealAnalysisGatewayError.malformedAnalysis {
            message = PhotoAnalysisMessage.malformed
        } catch {
            message = PhotoAnalysisMessage.unavailable
        }

        // The person may have moved on to another meal entry while the photo was being analyzed.
        guard draft?.id == entry.id else { throw MealEntryWorkflowError.noMealEntryInProgress }
        var state = photoSuggestions ?? PhotoSuggestionState()
        state.pending += newSuggestions
        state.message = message
        photoSuggestions = state
        return present(state)
    }

    /// Looks up documented foods for a suggestion through the boundary. A failed lookup leaves no matches;
    /// the person can still search themselves or add a custom food.
    private func lookUp(_ suggestion: FoodSuggestion, photoIDs: [MealPhoto.ID]) async -> PendingSuggestion {
        let matches: [Food]?
        do {
            matches = Array(try await gateway.searchFoods(matching: suggestion.searchQuery).prefix(5))
        } catch {
            matches = nil
        }
        return PendingSuggestion(suggestion: suggestion, photoIDs: photoIDs, matches: matches)
    }

    /// Each suggestion with the draft photos it refers to. Suggestions that name no analyzed photo, or no
    /// food, do not fit the contract.
    private static func validated(
        _ response: MealPhotoAnalysisResponse,
        photos: [MealPhoto]
    ) throws -> [(FoodSuggestion, [MealPhoto.ID])] {
        let photosByID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id.uuidString, $0.id) })
        return try response.suggestions.map { suggestion in
            let photoIDs = suggestion.photoIDs.compactMap { photosByID[$0] }
            guard !suggestion.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !photoIDs.isEmpty, photoIDs.count == suggestion.photoIDs.count else {
                throw MealAnalysisGatewayError.malformedAnalysis
            }
            return (suggestion, photoIDs.uniqued())
        }
    }

    // MARK: Review

    private func pendingSuggestion(_ id: PresentedFoodSuggestion.ID) throws -> PendingSuggestion {
        guard let pending = photoSuggestions?.pending.first(where: { $0.id == id }) else {
            throw MealEntryWorkflowError.suggestionNotFound(id)
        }
        return pending
    }

    private func accept(_ pending: PendingSuggestion, as food: Food, portion: Portion) throws -> ReviewedFood.ID {
        let foodID = try addReviewedFood(
            food,
            portion: portion,
            shownIn: pending.photoIDs,
            uncertaintyNotes: pending.suggestion.unresolvedDetails.map(UncertaintyNote.init)
        )
        photoSuggestions?.pending.removeAll { $0.id == pending.id }
        return foodID
    }

    /// The suggested portion for a food: grams as suggested, a serving unit the source documents a gram
    /// weight for, or else the analysis's gram estimate. Nil when only a guess could convert it.
    static func suggestedPortion(_ suggestion: PortionSuggestion?, for food: Food) -> Portion? {
        guard let suggestion, suggestion.quantity.isFinite, suggestion.quantity > 0 else { return nil }
        let unit = PortionUnitName(suggestion.unit)
        if unit.isGrams { return Portion(grams: suggestion.quantity) }
        if let servingUnit = food.servingUnits.first(where: { PortionUnitName($0.name).matches(unit) }),
           let portion = Portion(quantity: suggestion.quantity, of: servingUnit) {
            return portion
        }
        if let grams = suggestion.grams, grams.isFinite, grams > 0 { return Portion(grams: grams) }
        return nil
    }

    private static func mediaType(forFileExtension fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        default: return "image/\(fileExtension.lowercased())"
        }
    }

    // MARK: Presentation

    private func present(_ state: PhotoSuggestionState) -> PhotoAnalysisPresentation {
        let photoNumbers = Dictionary(
            uniqueKeysWithValues: (draft?.photos ?? []).enumerated().map { ($1.id, $0 + 1) }
        )
        return PhotoAnalysisPresentation(
            suggestions: state.pending.map { PresentedFoodSuggestion($0, photoNumbers: photoNumbers) },
            message: state.message
        )
    }
}

/// Suggestions from photo analysis awaiting review for the draft meal entry.
struct PhotoSuggestionState {
    var pending: [PendingSuggestion] = []
    /// The latest analysis's message (failure, or no food found); nil when it produced suggestions.
    var message: String?
}

struct PendingSuggestion {
    var id = UUID()
    var suggestion: FoodSuggestion
    var photoIDs: [MealPhoto.ID]
    /// Documented foods found for the suggestion's search query; nil when the lookup failed.
    var matches: [Food]?
}

/// A portion unit name as written by the analysis or a source, compared loosely: case, plural "s" and
/// qualifiers after a comma ("cup, chopped") are ignored.
private struct PortionUnitName {
    let base: String

    init(_ name: String) {
        var base = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let comma = base.firstIndex(of: ",") { base = String(base[..<comma]) }
        base = base.trimmingCharacters(in: .whitespaces)
        if base.count > 2, base.hasSuffix("s") { base.removeLast() }
        self.base = base
    }

    var isGrams: Bool { ["g", "gram", "gm"].contains(base) }

    func matches(_ other: PortionUnitName) -> Bool { base == other.base }
}

enum PhotoAnalysisMessage {
    static let unavailable = "Photo analysis isn't available right now. Your photo is still in this meal entry: "
        + "search for foods or add a custom food to finish it."
    static let malformed = "Photo analysis returned results the app couldn't use. Your photo is still in this "
        + "meal entry: search for foods or add a custom food to finish it."
    static let noFoodFound = "Photo analysis found no food in this photo. Search for foods or add a custom food "
        + "instead."
}

// MARK: - Presented to the person

/// What the person reads before any photo is uploaded for analysis.
///
/// The provider details reflect the Gemini API unpaid tier used by the prototype. Re-verify the provider's
/// current terms in the developer account before changing tier or accepting public uploads.
public struct PhotoAnalysisDisclosure: Hashable, Sendable {
    public var title = "Photo analysis uploads your photo"
    public var paragraphs = [
        "To suggest foods and portions, the photo you choose is uploaded to Google through this app's server "
            + "and analyzed by the Gemini API. Nothing is uploaded until you choose to upload it.",
        "This prototype uses the Gemini API's unpaid tier. On that tier, Google may use submitted photos and "
            + "its responses to improve its products, which can involve human review. Google keeps them under "
            + "its own terms, not this app's.",
        "Only analyze non-sensitive test photos: no people, faces, documents, screens or anything private.",
        "Your meal history stays on this iPhone. Suggestions are approximate: you review every food and portion, "
            + "and nutrition comes from documented food data or custom foods, never from the analysis.",
    ]
    public var uploadButtonTitle = "Upload photo for analysis"
    public var manualEntryButtonTitle = "Enter foods myself"
}

/// Photo suggestions awaiting review, as the person sees them.
public struct PhotoAnalysisPresentation: Hashable, Sendable {
    /// Suggestions not yet accepted or rejected.
    public var suggestions: [PresentedFoodSuggestion]
    /// Why the latest analysis produced no suggestions (failure or no food found), pointing to manual entry.
    public var message: String?
    public var reviewNote = "Suggestions from photo analysis are approximate. Check each food and portion; "
        + "nutrition comes only from the documented food or custom food you choose."
}

/// One suggested food awaiting review.
public struct PresentedFoodSuggestion: Hashable, Identifiable, Sendable {
    public var id: UUID
    /// The food as the analysis names it, e.g. "Steamed white rice".
    public var name: String
    /// The analysis's portion, e.g. "1 cup (about 158 g)" or "120 g"; nil when it made none.
    public var suggestedPortion: String?
    /// Which meal photos show it, e.g. "Photo 1".
    public var shownIn: String?
    /// Specific details the photo cannot settle; kept with the food when it is accepted.
    public var uncertaintyNotes: [String]
    /// Documented foods to accept it as, with their source.
    public var matches: [SuggestedFoodMatch]
    /// Shown when no documented food was found, pointing to search or a custom food.
    public var noMatchMessage: String?

    init(_ pending: PendingSuggestion, photoNumbers: [MealPhoto.ID: Int]) {
        id = pending.id
        name = pending.suggestion.name
        suggestedPortion = pending.suggestion.portion.map(Self.format)
        shownIn = PhotoReferenceFormat.shownIn(pending.photoIDs.compactMap { photoNumbers[$0] })
        uncertaintyNotes = pending.suggestion.unresolvedDetails.map(\.detail)
        matches = (pending.matches ?? []).map { SuggestedFoodMatch($0, portion: pending.suggestion.portion) }
        switch pending.matches {
        case nil:
            noMatchMessage = "Food search is unavailable. Search again or add \(name) as a custom food."
        case let matches? where matches.isEmpty:
            noMatchMessage = "No documented food matches \(name). Search for another name or add it as a custom food."
        default:
            noMatchMessage = nil
        }
    }

    private static func format(_ portion: PortionSuggestion) -> String {
        let unit = PortionUnitName(portion.unit)
        if unit.isGrams { return NutrientFormat.grams(portion.quantity) }
        let text = "\(PortionFormat.quantity(portion.quantity)) \(portion.unit)"
        return portion.grams.map { "\(text) (about \(NutrientFormat.grams($0)))" } ?? text
    }
}

/// A documented food a suggestion can be accepted as, with the suggested portion converted for it.
public struct SuggestedFoodMatch: Hashable, Identifiable, Sendable {
    public var id: String { result.id }
    public var result: FoodSearchResult
    /// e.g. "1 cup (158 g)" through the source's serving weight, or "120 g"; nil when the suggested portion
    /// cannot be converted for this food without guessing (the person enters a portion instead).
    public var suggestedPortion: String?
    /// The suggested portion in the unit and amount it would be accepted in, to prefill a portion editor.
    public var suggestedUnit: PortionUnit?
    public var suggestedQuantity: Double?

    init(_ food: Food, portion: PortionSuggestion?) {
        result = FoodSearchResult(food)
        let converted = MealEntryWorkflow.suggestedPortion(portion, for: food)
        suggestedPortion = converted.map(PortionFormat.portion)
        suggestedUnit = converted?.unit
        suggestedQuantity = converted?.quantity
    }
}
