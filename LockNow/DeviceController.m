//  一键锁屏 1.0.1
//
//  1.0.0 闪退根因：
//    (1) 用 dlopen(..., RTLD_NOW) 强制加载 4 个私有框架，其依赖/构造器在第三方
//        App 进程里可能直接 abort；
//    (2) 把 dlsym 命中的 11 个符号**一律**强转成 void(long) 盲调，其中不少是
//        需要 mach_port_t / 结构体指针的 MIG 函数，传 0 会解引用 NULL；
//    (3) @try/@catch 只能捕获 NSException，抓不住 EXC_BAD_ACCESS / SIGSEGV。
//
//  1.0.1 的设计原则：**绝不调用任何签名不确定的函数**。
//    阶段 1（主路径）：公开 Darwin 通知 API notify_post()，签名固定
//        uint32_t(const char *)。入口 "com.apple.springboard.toggleLockScreen"
//        是 CVE-2025-24091 官方 PoC (rooootdev/evilnotify) 中验证过能锁屏的
//        通知；该漏洞直到 iOS 18.3 才通过 restrict-post 前缀 + entitlement
//        被封堵，iOS 15 上任意进程都可直接发送，无需 root / 平台权限。
//    阶段 2：只解析 GSEventLockDevice 这一个符号，它是 GraphicsServices 里
//        签名明确的 void(void)（见 LockMeNow / GSEvent.h）。GraphicsServices
//        已被 UIKit 链接进每个 App 进程，用 RTLD_DEFAULT 即可找到，不 dlopen。
//    阶段 3：其余候选 Darwin 通知逐条发送，逐条校验锁屏状态，避免重复
//        触发 toggle 语义导致「锁上又被解开」。
//
//    全程不 dlopen 私有框架、不对 SpringBoard 私有类发消息、不向未知签名的
//    函数指针发起调用 —— 从结构上消除闪退可能。所有 notify_* 符号都来自
//    libSystem，用 dlsym(RTLD_DEFAULT) 解析以规避 SDK 头文件差异。

#import "DeviceController.h"
#import <dlfcn.h>
#import <stdint.h>
#import <unistd.h>
#import <Foundation/Foundation.h>

// 公开 Darwin notify API 的确定签名（libSystem）
typedef uint32_t (*LNNotifyPostFn)(const char *name);
typedef uint32_t (*LNNotifyRegisterCheckFn)(const char *name, int *out_token);
typedef uint32_t (*LNNotifyGetStateFn)(int token, uint64_t *state);
typedef uint32_t (*LNNotifyCancelFn)(int token);

// GSEventLockDevice 的真实签名：无参 void(void)
typedef void (*LNLockDeviceFn)(void);

/// 阶段 1 的主入口：CVE-2025-24091 PoC 验证过的锁屏通知
static const char * const kPrimaryNotification = "com.apple.springboard.toggleLockScreen";

/// 阶段 3 的补充候选，全部是单向「请求锁定」类通知
static const char * const kFallbackNotifications[] = {
    "com.apple.springboard.lockdevice",
    "com.apple.springboard.requestlock",
    "com.apple.springboard.lock",
    "com.apple.springboard.lockScreen",
    "com.apple.springboard.dim",
    NULL
};

@interface DeviceController () {
    LNNotifyPostFn _post;
    LNNotifyRegisterCheckFn _registerCheck;
    LNNotifyGetStateFn _getState;
    LNNotifyCancelFn _cancel;
}
@property (nonatomic, strong) NSMutableArray<NSString *> *lines;
@end

@implementation DeviceController

- (instancetype)init
{
    self = [super init];
    if (self) {
        _lines = [NSMutableArray array];
        // 全部来自 libSystem，签名固定；取不到就整条路径跳过，绝不猜测调用
        _post          = (LNNotifyPostFn)dlsym(RTLD_DEFAULT, "notify_post");
        _registerCheck = (LNNotifyRegisterCheckFn)dlsym(RTLD_DEFAULT, "notify_register_check");
        _getState      = (LNNotifyGetStateFn)dlsym(RTLD_DEFAULT, "notify_get_state");
        _cancel        = (LNNotifyCancelFn)dlsym(RTLD_DEFAULT, "notify_cancel");
    }
    return self;
}

- (NSString *)diagnostics
{
    return self.lines.count ? [self.lines componentsJoinedByString:@"\n"] : @"（无诊断信息）";
}

- (void)line:(NSString *)text
{
    if (text) [self.lines addObject:text];
}

