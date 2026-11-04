//  以 root 身份拉起内置 helper，让它执行关机命令。
//  spawnRoot 的写法沿用 TrollStore / RebootTools：
//  https://github.com/opa334/TrollStore/blob/main/Shared/TSUtil.m

#import "DeviceController.h"
#import <spawn.h>
#import <sys/wait.h>
#import <Foundation/Foundation.h>

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *__restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *__restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *__restrict, uid_t);

static int spawnRoot(NSString *path, NSArray<NSString *> *args)
{
	NSMutableArray *argvM = args.mutableCopy ?: [NSMutableArray new];
	[argvM insertObject:path atIndex:0];

	NSUInteger argCount = argvM.count;
	char **argv = (char **)malloc((argCount + 1) * sizeof(char *));
	for (NSUInteger i = 0; i < argCount; i++) {
		argv[i] = strdup([argvM[i] UTF8String]);
	}
	argv[argCount] = NULL;

	posix_spawnattr_t attr;
	posix_spawnattr_init(&attr);
	posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
	posix_spawnattr_set_persona_uid_np(&attr, 0);
	posix_spawnattr_set_persona_gid_np(&attr, 0);

	pid_t pid = 0;
	int spawnError = posix_spawn(&pid, path.UTF8String, NULL, &attr, argv, NULL);
	posix_spawnattr_destroy(&attr);

	for (NSUInteger i = 0; i < argCount; i++) {
		free(argv[i]);
	}
	free(argv);

	if (spawnError != 0) {
		NSLog(@"[PowerOffNow] posix_spawn error %d", spawnError);
		return spawnError;
	}

	int status = 0;
	if (waitpid(pid, &status, 0) == -1) {
		return -1;
	}
	return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

@implementation DeviceController

- (void)powerOff
{
	NSString *path = [[NSBundle mainBundle] pathForResource:@"PowerOffHelper" ofType:@""];
	if (path == nil) {
		NSLog(@"[PowerOffNow] helper missing in bundle");
		return;
	}

	int status = spawnRoot(path, @[]);
	NSLog(@"[PowerOffNow] helper exited with %d", status);
}

@end
