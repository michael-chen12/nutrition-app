import NutritionCore
import SwiftUI
import UIKit

struct MealPhotosView: View {
    let photos: [PresentedMealPhoto]

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(photos) { photo in
                    if let image = UIImage(data: photo.imageData) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .topLeading) {
                                Text(photo.label).font(.caption2).padding(4)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4)).padding(4)
                            }
                    }
                }
            }
        }
    }
}

struct ReviewedFoodRow: View {
    let food: PresentedReviewedFood

    var body: some View {
        VStack(alignment: .leading) {
            Text(food.name)
            Text("\(food.portion) · \(SourceLabel.text(food.sourceName, food.sourceRecordID))")
                .font(.caption).foregroundStyle(.secondary)
            if let shownIn = food.shownIn {
                Text(shownIn).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(food.uncertaintyNotes, id: \.self) { note in
                Label(note, systemImage: "questionmark.circle").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

/// A form section for a custom food: its name, nutrition per 100 g the person provides, and a gram amount.
/// `extra` goes between the fields and the submit button (e.g. which meal photos show the food).
struct CustomFoodSection<Extra: View>: View {
    let title: String
    let submitTitle: String
    let submit: (CustomFood, _ grams: Double) -> Void
    private let suggestedName: String
    private let extra: Extra

    @State private var name = ""
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbohydrates: Double?
    @State private var fat: Double?
    @State private var grams: Double?

    init(
        title: String,
        submitTitle: String,
        suggestedName: String = "",
        submit: @escaping (CustomFood, _ grams: Double) -> Void,
        @ViewBuilder extra: () -> Extra
    ) {
        self.title = title
        self.submitTitle = submitTitle
        self.suggestedName = suggestedName
        self.submit = submit
        self.extra = extra()
    }

    var body: some View {
        Section(title) {
            TextField("Food name", text: $name)
            TextField("Calories (kcal)", value: $calories, format: .number).keyboardType(.decimalPad)
            TextField("Protein (g)", value: $protein, format: .number).keyboardType(.decimalPad)
            TextField("Carbohydrates (g)", value: $carbohydrates, format: .number).keyboardType(.decimalPad)
            TextField("Fat (g)", value: $fat, format: .number).keyboardType(.decimalPad)
            TextField("Amount (g)", value: $grams, format: .number).keyboardType(.decimalPad)
            extra
            Button(submitTitle) {
                guard let grams else { return }
                let nutrients = NutrientsPer100g(
                    calories: calories ?? 0, protein: protein ?? 0, carbohydrates: carbohydrates ?? 0, fat: fat ?? 0
                )
                submit(CustomFood(name: name, nutrientsPer100g: nutrients), grams)
            }
            .disabled(name.isEmpty || grams == nil)
        }
        .onAppear { if name.isEmpty { name = suggestedName } }
    }
}

extension CustomFoodSection where Extra == EmptyView {
    init(
        title: String,
        submitTitle: String,
        suggestedName: String = "",
        submit: @escaping (CustomFood, _ grams: Double) -> Void
    ) {
        self.init(title: title, submitTitle: submitTitle, suggestedName: suggestedName, submit: submit) { EmptyView() }
    }
}

struct FoodSearchResultRow: View {
    let result: FoodSearchResult

    var body: some View {
        VStack(alignment: .leading) {
            Text(result.name)
            Text(SourceLabel.text(result.sourceName, result.sourceRecordID))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// "USDA FoodData Central · record 168878", or just "Custom food".
enum SourceLabel {
    static func text(_ sourceName: String, _ recordID: String?) -> String {
        recordID.map { "\(sourceName) · record \($0)" } ?? sourceName
    }
}

/// States that the estimate covers all pictured food, shared food and leftovers included.
struct PicturedFoodNoteView: View {
    let note: String

    var body: some View {
        Label(note, systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
    }
}

struct NutritionEstimateView: View {
    let estimate: PresentedNutritionEstimate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(estimate.label).font(.headline)
            LabeledContent("Calories", value: estimate.calories)
            LabeledContent("Protein", value: estimate.protein)
            LabeledContent("Carbohydrates", value: estimate.carbohydrates)
            LabeledContent("Fat", value: estimate.fat)
        }
    }
}
