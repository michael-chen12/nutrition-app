import Foundation

/// An editable, saved record of one photographed meal: its meal photos, reviewed foods and portions.
/// Its nutrition estimate is always calculated from the reviewed foods, never stored separately.
public struct MealEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// When the meal was recorded; the meal entry is assigned to this date's day.
    public var date: Date
    public var photos: [MealPhoto]
    /// The pictured food after review. Each food counts once regardless of how many photos show it.
    public var reviewedFoods: [ReviewedFood]

    public init(id: UUID = UUID(), date: Date, photos: [MealPhoto] = [], reviewedFoods: [ReviewedFood] = []) {
        self.id = id
        self.date = date
        self.photos = photos
        self.reviewedFoods = reviewedFoods
    }

    public var nutritionEstimate: NutritionEstimate {
        reviewedFoods.map(\.nutritionEstimate).total()
    }
}

/// A photo of food retained with a meal entry. The image bytes live in the meal history store,
/// keyed by this photo's identity.
public struct MealPhoto: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// File extension of the stored image, e.g. "jpg" or "heic".
    public var fileExtension: String

    public init(id: UUID = UUID(), fileExtension: String) {
        self.id = id
        self.fileExtension = fileExtension
    }

    public var fileName: String {
        "\(id.uuidString).\(fileExtension)"
    }
}

/// One pictured food after the person reviewed it: the food, its portion, and any unresolved uncertainty.
public struct ReviewedFood: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var food: Food
    public var portion: Portion
    /// Unresolved details retained with the result so a precise-looking number does not hide weak evidence.
    public var uncertaintyNotes: [UncertaintyNote]
    /// The meal photos this food is visible in. Repeated views of the same food (other angles) are recorded
    /// here rather than as another reviewed food, so the food counts once in the nutrition estimate.
    public var photoIDs: [MealPhoto.ID]

    public init(
        id: UUID = UUID(),
        food: Food,
        portion: Portion,
        uncertaintyNotes: [UncertaintyNote] = [],
        photoIDs: [MealPhoto.ID] = []
    ) {
        self.id = id
        self.food = food
        self.portion = portion
        self.uncertaintyNotes = uncertaintyNotes
        self.photoIDs = photoIDs
    }

    public var nutritionEstimate: NutritionEstimate {
        NutritionEstimate(food.nutrientsPer100g, grams: portion.grams)
    }
}

/// The reviewed quantity of a food. Grams are the calculation basis for every portion.
public struct Portion: Codable, Hashable, Sendable {
    public var grams: Double

    public init(grams: Double) {
        self.grams = grams
    }
}

/// A specific unresolved detail about a reviewed food (ingredient, preparation or portion).
public struct UncertaintyNote: Codable, Hashable, Sendable {
    public var detail: String

    public init(detail: String) {
        self.detail = detail
    }
}
