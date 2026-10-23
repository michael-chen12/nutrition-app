import AnalysisContract
import Foundation

/// Reads a Gemini `generateContent` reply into the shared contract, refusing anything that does not fit it.
///
/// Only names, search queries, photo references, portion suggestions and unresolved details pass through.
/// Anything else the model adds (such as nutrient guesses) is dropped, since the contract has no place for it.
enum GeminiResponse {
    struct MalformedOutput: Error {
        var reason: String
    }

    static func suggestions(
        from body: Data,
        for request: MealPhotoAnalysisRequest
    ) throws -> MealPhotoAnalysisResponse {
        let reply: Reply
        do {
            reply = try JSONDecoder().decode(Reply.self, from: body)
        } catch {
            throw MalformedOutput(reason: "reply is not a generateContent response")
        }
        guard let candidate = reply.candidates?.first else {
            throw MalformedOutput(reason: "no candidate (blocked: \(reply.promptFeedback?.blockReason ?? "no"))")
        }
        if let finishReason = candidate.finishReason, finishReason != "STOP" {
            throw MalformedOutput(reason: "generation ended with \(finishReason)")
        }
        let text = (candidate.content?.parts ?? []).compactMap(\.text).joined()
        let output: ModelOutput
        do {
            output = try JSONDecoder().decode(ModelOutput.self, from: Data(text.utf8))
        } catch {
            throw MalformedOutput(reason: "model output does not match the response schema")
        }
        return try validated(output, photoIDs: Set(request.photos.map(\.photoID)))
    }

    private static func validated(_ output: ModelOutput, photoIDs: Set<String>) throws -> MealPhotoAnalysisResponse {
        var suggestionIDs = Set<String>()
        let suggestions = try output.foods.map { food -> FoodSuggestion in
            let id = trimmed(food.id)
            let name = trimmed(food.name)
            guard !id.isEmpty, suggestionIDs.insert(id).inserted else {
                throw MalformedOutput(reason: "missing or repeated food id")
            }
            guard !name.isEmpty else { throw MalformedOutput(reason: "food without a name") }
            guard !food.photoIds.isEmpty, food.photoIds.allSatisfy(photoIDs.contains) else {
                throw MalformedOutput(reason: "food refers to no photo or to a photo that was not sent")
            }
            let searchQuery = trimmed(food.searchQuery)
            return FoodSuggestion(
                id: id,
                name: name,
                searchQuery: searchQuery.isEmpty ? name : searchQuery,
                photoIDs: food.photoIds.uniqued(),
                portion: try food.portion.map(validated),
                unresolvedDetails: food.unresolvedDetails.compactMap { detail in
                    let text = trimmed(detail.detail)
                    return text.isEmpty ? nil : UnresolvedDetail(
                        kind: detail.kind,
                        detail: text,
                        question: nonEmpty(detail.question),
                        searchQuery: nonEmpty(detail.searchQuery)
                    )
                }
            )
        }
        let duplicateGroups = try output.duplicateGroups.map { group -> DuplicateGroupHint in
            let ids = group.suggestionIds.uniqued()
            guard ids.count >= 2, ids.allSatisfy(suggestionIDs.contains) else {
                throw MalformedOutput(reason: "duplicate group must name two or more listed foods")
            }
            let reason = group.reason.map(trimmed)
            return DuplicateGroupHint(suggestionIDs: ids, reason: reason?.isEmpty == false ? reason : nil)
        }
        return MealPhotoAnalysisResponse(suggestions: suggestions, duplicateGroups: duplicateGroups)
    }

    private static func validated(_ portion: ModelOutput.Portion) throws -> PortionSuggestion {
        let unit = trimmed(portion.unit)
        guard portion.quantity.isFinite, portion.quantity > 0, !unit.isEmpty else {
            throw MalformedOutput(reason: "portion needs a positive quantity and a unit")
        }
        if let grams = portion.grams, !(grams.isFinite && grams > 0) {
            throw MalformedOutput(reason: "portion grams must be positive")
        }
        return PortionSuggestion(quantity: portion.quantity, unit: unit, grams: portion.grams)
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text.map(trimmed), !text.isEmpty else { return nil }
        return text
    }

    // MARK: Wire shapes

    private struct Reply: Decodable {
        var candidates: [Candidate]?
        var promptFeedback: PromptFeedback?

        struct Candidate: Decodable {
            var content: Content?
            var finishReason: String?
        }

        struct Content: Decodable {
            var parts: [Part]?
        }

        struct Part: Decodable {
            var text: String?
        }

        struct PromptFeedback: Decodable {
            var blockReason: String?
        }
    }

    /// The structured output requested by `GeminiRequest.responseSchema`.
    private struct ModelOutput: Decodable {
        var foods: [Food]
        var duplicateGroups: [DuplicateGroup]

        struct Food: Decodable {
            var id: String
            var name: String
            var searchQuery: String
            var photoIds: [String]
            var portion: Portion?
            var unresolvedDetails: [Detail]

            private enum CodingKeys: String, CodingKey {
                case id, name, searchQuery, photoIds, portion, unresolvedDetails
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = try container.decode(String.self, forKey: .id)
                name = try container.decode(String.self, forKey: .name)
                searchQuery = try container.decodeIfPresent(String.self, forKey: .searchQuery) ?? ""
                photoIds = try container.decode([String].self, forKey: .photoIds)
                portion = try container.decodeIfPresent(Portion.self, forKey: .portion)
                unresolvedDetails = try container.decodeIfPresent([Detail].self, forKey: .unresolvedDetails) ?? []
            }
        }

        struct Portion: Decodable {
            var quantity: Double
            var unit: String
            var grams: Double?
        }

        struct Detail: Decodable {
            var kind: UnresolvedDetail.Kind
            var detail: String
            var question: String?
            var searchQuery: String?
        }

        struct DuplicateGroup: Decodable {
            var suggestionIds: [String]
            var reason: String?
        }

        private enum CodingKeys: String, CodingKey {
            case foods, duplicateGroups
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            foods = try container.decode([Food].self, forKey: .foods)
            duplicateGroups = try container.decodeIfPresent([DuplicateGroup].self, forKey: .duplicateGroups) ?? []
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
