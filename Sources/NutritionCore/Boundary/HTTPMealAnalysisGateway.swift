import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The app's `MealAnalysisGateway` over HTTP: photo analysis and food search both go to the backend
/// (Backend/), which holds the provider and nutrition source credentials, so no key ships with the app.
public final class HTTPMealAnalysisGateway: MealAnalysisGateway {
    public typealias Send = (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let backendURL: URL
    private let send: Send

    /// - Parameters:
    ///   - backendURL: The backend's base URL, e.g. `http://127.0.0.1:8080` during development.
    ///   - send: Performs the HTTP request; defaults to `URLSession.shared`.
    public init(backendURL: URL, send: Send? = nil) {
        self.backendURL = backendURL
        self.send = send ?? { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            return (data, httpResponse)
        }
    }

    /// Documented foods from the backend's food search, each with its source name, record ID and serving units.
    /// Throws `MealAnalysisGatewayError.foodSearchUnavailable` when the search cannot be completed.
    public func searchFoods(matching query: String) async throws -> [Food] {
        let urlRequest = try jsonRequest(
            path: FoodSearchEndpoint.path, method: FoodSearchEndpoint.method, body: FoodSearchRequest(query: query),
            timeout: 30
        )
        guard let (data, response) = try? await send(urlRequest), response.statusCode == 200,
              let reply = try? JSONDecoder().decode(FoodSearchResponse.self, from: data) else {
            throw MealAnalysisGatewayError.foodSearchUnavailable
        }
        return reply.foods.map(Food.init)
    }

    public func analyzeMealPhotos(_ request: MealPhotoAnalysisRequest) async throws -> MealPhotoAnalysisResponse {
        let urlRequest = try jsonRequest(
            path: MealPhotoAnalysisEndpoint.path, method: MealPhotoAnalysisEndpoint.method, body: request, timeout: 90
        )

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

    private func jsonRequest(
        path: String,
        method: String,
        body: some Encodable,
        timeout: TimeInterval
    ) throws -> URLRequest {
        var urlRequest = URLRequest(url: backendURL.appendingPathComponent(path), timeoutInterval: timeout)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }
}

extension Food {
    /// A documented food record from the backend, with its source reference and documented serving units.
    init(_ documented: DocumentedFood) {
        self.init(
            name: documented.name,
            nutrientsPer100g: NutrientsPer100g(
                calories: documented.nutrientsPer100g.calories,
                protein: documented.nutrientsPer100g.protein,
                carbohydrates: documented.nutrientsPer100g.carbohydrates,
                fat: documented.nutrientsPer100g.fat
            ),
            source: .documented(SourceReference(sourceName: documented.sourceName, recordID: documented.recordID)),
            servingUnits: documented.servingUnits.map {
                ServingUnit(name: $0.name, quantityBasis: $0.quantityBasis, gramWeight: $0.gramWeight)
            }
        )
    }
}
