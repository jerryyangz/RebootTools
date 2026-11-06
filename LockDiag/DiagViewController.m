//  锁屏诊断 1.0.0 —— 纯 Objective-C 对照包
//
//  目的：把「一点图标就闪退」拆成可观察的三步。本 App 启动后
//  **不执行任何锁屏调用、不自动做任何事**，只显示一个界面。
//  看到「✅ 启动成功」就证明：签名、entitlements、UIKit、ObjC 启动链路全正常。
//
//  三个按钮分别测试：① notify_post 发锁屏通知 ② 读 lockstate ③ 退出。
//  全新 Bundle ID（com.jerryyangz.LockDiag），可与旧「一键锁屏」并存，
//  排除同一 ID 反复覆盖安装造成的签名缓存问题。

#import "DiagViewController.h"
#include <stdint.h>
#include <stdlib.h>

/* 公开 Darwin notify API（libSystem）。weak_import 保证符号缺失时是 NULL 而非启动崩溃。 */
extern uint32_t notify_post(const char *name) __attribute__((weak_import));
extern uint32_t notify_register_check(const char *name, int *out_token) __attribute__((weak_import));
extern uint32_t notify_get_state(int token, uint64_t *state) __attribute__((weak_import));

@interface DiagViewController ()
@property (nonatomic, strong) UILabel *resultLabel;
@end

@implementation DiagViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    CGFloat W = [UIScreen mainScreen].bounds.size.width;
    CGFloat H = [UIScreen mainScreen].bounds.size.height;
    CGFloat x = 24.0;
    CGFloat w = W - 48.0;
    CGFloat y = 56.0;

    UILabel *ok = [self makeLabel:@"✅ 启动成功" size:26 bold:YES color:[UIColor whiteColor]];
    ok.frame = CGRectMake(x, y, w, 42);
    [self.view addSubview:ok];
    y += 50;

    UILabel *hint = [self makeLabel:@"看到这行 = 签名 / 权限 / 启动链路全部正常\n本包不会自动执行任何操作，请手动点下方按钮"
                              size:14 bold:NO color:[UIColor lightGrayColor]];
    hint.frame = CGRectMake(x, y, w, 48);
    [self.view addSubview:hint];
    y += 60;

    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"?";
    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    NSString *ios = [[UIDevice currentDevice] systemVersion];
    UILabel *info = [self makeLabel:[NSString stringWithFormat:
                      @"构建：LockDiag %@\nBundle ID：%@\niOS：%@\n编译架构：arm64 / arm64e",
                      ver, bid, ios] size:13 bold:NO color:[UIColor colorWithRed:0.55 green:0.75 blue:1.0 alpha:1.0]];
    info.frame = CGRectMake(x, y, w, 76);
    [self.view addSubview:info];
    y += 88;

    UIButton *b1 = [self makeButton:@"① 发送锁屏通知（notify_post）" action:@selector(onPost)];
    b1.frame = CGRectMake(x, y, w, 46);
    [self.view addSubview:b1];
    y += 58;

    UIButton *b2 = [self makeButton:@"② 读取锁定状态（lockstate）" action:@selector(onState)];
    b2.frame = CGRectMake(x, y, w, 46);
    [self.view addSubview:b2];
    y += 62;

    self.resultLabel = [self makeLabel:@"结果会显示在这里" size:13 bold:NO
                                 color:[UIColor colorWithRed:0.75 green:0.95 blue:0.78 alpha:1.0]];
    self.resultLabel.frame = CGRectMake(x, y, w, 190);
    [self.view addSubview:self.resultLabel];

    UIButton *b3 = [self makeButton:@"退出" action:@selector(onQuit)];
    b3.frame = CGRectMake(x, H - 90.0, w, 42);
    [self.view addSubview:b3];
}

- (UILabel *)makeLabel:(NSString *)text size:(CGFloat)size bold:(BOOL)bold color:(UIColor *)color
{
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.textColor = color;
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
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

#pragma mark - 分步测试

- (void)onPost
{
    if (!notify_post) {
        self.resultLabel.text = @"notify_post 不可用（当前系统未导出该符号）";
        return;
    }
    uint32_t rc = notify_post("com.apple.springboard.toggleLockScreen");
    self.resultLabel.text = [NSString stringWithFormat:
        @"notify_post(\"com.apple.springboard.toggleLockScreen\")\nrc = %u\n\n"
        @"• 屏幕熄灭 → 通知有效，锁屏可行\n"
        @"• 屏幕没灭 → iOS 15 的 SpringBoard 未监听该通知\n"
        @"• 点完就闪退 → 崩在 notify_post 本身，请提供 .ips 日志", rc];
}

- (void)onState
{
    if (!notify_register_check || !notify_get_state) {
        self.resultLabel.text = @"notify_register_check / notify_get_state 不可用";
        return;
    }
    int token = 0;
    uint32_t rc = notify_register_check("com.apple.springboard.lockstate", &token);
    uint64_t state = 0;
    uint32_t grc = notify_get_state(token, &state);
    self.resultLabel.text = [NSString stringWithFormat:
        @"notify_register_check rc = %u  token = %d\n"
        @"notify_get_state     rc = %u  state = %llu\n\n"
        @"state：1 = 已锁定，0 = 未锁定\n"
        @"点①之后再点②，若 state 由 0 变 1 即为锁屏成功", rc, token, grc, state];
}

- (void)onQuit
{
    exit(EXIT_SUCCESS);
}

@end
