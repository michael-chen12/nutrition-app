import NutritionCore
import SwiftUI

struct MealHistoryView: View {
    @Bindable var model: MealEntryModel
    @State private var isAddingMealEntry = false

    var body: some View {
        NavigationStack {
            List(model.history) { row in
                NavigationLink(value: row.id) {
                    VStack(alignment: .leading) {
                        Text(row.date, format: .dateTime.day().month().hour().minute())
                        Text(row.foodNames.joined(separator: ", ")).font(.subheadline)
                        Text("≈ \(row.nutritionEstimate.calories)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Meal history")
            .navigationDestination(for: MealEntry.ID.self) { id in
                if let entry = model.open(id) {
                    MealEntryDetailView(entry: entry)
                }
            }
            .toolbar {
                Button("New meal entry", systemImage: "plus") {
                    model.startNewMealEntry()
                    isAddingMealEntry = true
                }
            }
            .sheet(isPresented: $isAddingMealEntry) {
                NewMealEntryView(model: model, isPresented: $isAddingMealEntry)
            }
        }
    }
}

struct MealEntryDetailView: View {
    let entry: MealEntryPresentation

    var body: some View {
        List {
            Section { MealPhotosView(photos: entry.photos) }
            Section("Pictured food") {
                ForEach(entry.foods) { ReviewedFoodRow(food: $0) }
            }
            Section {
                NutritionEstimateView(estimate: entry.nutritionEstimate)
                PicturedFoodNoteView(note: entry.picturedFoodNote)
            }
        }
        .navigationTitle(Text(entry.date, format: .dateTime.day().month().hour().minute()))
    }
}
