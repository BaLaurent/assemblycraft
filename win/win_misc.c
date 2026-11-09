/* win_misc.c - process entry, threads, sleep and audio of the Windows platform layer.
 *
 * The game's assembly is assembled with --gprefix w_ and follows the System V AMD64 convention, so every
 * function below that the game calls is declared SYSV (win.h) and mingw-gcc does the Win64 <-> SysV
 * translation. Calls out of here into Win32 use the normal convention.
 *
 * Exports
 *   main                         process entry: UTF-8 argv and envp, then the game's `main` (w_main)
 *   w_pthread_create/join        threads (CreateThread, 8 MiB stack, like a glibc thread)
 *   w_pthread_mutex_lock/unlock, w_pthread_cond_wait/signal/broadcast
 *                                SRWLOCK / CONDITION_VARIABLE on all-zero statics (= the POSIX initialisers)
 *   w_usleep                     microsecond sleep, never early
 *   w_pa_simple_new/write/free   the part of libpulse-simple the game uses, on top of waveOut
 * Link: -lwinmm (timeBeginPeriod and waveOut); shell32 and kernel32 are mingw's default libraries.
 *
 * Audio design (src/audio.asm): once per frame the main thread mixes dt seconds of 44.1 kHz stereo S16 and
 * writes them; the write blocks while the device holds too much, which keeps the audio in step with the
 * frame clock. Here: a ring of PA_RING_N waveOut buffers of 10 ms each, completion signalled through an
 * event, the number of unplayed frames tracked from the WHDR_DONE flags.
 *   - steady-state lead ("prime"): 40 ms. The first write, and every write after the device ran dry, first
 *     queues silence so that the lead is 40 ms again - PulseAudio's prebuf does the same - which is what
 *     absorbs frame-time jitter. Total latency is that lead plus the Windows audio engine's own (~20-40 ms).
 *   - ceiling ("cap"): 100 ms, then the write blocks, in pieces, until the queue is down to 50 ms (hysteresis).
 *     A lead of 40 plus a worst-case 46 ms burst after a long frame, and the up-to-10 ms by which whole-buffer
 *     completions overstate it, stay well below that, so a healthy stream never blocks: a write that waited
 *     for room would stretch its frame, the next write would be bigger, and the loop would stay audio-bound.
 *     Only a device slower than the clock reaches the ceiling, and then once per many seconds.
 *   - the unplayed tail of a write is held back (up to one buffer) while at least 20 ms are queued ahead of it
 *     and sent as soon as less is queued, so small writes (fast frame rates) do not use up ring buffers.
 *   - a device that stops returning buffers is reset (waveOutReset) after 200 ms; three resets in a row
 *     without a healthy wait in between, or a failing waveOutWrite, end the stream: write then fails at once
 *     (the game ignores the result and carries on without sound).
 * No device, or a format the device refuses: pa_simple_new returns NULL with *error set (audio_init then
 * reports "sound disabled" and the game runs silently).
 */
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <shellapi.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include "win.h"

#ifndef CREATE_WAITABLE_TIMER_HIGH_RESOLUTION
#define CREATE_WAITABLE_TIMER_HIGH_RESOLUTION 0x00000002
#endif

extern SYSV int w_main(int argc, char **argv, char **envp);

/* ================================================================================================== */
/* 1. process entry                                                                                    */
/* ================================================================================================== */

/* UTF-8 size of w[0..wlen) (out == NULL), or the conversion into out. No NUL is written. */
static int utf8_of(const WCHAR *w, int wlen, char *out)
{
    if (wlen <= 0)
        return 0;
    return WideCharToMultiByte(CP_UTF8, 0, w, wlen, out, out ? INT_MAX : 0, NULL, NULL);
}

/* Splits a command line with CommandLineToArgvW's rules into a NULL-terminated UTF-8 argv, all in ONE heap
 * block that lives for the whole run. Returns NULL on failure; *argc is the count. */
