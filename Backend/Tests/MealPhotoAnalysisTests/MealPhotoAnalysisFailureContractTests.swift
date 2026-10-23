import AnalysisContract
import Foundation
import MealPhotoAnalysis
import XCTest

/// Ticket #9: credential protection, provider failures and malformed provider output. Every failure reaches
/// the app as an `AnalysisErrorResponse` with a safe message, so the app can offer the manual path.
final class MealPhotoAnalysisFailureContractTests: XCTestCase {
    private func reply(
        to transport: RecordingProviderTransport,
        body: Data = Fixtures.analysisRequestBody(),
        credential: ProviderCredential? = ProviderCredential(apiKey: Fixtures.testKey)
    ) async -> AnalysisHTTPResponse {
        await MealPhotoAnalysisService(credential: credential, transport: transport).handle(requestBody: body)
    }

    private func assertError(
        _ reply: AnalysisHTTPResponse,
        status: Int,
        code: AnalysisErrorCode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(reply.statusCode, status, file: file, line: line)
        XCTAssertEqual(reply.contentType, "application/json", file: file, line: line)
        let error = try JSONDecoder().decode(AnalysisErrorResponse.self, from: reply.body)
        XCTAssertEqual(error.code, code, file: file, line: line)
        XCTAssertFalse(error.message.isEmpty, file: file, line: line)
        XCTAssertFalse(
            String(decoding: reply.body, as: UTF8.self).contains(Fixtures.testKey),
            "The credential never appears in a reply", file: file, line: line
        )
    }

    // MARK: Credential handling

    func test_credentialTravelsOnlyInTheProviderRequestHeader() async throws {
        let transport = RecordingProviderTransport(.response(
            statusCode: 200, body: Fixtures.generateContentReply(modelText: Fixtures.riceAndChickenOutput)
        ))

        let reply = await reply(to: transport)

        let sent = try XCTUnwrap(transport.sentRequests.first)
        XCTAssertEqual(sent.headers["x-goog-api-key"], Fixtures.testKey)
        XCTAssertFalse(sent.url.absoluteString.contains(Fixtures.testKey), "Never in the URL")
        XCTAssertFalse(sent.url.absoluteString.contains("key="), "Never as a query parameter")
        XCTAssertFalse(String(decoding: sent.body, as: UTF8.self).contains(Fixtures.testKey), "Never in the body")
        XCTAssertFalse(String(decoding: reply.body, as: UTF8.self).contains(Fixtures.testKey), "Never sent to the app")
    }

    func test_printingACredentialDoesNotRevealTheKey() throws {
        let credential = try XCTUnwrap(ProviderCredential(apiKey: Fixtures.testKey))
        let configuration = GeminiConfiguration(environment: ["GEMINI_API_KEY": Fixtures.testKey])

        for text in [
            String(describing: credential), String(reflecting: credential), "\(credential)",
            String(describing: configuration), String(reflecting: configuration),
        ] {
            XCTAssertFalse(text.contains(Fixtures.testKey), text)
        }
    }

    func test_withoutAConfiguredKeyNothingIsUploaded() async throws {
        let transport = RecordingProviderTransport(.response(statusCode: 200, body: "{}"))

        let reply = await reply(to: transport, credential: nil)

        try assertError(reply, status: 503, code: .notConfigured)
        XCTAssertTrue(transport.sentRequests.isEmpty)
    }

    func test_providerRejectionThatEchoesTheKeyIsReportedWithoutIt() async throws {
        let transport = RecordingProviderTransport(.response(statusCode: 400, body: """
        { "error": { "code": 400, "message": "API key not valid: \(Fixtures.testKey)", "status": "INVALID_ARGUMENT" } }
        """))

        try assertError(await reply(to: transport), status: 502, code: .providerUnavailable)
    }

    // MARK: Provider failures

    func test_providerOutageAndQuotaExhaustionAreReportedAsUnavailable() async throws {
        for status in [429, 500, 503] {
            let transport = RecordingProviderTransport(.response(statusCode: status, body: """
            { "error": { "code": \(status), "message": "Resource has been exhausted", "status": "RESOURCE_EXHAUSTED" } }
            """))
            try assertError(await reply(to: transport), status: 502, code: .providerUnavailable)
        }
    }

    func test_networkFailureIsReportedAsUnavailableWithoutItsDetails() async throws {
        let transport = RecordingProviderTransport(.transportError(SimulatedNetworkError(
            description: "TLS failure for https://generativelanguage.googleapis.com?key=\(Fixtures.testKey)"
        )))

        let reply = await reply(to: transport)

        try assertError(reply, status: 502, code: .providerUnavailable)
        XCTAssertFalse(String(decoding: reply.body, as: UTF8.self).contains("TLS"))
    }

