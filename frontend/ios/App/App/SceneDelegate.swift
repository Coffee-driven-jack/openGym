import UIKit
import Capacitor

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    // The window and root view controller are created automatically from
    // Main.storyboard via the UISceneStoryboardFile key in Info.plist.
    // These callbacks just forward deep links / Universal Links to Capacitor,
    // since AppDelegate's equivalents are not called under the scene lifecycle.

    // A cold start by a link (the Live Activity's tap: <bundle id>://workout?idx=…) hands the URL
    // here rather than to openURLContexts; Capacitor keeps it for App.getLaunchUrl().
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let url = connectionOptions.urlContexts.first?.url else { return }
        _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, open: url, options: [:])
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, open: url, options: [:])
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        _ = ApplicationDelegateProxy.shared.application(UIApplication.shared, continue: userActivity) { _ in }
    }
}