static char **build_args(const WCHAR *cmdline, int *argc)
{
    int n = 0;
    WCHAR **w = CommandLineToArgvW(cmdline, &n);
    char **argv = NULL;
    char *pool;
    size_t bytes;

    if (!w)
        return NULL;
    bytes = ((size_t)n + 1) * sizeof(char *);
    for (int i = 0; i < n; i++)
        bytes += (size_t)utf8_of(w[i], (int)wcslen(w[i]), NULL) + 1;
    argv = HeapAlloc(GetProcessHeap(), 0, bytes);
    if (argv) {
        pool = (char *)(argv + n + 1);
        for (int i = 0; i < n; i++) {
            int len = utf8_of(w[i], (int)wcslen(w[i]), pool);
            argv[i] = pool;
            pool[len] = 0;
            pool += len + 1;
        }
        argv[n] = NULL;
        *argc = n;
    }
    LocalFree(w);
    return argv;
}

#define XDG_NAME "XDG_DATA_HOME"
#define XDG_LEN  13

/* Does the variable name e[0..n) equal the ASCII string name, ignoring case (Windows names are)? */
static int name_is(const WCHAR *e, size_t n, const char *name)
{
    for (size_t i = 0; i < n; i++) {
        WCHAR c = e[i];
        if (c >= L'a' && c <= L'z')
            c = (WCHAR)(c - (L'a' - L'A'));
        if (name[i] == 0 || c != (WCHAR)(unsigned char)name[i])
            return 0;
    }
    return name[n] == 0;
}

/* The value of variable `name` in an environment block (NAME=VALUE\0 ... \0\0), or NULL. */
static const WCHAR *env_find(const WCHAR *block, const char *name)
{
    for (const WCHAR *e = block; *e; e += wcslen(e) + 1) {
        const WCHAR *eq = e;
        if (*e == L'=')
            continue;                   /* "=C:=C:\dir": a per-drive working directory, not a variable */
        while (*eq && *eq != L'=')
            eq++;
        if (*eq && name_is(e, (size_t)(eq - e), name))
            return eq + 1;
    }
    return NULL;
}

/* The path with '/' separators and no trailing separator, in a new heap block (no NUL), or NULL when it is
 * empty. *len receives the length. */
static WCHAR *slashed(const WCHAR *path, size_t *len)
{
    size_t n = wcslen(path);
    WCHAR *s;

    while (n > 0 && (path[n - 1] == L'\\' || path[n - 1] == L'/'))
        n--;
    if (n == 0)
        return NULL;
    s = HeapAlloc(GetProcessHeap(), 0, n * sizeof(WCHAR));
    if (!s)
        return NULL;
    for (size_t i = 0; i < n; i++)
        s[i] = path[i] == L'\\' ? L'/' : path[i];
    *len = n;
    return s;
}

/* One walk over the block. With vec == NULL it only measures; otherwise it fills vec[] and the string pool.
 * Returns the pool bytes; *count receives the number of entries. XDG_DATA_HOME is written with that exact
 * (upper-case) name, because the game matches it case-sensitively; when it is empty it is left out, because
 * the game would skip it too. `home` (not NULL) is appended as XDG_DATA_HOME=<home>. */
static size_t env_pass(const WCHAR *block, const WCHAR *home, size_t home_len, char **vec, char *pool,
                       size_t *count)
{
    size_t n = 0, off = 0;

    for (const WCHAR *e = block; *e; e += wcslen(e) + 1) {
        size_t len = wcslen(e);
        const WCHAR *eq = e;
        int xdg = 0;

        if (*e == L'=')
            continue;
        while (*eq && *eq != L'=')
            eq++;
        if (*eq && name_is(e, (size_t)(eq - e), XDG_NAME)) {
            if (!eq[1])
                continue;
            xdg = 1;
        }
        if (vec)
            vec[n] = pool + off;
        if (xdg) {
            if (pool)
                memcpy(pool + off, XDG_NAME "=", XDG_LEN + 1);
            off += XDG_LEN + 1;
            off += (size_t)utf8_of(eq + 1, (int)(len - (size_t)(eq + 1 - e)), pool ? pool + off : NULL);
        } else {
            off += (size_t)utf8_of(e, (int)len, pool ? pool + off : NULL);
        }
        if (pool)
            pool[off] = 0;
        off++;
        n++;
    }
    if (home) {
        if (vec)
            vec[n] = pool + off;
        if (pool)
            memcpy(pool + off, XDG_NAME "=", XDG_LEN + 1);
        off += XDG_LEN + 1;
        off += (size_t)utf8_of(home, (int)home_len, pool ? pool + off : NULL);
        if (pool)
            pool[off] = 0;
        off++;
        n++;
    }
    *count = n;
    return off;
}

