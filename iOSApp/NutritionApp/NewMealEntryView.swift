import NutritionCore
import PhotosUI
import SwiftUI

struct NewMealEntryView: View {
    @Bindable var model: MealEntryModel
    @Binding var isPresented: Bool

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var foodName = ""
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbohydrates: Double?
    @State private var fat: Double?
    @State private var grams: Double?
    @State private var foodPhotoIDs: Set<MealPhoto.ID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let review = model.draftReview { MealPhotosView(photos: review.photos) }
                    PhotosPicker("Add photos", selection: $photoSelection, matching: .images)
                } header: {
                    Text("Meal photos")
                } footer: {
                    Text("Add other angles and every dish in the meal.")
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
                            ReviewedFoodRow(food: food).contextMenu { repeatedViewActions(for: food, in: review) }
                        }
                    } header: {
                        Text("Pictured food")
                    } footer: {
                        Text("Same food in another photo? Long-press it to note the photo or combine repeats.")
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
            .navigationTitle("New meal entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.save()
                        if model.errorMessage == nil { isPresented = false }
                    }
                }
            }
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
