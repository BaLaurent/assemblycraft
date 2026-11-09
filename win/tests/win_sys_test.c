/* win_sys_test.c - standalone test of win/win_sys.c (NOT linked into the game).
 *
 * It calls win_syscall() directly, the way win/syscall_stub.asm does, and checks the Linux results the game's
 * assembly relies on: file I/O, directories, getdents64 records, time, random numbers, anonymous memory and UDP
 * sockets. One `ok` / `FAIL` line per test; the exit code is non-zero when any test failed.
 *
 *   x86_64-w64-mingw32-gcc -O2 -std=gnu11 -Wall -Wextra -Iwin win/win_sys.c win/tests/win_sys_test.c \
 *       -o win_sys_test.exe -lws2_32 -lbcrypt -static
 *   wine win_sys_test.exe
 *
 * With -DWITH_STUB (and win/syscall_stub.asm assembled with `nasm -f win64` and linked in) one more test runs the
 * same calls through the real stub, which checks its register and stack-argument mapping against win_syscall. */
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../win.h"

extern SYSV int64_t win_syscall(int64_t nr, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6);

/* ---- the Linux numbers the test needs (the test must not share win_sys.c's names, it checks them) ------- */
enum {
    E_NOENT = 2, E_BADF = 9, E_AGAIN = 11, E_FAULT = 14, E_EXIST = 17, E_NOTDIR = 20, E_ISDIR = 21, E_INVAL = 22,
    E_MFILE = 24, E_NOSYS = 38, E_NOTEMPTY = 39, E_NOTSOCK = 88, E_NOPROTOOPT = 92, E_PROTONOSUPPORT = 93,
    E_SOCKTNOSUPPORT = 94, E_AFNOSUPPORT = 97, E_NETUNREACH = 101, E_CONNRESET = 104, E_NODEV = 19
};
enum { O_RD = 0, O_WR = 1, O_RW = 2, O_CRE = 0x40, O_EXC = 0x80, O_TRN = 0x200, O_APP = 0x400, O_DIR = 0x10000 };
#define O_WCT 0x241 /* O_WRONLY|O_CREAT|O_TRUNC, what file_write_atomic uses */

#define P(x) ((int64_t)(intptr_t)(x))

static int64_t s_open(const char *p, int fl) { return win_syscall(2, P(p), fl, 0644, 0, 0, 0); }
static int64_t s_close(int64_t fd) { return win_syscall(3, fd, 0, 0, 0, 0, 0); }
static int64_t s_read(int64_t fd, void *b, int64_t n) { return win_syscall(0, fd, P(b), n, 0, 0, 0); }
static int64_t s_write(int64_t fd, const void *b, int64_t n) { return win_syscall(1, fd, P(b), n, 0, 0, 0); }
static int64_t s_stat(const char *p, void *st) { return win_syscall(4, P(p), P(st), 0, 0, 0, 0); }
static int64_t s_fstat(int64_t fd, void *st) { return win_syscall(5, fd, P(st), 0, 0, 0, 0); }
static int64_t s_lseek(int64_t fd, int64_t off, int64_t wh) { return win_syscall(8, fd, off, wh, 0, 0, 0); }
static int64_t s_pread(int64_t fd, void *b, int64_t n, int64_t off) { return win_syscall(17, fd, P(b), n, off, 0, 0); }
static int64_t s_pwrite(int64_t fd, const void *b, int64_t n, int64_t off)
{
    return win_syscall(18, fd, P(b), n, off, 0, 0);
}
static int64_t s_rename(const char *a, const char *b) { return win_syscall(82, P(a), P(b), 0, 0, 0, 0); }
static int64_t s_mkdir(const char *p) { return win_syscall(83, P(p), 0755, 0, 0, 0, 0); }
static int64_t s_rmdir(const char *p) { return win_syscall(84, P(p), 0, 0, 0, 0, 0); }
static int64_t s_unlink(const char *p) { return win_syscall(87, P(p), 0, 0, 0, 0, 0); }
static int64_t s_getdents(int64_t fd, void *b, int64_t n) { return win_syscall(217, fd, P(b), n, 0, 0, 0); }
static int64_t s_time(int64_t *t) { return win_syscall(201, P(t), 0, 0, 0, 0, 0); }
static int64_t s_clock(int64_t clk, int64_t *ts) { return win_syscall(228, clk, P(ts), 0, 0, 0, 0); }
static int64_t s_getrandom(void *b, int64_t n, int64_t fl) { return win_syscall(318, P(b), n, fl, 0, 0, 0); }
static int64_t s_mmap(int64_t addr, int64_t len, int64_t prot, int64_t fl, int64_t fd, int64_t off)
{
    return win_syscall(9, addr, len, prot, fl, fd, off);
}
static int64_t s_munmap(int64_t addr, int64_t len) { return win_syscall(11, addr, len, 0, 0, 0, 0); }
static int64_t s_yield(void) { return win_syscall(24, 0, 0, 0, 0, 0, 0); }
static int64_t s_socket(int64_t d, int64_t t, int64_t p) { return win_syscall(41, d, t, p, 0, 0, 0); }
static int64_t s_connect(int64_t fd, const void *a, int64_t n) { return win_syscall(42, fd, P(a), n, 0, 0, 0); }
static int64_t s_sendto(int64_t fd, const void *b, int64_t n, int64_t fl, const void *a, int64_t al)
{
    return win_syscall(44, fd, P(b), n, fl, P(a), al);
}
static int64_t s_recvfrom(int64_t fd, void *b, int64_t n, int64_t fl, void *a, uint32_t *al)
{
    return win_syscall(45, fd, P(b), n, fl, P(a), P(al));
}
static int64_t s_bind(int64_t fd, const void *a, int64_t n) { return win_syscall(49, fd, P(a), n, 0, 0, 0); }
static int64_t s_getsockname(int64_t fd, void *a, uint32_t *al) { return win_syscall(51, fd, P(a), P(al), 0, 0, 0); }
static int64_t s_setsockopt(int64_t fd, int64_t lvl, int64_t opt, const void *v, int64_t n)
{
    return win_syscall(54, fd, lvl, opt, P(v), n, 0);
}

