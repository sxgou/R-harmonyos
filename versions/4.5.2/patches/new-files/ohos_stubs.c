/* OHOS libc 缺失符号补齐库
 *
 * OHOS SDK 的 libc.so（基于 musl 的裁剪版）中不包含以下符号。
 * 本文件编译为共享库 libohos_stubs.so，通过 LD_PRELOAD 注入
 * 提供运行时缺失的符号。
 *
 * 构建集成在 src/extra/ohos_stubs/Makefile.in 中，
 * 安装到 $(Rexeclibdir)（即 R 主库目录），由 etc/ldpaths 中的
 * LD_PRELOAD 机制自动加载。
 */

#define _GNU_SOURCE
#include <spawn.h>
#include <string.h>
#include <errno.h>

/* R 构建系统默认使用 -fvisibility=hidden，因此所有函数默认不导出。
 * LD_PRELOAD 需要全局可见符号，这里显式恢复默认可见性。 */
#pragma GCC visibility push(default)

/**
 * posix_spawn_file_actions_addchdir_np - 设置子进程工作目录
 *
 * glibc 扩展（2.29+），也被较新版本的 musl 支持。
 * OHOS 的 musl 版本不包含此函数。
 */
int posix_spawn_file_actions_addchdir_np(posix_spawn_file_actions_t *actions,
                                         const char *path) {
    (void)actions;
    (void)path;
    return ENOSYS;
}

/**
 * __xpg_strerror_r - XSI 兼容的错误信息函数
 *
 * glibc 中 strerror_r 有两个版本（GNU 和 XSI），
 * 通过 __xpg_strerror_r 符号提供 XSI 兼容版本。
 * musl 的 strerror_r 始终是 XSI 兼容的，直接转发即可。
 */
int __xpg_strerror_r(int errnum, char *buf, size_t buflen) {
    return strerror_r(errnum, buf, buflen);
}

/**
 * pthread_setcanceltype - 设置线程取消类型
 *
 * glibc 扩展（非 POSIX），musl 不包含。用于设置取消是延迟的
 * （仅在取消点取消）还是异步的（随时可取消）。
 *
 * R 包 cli 的 thread.c 使用此函数实现进度条线程。
 * 返回 0 使调用方认为设置成功，实际使用默认的延迟取消行为。
 */
int pthread_setcanceltype(int type, int *oldtype) {
    (void)type;
    if (oldtype) *oldtype = 0;  /* PTHREAD_CANCEL_DEFERRED */
    return 0;
}

/**
 * pthread_cancel - 向线程发送取消请求
 *
 * glibc 扩展（非 POSIX），musl 不包含。
 * stub 版本直接返回 0（成功），使调用方认为取消成功。
 * 进程退出时线程是否真正取消无关紧要。
 */
int pthread_cancel(void *thread) {
    (void)thread;
    return 0;
}

#pragma GCC visibility pop
