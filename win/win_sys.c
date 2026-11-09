/* win_sys.c - the Linux x86-64 system calls the game issues, emulated with Win32 and Winsock.
 *
 * The game's assembly issues raw `syscall` instructions. The Windows build (-DWIN64, src/common.inc) turns every
 * one of them into `call syscall_stub` (win/syscall_stub.asm), which saves what a real syscall would preserve and
 * calls
 *         int64_t win_syscall(nr, a1, a2, a3, a4, a5, a6)            (System V convention: SYSV)
 * with rax = nr and rdi rsi rdx r10 r8 r9 = a1..a6. The return value is what the Linux kernel would have put in
 * rax: >= 0 on success, -errno (Linux numbering) on failure. Every parameter and the result are int64_t: `long` is
 * 32 bits on Windows and would truncate pointers. Arguments the kernel takes as `int` (fds, flags) are read as
 * int, like the kernel does, so garbage in the upper half of a register is harmless.
 *
 * What is emulated: exactly the calls the game and its selftests issue (every `syscall` instruction of the .asm
 * sources in src/ was enumerated; the numbers resolve to the table below). Any other number returns -ENOSYS.
 *
 *   nr   call           where the game needs it
 *    0   read           sys.asm file_read
 *    1   write          sys.asm sys_print (fd 1/2 = the console), file_write_atomic
 *    2   open           sys.asm file_read/file_write_atomic (O_WCT, 0644)/file_patch (O_WRONLY)/file_pread/rmdir_flat
 *                       (O_RDONLY|O_DIRECTORY); saves.asm saves_scan (O_RDONLY|O_DIRECTORY); region.asm
 *                       region_write_column (O_RDWR, + O_CREAT|O_TRUNC for a new region file)
 *    3   close          everywhere, also the sockets of net.asm
 *    4   stat           sys.asm file_stat_mtime (st_mtime @ 88); saves.asm stat_info (st_mode @ 24, st_mtime @ 88)
 *    5   fstat          region.asm region_write_column (st_size @ 48)
 *    8   lseek          (SYS_LSEEK is defined in common.inc but no call site issues it; implemented in full)
 *    9   mmap           test_net.asm / test_netsync.asm: anonymous read/write mappings
 *   11   munmap         the same tests
 *   17   pread64        sys.asm file_pread
 *   18   pwrite64       sys.asm file_patch; region.asm pwrite_all
 *   24   sched_yield    test_net.asm raw_wait
 *   41   socket         net.asm net_ep_open, net_local_ip; test_net.asm raw_open
 *   42   connect        net.asm net_local_ip (a UDP connect, nothing is sent)
 *   44   sendto         net.asm ep_send_raw; test_net.asm raw_send
 *   45   recvfrom       net.asm net_ep_poll; test_net.asm raw_recv
 *   49   bind           net.asm net_ep_open; test_net.asm raw_open
 *   51   getsockname    net.asm net_ep_open, net_local_ip; test_net.asm raw_open
 *   54   setsockopt     net.asm net_ep_open (SOL_SOCKET: SO_RCVBUF, SO_SNDBUF)
 *   82   rename         sys.asm file_write_atomic (file.tmp over file)
 *   83   mkdir          sys.asm mkdir_p
 *   84   rmdir          sys.asm rmdir_flat
 *   87   unlink         sys.asm file_write_atomic, file_unlink, rmdir_flat
 *  201   time           sys.asm time_now
 *  217   getdents64     sys.asm rmdir_flat; saves.asm saves_scan
 *  228   clock_gettime  sys.asm time_mono_ns (CLOCK_MONOTONIC)
 *  318   getrandom      net.asm ep_rand32
 *
 * Design notes
 *  - File descriptors are indexes into a table of 4096 slots (fds 0..2 are the process's standard handles, the
 *    first fd handed out is 3, the lowest free slot is reused like POSIX does). A slot holds a file HANDLE, a
 *    SOCKET or a directory-enumeration state. Slot allocation and release take an SRWLOCK; the I/O itself runs
 *    without it.
 *  - Paths are UTF-8 on the game's side and UTF-16 on Win32's (the W APIs only). '/' and '\\' both separate;
 *    "/tmp" and "/tmp/..." mean the Windows temporary directory (the selftests keep their data there); a path of
 *    240+ characters is turned into an absolute \\?\ path so MAX_PATH does not apply.
 *  - Files are always opened with FILE_SHARE_READ|WRITE|DELETE, so a file this process has open never blocks another
 *    open of it, or a rename/delete by someone else. rename/unlink/rmdir retry a few times with a short back-off
 *    when Windows still reports a sharing problem (a virus scanner that holds the file for a moment).
 *  - UDP sockets get SIO_UDP_CONNRESET and SIO_UDP_NETRESET switched off: otherwise recvfrom fails with
 *    WSAECONNRESET after a datagram went to a closed port, which Linux never does on an unconnected socket.
 *
 * Known differences from Linux
 *  - mmap: anonymous memory only (-ENODEV for a file); MAP_FIXED cannot replace an existing mapping; munmap of
 *    part of a mapping decommits that part (the addresses stay reserved but fault).
 *  - open: the mode is ignored; O_NONBLOCK/O_NOFOLLOW/O_CLOEXEC change nothing; O_APPEND together with O_TRUNC
 *    appends by file position, not atomically.
 *  - rename: a directory replaces an empty directory by remove + move (not atomic); replacing a file that another
 *    handle holds open can fail with -EACCES where Linux succeeds (the retries wait for a scanner to let go).
 *  - stat: st_dev/st_ino are the volume serial and file index, uid/gid are 0, the permission bits are 0755/0644
 *    (0555/0444 for read-only), a directory's st_size is 0, st_ctime is the NTFS change time.
 *  - getdents64: d_ino and d_off are sequence numbers, the order is the file system's, names Linux could not hold
 *    (over 255 bytes of UTF-8) are skipped.
 *  - sockets: AF_INET stream and datagram only; SO_REUSEPORT is SO_REUSEADDR; options Windows lacks (SO_PRIORITY,
 *    SO_NO_CHECK, ...) are accepted and ignored; recvfrom of a datagram larger than the buffer returns the part
 *    that fits (no MSG_TRUNC); a send/receive timeout reports -EAGAIN like Linux.
 *  - sched_yield: when no other thread is ready it sleeps 1 ms instead of returning at once.
 *  - Windows reserved device names (CON, NUL, ...) and names ending in a dot or a space behave as Windows
 *    defines them.
 *
 * Link: -lws2_32 -lbcrypt (both in the Makefile's windows target). */
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601 /* Windows 7: nothing newer is imported statically */
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <bcrypt.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "win.h"

SYSV int64_t win_syscall(int64_t nr, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6);

_Static_assert(sizeof(void *) == 8, "the game is 64-bit");

/* ===================================================================================================== */
/* Linux ABI numbers                                                                                     */
/* ===================================================================================================== */

enum { /* system call numbers */
    NR_READ = 0, NR_WRITE = 1, NR_OPEN = 2, NR_CLOSE = 3, NR_STAT = 4, NR_FSTAT = 5, NR_LSEEK = 8, NR_MMAP = 9,
    NR_MUNMAP = 11, NR_PREAD64 = 17, NR_PWRITE64 = 18, NR_SCHED_YIELD = 24, NR_SOCKET = 41, NR_CONNECT = 42,
    NR_SENDTO = 44, NR_RECVFROM = 45, NR_BIND = 49, NR_GETSOCKNAME = 51, NR_SETSOCKOPT = 54, NR_RENAME = 82,
    NR_MKDIR = 83, NR_RMDIR = 84, NR_UNLINK = 87, NR_TIME = 201, NR_GETDENTS64 = 217, NR_CLOCK_GETTIME = 228,
    NR_GETRANDOM = 318
};

enum { /* errno */
    L_EPERM = 1, L_ENOENT = 2, L_EINTR = 4, L_EIO = 5, L_EBADF = 9, L_EAGAIN = 11, L_ENOMEM = 12, L_EACCES = 13,
    L_EFAULT = 14, L_EBUSY = 16, L_EEXIST = 17, L_EXDEV = 18, L_ENODEV = 19, L_ENOTDIR = 20, L_EISDIR = 21,
    L_EINVAL = 22, L_EMFILE = 24, L_ENOSPC = 28, L_ESPIPE = 29, L_EROFS = 30, L_EPIPE = 32, L_ENAMETOOLONG = 36,
    L_ENOSYS = 38, L_ENOTEMPTY = 39, L_ELOOP = 40, L_ENOTSOCK = 88, L_EDESTADDRREQ = 89, L_EMSGSIZE = 90,
    L_EPROTOTYPE = 91, L_ENOPROTOOPT = 92, L_EPROTONOSUPPORT = 93, L_ESOCKTNOSUPPORT = 94, L_EOPNOTSUPP = 95,
    L_EPFNOSUPPORT = 96, L_EAFNOSUPPORT = 97, L_EADDRINUSE = 98, L_EADDRNOTAVAIL = 99, L_ENETDOWN = 100,
    L_ENETUNREACH = 101, L_ENETRESET = 102, L_ECONNABORTED = 103, L_ECONNRESET = 104, L_ENOBUFS = 105,
    L_EISCONN = 106, L_ENOTCONN = 107, L_ESHUTDOWN = 108, L_ETOOMANYREFS = 109, L_ETIMEDOUT = 110,
    L_ECONNREFUSED = 111, L_EHOSTDOWN = 112, L_EHOSTUNREACH = 113, L_EALREADY = 114, L_EINPROGRESS = 115,
    L_ESTALE = 116, L_EDQUOT = 122
};

enum { /* open(2) flags */
    L_O_ACCMODE = 3, L_O_RDONLY = 0, L_O_WRONLY = 1, L_O_RDWR = 2, L_O_CREAT = 0x40, L_O_EXCL = 0x80,
    L_O_TRUNC = 0x200, L_O_APPEND = 0x400, L_O_DSYNC = 0x1000, L_O_DIRECTORY = 0x10000, L_O_TMPFILE = 0x410000
};

enum { L_SEEK_SET = 0, L_SEEK_CUR = 1, L_SEEK_END = 2 };

enum { /* st_mode */
    L_S_IFMT = 0170000, L_S_IFSOCK = 0140000, L_S_IFREG = 0100000, L_S_IFDIR = 0040000, L_S_IFCHR = 0020000,
    L_S_IFIFO = 0010000
};

