#import <Foundation/Foundation.h>

@interface DeviceController : NSObject

/// 以 root 身份运行 App 内置的 PowerOffHelper，让设备关机。
/// 成功关机的正常情况下这个调用**不会返回**（系统已经断电）。
/// 一旦返回，就说明关机没有生效。
- (void)powerOff;

@end
