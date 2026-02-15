import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    /// When `true`, the camera screen can rotate to landscape.
    /// All other screens stay portrait-locked.
    static var allowLandscape = false

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.allowLandscape ? .allButUpsideDown : .portrait
    }
}