enum { L_DT_DIR = 4, L_DT_REG = 8, L_DT_LNK = 10 };

enum { /* mmap */
    L_PROT_READ = 1, L_PROT_WRITE = 2, L_PROT_EXEC = 4, L_MAP_SHARED = 1, L_MAP_PRIVATE = 2, L_MAP_FIXED = 0x10,
    L_MAP_ANONYMOUS = 0x20
};

enum { /* clocks */
    L_CLOCK_REALTIME = 0, L_CLOCK_MONOTONIC = 1, L_CLOCK_MONOTONIC_RAW = 4, L_CLOCK_REALTIME_COARSE = 5,
    L_CLOCK_MONOTONIC_COARSE = 6, L_CLOCK_BOOTTIME = 7
};

enum { /* sockets */
    L_AF_INET = 2, L_SOCK_STREAM = 1, L_SOCK_DGRAM = 2, L_SOCK_TYPE_MASK = 0xf, L_SOCK_NONBLOCK = 0x800,
    L_SOCK_CLOEXEC = 0x80000, L_IPPROTO_IP = 0, L_IPPROTO_TCP = 6, L_IPPROTO_UDP = 17, L_SOL_SOCKET = 1,
    L_MSG_OOB = 0x1, L_MSG_PEEK = 0x2, L_MSG_DONTROUTE = 0x4, L_MSG_DONTWAIT = 0x40, L_MSG_WAITALL = 0x100
};

enum { /* SOL_SOCKET options */
    L_SO_DEBUG = 1, L_SO_REUSEADDR = 2, L_SO_DONTROUTE = 5, L_SO_BROADCAST = 6, L_SO_SNDBUF = 7, L_SO_RCVBUF = 8,
    L_SO_KEEPALIVE = 9, L_SO_OOBINLINE = 10, L_SO_NO_CHECK = 11, L_SO_PRIORITY = 12, L_SO_LINGER = 13,
    L_SO_BSDCOMPAT = 14, L_SO_REUSEPORT = 15, L_SO_RCVLOWAT = 18, L_SO_SNDLOWAT = 19, L_SO_RCVTIMEO = 20,
    L_SO_SNDTIMEO = 21, L_SO_SNDBUFFORCE = 32, L_SO_RCVBUFFORCE = 33
};

enum { /* IPPROTO_IP options */
    L_IP_TOS = 1, L_IP_TTL = 2, L_IP_MULTICAST_IF = 32, L_IP_MULTICAST_TTL = 33, L_IP_MULTICAST_LOOP = 34,
    L_IP_ADD_MEMBERSHIP = 35, L_IP_DROP_MEMBERSHIP = 36
};

enum { L_TCP_NODELAY = 1 };

#define L_GRND_NONBLOCK 1u
#define L_GRND_RANDOM 2u
#define L_GRND_INSECURE 4u

#ifndef SIO_UDP_CONNRESET
#define SIO_UDP_CONNRESET _WSAIOW(IOC_VENDOR, 12)
#endif
#ifndef SIO_UDP_NETRESET
#define SIO_UDP_NETRESET _WSAIOW(IOC_VENDOR, 15)
#endif

#define ERR(e) (-(int64_t)(e))
#define MAX_IO 0x7ffff000u /* the most one read/write transfers on Linux */
#define NAME_MAX_LINUX 255 /* longest directory entry name (bytes) */

/* The Linux x86-64 `struct stat` (144 bytes): the callers read st_mode @ 24, st_size @ 48, st_mtime @ 88. */
typedef struct {
    uint64_t st_dev;      /*   0 */
    uint64_t st_ino;      /*   8 */
    uint64_t st_nlink;    /*  16 */
    uint32_t st_mode;     /*  24 */
    uint32_t st_uid;      /*  28 */
    uint32_t st_gid;      /*  32 */
    uint32_t pad0;        /*  36 */
    uint64_t st_rdev;     /*  40 */
    int64_t st_size;      /*  48 */
    int64_t st_blksize;   /*  56 */
    int64_t st_blocks;    /*  64 */
    int64_t st_atime_s;   /*  72 */
    int64_t st_atime_ns;  /*  80 */
    int64_t st_mtime_s;   /*  88 */
    int64_t st_mtime_ns;  /*  96 */
    int64_t st_ctime_s;   /* 104 */
    int64_t st_ctime_ns;  /* 112 */
    int64_t unused[3];    /* 120 */
} LSTAT;
_Static_assert(sizeof(LSTAT) == 144 && offsetof(LSTAT, st_mode) == 24 && offsetof(LSTAT, st_size) == 48 &&
                   offsetof(LSTAT, st_mtime_s) == 88,
               "struct stat layout");

/* ===================================================================================================== */
/* Error mapping                                                                                         */
/* ===================================================================================================== */

/* Win32 error code -> Linux errno. Call GetLastError() first, before any other API call. */
static int map_win_error(DWORD e)
{
    switch (e) {
    case ERROR_FILE_NOT_FOUND:
    case ERROR_PATH_NOT_FOUND:
    case ERROR_INVALID_DRIVE:
    case ERROR_NO_MORE_FILES:
    case ERROR_BAD_NETPATH:
    case ERROR_BAD_NET_NAME:
    case ERROR_BAD_PATHNAME:
    case ERROR_INVALID_NAME:
    case ERROR_DEV_NOT_EXIST:
        return L_ENOENT;
    case ERROR_ACCESS_DENIED:
    case ERROR_SHARING_VIOLATION:
    case ERROR_LOCK_VIOLATION:
    case ERROR_NETWORK_ACCESS_DENIED:
    case ERROR_CANNOT_MAKE:
    case ERROR_CANT_ACCESS_FILE:
    case ERROR_DRIVE_LOCKED:
        return L_EACCES;
    case ERROR_ALREADY_EXISTS:
    case ERROR_FILE_EXISTS:
        return L_EEXIST;
    case ERROR_DIR_NOT_EMPTY:
        return L_ENOTEMPTY;
    case ERROR_DIRECTORY:
        return L_ENOTDIR;
    case ERROR_INVALID_HANDLE:
    case ERROR_INVALID_TARGET_HANDLE:
    case ERROR_DIRECT_ACCESS_HANDLE:
        return L_EBADF;
    case ERROR_NOT_ENOUGH_MEMORY:
    case ERROR_OUTOFMEMORY:
    case ERROR_NOT_ENOUGH_QUOTA:
    case ERROR_COMMITMENT_LIMIT:
        return L_ENOMEM;
    case ERROR_TOO_MANY_OPEN_FILES:
        return L_EMFILE;
    case ERROR_DISK_FULL:
    case ERROR_HANDLE_DISK_FULL:
        return L_ENOSPC;
    case ERROR_NOT_SAME_DEVICE:
        return L_EXDEV;
    case ERROR_WRITE_PROTECT:
        return L_EROFS;
    case ERROR_BROKEN_PIPE:
    case ERROR_NO_DATA:
        return L_EPIPE;
    case ERROR_FILENAME_EXCED_RANGE:
        return L_ENAMETOOLONG;
    case ERROR_CURRENT_DIRECTORY:
    case ERROR_BUSY:
        return L_EBUSY;
    case ERROR_INVALID_FUNCTION:
    case ERROR_INVALID_PARAMETER:
    case ERROR_INVALID_DATA:
    case ERROR_INVALID_ACCESS:
    case ERROR_NEGATIVE_SEEK:
        return L_EINVAL;
    case ERROR_PRIVILEGE_NOT_HELD:
        return L_EPERM;
    case ERROR_CANT_RESOLVE_FILENAME:
        return L_ELOOP;
    case ERROR_NOT_SUPPORTED:
        return L_EOPNOTSUPP;
    case ERROR_OPERATION_ABORTED:
    case ERROR_CANCELLED:
        return L_EINTR;
    default:
        return L_EIO;
    }
}

/* Winsock error code -> Linux errno. */
static int map_wsa_error(int e)
{
    switch (e) {
    case WSAEWOULDBLOCK: return L_EAGAIN;
    case WSAEINTR: return L_EINTR;
    case WSAEBADF: return L_EBADF;
    case WSAEACCES: return L_EACCES;
    case WSAEFAULT: return L_EFAULT;
    case WSAEINVAL: return L_EINVAL;
    case WSAEMFILE: return L_EMFILE;
    case WSAEINPROGRESS: return L_EINPROGRESS;
    case WSAEALREADY: return L_EALREADY;
    case WSAENOTSOCK: return L_ENOTSOCK;
    case WSAEDESTADDRREQ: return L_EDESTADDRREQ;
    case WSAEMSGSIZE: return L_EMSGSIZE;
    case WSAEPROTOTYPE: return L_EPROTOTYPE;
    case WSAENOPROTOOPT: return L_ENOPROTOOPT;
    case WSAEPROTONOSUPPORT: return L_EPROTONOSUPPORT;
    case WSAESOCKTNOSUPPORT: return L_ESOCKTNOSUPPORT;
    case WSAEOPNOTSUPP: return L_EOPNOTSUPP;
    case WSAEPFNOSUPPORT: return L_EPFNOSUPPORT;
    case WSAEAFNOSUPPORT: return L_EAFNOSUPPORT;
    case WSAEADDRINUSE: return L_EADDRINUSE;
    case WSAEADDRNOTAVAIL: return L_EADDRNOTAVAIL;
    case WSAENETDOWN: return L_ENETDOWN;
    case WSAENETUNREACH: return L_ENETUNREACH;
    case WSAENETRESET: return L_ENETRESET;
    case WSAECONNABORTED: return L_ECONNABORTED;
    case WSAECONNRESET: return L_ECONNRESET;
    case WSAENOBUFS: return L_ENOBUFS;
    case WSAEISCONN: return L_EISCONN;
    case WSAENOTCONN: return L_ENOTCONN;
    case WSAESHUTDOWN: return L_ESHUTDOWN;
    case WSAETOOMANYREFS: return L_ETOOMANYREFS;
    case WSAETIMEDOUT: return L_ETIMEDOUT;
    case WSAECONNREFUSED: return L_ECONNREFUSED;
    case WSAELOOP: return L_ELOOP;
    case WSAENAMETOOLONG: return L_ENAMETOOLONG;
    case WSAEHOSTDOWN: return L_EHOSTDOWN;
    case WSAEHOSTUNREACH: return L_EHOSTUNREACH;
    case WSAENOTEMPTY: return L_ENOTEMPTY;
    case WSAEDQUOT: return L_EDQUOT;
    case WSAESTALE: return L_ESTALE;
    case WSANOTINITIALISED: return L_ENETDOWN;
    default: return L_EIO;
    }
}

