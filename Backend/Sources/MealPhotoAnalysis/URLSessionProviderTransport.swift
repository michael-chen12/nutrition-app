import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends provider requests with URLSession. Used by the server; tests substitute a recording transport.
public struct URLSessionProviderTransport: ProviderTransport, @unchecked Sendable {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(session: URLSession = .shared, timeout: TimeInterval = 60) {
        self.session = session
        self.timeout = timeout
    }

    public func send(_ request: ProviderRequest) async throws -> ProviderResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = request.body
        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return ProviderResponse(statusCode: httpResponse.statusCode, body: data)
    }
}
