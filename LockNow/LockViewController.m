//  一键锁屏 1.1.0 —— 纯 Objective-C 正式版
//
//  1.0.0 ~ 1.0.3 连续四次「点图标就闪退」，均为 Swift + ObjC 混编实现。
//  用户用纯 ObjC 对照包「锁屏诊断」验证得到决定性结论：
//    · 纯 ObjC 启动链路完全正常，能看到「✅ 启动成功」
//    · 点击 notify_post("com.apple.springboard.toggleLockScreen") 后**屏幕熄灭**
//      → 该通知在 iOS 15.8.8 上确实有效，锁屏可行
//
//  因此本版整体按已验证的结构重写：
//    · 纯 Objective-C（main.m + UIApplicationMain），零 Swift 运行时依赖
//    · 全新 Bundle ID，避免旧 ID 反复覆盖安装造成的签名缓存问题
//    · 启动后自动发送一条锁屏通知；**只发一条**，避免 toggle 语义反向解锁
//    · 绝不自动退出，锁屏后解锁回来能看到结果页
//
//  与「锁屏诊断」的唯一区别：本版在 viewDidAppear 自动执行，无需点按钮。

#import "LockViewController.h"
#include <stdint.h>
#include <stdlib.h>

/* 公开 Darwin notify API（libSystem）。weak_import：符号缺失时为 NULL 而非启动崩溃。 */
extern uint32_t notify_post(const char *name) __attribute__((weak_import));
extern uint32_t notify_register_check(const char *name, int *out_token) __attribute__((weak_import));
extern uint32_t notify_get_state(int token, uint64_t *state) __attribute__((weak_import));

static NSString * const kLockNotification = @"com.apple.springboard.toggleLockScreen";

@interface LockViewController ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, assign) BOOL didStart;
@property (nonatomic, copy) NSString *report;
@end

@implementation LockViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    CGFloat W = [UIScreen mainScreen].bounds.size.width;
    CGFloat H = [UIScreen mainScreen].bounds.size.height;
    CGFloat x = 24.0;
    CGFloat w = W - 48.0;
    CGFloat y = 64.0;

    self.titleLabel = [self makeLabel:@"正在锁屏…" size:24 bold:YES color:[UIColor whiteColor]];
    self.titleLabel.frame = CGRectMake(x, y, w, 40);
    [self.view addSubview:self.titleLabel];
    y += 52;

    UILabel *hint = [self makeLabel:@"点开图标即锁屏并熄灭屏幕\n锁屏成功后本 App 不会自动退出，解锁后可回到这里"
                              size:14 bold:NO color:[UIColor lightGrayColor]];
    hint.frame = CGRectMake(x, y, w, 48);
    [self.view addSubview:hint];
    y += 62;

    self.detailLabel = [self makeLabel:@"" size:13 bold:NO
                                 color:[UIColor colorWithRed:0.75 green:0.95 blue:0.78 alpha:1.0]];
    self.detailLabel.frame = CGRectMake(x, y, w, 210);
    [self.view addSubview:self.detailLabel];

    UIButton *b1 = [self makeButton:@"再锁一次" action:@selector(onRetry)];
    b1.frame = CGRectMake(x, H - 150.0, w, 42);
    [self.view addSubview:b1];

    UIButton *b2 = [self makeButton:@"复制诊断" action:@selector(onCopy)];
    b2.frame = CGRectMake(x, H - 100.0, w, 42);
    [self.view addSubview:b2];

    UIButton *b3 = [self makeButton:@"退出" action:@selector(onQuit)];
    b3.frame = CGRectMake(x, H - 50.0, w, 38);
    [self.view addSubview:b3];
}

- (UILabel *)makeLabel:(NSString *)text size:(CGFloat)size bold:(BOOL)bold color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.textColor = color;
    l.font = bold ? [UIFont boldSystemFontOfSize:size]
                  : [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
    l.textAlignment = NSTextAlignmentLeft;
    l.numberOfLines = 0;
    return l;
}

- (UIButton *)makeButton:(NSString *)title action:(SEL)action
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    b.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1.0];
    b.layer.cornerRadius = 8;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (BOOL)prefersStatusBarHidden { return YES; }

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (self.didStart) return;
    self.didStart = YES;
    [self triggerLock];
}

#pragma mark - 核心

/// 读取当前锁定状态：-1 = 不可读，0 = 未锁定，1 = 已锁定
- (int)readLockState
{
    if (!notify_register_check || !notify_get_state) return -1;
    int token = 0;
    if (notify_register_check("com.apple.springboard.lockstate", &token) != 0) return -1;
    uint64_t state = 0;
    if (notify_get_state(token, &state) != 0) return -1;
    return (int)state;
}

- (void)triggerLock
{
    self.titleLabel.text = @"正在锁屏…";

    if (!notify_post) {
        self.titleLabel.text = @"锁屏失败";
        self.detailLabel.text = @"notify_post 在当前系统不可用。\n请确认本 App 是用 TrollStore 安装的。";
        return;
    }

    int before = [self readLockState];
    // 只发这一条，绝不多发：toggleLockScreen 是切换语义，连发会把屏幕解开。
    uint32_t rc = notify_post([kLockNotification UTF8String]);
    int after = [self readLockState];

    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"?";
    self.report = [NSString stringWithFormat:
        @"一键锁屏 %@  ·  %@\niOS %@\n\n"
        @"notify_post(\"com.apple.springboard.toggleLockScreen\")\nrc = %u\n"
        @"lockstate：%d → %d（1=已锁定，0=未锁定，-1=不可读）\n\n"
        @"rc=0 表示通知已投递。\n屏幕应已熄灭；解锁后回到本页即为正常运行。",
        ver, bid, [[UIDevice currentDevice] systemVersion], rc, before, after];

    self.titleLabel.text = (rc == 0) ? @"✅ 锁屏请求已发送" : @"锁屏请求发送失败";
    self.detailLabel.text = self.report;
}

#pragma mark - 按钮

- (void)onRetry
{
    // 手动重试时允许再次 toggle；若屏幕已锁定，用户看不到本页，不会误触。
    [self triggerLock];
}

- (void)onCopy
{
    UIPasteboard.generalPasteboard.string = self.report ?: @"";
    self.titleLabel.text = @"诊断已复制 ✓";
}

- (void)onQuit
{
    exit(EXIT_SUCCESS);
}

@end
