#include <unistd.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <dlfcn.h>

/* iOS SDK has no <sys/reboot.h>. Use dlsym() so no private header/symbol is needed. */
#define RB_HALT 0x08
typedef int (*reboot_fn)(int);

static void try_exec(const char *path, char *const argv[])
{
    if (access(path, X_OK) != 0) return;
    execv(path, argv);
}

int main(int argc, char *argv[])
{
    sync();
    char *shutdownArgs[] = { "shutdown", "-h", "now", NULL };
    char *haltArgs[] = { "halt", NULL };
    try_exec("/var/jb/usr/bin/shutdown", shutdownArgs);
    try_exec("/var/jb/usr/bin/halt", haltArgs);
    try_exec("/usr/bin/shutdown", shutdownArgs);
    try_exec("/usr/bin/halt", haltArgs);
    reboot_fn reboot_sys = (reboot_fn)dlsym(RTLD_DEFAULT, "reboot");
    if (reboot_sys != NULL) {
        reboot_sys(RB_HALT);
        fprintf(stderr, "poweroff failed: reboot(RB_HALT): %s\n", strerror(errno));
    } else {
        fprintf(stderr, "poweroff failed: reboot() unavailable\n");
    }
    return 1;
}