/* ===================================================================================================== */
/* One-time setup, time conversions                                                                      */
/* ===================================================================================================== */

typedef VOID(WINAPI *PFN_PRECISE_TIME)(LPFILETIME);

static INIT_ONCE g_base_once = INIT_ONCE_STATIC_INIT;
static PFN_PRECISE_TIME g_precise_time;   /* GetSystemTimePreciseAsFileTime (Windows 8+), else NULL */
static int64_t g_qpf = 1;                 /* QueryPerformanceFrequency */
static WCHAR g_tmpdir[MAX_PATH + 2];      /* the temporary directory, without a trailing backslash */
static size_t g_tmplen;                   /* its length in characters; 0 when it could not be found */
static DWORD g_page = 4096;

static BOOL CALLBACK base_init(PINIT_ONCE once, PVOID param, PVOID *ctx)
{
    (void)once;
    (void)param;
    (void)ctx;
    HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
    if (k32)
        g_precise_time = (PFN_PRECISE_TIME)(void *)GetProcAddress(k32, "GetSystemTimePreciseAsFileTime");
    LARGE_INTEGER f;
    if (QueryPerformanceFrequency(&f) && f.QuadPart > 0)
        g_qpf = f.QuadPart;
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    if (si.dwPageSize)
        g_page = si.dwPageSize;
    DWORD n = GetTempPathW(MAX_PATH, g_tmpdir);
    if (n == 0 || n >= MAX_PATH) {
        g_tmplen = 0;
    } else {
        while (n > 3 && (g_tmpdir[n - 1] == L'\\' || g_tmpdir[n - 1] == L'/'))
            n--; /* "C:\" keeps its slash: "C:" would mean the current directory of drive C */
        g_tmpdir[n] = 0;
        g_tmplen = n;
    }
    return TRUE;
}

static void base_once(void) { InitOnceExecuteOnce(&g_base_once, base_init, NULL, NULL); }

#define EPOCH_DIFF_100NS 116444736000000000LL /* 1601-01-01 .. 1970-01-01 in 100 ns */

static uint64_t ft_u64(FILETIME f) { return ((uint64_t)f.dwHighDateTime << 32) | f.dwLowDateTime; }

/* A FILETIME value (100 ns since 1601) -> Unix seconds and nanoseconds (floor division for dates before 1970). */
static void ft_to_unix(uint64_t ft, int64_t *sec, int64_t *nsec)
{
    int64_t d = (int64_t)ft - EPOCH_DIFF_100NS;
    int64_t s = d / 10000000, r = d % 10000000;
    if (r < 0) {
        s--;
        r += 10000000;
    }
    *sec = s;
    *nsec = r * 100;
}

/* ===================================================================================================== */
/* Paths: UTF-8 -> UTF-16                                                                                */
/* ===================================================================================================== */

#define WPATH_INLINE 320
#define LONG_PATH_AT 240 /* from this length on the path is made absolute and \\?\ prefixed */

typedef struct {
    WCHAR *p;
    WCHAR buf[WPATH_INLINE];
} WPATH;

static void wpath_free(WPATH *w)
{
    if (w->p && w->p != w->buf)
        free(w->p);
    w->p = NULL;
}

static int has_ext_prefix(const WCHAR *p) /* \\?\ or \\.\ */
{
    return p[0] == L'\\' && p[1] == L'\\' && (p[2] == L'?' || p[2] == L'.') && p[3] == L'\\';
}

/* Replaces w->p by the absolute, \\?\ prefixed form of itself (UNC paths become \\?\UNC\...). 0 or -errno. */
static int wpath_extend(WPATH *w)
{
    DWORD need = GetFullPathNameW(w->p, 0, NULL, NULL);
    if (need == 0)
        return -map_win_error(GetLastError());
    if (need > 32700)
        return -L_ENAMETOOLONG;
    WCHAR *full = (WCHAR *)malloc(((size_t)need + 1) * sizeof(WCHAR));
    WCHAR *out = (WCHAR *)malloc(((size_t)need + 16) * sizeof(WCHAR));
    if (!full || !out) {
        free(full);
        free(out);
        return -L_ENOMEM;
    }
    DWORD got = GetFullPathNameW(w->p, need + 1, full, NULL);
    if (got == 0 || got > need) {
        int e = got == 0 ? map_win_error(GetLastError()) : L_ENAMETOOLONG;
        free(full);
        free(out);
        return -e;
    }
    if (has_ext_prefix(full)) {
        wcscpy(out, full);
    } else if (full[0] == L'\\' && full[1] == L'\\') {
        wcscpy(out, L"\\\\?\\UNC\\");
        wcscat(out, full + 2);
    } else {
        wcscpy(out, L"\\\\?\\");
        wcscat(out, full);
    }
    free(full);
    wpath_free(w);
    w->p = out;
    return 0;
}

/* Converts a UTF-8 path the way the game writes it. 0 or -errno. */
static int wpath_set(WPATH *w, const char *u8)
{
    w->p = w->buf;
    if (!u8)
        return -L_EFAULT;
    if (!u8[0])
        return -L_ENOENT;
    base_once();
    size_t pre = 0;
    if (g_tmplen && u8[0] == '/' && u8[1] == 't' && u8[2] == 'm' && u8[3] == 'p' &&
        (u8[4] == 0 || u8[4] == '/' || u8[4] == '\\')) {
        pre = g_tmplen; /* "/tmp" is the Windows temporary directory */
        u8 += 4;
    }
    int n = 1; /* wide characters of the rest, with the terminating NUL */
    if (*u8) {
        n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, u8, -1, NULL, 0);
        if (n <= 0)
            return -L_EINVAL; /* not valid UTF-8: no Windows name can carry it */
    }
    size_t need = pre + (size_t)n;
    if (need > 32767)
        return -L_ENAMETOOLONG;
    WCHAR *dst = w->buf;
    if (need > WPATH_INLINE) {
        dst = (WCHAR *)malloc(need * sizeof(WCHAR));
        if (!dst)
            return -L_ENOMEM;
    }
    w->p = dst;
    memcpy(dst, g_tmpdir, pre * sizeof(WCHAR));
    if (*u8) {
        if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, u8, -1, dst + pre, n) != n) {
            wpath_free(w);
            return -L_EINVAL;
        }
    } else {
        dst[pre] = 0;
    }
    for (WCHAR *c = dst; *c; c++)
        if (*c == L'/')
            *c = L'\\';
    if (need - 1 >= LONG_PATH_AT && !has_ext_prefix(dst)) {
        int r = wpath_extend(w);
        if (r) {
            wpath_free(w);
            return r;
        }
    }
    return 0;
}

/* ===================================================================================================== */
/* The file-descriptor table                                                                             */
/* ===================================================================================================== */

#define FD_MAX 4096
#define FD_FIRST 3 /* 0, 1, 2 are the standard handles */

enum { K_FREE = 0, K_FILE, K_DIR, K_SOCK };

typedef struct DIRST DIRST;

typedef struct {
    unsigned char kind;
    unsigned char acc;      /* O_RDONLY / O_WRONLY / O_RDWR of the open */
    unsigned char nonblock; /* sockets: FIONBIO is on */
    unsigned char stype;    /* sockets: L_SOCK_STREAM / L_SOCK_DGRAM */
    union {
        HANDLE h;  /* K_FILE */
        SOCKET s;  /* K_SOCK */
        DIRST *dir; /* K_DIR */
    } u;
} FDENT;

static FDENT g_fd[FD_MAX];
static SRWLOCK g_fd_lock = SRWLOCK_INIT;
static volatile LONG g_std_closed; /* bit i: fd i (0..2) was closed by the program */

/* Stores a new entry in the lowest free slot >= FD_FIRST. Returns the fd, or -EMFILE. */
static int fd_alloc(const FDENT *proto)
{
    AcquireSRWLockExclusive(&g_fd_lock);
    for (int i = FD_FIRST; i < FD_MAX; i++) {
        if (g_fd[i].kind == K_FREE) {
            g_fd[i] = *proto;
            ReleaseSRWLockExclusive(&g_fd_lock);
            return i;
        }
    }
    ReleaseSRWLockExclusive(&g_fd_lock);
    return -L_EMFILE;
}

/* Copies the entry of an open fd into *out. 0 or -EBADF. fds 0..2 are the process's standard handles. */
static int fd_get(int fd, FDENT *out)
{
    if (fd < 0 || fd >= FD_MAX)
        return -L_EBADF;
    if (fd < FD_FIRST) {
        if (g_std_closed & (1L << fd))
            return -L_EBADF;
        HANDLE h = GetStdHandle(fd == 0 ? STD_INPUT_HANDLE : fd == 1 ? STD_OUTPUT_HANDLE : STD_ERROR_HANDLE);
        if (h == NULL || h == INVALID_HANDLE_VALUE)
            return -L_EBADF;
        memset(out, 0, sizeof *out);
        out->kind = K_FILE;
        out->acc = L_O_RDWR; /* a terminal's descriptors are read/write */
        out->u.h = h;
        return 0;
    }
    if (g_fd[fd].kind == K_FREE)
        return -L_EBADF;
    *out = g_fd[fd];
    return 0;
}

/* ===================================================================================================== */
/* Directory enumeration state (getdents64)                                                              */
/* ===================================================================================================== */

struct DIRST {
    WCHAR *path;       /* the directory, as opened */
    HANDLE find;       /* FindFirstFileEx handle; INVALID_HANDLE_VALUE until the first real entry is wanted */
    int stage;         /* 0: "." is next, 1: ".." is next, 2: reading the directory, 3: end reached */
    int pending;       /* the entry below was produced but did not fit into the previous buffer */
    uint64_t pos;      /* entries delivered so far (d_off of the next one) */
    unsigned char type;
    unsigned namelen;
    char name[NAME_MAX_LINUX + 1];
};

static void dir_free(DIRST *d)
{
    if (!d)
        return;
    if (d->find != INVALID_HANDLE_VALUE)
        FindClose(d->find);
    free(d->path);
    free(d);
}

static void dir_rewind(DIRST *d)
{
    if (d->find != INVALID_HANDLE_VALUE)
        FindClose(d->find);
    d->find = INVALID_HANDLE_VALUE;
    d->stage = 0;
    d->pending = 0;
    d->pos = 0;
}

