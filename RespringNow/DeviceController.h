#import <Foundation/Foundation.h>

@interface DeviceController : NSObject

/// 结束 SpringBoard（注销主屏幕）。
/// @return YES 表示至少有一个 SpringBoard 进程已成功收到 SIGTERM。
- (BOOL) respring;

/// 进程是否仍然存活（用于判断注销是否真的发生了）。
- (BOOL) isSpringBoardAlive;

@end
