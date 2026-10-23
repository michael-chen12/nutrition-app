import Foundation
import NutritionCore

/// A consented meal with known nutrition, used to measure nutrition estimate accuracy (ADR 0002): its foods were
/// weighed, or it was made from a known recipe, so its reference nutrition is worked out independently of the app.
public struct ReferenceMeal: Codable, Hashable, Identifiable, Sendable {
    /// Which part of the study a reference meal belongs to. Pass criteria are set from calibration meals only,
    /// then applied to validation meals, which are kept out of calibration.
    public enum Split: String, Codable, Hashable, Sendable {
        case calibration
        case validation
    }

    /// How the reference nutrition was established.
    public enum ReferenceMethod: String, Codable, Hashable, Sendable {
        /// Each food was weighed before the meal photos were taken.
        case weighedPortions
        /// Made from a recipe with weighed ingredients; reference foods are the recipe's share in the pictured food.
        case knownRecipe
    }

    /// Stable identifier, e.g. "pilot-001".
    public var id: String
    public var split: Split
    /// e.g. "South Asian". Errors are reported by cuisine.
    public var cuisine: String
    /// e.g. "Rice plate", "Soup", "Sandwich". Errors are reported by dish type.
    public var dishType: String
    public var referenceMethod: ReferenceMethod
    public var consent: ParticipantConsent
    /// The meal photos, in the pilot's photos folder.
    public var photoFileNames: [String]
    /// All pictured food, each with its weighed or recipe grams and nutrition.
    public var referenceFoods: [ReferenceFood]

    public init(
        id: String,
        split: Split,
        cuisine: String,
        dishType: String,
        referenceMethod: ReferenceMethod,
        consent: ParticipantConsent,
        photoFileNames: [String],
        referenceFoods: [ReferenceFood]
    ) {
        self.id = id
        self.split = split
        self.cuisine = cuisine
        self.dishType = dishType
        self.referenceMethod = referenceMethod
        self.consent = consent
        self.photoFileNames = photoFileNames
        self.referenceFoods = referenceFoods
    }

    /// What the pictured food actually contained: the measure estimates are compared with.
    public var referenceNutrition: NutritionEstimate {
        referenceFoods.map(\.nutrition).total()
    }
}

/// The participant's consent to use their meal in the study. Participants are identified only by a code.
public struct ParticipantConsent: Codable, Hashable, Sendable {
    /// A pseudonymous code such as "P01"; never a name or contact detail.
    public var participantCode: String
    public var consentedOn: Date
    /// The participant agreed that the meal photos may be uploaded for photo analysis, with the provider's
    /// retention terms explained (`PhotoAnalysisDisclosure`). A trial does not upload without it.
    public var coversPhotoAnalysisUpload: Bool

    public init(participantCode: String, consentedOn: Date, coversPhotoAnalysisUpload: Bool) {
        self.participantCode = participantCode
        self.consentedOn = consentedOn
        self.coversPhotoAnalysisUpload = coversPhotoAnalysisUpload
    }
}

/// One pictured food of a reference meal with its known amount and nutrition.
public struct ReferenceFood: Codable, Hashable, Identifiable, Sendable {
    /// Unique within the meal, e.g. "rice".
    public var id: String
    public var name: String
    /// Weighed grams, or the recipe's grams for the pictured share.
    public var grams: Double
    public var nutrientsPer100g: NutrientsPer100g
    /// Where the per-100 g values come from, e.g. "USDA FoodData Central 168878" or "Recipe, per 100 g cooked".
    public var nutritionSource: String

    public init(id: String, name: String, grams: Double, nutrientsPer100g: NutrientsPer100g, nutritionSource: String) {
        self.id = id
        self.name = name
        self.grams = grams
        self.nutrientsPer100g = nutrientsPer100g
        self.nutritionSource = nutritionSource
    }

    public var nutrition: NutritionEstimate {
        NutritionEstimate(nutrientsPer100g, grams: grams)
    }
}