/* The environment as a NULL-terminated array of UTF-8 "KEY=VALUE" strings (one heap block, kept for the whole
 * run). The game picks its data directory from XDG_DATA_HOME, then HOME; Windows has neither, so unless
 * XDG_DATA_HOME is set (and not empty) it is synthesised from %APPDATA% with forward slashes: the data
 * directory becomes %APPDATA%/assemblycraft, which the Win32 emulation of the file calls accepts. */
static char **build_env(const WCHAR *block)
{
    const WCHAR *xdg = env_find(block, XDG_NAME);
    const WCHAR *appdata = env_find(block, "APPDATA");
    WCHAR *home = NULL;
    size_t home_len = 0, n = 0, pool;
    char **vec;

    if ((!xdg || !xdg[0]) && appdata)
        home = slashed(appdata, &home_len);
    pool = env_pass(block, home, home_len, NULL, NULL, &n);
    vec = HeapAlloc(GetProcessHeap(), 0, (n + 1) * sizeof(char *) + pool);
    if (vec) {
        env_pass(block, home, home_len, vec, (char *)(vec + n + 1), &n);
        vec[n] = NULL;
    }
    if (home)
        HeapFree(GetProcessHeap(), 0, home);
    return vec;
}

#define STACK_PREGROW (256u << 10)

/* Linux grows the stack on any access; Windows commits it a page at a time through a guard page, so a frame
 * of a page or more whose far end is touched first would fault. The game's assembly never probes (rmdir_flat
 * has a 12 KB frame filled by getdents from its far end), so the first STACK_PREGROW bytes are committed here:
 * a frame this big makes the compiler probe every page in order, and committed pages stay committed. */
static void __attribute__((noinline)) pregrow_stack(void)
{
    char pad[STACK_PREGROW];

    __asm__ volatile("" : : "r"(pad) : "memory");   /* the array stays, and with it the probing of its frame */
}

int main(void)
{
    UINT old_cp = GetConsoleOutputCP();
    BOOL cp_set = old_cp != 0 && SetConsoleOutputCP(CP_UTF8);   /* the game prints UTF-8 */
    WCHAR *block = GetEnvironmentStringsW();
    int argc = 0, rc = 1;
    char **argv = build_args(GetCommandLineW(), &argc);
    char **envp = block ? build_env(block) : NULL;

    timeBeginPeriod(1);                 /* 1 ms timer: Sleep, waits and usleep are accurate to about a ms */
    if (block)
        FreeEnvironmentStringsW(block);
    if (argv && envp) {
        pregrow_stack();
        rc = w_main(argc, argv, envp);
    } else {
        fputs("assemblycraft: cannot read the command line or the environment\n", stderr);
    }
    fflush(NULL);
    timeEndPeriod(1);
    if (cp_set)
        SetConsoleOutputCP(old_cp);
    return rc;
}

/* ================================================================================================== */
/* 2. threads                                                                                          */
/* ================================================================================================== */

/* The pthread return codes the game could see: Linux's numbers. */
#define LX_ESRCH   3
#define LX_EAGAIN  11
#define LX_EINVAL  22
#define LX_EDEADLK 35

#define THREAD_STACK (8u << 20)         /* a glibc thread gets RLIMIT_STACK, 8 MiB */

typedef void *(SYSV *start_fn)(void *);

/* A running (or finished, not yet joined) thread. pthread_t is the HANDLE; the registry maps it back to
 * the start routine's result. */
