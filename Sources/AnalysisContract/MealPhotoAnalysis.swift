import Foundation

// The wire contract between the iPhone app and the meal photo analysis backend (Backend/).
// Codable values only, encoded as JSON. Both sides compile against these types.
//
// The contract carries suggestions to review, never nutrition facts: it has no nutrient values. Nutrients come
// only from documented nutrition sources or custom foods once the person has reviewed a suggestion.
//
// Extending it: new fields must be optional (or decode with a default) so an older app or backend still
// decodes newer messages. Multi-photo reconciliation reads `duplicateGroups`; focused questions about mixed
// dishes read `UnresolvedDetail`.

/// Where the backend serves meal photo analysis: `POST` a `MealPhotoAnalysisRequest` as JSON; the reply is a
/// `MealPhotoAnalysisResponse` (HTTP 200) or an `AnalysisErrorResponse` (any other status).
public enum MealPhotoAnalysisEndpoint {
    public static let path = "/v1/meal-photo-analyses"
    public static let method = "POST"
}

/// Meal photos sent for one analysis. Every photo is uploaded to the hosted analysis provider.
public struct MealPhotoAnalysisRequest: Codable, Hashable, Sendable {
    public var photos: [PhotoUpload]

    public init(photos: [PhotoUpload]) {
        self.photos = photos
    }
}

/// One meal photo in an analysis request. `photoID` is the app's identity for the meal photo; suggestions
/// refer back to it.
public struct PhotoUpload: Codable, Hashable, Sendable {
    public var photoID: String
    /// e.g. "image/jpeg" or "image/heic".
    public var mediaType: String
    /// The image bytes (base64 in JSON).
    public var imageData: Data

    public init(photoID: String, mediaType: String, imageData: Data) {
        self.photoID = photoID
        self.mediaType = mediaType
        self.imageData = imageData
    }
}

/// What the analysis suggests about the pictured food: candidates to review, not nutrition facts.
public struct MealPhotoAnalysisResponse: Codable, Hashable, Sendable {
    /// Each distinct pictured food the analysis found, including shared food and leftovers.
    public var suggestions: [FoodSuggestion]
    /// Suggestions that likely show the same food from different photos (cross-photo duplicates).
    public var duplicateGroups: [DuplicateGroupHint]

    public init(suggestions: [FoodSuggestion], duplicateGroups: [DuplicateGroupHint] = []) {
        self.suggestions = suggestions
        self.duplicateGroups = duplicateGroups
    }

    private enum CodingKeys: String, CodingKey {
        case suggestions, duplicateGroups
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        suggestions = try container.decode([FoodSuggestion].self, forKey: .suggestions)
        duplicateGroups = try container.decodeIfPresent([DuplicateGroupHint].self, forKey: .duplicateGroups) ?? []
    }
}

/// One candidate food seen in the meal photos.
public struct FoodSuggestion: Codable, Hashable, Sendable {
    /// Identifies the suggestion within one response (duplicate groups refer to it).
    public var id: String
    /// The food as the analysis names it, e.g. "Steamed white rice".
    public var name: String
    /// A short query for looking the food up in documented nutrition sources, e.g. "rice white cooked".
    public var searchQuery: String
    /// The `PhotoUpload.photoID`s of the photos that show this food.
    public var photoIDs: [String]
    /// The analysis's portion suggestion, if it made one.
    public var portion: PortionSuggestion?
    /// Specific details the photo cannot settle; never filled in by guessing.
    public var unresolvedDetails: [UnresolvedDetail]

    public init(
        id: String,
        name: String,
        searchQuery: String,
        photoIDs: [String],
        portion: PortionSuggestion? = nil,
        unresolvedDetails: [UnresolvedDetail] = []
    ) {
        self.id = id
        self.name = name
        self.searchQuery = searchQuery
        self.photoIDs = photoIDs
        self.portion = portion
        self.unresolvedDetails = unresolvedDetails
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, searchQuery, photoIDs, portion, unresolvedDetails
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        searchQuery = try container.decode(String.self, forKey: .searchQuery)
        photoIDs = try container.decode([String].self, forKey: .photoIDs)
        portion = try container.decodeIfPresent(PortionSuggestion.self, forKey: .portion)
        unresolvedDetails = try container.decodeIfPresent([UnresolvedDetail].self, forKey: .unresolvedDetails) ?? []
    }
}

/// A suggested portion: a quantity of a familiar unit ("1 cup", "2 slices", "150 g"), with the analysis's
/// gram estimate when it gave one. The app converts it to grams only through documented serving weights or
/// this gram estimate, and the person reviews it before saving.
public struct PortionSuggestion: Codable, Hashable, Sendable {
    public var quantity: Double
    /// e.g. "cup", "slice", "piece" or "g".
    public var unit: String
    public var grams: Double?

    public init(quantity: Double, unit: String, grams: Double? = nil) {
        self.quantity = quantity
        self.unit = unit
        self.grams = grams
    }
}

/// A specific detail about a suggested food that the photos cannot settle.
public struct UnresolvedDetail: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        /// Which food it is.
        case identity
        /// An ingredient that may be present but cannot be seen or identified (e.g. the oil used).
        case ingredient
        /// How it was prepared (e.g. fried or baked).
        case preparation
        /// How much there is.
        case portion
    }

    public var kind: Kind
    /// Shown to the person, e.g. "Cooking oil not visible".
    public var detail: String
    /// The focused question to ask the person about it, e.g. "Was it cooked in oil? How much?"; nil when the
    /// analysis gave none (the app then asks about `detail` itself).
    public var question: String?
    /// For a hidden ingredient or preparation detail: a short query for looking up what the person may add
    /// in documented nutrition sources, e.g. "oil vegetable".
    public var searchQuery: String?

    public init(kind: Kind, detail: String, question: String? = nil, searchQuery: String? = nil) {
        self.kind = kind
        self.detail = detail
        self.question = question
        self.searchQuery = searchQuery
    }
}

/// Suggestions that likely show the same food from different photos.
public struct DuplicateGroupHint: Codable, Hashable, Sendable {
    public var suggestionIDs: [String]
    /// Why they look like the same food, if the analysis said.
    public var reason: String?

    public init(suggestionIDs: [String], reason: String? = nil) {
        self.suggestionIDs = suggestionIDs
        self.reason = reason
    }
}

/// The body of every non-200 reply from the analysis endpoint. Its message is safe to show and never contains
/// credentials or raw provider output.
public struct AnalysisErrorResponse: Codable, Hashable, Sendable, Error {
    public var code: AnalysisErrorCode
    public var message: String

    public init(code: AnalysisErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public enum AnalysisErrorCode: String, Codable, Hashable, Sendable {
    /// The request is not a valid analysis request (e.g. no photos, unsupported image type, too large).
    case invalidRequest
    /// The backend has no provider credential configured.
    case notConfigured
    /// The provider could not be reached or refused the request (outage, quota, rejected key).
    case providerUnavailable
    /// The provider answered with output that does not fit the contract.
    case malformedProviderOutput
}
