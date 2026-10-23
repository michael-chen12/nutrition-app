import Foundation

// Focused questions about mixed dishes and hidden items (ticket #11).
//
// Each uncertainty note on a reviewed food is asked as a focused question ("Was it cooked in oil? How much?").
// The person answers by adding a food (a documented food or a custom food, e.g. the oil, a sauce or a drink
// the photos don't show), by correcting the food's portion, or dismisses it when it doesn't apply. Answered
// questions leave the meal entry; unanswered ones stay with the food as visible uncertainty, also once saved.
// Nothing is filled in by guessing: an unanswered question changes no nutrient value.

extension MealEntryWorkflow {
    /// Answers a focused question by adding a documented food (e.g. the cooking oil) in grams or one of its
    /// serving units. The added food is shown in the same meal photos as the food asked about, and counts
    /// toward the nutrition estimate.
    @discardableResult
    public func answerQuestion(
        _ questionID: UncertaintyNote.ID,
        byAdding searchResult: FoodSearchResult,
        quantity: Double,
        unit: PortionUnit
    ) throws -> ReviewedFood.ID {
        let askedAbout = try foodAsked(questionID)
        let portion = try makePortion(quantity: quantity, unit: unit, for: searchResult.food)
        let foodID = try addReviewedFood(searchResult.food, portion: portion, shownIn: askedAbout.photoIDs)
        resolveQuestion(questionID)
        return foodID
    }

    /// Answers a focused question by adding a custom food with nutrition the person provides (e.g. a sauce
    /// with no documented match), shown in the same meal photos as the food asked about.
    @discardableResult
    public func answerQuestion(
        _ questionID: UncertaintyNote.ID,
        byAddingCustomFood customFood: CustomFood,
        grams: Double
    ) throws -> ReviewedFood.ID {
        let askedAbout = try foodAsked(questionID)
        let food = Food(customFood)
        let portion = try makePortion(quantity: grams, unit: .grams, for: food)
        let foodID = try addReviewedFood(food, portion: portion, shownIn: askedAbout.photoIDs)
        resolveQuestion(questionID)
        return foodID
    }

    /// Answers a focused question by correcting the portion of the food asked about, in grams or one of its
    /// serving units.
    public func answerQuestion(
        _ questionID: UncertaintyNote.ID,
        byChangingPortionTo quantity: Double,
        unit: PortionUnit
    ) throws {
        let askedAbout = try foodAsked(questionID)
        try changePortion(of: askedAbout.id, quantity: quantity, unit: unit)
        resolveQuestion(questionID)
    }

    /// Dismisses a focused question the person knows doesn't apply (e.g. no oil was used). Nothing is added
    /// and the nutrition estimate is unchanged; the detail no longer counts as unresolved.
    public func dismissQuestion(_ questionID: UncertaintyNote.ID) throws {
        _ = try foodAsked(questionID)
        resolveQuestion(questionID)
    }

    // MARK: Private

    /// The draft food the open question is about.
    private func foodAsked(_ questionID: UncertaintyNote.ID) throws -> ReviewedFood {
        guard let index = indexOfFoodAsked(questionID) else { throw MealEntryWorkflowError.questionNotFound(questionID) }
        return draft!.reviewedFoods[index]
    }

    private func resolveQuestion(_ questionID: UncertaintyNote.ID) {
        guard let index = indexOfFoodAsked(questionID) else { return }
        draft!.reviewedFoods[index].uncertaintyNotes.removeAll { $0.id == questionID }
    }

    /// Where in the draft the food with this open question is; nil when no food has it.
    private func indexOfFoodAsked(_ questionID: UncertaintyNote.ID) -> Int? {
        draft?.reviewedFoods.firstIndex { $0.uncertaintyNotes.contains { $0.id == questionID } }
    }
}

extension UncertaintyNote {
    /// An unresolved detail from photo analysis, kept with the food it was found for.
    init(_ detail: UnresolvedDetail) {
        self.init(
            detail: detail.detail,
            kind: Kind(rawValue: detail.kind.rawValue),
            question: detail.question,
            searchQuery: detail.searchQuery
        )
    }
}

extension Array where Element == UncertaintyNote {
    /// The notes in order, keeping only the first note for each detail and question.
    func uniquedByContent() -> [UncertaintyNote] {
        var seen = Set<[String]>()
        return filter { seen.insert([$0.detail, $0.question ?? ""]).inserted }
    }
}

// MARK: - Presented to the person

/// One unresolved detail about a reviewed food, asked as a focused question. Answer it with
/// `MealEntryWorkflow.answerQuestion(_:…)` or dismiss it with `dismissQuestion(_:)`; until then it stays with
/// the food as visible uncertainty.
public struct PresentedFocusedQuestion: Hashable, Identifiable, Sendable {
    public var id: UncertaintyNote.ID
    /// The food the question is about.
    public var foodID: ReviewedFood.ID
    public var foodName: String
    /// e.g. "Was it cooked in oil? How much?"
    public var question: String
    /// What the photo couldn't settle, e.g. "Cooking oil not visible".
    public var detail: String
    /// Ingredient and preparation questions are usually answered by adding a food; portion questions by
    /// correcting the portion. Nil when the detail has no kind.
    public var kind: UncertaintyNote.Kind?
    /// A food search to offer when answering by adding a food, e.g. "oil vegetable".
    public var suggestedSearch: String?

    init(_ note: UncertaintyNote, about food: ReviewedFood) {
        id = note.id
        foodID = food.id
        foodName = food.food.name
        question = note.question ?? note.detail
        detail = note.detail
        kind = note.kind
        suggestedSearch = note.searchQuery
    }
}

extension MealEntryPresentation {
    /// Every unresolved detail in the meal entry, asked as a focused question, in food order.
    public var focusedQuestions: [PresentedFocusedQuestion] {
        foods.flatMap(\.focusedQuestions)
    }

    /// Shown with the nutrition estimate while any detail is unresolved; nil when none is.
    public var uncertaintySummary: String? {
        UncertaintyFormat.summary(unresolvedCount: focusedQuestions.count)
    }
}

enum UncertaintyFormat {
    static func summary(unresolvedCount count: Int) -> String? {
        switch count {
        case 0:
            return nil
        case 1:
            return "1 detail is still unresolved, so this estimate may be higher or lower. "
                + "Answer the question to refine it."
        default:
            return "\(count) details are still unresolved, so this estimate may be higher or lower. "
                + "Answer the questions to refine it."
        }
    }
}