static WCHAR *dir_pattern(const WCHAR *path) /* "<path>\*" */
{
    size_t n = wcslen(path);
    WCHAR *p = (WCHAR *)malloc((n + 3) * sizeof(WCHAR));
    if (!p)
        return NULL;
    memcpy(p, path, n * sizeof(WCHAR));
    if (n && p[n - 1] != L'\\' && p[n - 1] != L':')
        p[n++] = L'\\';
    p[n++] = L'*';
    p[n] = 0;
    return p;
}

/* Produces the next entry into d->type / d->name / d->namelen: 1 got one, 0 end of directory, -errno. "." and
 * ".." come first and exactly once, whatever the file system reports. Names that Linux could not hold (over 255
 * bytes of UTF-8) or that are not valid UTF-16 are skipped: no UTF-8 path could name them anyway. */
static int dir_fetch(DIRST *d)
{
    if (d->stage == 0 || d->stage == 1) {
        const char *nm = d->stage == 0 ? "." : "..";
        d->namelen = d->stage == 0 ? 1 : 2;
        memcpy(d->name, nm, d->namelen + 1);
        d->type = L_DT_DIR;
        d->stage++;
        return 1;
    }
    for (;;) {
        if (d->stage >= 3)
            return 0;
        WIN32_FIND_DATAW fd;
        if (d->find == INVALID_HANDLE_VALUE) {
            WCHAR *pat = dir_pattern(d->path);
            if (!pat)
                return -L_ENOMEM;
            HANDLE h = FindFirstFileExW(pat, FindExInfoBasic, &fd, FindExSearchNameMatch, NULL,
                                        FIND_FIRST_EX_LARGE_FETCH);
            DWORD e = GetLastError();
            free(pat);
            if (h == INVALID_HANDLE_VALUE) {
                d->stage = 3;
                if (e == ERROR_FILE_NOT_FOUND || e == ERROR_NO_MORE_FILES)
                    return 0; /* an empty directory */
                return -map_win_error(e);
            }
            d->find = h;
        } else if (!FindNextFileW(d->find, &fd)) {
            DWORD e = GetLastError();
            d->stage = 3;
            if (e == ERROR_NO_MORE_FILES)
                return 0;
            return -map_win_error(e);
        }
        if (fd.cFileName[0] == L'.' &&
            (fd.cFileName[1] == 0 || (fd.cFileName[1] == L'.' && fd.cFileName[2] == 0)))
            continue; /* the synthesized ones were delivered already */
        int n = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, fd.cFileName, -1, d->name, (int)sizeof d->name,
                                    NULL, NULL);
        if (n <= 1)
            continue; /* invalid UTF-16, or longer than a Linux name */
        d->namelen = (unsigned)n - 1;
        if ((fd.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) && fd.dwReserved0 == IO_REPARSE_TAG_SYMLINK)
            d->type = L_DT_LNK;
        else if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
            d->type = L_DT_DIR;
        else
            d->type = L_DT_REG;
        return 1;
    }
}

/* ===================================================================================================== */
/* stat                                                                                                  */
/* ===================================================================================================== */

typedef struct {
    DWORD attr;
    uint64_t atime, mtime, ctime; /* FILETIME values */
    uint64_t size;
    uint64_t dev, ino;
    DWORD nlink;
} FINFO;

static void stat_fill(void *out, const FINFO *fi)
{
    LSTAT st;
    memset(&st, 0, sizeof st);
    int isdir = (fi->attr & FILE_ATTRIBUTE_DIRECTORY) != 0;
    int ro = (fi->attr & FILE_ATTRIBUTE_READONLY) != 0;
    st.st_dev = fi->dev;
    st.st_ino = fi->ino;
    st.st_nlink = fi->nlink ? fi->nlink : 1;
    st.st_mode = isdir ? (L_S_IFDIR | (ro ? 0555u : 0755u)) : (L_S_IFREG | (ro ? 0444u : 0644u));
    st.st_size = isdir ? 0 : (int64_t)fi->size;
    st.st_blksize = 4096;
    st.st_blocks = (st.st_size + 511) / 512;
    ft_to_unix(fi->atime, &st.st_atime_s, &st.st_atime_ns);
    ft_to_unix(fi->mtime, &st.st_mtime_s, &st.st_mtime_ns);
    ft_to_unix(fi->ctime, &st.st_ctime_s, &st.st_ctime_ns);
    memcpy(out, &st, sizeof st);
}

/* A character device, pipe or socket: only the type bits of st_mode mean anything. */
static void stat_special(void *out, uint32_t mode)
{
    LSTAT st;
    memset(&st, 0, sizeof st);
    st.st_nlink = 1;
    st.st_mode = mode;
    st.st_blksize = 4096;
    memcpy(out, &st, sizeof st);
}

static int64_t stat_handle(HANDLE h, void *out)
{
    BY_HANDLE_FILE_INFORMATION bi;
    if (!GetFileInformationByHandle(h, &bi))
        return ERR(map_win_error(GetLastError()));
    FINFO fi;
    fi.attr = bi.dwFileAttributes;
    fi.atime = ft_u64(bi.ftLastAccessTime);
    fi.mtime = ft_u64(bi.ftLastWriteTime);
    fi.ctime = fi.mtime;
    FILE_BASIC_INFO bas;
    if (GetFileInformationByHandleEx(h, FileBasicInfo, &bas, sizeof bas) && bas.ChangeTime.QuadPart > 0)
        fi.ctime = (uint64_t)bas.ChangeTime.QuadPart; /* the NTFS change time is the closest thing to ctime */
    fi.size = ((uint64_t)bi.nFileSizeHigh << 32) | bi.nFileSizeLow;
    fi.dev = bi.dwVolumeSerialNumber;
    fi.ino = ((uint64_t)bi.nFileIndexHigh << 32) | bi.nFileIndexLow;
    fi.nlink = bi.nNumberOfLinks;
    stat_fill(out, &fi);
    return 0;
}

/* stat of a wide path; follows links like stat(2). A file that cannot be opened even for its attributes
 * (exclusive lock, ACL) is described from the directory entry instead. */
static int64_t stat_wide(const WCHAR *wp, void *out)
{
    HANDLE h = CreateFileW(wp, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                           OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    if (h != INVALID_HANDLE_VALUE) {
        int64_t r = stat_handle(h, out);
        CloseHandle(h);
        return r;
    }
    DWORD e = GetLastError();
    if (e == ERROR_ACCESS_DENIED || e == ERROR_SHARING_VIOLATION) {
        WIN32_FILE_ATTRIBUTE_DATA ad;
        if (GetFileAttributesExW(wp, GetFileExInfoStandard, &ad)) {
            FINFO fi;
            memset(&fi, 0, sizeof fi);
            fi.attr = ad.dwFileAttributes;
            fi.atime = ft_u64(ad.ftLastAccessTime);
            fi.mtime = ft_u64(ad.ftLastWriteTime);
            fi.ctime = fi.mtime;
            fi.size = ((uint64_t)ad.nFileSizeHigh << 32) | ad.nFileSizeLow;
            stat_fill(out, &fi);
            return 0;
        }
    }
    return ERR(map_win_error(e));
}

static int64_t sys_stat(const char *path, void *out)
{
    if (!out)
        return ERR(L_EFAULT);
    WPATH w;
    int r = wpath_set(&w, path);
    if (r)
        return r;
    int64_t res = stat_wide(w.p, out);
    wpath_free(&w);
    return res;
}

static int64_t sys_fstat(int fd, void *out)
{
    FDENT e;
    int r = fd_get(fd, &e);
    if (r)
        return r;
    if (!out)
        return ERR(L_EFAULT);
    switch (e.kind) {
    case K_DIR:
        return stat_wide(e.u.dir->path, out);
    case K_SOCK:
        stat_special(out, L_S_IFSOCK | 0777);
        return 0;
    default:
        break;
    }
    switch (GetFileType(e.u.h)) {
    case FILE_TYPE_CHAR:
        stat_special(out, L_S_IFCHR | 0620);
        return 0;
    case FILE_TYPE_PIPE:
        stat_special(out, L_S_IFIFO | 0600);
        return 0;
    default:
        return stat_handle(e.u.h, out);
    }
}

/* ===================================================================================================== */
/* open / close / read / write / lseek                                                                   */
/* ===================================================================================================== */

#define SHARE_ALL (FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE)

static int64_t open_dir(const WPATH *w, int acc)
{
    if (acc != L_O_RDONLY)
        return ERR(L_EISDIR);
    DWORD a = GetFileAttributesW(w->p);
    if (a == INVALID_FILE_ATTRIBUTES)
        return ERR(map_win_error(GetLastError()));
    if (!(a & FILE_ATTRIBUTE_DIRECTORY))
        return ERR(L_ENOTDIR);
    DIRST *d = (DIRST *)calloc(1, sizeof *d);
    if (!d)
        return ERR(L_ENOMEM);
    size_t n = wcslen(w->p);
    d->path = (WCHAR *)malloc((n + 1) * sizeof(WCHAR));
    if (!d->path) {
        free(d);
        return ERR(L_ENOMEM);
    }
    memcpy(d->path, w->p, (n + 1) * sizeof(WCHAR));
    d->find = INVALID_HANDLE_VALUE;
    FDENT ent;
    memset(&ent, 0, sizeof ent);
    ent.kind = K_DIR;
    ent.acc = L_O_RDONLY;
    ent.u.dir = d;
    int fd = fd_alloc(&ent);
    if (fd < 0)
        dir_free(d);
    return fd;
}

static int64_t open_file(const WPATH *w, int flags, int acc)
{
    int creat = (flags & L_O_CREAT) != 0, excl = (flags & L_O_EXCL) != 0, trunc = (flags & L_O_TRUNC) != 0;
    DWORD access = 0;
    if (acc != L_O_WRONLY)
        access |= GENERIC_READ;
    if (acc != L_O_RDONLY || trunc) {
        if ((flags & L_O_APPEND) && !trunc)
            access |= FILE_GENERIC_WRITE & ~(DWORD)FILE_WRITE_DATA; /* append-only: the system appends atomically */
        else
            access |= GENERIC_WRITE;
    }
    DWORD disp = creat && excl ? CREATE_NEW
                 : creat && trunc ? CREATE_ALWAYS
                 : creat ? OPEN_ALWAYS
                 : trunc ? TRUNCATE_EXISTING
                         : OPEN_EXISTING;
    DWORD attrs = FILE_ATTRIBUTE_NORMAL;
    if (flags & L_O_DSYNC)
        attrs |= FILE_FLAG_WRITE_THROUGH;
    HANDLE h = CreateFileW(w->p, access, SHARE_ALL, NULL, disp, attrs, NULL);
    if (h == INVALID_HANDLE_VALUE) {
        DWORD e = GetLastError();
        if (e == ERROR_ACCESS_DENIED) { /* CreateFile cannot open a directory without BACKUP_SEMANTICS */
            DWORD a = GetFileAttributesW(w->p);
            if (a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY)) {
                if (acc == L_O_RDONLY && !creat && !trunc)
                    return open_dir(w, acc); /* open(dir, O_RDONLY) works on Linux */
                return ERR(L_EISDIR);
            }
        }
        return ERR(map_win_error(e));
    }
    FDENT ent;
    memset(&ent, 0, sizeof ent);
    ent.kind = K_FILE;
    ent.acc = (unsigned char)acc;
    ent.u.h = h;
    int fd = fd_alloc(&ent);
    if (fd < 0)
        CloseHandle(h);
    return fd;
}

