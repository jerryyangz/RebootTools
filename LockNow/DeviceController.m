//  一键锁屏 1.0.2
//
//  1.0.0 / 1.0.1 连续两次「点图标就闪退」。本版不再试图猜哪个私有 API 能锁屏，
//  而是先把三件事做成确定性的：
//
//  (1) 进程内绝不调用任何私有框架 / 未验证签名的符号。
//      1.0.0 盲调了 11 个 dlsym 命中的私有符号（一律当成 void(long)），
//      1.0.1 仍保留了一个 GraphicsServices 私有锁屏函数 —— 两版唯一的共同危险调用就是它。
//      本版只调用 libSystem 的公开 notify_post()，从结构上消除 EXC_BAD_ACCESS。
//
//  (2) 修掉「一闪就没了」的真正元凶：AppDelegate 里的
//      applicationDidEnterBackground → exit(EXIT_SUCCESS)。锁屏通知只要让 App
//      短暂失焦，进程就会立刻自杀，用户看到的就是「闪退 + 屏幕没灭」。
//      RespringNow（真机验证成功）并没有这个回调。本版彻底删除它。
//
//  (3) 内置崩溃哨兵：崩溃信号触发时把「崩在第几阶段」写入
//      Documents/locknow-crash.log，下次启动显示出来并清空。若还存在未知
//      崩溃点，用户只要再点开一次图标就能拿到确切位置，不必连电脑取日志。
//
//  另外：本版绝不自动退出。锁屏成功时 App 只是进后台，解锁后会看到结果页；
//  只有用户点「退出」才调用 exit()。

#import "DeviceController.h"
#import <dlfcn.h>
#import <signal.h>
#import <unistd.h>
#import <fcntl.h>
#import <stdio.h>
#import <string.h>
#import <stdint.h>
#import <Foundation/Foundation.h>

#pragma mark - 崩溃哨兵

static volatile sig_atomic_t gStage = 0;
static char gStageNote[128] = "launch";
static int gLogFD = -1;
static char gLogPath[1024] = {0};

static void LNSetStage(int stage, const char *note)
{
    gStage = stage;
    if (note) {
        strncpy(gStageNote, note, sizeof(gStageNote) - 1);
        gStageNote[sizeof(gStageNote) - 1] = '\0';
    }
}

static void LNCrashHandler(int sig)
{
    // signal handler 里只用 async-signal-safe 的 write / snprintf(整数格式)
    char buf[320];
    int n = snprintf(buf, sizeof(buf), "CRASH sig=%d stage=%d note=%s\n",
                     sig, (int)gStage, gStageNote);
    if (n > 0 && gLogFD >= 0) {
        (void)write(gLogFD, buf, (size_t)n);
    }
    // 恢复默认并重新抛出，让系统照常生成 .ips 崩溃报告
    signal(sig, SIG_DFL);
    raise(sig);
}