typedef struct wthread {
    struct wthread *next;
    HANDLE handle;
    start_fn start;
    void *arg;
    void *result;
} wthread;

static SRWLOCK thr_lock = SRWLOCK_INIT;
static wthread *thr_list;

static DWORD WINAPI thread_entry(LPVOID param)
{
    wthread *t = param;

    t->result = t->start(t->arg);
    return 0;
}

/* int pthread_create(pthread_t *thread, const pthread_attr_t *attr, void *(*start)(void *), void *arg)
 * attr is ignored (the game always passes NULL). The 8 MiB stack is committed up front - the game's assembly
 * does not probe big frames, see pregrow_stack - and only if Windows refuses that much commit charge it is
 * merely reserved and committed as it grows. */
SYSV int w_pthread_create(uintptr_t *thread, const void *attr, start_fn start, void *arg)
{
    wthread *t;
    HANDLE h;

    (void)attr;
    if (!thread || !start)
        return LX_EINVAL;
    t = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof *t);
    if (!t)
        return LX_EAGAIN;
    t->start = start;
    t->arg = arg;
    h = CreateThread(NULL, THREAD_STACK, thread_entry, t, 0, NULL);
    if (!h)
        h = CreateThread(NULL, THREAD_STACK, thread_entry, t, STACK_SIZE_PARAM_IS_A_RESERVATION, NULL);
    if (!h) {
        HeapFree(GetProcessHeap(), 0, t);
        return LX_EAGAIN;
    }
    t->handle = h;
    AcquireSRWLockExclusive(&thr_lock);
    t->next = thr_list;
    thr_list = t;
    ReleaseSRWLockExclusive(&thr_lock);
    *thread = (uintptr_t)h;
    return 0;
}

/* int pthread_join(pthread_t thread, void **retval): waits for the thread, stores its result in *retval
 * (when not NULL) and releases it. A thread that is not (or no longer) known gives ESRCH, joining oneself
 * EDEADLK. */
SYSV int w_pthread_join(uintptr_t thread, void **retval)
{
    HANDLE h = (HANDLE)thread;
    wthread *t = NULL, **pp;
    int rc = 0;

    if (GetThreadId(h) == GetCurrentThreadId())
        return LX_EDEADLK;
    AcquireSRWLockExclusive(&thr_lock);
    for (pp = &thr_list; *pp; pp = &(*pp)->next) {
        if ((*pp)->handle == h) {
            t = *pp;
            *pp = t->next;
            break;
        }
    }
    ReleaseSRWLockExclusive(&thr_lock);
    if (!t)
        return LX_ESRCH;
    if (WaitForSingleObject(h, INFINITE) == WAIT_OBJECT_0) {
        if (retval)
            *retval = t->result;
    } else {
        rc = LX_EINVAL;
    }
    CloseHandle(h);
    HeapFree(GetProcessHeap(), 0, t);
    return rc;
}

/* The game's pthread_mutex_t / pthread_cond_t are 64-byte zeroed statics; the SRWLOCK and the
 * CONDITION_VARIABLE (one pointer each, valid when zero) live at the first 8-aligned address inside, so an
 * unaligned buffer never makes an interlocked operation straddle a cache line. */
static void *slot8(void *p)
{
    return (void *)(((uintptr_t)p + 7) & ~(uintptr_t)7);
}

SYSV int w_pthread_mutex_lock(void *m)
{
    AcquireSRWLockExclusive(slot8(m));
    return 0;
}

SYSV int w_pthread_mutex_unlock(void *m)
{
    ReleaseSRWLockExclusive(slot8(m));
    return 0;
}

/* Atomically releases m and waits for a signal, then takes m again. Wake-ups may be spurious, as in POSIX. */
SYSV int w_pthread_cond_wait(void *c, void *m)
{
    return SleepConditionVariableSRW(slot8(c), slot8(m), INFINITE, 0) ? 0 : LX_EINVAL;
}

SYSV int w_pthread_cond_signal(void *c)
{
    WakeConditionVariable(slot8(c));
    return 0;
}

SYSV int w_pthread_cond_broadcast(void *c)
{
    WakeAllConditionVariable(slot8(c));
    return 0;
}

