#import <Foundation/Foundation.h>

@interface DeviceController : NSObject

/// 只通过公开的 Darwin 通知 API 请求锁屏。
/// 不 dlopen 任何私有框架，也不调用任何未验证签名的私有符号。
- (BOOL)lockScreen;

/// 读取 com.apple.springboard.lockstate 的当前状态描述。
- (NSString *)currentLockState;

/// 逐步调用结果，锁屏未生效时显示给用户用于定位。
- (NSString *)diagnostics;

@end

/// 安装崩溃哨兵，必须在 didFinishLaunchingWithOptions 的第一行调用。
/// 捕获 SIGSEGV / SIGBUS / SIGABRT / SIGILL / SIGFPE，把崩溃时所处的阶段
/// 写入 Documents/locknow-crash.log，然后恢复默认处理让系统照常生成 .ips。
void LNInstallCrashGuard(void);

/// 读出并清空上一次的崩溃记录；没有记录返回 nil。
/// 下次启动发现记录时会进入「安全模式」，不再自动执行锁屏，避免连续闪退。
NSString *LNLastCrashReport(void);
