import AnalysisContract
import Foundation
import MealPhotoAnalysis

/// Stands in for the hosted provider over HTTP. Records what the backend sends and answers with a fixture,
/// so no test reaches a live model or needs a real key.
final class RecordingProviderTransport: ProviderTransport, @unchecked Sendable {
    enum Reply {
        case response(statusCode: Int, body: String)
        case transportError(Error)
    }

    var reply: Reply
    private(set) var sentRequests: [ProviderRequest] = []

    init(_ reply: Reply) {
        self.reply = reply
    }

    func send(_ request: ProviderRequest) async throws -> ProviderResponse {
        sentRequests.append(request)
        switch reply {
        case .response(let statusCode, let body):
            return ProviderResponse(statusCode: statusCode, body: Data(body.utf8))
        case .transportError(let error):
            throw error
        }
    }
}

enum Fixtures {
    static let testKey = "AIzaTEST-not-a-real-key-123"
    static let photoID = "6F1A2B3C-0000-4000-8000-000000000001"
    static let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])

    static func analysisRequestBody(
        photos: [PhotoUpload] = [PhotoUpload(photoID: photoID, mediaType: "image/jpeg", imageData: jpegBytes)]
    ) -> Data {
        try! JSONEncoder().encode(MealPhotoAnalysisRequest(photos: photos))
    }

    /// A generateContent reply whose first candidate's text part is `modelText`.
    static func generateContentReply(modelText: String, finishReason: String = "STOP") -> String {
        let escaped = String(data: try! JSONEncoder().encode(modelText), encoding: .utf8)!
        return """
        {
          "candidates": [
            {
              "content": { "role": "model", "parts": [ { "text": \(escaped) } ] },
              "finishReason": "\(finishReason)",
              "index": 0
            }
          ],
          "usageMetadata": { "promptTokenCount": 1290, "candidatesTokenCount": 180, "totalTokenCount": 1470 },
          "modelVersion": "gemini-2.5-flash"
        }
        """
    }

    /// Structured model output for a plate of rice and stir-fried chicken. It also carries nutrient guesses,
    /// which the backend must drop.
    static let riceAndChickenOutput = """
    {
      "foods": [
        {
          "id": "food-1",
          "name": "Steamed white rice",
          "searchQuery": "rice white cooked",
          "photoIds": ["\(photoID)"],
          "portion": { "quantity": 1, "unit": "cup", "grams": 158 },
          "unresolvedDetails": [],
          "calories": 205,
          "protein": 4.3
        },
        {
          "id": "food-2",
          "name": "Stir-fried chicken",
          "searchQuery": "chicken breast cooked",
          "photoIds": ["\(photoID)"],
          "portion": { "quantity": 120, "unit": "g" },
          "unresolvedDetails": [
            { "kind": "ingredient", "detail": "Cooking oil not visible" },
            { "kind": "preparation", "detail": "Sauce may contain added sugar" }
          ],
          "estimatedNutrients": { "calories": 240, "fat": 9 }
        }
      ],
      "duplicateGroups": []
    }
    """
}

struct SimulatedNetworkError: Error, CustomStringConvertible {
    var description: String
}
