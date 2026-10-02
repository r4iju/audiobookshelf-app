import Foundation

/// Text the shared core shows people, such as failure descriptions. The core has no string tables, so it keeps English
/// for its own tests and logs; each app installs its tables at launch, and the same text then reads in the chosen language
/// wherever it is shown. Templates use `{0}`, `{1}` placeholders, as the apps' tables do.
public enum CoreText {
    public typealias Lookup = @Sendable (_ english: String, _ arguments: [String]) -> String

    public static let english: Lookup = { template, arguments in
        var text = template
        for (index, argument) in arguments.enumerated().reversed() { text = text.replacingOccurrences(of: "{\(index)}", with: argument) }
        return text
    }

    nonisolated(unsafe) public static var lookup: Lookup = english

    public static func text(_ english: String, _ arguments: CustomStringConvertible...) -> String {
        lookup(english, arguments.map(\.description))
    }
}
