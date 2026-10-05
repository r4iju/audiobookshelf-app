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
    /// `action` names the legacy haptic call site; simulator journeys observe it because the simulator cannot vibrate.
    @MainActor static func impact(_ action: String) {
        let setting = NativeHaptic(rawValue: UserDefaults.standard.string(forKey: "previewHaptic") ?? "light") ?? .light
        guard let style = setting.style else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #if DEBUG && targetEnvironment(simulator)
        HapticProbe.observe(action + ":" + setting.rawValue)
        #endif
    }
}

#if DEBUG && targetEnvironment(simulator)
/// A passthrough window above every presentation so one probe label is visible to UI journeys run with `--observe-haptics`.
@MainActor private enum HapticProbe {
    private static var window: UIWindow?
    private static var count = 0
    static func observe(_ impact: String) {
        guard CommandLine.arguments.contains("--observe-haptics") else { return }
        count += 1
        if window == nil, let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let probe = UIWindow(windowScene: scene)
            probe.frame = CGRect(x: 0, y: scene.coordinateSpace.bounds.height - 14, width: 220, height: 14)
            probe.windowLevel = .alert + 1
            probe.isUserInteractionEnabled = false
            let label = UILabel(frame: probe.bounds)
            label.font = .systemFont(ofSize: 9)
            label.textColor = .secondaryLabel
            label.accessibilityIdentifier = "haptic-observation"
            probe.addSubview(label)
            probe.isHidden = false
            window = probe
        }
        (window?.subviews.first as? UILabel)?.text = "\(impact) \(count)"
    }
}
#endif

struct NativeSettings: View {
    @AppStorage("previewTheme") private var theme = "system"
    @AppStorage("previewHaptic") private var haptic = "light"
    @Environment(\.nativeStrings) private var l10n
    var body: some View {
        ShelfList {
            Section {
                NavigationLink(destination: NativeLanguageSettings()) {
                    HStack { Text(l10n("Language")); Spacer(); Text(l10n.language.name).foregroundColor(ShelfStyle.secondaryText) }
                }.accessibilityIdentifier("language-settings")
            }
            Section(header: Text(l10n("Appearance")).foregroundColor(ShelfStyle.secondaryText)) {
                ForEach(NativeAppearance.allCases, id: \.self) { choice in
                    option(l10n(choice.name, context: .theme), selected: theme == choice.rawValue, id: "theme-" + choice.rawValue) {
                        theme = choice.rawValue; NativeHaptic.impact("settings")
                    }
                }
            }
            Section(header: Text(l10n("Haptic feedback")).foregroundColor(ShelfStyle.secondaryText), footer: Text(l10n("Choose the feedback for playback controls and library actions.")).foregroundColor(ShelfStyle.secondaryText)) {
                ForEach(NativeHaptic.allCases, id: \.self) { choice in
                    option(l10n(choice.name, context: .hapticStrength), selected: haptic == choice.rawValue, id: "haptic-" + choice.rawValue) {
                        haptic = choice.rawValue; NativeHaptic.impact("settings")
                    }
                }
            }
            Section {
                NavigationLink(l10n("Network preferences"), destination: NativeNetworkSettings())
                NavigationLink(l10n("Import previous app data"), destination: NativeMigrationImport())
                NavigationLink(l10n("Diagnostics"), destination: NativeDiagnosticsView()).accessibilityIdentifier("diagnostics-settings")
            }
            Section(header: Text("Audiobook Loft")) {
                Text("Audiobook Loft began as an independently maintained fork of the Audiobookshelf app. Its browser and backend have been rewritten. Upstream copyright and license notices are retained. It is not affiliated with or endorsed by the Audiobookshelf project.")
                Text("Open source under GPLv3, with applicable third-party licenses retained.")
                Link("Source and license notices", destination: URL(string: "https://github.com/r4iju/audiobookshelf-app/releases")!)
            }
        }.listStyle(InsetGroupedListStyle()).navigationTitle(l10n("Settings"))
    }
    private func option(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title).foregroundColor(.primary); Spacer(); if selected { Image(systemName: "checkmark").foregroundColor(ShelfStyle.accent) } }
        }.accessibilityIdentifier(id).accessibilityValue(l10n(selected ? "Selected" : "Not selected"))
    }
}

struct NativeNetworkSettings: View {
    @Environment(\.nativeStrings) private var l10n
    @State private var streaming = AppleNetworkPolicy.read(AppleNetworkPolicy.streamingKey)
    @State private var downloads = AppleNetworkPolicy.read(AppleNetworkPolicy.downloadsKey)
    var body: some View {
        ShelfList {
            choices(l10n("Streaming"), key: AppleNetworkPolicy.streamingKey, selected: $streaming, id: "streaming")
            choices(l10n("Downloads"), key: AppleNetworkPolicy.downloadsKey, selected: $downloads, id: "downloads")
        }.listStyle(InsetGroupedListStyle()).navigationTitle(l10n("Network preferences"))
    }
    private func choices(_ title: String, key: String, selected: Binding<AppleNetworkPolicy>, id: String) -> some View {
        Section(header: Text(title).foregroundColor(ShelfStyle.secondaryText), footer: Text(l10n("Ask requests permission for each new session or download. Never uses Wi-Fi only. Changing a choice pauses current streaming and resets download cellular permissions.")).foregroundColor(ShelfStyle.secondaryText)) {
            ForEach(AppleNetworkPolicy.allCases, id: \.self) { choice in
                Button {
                    NativeHaptic.impact("settings")
                    selected.wrappedValue = choice
                    UserDefaults.standard.set(choice.rawValue, forKey: key)
                    NotificationCenter.default.post(name: AppleNetworkPolicy.changed, object: key)
                } label: {
                    HStack { Text(l10n(choice.title)).foregroundColor(.primary); Spacer(); if selected.wrappedValue == choice { Image(systemName: "checkmark").foregroundColor(ShelfStyle.accent) } }
                }.accessibilityIdentifier(id + "-" + choice.rawValue).accessibilityValue(l10n(selected.wrappedValue == choice ? "Selected" : "Not selected"))
            }
        }
    }
}
