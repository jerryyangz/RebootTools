// 关机 helper：以 root 身份运行，尽量走"优雅关机"，最后兜底内核停机。
// 构建方式见 .github/workflows/build-poweroffnow.yml（clang 直接编译，输出到 Resources/）。

#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <sys/reboot.h>

// sys/reboot.h 里这些宏只在 __APPLE_API_PRIVATE 下可见，显式兜底一次
#ifndef RB_HALT
#define RB_HALT 0x08
#endif

static void try_exec(const char *path, char *const argv[])
{
	if (access(path, X_OK) != 0) {
		return;
	}
	execv(path, argv);
}

int main(int argc, char *argv[])
{
	// 先把缓存落盘，后面无论走哪条路径都是有害无益的反面
	sync();

	char *shutdownArgs[] = { "shutdown", "-h", "now", NULL };
	char *haltArgs[] = { "halt", NULL };

	// 1) rootless 越狱（palera1n 2.x / Dopamine）的 Procursus bootstrap
	try_exec("/var/jb/usr/bin/shutdown", shutdownArgs);
	try_exec("/var/jb/usr/bin/halt", haltArgs);

	// 2) rootful 越狱环境
	try_exec("/usr/bin/shutdown", shutdownArgs);
	try_exec("/usr/bin/halt", haltArgs);

	// 3) 没有可用的关机命令（例如只有 TrollStore）：让内核直接停机。
	//    RB_HALT = 0x08，效果等同于强制关机，设备需要按电源键重新开机。
	reboot(RB_HALT);

	// 走到这里说明连停机都被拒绝（通常是没有 root 权限）
	fprintf(stderr, "poweroff failed: reboot(RB_HALT): %s\n", strerror(errno));
	return 1;
}
