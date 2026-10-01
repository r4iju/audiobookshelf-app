import SwiftUI

enum NativeAppearance: String, CaseIterable {
    case system, light, dark, black
    var name: String { rawValue.capitalized }
    var scheme: ColorScheme? { self == .system ? nil : self == .light ? .light : .dark }
    var background: Color { self == .black ? .black : Color(UIColor.systemGroupedBackground) }
    var card: Color { self == .black ? Color(white: 0.09) : Color(UIColor.secondarySystemGroupedBackground) }
}
private struct NativeAppearanceKey: EnvironmentKey { static let defaultValue = NativeAppearance.system }
extension EnvironmentValues {
    var shelfAppearance: NativeAppearance {
        get { self[NativeAppearanceKey.self] }
        set { self[NativeAppearanceKey.self] = newValue }
    }
}

private struct ShelfScrollSurface: ViewModifier {
    @Environment(\.shelfAppearance) private var appearance
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.scrollContentBackground(.hidden).background(appearance.background)
        } else { content.background(appearance.background) }
    }
}
struct ShelfList<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { List { content }.modifier(ShelfScrollSurface()) }
}
struct ShelfForm<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { Form { content }.modifier(ShelfScrollSurface()) }
}

enum NativeHaptic: String, CaseIterable {
    case off, light, medium, heavy
    var name: String { rawValue.capitalized }
    var style: UIImpactFeedbackGenerator.FeedbackStyle? {
        switch self { case .off: return nil; case .light: return .light; case .medium: return .medium; case .heavy: return .heavy }
    }
    @MainActor static func impact() {
        let setting = NativeHaptic(rawValue: UserDefaults.standard.string(forKey: "previewHaptic") ?? "light") ?? .light
        guard let style = setting.style else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

struct NativeSettings: View {
    @AppStorage("previewTheme") private var theme = "system"
    @AppStorage("previewHaptic") private var haptic = "light"
    var body: some View {
        ShelfList {
            Section(header: Text("Appearance")) {
                ForEach(NativeAppearance.allCases, id: \.self) { choice in
                    option(choice.name, selected: theme == choice.rawValue, id: "theme-" + choice.rawValue) {
                        theme = choice.rawValue; NativeHaptic.impact()
                    }
                }
            }
            Section(header: Text("Haptic feedback"), footer: Text("Choose the feedback for playback controls and library actions.")) {
                ForEach(NativeHaptic.allCases, id: \.self) { choice in
                    option(choice.name, selected: haptic == choice.rawValue, id: "haptic-" + choice.rawValue) {
                        haptic = choice.rawValue; NativeHaptic.impact()
                    }
                }
            }
        }.listStyle(InsetGroupedListStyle()).navigationTitle("Settings")
    }
    private func option(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title).foregroundColor(.primary); Spacer(); if selected { Image(systemName: "checkmark").foregroundColor(ShelfStyle.accent) } }
        }.accessibilityIdentifier(id).accessibilityValue(selected ? "Selected" : "Not selected")
    }
}
