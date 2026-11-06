#import <Foundation/Foundation.h>

@interface DeviceController : NSObject

/// 依次尝试所有已知的锁屏入口（私有 C 符号 / SpringBoard 类 / 系统通知）。
/// @return YES 表示至少找到并调用了一个候选入口；不代表设备一定已经锁屏。
- (BOOL)lockScreen;

/// 每条路径的命中与调用情况，锁屏未生效时直接展示给用户，便于一次定位。
- (NSString *)diagnostics;

@end
