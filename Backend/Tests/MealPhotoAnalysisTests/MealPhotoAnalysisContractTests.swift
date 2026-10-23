import AnalysisContract
import Foundation
import MealPhotoAnalysis
import XCTest

/// Ticket #9: the backend's external contract. The app posts meal photos; the backend asks the hosted provider
/// (Gemini) for structured suggestions and answers in the shared `AnalysisContract`. Provider replies are
/// controlled fixtures: these tests never assert what a live model says.
final class MealPhotoAnalysisContractTests: XCTestCase {
    private func makeService(
        _ transport: RecordingProviderTransport,
        credential: ProviderCredential? = ProviderCredential(apiKey: Fixtures.testKey)
    ) -> MealPhotoAnalysisService {
        MealPhotoAnalysisService(credential: credential, transport: transport)
    }

    // MARK: Response shape

    func test_structuredProviderOutputBecomesSuggestionsWithPortionsAndSpecificUncertainty() async throws {
        let transport = RecordingProviderTransport(.response(
            statusCode: 200, body: Fixtures.generateContentReply(modelText: Fixtures.riceAndChickenOutput)
        ))

        let reply = await makeService(transport).handle(requestBody: Fixtures.analysisRequestBody())

        XCTAssertEqual(reply.statusCode, 200)
        XCTAssertEqual(reply.contentType, "application/json")
        let response = try JSONDecoder().decode(MealPhotoAnalysisResponse.self, from: reply.body)
        XCTAssertEqual(response, MealPhotoAnalysisResponse(
            suggestions: [
                FoodSuggestion(
                    id: "food-1",
                    name: "Steamed white rice",
                    searchQuery: "rice white cooked",
                    photoIDs: [Fixtures.photoID],
                    portion: PortionSuggestion(quantity: 1, unit: "cup", grams: 158)
                ),
                FoodSuggestion(
                    id: "food-2",
                    name: "Stir-fried chicken",
                    searchQuery: "chicken breast cooked",
                    photoIDs: [Fixtures.photoID],
                    portion: PortionSuggestion(quantity: 120, unit: "g"),
                    unresolvedDetails: [
                        UnresolvedDetail(kind: .ingredient, detail: "Cooking oil not visible"),
                        UnresolvedDetail(kind: .preparation, detail: "Sauce may contain added sugar"),
                    ]
                ),
            ],
            duplicateGroups: []
        ))
    }

    /// Ticket #11: for a mixed dish the analysis names what the photo cannot show and the focused question to
    /// ask, with a search for the hidden ingredient, instead of inventing an answer.
    func test_mixedDishUnknownsArriveAsFocusedQuestionsInsteadOfGuesses() async throws {
        let output = """
        {
          "foods": [
            { "id": "1", "name": "Vegetable fried rice", "searchQuery": "fried rice vegetable",
              "photoIds": ["\(Fixtures.photoID)"], "portion": { "quantity": 1.5, "unit": "cup" },
              "unresolvedDetails": [
                { "kind": "preparation", "detail": "Cooking oil not visible",
                  "question": " Was it cooked in oil? How much? ", "searchQuery": "oil vegetable" },
                { "kind": "ingredient", "detail": "Sauce under the rice can't be identified",
                  "question": "Which sauce was added?", "searchQuery": "" },
                { "kind": "portion", "detail": "Bowl depth unclear", "question": "  " }
              ] }
          ],
          "duplicateGroups": []
        }
        """
        let transport = RecordingProviderTransport(.response(
            statusCode: 200, body: Fixtures.generateContentReply(modelText: output)
        ))

        let reply = await makeService(transport).handle(requestBody: Fixtures.analysisRequestBody())

        XCTAssertEqual(reply.statusCode, 200)
        let response = try JSONDecoder().decode(MealPhotoAnalysisResponse.self, from: reply.body)
        XCTAssertEqual(response.suggestions.first?.unresolvedDetails, [
            UnresolvedDetail(
                kind: .preparation, detail: "Cooking oil not visible",
                question: "Was it cooked in oil? How much?", searchQuery: "oil vegetable"
            ),
            UnresolvedDetail(
                kind: .ingredient, detail: "Sauce under the rice can't be identified", question: "Which sauce was added?"
            ),
            UnresolvedDetail(kind: .portion, detail: "Bowl depth unclear"),
        ])
    }

