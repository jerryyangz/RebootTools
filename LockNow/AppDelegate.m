#import "AppDelegate.h"
#import "LockViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[LockViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

// 与真机验证成功的「锁屏诊断」保持完全一致：
// 不实现任何后台回调，App 绝不自动退出。

@end
