import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = LockViewController()
        window?.makeKeyAndVisible()
        return true
    }

    /// 锁屏成功后 App 会被挂起；这里主动退出，解锁后直接回到桌面，
    /// 而不是回到这个一次性工具 App 的界面。
    func applicationDidEnterBackground(_ application: UIApplication) {
        exit(EXIT_SUCCESS)
    }
}
