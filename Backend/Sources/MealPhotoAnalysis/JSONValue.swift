import Foundation

/// A JSON value, used to write the provider's response schema.
enum JSONValue: Encodable, Hashable, Sendable, ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
    ExpressibleByDictionaryLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    init(stringLiteral value: String) { self = .string(value) }
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
    init(booleanLiteral value: Bool) { self = .bool(value) }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
