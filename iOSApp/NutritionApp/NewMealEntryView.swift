import NutritionCore
import PhotosUI
import SwiftUI

struct NewMealEntryView: View {
    @Bindable var model: MealEntryModel
    @Binding var isPresented: Bool
    /// "New meal entry", or "Edit meal entry" when a saved meal entry was reopened for review.
    var title = "New meal entry"

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var foodName = ""
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbohydrates: Double?
    @State private var fat: Double?
    @State private var grams: Double?
    @State private var searchQuery = ""
    @State private var chosenResult: FoodSearchResult?
    @State private var chosenGrams: Double?
    @State private var chosenUnit: PortionUnit = .grams
    @State private var portionEditorFood: PresentedReviewedFood?
    @State private var foodPhotoIDs: Set<MealPhoto.ID> = []
    @State private var photoCapture: MealPhotoCaptureModel?
    @State private var isPickingFromLibrary = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let review = model.draftReview { MealPhotosView(photos: review.photos) }
                    PhotosPicker("Add photos", selection: $photoSelection, matching: .images)
                    Button("Take photo") { photoCapture = model.makePhotoCapture() }
                } header: {
                    Text("Meal photos")
                } footer: {
                    Text("Add other angles and every dish in the meal.")
                }
                if let photos = model.draftReview?.photos, !photos.isEmpty {
                    PhotoSuggestionsSection(model: model, photos: photos)
                }
                Section("Find a documented food") {
                    TextField("Search foods", text: $searchQuery)
                        .submitLabel(.search)
                        .onSubmit { Task { await model.searchFoods(matching: searchQuery) } }
                    if let search = model.foodSearch {
                        if let message = search.noMatchMessage {
                            Text(message).foregroundStyle(.secondary)
                        }
                        ForEach(search.results) { result in
                            Button {
                                chosenResult = result
                                chosenUnit = .grams
                            } label: {
                                HStack {
                                    FoodSearchResultRow(result: result)
                                    if result.id == chosenResult?.id {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let chosenResult {
                        let portion = PortionFields(
                            units: chosenResult.portionUnits, unit: $chosenUnit, quantity: $chosenGrams
                        )
                        portion
                        Button("Add \(chosenResult.name)", action: addChosenFood).disabled(!portion.canSubmit)
                    }
                }
                Section("Custom food (per 100 g)") {
                    TextField("Food name", text: $foodName)
                    TextField("Calories (kcal)", value: $calories, format: .number).keyboardType(.decimalPad)
                    TextField("Protein (g)", value: $protein, format: .number).keyboardType(.decimalPad)
                    TextField("Carbohydrates (g)", value: $carbohydrates, format: .number).keyboardType(.decimalPad)
                    TextField("Fat (g)", value: $fat, format: .number).keyboardType(.decimalPad)
                    TextField("Amount (g)", value: $grams, format: .number).keyboardType(.decimalPad)
                    ForEach(model.draftReview?.photos ?? []) { photo in
                        Toggle("Shown in \(photo.label)", isOn: Binding(
                            get: { foodPhotoIDs.contains(photo.id) },
                            set: { isOn in
                                if isOn { foodPhotoIDs.insert(photo.id) } else { foodPhotoIDs.remove(photo.id) }
                            }
                        ))
                    }
                    Button("Add food", action: addFood).disabled(foodName.isEmpty || grams == nil)
                }
                if let review = model.draftReview, !review.foods.isEmpty {
                    Section {
                        ForEach(review.foods) { food in
                            Button { portionEditorFood = food } label: { ReviewedFoodRow(food: food) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Change portion") { portionEditorFood = food }
                                    repeatedViewActions(for: food, in: review)
                                }
                                .swipeActions {
                                    Button("Remove", role: .destructive) { model.removeFood(food.id) }
                                }
                        }
                    } header: {
                        Text("Pictured food")
                    } footer: {
                        Text("Tap a food to correct its portion in grams or a serving unit. Long-press it to note it "
                            + "in another photo. Swipe to remove it.")
                    }
                    Section {
                        NutritionEstimateView(estimate: review.nutritionEstimate)
                        PicturedFoodNoteView(note: review.picturedFoodNote)
                    }
                }
                if let message = model.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.save()
                        if model.errorMessage == nil { isPresented = false }
                    }
                }
            }
            .fullScreenCover(item: $photoCapture) { capture in
                MealPhotoCaptureView(model: capture) { choosePhotoLibrary in
                    photoCapture = nil
                    model.refreshDraftReview()
                    isPickingFromLibrary = choosePhotoLibrary
                }
            }
            .sheet(item: $portionEditorFood) { food in
                PortionEditorView(model: model, food: food)
            }
            .photosPicker(isPresented: $isPickingFromLibrary, selection: $photoSelection, matching: .images)
            .onChange(of: photoSelection) { _, items in
                guard !items.isEmpty else { return }
                photoSelection = []
                Task {
                    // Imported in picker order so photo numbers follow the person's selection.
                    for item in items {
                        guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                        let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                        model.importPhoto(data, fileExtension: fileExtension)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func repeatedViewActions(for food: PresentedReviewedFood, in review: MealEntryPresentation) -> some View {
        Menu("Also shown in…") {
            ForEach(review.photos) { photo in
                Button(photo.label) { model.markFood(food.id, asAlsoShownIn: photo.id) }
            }
        }
        Menu("Same food as…") {
            ForEach(review.foods.filter { $0.id != food.id }) { other in
                Button(other.name) { model.combineFood(food.id, into: other.id) }
            }
        }
    }

    private func addChosenFood() {
        guard let chosenResult, let chosenGrams else { return }
        model.addFood(chosenResult, quantity: chosenGrams, unit: chosenUnit)
        if model.errorMessage == nil {
            self.chosenResult = nil
            self.chosenGrams = nil
            chosenUnit = .grams
        }
    }

    private func addFood() {
        guard let grams else { return }
        let photoOrder = model.draftReview?.photos.map(\.id) ?? []
        model.addCustomFood(
            CustomFood(
                name: foodName,
                nutrientsPer100g: NutrientsPer100g(
                    calories: calories ?? 0, protein: protein ?? 0, carbohydrates: carbohydrates ?? 0, fat: fat ?? 0
                )
            ),
            grams: grams,
            shownIn: photoOrder.filter(foodPhotoIDs.contains)
        )
        if model.errorMessage == nil { foodPhotoIDs = [] }
    }
}
