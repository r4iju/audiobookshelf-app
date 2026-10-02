import UIKit
import Capacitor

/// The single window scene. UIKit loads `Main.storyboard` into `window` (see the scene manifest in
/// Info.plist); URLs and activities arrive here instead of the app delegate, so they are handed to
/// Capacitor exactly as `AppDelegate` did before scenes.
class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        (UIApplication.shared.delegate as? AppDelegate)?.window = window
        openURLContexts(connectionOptions.urlContexts)
        for activity in connectionOptions.userActivities {
            _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, continue: activity, restorationHandler: { _ in })
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        openURLContexts(URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, continue: userActivity, restorationHandler: { _ in })
    }

    func sceneWillResignActive(_ scene: UIScene) {
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        AbsLogger.info(message: "Audiobookself is now in the background")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        AbsLogger.info(message: "Audiobookself is now in the foreground")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        AbsLogger.info(message: "Audiobookself is now active")
    }

    private func openURLContexts(_ contexts: Set<UIOpenURLContext>) {
        for context in contexts {
            var options: [UIApplication.OpenURLOptionsKey: Any] = [.openInPlace: context.options.openInPlace]
            options[.sourceApplication] = context.options.sourceApplication
            options[.annotation] = context.options.annotation
            _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, open: context.url, options: options)
        }
    }
}