/* open(path, flags, mode): the mode is ignored (there are no Unix permissions). */
static int64_t sys_open(const char *path, int flags, int mode)
{
    (void)mode;
    int acc = flags & L_O_ACCMODE;
    if (acc == 3)
        return ERR(L_EINVAL);
    if ((flags & L_O_TMPFILE) == L_O_TMPFILE)
        return ERR(L_EOPNOTSUPP);
    WPATH w;
    int r = wpath_set(&w, path);
    if (r)
        return r;
    int64_t res;
    if (flags & L_O_DIRECTORY)
        res = (flags & L_O_CREAT) ? ERR(L_EINVAL) : open_dir(&w, acc);
    else
        res = open_file(&w, flags, acc);
    wpath_free(&w);
    return res;
}

static int64_t sys_close(int fd)
{
    if (fd < 0 || fd >= FD_MAX)
        return ERR(L_EBADF);
    if (fd < FD_FIRST) { /* the standard handles stay open for the process; the program just loses its fd */
        LONG old = InterlockedOr(&g_std_closed, 1L << fd);
        return (old & (1L << fd)) ? ERR(L_EBADF) : 0;
    }
    FDENT e;
    AcquireSRWLockExclusive(&g_fd_lock);
    if (g_fd[fd].kind == K_FREE) {
        ReleaseSRWLockExclusive(&g_fd_lock);
        return ERR(L_EBADF);
    }
    e = g_fd[fd];
    g_fd[fd].kind = K_FREE;
    ReleaseSRWLockExclusive(&g_fd_lock);
    switch (e.kind) { /* like Linux, the fd is gone even when the close itself reports an error */
    case K_FILE:
        return CloseHandle(e.u.h) ? 0 : ERR(map_win_error(GetLastError()));
    case K_SOCK:
        return closesocket(e.u.s) == 0 ? 0 : ERR(map_wsa_error(WSAGetLastError()));
    case K_DIR:
        dir_free(e.u.dir);
        return 0;
    default:
        return 0;
    }
}

static int64_t sock_read(const FDENT *e, void *buf, size_t n);
static int64_t sock_write(const FDENT *e, const void *buf, size_t n);

static int64_t sys_read(int fd, void *buf, size_t n)
{
    FDENT e;
    int r = fd_get(fd, &e);
    if (r)
        return r;
    if (e.acc == L_O_WRONLY)
        return ERR(L_EBADF);
    if (e.kind == K_DIR)
        return ERR(L_EISDIR);
    if (e.kind == K_SOCK)
        return sock_read(&e, buf, n);
    if (n == 0)
        return 0;
    if (!buf)
        return ERR(L_EFAULT);
    if (n > MAX_IO)
        n = MAX_IO;
    DWORD got = 0;
    if (!ReadFile(e.u.h, buf, (DWORD)n, &got, NULL)) {
        DWORD err = GetLastError();
        if (err == ERROR_HANDLE_EOF || err == ERROR_BROKEN_PIPE)
            return 0;
        return ERR(map_win_error(err));
    }
    return got;
}

static int64_t sys_write(int fd, const void *buf, size_t n)
{
    FDENT e;
    int r = fd_get(fd, &e);
    if (r)
        return r;
    if (e.acc == L_O_RDONLY)
        return ERR(L_EBADF);
    if (e.kind == K_DIR)
        return ERR(L_EISDIR);
    if (e.kind == K_SOCK)
        return sock_write(&e, buf, n);
    if (n == 0)
        return 0;
    if (!buf)
        return ERR(L_EFAULT);
    if (n > MAX_IO)
        n = MAX_IO;
    DWORD done = 0;
    if (!WriteFile(e.u.h, buf, (DWORD)n, &done, NULL))
        return ERR(map_win_error(GetLastError()));
    return done;
}

/* pread64 / pwrite64: transfer at an explicit offset and leave the file position alone (Windows moves it for a
 * synchronous handle, so it is saved and restored). */
static int64_t sys_pio(int fd, void *buf, size_t n, int64_t off, int is_write)
{
    FDENT e;
    int r = fd_get(fd, &e);
    if (r)
        return r;
    if (e.kind == K_DIR)
        return ERR(L_EISDIR);
    if (e.kind == K_SOCK)
        return ERR(L_ESPIPE);
    if (is_write ? e.acc == L_O_RDONLY : e.acc == L_O_WRONLY)
        return ERR(L_EBADF);
    if (off < 0)
        return ERR(L_EINVAL);
    if (GetFileType(e.u.h) != FILE_TYPE_DISK)
        return ERR(L_ESPIPE);
    if (n == 0)
        return 0;
    if (!buf)
        return ERR(L_EFAULT);
    if (n > MAX_IO)
        n = MAX_IO;
    LARGE_INTEGER zero, saved;
    zero.QuadPart = 0;
    if (!SetFilePointerEx(e.u.h, zero, &saved, FILE_CURRENT))
        return ERR(map_win_error(GetLastError()));
    OVERLAPPED ov;
    memset(&ov, 0, sizeof ov);
    ov.Offset = (DWORD)(uint64_t)off;
    ov.OffsetHigh = (DWORD)((uint64_t)off >> 32);
    DWORD done = 0;
    BOOL ok = is_write ? WriteFile(e.u.h, buf, (DWORD)n, &done, &ov) : ReadFile(e.u.h, buf, (DWORD)n, &done, &ov);
    DWORD err = ok ? 0 : GetLastError();
    SetFilePointerEx(e.u.h, saved, NULL, FILE_BEGIN);
    if (!ok) {
        if (!is_write && err == ERROR_HANDLE_EOF)
            return 0;
        return ERR(map_win_error(err));
    }
    return done;
}

static int64_t sys_lseek(int fd, int64_t off, int whence)
{
    FDENT e;
    int r = fd_get(fd, &e);
    if (r)
        return r;
    if (e.kind == K_SOCK)
        return ERR(L_ESPIPE);
    if (e.kind == K_DIR) { /* lseek(dirfd, 0, SEEK_SET) is rewinddir */
        if (whence == L_SEEK_SET && off == 0) {
            dir_rewind(e.u.dir);
            return 0;
        }
        return ERR(L_EINVAL);
    }
    DWORD method;
    switch (whence) {
    case L_SEEK_SET: method = FILE_BEGIN; break;
    case L_SEEK_CUR: method = FILE_CURRENT; break;
    case L_SEEK_END: method = FILE_END; break;
    default: return ERR(L_EINVAL);
    }
    if (GetFileType(e.u.h) != FILE_TYPE_DISK)
        return ERR(L_ESPIPE);
    LARGE_INTEGER li, np;
    li.QuadPart = off;
    if (!SetFilePointerEx(e.u.h, li, &np, method))
        return ERR(map_win_error(GetLastError()));
    return np.QuadPart;
}

/* ===================================================================================================== */
/* rename / mkdir / rmdir / unlink / getdents64                                                          */
/* ===================================================================================================== */

#define RETRIES 4 /* attempts beyond the first for a transient sharing problem; back-off 0, 2, 4, 6 ms */

static void backoff(int attempt) { Sleep((DWORD)attempt * 2); }

static DWORD attrs_of(const WCHAR *p) { return GetFileAttributesW(p); }

static int64_t sys_rename(const char *from, const char *to)
{
    WPATH a, b;
    int r = wpath_set(&a, from);
    if (r)
        return r;
    r = wpath_set(&b, to);
    if (r) {
        wpath_free(&a);
        return r;
    }
    int64_t res = 0;
    if (wcscmp(a.p, b.p) == 0) { /* rename onto itself: nothing to do if it exists */
        res = attrs_of(a.p) == INVALID_FILE_ATTRIBUTES ? ERR(map_win_error(GetLastError())) : 0;
        goto out;
    }
    DWORD fa = attrs_of(a.p);
    if (fa == INVALID_FILE_ATTRIBUTES) {
        res = ERR(map_win_error(GetLastError()));
        goto out;
    }
    int adir = (fa & FILE_ATTRIBUTE_DIRECTORY) != 0;
    DWORD flags = MOVEFILE_REPLACE_EXISTING;
    if (adir) {
        /* MOVEFILE_REPLACE_EXISTING does not apply to directories (and some systems let it replace a file by a
         * directory): the Linux rules are applied here. A directory replaces an empty one, never a file. */
        flags = 0;
        DWORD fb = attrs_of(b.p);
        if (fb != INVALID_FILE_ATTRIBUTES) {
            if (!(fb & FILE_ATTRIBUTE_DIRECTORY)) {
                res = ERR(L_ENOTDIR);
                goto out;
            }
            if (!RemoveDirectoryW(b.p)) { /* ERROR_DIR_NOT_EMPTY -> ENOTEMPTY */
                res = ERR(map_win_error(GetLastError()));
                goto out;
            }
        }
    }
    for (int tries = 0;; tries++) {
        if (MoveFileExW(a.p, b.p, flags))
            break;
        DWORD e = GetLastError();
        if (e == ERROR_ACCESS_DENIED || e == ERROR_ALREADY_EXISTS || e == ERROR_FILE_EXISTS ||
            e == ERROR_SHARING_VIOLATION || e == ERROR_LOCK_VIOLATION) {
            DWORD fb = attrs_of(b.p);
            if (!adir && fb != INVALID_FILE_ATTRIBUTES && (fb & FILE_ATTRIBUTE_DIRECTORY)) {
                res = ERR(L_EISDIR); /* a file onto a directory */
                break;
            }
            if (attrs_of(a.p) == INVALID_FILE_ATTRIBUTES) { /* the source vanished meanwhile */
                res = ERR(L_ENOENT);
                break;
            }
            if (tries < RETRIES) { /* somebody (a scanner) has one of the files open without sharing for a moment */
                backoff(tries);
                continue;
            }
        }
        res = ERR(map_win_error(e));
        break;
    }
out:
    wpath_free(&a);
    wpath_free(&b);
    return res;
}

