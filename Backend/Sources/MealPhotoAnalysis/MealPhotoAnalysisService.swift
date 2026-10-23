import AnalysisContract
import Foundation

/// The backend's meal photo analysis endpoint, independent of any HTTP server framework: it takes the body
/// the app posted to `MealPhotoAnalysisEndpoint.path` and returns the reply to send back.
///
/// Every reply is JSON in the shared contract: a `MealPhotoAnalysisResponse` (200) or an
/// `AnalysisErrorResponse`. Error messages are fixed, safe strings; provider replies and transport errors are
/// never forwarded, so neither the credential nor raw model output can leak to the app.
public struct MealPhotoAnalysisService: Sendable {
    /// Most photos accepted in one analysis.
    public static let maximumPhotoCount = 10
    /// Largest total image size accepted in one analysis. Gemini limits an inline request to 20 MB, and base64
    /// adds a third.
    public static let maximumTotalImageBytes = 14 * 1024 * 1024
    /// Image types Gemini accepts as inline data.
    public static let supportedMediaTypes: Set<String> = [
        "image/jpeg", "image/png", "image/webp", "image/heic", "image/heif",
    ]

    private let credential: ProviderCredential?
    private let model: String
    private let baseURL: URL
    private let transport: ProviderTransport

    public init(
        credential: ProviderCredential?,
        model: String = GeminiConfiguration.defaultModel,
        baseURL: URL = GeminiConfiguration.defaultBaseURL,
        transport: ProviderTransport
    ) {
        self.credential = credential
        self.model = model
        self.baseURL = baseURL
        self.transport = transport
    }

    public init(configuration: GeminiConfiguration, transport: ProviderTransport) {
        self.init(
            credential: configuration.credential,
            model: configuration.model,
            baseURL: configuration.baseURL,
            transport: transport
        )
    }

    public func handle(requestBody: Data) async -> AnalysisHTTPResponse {
        let request: MealPhotoAnalysisRequest
        do {
            request = try JSONDecoder().decode(MealPhotoAnalysisRequest.self, from: requestBody)
        } catch {
            return .failure(400, .invalidRequest, "The analysis request could not be read.")
        }
        if let invalid = validationFailure(request) { return invalid }
        guard let credential else {
            return .failure(503, .notConfigured, "Photo analysis is not set up on the server.")
        }

        let providerResponse: ProviderResponse
        do {
            let providerRequest = try GeminiRequest.make(
                for: request, credential: credential, model: model, baseURL: baseURL
            )
            providerResponse = try await transport.send(providerRequest)
        } catch {
            return .providerUnavailable
        }
        guard (200..<300).contains(providerResponse.statusCode) else { return .providerUnavailable }

        do {
            return .success(try GeminiResponse.suggestions(from: providerResponse.body, for: request))
        } catch {
            return .failure(
                502, .malformedProviderOutput, "The photo analysis service returned results that could not be used."
            )
        }
    }

    private func validationFailure(_ request: MealPhotoAnalysisRequest) -> AnalysisHTTPResponse? {
        guard !request.photos.isEmpty else {
            return .failure(400, .invalidRequest, "Add at least one meal photo to analyze.")
        }
        guard request.photos.count <= Self.maximumPhotoCount else {
            return .failure(400, .invalidRequest, "Analyze at most \(Self.maximumPhotoCount) photos at a time.")
        }
        guard Set(request.photos.map(\.photoID)).count == request.photos.count,
              request.photos.allSatisfy({ !$0.photoID.isEmpty }) else {
            return .failure(400, .invalidRequest, "Each photo needs its own identifier.")
        }
        guard request.photos.allSatisfy({ Self.supportedMediaTypes.contains($0.mediaType.lowercased()) }) else {
            return .failure(400, .invalidRequest, "Use JPEG, PNG, WebP or HEIC photos.")
        }
        guard request.photos.allSatisfy({ !$0.imageData.isEmpty }) else {
            return .failure(400, .invalidRequest, "A photo has no image data.")
        }
        guard request.photos.reduce(0, { $0 + $1.imageData.count }) <= Self.maximumTotalImageBytes else {
            return .failure(413, .invalidRequest, "These photos are too large to analyze together.")
        }
        return nil
    }
}

/// A reply from the analysis endpoint: status, content type and JSON body.
public struct AnalysisHTTPResponse: Sendable {
    public var statusCode: Int
    public var contentType: String
    public var body: Data

    static func success(_ response: MealPhotoAnalysisResponse) -> AnalysisHTTPResponse {
        AnalysisHTTPResponse(statusCode: 200, contentType: "application/json", body: try! encoder.encode(response))
    }

    static func failure(_ statusCode: Int, _ code: AnalysisErrorCode, _ message: String) -> AnalysisHTTPResponse {
        AnalysisHTTPResponse(
            statusCode: statusCode,
            contentType: "application/json",
            body: try! encoder.encode(AnalysisErrorResponse(code: code, message: message))
        )
    }

    static let providerUnavailable = failure(
        502, .providerUnavailable, "The photo analysis service is unavailable right now."
    )

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
