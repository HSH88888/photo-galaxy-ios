import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.backgroundColor = UIColor(red: 13/255, green: 13/255, blue: 23/255, alpha: 1.0)
        win.rootViewController = MainViewController()
        win.makeKeyAndVisible()
        self.window = win
        return true
    }
}
