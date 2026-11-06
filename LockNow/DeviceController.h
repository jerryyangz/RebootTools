#import <Foundation/Foundation.h>

@interface DeviceController : NSObject

/// 请求系统锁屏：只调用签名确定的公开 Darwin API，不探测、不盲调任何私有符号。
/// @return YES 表示锁屏请求已发出；是否真正锁定请读 currentLockState / diagnostics。
- (BOOL)lockScreen;

/// 读取系统当前的锁屏状态描述，例如「未锁定 (0)」「已锁定 (1)」。
- (NSString *)currentLockState;

/// 每一步的调用结果与前后状态对比，锁屏未生效时展示给用户便于一次定位。
- (NSString *)diagnostics;

@end
