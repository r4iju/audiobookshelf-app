import SwiftUI
import UIKit

/// The interface language: a saved legacy `languageCode`, or the device languages when nothing is saved.
@MainActor final class NativeLanguageSetting: ObservableObject {
    static let shared = NativeLanguageSetting()
    @Published private(set) var strings: NativeStrings
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        NativePresentationReset.applyOnce()
        strings = NativeStrings.current
        Self.mirrorUIKit(strings.language)
    }

    var saved: String? { defaults.string(forKey: NativeStrings.savedKey) }

    func choose(_ code: String?) {
        if let code { defaults.set(code, forKey: NativeStrings.savedKey) } else { defaults.removeObject(forKey: NativeStrings.savedKey) }
        strings = NativeStrings.current
        Self.mirrorUIKit(strings.language)
    }

    /// UIKit chrome created after a change, such as navigation bars and share sheets, follows the chosen direction.
    private static func mirrorUIKit(_ language: NativeLanguage) {
        UIView.appearance().semanticContentAttribute = language.isRightToLeft ? .forceRightToLeft : .forceLeftToRight
    }
}

/// Simulator journeys reset presentation state alongside the account reset in the app root.
enum NativePresentationReset {
    private static var applied = false
    static func applyOnce() {
        guard !applied else { return }
        applied = true
        #if DEBUG && targetEnvironment(simulator)
        if CommandLine.arguments.contains("--reset-preview-account") {
            UserDefaults.standard.removeObject(forKey: NativeStrings.savedKey)
            try? FileManager.default.removeItem(at: NativeDiagnostics.file)
        }
        #endif
    }
}

private struct NativeStringsKey: EnvironmentKey {
    static var defaultValue: NativeStrings { NativeStrings.current }
}
extension EnvironmentValues {
    var nativeStrings: NativeStrings {
        get { self[NativeStringsKey.self] }
        set { self[NativeStringsKey.self] = newValue }
    }
}

private struct NativeLocalizationModifier: ViewModifier {
    @ObservedObject private var setting = NativeLanguageSetting.shared
    func body(content: Content) -> some View {
        let language = setting.strings.language
        return content.environment(\.nativeStrings, setting.strings)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}
extension View {
    /// Applies the chosen language, its locale and its reading direction to native views, including presented sheets.
    func nativeLocalization() -> some View { modifier(NativeLocalizationModifier()) }
}

struct NativeLanguageSettings: View {
    @ObservedObject private var setting = NativeLanguageSetting.shared
    @Environment(\.nativeStrings) private var l10n
    var body: some View {
        ShelfList {
            Section(footer: Text(l10n("Some text appears in English when a translation is unavailable. System screens and controls follow your device language.")).foregroundColor(ShelfStyle.secondaryText).accessibilityIdentifier("language-coverage-note")) {
                row(l10n("System default"), detail: NativeLanguage.resolve(saved: nil, preferred: Locale.preferredLanguages).name, selected: setting.saved == nil, id: "language-system") { setting.choose(nil) }
            }
            Section {
                ForEach(NativeLanguage.all) { language in
                    row(language.name, detail: coverage(language), selected: setting.saved == language.code, id: "language-" + language.code) { setting.choose(language.code) }
                }
            }
        }.listStyle(InsetGroupedListStyle()).navigationTitle(l10n("Language"))
    }
    private func coverage(_ language: NativeLanguage) -> String? {
        guard language != .english else { return nil }
        return l10n("{0}% translated", NativeStrings(language: language).translatedPercent)
    }
    private func row(_ title: String, detail: String?, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button { NativeHaptic.impact("settings"); action() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundColor(.primary)
                    if let detail { Text(detail).font(.caption).foregroundColor(ShelfStyle.secondaryText) }
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundColor(ShelfStyle.accent).accessibilityIdentifier("language-selected-mark") }
            }
        }.accessibilityIdentifier(id).accessibilityValue(l10n(selected ? "Selected" : "Not selected"))
    }
}
