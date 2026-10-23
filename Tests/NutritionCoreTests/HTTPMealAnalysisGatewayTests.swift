import Foundation
import NutritionCore
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ticket #9: the app's HTTP adapter for the analysis backend speaks the shared contract and turns every
/// backend failure into a `MealAnalysisGatewayError`, so the workflow can offer the manual path.
final class HTTPMealAnalysisGatewayTests: XCTestCase {
    private let backend = URL(string: "http://127.0.0.1:8080")!
    private let request = MealPhotoAnalysisRequest(photos: [
        PhotoUpload(photoID: "photo-1", mediaType: "image/jpeg", imageData: Data([0xFF, 0xD8])),
    ])

    private func gateway(
        replying status: Int,
        _ body: String,
        recordInto sent: SentRequests? = nil
    ) -> HTTPMealAnalysisGateway {
        HTTPMealAnalysisGateway(backendURL: backend) { urlRequest in
            sent?.requests.append(urlRequest)
            let response = HTTPURLResponse(url: urlRequest.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    final class SentRequests {
        var requests: [URLRequest] = []
    }

    func test_postsTheContractRequestAndDecodesSuggestions() async throws {
        let sent = SentRequests()
        let reply = MealPhotoAnalysisResponse(suggestions: [
            FoodSuggestion(id: "1", name: "Rice", searchQuery: "rice", photoIDs: ["photo-1"]),
        ])
        let replyJSON = String(decoding: try JSONEncoder().encode(reply), as: UTF8.self)

        let response = try await gateway(replying: 200, replyJSON, recordInto: sent).analyzeMealPhotos(request)

        XCTAssertEqual(response, reply)
        let urlRequest = try XCTUnwrap(sent.requests.first)
        XCTAssertEqual(urlRequest.url?.absoluteString, "http://127.0.0.1:8080/v1/meal-photo-analyses")
        XCTAssertEqual(urlRequest.httpMethod, "POST")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(urlRequest.httpBody)
        XCTAssertEqual(try JSONDecoder().decode(MealPhotoAnalysisRequest.self, from: body), request)
    }

    func test_backendFailuresBecomeGatewayErrors() async throws {
        let cases: [(Int, String, MealAnalysisGatewayError)] = [
            (502, #"{"code":"malformedProviderOutput","message":"x"}"#, .malformedAnalysis),
            (502, #"{"code":"providerUnavailable","message":"x"}"#, .analysisUnavailable),
            (503, #"{"code":"notConfigured","message":"x"}"#, .analysisUnavailable),
            (400, #"{"code":"invalidRequest","message":"x"}"#, .analysisUnavailable),
            (500, "Internal Server Error", .analysisUnavailable),
            (200, #"{"suggestions": "not a list"}"#, .malformedAnalysis),
        ]
        for (status, body, expected) in cases {
            do {
                _ = try await gateway(replying: status, body).analyzeMealPhotos(request)
                XCTFail("Expected \(expected) for \(status) \(body)")
            } catch {
                XCTAssertEqual(error as? MealAnalysisGatewayError, expected, "\(status) \(body)")
            }
        }
    }

    func test_unreachableBackendIsReportedAsUnavailable() async throws {
        let gateway = HTTPMealAnalysisGateway(backendURL: backend) { _ in throw URLError(.cannotConnectToHost) }

        do {
            _ = try await gateway.analyzeMealPhotos(request)
            XCTFail("Expected analysisUnavailable")
        } catch {
            XCTAssertEqual(error as? MealAnalysisGatewayError, .analysisUnavailable)
        }
    }
}
