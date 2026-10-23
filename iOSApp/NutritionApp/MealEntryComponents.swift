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
            Text("\(food.portion) · \(food.sourceName)").font(.caption).foregroundStyle(.secondary)
            if let shownIn = food.shownIn {
                Text(shownIn).font(.caption).foregroundStyle(.secondary)
            }
        }
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
