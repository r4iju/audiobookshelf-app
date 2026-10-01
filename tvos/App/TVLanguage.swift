import SwiftUI

/// The interface language: a saved legacy language code under the shared native key, or the TV's languages when none is saved.
@MainActor final class TVLanguage: ObservableObject {
    static let shared = TVLanguage()
    @Published private(set) var strings = NativeStrings.current

    var saved: String? { UserDefaults.standard.string(forKey: NativeStrings.savedKey) }

    func choose(_ code: String?) {
        if let code { UserDefaults.standard.set(code, forKey: NativeStrings.savedKey) }
        else { UserDefaults.standard.removeObject(forKey: NativeStrings.savedKey) }
        strings = NativeStrings.current
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

private struct TVLocalization: ViewModifier {
    @ObservedObject private var language = TVLanguage.shared

    func body(content: Content) -> some View {
        let chosen = language.strings.language
        return content
            .environment(\.nativeStrings, language.strings)
            .environment(\.locale, chosen.locale)
            .environment(\.layoutDirection, chosen.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}

extension View {
    /// The chosen language, its locale and reading direction. Sheets are separate roots and apply it again.
    func tvLocalization() -> some View { modifier(TVLocalization()) }
}

/// Screens pushed from Settings or sign-in, and the link that opened each.
enum ReturnFocus: Hashable { case language, diagnostics }

extension View {
    /// Back puts focus on the link that opened the screen. tvOS otherwise leaves nothing focused when the screen behind was
    /// rebuilt meanwhile, as a language change does.
    func restoresFocus(path: [ReturnFocus], to focus: FocusState<ReturnFocus?>.Binding) -> some View {
        onChange(of: path) { previous, current in
            guard current.count < previous.count, let link = previous.last else { return }
            Task { @MainActor in focus.wrappedValue = link }
        }
    }
}

struct LanguageView: View {
    @ObservedObject private var language = TVLanguage.shared
    @Environment(\.nativeStrings) private var l10n

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(l10n("Language")).font(.title2.bold())
                Text(l10n("Apple TV screens show these translations where the earlier app had an equivalent. Other text, and system screens, stay in English or follow the Apple TV language."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("language-note")
                row(l10n("System default"), detail: NativeLanguage.resolve(saved: nil, preferred: Locale.preferredLanguages).name,
                    selected: language.saved == nil, identifier: "language-system") { language.choose(nil) }
                ForEach(NativeLanguage.all) { option in
                    row(option.name, detail: nil, selected: language.saved == option.code, identifier: "language-" + option.code) { language.choose(option.code) }
                }
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 50)
            .frame(maxWidth: 1400, alignment: .leading)
        }
    }

    private func row(_ title: String, detail: String?, selected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                if let detail { Text(detail).foregroundStyle(.secondary) }
                Spacer()
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
        }
        .accessibilityIdentifier(identifier)
        .accessibilityValue(l10n(selected ? "Selected" : "Not selected"))
    }
}
