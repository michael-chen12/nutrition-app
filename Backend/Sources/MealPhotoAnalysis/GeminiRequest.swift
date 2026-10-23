import AnalysisContract
import Foundation

/// Builds the Gemini `generateContent` request for a meal photo analysis: each photo as inline image data,
/// labeled with its photo ID, and a response schema for structured suggestions
/// (https://ai.google.dev/gemini-api/docs/image-understanding, https://ai.google.dev/gemini-api/docs/structured-output).
///
/// The schema never asks for nutrient values: nutrients come only from documented sources or custom foods.
enum GeminiRequest {
    static func make(
        for request: MealPhotoAnalysisRequest,
        credential: ProviderCredential,
        model: String,
        baseURL: URL
    ) throws -> ProviderRequest {
        var parts: [Part] = [.text(instructions)]
        for photo in request.photos {
            parts.append(.text("Photo ID: \(photo.photoID)"))
            parts.append(.inlineData(mimeType: photo.mediaType, data: photo.imageData.base64EncodedString()))
        }
        let body = Body(
            contents: [Content(role: "user", parts: parts)],
            generationConfig: GenerationConfig(
                responseMimeType: "application/json",
                responseSchema: responseSchema,
                temperature: 0.2
            )
        )
        return ProviderRequest(
            url: baseURL.appendingPathComponent("models").appendingPathComponent("\(model):generateContent"),
            method: "POST",
            // The key goes only in this header: never in the URL, where proxies and logs keep it.
            headers: ["Content-Type": "application/json", "x-goog-api-key": credential.apiKey],
            body: try JSONEncoder().encode(body)
        )
    }

    static let instructions = """
    You help a person review the food pictured in their meal photos for an approximate, general-wellness \
    nutrition estimate. The person will check and correct everything you suggest.

    List every distinct food and drink visible in the photos, including food that looks shared or partly eaten \
    and visible leftovers. Each photo is preceded by its "Photo ID" label.

    For each food give:
    - id: a short identifier unique within your answer.
    - name: the common English name; keep the dish's own name for dishes from any cuisine.
    - searchQuery: 2 to 5 words to look the food up in a nutrition database such as USDA FoodData Central.
    - photoIds: the Photo IDs of the photos that show it.
    - portion: a quantity of a familiar unit (cup, slice, piece, bowl, tablespoon or g), with grams only when \
    you can reasonably estimate them. Leave it out if you cannot judge the amount.
    - unresolvedDetails: each specific thing the photos cannot settle, instead of guessing: which food it is \
    (identity), an ingredient that may be present but cannot be seen (ingredient), how it was prepared \
    (preparation), or how much there is (portion).

    If the same food appears in more than one photo, list it once for each photo and put those ids in one \
    duplicateGroups entry with a short reason.

    Do not give calories or any nutrient values.
    """

    /// The structured output Gemini must return (an OpenAPI schema subset).
    static let responseSchema: JSONValue = [
        "type": "OBJECT",
        "properties": [
            "foods": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "id": ["type": "STRING"],
                        "name": ["type": "STRING"],
                        "searchQuery": ["type": "STRING"],
                        "photoIds": ["type": "ARRAY", "items": ["type": "STRING"]],
                        "portion": [
                            "type": "OBJECT",
                            "properties": [
                                "quantity": ["type": "NUMBER"],
                                "unit": ["type": "STRING"],
                                "grams": ["type": "NUMBER"],
                            ],
                            "required": ["quantity", "unit"],
                        ],
                        "unresolvedDetails": [
                            "type": "ARRAY",
                            "items": [
                                "type": "OBJECT",
                                "properties": [
                                    "kind": [
                                        "type": "STRING",
                                        "enum": .array(UnresolvedDetail.Kind.allCases.map { .string($0.rawValue) }),
                                    ],
                                    "detail": ["type": "STRING"],
                                ],
                                "required": ["kind", "detail"],
                            ],
                        ],
                    ],
                    "required": ["id", "name", "searchQuery", "photoIds", "unresolvedDetails"],
                ],
            ],
            "duplicateGroups": [
                "type": "ARRAY",
                "items": [
                    "type": "OBJECT",
                    "properties": [
                        "suggestionIds": ["type": "ARRAY", "items": ["type": "STRING"]],
                        "reason": ["type": "STRING"],
                    ],
                    "required": ["suggestionIds"],
                ],
            ],
        ],
        "required": ["foods", "duplicateGroups"],
    ]

    // MARK: Wire shapes (REST field names as documented)

    private struct Body: Encodable {
        var contents: [Content]
        var generationConfig: GenerationConfig
    }

    private struct Content: Encodable {
        var role: String
        var parts: [Part]
    }

    private enum Part: Encodable {
        case text(String)
        case inlineData(mimeType: String, data: String)

        private enum CodingKeys: String, CodingKey {
            case text
            case inlineData = "inline_data"
        }

        private enum InlineDataKeys: String, CodingKey {
            case mimeType = "mime_type"
            case data
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode(text, forKey: .text)
            case .inlineData(let mimeType, let data):
                var inline = container.nestedContainer(keyedBy: InlineDataKeys.self, forKey: .inlineData)
                try inline.encode(mimeType, forKey: .mimeType)
                try inline.encode(data, forKey: .data)
            }
        }
    }

    private struct GenerationConfig: Encodable {
        var responseMimeType: String
        var responseSchema: JSONValue
        var temperature: Double
    }
}
