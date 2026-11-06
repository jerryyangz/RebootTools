//  一键锁屏 1.0.3
//
//  1.0.2 的崩溃哨兵在真机回报：CRASH sig=11 stage=1 note=didFinishLaunching。
//  stage=1 是「哨兵安装完毕」到「lockScreen 开始」之间的唯一阶段号，
//  下一个 stage 是 10（lockScreen begin）。这证明崩溃发生在启动 UI 路径上，
//  锁屏代码一次都没执行过 —— 前两版「通知发出去但锁不住」的判断并不成立，
//  通知根本没发出去。之前两轮一直在改锁屏 API，方向错了。
//
//  本版把启动路径做成与真机验证成功的 RespringNow 完全同构，删掉 LockNow
//  独有的所有额外机制：
//   - 删除崩溃哨兵（signal handler、C 函数桥接、Documents 文件 IO）
//   - 删除动态符号解析：改用编译期 extern 声明 libSystem 的公开 Darwin 符号
//   - 删除后台队列与人为延迟：锁屏调用在主线程 viewDidAppear 同步执行，全程 < 50ms
//   - 删除安全模式、多行文本框、复杂约束与 viewDidLoad 抢跑
//   - 绝不自动退出，只有用户点「退出」才结束进程
//
//  notify_* 是公开的 Darwin 通知 API，由 libSystem 导出，签名自 Mac OS X 10.4
//  起未变。extern 声明让 dyld 在启动时绑定，比运行时解析符号更确定。

#import "DeviceController.h"
#include <stdint.h>

/* 公开 Darwin notify API（libSystem）。不使用 <notify.h> 以免 iOS SDK 头文件差异。
   weak_import：万一某个 iOS 版本未导出，符号为 NULL 而不是让 dyld 在启动时终止 App。 */
extern uint32_t notify_post(const char *name) __attribute__((weak_import));
extern uint32_t notify_register_check(const char *name, int *out_token) __attribute__((weak_import));
extern uint32_t notify_get_state(int token, uint64_t *state) __attribute__((weak_import));

/// 首条是 CVE-2025-24091 官方 PoC (rooootdev/evilnotify) 里预设的锁屏入口。
/// 逐条投递并读取 lockstate，一旦检测到已锁定立即停止，避免 toggle 反向解锁。
static const char * const kLockNotifications[] = {
    "com.apple.springboard.toggleLockScreen",
    "com.apple.springboard.lockdevice",
    "com.apple.springboard.lockScreen",
    "com.apple.springboard.requestlock",
    "com.apple.springboard.lock",
    NULL
};

@interface DeviceController ()
@property (nonatomic, strong) NSMutableArray<NSString *> *lines;
@end

@implementation DeviceController

- (instancetype)init
{
    self = [super init];
    if (self) {
        _lines = [NSMutableArray array];
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

/// 0=未锁定，1=已锁定，读取失败返回 -1
- (int)readLockState
{
    if (!notify_register_check || !notify_get_state) return -1;
    int token = 0;
    if (notify_register_check("com.apple.springboard.lockstate", &token) != 0) return -1;
    uint64_t state = 0;
    if (notify_get_state(token, &state) != 0) return -1;
    return (int)state;
}

- (BOOL)isLocked
{
    return [self readLockState] == 1;
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
    if (!notify_post) {
        [self line:@"notify_post 在当前系统不可用，请确认是用 TrollStore 安装的。"];
        return NO;
    }
    [self line:[NSString stringWithFormat:@"锁屏前状态：%@", [self currentLockState]]];
    [self line:@""];

    BOOL posted = NO;
    for (int i = 0; kLockNotifications[i] != NULL; i++) {
        const char *name = kLockNotifications[i];
        uint32_t rc = notify_post(name);
        if (rc == 0) posted = YES;
        int s = [self readLockState];
        [self line:[NSString stringWithFormat:@"%s\n   rc=%u  状态=%d", name, rc, s]];
        if (s == 1) {
            [self line:@"→ 检测到已锁定，停止投递（避免 toggle 反向解锁）"];
            break;
        }
    }

    [self line:@""];
    [self line:[NSString stringWithFormat:@"锁屏后状态：%@", [self currentLockState]]];
    [self line:@"注：rc=0 只表示通知已投递，是否熄屏由 SpringBoard 决定。"];
    return posted;
}

@end