    /// Story 34: how sure the analysis is of each food's identity reaches the app, so it can ask the person to
    /// check weak matches. A missing or unrecognized rating arrives as no rating, which the app treats as weak.
    func test_matchConfidenceReachesTheAppAndAnUnrecognizedRatingIsDropped() async throws {
        let output = """
        {
          "foods": [
            { "id": "1", "name": "Rice", "searchQuery": "rice", "photoIds": ["\(Fixtures.photoID)"],
              "unresolvedDetails": [], "matchConfidence": "high" },
            { "id": "2", "name": "Curry", "searchQuery": "curry", "photoIds": ["\(Fixtures.photoID)"],
              "unresolvedDetails": [], "matchConfidence": " Low " },
            { "id": "3", "name": "Pickle", "searchQuery": "pickle", "photoIds": ["\(Fixtures.photoID)"],
              "unresolvedDetails": [], "matchConfidence": "certain" },
            { "id": "4", "name": "Bread", "searchQuery": "bread", "photoIds": ["\(Fixtures.photoID)"],
              "unresolvedDetails": [] }
          ],
          "duplicateGroups": []
        }
        """
        let transport = RecordingProviderTransport(.response(
            statusCode: 200, body: Fixtures.generateContentReply(modelText: output)
        ))

        let reply = await makeService(transport).handle(requestBody: Fixtures.analysisRequestBody())

        XCTAssertEqual(reply.statusCode, 200)
        let response = try JSONDecoder().decode(MealPhotoAnalysisResponse.self, from: reply.body)
        XCTAssertEqual(response.suggestions.map(\.matchConfidence), [.high, .low, nil, nil])
        let sent = try XCTUnwrap(transport.sentRequests.first)
        let schemaText = String(decoding: sent.body, as: UTF8.self)
        XCTAssertTrue(schemaText.contains("\"matchConfidence\""), "Schema asks for match confidence")
    }

    func test_modelNutrientGuessesNeverReachTheApp() async throws {
        let transport = RecordingProviderTransport(.response(
            statusCode: 200, body: Fixtures.generateContentReply(modelText: Fixtures.riceAndChickenOutput)
        ))

        let reply = await makeService(transport).handle(requestBody: Fixtures.analysisRequestBody())

        let json = String(decoding: reply.body, as: UTF8.self)
        for nutrientWord in ["calories", "protein", "fat", "estimatedNutrients", "205", "240"] {
            XCTAssertFalse(json.contains(nutrientWord), "Response leaked \(nutrientWord): \(json)")
        }
    }

    func test_duplicateGroupHintsSurviveForCrossPhotoReview() async throws {
        let secondPhotoID = "6F1A2B3C-0000-4000-8000-000000000002"
        let output = """
        {
          "foods": [
            { "id": "a", "name": "Pasta", "searchQuery": "pasta cooked", "photoIds": ["\(Fixtures.photoID)"],
              "unresolvedDetails": [] },
            { "id": "b", "name": "Pasta", "searchQuery": "pasta cooked", "photoIds": ["\(secondPhotoID)"],
              "unresolvedDetails": [{ "kind": "portion", "detail": "Plate depth unclear" }] }
          ],
          "duplicateGroups": [ { "suggestionIds": ["a", "b"], "reason": "Same plate from two angles" } ]
        }
        """
        let transport = RecordingProviderTransport(.response(
            statusCode: 200, body: Fixtures.generateContentReply(modelText: output)
        ))
        let body = Fixtures.analysisRequestBody(photos: [
            PhotoUpload(photoID: Fixtures.photoID, mediaType: "image/jpeg", imageData: Fixtures.jpegBytes),
            PhotoUpload(photoID: secondPhotoID, mediaType: "image/png", imageData: Data([0x89, 0x50])),
        ])

        let reply = await makeService(transport).handle(requestBody: body)

        XCTAssertEqual(reply.statusCode, 200)
        let response = try JSONDecoder().decode(MealPhotoAnalysisResponse.self, from: reply.body)
        XCTAssertEqual(response.suggestions.map(\.photoIDs), [[Fixtures.photoID], [secondPhotoID]])
        XCTAssertNil(response.suggestions[0].portion)
        XCTAssertEqual(
            response.duplicateGroups,
            [DuplicateGroupHint(suggestionIDs: ["a", "b"], reason: "Same plate from two angles")]
        )
    }

    // MARK: Provider request

