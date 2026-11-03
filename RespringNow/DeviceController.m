//  注销主屏幕的核心实现。
//  进程枚举与 kill 的写法沿用 TrollStore / RebootTools 的实现：
//  https://github.com/opa334/TrollStore/blob/main/Shared/TSUtil.m
//  需要 entitlements.plist 里的 platform-application /
//  com.apple.private.security.no-sandbox 才能向 SpringBoard 发信号。

#import "DeviceController.h"
#import <sys/sysctl.h>
#import <signal.h>
#import <Foundation/Foundation.h>

static void enumerateProcessesUsingBlock(void (^enumerator)(pid_t pid, NSString *executablePath, BOOL *stop));

@implementation DeviceController

- (BOOL) respring
{
	__block BOOL killed = NO;

	enumerateProcessesUsingBlock(^(pid_t pid, NSString *executablePath, BOOL *stop) {
		if ([executablePath.lastPathComponent isEqualToString:@"SpringBoard"]) {
			// SIGTERM 让 SpringBoard 体面退出，系统会立刻重新拉起它（即一次注销）
			if (kill(pid, SIGTERM) == 0) {
				killed = YES;
			}
		}
	});

	return killed;
}

- (BOOL) isSpringBoardAlive
{
	__block BOOL alive = NO;

	enumerateProcessesUsingBlock(^(pid_t pid, NSString *executablePath, BOOL *stop) {
		if ([executablePath.lastPathComponent isEqualToString:@"SpringBoard"]) {
			alive = YES;
			*stop = YES;
		}
	});

	return alive;
}

static void enumerateProcessesUsingBlock(void (^enumerator)(pid_t pid, NSString *executablePath, BOOL *stop))
{
	static int maxArgumentSize = 0;
	if (maxArgumentSize == 0) {
		size_t size = sizeof(maxArgumentSize);
		if (sysctl((int[]){ CTL_KERN, KERN_ARGMAX }, 2, &maxArgumentSize, &size, NULL, 0) == -1) {
			maxArgumentSize = 4096; // 兜底值
		}
	}

	int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
	struct kinfo_proc *info;
	size_t length;

	if (sysctl(mib, 3, NULL, &length, NULL, 0) < 0) return;
	if (!(info = malloc(length))) return;
	if (sysctl(mib, 3, info, &length, NULL, 0) < 0) {
		free(info);
		return;
	}

	int count = (int)(length / sizeof(struct kinfo_proc));
	for (int i = 0; i < count; i++) {
		@autoreleasepool {
			pid_t pid = info[i].kp_proc.p_pid;
			if (pid == 0) continue;

			size_t size = maxArgumentSize;
			char *buffer = (char *)malloc(length);
			if (!buffer) continue;

			if (sysctl((int[]){ CTL_KERN, KERN_PROCARGS2, pid }, 3, buffer, &size, NULL, 0) == 0) {
				NSString *executablePath = [NSString stringWithCString:(buffer + sizeof(int))
															  encoding:NSUTF8StringEncoding];
				BOOL stop = NO;
				if (executablePath) {
					enumerator(pid, executablePath, &stop);
				}
				if (stop) {
					free(buffer);
					break;
				}
			}
			free(buffer);
		}
	}

	free(info);
}

@end
