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

    /// What photo analysis alone estimates for the suggestions awaiting review: each accepted as offered, as its
    /// first documented match with the suggested portion (`acceptSuggestion(_:as:)`). Likely duplicates count
    /// once, as they are reviewed. Nil before analysis. Accuracy calibration compares it with the final reviewed
    /// estimate (ADR 0002).
    public var preReviewEstimate: PreReviewEstimate? {
        photoSuggestions.map { state in
            var estimates: [NutritionEstimate] = []
            var withoutEstimate: [String] = []
            for pending in state.pending {
                if let food = pending.matches?.first,
                   let suggested = Self.suggestedPortion(pending.suggestion.portion, for: food) {
                    estimates.append(NutritionEstimate(food.nutrientsPer100g, grams: suggested.portion.grams))
                } else {
                    withoutEstimate.append(pending.suggestion.name)
                }
            }
            return PreReviewEstimate(nutritionEstimate: estimates.total(), suggestionsWithoutEstimate: withoutEstimate)
        }
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
    /// suggestion's portion cannot be converted for that food; accept it with a portion instead. Grams the
    /// analysis estimated from the photo are kept with a portion uncertainty note.
    @discardableResult
    public func acceptSuggestion(_ suggestionID: PresentedFoodSuggestion.ID, as match: SuggestedFoodMatch) throws
        -> ReviewedFood.ID {
        let pending = try pendingSuggestion(suggestionID)
        let food = match.result.food
        guard let suggested = Self.suggestedPortion(pending.suggestion.portion, for: food) else {
            throw MealEntryWorkflowError.suggestedPortionUnavailable
        }
        let estimateNote = suggested.isPhotoEstimate
            ? Self.photoEstimateNote(for: food, suggestion: pending.suggestion)
            : nil
        return try accept(
            pending, as: food, portion: suggested.portion, asSuggested: true, adding: estimateNote.map { [$0] } ?? []
        )
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
        let isSuggestedMatch = pending.matches?.contains(searchResult.food) ?? false
        return try accept(pending, as: searchResult.food, portion: portion, asSuggested: isSuggestedMatch)
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
        let portion = try makePortion(quantity: grams, unit: .grams, for: food)
        return try accept(pending, as: food, portion: portion, asSuggested: false)
    }

    /// Separates a suggestion that joins likely views of the same food into one suggestion per view, in its
    /// place, when they are in fact different foods (e.g. two plates of the same dish). Each is then reviewed
    /// and counted on its own. Returns the separate suggestions; a suggestion with no views to separate
    /// stays as it is.
    @discardableResult
    public func separateSuggestion(_ suggestionID: PresentedFoodSuggestion.ID) throws -> [PresentedFoodSuggestion.ID] {
        let pending = try pendingSuggestion(suggestionID)
        guard let views = pending.likelyDuplicates?.views,
              let index = photoSuggestions?.pending.firstIndex(where: { $0.id == suggestionID }) else {
            return [suggestionID]
        }
        photoSuggestions?.pending.replaceSubrange(index...index, with: views)
        return views.map(\.id)
    }

    /// Rejects a suggestion: it is not added to the meal entry.
    public func rejectSuggestion(_ suggestionID: PresentedFoodSuggestion.ID) throws {
        _ = try pendingSuggestion(suggestionID)
        photoSuggestions?.pending.removeAll { $0.id == suggestionID }
    }

    // MARK: Analysis

    /// Uploads several draft meal photos together for one hosted analysis: other angles of the same food and
    /// additional dishes. Suggestions the analysis finds likely to be the same food seen in different photos
    /// are grouped into one suggestion that counts once unless the person separates it
    /// (`separateSuggestion(_:)`); distinct foods stay separate. Failures behave as in `analyzePhoto(_:)`.
    @discardableResult
    public func analyzePhotos(_ photoIDs: [MealPhoto.ID]) async throws -> PhotoAnalysisPresentation {
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
            var lookedUp: [PendingSuggestion] = []
            var matchesByQuery: [String: [Food]?] = [:]
            for (suggestion, suggestionPhotoIDs) in suggestions {
                lookedUp.append(await lookUp(suggestion, photoIDs: suggestionPhotoIDs, cache: &matchesByQuery))
            }
            newSuggestions = Self.groupingLikelyDuplicates(lookedUp, hints: response.duplicateGroups)
            if newSuggestions.isEmpty { message = PhotoAnalysisMessage.noFoodFound(photoCount: photos.count) }
        } catch MealAnalysisGatewayError.malformedAnalysis {
            message = PhotoAnalysisMessage.malformed(photoCount: photos.count)
        } catch {
            message = PhotoAnalysisMessage.unavailable(photoCount: photos.count)
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
    /// Repeated queries within one analysis (the same food seen in several photos) are looked up once.
    private func lookUp(
        _ suggestion: FoodSuggestion,
        photoIDs: [MealPhoto.ID],
        cache: inout [String: [Food]?]
    ) async -> PendingSuggestion {
        let matches: [Food]?
        if let cached = cache[suggestion.searchQuery] {
            matches = cached
        } else {
            do {
                matches = Array(try await gateway.searchFoods(matching: suggestion.searchQuery).prefix(5))
            } catch {
                matches = nil
            }
            cache[suggestion.searchQuery] = .some(matches)
        }
        return PendingSuggestion(suggestion: suggestion, photoIDs: photoIDs, matches: matches)
    }

    /// Joins suggestions the analysis hints are the same food seen in different photos into one suggestion
    /// that keeps its views, so it counts once until the person separates it. Overlapping hints join into
    /// one group. A hint that would join suggestions seen in the same photo is not followed: one photo showing
    /// two of a food shows two foods. A hint naming a suggestion that is not listed exactly once is ignored; the
    /// suggestions it names are still reviewed on their own.
    static func groupingLikelyDuplicates(
        _ suggestions: [PendingSuggestion],
        hints: [DuplicateGroupHint]
    ) -> [PendingSuggestion] {
        guard !hints.isEmpty else { return suggestions }
        var indicesByID: [String: [Int]] = [:]
        for (index, pending) in suggestions.enumerated() { indicesByID[pending.suggestion.id, default: []].append(index) }

        // Groups of suggestion indices in review order, each with the first reason given for it.
        var groups: [(members: [Int], reason: String?)] = suggestions.indices.map { ([$0], nil) }
        for hint in hints {
            let members = hint.suggestionIDs.compactMap { id in
                indicesByID[id].flatMap { $0.count == 1 ? $0[0] : nil }
            }
            guard members.count == hint.suggestionIDs.count else { continue }
            let slots = Set(members.map { member in groups.firstIndex { $0.members.contains(member) }! }).sorted()
            guard slots.count > 1 else { continue }
            let joined = slots.flatMap { groups[$0].members }.sorted()
            let photoIDs = joined.flatMap { suggestions[$0].photoIDs }
            guard Set(photoIDs).count == photoIDs.count else { continue }
            let reason = slots.lazy.compactMap { groups[$0].reason }.first ?? hint.reason.flatMap(\.nonBlank)
            groups[slots[0]] = (joined, reason)
            for slot in slots.dropFirst().reversed() { groups.remove(at: slot) }
        }
        return groups.map { members, reason in
            members.count == 1
                ? suggestions[members[0]]
                : PendingSuggestion(likelyDuplicates: members.map { suggestions[$0] }, reason: reason)
        }
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

    /// Adds the suggestion as a reviewed food with its unresolved details and `additionalNotes`. `asSuggested`
    /// says whether the person kept the food the analysis matched (one of its documented matches) rather than
    /// correcting it to another food; a weak match kept that way stays in doubt as an identity note.
    private func accept(
        _ pending: PendingSuggestion,
        as food: Food,
        portion: Portion,
        asSuggested: Bool,
        adding additionalNotes: [UncertaintyNote] = []
    ) throws -> ReviewedFood.ID {
        var notes = pending.suggestion.unresolvedDetails.map(UncertaintyNote.init) + additionalNotes
        if asSuggested, pending.suggestion.isWeakMatch {
            notes.append(UncertaintyNote(
                detail: "Weak match: photo analysis wasn't sure this is \(pending.suggestion.name)",
                kind: .identity,
                question: "Is \(food.name) the right food?"
            ))
        }
        let foodID = try addReviewedFood(food, portion: portion, shownIn: pending.photoIDs, uncertaintyNotes: notes)
        photoSuggestions?.pending.removeAll { $0.id == pending.id }
        return foodID
    }

    /// The suggested portion for a food: grams as suggested, a serving unit the source documents a gram
    /// weight for, or else the analysis's gram estimate. Nil when only a guess could convert it.
    static func suggestedPortion(_ suggestion: PortionSuggestion?, for food: Food) -> SuggestedPortion? {
        guard let suggestion, suggestion.quantity.isFinite, suggestion.quantity > 0 else { return nil }
        let unit = PortionUnitName(suggestion.unit)
        if unit.isGrams {
            return SuggestedPortion(portion: Portion(grams: suggestion.quantity), isPhotoEstimate: true)
        }
        if let servingUnit = food.servingUnits.first(where: { PortionUnitName($0.name).matches(unit) }),
           let portion = Portion(quantity: suggestion.quantity, of: servingUnit) {
            return SuggestedPortion(portion: portion, isPhotoEstimate: false)
        }
        if let grams = suggestion.grams, grams.isFinite, grams > 0 {
            return SuggestedPortion(portion: Portion(grams: grams), isPhotoEstimate: true)
        }
        return nil
    }

    /// Kept with a food accepted with grams the analysis estimated from the photo, so the precise-looking amount
    /// stays open to correction. Not added when the analysis already noted the portion as unresolved.
    private static func photoEstimateNote(for food: Food, suggestion: FoodSuggestion) -> UncertaintyNote? {
        guard !suggestion.unresolvedDetails.contains(where: { $0.kind == .portion }) else { return nil }
        return UncertaintyNote(
            detail: "Portion estimated from the photo", kind: .portion, question: "How much \(food.name) was there?"
        )
    }

    private static func mediaType(forFileExtension fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        default: return "image/\(fileExtension.lowercased())"
        }
    }

    // MARK: Presentation

    private func present(_ state: PhotoSuggestionState) -> PhotoAnalysisPresentation {
        let photoNumbers = PresentedMealPhoto.numbers(of: draft?.photos ?? [])
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
    /// Set when this suggestion joins likely views of one food from different photos.
    var likelyDuplicates: LikelyDuplicates?
}

/// Suggestions from different photos that likely show the same food, reviewed as one.
struct LikelyDuplicates {
    /// Each photo's suggestion, as reviewed separately if the person separates them.
    var views: [PendingSuggestion]
    /// Why the analysis thinks they are the same food, if it said.
    var reason: String?
}

extension PendingSuggestion {
    /// One suggestion for likely views of the same food: named and looked up as the first view, shown in
    /// every view's photos, with the first suggested portion and every view's unresolved details. Accepting
    /// it adds one reviewed food shown in all those photos.
    init(likelyDuplicates views: [PendingSuggestion], reason: String?) {
        let first = views[0]
        var suggestion = first.suggestion
        suggestion.photoIDs = views.flatMap(\.suggestion.photoIDs).uniqued()
        suggestion.portion = views.lazy.compactMap(\.suggestion.portion).first
        suggestion.unresolvedDetails = views.flatMap(\.suggestion.unresolvedDetails).uniqued()
        // The group is only as sure as its least sure view.
        if let weakView = views.first(where: \.suggestion.isWeakMatch) {
            suggestion.matchConfidence = weakView.suggestion.matchConfidence
        }
        self.init(
            suggestion: suggestion,
            photoIDs: views.flatMap(\.photoIDs).uniqued(),
            matches: first.matches,
            likelyDuplicates: LikelyDuplicates(views: views, reason: reason)
        )
    }
}

extension FoodSuggestion {
    /// The analysis rated its identity low, or gave no rating: the person is asked to check it.
    var isWeakMatch: Bool {
        matchConfidence == nil || matchConfidence == .low
    }
}

private extension String {
    /// The text trimmed, or nil when nothing is left.
    var nonBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
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

/// Why an analysis of `photoCount` photos produced no suggestions, worded for one photo or several.
enum PhotoAnalysisMessage {
    static func unavailable(photoCount: Int) -> String {
        "Photo analysis isn't available right now. \(stillInMealEntry(photoCount)): "
            + "search for foods or add a custom food to finish it."
    }

    static func malformed(photoCount: Int) -> String {
        "Photo analysis returned results the app couldn't use. \(stillInMealEntry(photoCount)): "
            + "search for foods or add a custom food to finish it."
    }

    static func noFoodFound(photoCount: Int) -> String {
        "Photo analysis found no food in \(photoCount == 1 ? "this photo" : "these photos"). "
            + "Search for foods or add a custom food instead."
    }

    private static func stillInMealEntry(_ photoCount: Int) -> String {
        photoCount == 1 ? "Your photo is still in this meal entry" : "Your photos are still in this meal entry"
    }
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
    /// Shown when photo analysis was unsure (or didn't say) that this is the named food, asking the person to
    /// check it. Accepting one of its matches unchanged keeps that doubt as an uncertainty note.
    public var checkMatchPrompt: String?
    /// Documented foods to accept it as, with their source.
    public var matches: [SuggestedFoodMatch]
    /// Shown when no documented food was found, pointing to search or a custom food.
    public var noMatchMessage: String?
    /// Set when the suggestion joins likely views of the same food from different photos, which count once
    /// unless the person separates them (`MealEntryWorkflow.separateSuggestion(_:)`).
    public var likelyDuplicateNote: String?

    init(_ pending: PendingSuggestion, photoNumbers: [MealPhoto.ID: Int]) {
        id = pending.id
        name = pending.suggestion.name
        suggestedPortion = pending.suggestion.portion.map(Self.format)
        let shownIn = PhotoReferenceFormat.shownIn(pending.photoIDs.compactMap { photoNumbers[$0] })
        self.shownIn = shownIn
        likelyDuplicateNote = pending.likelyDuplicates.map { group in
            let seen = shownIn.map { "Likely the same food seen in \($0)" } ?? "Likely the same food"
            let reason = group.reason.map { " (\($0))" } ?? ""
            return "\(seen)\(reason). It counts once unless you separate it."
        }
        uncertaintyNotes = pending.suggestion.unresolvedDetails.map(\.detail)
        checkMatchPrompt = pending.suggestion.isWeakMatch
            ? "Check this match: photo analysis isn't sure this is \(name). Compare it with your photo, "
                + "or choose another food."
            : nil
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
    /// e.g. "1 cup (158 g)" through the source's serving weight, or "About 120 g, estimated from the photo" for
    /// grams the analysis estimated; nil when the suggested portion cannot be converted for this food without
    /// guessing (the person enters a portion instead).
    public var suggestedPortion: String?
    /// The suggested portion in the unit and amount it would be accepted in, to prefill a portion editor.
    public var suggestedUnit: PortionUnit?
    public var suggestedQuantity: Double?

    init(_ food: Food, portion: PortionSuggestion?) {
        result = FoodSearchResult(food)
        let converted = MealEntryWorkflow.suggestedPortion(portion, for: food)
        suggestedPortion = converted.map { suggested in
            suggested.isPhotoEstimate
                ? "About \(PortionFormat.portion(suggested.portion)), estimated from the photo"
                : PortionFormat.portion(suggested.portion)
        }
        suggestedUnit = converted?.portion.unit
        suggestedQuantity = converted?.portion.quantity
    }
}

/// The nutrition estimate of photo suggestions accepted as offered (`MealEntryWorkflow.preReviewEstimate`).
public struct PreReviewEstimate: Hashable, Sendable {
    public var nutritionEstimate: NutritionEstimate
    /// Suggestions that add nothing to it: no documented food was found for them, or their portion cannot be
    /// converted for the food found without guessing.
    public var suggestionsWithoutEstimate: [String]
}

/// A suggested portion converted for one food.
struct SuggestedPortion {
    var portion: Portion
    /// The grams are the analysis's estimate from the photo, not a documented serving weight.
    var isPhotoEstimate: Bool
}