/* ================================================================================================== */
/* 3. usleep                                                                                           */
/* ================================================================================================== */

static LONGLONG qpc_freq;               /* ticks per second, set on first use */
static volatile LONG hires_state;       /* high-resolution timers: 0 unknown, 1 available, -1 not */

static LONGLONG qpc_now(void)
{
    LARGE_INTEGER t;

    QueryPerformanceCounter(&t);
    return t.QuadPart;
}

/* int usleep(useconds_t usec): sleeps at least usec microseconds (measured with the performance counter),
 * normally less than a millisecond longer. 0 only yields. A high-resolution waitable timer does the waiting
 * where Windows has one (10 1803+); elsewhere Sleep, rounded up (the process runs at a 1 ms timer period).
 * The last 150 microseconds are spun. */
SYSV int w_usleep(unsigned int usec)
{
    LONGLONG f = qpc_freq, deadline;
    HANDLE timer = NULL;

    if (usec == 0) {
        Sleep(0);
        return 0;
    }
    if (f == 0) {
        LARGE_INTEGER q;

        QueryPerformanceFrequency(&q);
        qpc_freq = f = q.QuadPart;
    }
    deadline = qpc_now() + (LONGLONG)usec * f / 1000000;
    if (hires_state >= 0) {
        timer = CreateWaitableTimerExW(NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,
                                       TIMER_MODIFY_STATE | SYNCHRONIZE);
        hires_state = timer ? 1 : -1;
    }
    for (;;) {
        LONGLONG left = deadline - qpc_now();
        LONGLONG left_us;

        if (left <= 0)
            break;
        left_us = left * 1000000 / f;
        if (left_us < 150) {
            YieldProcessor();
            continue;
        }
        if (timer) {
            LARGE_INTEGER due;

            due.QuadPart = -(left_us * 10);             /* relative, 100 ns units */
            if (SetWaitableTimer(timer, &due, 0, NULL, NULL, FALSE)) {
                WaitForSingleObject(timer, INFINITE);
                continue;
            }
        }
        Sleep((DWORD)((left_us + 999) / 1000));
    }
    if (timer)
        CloseHandle(timer);
    return 0;
}

/* ================================================================================================== */
/* 4. audio: the libpulse-simple calls of src/audio.asm over waveOut                                   */
/* ================================================================================================== */

#define PA_STREAM_PLAYBACK 1
#define PA_STREAM_RECORD   2
#define PA_SAMPLE_S16LE    3
#define PA_SAMPLE_COUNT    13           /* pa_sample_format_t values 0..12 exist */
#define PA_RATE_MAX        (48000u * 8)
#define PA_CHANNELS_MAX    32

/* pa_error_code_t values reported through *error */
#define PAE_INVALID        3
#define PAE_CONNREFUSED    6
#define PAE_INTERNAL       10
#define PAE_CONNTERM       11
#define PAE_NOTSUPPORTED   19
#define PAE_BUSY           26

typedef struct {
    int32_t format;
    uint32_t rate;
    uint8_t channels;
} pa_sample_spec;

#define AU_RING_N       12              /* waveOut buffers */
#define AU_PRIME_BUFS   4               /* lead kept in front of the device: 4 buffers = 40 ms */
#define AU_CAP_BUFS     10              /* ceiling: 100 ms ... */
#define AU_LOW_BUFS     5               /* ... drained to 50 ms once it is reached */
#define AU_SEND_BUFS    2               /* the partly filled buffer waits while this much is queued ahead */
#define AU_STALL_MS     200
#define AU_STALLS_MAX   3

