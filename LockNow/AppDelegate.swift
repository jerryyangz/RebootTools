import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 崩溃哨兵必须最早安装，连启动期崩溃都能被记录。
        LNInstallCrashGuard()

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = LockViewController()
        window?.makeKeyAndVisible()
        return true
    }

    // 刻意不实现 applicationDidEnterBackground 里的 exit(0)。
    // 1.0.0 / 1.0.1 正是因为这个回调：锁屏通知只要让 App 短暂失焦，
    // 进程就立刻自杀，用户看到的就是「一点图标就闪退、屏幕也没灭」。
    // 真机验证成功的 RespringNow 并没有这个回调。
}