    func test_providerRequestSendsThePhotoInlineAndAsksForStructuredSuggestionsWithoutNutrients() async throws {
        let transport = RecordingProviderTransport(.response(
            statusCode: 200, body: Fixtures.generateContentReply(modelText: Fixtures.riceAndChickenOutput)
        ))

        _ = await makeService(transport).handle(requestBody: Fixtures.analysisRequestBody())

        let sent = try XCTUnwrap(transport.sentRequests.first)
        XCTAssertEqual(transport.sentRequests.count, 1)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(
            sent.url.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
        )
        XCTAssertEqual(sent.headers["Content-Type"], "application/json")

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        let parts = try XCTUnwrap(((body["contents"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]])
        let inlineData = try XCTUnwrap(parts.compactMap { $0["inline_data"] as? [String: Any] }.first)
        XCTAssertEqual(inlineData["mime_type"] as? String, "image/jpeg")
        XCTAssertEqual(inlineData["data"] as? String, Fixtures.jpegBytes.base64EncodedString())
        let prompt = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        XCTAssertTrue(prompt.contains(Fixtures.photoID), "The prompt labels each photo with its ID")

        let generationConfig = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertEqual(generationConfig["responseMimeType"] as? String, "application/json")
        let schema = try XCTUnwrap(generationConfig["responseSchema"] as? [String: Any])
        let schemaText = String(decoding: try JSONSerialization.data(withJSONObject: schema), as: UTF8.self)
        for field in ["foods", "searchQuery", "photoIds", "portion", "unresolvedDetails", "question", "duplicateGroups"] {
            XCTAssertTrue(schemaText.contains("\"\(field)\""), "Schema asks for \(field)")
        }
        XCTAssertTrue(prompt.contains("instead of guessing"), "Unknowns are asked about, not invented")
        XCTAssertTrue(prompt.contains("oil"), "The prompt names high-impact hidden ingredients such as oil")
        XCTAssertFalse(schemaText.lowercased().contains("calorie"), "Schema never asks for nutrient values")
    }

    func test_severalPhotosGoInOneProviderRequestEachLabeledWithItsPhotoID() async throws {
        let secondPhotoID = "6F1A2B3C-0000-4000-8000-000000000002"
        let secondPhoto = Data([0x89, 0x50, 0x4E, 0x47])
        let transport = RecordingProviderTransport(.response(
            statusCode: 200, body: Fixtures.generateContentReply(modelText: Fixtures.riceAndChickenOutput)
        ))

        _ = await makeService(transport).handle(requestBody: Fixtures.analysisRequestBody(photos: [
            PhotoUpload(photoID: Fixtures.photoID, mediaType: "image/jpeg", imageData: Fixtures.jpegBytes),
            PhotoUpload(photoID: secondPhotoID, mediaType: "image/png", imageData: secondPhoto),
        ]))

        XCTAssertEqual(transport.sentRequests.count, 1, "One analysis for all the meal photos")
        let sent = try XCTUnwrap(transport.sentRequests.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        let parts = try XCTUnwrap(((body["contents"] as? [[String: Any]])?.first?["parts"]) as? [[String: Any]])
        // Each image follows the label naming its photo ID, so suggestions can refer back to the photo.
        let labeledImages = zip(parts, parts.dropFirst()).compactMap { label, image -> String? in
            guard let text = label["text"] as? String,
                  let inline = image["inline_data"] as? [String: Any],
                  let mimeType = inline["mime_type"] as? String,
                  let data = inline["data"] as? String else { return nil }
            return "\(text) | \(mimeType) | \(data)"
        }
        XCTAssertEqual(labeledImages, [
            "Photo ID: \(Fixtures.photoID) | image/jpeg | \(Fixtures.jpegBytes.base64EncodedString())",
            "Photo ID: \(secondPhotoID) | image/png | \(secondPhoto.base64EncodedString())",
        ])
        let prompt = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        XCTAssertTrue(prompt.contains("duplicateGroups"), "The prompt asks for likely cross-photo duplicates")
        XCTAssertTrue(prompt.contains("same photo"), "The prompt keeps foods seen in one photo distinct")
    }

    func test_modelNameAndKeyComeFromTheBackendEnvironment() {
        let configuration = GeminiConfiguration(environment: [
            "GEMINI_API_KEY": Fixtures.testKey,
            "GEMINI_MODEL": "gemini-2.5-flash-lite",
        ])

        XCTAssertEqual(configuration.model, "gemini-2.5-flash-lite")
        XCTAssertNotNil(configuration.credential)
        XCTAssertEqual(GeminiConfiguration(environment: [:]).model, "gemini-2.5-flash")
        XCTAssertNil(GeminiConfiguration(environment: [:]).credential)
        XCTAssertNil(GeminiConfiguration(environment: ["GEMINI_API_KEY": "  "]).credential)
    }
}