typedef struct pa_simple {
    HWAVEOUT hwo;
    HANDLE ev;                          /* auto-reset, set by the driver whenever a buffer is done */
    unsigned fs;                        /* bytes per frame */
    unsigned buf_frames;                /* frames per ring buffer: 10 ms */
    unsigned prime_frames, cap_frames, low_frames, send_frames;
    int draining;                       /* the queue reached cap_frames: no room until it is down to low_frames */
    unsigned fill;                      /* ring index of the buffer being filled */
    unsigned fill_len;                  /* bytes in it, not yet handed to the device */
    unsigned carry_len;                 /* bytes of a frame the caller has not completed yet */
    unsigned char carry[8];
    int stalls;                         /* consecutive writes that had to reset the device */
    int broken;                         /* pa_error_code_t of the failure that ended the stream, or 0 */
    unsigned char *mem;                 /* AU_RING_N buffers of buf_frames frames */
    unsigned char queued[AU_RING_N];    /* handed to the device and not seen done yet */
    WAVEHDR hdr[AU_RING_N];
} pa_stream;

static int au_error(int *error, int code)
{
    if (error)
        *error = code;
    return -1;
}

/* Is ring buffer i still with the device? WHDR_DONE ends it (the driver sets it before it signals). */
static int au_busy(pa_stream *s, unsigned i)
{
    if (!s->queued[i])
        return 0;
    if (*(volatile DWORD *)&s->hdr[i].dwFlags & WHDR_DONE) {
        s->queued[i] = 0;
        return 0;
    }
    return 1;
}

/* Frames the device still has to play (buffers handed over and not done). */
static unsigned au_inflight(pa_stream *s)
{
    unsigned bytes = 0;

    for (unsigned i = 0; i < AU_RING_N; i++)
        if (au_busy(s, i))
            bytes += s->hdr[i].dwBufferLength;
    return bytes / s->fs;
}

/* Hands the buffer being filled (fill_len bytes) to the device. */
static int au_submit(pa_stream *s)
{
    WAVEHDR *h = &s->hdr[s->fill];
    unsigned i = s->fill;

    h->dwBufferLength = s->fill_len;
    *(volatile DWORD *)&h->dwFlags &= ~(DWORD)WHDR_DONE;
    s->queued[i] = 1;
    s->fill = (s->fill + 1) % AU_RING_N;
    s->fill_len = 0;
    if (waveOutWrite(s->hwo, h, sizeof *h) != MMSYSERR_NOERROR) {
        s->queued[i] = 0;
        s->broken = PAE_CONNTERM;
        return -1;
    }
    return 0;
}

/* Waits until the next frame can go into the ring: the buffer being filled is free and the queue is below
 * its ceiling. Reaching the ceiling starts a drain: the wait goes on until only the low-water mark is left
 * queued (hysteresis), so a lead that grew - the burst after a long frame, a device a little slower than the
 * clock - is brought back to a normal one in a single wait instead of keeping every later write at the
 * ceiling, where each would wait for a buffer and stretch the frame it is in. A device that returns nothing
 * for AU_STALL_MS is reset; after AU_STALLS_MAX resets in a row (no wait that ended by the device returning
 * a buffer by itself in between) the stream is dead. Returns 0, or -1 with s->broken set. */
static int au_wait_room(pa_stream *s)
{
    ULONGLONG t0 = GetTickCount64();
    int waited = 0, stalled = 0;

    for (;;) {
        unsigned level = au_inflight(s) + s->fill_len / s->fs;

        if (s->draining ? level <= s->low_frames : level >= s->cap_frames)
            s->draining = !s->draining;
        if (!s->draining && (s->fill_len > 0 || !au_busy(s, s->fill))) {
            if (waited && !stalled)
                s->stalls = 0;                          /* the device gave a buffer back by itself: alive */
            return 0;
        }
        if (GetTickCount64() - t0 >= AU_STALL_MS) {
            stalled = 1;
            if (++s->stalls > AU_STALLS_MAX) {
                s->broken = PAE_CONNTERM;
                return -1;
            }
            waveOutReset(s->hwo);
            t0 = GetTickCount64();
            continue;
        }
        waited = 1;
        WaitForSingleObject(s->ev, 10);
    }
}

/* Appends `frames` frames (silence when src is NULL) to the ring, handing full buffers to the device and
 * waiting for room as needed. */