/* ---- failure reporting ----------------------------------------------------------------------------- */
static char g_fail[512];
static int fail_at(int line, const char *what)
{
    snprintf(g_fail, sizeof g_fail, "line %d: %s", line, what);
    return 1;
}
static int fail_eq(int line, const char *expr, int64_t got, int64_t want)
{
    snprintf(g_fail, sizeof g_fail, "line %d: %s = %lld, expected %lld", line, expr, (long long)got, (long long)want);
    return 1;
}
#define CHECK(c)                                                                                                       \
    do {                                                                                                               \
        if (!(c))                                                                                                      \
            return fail_at(__LINE__, #c);                                                                              \
    } while (0)
#define CHECK_EQ(a, b)                                                                                                 \
    do {                                                                                                               \
        int64_t g_ = (int64_t)(a), w_ = (int64_t)(b);                                                                  \
        if (g_ != w_)                                                                                                  \
            return fail_eq(__LINE__, #a, g_, w_);                                                                      \
    } while (0)

/* ---- the scratch directory ------------------------------------------------------------------------- */
static char g_dir[64];            /* "/tmp/acwin-<pid>": what the syscalls see */
static WCHAR g_dir_w[2 * MAX_PATH]; /* the same directory for Win32, \\?\ prefixed */

static const char *pth(const char *fmt, ...) /* g_dir + "/" + formatted name, in one of 64 rotating buffers */
{
    static char ring[64][2048];
    static int next;
    char *b = ring[next++ & 63];
    int n = snprintf(b, 2048, "%s/", g_dir);
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(b + n, 2048 - (size_t)n, fmt, ap);
    va_end(ap);
    return b;
}

static void rm_rf_w(const WCHAR *dir)
{
    WCHAR pat[4 * MAX_PATH];
    swprintf(pat, 4 * MAX_PATH, L"%ls\\*", dir);
    WIN32_FIND_DATAW fd;
    HANDLE h = FindFirstFileW(pat, &fd);
    if (h != INVALID_HANDLE_VALUE) {
        do {
            if (!wcscmp(fd.cFileName, L".") || !wcscmp(fd.cFileName, L".."))
                continue;
            WCHAR full[4 * MAX_PATH];
            swprintf(full, 4 * MAX_PATH, L"%ls\\%ls", dir, fd.cFileName);
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                rm_rf_w(full);
            } else {
                SetFileAttributesW(full, FILE_ATTRIBUTE_NORMAL);
                DeleteFileW(full);
            }
        } while (FindNextFileW(h, &fd));
        FindClose(h);
    }
    RemoveDirectoryW(dir);
}

static int64_t now_unix(void)
{
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    return (int64_t)((t - 116444736000000000ULL) / 10000000ULL);
}

/* struct stat fields read from the raw bytes at the offsets the assembly uses */
static uint32_t st_mode(const unsigned char *b) { uint32_t v; memcpy(&v, b + 24, 4); return v; }
static int64_t st_size(const unsigned char *b) { int64_t v; memcpy(&v, b + 48, 8); return v; }
static int64_t st_mtime(const unsigned char *b) { int64_t v; memcpy(&v, b + 88, 8); return v; }

static int64_t write_file(const char *p, const void *d, int64_t n)
{
    int64_t fd = s_open(p, O_WCT);
    if (fd < 0)
        return fd;
    int64_t w = s_write(fd, d, n);
    s_close(fd);
    return w;
}

static int64_t read_file(const char *p, void *d, int64_t cap)
{
    int64_t fd = s_open(p, O_RD);
    if (fd < 0)
        return fd;
    int64_t r = s_read(fd, d, cap);
    s_close(fd);
    return r;
}

/* ===================================================================================================== */

static int t_unknown_syscall(void)
{
    CHECK_EQ(win_syscall(9999, 1, 2, 3, 4, 5, 6), -E_NOSYS);
    CHECK_EQ(win_syscall(-1, 0, 0, 0, 0, 0, 0), -E_NOSYS);
    CHECK_EQ(win_syscall(60, 0, 0, 0, 0, 0, 0), -E_NOSYS); /* exit: it must return, not end the process */
    CHECK_EQ(win_syscall(39, 0, 0, 0, 0, 0, 0), -E_NOSYS); /* getpid */
    return 0;
}

static int t_file_basic(void)
{
    const char *p = pth("basic.bin");
    char buf[64];
    int64_t fd = s_open(p, O_WCT);
    CHECK(fd >= 3);
    CHECK_EQ(s_write(fd, "hello world", 11), 11);
    CHECK_EQ(s_read(fd, buf, 4), -E_BADF); /* a write-only descriptor cannot read */
    CHECK_EQ(s_close(fd), 0);
    CHECK_EQ(s_close(fd), -E_BADF);

    fd = s_open(p, O_RD);
    CHECK(fd >= 3);
    CHECK_EQ(s_read(fd, buf, 5), 5);
    CHECK(!memcmp(buf, "hello", 5));
    CHECK_EQ(s_read(fd, buf, 64), 6);
    CHECK(!memcmp(buf, " world", 6));
    CHECK_EQ(s_read(fd, buf, 64), 0); /* end of file */
    CHECK_EQ(s_write(fd, "x", 1), -E_BADF); /* a read-only descriptor cannot write */
    CHECK_EQ(s_lseek(fd, 0, 0), 0);
    CHECK_EQ(s_pread(fd, buf, 5, 6), 5);
    CHECK(!memcmp(buf, "world", 5));
    CHECK_EQ(s_lseek(fd, 0, 1), 0); /* pread leaves the position alone */
    CHECK_EQ(s_read(fd, buf, 5), 5);
    CHECK(!memcmp(buf, "hello", 5));
    CHECK_EQ(s_lseek(fd, -5, 2), 6);
    CHECK_EQ(s_lseek(fd, 0, 2), 11);
    CHECK_EQ(s_lseek(fd, 3, 1), 14); /* seeking past the end is allowed */
    CHECK_EQ(s_lseek(fd, -1, 0), -E_INVAL);
    CHECK_EQ(s_lseek(fd, 0, 5), -E_INVAL);
    CHECK_EQ(s_pread(fd, buf, 4, 11), 0);
    CHECK_EQ(s_pread(fd, buf, 10, 8), 3); /* short read at the end */
    CHECK(!memcmp(buf, "rld", 3));
    CHECK_EQ(s_pread(fd, buf, 4, 100), 0);
    CHECK_EQ(s_pread(fd, buf, 4, -1), -E_INVAL);
    CHECK_EQ(s_pwrite(fd, "z", 1, 0), -E_BADF);

    unsigned char st[152];
    memset(st, 0xAA, sizeof st);
    CHECK_EQ(s_fstat(fd, st), 0);
    CHECK_EQ(st_size(st), 11);
    CHECK_EQ(st_mode(st) & 0xF000, 0x8000);
    for (int i = 144; i < 152; i++)
        CHECK(st[i] == 0xAA); /* struct stat is 144 bytes: nothing beyond */
    CHECK_EQ(s_close(fd), 0);

    memset(st, 0, sizeof st);
    CHECK_EQ(s_stat(p, st), 0);
    CHECK_EQ(st_size(st), 11);
    CHECK_EQ(st_mode(st) & 0xF000, 0x8000);
    int64_t d = st_mtime(st) - now_unix();
    CHECK(d > -300 && d < 300);
    CHECK_EQ(s_stat(pth("no-such-file"), st), -E_NOENT);
    CHECK_EQ(s_fstat(9, st), -E_BADF);
    return 0;
}

static int t_file_sparse_and_positions(void)
{
    const char *p = pth("sparse.bin");
    unsigned char buf[32];
    int64_t fd = s_open(p, O_RW | O_CRE | O_TRN);
    CHECK(fd >= 3);
    CHECK_EQ(s_pwrite(fd, "ABCD", 4, 8192), 4); /* beyond the end: a hole, like region.asm's pwrite_all */
    unsigned char st[144];
    CHECK_EQ(s_fstat(fd, st), 0);
    CHECK_EQ(st_size(st), 8196);
    CHECK_EQ(s_lseek(fd, 0, 1), 0); /* pwrite does not move the position */
    CHECK_EQ(s_pread(fd, buf, 16, 0), 16);
    for (int i = 0; i < 16; i++)
        CHECK(buf[i] == 0);
    CHECK_EQ(s_pread(fd, buf, 4, 8192), 4);
    CHECK(!memcmp(buf, "ABCD", 4));
    CHECK_EQ(s_write(fd, "xy", 2), 2);
    CHECK_EQ(s_lseek(fd, 0, 1), 2);
    CHECK_EQ(s_pwrite(fd, "Z", 1, 0), 1);
    CHECK_EQ(s_lseek(fd, 0, 1), 2); /* still 2 */
    CHECK_EQ(s_pread(fd, buf, 2, 0), 2);
    CHECK(!memcmp(buf, "Zy", 2));
    CHECK_EQ(s_close(fd), 0);

    /* file_patch: open an existing file write-only and overwrite the middle */
    fd = s_open(p, O_WR);
    CHECK(fd >= 3);
    CHECK_EQ(s_pwrite(fd, "QQ", 2, 100), 2);
    CHECK_EQ(s_close(fd), 0);
    CHECK_EQ(s_stat(p, st), 0);
    CHECK_EQ(st_size(st), 8196); /* not truncated, not extended */
    fd = s_open(p, O_RD);
    CHECK_EQ(s_pread(fd, buf, 4, 99), 4);
    CHECK(buf[0] == 0 && !memcmp(buf + 1, "QQ", 2) && buf[3] == 0);
    CHECK_EQ(s_close(fd), 0);
    return 0;
}

static int t_open_flags(void)
{
    unsigned char st[144];
    char buf[16];
    CHECK_EQ(s_open(pth("missing"), O_RD), -E_NOENT);
    CHECK_EQ(s_open(pth("nodir/x"), O_WCT), -E_NOENT);
    CHECK_EQ(s_open(pth("x"), 3), -E_INVAL); /* access mode 3 does not exist */

    const char *f = pth("flags.txt");
    CHECK_EQ(write_file(f, "A", 1), 1);
    CHECK_EQ(s_open(f, O_WR | O_CRE | O_EXC), -E_EXIST);
    const char *g = pth("excl.txt");
    int64_t fd = s_open(g, O_WR | O_CRE | O_EXC);
    CHECK(fd >= 3);
    CHECK_EQ(s_close(fd), 0);
    CHECK_EQ(s_open(g, O_WR | O_CRE | O_EXC), -E_EXIST);

    /* O_APPEND appends wherever the position is */
    fd = s_open(f, O_WR | O_APP);
    CHECK(fd >= 3);
    CHECK_EQ(s_lseek(fd, 0, 0), 0);
    CHECK_EQ(s_write(fd, "B", 1), 1);
    CHECK_EQ(s_close(fd), 0);
    CHECK_EQ(read_file(f, buf, 16), 2);
    CHECK(!memcmp(buf, "AB", 2));

    /* O_TRUNC on an existing file */
    fd = s_open(f, O_WR | O_TRN);
    CHECK(fd >= 3);
    CHECK_EQ(s_fstat(fd, st), 0);
    CHECK_EQ(st_size(st), 0);
    CHECK_EQ(s_close(fd), 0);

    /* O_CREAT without O_TRUNC keeps the content */
    CHECK_EQ(write_file(f, "keep", 4), 4);
    fd = s_open(f, O_RW | O_CRE);
    CHECK(fd >= 3);
    CHECK_EQ(s_read(fd, buf, 16), 4);
    CHECK(!memcmp(buf, "keep", 4));
    CHECK_EQ(s_close(fd), 0);

    /* directories */
    const char *d = pth("flagsdir");
    CHECK_EQ(s_mkdir(d), 0);
    CHECK_EQ(s_open(f, O_RD | O_DIR), -E_NOTDIR);
    CHECK_EQ(s_open(pth("missingdir"), O_RD | O_DIR), -E_NOENT);
    CHECK_EQ(s_open(d, O_WR), -E_ISDIR);
    CHECK_EQ(s_open(d, O_RW | O_CRE), -E_ISDIR);
    CHECK_EQ(s_open(d, O_RD | O_DIR | O_CRE), -E_INVAL);
    CHECK_EQ(s_open(d, O_WR | O_DIR), -E_ISDIR);
    fd = s_open(d, O_RD | O_DIR);
    CHECK(fd >= 3);
    CHECK_EQ(s_read(fd, buf, 4), -E_ISDIR);
    CHECK_EQ(s_write(fd, "x", 1), -E_BADF);
    CHECK_EQ(s_fstat(fd, st), 0);
    CHECK_EQ(st_mode(st) & 0xF000, 0x4000);
    CHECK_EQ(s_lseek(fd, 5, 0), -E_INVAL);
    CHECK_EQ(s_close(fd), 0);
    fd = s_open(d, O_RD); /* open(dir, O_RDONLY) works on Linux */
    CHECK(fd >= 3);
    CHECK_EQ(s_read(fd, buf, 4), -E_ISDIR);
    CHECK_EQ(s_close(fd), 0);

    /* bad descriptors */
    CHECK_EQ(s_read(-1, buf, 4), -E_BADF);
    CHECK_EQ(s_read(4000, buf, 4), -E_BADF);
    CHECK_EQ(s_read(1 << 20, buf, 4), -E_BADF);
    CHECK_EQ(s_write(4095, "x", 1), -E_BADF);
    CHECK_EQ(s_lseek(4000, 0, 0), -E_BADF);
    CHECK_EQ(s_close(-3), -E_BADF);
    CHECK_EQ(s_getdents(3999, buf, 16), -E_BADF);
    CHECK_EQ(s_open(NULL, O_RD), -E_FAULT);
    CHECK_EQ(s_open("", O_RD), -E_NOENT);
    /* the upper half of a register is not part of an int argument */
    fd = s_open(f, O_RD);
    CHECK(fd >= 3);
    CHECK_EQ(s_read(fd | (int64_t)0x5555555500000000LL, buf, 2), 2);
    CHECK_EQ(s_close(fd | (int64_t)0x1234000000000000LL), 0);
    return 0;
}

static int t_rename(void)
{
    char buf[32];
    unsigned char st[144];
    const char *a = pth("r.tmp"), *b = pth("r.dat");
    CHECK_EQ(write_file(b, "old-content-that-is-longer", 26), 26);
    CHECK_EQ(write_file(a, "new", 3), 3);
    CHECK_EQ(s_rename(a, b), 0); /* the atomic replace of file_write_atomic */
    CHECK_EQ(read_file(b, buf, 32), 3);
    CHECK(!memcmp(buf, "new", 3));
    CHECK_EQ(s_stat(a, st), -E_NOENT);
    CHECK_EQ(s_rename(a, b), -E_NOENT); /* source gone */
    CHECK_EQ(s_rename(pth("nosuch"), pth("whatever")), -E_NOENT);
    CHECK_EQ(s_rename(b, b), 0); /* onto itself */
    CHECK_EQ(s_rename(pth("nosuch"), pth("nosuch")), -E_NOENT);

    /* The target is open elsewhere (a reader): Windows may replace it or refuse while the reader holds it, which
     * the sharing mode cannot change for rename-over; what must hold is a clean EACCES and a working replace once
     * the reader is gone. */
    CHECK_EQ(write_file(a, "tmp2", 4), 4);
    int64_t rd = s_open(b, O_RD);
    CHECK(rd >= 3);
    int64_t rr = s_rename(a, b);
    CHECK(rr == 0 || rr == -13);
    CHECK_EQ(s_close(rd), 0);
    if (rr != 0)
        CHECK_EQ(s_rename(a, b), 0);
    CHECK_EQ(read_file(b, buf, 32), 4);
    CHECK(!memcmp(buf, "tmp2", 4));

    /* directories */
    const char *d = pth("rdir"), *d2 = pth("rdir2"), *d3 = pth("rdir3");
    CHECK_EQ(s_mkdir(d), 0);
    CHECK_EQ(s_mkdir(d2), 0);
    CHECK_EQ(s_mkdir(d3), 0);
    CHECK_EQ(s_rename(b, d), -E_ISDIR);  /* a file onto a directory */
    CHECK_EQ(s_rename(d, b), -E_NOTDIR); /* a directory onto a file */
    CHECK_EQ(write_file(pth("rdir2/inside"), "i", 1), 1);
    CHECK_EQ(s_rename(d, d2), -E_NOTEMPTY); /* onto a non-empty directory */
    CHECK_EQ(s_rename(d, d3), 0);           /* onto an empty one */
    CHECK_EQ(s_stat(d, st), -E_NOENT);
    CHECK_EQ(s_stat(d3, st), 0);
    CHECK_EQ(st_mode(st) & 0xF000, 0x4000);
    CHECK_EQ(s_rename(d3, pth("rdir4")), 0);
    CHECK_EQ(s_rename(d2, pth("rdir5")), 0);
    CHECK_EQ(read_file(pth("rdir5/inside"), buf, 32), 1); /* its content moved with it */
    return 0;
}

static int t_unlink(void)
{
    unsigned char st[144];
    const char *f = pth("u.txt");
    CHECK_EQ(write_file(f, "x", 1), 1);
    CHECK_EQ(s_unlink(f), 0);
    CHECK_EQ(s_stat(f, st), -E_NOENT);
    CHECK_EQ(s_unlink(f), -E_NOENT);
    const char *d = pth("udir");
    CHECK_EQ(s_mkdir(d), 0);
    CHECK_EQ(s_unlink(d), -E_ISDIR); /* rmdir_flat leaves a subdirectory entry with this error */
    CHECK_EQ(s_rmdir(d), 0);
    /* a read-only file goes too: unlink(2) does not care about that attribute */
    const char *r = pth("ro.txt");
    CHECK_EQ(write_file(r, "ro", 2), 2);
    WCHAR wr[4 * MAX_PATH];
    swprintf(wr, 4 * MAX_PATH, L"%ls\\ro.txt", g_dir_w);
    CHECK(SetFileAttributesW(wr, FILE_ATTRIBUTE_READONLY));
    CHECK_EQ(s_stat(r, st), 0);
    CHECK_EQ(st_mode(st) & 0222, 0); /* read-only shows in st_mode */
    CHECK_EQ(s_unlink(r), 0);
    CHECK_EQ(s_stat(r, st), -E_NOENT);
    CHECK_EQ(s_unlink(pth("nodir/x")), -E_NOENT);
    return 0;
}

static int t_mkdir_rmdir(void)
{
    unsigned char st[144];
    char buf[8];
    const char *d = pth("md");
    CHECK_EQ(s_mkdir(d), 0);
    CHECK_EQ(s_mkdir(d), -E_EXIST);
    CHECK_EQ(s_stat(d, st), 0);
    CHECK_EQ(st_mode(st) & 0xF000, 0x4000);
    CHECK_EQ(s_mkdir(pth("md/x/y")), -E_NOENT); /* a missing parent */
    CHECK_EQ(s_mkdir(pth("md/trail/")), 0);     /* a trailing slash */
    CHECK_EQ(s_rmdir(pth("md/trail")), 0);
    CHECK_EQ(write_file(pth("md/f"), "f", 1), 1);
    CHECK_EQ(s_mkdir(pth("md/f")), -E_EXIST); /* an existing file */
    CHECK_EQ(s_rmdir(d), -E_NOTEMPTY);
    CHECK_EQ(s_rmdir(pth("md/f")), -E_NOTDIR); /* a file */
    CHECK_EQ(s_unlink(pth("md/f")), 0);
    CHECK_EQ(s_rmdir(d), 0);
    CHECK_EQ(s_rmdir(d), -E_NOENT);
    CHECK_EQ(s_stat(d, st), -E_NOENT);
    CHECK_EQ(s_mkdir(""), -E_NOENT);
    CHECK_EQ(s_rmdir(""), -E_NOENT);

    /* mkdir_p: every prefix of the path, EEXIST for the ones that are there, mixed separators */
    char p[600];
    snprintf(p, sizeof p, "%s/mp", g_dir);
    CHECK_EQ(s_mkdir(p), 0);
    snprintf(p, sizeof p, "%s/mp/a", g_dir);
    CHECK_EQ(s_mkdir(p), 0);
    snprintf(p, sizeof p, "%s/mp/a\\b", g_dir);
    CHECK_EQ(s_mkdir(p), 0);
    snprintf(p, sizeof p, "%s\\mp/a\\b/c", g_dir);
    CHECK_EQ(s_mkdir(p), 0);
    CHECK_EQ(write_file(pth("mp/a/b/c/leaf"), "L", 1), 1);
    CHECK_EQ(read_file(pth("mp\\a\\b\\c\\leaf"), buf, 8), 1);

    /* the existing prefixes of an absolute Windows path report EEXIST, not EACCES (mkdir_p relies on it) */
    WCHAR tw[MAX_PATH];
    GetTempPathW(MAX_PATH, tw);
    char tu[3 * MAX_PATH];
    CHECK(WideCharToMultiByte(CP_UTF8, 0, tw, -1, tu, sizeof tu, NULL, NULL) > 0);
    size_t n = strlen(tu);
    CHECK(n > 3 && tu[1] == ':');
    char drv[4] = {tu[0], ':', 0, 0}, drv_slash[4] = {tu[0], ':', '/', 0};
    CHECK_EQ(s_mkdir(drv), -E_EXIST);       /* "X:" and "X:/": what mkdir_p starts with on a drive path */
    CHECK_EQ(s_mkdir(drv_slash), -E_EXIST);
    for (size_t i = 3; i + 1 < n; i++) {
        if (tu[i] == '\\' || tu[i] == '/') {
            char c = tu[i];
            tu[i] = 0;
            CHECK_EQ(s_mkdir(tu), -E_EXIST);
            tu[i] = c;
        }
    }
    return 0;
}

typedef struct {
    char name[300];
    int type;
    unsigned reclen;
    uint64_t ino, off;
} DENT;

/* Parses a getdents64 buffer; returns the number of records or -1 on a malformed one. */
static int parse_dents(const unsigned char *buf, int64_t n, DENT *out, int max)
{
    int c = 0;
    int64_t o = 0;
    while (o < n) {
        uint16_t rl;
        memcpy(&rl, buf + o + 16, 2);
        if (rl < 24 || (rl & 7) || o + rl > n || c >= max)
            return -1;
        size_t nl = strlen((const char *)buf + o + 19);
        if ((((19 + nl + 1) + 7) & ~(size_t)7) != rl) /* exactly the kernel's record size */
            return -1;
        for (size_t i = 19 + nl + 1; i < rl; i++)
            if (buf[o + (int64_t)i] != 0) /* zero padding */
                return -1;
        DENT *d = &out[c++];
        memcpy(d->name, buf + o + 19, nl + 1);
        d->type = buf[o + 18];
        d->reclen = rl;
        memcpy(&d->ino, buf + o, 8);
        memcpy(&d->off, buf + o + 8, 8);
        o += rl;
    }
    return o == n ? c : -1;
}

static int find_dent(const DENT *d, int n, const char *name)
{
    int found = -1;
    for (int i = 0; i < n; i++)
        if (!strcmp(d[i].name, name)) {
            if (found >= 0)
                return -2; /* twice */
            found = i;
        }
    return found;
}

static int t_getdents(void)
{
    const char *dir = pth("gd");
    static const char utf8[] = "\xc3\xa9\xe2\x98\x83.txt"; /* e-acute, snowman */
    CHECK_EQ(s_mkdir(dir), 0);
    CHECK_EQ(write_file(pth("gd/a.txt"), "1", 1), 1);
    CHECK_EQ(write_file(pth("gd/bb.txt"), "22", 2), 2);
    CHECK_EQ(write_file(pth("gd/ccc.txt"), "333", 3), 3);
    CHECK_EQ(s_mkdir(pth("gd/sub")), 0);
    CHECK_EQ(write_file(pth("gd/%s", utf8), "u", 1), 1);

    int64_t fd = s_open(dir, O_RD | O_DIR);
    CHECK(fd >= 3);
    unsigned char buf[4096];
    DENT ents[16];
    int64_t n = s_getdents(fd, buf, sizeof buf);
    CHECK(n > 0);
    int cnt = parse_dents(buf, n, ents, 16);
    CHECK_EQ(cnt, 7); /* . .. a.txt bb.txt ccc.txt sub and the UTF-8 name */
    const char *want[] = {".", "..", "a.txt", "bb.txt", "ccc.txt", "sub", utf8};
    for (int i = 0; i < 7; i++) {
        int k = find_dent(ents, cnt, want[i]);
        CHECK(k >= 0);
        int isdir = !strcmp(want[i], ".") || !strcmp(want[i], "..") || !strcmp(want[i], "sub");
        CHECK_EQ(ents[k].type, isdir ? 4 : 8); /* DT_DIR / DT_REG */
        CHECK(ents[k].ino != 0);
    }
    CHECK_EQ(find_dent(ents, cnt, ".") < find_dent(ents, cnt, "a.txt"), 1);   /* "." and ".." come first */
    CHECK_EQ(find_dent(ents, cnt, "..") < find_dent(ents, cnt, "a.txt"), 1);
    CHECK_EQ(s_getdents(fd, buf, sizeof buf), 0); /* the end, and it stays the end */
    CHECK_EQ(s_getdents(fd, buf, sizeof buf), 0);

    /* rewinddir: lseek(fd, 0, SEEK_SET) */
    CHECK_EQ(s_lseek(fd, 0, 0), 0);
    n = s_getdents(fd, buf, sizeof buf);
    CHECK(n > 0);
    CHECK_EQ(parse_dents(buf, n, ents, 16), 7);
    CHECK_EQ(s_getdents(fd, buf, sizeof buf), 0);

    /* a buffer that cannot hold one record: EINVAL, and nothing is lost */
    CHECK_EQ(s_lseek(fd, 0, 0), 0);
    CHECK_EQ(s_getdents(fd, buf, 16), -E_INVAL);
    CHECK_EQ(s_getdents(fd, buf, 8), -E_INVAL);

    /* one record at a time (40 bytes: 24 + 24 does not fit, the UTF-8 record is 32): every entry exactly once */
    int seen[7] = {0}, total = 0;
    for (int guard = 0; guard < 20; guard++) {
        n = s_getdents(fd, buf, 40);
        CHECK(n >= 0);
        if (n == 0)
            break;
        DENT e1[2];
        int c1 = parse_dents(buf, n, e1, 2);
        CHECK_EQ(c1, 1);
        total += c1;
        for (int i = 0; i < 7; i++)
            if (!strcmp(e1[0].name, want[i]))
                seen[i]++;
    }
    CHECK_EQ(total, 7);
    for (int i = 0; i < 7; i++)
        CHECK_EQ(seen[i], 1);

    CHECK_EQ(s_write(fd, "x", 1), -E_BADF);
    CHECK_EQ(s_close(fd), 0);

    /* getdents64 on something that is not a directory */
    fd = s_open(pth("gd/a.txt"), O_RD);
    CHECK(fd >= 3);
    CHECK_EQ(s_getdents(fd, buf, sizeof buf), -E_NOTDIR);
    CHECK_EQ(s_close(fd), 0);
    return 0;
}

static int t_getdents_many(void)
{
    char dir[512];
    snprintf(dir, sizeof dir, "%s/many", g_dir);
    CHECK_EQ(s_mkdir(dir), 0);
    for (int i = 0; i < 300; i++)
        CHECK_EQ(write_file(pth("many/m%03d", i), "m", 1), 1);
    int64_t fd = s_open(dir, O_RD | O_DIR);
    CHECK(fd >= 3);
    static unsigned char buf[1024];
    static unsigned char seen[300];
    int dots = 0, files = 0;
    for (int guard = 0; guard < 1000; guard++) {
        int64_t n = s_getdents(fd, buf, sizeof buf);
        CHECK(n >= 0);
        if (n == 0)
            break;
        DENT e[64];
        int c = parse_dents(buf, n, e, 64);
        CHECK(c > 0);
        for (int i = 0; i < c; i++) {
            if (!strcmp(e[i].name, ".") || !strcmp(e[i].name, "..")) {
                dots++;
                continue;
            }
            int k = -1;
            CHECK(sscanf(e[i].name, "m%3d", &k) == 1 && k >= 0 && k < 300);
            seen[k]++;
            files++;
        }
    }
    CHECK_EQ(dots, 2);
    CHECK_EQ(files, 300);
    for (int i = 0; i < 300; i++)
        CHECK_EQ(seen[i], 1);
    CHECK_EQ(s_close(fd), 0);
    return 0;
}

/* The way rmdir_flat works: unlink every entry while the directory is open and being read, close, rmdir. */
static int t_rmdir_flat_pattern(void)
{
    char dir[512];
    snprintf(dir, sizeof dir, "%s/flat", g_dir);
    CHECK_EQ(s_mkdir(dir), 0);
    for (int i = 0; i < 60; i++)
        CHECK_EQ(write_file(pth("flat/f%02d", i), "x", 1), 1);
    CHECK_EQ(s_mkdir(pth("flat/sub")), 0);
    int64_t fd = s_open(dir, O_RD | O_DIR);
    CHECK(fd >= 3);
    unsigned char buf[512];
    int unlinked = 0, subdir_errs = 0;
    for (int guard = 0; guard < 1000; guard++) {
        int64_t n = s_getdents(fd, buf, sizeof buf);
        CHECK(n >= 0);
        if (n == 0)
            break;
        DENT e[32];
        int c = parse_dents(buf, n, e, 32);
        CHECK(c > 0);
        for (int i = 0; i < c; i++) {
            if (!strcmp(e[i].name, ".") || !strcmp(e[i].name, ".."))
                continue;
            int64_t r = s_unlink(pth("flat/%s", e[i].name));
            if (!strcmp(e[i].name, "sub")) {
                CHECK_EQ(r, -E_ISDIR);
                subdir_errs++;
            } else {
                CHECK_EQ(r, 0);
                unlinked++;
            }
        }
    }
    CHECK_EQ(unlinked, 60);
    CHECK_EQ(subdir_errs, 1);
    CHECK_EQ(s_close(fd), 0);
    CHECK_EQ(s_rmdir(pth("flat/sub")), 0);
    CHECK_EQ(s_rmdir(dir), 0);
    return 0;
}

static int t_time_clock(void)
{
    int64_t t = 0;
    int64_t r = s_time(&t);
    CHECK(r > 1577836800 && r < 4102444800LL); /* 2020 .. 2100 */
    CHECK_EQ(t, r);
    int64_t t2 = s_time(NULL); /* a NULL pointer is allowed; the clock does not run backwards */
    CHECK(t2 >= r && t2 <= r + 2);
    int64_t d = r - now_unix();
    CHECK(d > -3 && d < 3);

    int64_t ts[2] = {-1, -1};
    CHECK_EQ(s_clock(0, ts), 0);
    CHECK(ts[1] >= 0 && ts[1] < 1000000000);
    d = ts[0] - now_unix();
    CHECK(d > -3 && d < 3);
    int64_t last_s = 0, last_ns = 0;
    CHECK_EQ(s_clock(1, ts), 0);
    last_s = ts[0];
    last_ns = ts[1];
    CHECK(last_ns >= 0 && last_ns < 1000000000);
    for (int i = 0; i < 20000; i++) {
        CHECK_EQ(s_clock(1, ts), 0);
        CHECK(ts[1] >= 0 && ts[1] < 1000000000);
        CHECK(ts[0] > last_s || (ts[0] == last_s && ts[1] >= last_ns)); /* monotonic */
        last_s = ts[0];
        last_ns = ts[1];
    }
    int64_t a[2], b[2];
    CHECK_EQ(s_clock(1, a), 0);
    Sleep(60);
    CHECK_EQ(s_clock(1, b), 0);
    int64_t ms = (b[0] - a[0]) * 1000 + (b[1] - a[1]) / 1000000;
    CHECK(ms >= 40 && ms < 5000); /* it advanced by about the sleep */
    CHECK_EQ(s_clock(4, a), 0);   /* CLOCK_MONOTONIC_RAW */
    CHECK_EQ(s_clock(7, a), 0);   /* CLOCK_BOOTTIME */
    CHECK_EQ(s_clock(99, a), -E_INVAL);
    CHECK_EQ(s_clock(1, NULL), -E_FAULT);
    return 0;
}

static int t_getrandom(void)
{
    unsigned char a[32], b[32], z[32];
    memset(a, 0, sizeof a);
    memset(b, 0, sizeof b);
    memset(z, 0, sizeof z);
    CHECK_EQ(s_getrandom(a, 32, 0), 32);
    CHECK_EQ(s_getrandom(b, 32, 0), 32);
    CHECK(memcmp(a, z, 32) != 0);
    CHECK(memcmp(a, b, 32) != 0);
    uint32_t w = 0;
    CHECK_EQ(s_getrandom(&w, 4, 0), 4); /* what ep_rand32 asks for */
    CHECK_EQ(s_getrandom(a, 0, 0), 0);
    CHECK_EQ(s_getrandom(a, 8, 0xFF), -E_INVAL);
    CHECK_EQ(s_getrandom(a, 8, 1), 8); /* GRND_NONBLOCK */
    unsigned char *big = (unsigned char *)malloc(1 << 20);
    CHECK(big != NULL);
    memset(big, 0, 1 << 20);
    CHECK_EQ(s_getrandom(big, 1 << 20, 0), 1 << 20);
    int nonzero = 0;
    for (int i = 0; i < (1 << 20); i++)
        nonzero += big[i] != 0;
    free(big);
    CHECK(nonzero > (1 << 20) * 9 / 10); /* about 255/256 of random bytes are non-zero */
    return 0;
}

static int t_mmap_munmap(void)
{
    int64_t len = 100000;
    int64_t p = s_mmap(0, len, 3, 0x22, -1, 0); /* PROT_READ|WRITE, MAP_PRIVATE|MAP_ANONYMOUS, as test_net.asm does */
    CHECK(p > 0 && (p & 4095) == 0);
    unsigned char *m = (unsigned char *)(intptr_t)p;
    for (int64_t i = 0; i < len; i++)
        CHECK(m[i] == 0); /* zeroed */
    memset(m, 0x5A, (size_t)len);
    CHECK(m[len - 1] == 0x5A);
    CHECK_EQ(s_munmap(p, len), 0);
    CHECK_EQ(s_munmap(p, len), 0); /* unmapping what is not mapped is not an error */

    CHECK_EQ(s_mmap(0, 0, 3, 0x22, -1, 0), -E_INVAL);          /* length 0 */
    CHECK_EQ(s_mmap(0, 4096, 3, 0x20, -1, 0), -E_INVAL);       /* neither SHARED nor PRIVATE */
    CHECK_EQ(s_mmap(0, 4096, 3, 0x22, 7, 0), -E_NODEV);        /* file mappings are not emulated */
    CHECK_EQ(s_mmap(0, 4096, 3, 0x02, -1, 0), -E_NODEV);       /* not anonymous */
    CHECK_EQ(s_munmap(p + 1, 4096), -E_INVAL);                 /* unaligned */
    CHECK_EQ(s_munmap(p, 0), -E_INVAL);

    /* part of a mapping: the rest stays usable, then the whole goes */
    int64_t q = s_mmap(0, 16 * 4096, 3, 0x22, -1, 0);
    CHECK(q > 0);
    unsigned char *mq = (unsigned char *)(intptr_t)q;
    mq[0] = 1;
    mq[15 * 4096] = 2;
    CHECK_EQ(s_munmap(q + 4 * 4096, 4 * 4096), 0);
    CHECK(mq[0] == 1 && mq[15 * 4096] == 2 && mq[3 * 4096] == 0);
    CHECK_EQ(s_munmap(q, 16 * 4096), 0);

    /* read-only protection is honoured */
    int64_t r = s_mmap(0, 4096, 1, 0x22, -1, 0);
    CHECK(r > 0);
    MEMORY_BASIC_INFORMATION mbi;
    CHECK(VirtualQuery((void *)(intptr_t)r, &mbi, sizeof mbi) != 0);
    CHECK(mbi.Protect == PAGE_READONLY);
    CHECK_EQ(s_munmap(r, 4096), 0);
    return 0;
}

static int t_sched_yield(void)
{
    for (int i = 0; i < 100; i++)
        CHECK_EQ(s_yield(), 0);
    return 0;
}

/* ---- sockets --------------------------------------------------------------------------------------- */
#define SOCK_NB_DGRAM (2 | 0x800 | 0x80000) /* SOCK_DGRAM | SOCK_NONBLOCK | SOCK_CLOEXEC */

static struct sockaddr_in sin_loop(uint16_t port_be)
{
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_port = port_be;
    a.sin_addr.s_addr = htonl(0x7F000001);
    return a;
}

/* recvfrom, retried while nothing has arrived yet (loopback delivery is asynchronous on some systems) */
static int64_t recv_wait(int64_t fd, void *b, int64_t n, int64_t fl, struct sockaddr_in *from)
{
    for (int i = 0; i < 1000; i++) {
        uint32_t fl_len = sizeof *from;
        int64_t r = s_recvfrom(fd, b, n, fl, from, &fl_len);
        if (r != -E_AGAIN)
            return r;
        Sleep(2);
    }
    return -E_AGAIN;
}

static int t_sockets_udp(void)
{
    struct sockaddr_in sa, got, from;
    uint32_t sl;
    char buf[2048];

    int64_t a = s_socket(2, SOCK_NB_DGRAM, 0);
    CHECK(a >= 3);

    /* an unbound socket answers 0.0.0.0:0, as on Linux */
    memset(&got, 0xAA, sizeof got);
    sl = sizeof got;
    CHECK_EQ(s_getsockname(a, &got, &sl), 0);
    CHECK_EQ(sl, 16);
    CHECK(got.sin_family == AF_INET && got.sin_port == 0 && got.sin_addr.s_addr == 0);

    /* bind to port 0, read the port back */
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    CHECK_EQ(s_bind(a, &sa, sizeof sa), 0);
    memset(&got, 0xAA, sizeof got);
    sl = sizeof got;
    CHECK_EQ(s_getsockname(a, &got, &sl), 0);
    CHECK_EQ(sl, 16);
    CHECK(got.sin_family == AF_INET && got.sin_port != 0 && got.sin_addr.s_addr == 0);
    uint16_t port_a = got.sin_port;

    /* nothing has been sent: a non-blocking recvfrom says EAGAIN */
    sl = sizeof from;
    CHECK_EQ(s_recvfrom(a, buf, sizeof buf, 0, &from, &sl), -E_AGAIN);

    /* the other socket sends; the datagram arrives with the right source */
    int64_t b = s_socket(2, 2, 0);
    CHECK(b >= 3 && b != a);
    struct sockaddr_in dst = sin_loop(port_a);
    CHECK_EQ(s_sendto(b, "hello", 5, 0, &dst, sizeof dst), 5);
    memset(&from, 0, sizeof from);
    CHECK_EQ(recv_wait(a, buf, sizeof buf, 0, &from), 5);
    CHECK(!memcmp(buf, "hello", 5));
    CHECK(from.sin_family == AF_INET && from.sin_addr.s_addr == htonl(0x7F000001));
    sl = sizeof got;
    CHECK_EQ(s_getsockname(b, &got, &sl), 0);
    CHECK(got.sin_port != 0 && got.sin_port == from.sin_port); /* b got an ephemeral port by sending */
    uint16_t port_b = got.sin_port;
    CHECK_EQ(s_recvfrom(a, buf, sizeof buf, 0, &from, &(uint32_t){16}), -E_AGAIN);

    /* the source address is optional */
    CHECK_EQ(s_sendto(b, "no-addr", 7, 0, &dst, sizeof dst), 7);
    int64_t r = -E_AGAIN;
    for (int i = 0; i < 1000 && r == -E_AGAIN; i++) {
        r = win_syscall(45, a, P(buf), sizeof buf, 0, 0, 0);
        if (r == -E_AGAIN)
            Sleep(2);
    }
    CHECK_EQ(r, 7);

    /* a datagram larger than the buffer is cut, like Linux without MSG_TRUNC */
    char big[100];
    memset(big, 'B', sizeof big);
    CHECK_EQ(s_sendto(b, big, sizeof big, 0, &dst, sizeof dst), 100);
    CHECK_EQ(recv_wait(a, buf, 10, 0, &from), 10);
    CHECK(!memcmp(buf, big, 10));
    CHECK_EQ(s_recvfrom(a, buf, sizeof buf, 0, &from, &(uint32_t){16}), -E_AGAIN); /* the rest is gone */

    /* MSG_PEEK leaves the datagram in the queue */
    CHECK_EQ(s_sendto(b, "peek!", 5, 0, &dst, sizeof dst), 5);
    CHECK_EQ(recv_wait(a, buf, sizeof buf, 2, &from), 5);
    CHECK_EQ(recv_wait(a, buf, sizeof buf, 0, &from), 5);
    CHECK(!memcmp(buf, "peek!", 5));
    CHECK_EQ(s_recvfrom(a, buf, sizeof buf, 0, &from, &(uint32_t){16}), -E_AGAIN);

    /* a short address buffer is filled partly and the real length comes back */
    CHECK_EQ(s_sendto(b, "short", 5, 0, &dst, sizeof dst), 5);
    unsigned char ab[16];
    memset(ab, 0xEE, sizeof ab);
    sl = 8;
    r = -E_AGAIN;
    for (int i = 0; i < 1000 && r == -E_AGAIN; i++) {
        sl = 8;
        r = s_recvfrom(a, buf, sizeof buf, 0, ab, &sl);
        if (r == -E_AGAIN)
            Sleep(2);
    }
    CHECK_EQ(r, 5);
    CHECK_EQ(sl, 16);
    CHECK(ab[0] == 2 && ab[8] == 0xEE); /* AF_INET in the first 8 bytes, the rest untouched */

    /* an empty datagram is a datagram */
    CHECK_EQ(s_sendto(b, NULL, 0, 0, &dst, sizeof dst), 0);
    CHECK_EQ(recv_wait(a, buf, sizeof buf, 0, &from), 0);

    /* a reply goes back to the source address of the first one */
    struct sockaddr_in back = sin_loop(port_b);
    CHECK_EQ(s_sendto(a, "pong", 4, 0, &back, sizeof back), 4);
    CHECK_EQ(s_sendto(b, "ping", 4, 0, &dst, sizeof dst), 4);
    CHECK_EQ(recv_wait(a, buf, sizeof buf, 0, &from), 4);
    CHECK(from.sin_port == port_b);
    /* b is a blocking socket; MSG_DONTWAIT (0x40) makes one recv non-blocking */
    int64_t bd = -E_AGAIN;
    for (int i = 0; i < 1000 && bd == -E_AGAIN; i++) {
        bd = s_recvfrom(b, buf, sizeof buf, 0x40, &from, &(uint32_t){16});
        if (bd == -E_AGAIN)
            Sleep(2);
    }
    CHECK_EQ(bd, 4);
    CHECK(!memcmp(buf, "pong", 4));
    CHECK_EQ(s_recvfrom(b, buf, sizeof buf, 0x40, &from, &(uint32_t){16}), -E_AGAIN); /* nothing, and it did not block */

    /* errors */
    struct sockaddr_in badfam = dst;
    badfam.sin_family = 1;
    CHECK_EQ(s_sendto(b, "x", 1, 0, &badfam, sizeof badfam), -E_AFNOSUPPORT);
    CHECK_EQ(s_sendto(b, "x", 1, 0, &dst, 8), -E_INVAL);
    CHECK_EQ(s_bind(b, &badfam, sizeof badfam), -E_AFNOSUPPORT);
    CHECK_EQ(s_bind(b, &dst, 8), -E_INVAL);
    CHECK_EQ(s_sendto(b, "x", 1, 0, &dst, sizeof dst) , 1); /* still fine */

    CHECK_EQ(s_close(a), 0);
    CHECK_EQ(s_close(b), 0);
    CHECK_EQ(s_close(a), -E_BADF);
    CHECK_EQ(s_recvfrom(a, buf, sizeof buf, 0, &from, &(uint32_t){16}), -E_BADF);
    CHECK_EQ(s_sendto(a, "x", 1, 0, &dst, sizeof dst), -E_BADF);
    return 0;
}

/* Two sockets cannot share a port, and a port nobody listens on does not break the receiving socket. */
static int t_sockets_bind_conflict_and_connreset(void)
{
    struct sockaddr_in sa, got;
    uint32_t sl;
    char buf[64], from_buf[16];
    int64_t a = s_socket(2, SOCK_NB_DGRAM, 0);
    CHECK(a >= 3);
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    CHECK_EQ(s_bind(a, &sa, sizeof sa), 0);
    sl = sizeof got;
    CHECK_EQ(s_getsockname(a, &got, &sl), 0);
    uint16_t port_a = got.sin_port;

    int64_t c = s_socket(2, SOCK_NB_DGRAM, 0);
    CHECK(c >= 3);
    sa.sin_port = port_a;
    CHECK_EQ(s_bind(c, &sa, sizeof sa), -98); /* EADDRINUSE: the host's "try the next port" relies on it */
    CHECK_EQ(s_close(c), 0);

    /* A port that nothing listens on: bind a socket, learn its port, close it */
    int64_t d = s_socket(2, SOCK_NB_DGRAM, 0);
    CHECK(d >= 3);
    sa.sin_port = 0;
    CHECK_EQ(s_bind(d, &sa, sizeof sa), 0);
    sl = sizeof got;
    CHECK_EQ(s_getsockname(d, &got, &sl), 0);
    uint16_t dead_port = got.sin_port;
    CHECK_EQ(s_close(d), 0);

    /* Datagrams to the dead port provoke ICMP port unreachable. On Windows that used to turn the next recvfrom
     * into WSAECONNRESET (-104): the ioctl in socket() must have switched it off. */
    struct sockaddr_in dead = sin_loop(dead_port);
    for (int i = 0; i < 5; i++) {
        CHECK_EQ(s_sendto(a, "x", 1, 0, &dead, sizeof dead), 1);
        Sleep(40);
        sl = 16;
        int64_t r = s_recvfrom(a, buf, sizeof buf, 0, from_buf, &sl);
        CHECK(r != -E_CONNRESET);
        CHECK_EQ(r, -E_AGAIN);
    }
    /* and the socket still works afterwards */
    int64_t b = s_socket(2, 2, 0);
    CHECK(b >= 3);
    struct sockaddr_in dst = sin_loop(port_a);
    CHECK_EQ(s_sendto(b, "alive", 5, 0, &dst, sizeof dst), 5);
    struct sockaddr_in from;
    CHECK_EQ(recv_wait(a, buf, sizeof buf, 0, &from), 5);
    CHECK_EQ(s_close(a), 0);
    CHECK_EQ(s_close(b), 0);
    return 0;
}

static int t_sockets_options_and_misc(void)
{
    struct sockaddr_in sa, got;
    uint32_t sl;
    char buf[64];
    int one = 1, mib = 1 << 20;

    /* net_ep_open: the buffers, before bind */
    int64_t s = s_socket(2, SOCK_NB_DGRAM, 0);
    CHECK(s >= 3);
    CHECK_EQ(s_setsockopt(s, 1, 8, &mib, 4), 0); /* SOL_SOCKET, SO_RCVBUF */
    CHECK_EQ(s_setsockopt(s, 1, 7, &mib, 4), 0); /* SO_SNDBUF */
    CHECK_EQ(s_setsockopt(s, 1, 2, &one, 4), 0); /* SO_REUSEADDR */
    CHECK_EQ(s_setsockopt(s, 1, 6, &one, 4), 0); /* SO_BROADCAST */
    int lg[2] = {1, 2};
    CHECK_EQ(s_setsockopt(s, 1, 13, lg, 8), 0); /* SO_LINGER on a datagram socket: accepted (Winsock refuses it) */
    CHECK_EQ(s_setsockopt(s, 1, 13, lg, 4), -E_INVAL); /* ... but the option length is checked */
    CHECK_EQ(s_setsockopt(s, 1, 9, &one, 4), 0);       /* SO_KEEPALIVE */
    CHECK_EQ(s_setsockopt(s, 1, 10, &one, 4), 0);      /* SO_OOBINLINE */
    CHECK_EQ(s_setsockopt(s, 1, 12, &one, 4), 0); /* SO_PRIORITY: ignored */
    CHECK_EQ(s_setsockopt(s, 1, 999, &one, 4), -E_NOPROTOOPT);
    CHECK_EQ(s_setsockopt(s, 77, 1, &one, 4), -E_NOPROTOOPT);
    CHECK_EQ(s_setsockopt(s, 1, 8, &mib, 2), -E_INVAL); /* too short */
    CHECK_EQ(s_setsockopt(s, 1, 8, NULL, 4), -E_FAULT);
    CHECK_EQ(s_setsockopt(s, 0, 2, &one, 4), 0);        /* IPPROTO_IP, IP_TTL */
    CHECK_EQ(s_setsockopt(999, 1, 8, &mib, 4), -E_BADF);
    int64_t f = s_open(pth("sockopt-file"), O_WCT);
    CHECK(f >= 3);
    CHECK_EQ(s_setsockopt(f, 1, 8, &mib, 4), -E_NOTSOCK);
    CHECK_EQ(s_bind(f, &sa, 16), -E_NOTSOCK);
    CHECK_EQ(s_sendto(f, "x", 1, 0, &sa, 16), -E_NOTSOCK);
    CHECK_EQ(s_getsockname(f, &sa, &(uint32_t){16}), -E_NOTSOCK);
    CHECK_EQ(s_close(f), 0);
    memset(&sa, 0, sizeof sa);
    sa.sin_family = AF_INET;
    CHECK_EQ(s_bind(s, &sa, sizeof sa), 0);
    CHECK_EQ(s_close(s), 0);

    /* SO_RCVTIMEO on a blocking socket: recvfrom gives up with EAGAIN after about the timeout */
    int64_t t = s_socket(2, 2, 0);
    CHECK(t >= 3);
    CHECK_EQ(s_bind(t, &sa, sizeof sa), 0);
    int64_t tv[2] = {0, 150000};
    CHECK_EQ(s_setsockopt(t, 1, 20, tv, 16), 0);
    DWORD t0 = GetTickCount();
    sl = 16;
    CHECK_EQ(s_recvfrom(t, buf, sizeof buf, 0, &got, &sl), -E_AGAIN);
    DWORD el = GetTickCount() - t0;
    CHECK(el >= 100 && el < 3000);
    int64_t badtv[2] = {-1, 0};
    CHECK_EQ(s_setsockopt(t, 1, 20, badtv, 16), -E_INVAL);
    CHECK_EQ(s_close(t), 0);

    /* socket() argument checks */
    CHECK_EQ(s_socket(1, 2, 0), -E_AFNOSUPPORT);       /* AF_UNIX */
    CHECK_EQ(s_socket(2, 3, 0), -E_SOCKTNOSUPPORT);    /* SOCK_RAW */
    CHECK_EQ(s_socket(2, 2, 6), -E_PROTONOSUPPORT);    /* UDP socket with IPPROTO_TCP */
    CHECK_EQ(s_socket(2, 2 | 0x1000, 0), -E_INVAL);    /* a flag Linux does not know */
    int64_t u = s_socket(2, 2, 17);
    CHECK(u >= 3);
    CHECK_EQ(s_close(u), 0);
    int64_t tcp = s_socket(2, 1 | 0x80000, 0);
    CHECK(tcp >= 3);
    unsigned char st[144];
    CHECK_EQ(s_fstat(tcp, st), 0);
    CHECK_EQ(st_mode(st) & 0xF000, 0xC000); /* S_IFSOCK */
    CHECK_EQ(s_lseek(tcp, 0, 0), -29);      /* ESPIPE */
    CHECK_EQ(s_pread(tcp, buf, 4, 0), -29);
    int zero_one[2] = {1, 2};
    CHECK_EQ(s_setsockopt(tcp, 1, 9, &one, 4), 0);          /* SO_KEEPALIVE: a real Winsock option on TCP */
    CHECK_EQ(s_setsockopt(tcp, 6, 1, &one, 4), 0);          /* TCP_NODELAY */
    CHECK_EQ(s_setsockopt(tcp, 1, 13, zero_one, 8), 0);     /* SO_LINGER: struct linger converted */
    CHECK_EQ(s_setsockopt(tcp, 1, 7, &mib, 4), 0);          /* SO_SNDBUF */
    (void)s_setsockopt(tcp, 0, 1, &one, 4); /* IP_TOS: some systems take it, some refuse; either is fine */
    CHECK_EQ(s_close(tcp), 0);

    /* net_local_ip: a UDP socket connected to a probe (nothing is sent), then getsockname */
    int64_t p = s_socket(2, 2 | 0x80000, 0);
    CHECK(p >= 3);
    struct sockaddr_in probe = sin_loop(htons(9));
    CHECK_EQ(s_connect(p, &probe, sizeof probe), 0);
    sl = sizeof got;
    CHECK_EQ(s_getsockname(p, &got, &sl), 0);
    CHECK(got.sin_family == AF_INET && got.sin_addr.s_addr == htonl(0x7F000001) && got.sin_port != 0);
    CHECK_EQ(s_connect(p, &probe, 8), -E_INVAL);
    struct sockaddr_in badfam = probe;
    badfam.sin_family = 1;
    CHECK_EQ(s_connect(p, &badfam, sizeof badfam), -E_AFNOSUPPORT);
    CHECK_EQ(s_close(p), 0);
    /* the real probe of net_local_ip: the rendezvous server; without a route Linux says ENETUNREACH, which the game
     * answers with 127.0.0.1 */
    p = s_socket(2, 2 | 0x80000, 0);
    CHECK(p >= 3);
    struct sockaddr_in rv;
    memset(&rv, 0, sizeof rv);
    rv.sin_family = AF_INET;
    rv.sin_port = htons(27600);
    rv.sin_addr.s_addr = htonl((93u << 24) | (127u << 16) | (163u << 8) | 226u);
    int64_t cr = s_connect(p, &rv, sizeof rv);
    CHECK(cr == 0 || cr == -E_NETUNREACH);
    CHECK_EQ(s_close(p), 0);
    return 0;
}

/* ---- paths ----------------------------------------------------------------------------------------- */
static int t_paths(void)
{
    unsigned char st[144];
    char buf[16];
    /* "/tmp/..." is the Windows temporary directory */
    CHECK_EQ(s_mkdir(pth("pm")), 0);
    WCHAR chk[4 * MAX_PATH];
    swprintf(chk, 4 * MAX_PATH, L"%ls\\pm", g_dir_w);
    DWORD at = GetFileAttributesW(chk);
    CHECK(at != INVALID_FILE_ATTRIBUTES && (at & FILE_ATTRIBUTE_DIRECTORY));
    CHECK_EQ(s_stat(g_dir, st), 0); /* g_dir itself starts with /tmp */
    CHECK_EQ(s_stat("/tmp", st), 0);
    CHECK_EQ(st_mode(st) & 0xF000, 0x4000);

    /* the same directory spelled the Windows way, with either kind of separator */
    WCHAR tw[MAX_PATH];
    GetTempPathW(MAX_PATH, tw);
    char tu[3 * MAX_PATH];
    CHECK(WideCharToMultiByte(CP_UTF8, 0, tw, -1, tu, sizeof tu, NULL, NULL) > 0);
    char p1[4 * MAX_PATH], p2[4 * MAX_PATH];
    snprintf(p1, sizeof p1, "%s%s", tu, g_dir + 5); /* g_dir + 5 skips "/tmp/" */
    CHECK_EQ(write_file(pth("pm/win.txt"), "w", 1), 1);
    snprintf(p2, sizeof p2, "%s\\pm\\win.txt", p1);
    CHECK_EQ(s_stat(p2, st), 0);
    CHECK_EQ(st_size(st), 1);
    for (char *c = p2; *c; c++)
        if (*c == '\\')
            *c = '/';
    CHECK_EQ(read_file(p2, buf, 16), 1);

    /* \\?\ paths pass through */
    char pe[4 * MAX_PATH];
    snprintf(pe, sizeof pe, "\\\\?\\%s\\pm\\win.txt", p1);
    CHECK_EQ(s_stat(pe, st), 0);

    /* relative to the current directory */
    WCHAR old[MAX_PATH];
    DWORD ol = GetCurrentDirectoryW(MAX_PATH, old);
    CHECK(ol > 0 && ol < MAX_PATH);
    CHECK(SetCurrentDirectoryW(chk));
    CHECK_EQ(write_file("rel.txt", "r", 1), 1);
    CHECK_EQ(s_stat("./rel.txt", st), 0);
    CHECK_EQ(s_stat("..\\pm\\rel.txt", st), 0);
    CHECK(SetCurrentDirectoryW(old));
    CHECK_EQ(s_stat(pth("pm/rel.txt"), st), 0);

    /* invalid UTF-8 cannot be a Windows name */
    CHECK_EQ(s_stat("\xff\xfe", st), -E_INVAL);
    CHECK_EQ(s_open("/tmp/\xc3", O_RD), -E_INVAL);
    CHECK_EQ(s_stat("", st), -E_NOENT);
    CHECK_EQ(s_stat(NULL, st), -E_FAULT);
    CHECK_EQ(s_stat(pth("pm/win.txt"), NULL), -E_FAULT);
    return 0;
}

static int t_utf8_names(void)
{
    static const char name[] = "\xe2\x82\xac-\xe6\x97\xa5\xe6\x9c\xac.bin"; /* euro sign, two CJK characters */
    char buf[8];
    const char *p = pth("%s", name);
    CHECK_EQ(write_file(p, "u8", 2), 2);
    CHECK_EQ(read_file(p, buf, 8), 2);
    unsigned char st[144];
    CHECK_EQ(s_stat(p, st), 0);
    WCHAR wn[MAX_PATH], full[4 * MAX_PATH];
    CHECK(MultiByteToWideChar(CP_UTF8, 0, name, -1, wn, MAX_PATH) > 0);
    swprintf(full, 4 * MAX_PATH, L"%ls\\%ls", g_dir_w, wn);
    CHECK(GetFileAttributesW(full) != INVALID_FILE_ATTRIBUTES); /* the UTF-16 name is what Windows holds */
    CHECK_EQ(s_unlink(p), 0);
    CHECK_EQ(s_stat(p, st), -E_NOENT);
    return 0;
}

static int t_long_path(void)
{
    /* an absolute path of about 400 characters, built level by level: beyond MAX_PATH */
    char p[1500];
    unsigned char st[144];
    char buf[8];
    int n = snprintf(p, sizeof p, "%s/long", g_dir);
    CHECK_EQ(s_mkdir(p), 0);
    int levels = 0;
    char comp[40];
    while (n < 420) {
        snprintf(comp, sizeof comp, "/level-%02d-xxxxxxxxxxxxxxxxxxxx", levels);
        n += snprintf(p + n, sizeof p - (size_t)n, "%s", comp);
        CHECK_EQ(s_mkdir(p), 0);
        levels++;
    }
    CHECK(levels >= 8 && n > 300);
    n += snprintf(p + n, sizeof p - (size_t)n, "/leaf.txt");
    CHECK_EQ(write_file(p, "deep", 4), 4);
    CHECK_EQ(read_file(p, buf, 8), 4);
    CHECK(!memcmp(buf, "deep", 4));
    CHECK_EQ(s_stat(p, st), 0);
    CHECK_EQ(st_size(st), 4);
    char q[1500];
    snprintf(q, sizeof q, "%s.moved", p);
    CHECK_EQ(s_rename(p, q), 0);
    CHECK_EQ(s_stat(p, st), -E_NOENT);
    CHECK_EQ(s_unlink(q), 0);
    /* and a directory listing at that depth */
    p[n - 9] = 0; /* cut "/leaf.txt" */
    CHECK_EQ(write_file(pth("long/placeholder"), "p", 1), 1);
    char f2[1600];
    snprintf(f2, sizeof f2, "%s/two.txt", p);
    CHECK_EQ(write_file(f2, "2", 1), 1);
    int64_t fd = s_open(p, O_RD | O_DIR);
    CHECK(fd >= 3);
    unsigned char db[2048];
    int64_t dn = s_getdents(fd, db, sizeof db);
    CHECK(dn > 0);
    DENT e[8];
    int c = parse_dents(db, dn, e, 8);
    CHECK_EQ(c, 3);
    CHECK(find_dent(e, c, "two.txt") >= 0);
    CHECK_EQ(s_close(fd), 0);
    CHECK_EQ(s_unlink(f2), 0);
    /* remove the levels again, deepest first */
    for (int i = levels - 1; i >= 0; i--) {
        char *last = strrchr(p, '/');
        CHECK(last != NULL);
        CHECK_EQ(s_rmdir(p), 0);
        *last = 0;
    }
    return 0;
}

static int t_fd_table(void)
{
    const char *f = pth("fdt.txt");
    CHECK_EQ(write_file(f, "f", 1), 1);
    int64_t a = s_open(f, O_RD), b = s_open(f, O_RD);
    CHECK(a >= 3 && b == a + 1);
    CHECK_EQ(s_close(a), 0);
    int64_t c = s_open(f, O_RD);
    CHECK_EQ(c, a); /* the lowest free descriptor is reused, as POSIX does */
    CHECK_EQ(s_close(b), 0);
    CHECK_EQ(s_close(c), 0);

    /* run the table dry: 4096 slots, 3 of them are the standard streams */
    static int64_t fds[4200];
    int n = 0;
    int64_t r = 0;
    for (; n < 4200; n++) {
        r = s_open(f, O_RD);
        if (r < 0)
            break;
        fds[n] = r;
    }
    CHECK_EQ(r, -E_MFILE);
    CHECK(n >= 1000 && n <= 4093);
    for (int i = 0; i < n; i++)
        CHECK_EQ(s_close(fds[i]), 0);
    r = s_open(f, O_RD);
    CHECK(r >= 3);
    CHECK_EQ(s_close(r), 0);
    return 0;
}

/* ---- threads: slot allocation and release take a lock -------------------------------------------- */
static volatile LONG g_owner[4096];
static volatile LONG g_thread_errors;

static DWORD WINAPI worker(LPVOID arg)
{
    int id = (int)(intptr_t)arg + 1;
    char name[2048];
    for (int i = 0; i < 300; i++) {
        snprintf(name, sizeof name, "%s/thr%d.txt", g_dir, id);
        int64_t fd = s_open(name, O_WCT);
        if (fd < 3 || fd >= 4096) {
            InterlockedIncrement(&g_thread_errors);
            continue;
        }
        if (InterlockedExchange(&g_owner[fd], id) != 0) /* somebody else holds this descriptor */
            InterlockedIncrement(&g_thread_errors);
        if (s_write(fd, "12345678", 8) != 8)
            InterlockedIncrement(&g_thread_errors);
        if (i % 4 == 0) {
            int64_t sk = s_socket(2, SOCK_NB_DGRAM, 0);
            if (sk < 3 || sk >= 4096 || InterlockedExchange(&g_owner[sk], id) != 0)
                InterlockedIncrement(&g_thread_errors);
            else {
                InterlockedExchange(&g_owner[sk], 0);
                if (s_close(sk) != 0)
                    InterlockedIncrement(&g_thread_errors);
            }
        }
        InterlockedExchange(&g_owner[fd], 0);
        if (s_close(fd) != 0)
            InterlockedIncrement(&g_thread_errors);
    }
    return 0;
}

static int t_threads(void)
{
    HANDLE th[4];
    for (int i = 0; i < 4; i++) {
        th[i] = CreateThread(NULL, 0, worker, (LPVOID)(intptr_t)i, 0, NULL);
        CHECK(th[i] != NULL);
    }
    CHECK(WaitForMultipleObjects(4, th, TRUE, 120000) == WAIT_OBJECT_0);
    for (int i = 0; i < 4; i++)
        CloseHandle(th[i]);
    CHECK_EQ(g_thread_errors, 0);
    return 0;
}

static int t_std_handles(void)
{
    static const char m1[] = "win_sys_test: write(1) works\n", m2[] = "win_sys_test: write(2) works\n";
    unsigned char st[144];
    fflush(stdout);
    CHECK_EQ(s_write(1, m1, sizeof m1 - 1), (int64_t)sizeof m1 - 1);
    CHECK_EQ(s_write(2, m2, sizeof m2 - 1), (int64_t)sizeof m2 - 1);
    CHECK_EQ(s_write(1, "", 0), 0);
    CHECK_EQ(s_fstat(1, st), 0);
    uint32_t type = st_mode(st) & 0xF000; /* a terminal, a pipe or a file, whatever stdout is */
    CHECK(type == 0x2000 || type == 0x1000 || type == 0x8000);
    CHECK_EQ(s_lseek(1, 0, 1) == -29 || type == 0x8000, 1); /* ESPIPE unless stdout is a plain file */
    return 0;
}

#ifdef WITH_STUB
/* The same calls through the real win/syscall_stub.asm: rax = number, rdi rsi rdx r10 r8 r9 = arguments. */
static int64_t stub_sc(int64_t nr, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6)
{
    register int64_t r10 __asm__("r10") = a4;
    register int64_t r8 __asm__("r8") = a5;
    register int64_t r9 __asm__("r9") = a6;
    int64_t rax = nr;
    __asm__ volatile("call w_syscall_stub"
                     : "+a"(rax)
                     : "D"(a1), "S"(a2), "d"(a3), "r"(r10), "r"(r8), "r"(r9)
                     : "rcx", "r11", "memory", "cc");
    return rax;
}

static int t_stub_chain(void)
{
    char buf[16];
    const char *p = pth("stub.bin");
    int64_t fd = stub_sc(2, P(p), O_WCT, 0644, 0, 0, 0);
    CHECK(fd >= 3);
    CHECK_EQ(stub_sc(1, fd, P("stub!"), 5, 0, 0, 0), 5);
    CHECK_EQ(stub_sc(3, fd, 0, 0, 0, 0, 0), 0);
    fd = stub_sc(2, P(p), O_RD, 0, 0, 0, 0);
    CHECK(fd >= 3);
    CHECK_EQ(stub_sc(17, fd, P(buf), 3, 2, 0, 0), 3); /* pread64: a4 = r10 = offset 2 */
    CHECK(!memcmp(buf, "ub!", 3));
    CHECK_EQ(stub_sc(3, fd, 0, 0, 0, 0, 0), 0);
    CHECK_EQ(stub_sc(87, P(p), 0, 0, 0, 0, 0), 0);
    /* six arguments: the sixth travels on the stack */
    int64_t m = stub_sc(9, 0, 8192, 3, 0x22, -1, 0);
    CHECK(m > 0);
    ((unsigned char *)(intptr_t)m)[8191] = 7;
    CHECK_EQ(stub_sc(11, m, 8192, 0, 0, 0, 0), 0);
    int64_t s = stub_sc(41, 2, SOCK_NB_DGRAM, 0, 0, 0, 0);
    CHECK(s >= 3);
    struct sockaddr_in from;
    uint32_t fl = sizeof from;
    CHECK_EQ(stub_sc(45, s, P(buf), sizeof buf, 0, P(&from), P(&fl)), -E_AGAIN); /* a6 = &addrlen */
    CHECK_EQ(stub_sc(3, s, 0, 0, 0, 0, 0), 0);

    /* sendto: a4 = r10 = flags, a5 = r8 = address, a6 = r9 = address length (the stack); recvfrom: a5 = the source
     * address buffer, a6 = its length. A datagram from one socket to the other must arrive with its source. */
    int64_t ra = stub_sc(41, 2, SOCK_NB_DGRAM, 0, 0, 0, 0), rb = stub_sc(41, 2, 2, 0, 0, 0, 0);
    CHECK(ra >= 3 && rb >= 3);
    struct sockaddr_in any, bound, dst;
    memset(&any, 0, sizeof any);
    any.sin_family = AF_INET;
    CHECK_EQ(stub_sc(49, ra, P(&any), sizeof any, 0, 0, 0), 0);
    uint32_t bl = sizeof bound;
    CHECK_EQ(stub_sc(51, ra, P(&bound), P(&bl), 0, 0, 0), 0);
    CHECK(bound.sin_port != 0);
    dst = sin_loop(bound.sin_port);
    CHECK_EQ(stub_sc(44, rb, P("via-stub"), 8, 0, P(&dst), sizeof dst), 8);
    int64_t got = -E_AGAIN;
    for (int i = 0; i < 1000 && got == -E_AGAIN; i++) {
        fl = sizeof from;
        memset(&from, 0, sizeof from);
        got = stub_sc(45, ra, P(buf), sizeof buf, 0, P(&from), P(&fl));
        if (got == -E_AGAIN)
            Sleep(2);
    }
    CHECK_EQ(got, 8);
    CHECK(!memcmp(buf, "via-stub", 8));
    CHECK_EQ(fl, 16);
    CHECK(from.sin_family == AF_INET && from.sin_addr.s_addr == htonl(0x7F000001) && from.sin_port != 0);
    CHECK_EQ(stub_sc(3, ra, 0, 0, 0, 0, 0), 0);
    CHECK_EQ(stub_sc(3, rb, 0, 0, 0, 0, 0), 0);
    int64_t t = stub_sc(201, 0, 0, 0, 0, 0, 0);
    CHECK(t > 1577836800);
    CHECK_EQ(stub_sc(9999, 0, 0, 0, 0, 0, 0), -E_NOSYS);
    return 0;
}
#endif

/* ===================================================================================================== */

typedef struct {
    const char *name;
    int (*fn)(void);
} TEST;

static const TEST tests[] = {
    {"unknown_syscall", t_unknown_syscall},
    {"file_basic", t_file_basic},
    {"file_sparse_and_positions", t_file_sparse_and_positions},
    {"open_flags_and_errors", t_open_flags},
    {"rename_over_existing", t_rename},
    {"unlink", t_unlink},
    {"mkdir_rmdir", t_mkdir_rmdir},
    {"getdents64", t_getdents},
    {"getdents64_300_entries", t_getdents_many},
    {"rmdir_flat_pattern", t_rmdir_flat_pattern},
    {"time_clock_gettime", t_time_clock},
    {"getrandom", t_getrandom},
    {"mmap_munmap", t_mmap_munmap},
    {"sched_yield", t_sched_yield},
    {"sockets_udp", t_sockets_udp},
    {"sockets_bind_conflict_connreset", t_sockets_bind_conflict_and_connreset},
    {"sockets_options_and_misc", t_sockets_options_and_misc},
    {"paths", t_paths},
    {"utf8_names", t_utf8_names},
    {"long_path", t_long_path},
    {"fd_table", t_fd_table},
    {"threads", t_threads},
    {"std_handles", t_std_handles},
#ifdef WITH_STUB
    {"syscall_stub_chain", t_stub_chain},
#endif
};

int main(void)
{
    WCHAR tw[MAX_PATH];
    DWORD n = GetTempPathW(MAX_PATH, tw);
    if (n == 0 || n >= MAX_PATH) {
        fprintf(stderr, "no temporary directory\n");
        return 2;
    }
    snprintf(g_dir, sizeof g_dir, "/tmp/acwin-%lu", (unsigned long)GetCurrentProcessId());
    swprintf(g_dir_w, 2 * MAX_PATH, L"\\\\?\\%ls%hs", tw, g_dir + 5);
    rm_rf_w(g_dir_w); /* a leftover of a crashed run with the same pid */
    if (s_mkdir(g_dir) != 0) {
        fprintf(stderr, "cannot create %s\n", g_dir);
        return 2;
    }

    int failed = 0, total = (int)(sizeof tests / sizeof tests[0]);
    for (int i = 0; i < total; i++) {
        g_fail[0] = 0;
        int r = tests[i].fn();
        if (r) {
            failed++;
            printf("FAIL %s: %s\n", tests[i].name, g_fail);
        } else {
            printf("ok   %s\n", tests[i].name);
        }
        fflush(stdout);
    }
    rm_rf_w(g_dir_w);
    printf("win_sys_test: %d passed, %d failed\n", total - failed, failed);
    return failed ? 1 : 0;
}
