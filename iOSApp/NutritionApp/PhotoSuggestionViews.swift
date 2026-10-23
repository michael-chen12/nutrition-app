import NutritionCore
import SwiftUI

/// Shown before a meal photo is uploaded for analysis: where it goes and how the provider may use it.
struct PhotoAnalysisDisclosureView: View {
    let disclosure: PhotoAnalysisDisclosure
    let upload: () -> Void
    let enterManually: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(disclosure.paragraphs, id: \.self) { Text($0) }
                }
                .padding()
            }
            .navigationTitle(disclosure.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button(disclosure.uploadButtonTitle, action: upload).buttonStyle(.borderedProminent)
                    Button(disclosure.manualEntryButtonTitle, action: enterManually)
                }
                .padding()
            }
        }
    }
}

/// Meal photos that can be analyzed, and the suggestions awaiting review.
struct PhotoSuggestionsSection: View {
    @Bindable var model: MealEntryModel
    let photos: [PresentedMealPhoto]

    @State private var photosToAnalyze: PhotosToAnalyze?
    @State private var suggestionToReview: PresentedFoodSuggestion?

    /// The meal photos the person chose to upload together for one analysis.
    private struct PhotosToAnalyze: Identifiable {
        var id: [MealPhoto.ID]
    }

    var body: some View {
        Section {
            if photos.count > 1 {
                Button("Suggest foods from all \(photos.count) photos") {
                    photosToAnalyze = PhotosToAnalyze(id: photos.map(\.id))
                }
                .disabled(model.isAnalyzingPhoto)
            }
            ForEach(photos) { photo in
                Button("Suggest foods from \(photo.label)") { photosToAnalyze = PhotosToAnalyze(id: [photo.id]) }
                    .disabled(model.isAnalyzingPhoto)
            }
            if model.isAnalyzingPhoto { ProgressView("Analyzing photos…") }
            if let analysis = model.photoAnalysis {
                if let message = analysis.message {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
                ForEach(analysis.suggestions) { suggestion in
                    Button { suggestionToReview = suggestion } label: { SuggestionRow(suggestion: suggestion) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Reject", role: .destructive) { model.rejectSuggestion(suggestion.id) }
                            if suggestion.likelyDuplicateNote != nil {
                                Button("Separate") { model.separateSuggestion(suggestion.id) }
                            }
                        }
                }
                if !analysis.suggestions.isEmpty {
                    Text(analysis.reviewNote).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Photo suggestions")
        } footer: {
            Text("Optional. You can always add foods yourself below.")
        }
        .sheet(item: $photosToAnalyze) { chosen in
            PhotoAnalysisDisclosureView(
                disclosure: model.photoAnalysisDisclosure,
                upload: {
                    photosToAnalyze = nil
                    Task { await model.uploadForAnalysis(chosen.id) }
                },
                enterManually: { photosToAnalyze = nil }
            )
        }
        .sheet(item: $suggestionToReview) { suggestion in
            SuggestionReviewView(model: model, suggestion: suggestion)
        }
    }
}

struct SuggestionRow: View {
    let suggestion: PresentedFoodSuggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(suggestion.name)
            Text([suggestion.suggestedPortion, suggestion.shownIn].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if let note = suggestion.likelyDuplicateNote {
                Label(note, systemImage: "square.on.square").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(suggestion.uncertaintyNotes, id: \.self) { note in
                Label(note, systemImage: "questionmark.circle").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

/// Accept a suggestion as a documented food (a match, or any food the person searches for) or a custom food,
/// with a portion they confirm; or reject it.
struct SuggestionReviewView: View {
    @Bindable var model: MealEntryModel
    let suggestion: PresentedFoodSuggestion
    @Environment(\.dismiss) private var dismiss

    @State private var chosen: FoodSearchResult?
    @State private var unit: PortionUnit = .grams
    @State private var quantity: Double?
    @State private var searchQuery = ""
    @State private var customName = ""
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbohydrates: Double?
    @State private var fat: Double?
    @State private var customGrams: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SuggestionRow(suggestion: suggestion)
                } footer: {
                    Text("Nutrition comes only from the documented food or custom food you choose.")
                }
                Section("Documented matches") {
                    if let message = suggestion.noMatchMessage { Text(message).foregroundStyle(.secondary) }
                    ForEach(suggestion.matches) { match in
                        Button { choose(match.result, unit: match.suggestedUnit, quantity: match.suggestedQuantity) }
                            label: {
                                VStack(alignment: .leading) {
                                    FoodSearchResultRow(result: match.result)
                                    Text(match.suggestedPortion ?? "Enter a portion for this food")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                    }
                }
                Section("Search another food") {
                    TextField("Search foods", text: $searchQuery)
                        .submitLabel(.search)
                        .onSubmit { Task { await model.searchFoods(matching: searchQuery) } }
                    if let search = model.foodSearch {
                        if let message = search.noMatchMessage { Text(message).foregroundStyle(.secondary) }
                        ForEach(search.results) { result in
                            Button { choose(result, unit: nil, quantity: nil) } label: {
                                FoodSearchResultRow(result: result)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let chosen {
                    let fields = PortionFields(units: chosen.portionUnits, unit: $unit, quantity: $quantity)
                    Section("Accept as \(chosen.name)") {
                        fields
                        Button("Accept") {
                            guard let quantity else { return }
                            model.acceptSuggestion(suggestion.id, as: chosen, quantity: quantity, unit: unit)
                            if model.errorMessage == nil { dismiss() }
                        }
                        .disabled(!fields.canSubmit)
                    }
                }
                Section("Or accept as a custom food (per 100 g)") {
                    TextField("Food name", text: $customName)
                    TextField("Calories (kcal)", value: $calories, format: .number).keyboardType(.decimalPad)
                    TextField("Protein (g)", value: $protein, format: .number).keyboardType(.decimalPad)
                    TextField("Carbohydrates (g)", value: $carbohydrates, format: .number).keyboardType(.decimalPad)
                    TextField("Fat (g)", value: $fat, format: .number).keyboardType(.decimalPad)
                    TextField("Amount (g)", value: $customGrams, format: .number).keyboardType(.decimalPad)
                    Button("Accept as custom food", action: acceptCustomFood)
                        .disabled(customName.isEmpty || customGrams == nil)
                }
                if suggestion.likelyDuplicateNote != nil {
                    Section {
                        Button("Separate into one food per photo") {
                            model.separateSuggestion(suggestion.id)
                            dismiss()
                        }
                    } footer: {
                        Text("Use this when the photos show different servings, such as two plates of the same dish.")
                    }
                }
                Section {
                    Button("Reject suggestion", role: .destructive) {
                        model.rejectSuggestion(suggestion.id)
                        dismiss()
                    }
                }
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
            .navigationTitle("Review suggestion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { customName = suggestion.name }
        }
    }

    private func choose(_ result: FoodSearchResult, unit: PortionUnit?, quantity: Double?) {
        chosen = result
        self.unit = unit ?? .grams
        self.quantity = quantity
    }

    private func acceptCustomFood() {
        guard let customGrams else { return }
        model.acceptSuggestion(
            suggestion.id,
            asCustomFood: CustomFood(
                name: customName,
                nutrientsPer100g: NutrientsPer100g(
                    calories: calories ?? 0, protein: protein ?? 0, carbohydrates: carbohydrates ?? 0, fat: fat ?? 0
                )
            ),
            grams: customGrams
        )
        if model.errorMessage == nil { dismiss() }
    }
}