void LNInstallCrashGuard(void)
{
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                          NSUserDomainMask, YES) firstObject];
    if (docs.length == 0) {
        docs = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:docs
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *path = [docs stringByAppendingPathComponent:@"locknow-crash.log"];
    const char *fs = [path fileSystemRepresentation];
    if (fs) {
        strncpy(gLogPath, fs, sizeof(gLogPath) - 1);
        gLogPath[sizeof(gLogPath) - 1] = '\0';
    }
    if (gLogPath[0] != '\0') {
        gLogFD = open(gLogPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    }
    // 容器不可写时退到 /tmp，保证哨兵至少有一个落点
    if (gLogFD < 0) {
        strncpy(gLogPath, "/tmp/locknow-crash.log", sizeof(gLogPath) - 1);
        gLogPath[sizeof(gLogPath) - 1] = '\0';
        gLogFD = open(gLogPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    }
    signal(SIGSEGV, LNCrashHandler);
    signal(SIGBUS,  LNCrashHandler);
    signal(SIGABRT, LNCrashHandler);
    signal(SIGILL,  LNCrashHandler);
    signal(SIGFPE,  LNCrashHandler);
    LNSetStage(1, "didFinishLaunching");
}

NSString *LNLastCrashReport(void)
{
    if (gLogPath[0] == '\0') return nil;
    int fd = open(gLogPath, O_RDONLY);
    if (fd < 0) return nil;
    char buf[2048];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) return nil;
    buf[n] = '\0';
    // 读走即清空，避免每次启动都重复显示同一条记录
    unlink(gLogPath);
    if (gLogFD >= 0) close(gLogFD);
    gLogFD = open(gLogPath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    NSString *s = [NSString stringWithUTF8String:buf];
    return s.length ? s : nil;
}

#pragma mark - 公开 Darwin notify API（libSystem，签名固定）

typedef uint32_t (*LNNotifyPostFn)(const char *name);
typedef uint32_t (*LNNotifyRegisterCheckFn)(const char *name, int *out_token);
typedef uint32_t (*LNNotifyGetStateFn)(int token, uint64_t *state);
typedef uint32_t (*LNNotifyCancelFn)(int token);

static BOOL sResolved = NO;
static LNNotifyPostFn sPost = NULL;
static LNNotifyRegisterCheckFn sRegisterCheck = NULL;
static LNNotifyGetStateFn sGetState = NULL;
static LNNotifyCancelFn sCancel = NULL;

static void LNResolveNotify(void)
{
    if (sResolved) return;
    sResolved = YES;
    sPost          = (LNNotifyPostFn)dlsym(RTLD_DEFAULT, "notify_post");
    sRegisterCheck = (LNNotifyRegisterCheckFn)dlsym(RTLD_DEFAULT, "notify_register_check");
    sGetState      = (LNNotifyGetStateFn)dlsym(RTLD_DEFAULT, "notify_get_state");
    sCancel        = (LNNotifyCancelFn)dlsym(RTLD_DEFAULT, "notify_cancel");
}

/// 首条是 CVE-2025-24091 官方 PoC (rooootdev/evilnotify) 里预设的锁屏入口；
/// 其余为历史上出现过的单向「请求锁定」通知名。逐条发送并逐条校验状态，
/// 一旦检测到已锁定立即停止，避免 toggle 语义把屏幕又解开。
static const char * const kLockNotifications[] = {
    "com.apple.springboard.toggleLockScreen",
    "com.apple.springboard.lockdevice",
    "com.apple.springboard.lockScreen",
    "com.apple.springboard.requestlock",
    "com.apple.springboard.lock",
    "com.apple.springboard.dim",
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
    if (!sRegisterCheck || !sGetState) return -1;
    int token = 0;
    uint32_t rc = sRegisterCheck("com.apple.springboard.lockstate", &token);
    if (rc != 0) return -1;
    uint64_t state = 0;
    uint32_t grc = sGetState(token, &state);
    if (sCancel) sCancel(token);
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
    LNResolveNotify();
    LNSetStage(10, "lockScreen begin");

    NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
    [self line:@"== 环境 =="];
    [self line:[NSString stringWithFormat:@"iOS %ld.%ld.%ld",
                (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion]];
    [self line:[NSString stringWithFormat:@"notify_post %@ / notify_get_state %@",
                sPost ? @"可用" : @"不可用", sGetState ? @"可用" : @"不可用"]];
    [self line:[NSString stringWithFormat:@"锁屏前状态：%@", [self currentLockState]]];
    [self line:@""];
    [self line:@"== 逐条发送（每条后读系统状态）=="];

    BOOL posted = NO;
    if (!sPost) {
        [self line:@"notify_post 不可用，请确认是用 TrollStore 安装的。"];
    } else {
        for (int i = 0; kLockNotifications[i] != NULL; i++) {
            const char *name = kLockNotifications[i];
            LNSetStage(20 + i, name);
            uint32_t rc = sPost(name);
            if (rc == 0) posted = YES;
            usleep(300000);  // 0.3s，总时长 < 2s，且在后台队列不阻塞主线程
            int s = [self readLockState];
            [self line:[NSString stringWithFormat:@"%s\n   rc=%u  状态=%@",
                        name, rc,
                        s == 1 ? @"已锁定 (1)" : (s == 0 ? @"未锁定 (0)" : @"不可读 (-1)")]];
            if (s == 1) {
                [self line:@"→ 检测到已锁定，停止发送剩余通知（避免 toggle 反向解锁）。"];
                break;
            }
        }
    }

    LNSetStage(90, "lockScreen finish");
    [self line:@""];
    [self line:@"== 结果 =="];
    [self line:[NSString stringWithFormat:@"最终状态：%@", [self currentLockState]]];
    [self line:@"注：rc=0 只表示通知已投递，是否熄屏由 SpringBoard 决定。"];
    [self line:@"若屏幕没熄灭，请长按复制这段内容发给开发者。"];
    return posted;
}

@end