    // MARK: Malformed provider output

    func test_outputThatDoesNotFitTheContractIsReportedAsMalformed() async throws {
        let otherPhoto = "6F1A2B3C-0000-4000-8000-0000000000FF"
        let malformedReplies: [String: String] = [
            "not JSON at all": "<html>Bad gateway</html>",
            "no candidates": #"{ "promptFeedback": { "blockReason": "OTHER" } }"#,
            "model text is prose": Fixtures.generateContentReply(modelText: "Looks like rice and chicken!"),
            "truncated output": Fixtures.generateContentReply(
                modelText: #"{ "foods": [ { "id": "1", "name": "Ri"#, finishReason: "MAX_TOKENS"
            ),
            "missing foods": Fixtures.generateContentReply(modelText: #"{ "duplicateGroups": [] }"#),
            "food without a name": Fixtures.generateContentReply(modelText: """
            { "foods": [ { "id": "1", "name": " ", "searchQuery": "x", "photoIds": ["\(Fixtures.photoID)"],
              "unresolvedDetails": [] } ], "duplicateGroups": [] }
            """),
            "photo that was not sent": Fixtures.generateContentReply(modelText: """
            { "foods": [ { "id": "1", "name": "Rice", "searchQuery": "rice", "photoIds": ["\(otherPhoto)"],
              "unresolvedDetails": [] } ], "duplicateGroups": [] }
            """),
            "negative portion": Fixtures.generateContentReply(modelText: """
            { "foods": [ { "id": "1", "name": "Rice", "searchQuery": "rice", "photoIds": ["\(Fixtures.photoID)"],
              "portion": { "quantity": -1, "unit": "cup" }, "unresolvedDetails": [] } ], "duplicateGroups": [] }
            """),
            "unknown uncertainty kind": Fixtures.generateContentReply(modelText: """
            { "foods": [ { "id": "1", "name": "Rice", "searchQuery": "rice", "photoIds": ["\(Fixtures.photoID)"],
              "unresolvedDetails": [ { "kind": "vibes", "detail": "?" } ] } ], "duplicateGroups": [] }
            """),
            "duplicate group naming an unlisted food": Fixtures.generateContentReply(modelText: """
            { "foods": [ { "id": "1", "name": "Rice", "searchQuery": "rice", "photoIds": ["\(Fixtures.photoID)"],
              "unresolvedDetails": [] } ], "duplicateGroups": [ { "suggestionIds": ["1", "9"] } ] }
            """),
        ]

        for (situation, body) in malformedReplies {
            let transport = RecordingProviderTransport(.response(statusCode: 200, body: body))
            let reply = await reply(to: transport)
            XCTAssertEqual(reply.statusCode, 502, situation)
            let error = try? JSONDecoder().decode(AnalysisErrorResponse.self, from: reply.body)
            XCTAssertEqual(error?.code, .malformedProviderOutput, situation)
        }
    }

    // MARK: Invalid requests

    func test_invalidRequestsAreRefusedBeforeAnythingIsUploaded() async throws {
        let jpeg = Fixtures.jpegBytes
        let invalidBodies: [String: Data] = [
            "not a request": Data("hello".utf8),
            "no photos": Fixtures.analysisRequestBody(photos: []),
            "unsupported type": Fixtures.analysisRequestBody(photos: [
                PhotoUpload(photoID: "1", mediaType: "application/pdf", imageData: jpeg),
            ]),
            "empty image": Fixtures.analysisRequestBody(photos: [
                PhotoUpload(photoID: "1", mediaType: "image/jpeg", imageData: Data()),
            ]),
            "repeated photo id": Fixtures.analysisRequestBody(photos: [
                PhotoUpload(photoID: "1", mediaType: "image/jpeg", imageData: jpeg),
                PhotoUpload(photoID: "1", mediaType: "image/jpeg", imageData: jpeg),
            ]),
            "too many photos": Fixtures.analysisRequestBody(photos: (0...10).map {
                PhotoUpload(photoID: "\($0)", mediaType: "image/jpeg", imageData: jpeg)
            }),
        ]

        for (situation, body) in invalidBodies {
            let transport = RecordingProviderTransport(.response(statusCode: 200, body: "{}"))
            let reply = await reply(to: transport, body: body)
            XCTAssertEqual(reply.statusCode, 400, situation)
            let error = try? JSONDecoder().decode(AnalysisErrorResponse.self, from: reply.body)
            XCTAssertEqual(error?.code, .invalidRequest, situation)
            XCTAssertTrue(transport.sentRequests.isEmpty, situation)
        }
    }
}
