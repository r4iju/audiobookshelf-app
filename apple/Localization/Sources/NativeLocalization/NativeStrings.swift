import Foundation

/// The meaning of English wording that names more than one thing, so a language can translate each one differently. Such
/// text is keyed `<context>::<English>` in the tables; the English table maps the key back to the plain wording, so English
/// display and accessibility labels are unchanged. `generate.py` reads these cases.
public enum NativeTextContext: String, CaseIterable, Sendable {
    /// A color theme, for the app or the reader.
    case theme
    /// A haptic feedback strength.
    case hapticStrength

    public func key(_ english: String) -> String { rawValue + "::" + english }
}

/// Looks up native text by its English wording. `apple/Localization/generate.py` writes the tables, carrying a legacy
/// translation where its meaning matches, then a maintained native translation, with English as the fallback. The table name keeps SwiftUI's own
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
        Self.substitute(table[english] ?? english, arguments)
    }

    /// The same lookup for arguments gathered elsewhere, such as the shared core's text.
    public func callAsFunction(_ english: String, arguments: [CustomStringConvertible]) -> String {
        Self.substitute(table[english] ?? english, arguments)
    }

    /// Text whose English wording is shared by several meanings, translated for the one named. Without a translation
    /// for that meaning it stays English, never borrowing another meaning's translation.
    public func callAsFunction(_ english: String, context: NativeTextContext, _ arguments: CustomStringConvertible...) -> String {
        Self.substitute(table[context.key(english)] ?? english, arguments)
    }

    private static func substitute(_ template: String, _ arguments: [CustomStringConvertible]) -> String {
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

    /// The share as whole percent for display, rounded down so only a complete language reads 100%.
    public static func translatedPercent(translated: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        return translated * 100 / total
    }

    /// The share of native text this language translates, so the language list can disclose partial coverage.
    public var translatedPercent: Int {
        guard language != .english else { return 100 }
        return Self.translatedPercent(translated: table.count, of: Self.table(NativeLanguage.english.localization, bundle: bundle).count)
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