static int64_t sys_mkdir(const char *path, int mode)
{
    (void)mode;
    WPATH w;
    int r = wpath_set(&w, path);
    if (r)
        return r;
    int64_t res = 0;
    if (!CreateDirectoryW(w.p, NULL)) {
        res = ERR(map_win_error(GetLastError()));
        /* mkdir on something that exists is EEXIST whatever Windows called it: a drive root, a share or a system
         * folder answers "access denied" or worse (mkdir_p makes every prefix of a path and relies on EEXIST). */
        if (attrs_of(w.p) != INVALID_FILE_ATTRIBUTES)
            res = ERR(L_EEXIST);
    }
    wpath_free(&w);
    return res;
}

static int64_t sys_rmdir(const char *path)
{
    WPATH w;
    int r = wpath_set(&w, path);
    if (r)
        return r;
    int64_t res = 0;
    for (int tries = 0;; tries++) {
        if (RemoveDirectoryW(w.p))
            break;
        DWORD e = GetLastError();
        if (e == ERROR_DIRECTORY) {
            res = ERR(L_ENOTDIR);
            break;
        }
        if (e == ERROR_ACCESS_DENIED || e == ERROR_SHARING_VIOLATION || e == ERROR_LOCK_VIOLATION ||
            e == ERROR_DIR_NOT_EMPTY) {
            DWORD a = attrs_of(w.p);
            if (a != INVALID_FILE_ATTRIBUTES && !(a & FILE_ATTRIBUTE_DIRECTORY)) {
                res = ERR(L_ENOTDIR);
                break;
            }
            if (a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_READONLY) && tries == 0) {
                SetFileAttributesW(w.p, a & ~(DWORD)FILE_ATTRIBUTE_READONLY); /* rmdir ignores that attribute */
                continue;
            }
            /* files that are being deleted, or a scanner that still has something open, keep a directory
             * non-empty or busy for a moment */
            if (tries < RETRIES) {
                backoff(tries);
                continue;
            }
        }
        res = ERR(map_win_error(e));
        break;
    }
    wpath_free(&w);
    return res;
}

static int64_t sys_unlink(const char *path)
{
    WPATH w;
    int r = wpath_set(&w, path);
    if (r)
        return r;
    int64_t res = 0;
    for (int tries = 0;; tries++) {
        if (DeleteFileW(w.p))
            break;
        DWORD e = GetLastError();
        if (e == ERROR_ACCESS_DENIED || e == ERROR_SHARING_VIOLATION || e == ERROR_LOCK_VIOLATION) {
            DWORD a = attrs_of(w.p);
            if (a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY)) {
                res = ERR(L_EISDIR);
                break;
            }
            if (a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_READONLY) && tries == 0) {
                SetFileAttributesW(w.p, a & ~(DWORD)FILE_ATTRIBUTE_READONLY); /* unlink ignores that attribute */
                continue;
            }
            if (tries < RETRIES) {
                backoff(tries);
                continue;
            }
        }
        res = ERR(map_win_error(e));
        break;
    }
    wpath_free(&w);
    return res;
}

/* getdents64(fd, buf, count): struct linux_dirent64 { u64 d_ino; s64 d_off; u16 d_reclen; u8 d_type; char
 * d_name[]; } records, each padded to 8 bytes. Returns the bytes stored, 0 at the end, -EINVAL when not even one
 * record fits. */
static int64_t sys_getdents64(int fd, void *buf, size_t cap)
{
    FDENT e;
    int r = fd_get(fd, &e);
    if (r)
        return r;
    if (e.kind != K_DIR)
        return ERR(L_ENOTDIR);
    if (!buf)
        return ERR(L_EFAULT);
    DIRST *d = e.u.dir;
    unsigned char *out = (unsigned char *)buf;
    size_t used = 0;
    for (;;) {
        if (!d->pending) {
            int f = dir_fetch(d);
            if (f < 0) {
                if (used)
                    break; /* deliver what there is; the error ends the stream (stage 3) */
                return f;
            }
            if (f == 0)
                break;
            d->pending = 1;
        }
        size_t reclen = (19 + (size_t)d->namelen + 1 + 7) & ~(size_t)7;
        if (used + reclen > cap) {
            if (used == 0)
                return ERR(L_EINVAL); /* the buffer cannot hold even one record */
            break;                    /* the entry waits for the next call */
        }
        unsigned char *rec = out + used;
        uint64_t ino = d->pos + 1, off = d->pos + 1;
        uint16_t rl = (uint16_t)reclen;
        memset(rec, 0, reclen);
        memcpy(rec + 0, &ino, 8);
        memcpy(rec + 8, &off, 8);
        memcpy(rec + 16, &rl, 2);
        rec[18] = d->type;
        memcpy(rec + 19, d->name, d->namelen + 1);
        used += reclen;
        d->pos++;
        d->pending = 0;
    }
    return (int64_t)used;
}

/* ===================================================================================================== */
/* time, clocks, random numbers, memory, scheduling                                                      */
/* ===================================================================================================== */

static int64_t sys_time(int64_t *tloc)
{
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    int64_t s, ns;
    ft_to_unix(ft_u64(ft), &s, &ns);
    if (tloc)
        *tloc = s;
    return s;
}

static int64_t sys_clock_gettime(int clk, int64_t *ts)
{
    int64_t sec, nsec;
    base_once();
    switch (clk) {
    case L_CLOCK_REALTIME:
    case L_CLOCK_REALTIME_COARSE: {
        FILETIME ft;
        if (g_precise_time)
            g_precise_time(&ft);
        else
            GetSystemTimeAsFileTime(&ft);
        ft_to_unix(ft_u64(ft), &sec, &nsec);
        break;
    }
    case L_CLOCK_MONOTONIC:
    case L_CLOCK_MONOTONIC_RAW:
    case L_CLOCK_MONOTONIC_COARSE:
    case L_CLOCK_BOOTTIME: {
        LARGE_INTEGER c;
        QueryPerformanceCounter(&c);
        uint64_t t = (uint64_t)c.QuadPart, f = (uint64_t)g_qpf;
        sec = (int64_t)(t / f);
        nsec = (int64_t)(((t % f) * 1000000000u) / f); /* (t % f) < f <= a few GHz: the product fits 64 bits */
        break;
    }
    default:
        return ERR(L_EINVAL);
    }
    if (!ts)
        return ERR(L_EFAULT);
    ts[0] = sec;
    ts[1] = nsec;
    return 0;
}