static int au_feed(pa_stream *s, const unsigned char *src, size_t frames)
{
    while (frames > 0) {
        size_t k = frames, room;
        unsigned char *dst;

        if (au_wait_room(s) != 0)
            return -1;
        room = s->buf_frames - s->fill_len / s->fs;
        if (k > room)
            k = room;
        room = s->cap_frames - (au_inflight(s) + s->fill_len / s->fs);
        if (k > room)
            k = room;
        dst = (unsigned char *)s->hdr[s->fill].lpData + s->fill_len;
        if (src) {
            memcpy(dst, src, k * s->fs);
            src += k * s->fs;
        } else {
            memset(dst, 0, k * s->fs);
        }
        s->fill_len += (unsigned)(k * s->fs);
        frames -= k;
        if (s->fill_len == s->buf_frames * s->fs && au_submit(s) != 0)
            return -1;
    }
    return 0;
}

/* pa_simple *pa_simple_new(server, name, dir, dev, stream_name, ss, map, attr, error)
 * Opens the default playback device for S16LE audio (mono or stereo, any rate). server, name, dev,
 * stream_name, map and attr (the buffering is fixed, see the top of the file) are ignored. Returns NULL
 * with *error set when there is no device or it refuses the format. */
SYSV void *w_pa_simple_new(const char *server, const char *name, int dir, const char *dev,
                           const char *stream_name, const void *spec, const void *map, const void *attr,
                           int *error)
{
    const pa_sample_spec *ss = spec;
    WAVEFORMATEX wf;
    pa_stream *s;
    MMRESULT r;
    size_t buf_bytes;

    (void)server; (void)name; (void)dev; (void)stream_name; (void)map; (void)attr;
    if (dir == PA_STREAM_RECORD) {
        au_error(error, PAE_NOTSUPPORTED);
        return NULL;
    }
    if (dir != PA_STREAM_PLAYBACK || !ss || ss->rate == 0 || ss->rate > PA_RATE_MAX || ss->channels == 0 ||
        ss->channels > PA_CHANNELS_MAX || ss->format < 0 || ss->format >= PA_SAMPLE_COUNT) {
        au_error(error, PAE_INVALID);
        return NULL;
    }
    if (ss->format != PA_SAMPLE_S16LE || ss->channels > 2) {
        au_error(error, PAE_NOTSUPPORTED);
        return NULL;
    }
    if (waveOutGetNumDevs() == 0) {
        au_error(error, PAE_CONNREFUSED);
        return NULL;
    }
    s = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof *s);
    if (!s) {
        au_error(error, PAE_INTERNAL);
        return NULL;
    }
    s->fs = 2u * ss->channels;
    s->buf_frames = ss->rate / 100;
    if (s->buf_frames < 32)
        s->buf_frames = 32;
    buf_bytes = (size_t)s->buf_frames * s->fs;
    s->cap_frames = AU_CAP_BUFS * s->buf_frames;
    s->low_frames = AU_LOW_BUFS * s->buf_frames;
    s->prime_frames = AU_PRIME_BUFS * s->buf_frames;
    s->send_frames = AU_SEND_BUFS * s->buf_frames;
    s->mem = HeapAlloc(GetProcessHeap(), 0, AU_RING_N * buf_bytes);
    s->ev = CreateEventW(NULL, FALSE, FALSE, NULL);
    if (!s->mem || !s->ev) {
        au_error(error, PAE_INTERNAL);
        goto fail;
    }
    memset(&wf, 0, sizeof wf);
    wf.wFormatTag = WAVE_FORMAT_PCM;
    wf.nChannels = ss->channels;
    wf.nSamplesPerSec = ss->rate;
    wf.wBitsPerSample = 16;
    wf.nBlockAlign = (WORD)s->fs;
    wf.nAvgBytesPerSec = ss->rate * s->fs;
    r = waveOutOpen(&s->hwo, WAVE_MAPPER, &wf, (DWORD_PTR)s->ev, 0, CALLBACK_EVENT);
    if (r != MMSYSERR_NOERROR) {
        au_error(error, r == MMSYSERR_ALLOCATED ? PAE_BUSY : r == WAVERR_BADFORMAT ? PAE_NOTSUPPORTED :
                 (r == MMSYSERR_BADDEVICEID || r == MMSYSERR_NODRIVER) ? PAE_CONNREFUSED : PAE_INTERNAL);
        s->hwo = NULL;
        goto fail;
    }
    for (unsigned i = 0; i < AU_RING_N; i++) {
        s->hdr[i].lpData = (LPSTR)(s->mem + i * buf_bytes);
        s->hdr[i].dwBufferLength = (DWORD)buf_bytes;
        if (waveOutPrepareHeader(s->hwo, &s->hdr[i], sizeof s->hdr[i]) != MMSYSERR_NOERROR) {
            while (i-- > 0)
                waveOutUnprepareHeader(s->hwo, &s->hdr[i], sizeof s->hdr[i]);
            au_error(error, PAE_INTERNAL);
            waveOutClose(s->hwo);
            goto fail;
        }
    }
    return s;
