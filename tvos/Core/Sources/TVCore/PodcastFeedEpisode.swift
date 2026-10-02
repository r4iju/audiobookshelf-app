import Foundation

public struct PodcastFeedEpisode: Codable, Identifiable {
    // Return the server's full RSS object when queueing, including enclosure,
    // GUID and chapter fields that are not presented by this screen.
    private let payload: FeedValue
    public var enclosureURL: String? { payload["enclosure"]?["url"]?.string }
    public var title: String { payload["title"]?.string ?? "Untitled episode" }
    public var id: String { enclosureURL ?? payload["guid"]?.string ?? title }
    public init(from decoder: Decoder) throws { payload = try FeedValue(from: decoder) }
    public func encode(to encoder: Encoder) throws { try payload.encode(to: encoder) }
}

private enum FeedValue: Codable {
    case object([String: FeedValue]), array([FeedValue]), string(String), number(Double), bool(Bool), null
    subscript(_ key: String) -> FeedValue? {
        if case .object(let value) = self { return value[key] }
        return nil
    }
    var string: String? { if case .string(let value) = self { return value }; return nil }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let decoded = try? value.decode(Bool.self) { self = .bool(decoded) }
        else if let decoded = try? value.decode(String.self) { self = .string(decoded) }
        else if let decoded = try? value.decode(Double.self) { self = .number(decoded) }
        else if let decoded = try? value.decode([String: FeedValue].self) { self = .object(decoded) }
        else { self = .array(try value.decode([FeedValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .string(let string): try value.encode(string)
        case .number(let number): try value.encode(number)
        case .bool(let bool): try value.encode(bool)
        case .null: try value.encodeNil()
        }
    }
}
