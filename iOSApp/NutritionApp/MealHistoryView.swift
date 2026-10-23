import NutritionCore
import SwiftUI

struct MealHistoryView: View {
    @Bindable var model: MealEntryModel
    @State private var isAddingMealEntry = false

    var body: some View {
        NavigationStack {
            List(model.historyDays) { day in
                Section {
                    DailyPicturedFoodTotalView(total: day.picturedFoodTotal)
                    ForEach(day.mealEntries) { row in
                        NavigationLink(value: row.id) {
                            VStack(alignment: .leading) {
                                Text(row.date, format: .dateTime.hour().minute())
                                Text(row.foodNames.joined(separator: ", ")).font(.subheadline)
                                Text("≈ \(row.nutritionEstimate.calories)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                }
            }
            .navigationTitle("Meal history")
            .navigationDestination(for: MealEntry.ID.self) { id in
                MealEntryDetailView(model: model, id: id)
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

/// The four-value daily pictured-food total with its label and note, rendered as the core presents them.
struct DailyPicturedFoodTotalView: View {
    let total: PresentedDailyPicturedFoodTotal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(total.label).font(.headline)
            Text("≈ \(total.calories) · protein \(total.protein) · carbohydrates \(total.carbohydrates) · fat \(total.fat)")
                .font(.subheadline)
            Text(total.note).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct MealEntryDetailView: View {
    @Bindable var model: MealEntryModel
    let id: MealEntry.ID
    @State private var entry: MealEntryPresentation?
    @State private var isEditing = false

    var body: some View {
        Group {
            if let entry {
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
        .toolbar {
            Button("Edit") {
                model.editMealEntry(id)
                isEditing = model.draftReview != nil
            }
        }
        .sheet(isPresented: $isEditing, onDismiss: reload) {
            NewMealEntryView(model: model, isPresented: $isEditing, title: "Edit meal entry")
        }
        .onAppear(perform: reload)
    }

    /// Shows the saved meal entry as it now is, including any edits just saved.
    private func reload() {
        entry = model.open(id)
    }
}
