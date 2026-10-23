import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The app's `MealAnalysisGateway` over HTTP: photo analysis goes to the meal photo analysis backend
/// (Backend/), which holds the provider credential, so no key ships with the app.
///
/// Food lookup is not served by the backend yet; it is delegated to `foodLookup` (by default, no results, so
/// search points the person to a custom food).
public final class HTTPMealAnalysisGateway: MealAnalysisGateway {
    public typealias Send = (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let backendURL: URL
    private let send: Send
    private let foodLookup: (String) async throws -> [Food]

    /// - Parameters:
    ///   - backendURL: The backend's base URL, e.g. `http://127.0.0.1:8080` during development.
    ///   - send: Performs the HTTP request; defaults to `URLSession.shared`.
    ///   - foodLookup: Documented food search until the backend serves it.
    public init(
        backendURL: URL,
        foodLookup: @escaping (String) async throws -> [Food] = { _ in [] },
        send: Send? = nil
    ) {
        self.backendURL = backendURL
        self.foodLookup = foodLookup
        self.send = send ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, httpResponse)
        }
    }

    public convenience init(backendURL: URL, send: @escaping Send) {
        self.init(backendURL: backendURL, foodLookup: { _ in [] }, send: send)
    }

    public func searchFoods(matching query: String) async throws -> [Food] {
        try await foodLookup(query)
    }

    public func analyzeMealPhotos(_ request: MealPhotoAnalysisRequest) async throws -> MealPhotoAnalysisResponse {
        var urlRequest = URLRequest(
            url: backendURL.appendingPathComponent(MealPhotoAnalysisEndpoint.path),
            timeoutInterval: 90
        )
        urlRequest.httpMethod = MealPhotoAnalysisEndpoint.method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await send(urlRequest)
        } catch {
            throw MealAnalysisGatewayError.analysisUnavailable
        }

        guard response.statusCode == 200 else {
            let failure = try? JSONDecoder().decode(AnalysisErrorResponse.self, from: data)
            throw failure?.code == .malformedProviderOutput
                ? MealAnalysisGatewayError.malformedAnalysis
                : MealAnalysisGatewayError.analysisUnavailable
        }
        do {
            return try JSONDecoder().decode(MealPhotoAnalysisResponse.self, from: data)
        } catch {
            throw MealAnalysisGatewayError.malformedAnalysis
        }
    }
}
