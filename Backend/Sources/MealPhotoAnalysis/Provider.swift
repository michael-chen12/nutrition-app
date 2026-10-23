import Foundation

/// The hosted provider's API key. It stays on the backend: it is sent only in the provider request's header,
/// and printing, logging or reflecting a credential never shows the key.
public struct ProviderCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let apiKey: String

    /// Returns nil for an empty or blank key.
    public init?(apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.apiKey = trimmed
    }

    public var description: String { "ProviderCredential(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

/// Gemini settings read from the backend's environment.
///
/// Re-verify in the Google AI Studio developer account before relying on them: the model name, its live
/// free-tier quota, and the unpaid-service terms (Google may use submitted content and responses to improve
/// products, possibly with human review). Use only non-sensitive test photos on the free tier.
public struct GeminiConfiguration: Sendable {
    public static let defaultModel = "gemini-2.5-flash"
    public static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    /// From `GEMINI_API_KEY`; nil when unset or blank, in which case the backend answers `notConfigured`.
    public var credential: ProviderCredential?
    /// From `GEMINI_MODEL`, defaulting to `defaultModel`.
    public var model: String
    public var baseURL: URL

    public init(credential: ProviderCredential?, model: String = defaultModel, baseURL: URL = defaultBaseURL) {
        self.credential = credential
        self.model = model
        self.baseURL = baseURL
    }

    public init(environment: [String: String]) {
        let model = environment["GEMINI_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            credential: environment["GEMINI_API_KEY"].flatMap(ProviderCredential.init(apiKey:)),
            model: model.flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultModel
        )
    }
}

/// An HTTP request to the hosted provider.
public struct ProviderRequest: Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data

    public init(url: URL, method: String, headers: [String: String], body: Data) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// The provider's HTTP reply.
public struct ProviderResponse: Sendable {
    public var statusCode: Int
    public var body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// Sends provider requests over the network. Tests substitute a recording transport with fixture replies.
public protocol ProviderTransport: Sendable {
    func send(_ request: ProviderRequest) async throws -> ProviderResponse
}
