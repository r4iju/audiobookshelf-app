import Foundation

/// Looks up native text by its English wording. `apple/Localization/generate.py` writes the tables, carrying a legacy
/// translation only where its meaning matches; anything else stays in English. The table name keeps SwiftUI's own
/// `Text` lookup from translating literals that were never reviewed.
public struct NativeStrings {
    public let language: NativeLanguage
    private let table: [String: String]
    private let bundle: Bundle

    /// The legacy `deviceSettings.languageCode` domain; absent means follow the device.
    public static let savedKey = "previewLanguage"
    public static let tableName = "NativeStrings"

    /// The language for code outside views, such as store messages, resolved the same way as the interface.
    public static var current: NativeStrings {
        NativeStrings(language: .current)
    }

    public init(language: NativeLanguage, bundle: Bundle = .main) {
        self.language = language
        self.bundle = bundle
        table = Self.table(language.localization, bundle: bundle)
    }

    public func callAsFunction(_ english: String, _ arguments: CustomStringConvertible...) -> String {
        let template = table[english] ?? english
        guard !arguments.isEmpty else { return template }
        // One pass, so a title that itself contains "{1}" is never substituted again.
        var text = ""
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            text += rest[..<open]
            if let close = rest[open...].firstIndex(of: "}"), let index = Int(rest[rest.index(after: open)..<close]), arguments.indices.contains(index) {
                text += arguments[index].description
                rest = rest[rest.index(after: close)...]
            } else {
                text.append("{")
                rest = rest[rest.index(after: open)...]
            }
        }
        return text + rest
    }

    /// An immutable copy of the translations for `english` templates, for renderers that must not depend on the app or
    /// its resources. Untranslated templates are left out so the renderer keeps its own English default.
    public func copy(_ english: [String]) -> [String: String] {
        guard language != .english else { return [:] }
        return english.reduce(into: [:]) { copy, key in if let value = table[key] { copy[key] = value } }
    }

    /// The share of native text carrying a legacy translation, so the language list can disclose partial coverage.
    public var translatedFraction: Double {
        guard language != .english else { return 1 }
        let english = Self.table(NativeLanguage.english.localization, bundle: bundle).count
        guard english > 0 else { return 0 }
        return Double(table.count) / Double(english)
    }

    public static func placeholders(in text: String) -> Set<String> {
        var found = Set<String>()
        var remaining = text[...]
        while let open = remaining.firstIndex(of: "{"), let close = remaining[open...].firstIndex(of: "}") {
            found.insert(String(remaining[open...close]))
            remaining = remaining[remaining.index(after: close)...]
        }
        return found
    }

    private static let lock = NSLock()
    private static var cache: [String: [String: String]] = [:]
    private static func table(_ localization: String, bundle: Bundle) -> [String: String] {
        let key = bundle.bundlePath + "|" + localization
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let url = bundle.url(forResource: tableName, withExtension: "strings", subdirectory: nil, localization: localization)
        let table = url.flatMap { NSDictionary(contentsOf: $0) as? [String: String] } ?? [:]
        cache[key] = table
        return table
    }
}
