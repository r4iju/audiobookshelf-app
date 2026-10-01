#if os(iOS)
import UIKit

// Consent belongs to a session or durable download, never a global one-time grant.
enum AppleNetworkPolicy: String, CaseIterable {
    case ask, always, never
    static let streamingKey = "previewStreamingNetwork"
    static let downloadsKey = "previewDownloadsNetwork"
    static let changed = Notification.Name("NativeNetworkPolicyChanged")
    var title: String { rawValue.capitalized }
    static func read(_ key: String) -> Self {
        if let value = UserDefaults.standard.string(forKey: key), let policy = Self(rawValue: value) { return policy }
        if key == downloadsKey { return UserDefaults.standard.bool(forKey: "previewDownloadCellular") ? .always : .never }
        return .always
    }
    @MainActor static func request(_ key: String, title: String) async -> Bool {
        switch read(key) {
        case .always: return true
        case .never: return false
        case .ask:
            guard UIApplication.shared.applicationState == .active,
                  let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow),
                  var presenter = window.rootViewController else { return false }
            while let presented = presenter.presentedViewController { presenter = presented }
            guard !(presenter is UIAlertController), !presenter.isBeingDismissed else { return false }
            return await withCheckedContinuation { continuation in
                let alert = UIAlertController(title: "Use cellular data?", message: "Allow cellular data for \(title), including if Wi-Fi disconnects? Wi-Fi only will wait for Wi-Fi when needed.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Wi-Fi only", style: .cancel) { _ in continuation.resume(returning: false) })
                alert.addAction(UIAlertAction(title: "Allow cellular", style: .default) { _ in continuation.resume(returning: true) })
                presenter.present(alert, animated: true)
            }
        }
    }
}
#endif
