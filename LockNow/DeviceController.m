//  一键锁屏的核心实现。
//
//  纯 TrollStore App 无法注入 SpringBoard，也不能使用 iOS 16.4+ 的快捷指令
//  「锁定屏幕」动作，因此只能在运行时探测系统私有框架里可用的锁屏入口。
//  所有符号都用 dlopen/dlsym 动态解析：编译/链接不依赖任何私有头或私有符号，
//  也不会因为某个符号在某版 iOS 上被移除而构建失败。
//
//  多出来的 long 参数是为了兼容「需要一个 mach_port_t」的签名：
//  void(void) 的函数会忽略它，需要 port 的函数拿到 0 (MACH_PORT_NULL) 会安全失败。

#import "DeviceController.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>

typedef void (*LNLockFn)(long);
typedef uint32_t (*LNNotifyPostFn)(const char *);

static const char *kFrameworks[] = {
    "/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices",
    "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
    "/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices",
    "/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices",
    NULL
};

static const char *kSymbols[] = {
    "GSEventLockDevice",
    "GSEventLockDeviceNow",
    "SBSLockDevice",
    "SBSLockScreen",
    "SBSLockScreenNow",
    "SBSLockDeviceNow",
    "SBSLockUI",
    "SBSpringBoardServerLockDevice",
    "SBSpringBoardServerLockScreen",
    "BKSLockDevice",
    "FBSSystemServiceLockDevice",
    NULL
};

static const char *kNotifications[] = {
    "com.apple.springboard.lockdevice",
    "com.apple.springboard.lock",
    "com.apple.springboard.requestlock",
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

- (BOOL)lockScreen
{
    [self.lines removeAllObjects];
    BOOL found = NO;

    [self line:@"== 私有框架 =="];
    for (int fi = 0; kFrameworks[fi]; fi++) {
        void *handle = dlopen(kFrameworks[fi], RTLD_NOW | RTLD_LOCAL);
        NSString *name = [[NSString stringWithUTF8String:kFrameworks[fi]] lastPathComponent];
        [self line:[NSString stringWithFormat:@"%@  %@", name, handle ? @"✔ 已加载" : @"✗ 加载失败"]];

        if (!handle) continue;
        for (int si = 0; kSymbols[si]; si++) {
            void *sym = dlsym(handle, kSymbols[si]);
            if (!sym) continue;
            found = YES;
            @try {
                ((LNLockFn)sym)(0);
                [self line:[NSString stringWithFormat:@"%s  ✔ 已调用 (%@)", kSymbols[si], name]];
            } @catch (NSException *e) {
                [self line:[NSString stringWithFormat:@"%s  ! 异常: %@", kSymbols[si], e.reason]];
            }
        }
        // 不 dlclose：保持框架加载，避免刚发出的事件被撤销
    }
    if (!found) [self line:@"（没有任何候选锁屏符号命中）"];

    [self line:@"== SpringBoard 类 =="];
    [self tryClass:@"SBLockScreenManager" selector:@selector(lockUIFromSource:withOptions:) style:1];
    [self tryClass:@"SBLockScreenManager" selector:@selector(lockUIFromSource:) style:2];
    [self tryClass:@"SBLockScreenManager" selector:@selector(lockUI) style:0];
    [self tryClass:@"SBUserAgent" selector:@selector(lockAndDimDevice) style:0];
    [self tryClass:@"SBUserAgent" selector:@selector(lockAndDim) style:0];

    [self line:@"== 系统通知 =="];
    LNNotifyPostFn notifyPost = (LNNotifyPostFn)dlsym(RTLD_DEFAULT, "notify_post");
    if (!notifyPost) {
        [self line:@"notify_post  ✗ 不可用"];
    } else {
        for (int ni = 0; kNotifications[ni]; ni++) {
            uint32_t status = notifyPost(kNotifications[ni]);
            [self line:[NSString stringWithFormat:@"%s  ✔ 已发送 (status=%u)", kNotifications[ni], status]];
        }
    }

    return found;
}

/// 只调用当前进程里已经加载的类；刻意不 dlopen 整个 SpringBoard.framework，
/// 避免在第三方 App 进程里拉起大量依赖导致崩溃。
- (BOOL)tryClass:(NSString *)className selector:(SEL)selector style:(int)style
{
    Class cls = NSClassFromString(className);
    NSString *selName = NSStringFromSelector(selector);
    if (!cls) {
        [self line:[NSString stringWithFormat:@"%@.%@  ✗ 类未在当前进程加载", className, selName]];
        return NO;
    }

    id instance = nil;
    @try {
        if ([cls respondsToSelector:@selector(sharedInstance)]) {
            instance = ((id (*)(id, SEL))objc_msgSend)((id)cls, @selector(sharedInstance));
        } else if ([cls respondsToSelector:@selector(sharedManager)]) {
            instance = ((id (*)(id, SEL))objc_msgSend)((id)cls, @selector(sharedManager));
        }
    } @catch (NSException *e) {
        [self line:[NSString stringWithFormat:@"%@  ! 单例异常: %@", className, e.reason]];
        return NO;
    }

    if (!instance || ![instance respondsToSelector:selector]) {
        [self line:[NSString stringWithFormat:@"%@.%@  ✗ 无此方法", className, selName]];
        return NO;
    }

    @try {
        switch (style) {
            case 0:
                ((void (*)(id, SEL))objc_msgSend)(instance, selector);
                break;
            case 1:
                ((void (*)(id, SEL, NSUInteger, id))objc_msgSend)(instance, selector, 1, nil);
                break;
            default:
                ((void (*)(id, SEL, NSUInteger))objc_msgSend)(instance, selector, 1);
                break;
        }
        [self line:[NSString stringWithFormat:@"%@.%@  ✔ 已调用", className, selName]];
        return YES;
    } @catch (NSException *e) {
        [self line:[NSString stringWithFormat:@"%@  ! 异常: %@", className, e.reason]];
        return NO;
    }
}

@end
