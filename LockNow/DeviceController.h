#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DeviceController : NSObject

/// 通过 libSystem 的公开 Darwin 通知请求锁屏，并读取系统锁定状态。
/// 不加载私有框架，不调用任何未验证签名的符号。
- (BOOL)lockScreen;

/// 是否已锁定。返回 BOOL 可避免 Swift 桥接时的可选值歧义。
- (BOOL)isLocked;

/// 当前锁定状态的可读描述。
- (NSString *)currentLockState;

/// 逐条投递结果，供界面显示。
- (NSString *)diagnostics;

@end

NS_ASSUME_NONNULL_END
