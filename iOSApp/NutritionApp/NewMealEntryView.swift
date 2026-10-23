import NutritionCore
import PhotosUI
import SwiftUI

struct NewMealEntryView: View {
    @Bindable var model: MealEntryModel
    @Binding var isPresented: Bool

    @State private var photoSelection: PhotosPickerItem?
    @State private var foodName = ""
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbohydrates: Double?
    @State private var fat: Double?
    @State private var grams: Double?

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal photo") {
                    if let review = model.draftReview { MealPhotosView(photos: review.photos) }
                    PhotosPicker("Import photo", selection: $photoSelection, matching: .images)
                }
                Section("Custom food (per 100 g)") {
                    TextField("Food name", text: $foodName)
                    TextField("Calories (kcal)", value: $calories, format: .number).keyboardType(.decimalPad)
                    TextField("Protein (g)", value: $protein, format: .number).keyboardType(.decimalPad)
                    TextField("Carbohydrates (g)", value: $carbohydrates, format: .number).keyboardType(.decimalPad)
                    TextField("Fat (g)", value: $fat, format: .number).keyboardType(.decimalPad)
                    TextField("Amount (g)", value: $grams, format: .number).keyboardType(.decimalPad)
                    Button("Add food", action: addFood).disabled(foodName.isEmpty || grams == nil)
                }
                if let review = model.draftReview, !review.foods.isEmpty {
                    Section("Foods") { ForEach(review.foods) { ReviewedFoodRow(food: $0) } }
                    Section { NutritionEstimateView(estimate: review.nutritionEstimate) }
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
            .task(id: photoSelection) {
                guard let item = photoSelection,
                      let data = try? await item.loadTransferable(type: Data.self) else { return }
                let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                model.importPhoto(data, fileExtension: fileExtension)
            }
        }
    }

    private func addFood() {
        guard let grams else { return }
        model.addCustomFood(
            CustomFood(
                name: foodName,
                nutrientsPer100g: NutrientsPer100g(
                    calories: calories ?? 0, protein: protein ?? 0, carbohydrates: carbohydrates ?? 0, fat: fat ?? 0
                )
            ),
            grams: grams
        )
    }
}