/// 读取系统锁屏状态：0=未锁定，1=已锁定，读取失败返回 -1
- (int)readLockState
{
    if (!_registerCheck || !_getState) return -1;
    int token = 0;
    uint32_t rc = _registerCheck("com.apple.springboard.lockstate", &token);
    if (rc != 0) return -1;
    uint64_t state = 0;
    uint32_t grc = _getState(token, &state);
    if (_cancel) _cancel(token);
    if (grc != 0) return -1;
    return (int)state;
}

- (NSString *)currentLockState
{
    int s = [self readLockState];
    if (s == 1) return @"已锁定 (1)";
    if (s == 0) return @"未锁定 (0)";
    return @"状态不可读 (-1)";
}

- (BOOL)lockScreen
{
    [self.lines removeAllObjects];

    NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
    [self line:@"== 环境 =="];
    [self line:[NSString stringWithFormat:@"iOS %ld.%ld.%ld",
                (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion]];
    [self line:[NSString stringWithFormat:@"notify_post %@ / notify_get_state %@",
                _post ? @"可用" : @"不可用", _getState ? @"可用" : @"不可用"]];
    [self line:[NSString stringWithFormat:@"锁屏前状态：%@", [self currentLockState]]];
    [self line:@""];

    BOOL posted = NO;

    // ---------- 阶段 1：公开 Darwin 通知（主路径） ----------
    [self line:@"== 阶段 1：Darwin 锁屏通知 =="];
    if (!_post) {
        [self line:@"notify_post 不可用，跳过此阶段。"];
    } else {
        uint32_t rc = _post(kPrimaryNotification);
        if (rc == 0) posted = YES;
        [self line:[NSString stringWithFormat:@"%s  →  %@", kPrimaryNotification,
                    rc == 0 ? @"已发送 (rc=0)"
                            : [NSString stringWithFormat:@"发送失败 (rc=%u)", rc]]];
        usleep(700000);  // 给 SpringBoard 处理通知的时间
        [self line:[NSString stringWithFormat:@"阶段 1 后状态：%@", [self currentLockState]]];
        if ([self readLockState] == 1) {
            [self line:@"→ 已锁定，停止后续尝试（避免重复 toggle 解锁）。"];
            return posted;
        }
    }

    // ---------- 阶段 2：唯一签名明确的私有入口 ----------
    [self line:@""];
    [self line:@"== 阶段 2：GSEventLockDevice() =="];
    LNLockDeviceFn lockDevice = (LNLockDeviceFn)dlsym(RTLD_DEFAULT, "GSEventLockDevice");
    if (lockDevice) {
        lockDevice();  // void(void)，不传任何参数
        [self line:@"已按 void(void) 签名调用（该符号在进程内已加载，未 dlopen 框架）"];
        usleep(400000);
        [self line:[NSString stringWithFormat:@"阶段 2 后状态：%@", [self currentLockState]]];
        if ([self readLockState] == 1) {
            [self line:@"→ 已锁定，停止后续尝试。"];
            return posted;
        }
    } else {
        [self line:@"当前进程未导出该符号，跳过（不 dlopen 私有框架）"];
    }

    // ---------- 阶段 3：逐条补充通知，逐条校验 ----------
    [self line:@""];
    [self line:@"== 阶段 3：补充候选通知（逐条校验）=="];
    if (!_post) {
        [self line:@"notify_post 不可用，跳过此阶段。"];
    } else {
        for (int i = 0; kFallbackNotifications[i]; i++) {
            if ([self readLockState] == 1) {
                [self line:@"→ 已锁定，停止发送剩余通知。"];
                break;
            }
            uint32_t rc = _post(kFallbackNotifications[i]);
            if (rc == 0) posted = YES;
            [self line:[NSString stringWithFormat:@"%s  →  %@",
                        kFallbackNotifications[i],
                        rc == 0 ? @"已发送 (rc=0)"
                                : [NSString stringWithFormat:@"发送失败 (rc=%u)", rc]]];
            usleep(250000);
            int s = [self readLockState];
            [self line:[NSString stringWithFormat:@"   状态：%@",
                        s == 1 ? @"已锁定 (1)" : (s == 0 ? @"未锁定 (0)" : @"不可读 (-1)")]];
            if (s == 1) break;
        }
    }

    [self line:@""];
    [self line:@"== 结果 =="];
    [self line:[NSString stringWithFormat:@"最终状态：%@", [self currentLockState]]];
    [self line:@"注：rc=0 只表示通知已投递；是否熄屏锁定由 SpringBoard 决定。"];
    [self line:@"若屏幕没熄灭，请把此段文字复制给开发者。"];
    return posted;
}

@end
