import UIKit

/// Reduced to the scene-configuration hook now that window/root-view-controller
/// setup lives in `SceneDelegate`, per the `UIScene` lifecycle adopted via
/// `Host/Info.plist`'s `UIApplicationSceneManifest`.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                      configurationForConnecting connectingSceneSession: UISceneSession,
                      options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
