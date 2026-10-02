import Foundation

/// A language the legacy app offered. `code` is the legacy `languageCode`, so saved and migrated choices share one domain;
/// `localization` names the `.lproj` resources.
public struct NativeLanguage: Hashable, Identifiable {
    public let code: String
    public let name: String
    public let localization: String
    public var id: String { code }
    public var isRightToLeft: Bool { ["ar", "he"].contains(code) }
    public var locale: Locale { Locale(identifier: localization) }

    public static let english = NativeLanguage(code: "en-us", name: "English", localization: "en")
    public static let all: [NativeLanguage] = [
        .init(code: "ar", name: "عربي", localization: "ar"),
        .init(code: "be", name: "Беларуская", localization: "be"),
        .init(code: "bg", name: "Български", localization: "bg"),
        .init(code: "bn", name: "বাংলা", localization: "bn"),
        .init(code: "ca", name: "Català", localization: "ca"),
        .init(code: "cs", name: "Čeština", localization: "cs"),
        .init(code: "da", name: "Dansk", localization: "da"),
        .init(code: "de", name: "Deutsch", localization: "de"),
        english,
        .init(code: "es", name: "Español", localization: "es"),
        .init(code: "fi", name: "Suomi", localization: "fi"),
        .init(code: "fr", name: "Français", localization: "fr"),
        .init(code: "he", name: "עברית", localization: "he"),
        .init(code: "hr", name: "Hrvatski", localization: "hr"),
        .init(code: "it", name: "Italiano", localization: "it"),
        .init(code: "lt", name: "Lietuvių", localization: "lt"),
        .init(code: "hu", name: "Magyar", localization: "hu"),
        .init(code: "ko", name: "한국어", localization: "ko"),
        .init(code: "nl", name: "Nederlands", localization: "nl"),
        .init(code: "no", name: "Norsk", localization: "nb"),
        .init(code: "pl", name: "Polski", localization: "pl"),
        .init(code: "pt-br", name: "Português (Brasil)", localization: "pt-BR"),
        .init(code: "ru", name: "Русский", localization: "ru"),
        .init(code: "sk", name: "Slovenčina", localization: "sk"),
        .init(code: "sl", name: "Slovenščina", localization: "sl"),
        .init(code: "sv", name: "Svenska", localization: "sv"),
        .init(code: "tr", name: "Türkçe", localization: "tr"),
        .init(code: "uk", name: "Українська", localization: "uk"),
        .init(code: "vi-vn", name: "Tiếng Việt", localization: "vi"),
        .init(code: "zh-cn", name: "简体中文 (Simplified Chinese)", localization: "zh-Hans")
    ]

    /// The saved choice, or the device languages when nothing is saved.
    public static var current: NativeLanguage {
        resolve(saved: UserDefaults.standard.string(forKey: NativeStrings.savedKey), preferred: Locale.preferredLanguages)
    }

    /// For migration: keeps the legacy `languageCode` unless the native app already has a choice. `en-us` is kept too:
    /// the legacy app showed English for it whatever the device language, and its export cannot tell a default from a choice.
    @discardableResult public static func adoptLegacy(_ code: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let language = named(code), defaults.string(forKey: NativeStrings.savedKey) == nil else { return false }
        defaults.set(language.code, forKey: NativeStrings.savedKey)
        return true
    }

    public static func named(_ code: String?) -> NativeLanguage? { all.first { $0.code == code } }

    /// A saved legacy choice wins; otherwise the first supported device language, then the legacy English default.
    public static func resolve(saved: String?, preferred: [String]) -> NativeLanguage {
        if let chosen = named(saved) { return chosen }
        for identifier in preferred {
            if let match = match(identifier) { return match }
        }
        return english
    }

    private static func match(_ identifier: String) -> NativeLanguage? {
        let parts = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").map(String.init)
        guard let language = parts.first else { return nil }
        switch language {
        case "zh":
            let traditional = parts.contains("hant") || (!parts.contains("hans") && parts.contains { ["tw", "hk", "mo"].contains($0) })
            return traditional ? nil : named("zh-cn")
        case "pt": return named("pt-br")
        case "nb", "nn", "no": return named("no")
        case "en": return english
        case "vi": return named("vi-vn")
        case "iw": return named("he")
        default: return named(language)
        }
    }
}