fail:
    if (s->ev)
        CloseHandle(s->ev);
    if (s->mem)
        HeapFree(GetProcessHeap(), 0, s->mem);
    HeapFree(GetProcessHeap(), 0, s);
    return NULL;
}

/* int pa_simple_write(s, data, bytes, error): queues the samples and returns 0 once all of them are in the
 * ring, waiting while it is full (see the top of the file). -1 with *error set on a bad argument or after the
 * device failed. A partial frame at the end is kept and completed by the next call. */
SYSV int w_pa_simple_write(void *handle, const void *data, size_t bytes, int *error)
{
    pa_stream *s = handle;
    const unsigned char *p = data;
    size_t frames, whole;

    if (!s || !data || bytes == 0)
        return au_error(error, PAE_INVALID);
    if (s->broken)
        return au_error(error, s->broken);
    frames = (s->carry_len + bytes) / s->fs;
    if (frames > 0 && au_inflight(s) == 0) {            /* the first write, or the device ran dry */
        size_t have = s->fill_len / s->fs + frames;

        if (have < s->prime_frames && au_feed(s, NULL, s->prime_frames - have) != 0)
            return au_error(error, s->broken);
    }
    while (s->carry_len > 0 && s->carry_len < s->fs && bytes > 0 && s->carry_len < sizeof s->carry) {
        s->carry[s->carry_len++] = *p++;                /* complete the frame the previous call left open */
        bytes--;
    }
    if (s->carry_len == s->fs) {
        if (au_feed(s, s->carry, 1) != 0)
            return au_error(error, s->broken);
        s->carry_len = 0;
    }
    whole = s->carry_len ? 0 : bytes / s->fs;
    if (whole > 0 && au_feed(s, p, whole) != 0)
        return au_error(error, s->broken);
    p += whole * s->fs;
    bytes -= whole * s->fs;
    while (bytes > 0 && s->carry_len < sizeof s->carry) {
        s->carry[s->carry_len++] = *p++;                /* an incomplete frame at the end waits for the next call */
        bytes--;
    }
    if (s->fill_len > 0 && au_inflight(s) < s->send_frames && au_submit(s) != 0)
        return au_error(error, s->broken);
    if (error)
        *error = 0;
    return 0;
}

/* void pa_simple_free(s): stops the stream at once (queued audio is dropped, like libpulse-simple without a
 * drain) and releases everything. NULL is ignored. */
SYSV void w_pa_simple_free(void *handle)
{
    pa_stream *s = handle;

    if (!s)
        return;
    waveOutReset(s->hwo);
    for (unsigned i = 0; i < AU_RING_N; i++) {
        s->hdr[i].dwBufferLength = s->buf_frames * s->fs;      /* as prepared: partial buffers were sent shorter */
        for (int tries = 0; tries < 50 &&
             waveOutUnprepareHeader(s->hwo, &s->hdr[i], sizeof s->hdr[i]) == WAVERR_STILLPLAYING; tries++)
            Sleep(2);
    }
    waveOutClose(s->hwo);
    CloseHandle(s->ev);
    HeapFree(GetProcessHeap(), 0, s->mem);
    HeapFree(GetProcessHeap(), 0, s);
}
