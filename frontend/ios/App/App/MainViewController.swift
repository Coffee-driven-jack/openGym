import UIKit
import Capacitor

// The app's own plugins. Capacitor registers only the npm plugins listed in the generated
// capacitor.config.json (packageClassList), so the ones that live in this folder are handed to
// the bridge here. Main.storyboard names this class as its root view controller.
class MainViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(PrintPlugin())
        bridge?.registerPluginInstance(RestAlertPlugin())
    }
}
