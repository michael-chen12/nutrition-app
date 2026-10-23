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
        }
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
