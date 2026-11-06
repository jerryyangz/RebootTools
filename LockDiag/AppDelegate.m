#import "AppDelegate.h"
#import "DiagViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[DiagViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

// 刻意不实现任何后台回调，App 绝不自动退出。

@end
