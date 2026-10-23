import AnalysisContract
import AUSNUT
import FoodDataCentral
import Foundation

/// USDA FoodData Central settings read from the backend's environment.
///
/// Get a key at https://fdc.nal.usda.gov/api-key-signup (api.data.gov); re-verify its rate limits there.
public struct FoodDataCentralConfiguration: Sendable {
    public static let defaultBaseURL = URL(string: "https://api.nal.usda.gov/fdc/v1")!

    /// From `FDC_API_KEY`; nil when unset or blank, in which case food search answers `notConfigured`.
    public var credential: ProviderCredential?
    public var baseURL: URL

    public init(credential: ProviderCredential?, baseURL: URL = defaultBaseURL) {
        self.credential = credential
        self.baseURL = baseURL
    }

    public init(environment: [String: String]) {
        self.init(credential: environment["FDC_API_KEY"].flatMap(ProviderCredential.init(apiKey:)))
    }
}

/// The backend's food search endpoint, independent of any HTTP server framework: it takes the body the app
/// posted to `FoodSearchEndpoint.path` and returns the reply to send back.
///
/// It searches two documented sources (ADR 0003):
/// - FoodData Central: it searches, then fetches the full records of the hits (search results carry no
///   household measures) and normalizes them with the shared `FoodDataCentralRecord` adapter, keeping the
///   search's relevance order.
/// - The packaged AUSNUT 2023 data (`AUSNUTDataset`), which covers mixed dishes FDC lacks (ticket #13).
///
/// The reply alternates between the two sources' results, FDC first, so overlapping foods appear side by side
/// with their source names and either source's best matches reach the top. FDC failures still fail the whole
/// search, as before. Every reply is JSON in the shared contract: a `FoodSearchResponse` (200) or an
/// `AnalysisErrorResponse`. The key is sent only in the `X-Api-Key` request header; FDC replies and transport
/// errors are never forwarded, so the key cannot leak to the app.
public struct FoodSearchService: Sendable {
    /// Most foods returned for one search, and asked of each source.
    public static let maximumResults = 10
    /// Longest query accepted, in characters.
    public static let maximumQueryLength = 100
    /// FDC data types searched: generic foods with documented portion weights. Branded foods are left out for
    /// now; their nutrients may be per 100 mL and they rarely document household measures.
    static let dataTypes = ["Foundation", "SR Legacy", "Survey (FNDDS)"]

    private let credential: ProviderCredential?
    private let baseURL: URL
    private let transport: ProviderTransport
    private let ausnut: AUSNUTDataset

    public init(
        credential: ProviderCredential?,
        baseURL: URL = FoodDataCentralConfiguration.defaultBaseURL,
        transport: ProviderTransport,
        ausnut: AUSNUTDataset
    ) {
        self.credential = credential
        self.baseURL = baseURL
        self.transport = transport
        self.ausnut = ausnut
    }

    public init(configuration: FoodDataCentralConfiguration, transport: ProviderTransport, ausnut: AUSNUTDataset) {
        self.init(
            credential: configuration.credential, baseURL: configuration.baseURL, transport: transport, ausnut: ausnut
        )
    }

    public func handle(requestBody: Data) async -> AnalysisHTTPResponse {
        guard let request = try? JSONDecoder().decode(FoodSearchRequest.self, from: requestBody) else {
            return .failure(400, .invalidRequest, "The food search could not be read.")
        }
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .failure(400, .invalidRequest, "Enter a food to search for.") }
        guard query.count <= Self.maximumQueryLength else {
            return .failure(400, .invalidRequest, "Use a shorter food search.")
        }
        guard let credential else {
            return .failure(503, .notConfigured, "Food search is not set up on the server.")
        }

        do {
            let fdcFoods = try await fdcFoods(matching: query, credential: credential)
            let ausnutFoods = ausnut.search(query, limit: Self.maximumResults)
            let foods = Self.alternating(fdcFoods, ausnutFoods).prefix(Self.maximumResults)
            return .success(FoodSearchResponse(foods: Array(foods)))
        } catch let failure as SourceFailure {
            return failure.reply
        } catch {
            return .foodSourceUnavailable
        }
    }

    /// FDC's suitable foods for the query in its relevance order, with their full records' serving units.
    private func fdcFoods(matching query: String, credential: ProviderCredential) async throws -> [DocumentedFood] {
        let hits = try await post(
            SearchBody(query: query, dataType: Self.dataTypes, pageSize: Self.maximumResults),
            to: "foods/search", credential: credential, decoding: FoodDataCentralSearchResponse.self
        )
        let fdcIDs = hits.foods.map(\.fdcId).uniqued()
        guard !fdcIDs.isEmpty else { return [] }

        let records = try await post(
            FoodsBody(fdcIds: fdcIDs, format: "full"),
            to: "foods", credential: credential, decoding: FoodDataCentralRecordList.self
        )
        let foodsByID = Dictionary(
            records.suitableFoods().map { ($0.recordID, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return fdcIDs.compactMap { foodsByID[String($0)] }
    }

    /// `first[0], second[0], first[1], second[1], ...`, then the rest of the longer list.
    private static func alternating(_ first: [DocumentedFood], _ second: [DocumentedFood]) -> [DocumentedFood] {
        (0..<max(first.count, second.count)).flatMap { index in
            [first, second].compactMap { index < $0.count ? $0[index] : nil }
        }
    }

    /// Why a call to the source produced no usable reply, as the reply to send the app.
    private struct SourceFailure: Error {
        var reply: AnalysisHTTPResponse
    }

    private func post<Reply: Decodable>(
        _ body: some Encodable,
        to path: String,
        credential: ProviderCredential,
        decoding: Reply.Type
    ) async throws -> Reply {
        let response: ProviderResponse
        do {
            response = try await transport.send(ProviderRequest(
                url: baseURL.appendingPathComponent(path),
                method: "POST",
                // The key goes only in this header: never in the URL, where proxies and logs keep it.
                headers: ["Content-Type": "application/json", "X-Api-Key": credential.apiKey],
                body: try JSONEncoder().encode(body)
            ))
        } catch {
            throw SourceFailure(reply: .foodSourceUnavailable)
        }
        guard (200..<300).contains(response.statusCode) else { throw SourceFailure(reply: .foodSourceUnavailable) }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: response.body) else {
            throw SourceFailure(reply: .failure(
                502, .malformedProviderOutput, "The food data source returned results that could not be used."
            ))
        }
        return reply
    }

    private struct SearchBody: Encodable {
        var query: String
        var dataType: [String]
        var pageSize: Int
    }

    private struct FoodsBody: Encodable {
        var fdcIds: [Int]
        var format: String
    }
}

extension AnalysisHTTPResponse {
    static func success(_ response: FoodSearchResponse) -> AnalysisHTTPResponse {
        AnalysisHTTPResponse(statusCode: 200, contentType: "application/json", body: try! encoder.encode(response))
    }

    static let foodSourceUnavailable = failure(502, .providerUnavailable, "Food search is unavailable right now.")
}
