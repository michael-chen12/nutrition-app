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

/// The reviewed quantity of a food. Grams are the calculation basis for every portion; a portion the person
/// entered in a serving unit also keeps that unit and quantity, with `grams` as its effective gram amount.
public struct Portion: Codable, Hashable, Sendable {
    /// Effective grams: what the nutrition estimate is calculated from.
    public var grams: Double
    /// The serving unit and quantity the person chose; nil when they entered grams directly.
    public var serving: ServingPortion?

    public init(grams: Double) {
        self.grams = grams
        serving = nil
    }

    /// A portion of `quantity` servings of `unit`, converted through the unit's documented gram weight.
    /// Returns nil when the unit has no known gram weight, since the conversion would be a guess.
    public init?(quantity: Double, of unit: ServingUnit) {
        guard let gramsPerUnit = unit.gramsPerUnit else { return nil }
        grams = quantity * gramsPerUnit
        serving = ServingPortion(unit: unit, quantity: quantity)
    }

    /// The unit the person chose for this portion.
    public var unit: PortionUnit {
        serving.map { .serving($0.unit) } ?? .grams
    }

    /// The amount in `unit`: servings, or grams.
    public var quantity: Double {
        serving?.quantity ?? grams
    }
}

/// A quantity of a serving unit, e.g. 1.5 cups.
public struct ServingPortion: Codable, Hashable, Sendable {
    public var unit: ServingUnit
    public var quantity: Double

    public init(unit: ServingUnit, quantity: Double) {
        self.unit = unit
        self.quantity = quantity
    }
}

/// The unit a portion is entered in: grams, or one of the food's serving units.
public enum PortionUnit: Hashable, Sendable {
    case grams
    case serving(ServingUnit)
}

/// A specific unresolved detail about a reviewed food (ingredient, preparation or portion).
public struct UncertaintyNote: Codable, Hashable, Sendable {
    public var detail: String

    public init(detail: String) {
        self.detail = detail
    }
}