static int64_t sys_getrandom(void *buf, size_t n, unsigned flags)
{
    if (flags & ~(L_GRND_NONBLOCK | L_GRND_RANDOM | L_GRND_INSECURE))
        return ERR(L_EINVAL);
    if ((flags & L_GRND_RANDOM) && (flags & L_GRND_INSECURE))
        return ERR(L_EINVAL);
    if (n == 0)
        return 0;
    if (!buf)
        return ERR(L_EFAULT);
    if (n > 33554431u) /* what one call delivers on Linux (32 MiB - 1) */
        n = 33554431u;
    if (BCryptGenRandom(NULL, (PUCHAR)buf, (ULONG)n, BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0)
        return ERR(L_EIO);
    return (int64_t)n;
}

static DWORD prot_to_win(int prot)
{
    int rd = (prot & L_PROT_READ) != 0, wr = (prot & L_PROT_WRITE) != 0, ex = (prot & L_PROT_EXEC) != 0;
    if (ex)
        return wr ? PAGE_EXECUTE_READWRITE : rd ? PAGE_EXECUTE_READ : PAGE_EXECUTE;
    if (wr)
        return PAGE_READWRITE;
    return rd ? PAGE_READONLY : PAGE_NOACCESS;
}

/* mmap: anonymous memory only (VirtualAlloc). A hint is honoured when the range is free; MAP_FIXED needs it. */
static int64_t sys_mmap(uint64_t addr, uint64_t len, int prot, int flags, int fd, int64_t off)
{
    (void)off;
    if (len == 0)
        return ERR(L_EINVAL);
    int shared = (flags & L_MAP_SHARED) != 0, priv = (flags & L_MAP_PRIVATE) != 0;
    if (shared == priv)
        return ERR(L_EINVAL); /* exactly one of MAP_SHARED / MAP_PRIVATE */
    if (!(flags & L_MAP_ANONYMOUS) || fd != -1)
        return ERR(L_ENODEV); /* file mappings are not emulated */
    if (len > ((uint64_t)1 << 47))
        return ERR(L_ENOMEM);
    DWORD protect = prot_to_win(prot);
    void *p = NULL;
    if (addr) {
        p = VirtualAlloc((void *)(uintptr_t)addr, (SIZE_T)len, MEM_RESERVE | MEM_COMMIT, protect);
        if (!p && (flags & L_MAP_FIXED))
            return ERR(L_ENOMEM);
    }
    if (!p)
        p = VirtualAlloc(NULL, (SIZE_T)len, MEM_RESERVE | MEM_COMMIT, protect);
    if (!p)
        return ERR(L_ENOMEM);
    return (int64_t)(uintptr_t)p;
}

/* munmap: a whole VirtualAlloc region is released; part of one is decommitted (its addresses stay reserved
 * but fault, like unmapped ones). Unmapping what is not mapped succeeds, as on Linux. */
static int64_t sys_munmap(uint64_t addr, uint64_t len)
{
    base_once();
    if ((addr & (g_page - 1)) || len == 0)
        return ERR(L_EINVAL);
    len = (len + g_page - 1) & ~((uint64_t)g_page - 1);
    MEMORY_BASIC_INFORMATION mbi;
    if (!VirtualQuery((void *)(uintptr_t)addr, &mbi, sizeof mbi))
        return ERR(L_EINVAL);
    if (mbi.State == MEM_FREE)
        return 0;
    if (mbi.AllocationBase == (void *)(uintptr_t)addr) {
        uint64_t total = 0, p = addr;
        MEMORY_BASIC_INFORMATION m2;
        while (VirtualQuery((void *)(uintptr_t)p, &m2, sizeof m2) && m2.AllocationBase == (void *)(uintptr_t)addr) {
            total += m2.RegionSize;
            p += m2.RegionSize;
        }
        if (len >= total)
            return VirtualFree((void *)(uintptr_t)addr, 0, MEM_RELEASE) ? 0 : ERR(map_win_error(GetLastError()));
    }
    return VirtualFree((void *)(uintptr_t)addr, (SIZE_T)len, MEM_DECOMMIT) ? 0 : ERR(map_win_error(GetLastError()));
}

/* sched_yield: give the CPU to another ready thread; when none wants it the system is idle (callers spin on
 * sched_yield while they wait for something to arrive) and a millisecond's nap loses nothing. */
static int64_t sys_sched_yield(void)
{
    if (!SwitchToThread())
        Sleep(1);
    return 0;
}

/* ===================================================================================================== */
/* Sockets                                                                                               */
/* ===================================================================================================== */

static INIT_ONCE g_wsa_once = INIT_ONCE_STATIC_INIT;
static int g_wsa_err;

static BOOL CALLBACK wsa_init(PINIT_ONCE once, PVOID param, PVOID *ctx)
{
    (void)once;
    (void)param;
    (void)ctx;
    WSADATA d;
    g_wsa_err = WSAStartup(MAKEWORD(2, 2), &d);
    return TRUE;
}

static int wsa_ready(void)
{
    InitOnceExecuteOnce(&g_wsa_once, wsa_init, NULL, NULL);
    return g_wsa_err == 0;
}

static int64_t serr(void) { return ERR(map_wsa_error(WSAGetLastError())); }

/* The slot of a socket fd. */
static int fd_sock(int fd, FDENT *e)
{
    int r = fd_get(fd, e);
    if (r)
        return r;
    return e->kind == K_SOCK ? 0 : -L_ENOTSOCK;
}

static int64_t sys_socket(int domain, int type, int protocol)
{
    if (domain != L_AF_INET)
        return ERR(L_EAFNOSUPPORT);
    if (type & ~(L_SOCK_TYPE_MASK | L_SOCK_NONBLOCK | L_SOCK_CLOEXEC))
        return ERR(L_EINVAL);
    int t = type & L_SOCK_TYPE_MASK;
    int wtype, wproto;
    if (t == L_SOCK_DGRAM) {
        if (protocol != 0 && protocol != L_IPPROTO_UDP)
            return ERR(L_EPROTONOSUPPORT);
        wtype = SOCK_DGRAM;
        wproto = IPPROTO_UDP;
    } else if (t == L_SOCK_STREAM) {
        if (protocol != 0 && protocol != L_IPPROTO_TCP)
            return ERR(L_EPROTONOSUPPORT);
        wtype = SOCK_STREAM;
        wproto = IPPROTO_TCP;
    } else {
        return ERR(L_ESOCKTNOSUPPORT);
    }
    if (!wsa_ready())
        return ERR(L_ENETDOWN);
    SOCKET s = socket(AF_INET, wtype, wproto);
    if (s == INVALID_SOCKET)
        return serr();
    SetHandleInformation((HANDLE)s, HANDLE_FLAG_INHERIT, 0); /* SOCK_CLOEXEC, always */
    if (t == L_SOCK_DGRAM) {
        /* Without this a datagram sent to a closed port makes a later recvfrom fail with WSAECONNRESET. */
        DWORD ret = 0;
        BOOL off = FALSE;
        WSAIoctl(s, SIO_UDP_CONNRESET, &off, sizeof off, NULL, 0, &ret, NULL, NULL);
        WSAIoctl(s, SIO_UDP_NETRESET, &off, sizeof off, NULL, 0, &ret, NULL, NULL);
    }
    int nonblock = (type & L_SOCK_NONBLOCK) != 0;
    if (nonblock) {
        u_long nb = 1;
        if (ioctlsocket(s, FIONBIO, &nb) != 0) {
            int64_t r = serr();
            closesocket(s);
            return r;
        }
    }
    FDENT ent;
    memset(&ent, 0, sizeof ent);
    ent.kind = K_SOCK;
    ent.acc = L_O_RDWR;
    ent.nonblock = (unsigned char)nonblock;
    ent.stype = (unsigned char)t;
    ent.u.s = s;
    int fd = fd_alloc(&ent);
    if (fd < 0)
        closesocket(s);
    return fd;
}

/* Reads a sockaddr_in handed over by the caller. 0 or -errno. */
static int sockaddr_in_get(const void *addr, uint32_t alen, struct sockaddr_in *sa)
{
    if (!addr)
        return -L_EFAULT;
    if (alen < sizeof *sa)
        return -L_EINVAL;
    memcpy(sa, addr, sizeof *sa);
    if (sa->sin_family != AF_INET)
        return -L_EAFNOSUPPORT;
    return 0;
}

static int64_t sys_bind(int fd, const void *addr, uint32_t alen)
{
    FDENT e;
    int r = fd_sock(fd, &e);
    if (r)
        return r;
    struct sockaddr_in sa;
    r = sockaddr_in_get(addr, alen, &sa);
    if (r)
        return r;
    if (bind(e.u.s, (struct sockaddr *)&sa, sizeof sa) == SOCKET_ERROR)
        return serr();
    return 0;
}

static int64_t sys_connect(int fd, const void *addr, uint32_t alen)
{
    FDENT e;
    int r = fd_sock(fd, &e);
    if (r)
        return r;
    struct sockaddr_in sa;
    r = sockaddr_in_get(addr, alen, &sa);
    if (r)
        return r;
    if (connect(e.u.s, (struct sockaddr *)&sa, sizeof sa) == SOCKET_ERROR) {
        int w = WSAGetLastError();
        return ERR(w == WSAEWOULDBLOCK ? L_EINPROGRESS : map_wsa_error(w));
    }
    return 0;
}

static int64_t sys_getsockname(int fd, void *addr, uint32_t *alenp)
{
    FDENT e;
    int r = fd_sock(fd, &e);
    if (r)
        return r;
    if (!addr || !alenp)
        return ERR(L_EFAULT);
    struct sockaddr_in sa;
    int sl = (int)sizeof sa;
    memset(&sa, 0, sizeof sa);
    if (getsockname(e.u.s, (struct sockaddr *)&sa, &sl) == SOCKET_ERROR) {
        int w = WSAGetLastError();
        if (w != WSAEINVAL)
            return ERR(map_wsa_error(w));
        memset(&sa, 0, sizeof sa); /* Winsock refuses an unbound socket; Linux answers 0.0.0.0:0 */
        sa.sin_family = AF_INET;
    }
    uint32_t cap = *alenp, n = cap < sizeof sa ? cap : (uint32_t)sizeof sa;
    memcpy(addr, &sa, n);
    *alenp = (uint32_t)sizeof sa; /* the real size, as the kernel reports it even when it truncated */
    return 0;
}

/* Linux MSG_* -> Winsock; *dontwait says MSG_DONTWAIT was given (Winsock has no such flag). */
static int msg_flags(int lf, int *dontwait)
{
    int w = 0;
    if (lf & L_MSG_OOB)
        w |= MSG_OOB;
    if (lf & L_MSG_PEEK)
        w |= MSG_PEEK;
    if (lf & L_MSG_DONTROUTE)
        w |= MSG_DONTROUTE;
    if (lf & L_MSG_WAITALL)
        w |= MSG_WAITALL;
    *dontwait = (lf & L_MSG_DONTWAIT) != 0;
    return w; /* MSG_NOSIGNAL and anything unknown: nothing to do */
}

/* MSG_DONTWAIT on a blocking socket: non-blocking for the length of one call. */
static int dontwait_on(const FDENT *e, int dontwait)
{
    if (dontwait && !e->nonblock) {
        u_long nb = 1;
        ioctlsocket(e->u.s, FIONBIO, &nb);
        return 1;
    }
    return 0;
}

static void dontwait_off(const FDENT *e, int toggled)
{
    if (toggled) {
        u_long nb = 0;
        ioctlsocket(e->u.s, FIONBIO, &nb);
    }
}

/* A send/receive timeout (SO_SNDTIMEO / SO_RCVTIMEO) shows up as EAGAIN on Linux, not ETIMEDOUT. */
static int64_t io_error(void)
{
    int w = WSAGetLastError();
    return ERR(w == WSAETIMEDOUT ? L_EAGAIN : map_wsa_error(w));
}

static int64_t sys_sendto(int fd, const void *buf, size_t len, int flags, const void *addr, uint32_t alen)
{
    FDENT e;
    int r = fd_sock(fd, &e);
    if (r)
        return r;
    if (len && !buf)
        return ERR(L_EFAULT);
    int dontwait;
    int wf = msg_flags(flags, &dontwait);
    int n = len > (size_t)INT_MAX ? INT_MAX : (int)len;
    struct sockaddr_in sa;
    if (addr) {
        r = sockaddr_in_get(addr, alen, &sa);
        if (r)
            return r;
    }
    int tog = dontwait_on(&e, dontwait);
    int got = addr ? sendto(e.u.s, (const char *)buf, n, wf, (struct sockaddr *)&sa, sizeof sa)
                   : send(e.u.s, (const char *)buf, n, wf);
    int64_t res = got == SOCKET_ERROR ? io_error() : got;
    dontwait_off(&e, tog);
    return res;
}

static int64_t sys_recvfrom(int fd, void *buf, size_t len, int flags, void *addr, uint32_t *alenp)
{
    FDENT e;
    int r = fd_sock(fd, &e);
    if (r)
        return r;
    if (len && !buf)
        return ERR(L_EFAULT);
    int dontwait;
    int wf = msg_flags(flags, &dontwait);
    int n = len > (size_t)INT_MAX ? INT_MAX : (int)len;
    struct sockaddr_in sa;
    int sl = (int)sizeof sa;
    int want_addr = addr != NULL && alenp != NULL;
    memset(&sa, 0, sizeof sa);
    int tog = dontwait_on(&e, dontwait);
    int got = recvfrom(e.u.s, (char *)buf, n, wf, want_addr ? (struct sockaddr *)&sa : NULL, want_addr ? &sl : NULL);
    int werr = got == SOCKET_ERROR ? WSAGetLastError() : 0;
    dontwait_off(&e, tog);
    if (got == SOCKET_ERROR) {
        if (werr != WSAEMSGSIZE) /* a datagram larger than the buffer: Linux returns the part that fits */
            return ERR(werr == WSAETIMEDOUT ? L_EAGAIN : map_wsa_error(werr));
        got = n;
    }
    if (want_addr) {
        uint32_t cap = *alenp, c = cap < sizeof sa ? cap : (uint32_t)sizeof sa;
        memcpy(addr, &sa, c);
        *alenp = (uint32_t)sizeof sa;
    }
    return got;
}

static int64_t sock_read(const FDENT *e, void *buf, size_t n)
{
    if (n && !buf)
        return ERR(L_EFAULT);
    int got = recv(e->u.s, (char *)buf, n > (size_t)INT_MAX ? INT_MAX : (int)n, 0);
    return got == SOCKET_ERROR ? io_error() : got;
}

static int64_t sock_write(const FDENT *e, const void *buf, size_t n)
{
    if (n && !buf)
        return ERR(L_EFAULT);
    int got = send(e->u.s, (const char *)buf, n > (size_t)INT_MAX ? INT_MAX : (int)n, 0);
    return got == SOCKET_ERROR ? io_error() : got;
}

/* setsockopt: Linux option numbers and value layouts -> Winsock. Options Windows lacks and that only tune
 * performance are accepted and ignored; unknown ones are -ENOPROTOOPT. */
static int64_t sys_setsockopt(int fd, int level, int opt, const void *val, uint32_t vlen)
{
    FDENT e;
    int r = fd_sock(fd, &e);
    if (r)
        return r;
    if (!val)
        return ERR(L_EFAULT);
    int wl, wo;
    int is_bool = 0, is_int = 1;
    union {
        int i;
        DWORD ms;
        struct linger lg;
    } cv;
    const char *pv;
    int pl;

    if (level == L_SOL_SOCKET) {
        wl = SOL_SOCKET;
        switch (opt) {
        case L_SO_DEBUG: wo = SO_DEBUG; is_bool = 1; break;
        case L_SO_REUSEADDR:
        case L_SO_REUSEPORT: wo = SO_REUSEADDR; is_bool = 1; break; /* the closest thing Winsock has */
        case L_SO_DONTROUTE: wo = SO_DONTROUTE; is_bool = 1; break;
        case L_SO_BROADCAST: wo = SO_BROADCAST; is_bool = 1; break;
        case L_SO_SNDBUF:
        case L_SO_SNDBUFFORCE: wo = SO_SNDBUF; break;
        case L_SO_RCVBUF:
        case L_SO_RCVBUFFORCE: wo = SO_RCVBUF; break;
        case L_SO_KEEPALIVE:
        case L_SO_OOBINLINE:
        case L_SO_LINGER:
            if (e.stype == L_SOCK_DGRAM) /* meaningless for datagrams: Linux takes them, Winsock refuses */
                return vlen >= (opt == L_SO_LINGER ? 2 * sizeof(int) : sizeof(int)) ? 0 : ERR(L_EINVAL);
            wo = opt == L_SO_KEEPALIVE ? SO_KEEPALIVE : opt == L_SO_OOBINLINE ? SO_OOBINLINE : SO_LINGER;
            is_bool = opt != L_SO_LINGER;
            is_int = opt != L_SO_LINGER;
            break;
        case L_SO_RCVTIMEO:
        case L_SO_SNDTIMEO:
            wo = opt == L_SO_RCVTIMEO ? SO_RCVTIMEO : SO_SNDTIMEO;
            is_int = 0;
            break;
        case L_SO_NO_CHECK:
        case L_SO_PRIORITY:
        case L_SO_BSDCOMPAT:
        case L_SO_RCVLOWAT:
        case L_SO_SNDLOWAT:
            return 0; /* nothing to tune on Windows */
        default:
            return ERR(L_ENOPROTOOPT);
        }
    } else if (level == L_IPPROTO_IP) {
        wl = IPPROTO_IP;
        switch (opt) {
        case L_IP_TOS: wo = IP_TOS; break;
        case L_IP_TTL: wo = IP_TTL; break;
        case L_IP_MULTICAST_TTL: wo = IP_MULTICAST_TTL; break;
        case L_IP_MULTICAST_LOOP: wo = IP_MULTICAST_LOOP; is_bool = 1; break;
        case L_IP_MULTICAST_IF: wo = IP_MULTICAST_IF; is_int = 0; break;
        case L_IP_ADD_MEMBERSHIP: wo = IP_ADD_MEMBERSHIP; is_int = 0; break;
        case L_IP_DROP_MEMBERSHIP: wo = IP_DROP_MEMBERSHIP; is_int = 0; break;
        default: return ERR(L_ENOPROTOOPT);
        }
    } else if (level == L_IPPROTO_TCP) {
        wl = IPPROTO_TCP;
        if (opt != L_TCP_NODELAY)
            return ERR(L_ENOPROTOOPT);
        wo = TCP_NODELAY;
        is_bool = 1;
    } else {
        return ERR(L_ENOPROTOOPT);
    }

    if (is_int) { /* an int on Linux (a one-byte value is accepted for the IP options, as there) */
        if (vlen >= sizeof(int)) {
            memcpy(&cv.i, val, sizeof(int));
        } else if (vlen == 1 && level == L_IPPROTO_IP) {
            cv.i = *(const unsigned char *)val;
        } else {
            return ERR(L_EINVAL);
        }
        if (is_bool)
            cv.i = cv.i != 0;
        pv = (const char *)&cv.i;
        pl = (int)sizeof cv.i;
    } else if (wl == SOL_SOCKET && wo == SO_LINGER) { /* struct linger { int onoff; int linger; } */
        int lv[2];
        if (vlen < sizeof lv)
            return ERR(L_EINVAL);
        memcpy(lv, val, sizeof lv);
        cv.lg.l_onoff = (u_short)(lv[0] != 0);
        cv.lg.l_linger = (u_short)(lv[1] < 0 ? 0 : lv[1] > 65535 ? 65535 : lv[1]);
        pv = (const char *)&cv.lg;
        pl = (int)sizeof cv.lg;
    } else if (wl == SOL_SOCKET) { /* SO_RCVTIMEO / SO_SNDTIMEO: struct timeval { s64 sec; s64 usec } -> ms */
        int64_t tv[2];
        if (vlen < sizeof tv)
            return ERR(L_EINVAL);
        memcpy(tv, val, sizeof tv);
        if (tv[0] < 0 || tv[1] < 0 || tv[1] >= 1000000)
            return ERR(L_EINVAL);
        uint64_t ms = (uint64_t)tv[0] * 1000u + (uint64_t)tv[1] / 1000u;
        if (ms == 0 && tv[1] > 0)
            ms = 1; /* a sub-millisecond timeout must not turn into "wait forever" */
        cv.ms = ms > 0x7fffffffu ? 0x7fffffffu : (DWORD)ms;
        pv = (const char *)&cv.ms;
        pl = (int)sizeof cv.ms;
    } else { /* IP_MULTICAST_IF (struct in_addr) and the memberships (struct ip_mreq): same layout on both */
        pv = (const char *)val;
        pl = (int)vlen;
    }
    if (setsockopt(e.u.s, wl, wo, pv, pl) == SOCKET_ERROR)
        return serr();
    return 0;
}

/* ===================================================================================================== */
/* The entry point                                                                                       */
/* ===================================================================================================== */

#define PTR(x) ((void *)(uintptr_t)(x))

SYSV int64_t win_syscall(int64_t nr, int64_t a1, int64_t a2, int64_t a3, int64_t a4, int64_t a5, int64_t a6)
{
    switch (nr) {
    case NR_READ:
        return sys_read((int)a1, PTR(a2), (size_t)a3);
    case NR_WRITE:
        return sys_write((int)a1, PTR(a2), (size_t)a3);
    case NR_OPEN:
        return sys_open((const char *)PTR(a1), (int)a2, (int)a3);
    case NR_CLOSE:
        return sys_close((int)a1);
    case NR_STAT:
        return sys_stat((const char *)PTR(a1), PTR(a2));
    case NR_FSTAT:
        return sys_fstat((int)a1, PTR(a2));
    case NR_LSEEK:
        return sys_lseek((int)a1, a2, (int)a3);
    case NR_MMAP:
        return sys_mmap((uint64_t)a1, (uint64_t)a2, (int)a3, (int)a4, (int)a5, a6);
    case NR_MUNMAP:
        return sys_munmap((uint64_t)a1, (uint64_t)a2);
    case NR_PREAD64:
        return sys_pio((int)a1, PTR(a2), (size_t)a3, a4, 0);
    case NR_PWRITE64:
        return sys_pio((int)a1, PTR(a2), (size_t)a3, a4, 1);
    case NR_SCHED_YIELD:
        return sys_sched_yield();
    case NR_SOCKET:
        return sys_socket((int)a1, (int)a2, (int)a3);
    case NR_CONNECT:
        return sys_connect((int)a1, PTR(a2), (uint32_t)a3);
    case NR_SENDTO:
        return sys_sendto((int)a1, PTR(a2), (size_t)a3, (int)a4, PTR(a5), (uint32_t)a6);
    case NR_RECVFROM:
        return sys_recvfrom((int)a1, PTR(a2), (size_t)a3, (int)a4, PTR(a5), (uint32_t *)PTR(a6));
    case NR_BIND:
        return sys_bind((int)a1, PTR(a2), (uint32_t)a3);
    case NR_GETSOCKNAME:
        return sys_getsockname((int)a1, PTR(a2), (uint32_t *)PTR(a3));
    case NR_SETSOCKOPT:
        return sys_setsockopt((int)a1, (int)a2, (int)a3, PTR(a4), (uint32_t)a5);
    case NR_RENAME:
        return sys_rename((const char *)PTR(a1), (const char *)PTR(a2));
    case NR_MKDIR:
        return sys_mkdir((const char *)PTR(a1), (int)a2);
    case NR_RMDIR:
        return sys_rmdir((const char *)PTR(a1));
    case NR_UNLINK:
        return sys_unlink((const char *)PTR(a1));
    case NR_TIME:
        return sys_time((int64_t *)PTR(a1));
    case NR_GETDENTS64:
        return sys_getdents64((int)a1, PTR(a2), (size_t)a3);
    case NR_CLOCK_GETTIME:
        return sys_clock_gettime((int)a1, (int64_t *)PTR(a2));
    case NR_GETRANDOM:
        return sys_getrandom(PTR(a1), (size_t)a2, (unsigned)a3);
    default:
        return ERR(L_ENOSYS);
    }
}
