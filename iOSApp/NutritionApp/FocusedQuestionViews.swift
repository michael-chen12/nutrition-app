import NutritionCore
import SwiftUI

/// Focused questions about details the photos can't settle (hidden oil, sauces, preparation, amounts).
/// Each opens `FocusedQuestionAnswerView`; questions left open stay with the meal entry as uncertainty.
struct FocusedQuestionsSection: View {
    @Bindable var model: MealEntryModel
    let review: MealEntryPresentation
    @State private var answering: PresentedFocusedQuestion?

    var body: some View {
        Section {
            ForEach(review.focusedQuestions) { question in
                Button { answering = question } label: {
                    VStack(alignment: .leading) {
                        Text(question.question)
                        Text("\(question.foodName) · \(question.detail)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Doesn't apply") { model.dismissQuestion(question.id) }
                }
            }
        } header: {
            Text("Questions about this meal")
        } footer: {
            Text("Answer by adding what the photos don't show, such as oil, sauce or a drink, or by correcting a "
                + "portion. Questions you leave open stay with the meal entry as uncertainty.")
        }
        .sheet(item: $answering) { question in
            FocusedQuestionAnswerView(
                model: model, question: question, food: review.foods.first { $0.id == question.foodID }
            )
        }
    }
}

/// Answers one focused question: add a documented or custom food, correct the portion, or dismiss it.
struct FocusedQuestionAnswerView: View {
    @Bindable var model: MealEntryModel
    let question: PresentedFocusedQuestion
    /// The food the question is about, for correcting its portion.
    let food: PresentedReviewedFood?
    @Environment(\.dismiss) private var dismiss

    @State private var searchQuery = ""
    @State private var chosen: FoodSearchResult?
    @State private var unit: PortionUnit = .grams
    @State private var quantity: Double?
    @State private var portionUnit: PortionUnit = .grams
    @State private var portionQuantity: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(question.question).font(.headline)
                } footer: {
                    Text("\(question.foodName) · \(question.detail)")
                }
                if question.kind == .portion, let food {
                    let fields = PortionFields(units: food.portionUnits, unit: $portionUnit, quantity: $portionQuantity)
                    Section("Correct the portion of \(food.name)") {
                        fields
                        Button("Use this portion") {
                            guard let portionQuantity else { return }
                            model.answerQuestion(question.id, byChangingPortionTo: portionQuantity, unit: portionUnit)
                            if model.errorMessage == nil { dismiss() }
                        }
                        .disabled(!fields.canSubmit)
                    }
                }
                Section("Add a documented food") {
                    TextField("Search foods", text: $searchQuery)
                        .submitLabel(.search)
                        .onSubmit { Task { await model.searchFoods(matching: searchQuery) } }
                    if let search = model.foodSearch {
                        if let message = search.noMatchMessage { Text(message).foregroundStyle(.secondary) }
                        ForEach(search.results) { result in
                            Button { chosen = result; unit = .grams; quantity = nil } label: {
                                FoodSearchResultRow(result: result)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let chosen {
                        let fields = PortionFields(units: chosen.portionUnits, unit: $unit, quantity: $quantity)
                        fields
                        Button("Add \(chosen.name)") {
                            guard let quantity else { return }
                            model.answerQuestion(question.id, byAdding: chosen, quantity: quantity, unit: unit)
                            if model.errorMessage == nil { dismiss() }
                        }
                        .disabled(!fields.canSubmit)
                    }
                }
                CustomFoodSection(
                    title: "Or add a custom food (per 100 g)", submitTitle: "Add custom food", submit: addCustomFood
                )
                Section {
                    Button("Doesn't apply") {
                        model.dismissQuestion(question.id)
                        if model.errorMessage == nil { dismiss() }
                    }
                } footer: {
                    Text("Not sure? Leave it open: it stays with the meal entry as uncertainty.")
                }
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
            .navigationTitle("Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Leave open") { dismiss() } }
            }
            .task {
                if let food {
                    portionUnit = food.selectedPortionUnit
                    portionQuantity = food.portionQuantity
                }
                if let suggestedSearch = question.suggestedSearch {
                    searchQuery = suggestedSearch
                    await model.searchFoods(matching: suggestedSearch)
                }
            }
        }
    }

    private func addCustomFood(_ customFood: CustomFood, grams: Double) {
        model.answerQuestion(question.id, byAddingCustomFood: customFood, grams: grams)
        if model.errorMessage == nil { dismiss() }
    }
}

/// Shown with the nutrition estimate while any detail is unresolved.
struct UncertaintySummaryView: View {
    let summary: String

    var body: some View {
        Label(summary, systemImage: "questionmark.circle").font(.footnote).foregroundStyle(.orange)
    }
}
