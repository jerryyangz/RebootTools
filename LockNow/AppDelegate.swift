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

    // 与真机验证成功的 RespringNow 保持完全一致：
    // 不实现任何后台回调，App 绝不自动退出。
}
