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
    @EnvironmentObject private var connection: ConnectionStore
    @AppStorage("previewTheme") private var theme = "system"
    @Environment(\.nativeStrings) private var l10n
    var body: some View {
        ShelfForm {
            Section(header: Text(l10n("Account"))) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(connection.username).font(.headline)
                    Text(connection.activeAccount?.server ?? connection.api.credentials?.server ?? connection.server)
                        .font(.caption).foregroundColor(ShelfStyle.secondaryText)
                }
                Button(l10n("Saved connections")) { connection.refreshSavedConnections(); connection.savedConnectionsPresented = true }
                Button(l10n("Sign out")) { NativeHaptic.impact("sign-out"); connection.signOut() }.accessibilityIdentifier("account-signout")
            }
            Section(header: Text(l10n("Listening"))) {
                NavigationLink(destination: NativeListeningSettings()) { Label(l10n("Playback preferences"), systemImage: "slider.horizontal.3") }.accessibilityIdentifier("listening-settings")
            }
            Section(header: Text(l10n("Reading"))) {
                NavigationLink(destination: NativeReadingSettings()) { Label(l10n("Reading preferences"), systemImage: "text.book.closed") }.accessibilityIdentifier("reading-settings")
            }
            Section(header: Text(l10n("Appearance"))) {
                NavigationLink(destination: NativeAppearanceSettings()) {
                    summary(l10n("Theme and feedback"), value: l10n((NativeAppearance(rawValue: theme) ?? .system).name, context: .theme))
                }.accessibilityIdentifier("appearance-settings")
                NavigationLink(destination: NativeLanguageSettings()) {
                    summary(l10n("Language"), value: l10n.language.name)
                }.accessibilityIdentifier("language-settings")
            }
            Section(header: Text(l10n("Utilities"))) {
                NavigationLink(destination: StatisticsView(api: connection.api)) { Label(l10n("Statistics"), systemImage: "chart.bar") }
                NavigationLink(destination: YearReviewView(api: connection.api)) { Label(l10n("Year in review"), systemImage: "calendar") }
                NavigationLink(destination: NativeNetworkSettings()) { Label(l10n("Network preferences"), systemImage: "network") }
                NavigationLink(destination: NativeDiagnosticsView()) { Label(l10n("Diagnostics"), systemImage: "stethoscope") }.accessibilityIdentifier("diagnostics-settings")
                NavigationLink(destination: NativeMigrationImport()) { Label(l10n("Import previous app data"), systemImage: "square.and.arrow.down") }
            }
            Section(header: Text(l10n("About"))) {
                NavigationLink(destination: NativeAboutSettings()) { Label(l10n("Source and license notices"), systemImage: "info.circle") }
            }
        }.navigationTitle(l10n("Settings")).navigationBarTitleDisplayMode(.inline)
    }
    private func summary(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(value).font(.caption).foregroundColor(ShelfStyle.secondaryText)
        }
    }
}

struct NativeAppearanceSettings: View {
    @AppStorage("previewTheme") private var theme = "system"
    @AppStorage("previewHaptic") private var haptic = "light"
    @Environment(\.nativeStrings) private var l10n
    var body: some View {
        ShelfForm {
            Section(header: Text(l10n("Appearance"))) {
                ForEach(NativeAppearance.allCases, id: \.self) { choice in
                    option(l10n(choice.name, context: .theme), selected: theme == choice.rawValue, id: "theme-" + choice.rawValue) {
                        theme = choice.rawValue; NativeHaptic.impact("settings")
                    }
                }
            }
            Section(header: Text(l10n("Haptic feedback")), footer: Text(l10n("Choose the feedback for playback controls and library actions."))) {
                ForEach(NativeHaptic.allCases, id: \.self) { choice in
                    option(l10n(choice.name, context: .hapticStrength), selected: haptic == choice.rawValue, id: "haptic-" + choice.rawValue) {
                        haptic = choice.rawValue; NativeHaptic.impact("settings")
                    }
                }
            }
        }.navigationTitle(l10n("Theme and feedback")).navigationBarTitleDisplayMode(.inline)
    }
    private func option(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title).foregroundColor(.primary); Spacer(); if selected { Image(systemName: "checkmark").foregroundColor(ShelfStyle.accent) } }
        }.accessibilityIdentifier(id).accessibilityValue(l10n(selected ? "Selected" : "Not selected"))
    }
}

struct NativeAboutSettings: View {
    @Environment(\.nativeStrings) private var l10n
    var body: some View {
        ShelfList {
            Section(header: Text("Audiobook Loft")) {
                Text(l10n("Audiobook Loft began as an independently maintained fork of the Audiobookshelf app. Its browser and backend have been rewritten. Upstream copyright and license notices are retained. It is not affiliated with or endorsed by the Audiobookshelf project."))
            }
            Section(header: Text(l10n("License"))) {
                Text(l10n("Open source under GPLv3, with applicable third-party licenses retained."))
                Link(l10n("Source and license notices"), destination: URL(string: "https://github.com/r4iju/audiobookshelf-app/releases")!)
            }
        }.navigationTitle(l10n("About")).navigationBarTitleDisplayMode(.inline)
    }
}

struct NativeNetworkSettings: View {
    @Environment(\.nativeStrings) private var l10n
    @State private var streaming = AppleNetworkPolicy.read(AppleNetworkPolicy.streamingKey)
    @State private var downloads = AppleNetworkPolicy.read(AppleNetworkPolicy.downloadsKey)
    var body: some View {
        ShelfForm {
            choices(l10n("Streaming"), key: AppleNetworkPolicy.streamingKey, selected: $streaming, id: "streaming")
            choices(l10n("Downloads"), key: AppleNetworkPolicy.downloadsKey, selected: $downloads, id: "downloads")
        }.navigationTitle(l10n("Network preferences")).navigationBarTitleDisplayMode(.inline)
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
