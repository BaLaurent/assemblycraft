/* win_misc_test.c - standalone test of win/win_misc.c (NOT linked into the game). It includes the file, so
 * the static helpers are reachable, and runs under wine. Two builds, from the repository root:
 *
 *   CC="docker run --rm -u $(id -u):$(id -g) -v $PWD:/src -v /tmp/winmisc:/out -w /src ac-mingw x86_64-w64-mingw32-gcc"
 *   FLAGS="-O2 -std=gnu11 -Wall -Wextra -mincoming-stack-boundary=4 -Iwin/glfw/include"
 *   $CC $FLAGS win/tests/win_misc_test.c -o /out/real.exe -Wl,--stack,8388608 -lwinmm
 *   $CC $FLAGS -DFAKE_WAVE win/tests/win_misc_test.c -o /out/fake.exe -Wl,--stack,8388608 -lwinmm
 *   WINEDEBUG=-all WINEPREFIX=/tmp/winmisc/prefix wine /tmp/winmisc/real.exe     # entry, threads, usleep, real audio
 *   WINEDEBUG=-all WINEPREFIX=/tmp/winmisc/prefix wine /tmp/winmisc/fake.exe     # the audio ring against a fake device
 *
 * (-mincoming-stack-boundary=4 is only for this file: without it the mingw gcc 12 of the ac-mingw image dies
 * with an internal error in choose_baseaddr on some functions of a translation unit that mixes sysv_abi and
 * ms_abi code at -O1/-O2; win_misc.c itself compiles fine with the Makefile's flags.)
 *
 * real.exe: the argv/envp builders, the real entry in a child process, threads (also called the way the
 * game's assembly calls them: System V registers, callee-saved registers checked), usleep, and
 * pa_simple_new/write/free on whatever audio device wine offers (or none).
 * fake.exe: win_misc.c compiled against a simulated waveOut device (real-time completion, event, WHDR flags)
 * to check the ring: integrity of the byte stream, lead, throttling, re-priming, stalls, failures.
 * Exit code 0 = everything passed. */
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0601
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#include <shellapi.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include "../win.h"

/* libpulse's pa_buffer_attr as audio.asm fills it (win_misc.c ignores it) */
typedef struct {
    uint32_t maxlength, tlength, prebuf, minreq, fragsize;
} pa_buffer_attr;

static int fails;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); \
                                       printf("\n"); fflush(stdout); } } while (0)
#define CHECKC(c) CHECK(c, "%s", #c)

static double now_ms(void)
{
    static LONGLONG f;
    LARGE_INTEGER t;

    if (!f) { QueryPerformanceFrequency(&t); f = t.QuadPart; }
    QueryPerformanceCounter(&t);
    return (double)t.QuadPart * 1000.0 / (double)f;
}

/* ================================================================================================== */
/* the fake waveOut device                                                                             */
/* ================================================================================================== */
#ifdef FAKE_WAVE

typedef struct {
    CRITICAL_SECTION cs;
    HANDLE ev;
    unsigned rate, fs;
    WAVEHDR *q[64];
    double done[64];                    /* ms (now_ms) each queued buffer finishes */
    int qn;
    double next_free;                   /* ms the device runs out of queued data */
    volatile int freeze;                /* queued buffers never complete */
    volatile int fail_write;
    unsigned open_error;
    unsigned ndevs;
    unsigned char *cap;                 /* every byte handed to waveOutWrite */
    size_t cap_len, cap_max;
    int writes, resets, opens, closes, idle_writes;
    volatile int stop;
    HANDLE thread;
} fakedev;
static fakedev fk;

static DWORD WINAPI fk_thread(LPVOID p)
{
    (void)p;
    while (!fk.stop) {
        double now = now_ms();

        EnterCriticalSection(&fk.cs);
        while (!fk.freeze && fk.qn > 0 && fk.done[0] <= now) {
            WAVEHDR *h = fk.q[0];

            h->dwFlags = (h->dwFlags & ~(DWORD)WHDR_INQUEUE) | WHDR_DONE;
            fk.qn--;
            memmove(&fk.q[0], &fk.q[1], (size_t)fk.qn * sizeof fk.q[0]);
            memmove(&fk.done[0], &fk.done[1], (size_t)fk.qn * sizeof fk.done[0]);
            SetEvent(fk.ev);
        }
        LeaveCriticalSection(&fk.cs);
        Sleep(1);
    }
    return 0;
}

static void fk_reset_state(void)
{
    fk.freeze = fk.fail_write = 0;
    fk.open_error = MMSYSERR_NOERROR;
    fk.ndevs = 1;
    fk.cap_len = 0;
    fk.writes = fk.resets = fk.idle_writes = 0;
    fk.qn = 0;
    fk.next_free = 0;
}

static UINT WINAPI fake_waveOutGetNumDevs(void) { return fk.ndevs; }

static MMRESULT WINAPI fake_waveOutOpen(LPHWAVEOUT ph, UINT id, LPCWAVEFORMATEX fmt, DWORD_PTR cb,
                                        DWORD_PTR inst, DWORD flags)
{
    (void)id; (void)inst;
    if (fk.open_error)
        return fk.open_error;
    if (!(flags & CALLBACK_EVENT) || fmt->wFormatTag != WAVE_FORMAT_PCM || fmt->wBitsPerSample != 16)
        return WAVERR_BADFORMAT;
    fk.ev = (HANDLE)cb;
    fk.rate = fmt->nSamplesPerSec;
    fk.fs = fmt->nBlockAlign;
    fk.opens++;
    *ph = (HWAVEOUT)&fk;
    return MMSYSERR_NOERROR;
}

static MMRESULT WINAPI fake_waveOutPrepareHeader(HWAVEOUT h, LPWAVEHDR hdr, UINT sz)
{
    (void)h; (void)sz;
    hdr->dwFlags |= WHDR_PREPARED;
    return MMSYSERR_NOERROR;
}

static MMRESULT WINAPI fake_waveOutUnprepareHeader(HWAVEOUT h, LPWAVEHDR hdr, UINT sz)
{
    (void)h; (void)sz;
    if ((hdr->dwFlags & WHDR_INQUEUE) && !(hdr->dwFlags & WHDR_DONE))
        return WAVERR_STILLPLAYING;
    hdr->dwFlags &= ~(DWORD)WHDR_PREPARED;
    return MMSYSERR_NOERROR;
}

static MMRESULT WINAPI fake_waveOutWrite(HWAVEOUT h, LPWAVEHDR hdr, UINT sz)
{
    double now = now_ms(), start;

    (void)h; (void)sz;
    if (fk.fail_write)
        return MMSYSERR_NODRIVER;
    if (!(hdr->dwFlags & WHDR_PREPARED))
        return WAVERR_UNPREPARED;
    EnterCriticalSection(&fk.cs);
    if (fk.cap_len + hdr->dwBufferLength > fk.cap_max) {
        fk.cap_max = (fk.cap_len + hdr->dwBufferLength) * 2;
        fk.cap = realloc(fk.cap, fk.cap_max);
    }
    memcpy(fk.cap + fk.cap_len, hdr->lpData, hdr->dwBufferLength);
    fk.cap_len += hdr->dwBufferLength;
    fk.writes++;
    if (fk.next_free < now && fk.writes > 1)
        fk.idle_writes++;               /* the device had run dry */
    start = fk.next_free > now ? fk.next_free : now;
    fk.next_free = start + (double)(hdr->dwBufferLength / fk.fs) * 1000.0 / (double)fk.rate;
    hdr->dwFlags = (hdr->dwFlags & ~(DWORD)WHDR_DONE) | WHDR_INQUEUE;
    fk.q[fk.qn] = hdr;
    fk.done[fk.qn++] = fk.next_free;
    LeaveCriticalSection(&fk.cs);
    return MMSYSERR_NOERROR;
}

/* Completes the n oldest queued buffers at once (for a frozen device) and signals the event. */
static void fk_complete(int n)
{
    EnterCriticalSection(&fk.cs);
    for (int i = 0; i < n && fk.qn > 0; i++) {
        fk.q[0]->dwFlags = (fk.q[0]->dwFlags & ~(DWORD)WHDR_INQUEUE) | WHDR_DONE;
        fk.qn--;
        memmove(&fk.q[0], &fk.q[1], (size_t)fk.qn * sizeof fk.q[0]);
        memmove(&fk.done[0], &fk.done[1], (size_t)fk.qn * sizeof fk.done[0]);
    }
    SetEvent(fk.ev);
    LeaveCriticalSection(&fk.cs);
}

static MMRESULT WINAPI fake_waveOutReset(HWAVEOUT h)
{
    (void)h;
    EnterCriticalSection(&fk.cs);
    for (int i = 0; i < fk.qn; i++)
        fk.q[i]->dwFlags = (fk.q[i]->dwFlags & ~(DWORD)WHDR_INQUEUE) | WHDR_DONE;
    fk.qn = 0;
    fk.next_free = now_ms();
    fk.resets++;
    SetEvent(fk.ev);
    LeaveCriticalSection(&fk.cs);
    return MMSYSERR_NOERROR;
}

static MMRESULT WINAPI fake_waveOutClose(HWAVEOUT h)
{
    (void)h;
    fk.closes++;
    return MMSYSERR_NOERROR;
}

#define waveOutGetNumDevs fake_waveOutGetNumDevs
#define waveOutOpen fake_waveOutOpen
#define waveOutPrepareHeader fake_waveOutPrepareHeader
#define waveOutUnprepareHeader fake_waveOutUnprepareHeader
#define waveOutWrite fake_waveOutWrite
#define waveOutReset fake_waveOutReset
#define waveOutClose fake_waveOutClose

/* win_misc.c's main needs the game's entry point to link; this build never runs it */
SYSV int w_main(int argc, char **argv, char **envp)
{
    (void)argc; (void)argv; (void)envp;
    return 0;
}
#endif /* FAKE_WAVE */

#define main win_misc_main
#include "../win_misc.c"
#undef main

/* ================================================================================================== */
/* the real entry: a child process runs win_misc_main, whose w_main checks what it is given            */
/* ================================================================================================== */
#ifndef FAKE_WAVE

/* Moves rsp down by `bytes` and writes at the far end first, like the game's assembly does with a big frame (it
 * never probes the stack): a page that is not committed yet would fault on Windows. */
static void touch_far_end(size_t bytes)
{
    __asm__ volatile("subq %0, %%rsp\n\tmovb $1, (%%rsp)\n\taddq %0, %%rsp" : : "r"(bytes) : "memory", "cc");
}

static int is_xdg(const char *e)
{
    return strncmp(e, "XDG_DATA_HOME=", 14) == 0;
}

/* The game's `main` as the child sees it. argv[2] is the case: A..E, see run_entry_case(). */
SYSV int w_main(int argc, char **argv, char **envp)
{
    char c = argc > 2 ? argv[2][0] : '?';
    int n_xdg = 0, n_env = 0, bad = 0;
    const char *xdg = NULL;

    touch_far_end(200000);                       /* inside the part of the main stack win_misc_main commits */

    if (argc != 8 || argv[argc] != NULL) return 101;
    if (strcmp(argv[1], "--entry-child") != 0) bad |= 1;
    if (strcmp(argv[3], "a b") != 0) bad |= 2;
    if (strcmp(argv[4], "\xce\xb4\xc3\xa9") != 0) bad |= 4;      /* the Greek delta and e acute, UTF-8 */
    if (strcmp(argv[5], "") != 0) bad |= 8;
    if (strcmp(argv[6], "tail") != 0) bad |= 16;
    if (strcmp(argv[7], "q\"uote") != 0) bad |= 32;
    if (strlen(argv[0]) < 5 || _stricmp(argv[0] + strlen(argv[0]) - 4, ".exe") != 0) bad |= 64;
    for (char **e = envp; *e; e++) {
        n_env++;
        if (is_xdg(*e)) { n_xdg++; xdg = *e + 14; }
        if ((*e)[0] == '=') bad |= 128;                          /* no "=C:=C:\dir" pseudo variables */
    }
    if (n_env < 1) bad |= 256;
    switch (c) {
    case 'A': if (n_xdg != 1 || strcmp(xdg, "C:/Users/Zo\xc3\xab/AppData/Roaming") != 0) bad |= 512; break;
    case 'B': if (n_xdg != 1 || strcmp(xdg, "D:\\data dir") != 0) bad |= 512; break;
    case 'C': if (n_xdg != 1 || strcmp(xdg, "C:/x") != 0) bad |= 512; break;
    case 'D': if (n_xdg != 0) bad |= 512; break;
    case 'E': if (n_xdg != 1 || strcmp(xdg, "C:/x") != 0) bad |= 512; return bad ? 100 : 7;
    default: bad |= 1024;
    }
    return bad ? 100 : 0;
}

static WCHAR *child_env(const WCHAR *appdata, const WCHAR *xdg)
{
    WCHAR *cur = GetEnvironmentStringsW(), *out, *o;
    size_t total = 2;

    for (const WCHAR *e = cur; *e; e += wcslen(e) + 1)
        total += wcslen(e) + 1;
    total += (appdata ? wcslen(appdata) + 9 : 0) + (xdg ? wcslen(xdg) + 15 : 0);
    out = o = malloc(total * sizeof(WCHAR));
    for (const WCHAR *e = cur; *e; e += wcslen(e) + 1) {
        if (_wcsnicmp(e, L"APPDATA=", 8) == 0 || _wcsnicmp(e, L"XDG_DATA_HOME=", 14) == 0)
            continue;
        wcscpy(o, e);
        o += wcslen(e) + 1;
    }
    if (appdata) { wcscpy(o, L"APPDATA="); wcscat(o, appdata); o += wcslen(o) + 1; }
    if (xdg) { wcscpy(o, L"XDG_DATA_HOME="); wcscat(o, xdg); o += wcslen(o) + 1; }
    *o = 0;
    FreeEnvironmentStringsW(cur);
    return out;
}

/* Runs this exe as the game: win_misc_main in the child, with a crafted command line and environment. */
static DWORD run_entry_case(wchar_t which, const WCHAR *appdata, const WCHAR *xdg)
{
    WCHAR exe[MAX_PATH], cmd[2 * MAX_PATH + 200];
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    WCHAR *env = child_env(appdata, xdg);
    DWORD code = 9999;

    GetModuleFileNameW(NULL, exe, MAX_PATH);
    swprintf(cmd, sizeof cmd / sizeof cmd[0], L"\"%ls\" --entry-child %lc \"a b\" \u03b4\u00e9 \"\" tail \"q\\\"uote\"",
             exe, which);
    memset(&si, 0, sizeof si);
    si.cb = sizeof si;
    if (!CreateProcessW(exe, cmd, NULL, NULL, FALSE, CREATE_UNICODE_ENVIRONMENT, env, NULL, &si, &pi)) {
        printf("CreateProcess failed: %lu\n", GetLastError());
        free(env);
        return code;
    }
    WaitForSingleObject(pi.hProcess, 30000);
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    free(env);
    return code;
}

static void test_entry(void)
{
    CHECK(run_entry_case(L'A', L"C:\\Users\\Zo\u00eb\\AppData\\Roaming\\", NULL) == 0, "entry A: APPDATA -> XDG_DATA_HOME");
    CHECK(run_entry_case(L'B', L"C:\\x", L"D:\\data dir") == 0, "entry B: an existing XDG_DATA_HOME is kept");
    CHECK(run_entry_case(L'C', L"C:\\x", L"") == 0, "entry C: an empty XDG_DATA_HOME is replaced");
    CHECK(run_entry_case(L'D', NULL, NULL) == 0, "entry D: nothing to synthesise from");
    CHECK(run_entry_case(L'E', L"C:\\x\\", NULL) == 7, "entry E: w_main's exit code is the process's");
}

/* ---- the argv / envp builders on synthetic input --------------------------------------------------- */

static WCHAR *mkblock(const WCHAR *const *entries, int n)
{
    size_t total = 2;
    WCHAR *b, *o;

    for (int i = 0; i < n; i++)
        total += wcslen(entries[i]) + 1;
    b = o = calloc(total, sizeof(WCHAR));
    for (int i = 0; i < n; i++) {
        wcscpy(o, entries[i]);
        o += wcslen(entries[i]) + 1;
    }
    return b;
}

static int env_count(char **v) { int n = 0; while (v[n]) n++; return n; }

static const char *env_get(char **v, const char *name)
{
    size_t l = strlen(name);

    for (; *v; v++)
        if (strncmp(*v, name, l) == 0 && (*v)[l] == '=')
            return *v + l + 1;
    return NULL;
}

static void test_args_env(void)
{
    int argc = 0;
    char **a = build_args(L"C:\\Games\\ac.exe --data-dir \"C:\\My Games\\ac data\" --seed 5 \u00e9\u4e16 \"\" tail \"x\\\"y\"", &argc);

    CHECKC(a != NULL);
    CHECK(argc == 9, "argc %d", argc);
    if (a && argc == 9) {
        CHECK(strcmp(a[0], "C:\\Games\\ac.exe") == 0, "argv0 %s", a[0]);
        CHECK(strcmp(a[2], "C:\\My Games\\ac data") == 0, "quoted path %s", a[2]);
        CHECK(strcmp(a[5], "\xc3\xa9\xe4\xb8\x96") == 0, "utf-8 argument");
        CHECK(a[6][0] == 0, "empty argument");
        CHECK(strcmp(a[8], "x\"y") == 0, "escaped quote %s", a[8]);
        CHECK(a[9] == NULL, "argv is NULL-terminated");
    }

    {   /* APPDATA -> XDG_DATA_HOME; hidden =C: entry dropped; empty XDG dropped; others kept in order */
        const WCHAR *e[] = { L"A=1", L"=C:=C:\\dir", L"XDG_DATA_HOME=", L"Path=C:\\x;D:\\y",
                             L"APPDATA=C:\\Users\\Zo\u00eb\\AppData\\Roaming\\" };
        WCHAR *blk = mkblock(e, 5);
        char **v = build_env(blk);

        CHECKC(v != NULL);
        CHECK(v && env_count(v) == 4, "count %d", v ? env_count(v) : -1);
        if (v && env_count(v) == 4) {
            CHECK(strcmp(v[0], "A=1") == 0, "order: %s", v[0]);
            CHECK(strcmp(v[1], "Path=C:\\x;D:\\y") == 0, "order: %s", v[1]);
            CHECK(strncmp(v[2], "APPDATA=C:\\Users\\Zo", 19) == 0, "APPDATA itself is untouched: %s", v[2]);
            CHECK(strcmp(v[3], "XDG_DATA_HOME=C:/Users/Zo\xc3\xab/AppData/Roaming") == 0, "synthesised: %s", v[3]);
        }
        free(blk);
    }
    {   /* a non-empty XDG_DATA_HOME in any case is kept, with the exact name the game matches */
        const WCHAR *e[] = { L"xdg_data_home=D:\\data", L"APPDATA=C:\\a" };
        WCHAR *blk = mkblock(e, 2);
        char **v = build_env(blk);

        CHECKC(v != NULL);
        CHECK(v && env_count(v) == 2, "count %d", v ? env_count(v) : -1);
        if (v && env_count(v) == 2) {
            CHECK(strcmp(v[0], "XDG_DATA_HOME=D:\\data") == 0, "canonical name: %s", v[0]);
            CHECK(env_get(v, "XDG_DATA_HOME") && strcmp(env_get(v, "XDG_DATA_HOME"), "D:\\data") == 0, "value kept");
        }
        free(blk);
    }
    {   /* nothing to synthesise from */
        const WCHAR *e[] = { L"Foo=bar" };
        WCHAR *blk = mkblock(e, 1);
        char **v = build_env(blk);

        CHECK(v && env_count(v) == 1 && !env_get(v, "XDG_DATA_HOME"), "no APPDATA, no XDG_DATA_HOME");
        free(blk);
    }
    {   /* separators only: nothing either; a bare drive: "C:" */
        const WCHAR *e1[] = { L"APPDATA=\\\\" };
        const WCHAR *e2[] = { L"APPDATA=C:\\" };
        WCHAR *b1 = mkblock(e1, 1), *b2 = mkblock(e2, 1);
        char **v1 = build_env(b1), **v2 = build_env(b2);

        CHECK(v1 && !env_get(v1, "XDG_DATA_HOME"), "APPDATA of separators only");
        CHECK(v2 && env_get(v2, "XDG_DATA_HOME") && strcmp(env_get(v2, "XDG_DATA_HOME"), "C:") == 0, "APPDATA C:\\");
        free(b1);
        free(b2);
    }
    {   /* empty environment */
        WCHAR blk[2] = { 0, 0 };
        char **v = build_env(blk);

        CHECK(v && v[0] == NULL, "empty block");
    }
    {   /* this process's own environment: valid, NULL-terminated, UTF-8 */
        WCHAR *blk = GetEnvironmentStringsW();
        char **v = build_env(blk);

        CHECK(v && env_count(v) > 0, "own environment");
        FreeEnvironmentStringsW(blk);
    }
}

/* ================================================================================================== */
/* threads                                                                                             */
/* ================================================================================================== */

static SYSV void *thr_triple(void *arg) { return (void *)((uintptr_t)arg * 3 + 1); }

static struct { char mu[64]; char cv[64]; volatile int turn; volatile int count; int log[400]; } pp;
#define PP_ROUNDS 200

static SYSV void *pp_thread(void *arg)
{
    int me = (int)(intptr_t)arg;

    for (int i = 0; i < PP_ROUNDS; i++) {
        w_pthread_mutex_lock(pp.mu);
        while (pp.turn != me)
            w_pthread_cond_wait(pp.cv, pp.mu);
        pp.log[pp.count++] = me;
        pp.turn = 1 - me;
        w_pthread_cond_signal(pp.cv);
        w_pthread_mutex_unlock(pp.mu);
    }
    return NULL;
}

static struct { char mu[64]; volatile long n; } ex;
#define EX_THREADS 4
#define EX_ITERS 50000

static SYSV void *ex_thread(void *arg)
{
    (void)arg;
    for (int i = 0; i < EX_ITERS; i++) {
        w_pthread_mutex_lock(ex.mu);
        ex.n = ex.n + 1;
        w_pthread_mutex_unlock(ex.mu);
    }
    return NULL;
}

static struct { char mu[64]; char cv[64]; volatile int waiting, go, out; } bc;

static SYSV void *bc_thread(void *arg)
{
    (void)arg;
    w_pthread_mutex_lock(bc.mu);
    bc.waiting++;
    while (!bc.go)
        w_pthread_cond_wait(bc.cv, bc.mu);
    bc.out++;
    w_pthread_mutex_unlock(bc.mu);
    return NULL;
}

static volatile uintptr_t self_tid;
static volatile int self_rc;

static SYSV void *self_thread(void *arg)
{
    (void)arg;
    while (!self_tid)
        Sleep(1);
    self_rc = w_pthread_join(self_tid, NULL);
    return NULL;
}

static SYSV void *stack_thread(void *arg)
{
    volatile unsigned char big[6u << 20];                  /* 6 MiB of the 8 MiB reserved */
    uintptr_t sum = 0;

    for (size_t i = 0; i < sizeof big; i++)
        big[i] = (unsigned char)(i + (uintptr_t)arg);
    for (size_t i = 0; i < sizeof big; i += 4099)
        sum += big[i];
    return (void *)sum;
}

/* the far end of a 7 MiB frame written first, no probing: needs the whole stack committed up front */
static SYSV void *far_thread(void *arg)
{
    touch_far_end((size_t)arg);
    return (void *)1;
}

/* Calls fn(a1..a5) with System V registers from assembly, the way the game's .asm files do, with magic values
 * in all callee-saved registers (rbx rbp r12-r15); probe_bad gets a bit for each that came back changed.
 * (Arguments are pointer sized: a Windows `long` has 32 bits.) */
extern SYSV int sysv_probe(void *fn, intptr_t a1, intptr_t a2, intptr_t a3, intptr_t a4, intptr_t a5);
extern SYSV void *probe_pa_new(const void *ss, const void *attr, int *err);
volatile int probe_bad;

__asm__(
    ".intel_syntax noprefix\n"
    ".text\n"
    ".globl sysv_probe\n"
    "sysv_probe:\n"
    "    push rbp\n    push rbx\n    push r12\n    push r13\n    push r14\n    push r15\n    sub rsp, 8\n"
    "    mov rax, rdi\n    mov rdi, rsi\n    mov rsi, rdx\n    mov rdx, rcx\n    mov rcx, r8\n    mov r8, r9\n"
    "    xor r9d, r9d\n"
    "    movabs rbx, 0x1111111111111111\n    movabs rbp, 0x2222222222222222\n    movabs r12, 0x3333333333333333\n"
    "    movabs r13, 0x4444444444444444\n    movabs r14, 0x5555555555555555\n    movabs r15, 0x6666666666666666\n"
    "    call rax\n"
    "    xor ecx, ecx\n"
    "    movabs rdx, 0x1111111111111111\n    cmp rbx, rdx\n    je 1f\n    or ecx, 1\n1:\n"
    "    movabs rdx, 0x2222222222222222\n    cmp rbp, rdx\n    je 2f\n    or ecx, 2\n2:\n"
    "    movabs rdx, 0x3333333333333333\n    cmp r12, rdx\n    je 3f\n    or ecx, 4\n3:\n"
    "    movabs rdx, 0x4444444444444444\n    cmp r13, rdx\n    je 4f\n    or ecx, 8\n4:\n"
    "    movabs rdx, 0x5555555555555555\n    cmp r14, rdx\n    je 5f\n    or ecx, 16\n5:\n"
    "    movabs rdx, 0x6666666666666666\n    cmp r15, rdx\n    je 6f\n    or ecx, 32\n6:\n"
    "    mov dword ptr [rip + probe_bad], ecx\n"
    "    add rsp, 8\n    pop r15\n    pop r14\n    pop r13\n    pop r12\n    pop rbx\n    pop rbp\n    ret\n"
    /* audio_init's call sequence: 6 register arguments, 3 on the stack (map, attr, error) */
    ".globl probe_pa_new\n"
    "probe_pa_new:\n"
    "    push rbp\n    push rbx\n    push r12\n    sub rsp, 32\n"
    "    mov r9, rdi\n    mov r10, rsi\n    mov r11, rdx\n"
    "    xor edi, edi\n    lea rsi, [rip + probe_app]\n    mov edx, 1\n    xor ecx, ecx\n"
    "    lea r8, [rip + probe_stream]\n"
    "    mov qword ptr [rsp], 0\n    mov [rsp + 8], r10\n    mov [rsp + 16], r11\n"
    "    movabs rbx, 0x1111111111111111\n    movabs rbp, 0x2222222222222222\n    movabs r12, 0x3333333333333333\n"
    "    call w_pa_simple_new\n"
    "    xor ecx, ecx\n"
    "    movabs rdx, 0x1111111111111111\n    cmp rbx, rdx\n    je 1f\n    or ecx, 1\n1:\n"
    "    movabs rdx, 0x2222222222222222\n    cmp rbp, rdx\n    je 2f\n    or ecx, 2\n2:\n"
    "    movabs rdx, 0x3333333333333333\n    cmp r12, rdx\n    je 3f\n    or ecx, 4\n3:\n"
    "    mov dword ptr [rip + probe_bad], ecx\n"
    "    add rsp, 32\n    pop r12\n    pop rbx\n    pop rbp\n    ret\n"
    "probe_app: .asciz \"AssemblyCraft\"\n"
    "probe_stream: .asciz \"Game sounds\"\n"
    ".att_syntax prefix\n");

static void test_threads(void)
{
    uintptr_t tid = 0;
    void *ret = NULL;
    uintptr_t t4[EX_THREADS];
    double t0;

    /* create / join with a result, called from C and from assembly */
    CHECKC(w_pthread_create(&tid, NULL, thr_triple, (void *)14) == 0);
    CHECKC(w_pthread_join(tid, &ret) == 0);
    CHECK((uintptr_t)ret == 43, "result %p", ret);
    CHECK(w_pthread_join(tid, &ret) == 3, "a second join is ESRCH");
    CHECK(w_pthread_join(0, NULL) == 3, "join(0) is ESRCH");
    CHECK(w_pthread_create(NULL, NULL, thr_triple, NULL) == 22, "NULL thread -> EINVAL");
    CHECK(w_pthread_create(&tid, NULL, NULL, NULL) == 22, "NULL start -> EINVAL");

    probe_bad = -1;
    tid = 0;
    CHECK(sysv_probe((void *)w_pthread_create, (intptr_t)&tid, 0, (intptr_t)thr_triple, 5, 0) == 0, "asm pthread_create");
    CHECK(probe_bad == 0, "pthread_create kept callee-saved registers (mask %d)", probe_bad);
    ret = NULL;
    probe_bad = -1;
    CHECK(sysv_probe((void *)w_pthread_join, (intptr_t)tid, (intptr_t)&ret, 0, 0, 0) == 0, "asm pthread_join");
    CHECK(probe_bad == 0, "pthread_join kept callee-saved registers (mask %d)", probe_bad);
    CHECK((uintptr_t)ret == 16, "asm-created thread result %p", ret);

    /* a thread that finished long ago can still be joined */
    CHECKC(w_pthread_create(&tid, NULL, thr_triple, (void *)1) == 0);
    Sleep(50);
    CHECKC(w_pthread_join(tid, &ret) == 0 && (uintptr_t)ret == 4);
    /* retval may be NULL */
    CHECKC(w_pthread_create(&tid, NULL, thr_triple, (void *)1) == 0);
    CHECKC(w_pthread_join(tid, NULL) == 0);

    /* joining oneself */
    self_tid = 0;
    CHECKC(w_pthread_create(&tid, NULL, self_thread, NULL) == 0);
    self_tid = tid;
    CHECKC(w_pthread_join(tid, NULL) == 0);
    CHECK(self_rc == 35, "self join -> EDEADLK, got %d", self_rc);

    /* the 8 MiB stack: a thread that needs 6 MiB */
    CHECKC(w_pthread_create(&tid, NULL, stack_thread, (void *)3) == 0);
    CHECKC(w_pthread_join(tid, &ret) == 0);
    CHECK((uintptr_t)ret != 0, "stack thread ran");
    CHECKC(w_pthread_create(&tid, NULL, far_thread, (void *)(7u << 20)) == 0);
    CHECKC(w_pthread_join(tid, &ret) == 0);
    CHECK((uintptr_t)ret == 1, "a worker can use its whole stack without probing");

    /* mutual exclusion */
    memset(&ex, 0, sizeof ex);
    for (int i = 0; i < EX_THREADS; i++)
        CHECKC(w_pthread_create(&t4[i], NULL, ex_thread, NULL) == 0);
    for (int i = 0; i < EX_THREADS; i++)
        CHECKC(w_pthread_join(t4[i], NULL) == 0);
    CHECK(ex.n == (long)EX_THREADS * EX_ITERS, "counter %ld", ex.n);

    /* two threads taking turns through one mutex and one condition variable */
    {
        uintptr_t a, b;

        memset(&pp, 0, sizeof pp);
        t0 = now_ms();
        CHECKC(w_pthread_create(&a, NULL, pp_thread, (void *)0) == 0);
        CHECKC(w_pthread_create(&b, NULL, pp_thread, (void *)1) == 0);
        CHECKC(w_pthread_join(a, NULL) == 0);
        CHECKC(w_pthread_join(b, NULL) == 0);
        CHECK(pp.count == 2 * PP_ROUNDS, "ping-pong count %d", pp.count);
        for (int i = 0; i < pp.count && i < 400; i++)
            if (pp.log[i] != i % 2) { CHECK(0, "ping-pong order broke at %d", i); break; }
        printf("  ping-pong of %d turns: %.1f ms\n", 2 * PP_ROUNDS, now_ms() - t0);
    }

    /* broadcast wakes everybody */
    {
        uintptr_t w[4];

        memset(&bc, 0, sizeof bc);
        for (int i = 0; i < 4; i++)
            CHECKC(w_pthread_create(&w[i], NULL, bc_thread, NULL) == 0);
        t0 = now_ms();
        for (;;) {
            int n;

            w_pthread_mutex_lock(bc.mu);
            n = bc.waiting;
            w_pthread_mutex_unlock(bc.mu);
            if (n == 4 || now_ms() - t0 > 5000) break;
            Sleep(1);
        }
        Sleep(20);                                         /* let the last one reach its wait */
        w_pthread_mutex_lock(bc.mu);
        CHECK(bc.out == 0, "nobody leaves before the broadcast");
        bc.go = 1;
        w_pthread_cond_broadcast(bc.cv);
        w_pthread_mutex_unlock(bc.mu);
        for (int i = 0; i < 4; i++)
            CHECKC(w_pthread_join(w[i], NULL) == 0);
        CHECK(bc.out == 4, "broadcast woke %d of 4", bc.out);
    }

    /* an unaligned 64-byte buffer works, and nothing outside it is touched */
    {
        unsigned char raw[96];
        unsigned char *m = raw + 3;

        memset(raw, 0xA5, sizeof raw);
        memset(m, 0, 64);
        w_pthread_mutex_lock(m);
        w_pthread_mutex_unlock(m);
        w_pthread_cond_signal(m);
        w_pthread_cond_broadcast(m);
        CHECK(memcmp(raw, "\xA5\xA5\xA5", 3) == 0 && raw[3 + 64] == 0xA5 && raw[95] == 0xA5, "canaries intact");
        CHECK(((uintptr_t)slot8(m) & 7) == 0 && slot8(m) >= (void *)m && (char *)slot8(m) + 8 <= (char *)m + 64,
              "lock slot aligned inside the buffer");
    }

    /* mutex and cond called from assembly keep the callee-saved registers */
    {
        static char mu[64], cv[64];

        probe_bad = -1;
        CHECKC(sysv_probe((void *)w_pthread_mutex_lock, (intptr_t)mu, 0, 0, 0, 0) == 0);
        CHECK(probe_bad == 0, "mutex_lock mask %d", probe_bad);
        probe_bad = -1;
        CHECKC(sysv_probe((void *)w_pthread_cond_signal, (intptr_t)cv, 0, 0, 0, 0) == 0);
        CHECK(probe_bad == 0, "cond_signal mask %d", probe_bad);
        probe_bad = -1;
        CHECKC(sysv_probe((void *)w_pthread_cond_broadcast, (intptr_t)cv, 0, 0, 0, 0) == 0);
        CHECK(probe_bad == 0, "cond_broadcast mask %d", probe_bad);
        probe_bad = -1;
        CHECKC(sysv_probe((void *)w_pthread_mutex_unlock, (intptr_t)mu, 0, 0, 0, 0) == 0);
        CHECK(probe_bad == 0, "mutex_unlock mask %d", probe_bad);
    }
}

/* ================================================================================================== */
/* usleep                                                                                              */
/* ================================================================================================== */

static int cmp_dbl(const void *a, const void *b)
{
    double x = *(const double *)a, y = *(const double *)b;

    return x < y ? -1 : x > y;
}

static void test_usleep(void)
{
    static const unsigned us[] = { 1, 100, 1000, 2000, 5000, 20000, 100000 };
    double t;

    timeBeginPeriod(1);
    for (unsigned k = 0; k < sizeof us / sizeof us[0]; k++) {
        double s[15], min = 1e9;
        int reps = us[k] >= 100000 ? 3 : 15;

        for (int i = 0; i < reps; i++) {
            t = now_ms();
            CHECKC(w_usleep(us[k]) == 0);
            s[i] = (now_ms() - t) * 1000.0;
            if (s[i] < min) min = s[i];
        }
        qsort(s, (size_t)reps, sizeof s[0], cmp_dbl);
        printf("  usleep(%u): min %.0f us, median %.0f us, max %.0f us\n", us[k], min, s[reps / 2], s[reps - 1]);
        CHECK(min >= (double)us[k], "usleep(%u) returned early: %.1f us", us[k], min);
        CHECK(s[reps / 2] < (double)us[k] + 4000.0, "usleep(%u) median %.0f us is too late", us[k], s[reps / 2]);
    }
    t = now_ms();
    CHECKC(w_usleep(0) == 0);
    CHECK(now_ms() - t < 20.0, "usleep(0) took %.1f ms", now_ms() - t);

    probe_bad = -1;
    t = now_ms();
    CHECKC(sysv_probe((void *)w_usleep, 3000, 0, 0, 0, 0) == 0);
    CHECK(probe_bad == 0, "usleep kept callee-saved registers (mask %d)", probe_bad);
    CHECK(now_ms() - t >= 3.0, "usleep(3000) from assembly took %.2f ms", now_ms() - t);
    timeEndPeriod(1);
}

/* ================================================================================================== */
/* audio on whatever device the host has (maybe none)                                                  */
/* ================================================================================================== */

/* audio.asm's pa_ss and pa_attr */
static const pa_sample_spec game_ss = { 3, 44100, 2 };
static const pa_buffer_attr game_attr = { 0xFFFFFFFFu, 10584, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu };

static void test_audio_real(void)
{
    int err = -1;
    void *s;

    {   /* the error pointer is the 9th argument, the third one on the stack: it must come through even without a device */
        pa_sample_spec bad = { 3, 0, 2 };                  /* rate 0 is invalid whatever the host has */
        int e2 = -1;

        probe_bad = -1;
        CHECK(probe_pa_new(&bad, &game_attr, &e2) == NULL && e2 == 3, "error pointer from assembly: error %d", e2);
        CHECK(probe_bad == 0, "pa_simple_new failure path kept callee-saved registers (%d)", probe_bad);
    }
    probe_bad = -1;
    s = probe_pa_new(&game_ss, &game_attr, &err);
    CHECK(probe_bad == 0, "pa_simple_new from assembly (3 stack arguments) kept callee-saved registers (%d)", probe_bad);
    if (!s) {
        printf("  audio: no device (waveOutGetNumDevs=%u): pa_simple_new returned NULL, *error = %d\n",
               waveOutGetNumDevs(), err);
        CHECK(err == 3 || err == 5 || err == 6 || err == 10 || err == 19 || err == 26, "error code %d", err);
        return;
    }
    {   /* the spec is the 6th argument (r9): the geometry follows from it; attr (8th, on the stack) is ignored */
        pa_stream *p = s;

        CHECK(p->fs == 4 && p->buf_frames == 441 && p->prime_frames == 1764 && p->cap_frames == 4410,
              "geometry of a stream opened from assembly: %u %u %u %u", p->fs, p->buf_frames, p->prime_frames,
              p->cap_frames);
    }
    printf("  audio: device opened (waveOutGetNumDevs=%u)\n", waveOutGetNumDevs());
    {
        static short buf[735 * 2];                         /* zeros: silence */
        double t0 = now_ms(), worst = 0;
        int r = 0;

        for (int i = 0; i < 60 && r == 0; i++) {           /* 60 frames of 735 = 1.0 s, as fast as it lets us */
            double t = now_ms();

            r = w_pa_simple_write(s, buf, sizeof buf, &err);
            if (now_ms() - t > worst) worst = now_ms() - t;
        }
        t0 = now_ms() - t0;
        printf("  audio: 1.0 s of silence written in %.0f ms (longest single write %.0f ms)\n", t0, worst);
        CHECK(r == 0, "write failed, error %d", err);
        CHECK(t0 > 800.0 && t0 < 2500.0, "1 s of audio was accepted in %.0f ms: the write does not throttle", t0);
        CHECK(w_pa_simple_write(s, NULL, 4, &err) == -1 && err == 3, "NULL data");
        CHECK(w_pa_simple_write(s, buf, 0, &err) == -1 && err == 3, "zero bytes");
        CHECK(w_pa_simple_write(s, buf, 6, &err) == 0, "a partial frame is accepted");
    }
    w_pa_simple_free(s);
    w_pa_simple_free(NULL);
}

#endif /* !FAKE_WAVE */

/* ================================================================================================== */
/* the audio ring against the fake device                                                              */
/* ================================================================================================== */
#ifdef FAKE_WAVE

static const pa_sample_spec game_ss = { 3, 44100, 2 };
static const pa_buffer_attr game_attr = { 0xFFFFFFFFu, 10584, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu };

static void fk_open(pa_stream **out)
{
    int err = -1;

    fk_reset_state();
    *out = w_pa_simple_new(NULL, "t", 1, NULL, "t", &game_ss, NULL, &game_attr, &err);
    CHECK(*out != NULL, "pa_simple_new failed, error %d", err);
}

static unsigned char pat(size_t i) { return (unsigned char)(1 + i % 250); }       /* never 0 = silence */

static void test_new_errors(void)
{
    int err;
    pa_sample_spec ss = game_ss;
    pa_stream *s;

    fk_reset_state();
    fk.ndevs = 0;
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 1, NULL, "t", &game_ss, NULL, NULL, &err) == NULL && err == 6, "no device: %d", err);
    fk_reset_state();
    fk.open_error = MMSYSERR_ALLOCATED;
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 1, NULL, "t", &game_ss, NULL, NULL, &err) == NULL && err == 26, "busy: %d", err);
    fk.open_error = WAVERR_BADFORMAT;
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 1, NULL, "t", &game_ss, NULL, NULL, &err) == NULL && err == 19, "bad format: %d", err);
    fk.open_error = MMSYSERR_BADDEVICEID;
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 1, NULL, "t", &game_ss, NULL, NULL, &err) == NULL && err == 6, "bad device: %d", err);
    fk.open_error = MMSYSERR_NOMEM;
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 1, NULL, "t", &game_ss, NULL, NULL, &err) == NULL && err == 10, "nomem: %d", err);
    CHECK(w_pa_simple_new(NULL, "t", 1, NULL, "t", &game_ss, NULL, NULL, NULL) == NULL, "NULL error pointer is fine");
    fk_reset_state();
    ss.rate = 0;
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 1, NULL, "t", &ss, NULL, NULL, &err) == NULL && err == 3, "rate 0: %d", err);
    ss = game_ss; ss.channels = 0;
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 1, NULL, "t", &ss, NULL, NULL, &err) == NULL && err == 3, "0 channels: %d", err);
    ss = game_ss; ss.channels = 3;
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 1, NULL, "t", &ss, NULL, NULL, &err) == NULL && err == 19, "3 channels: %d", err);
    ss = game_ss; ss.format = 5;
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 1, NULL, "t", &ss, NULL, NULL, &err) == NULL && err == 19, "float: %d", err);
    ss = game_ss; ss.format = 99;
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 1, NULL, "t", &ss, NULL, NULL, &err) == NULL && err == 3, "format 99: %d", err);
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 2, NULL, "t", &game_ss, NULL, NULL, &err) == NULL && err == 19, "record: %d", err);
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 0, NULL, "t", &game_ss, NULL, NULL, &err) == NULL && err == 3, "dir 0: %d", err);
    err = 0; CHECK(w_pa_simple_new(NULL, "t", 1, NULL, "t", NULL, NULL, NULL, &err) == NULL && err == 3, "no spec: %d", err);
    CHECK(fk.opens == 0, "nothing was opened by the failures (%d)", fk.opens);

    /* geometry: the ceiling is fixed (the game's attr, no attr, a silly tlength all give the same), mono scales */
    fk_open(&s);
    if (s) {
        CHECK(s->buf_frames == 441 && s->prime_frames == 1764 && s->cap_frames == 4410 && s->low_frames == 2205 &&
              s->send_frames == 882, "game geometry %u %u %u %u %u", s->buf_frames, s->prime_frames, s->cap_frames,
              s->low_frames, s->send_frames);
        w_pa_simple_free(s);
    }
    s = w_pa_simple_new(NULL, "t", 1, NULL, "t", &game_ss, NULL, NULL, &err);
    CHECK(s && s->cap_frames == 4410, "no attr: cap %u", s ? s->cap_frames : 0);
    if (s) w_pa_simple_free(s);
    {
        pa_buffer_attr a = game_attr;

        a.tlength = 1000;
        s = w_pa_simple_new(NULL, "t", 1, NULL, "t", &game_ss, NULL, &a, &err);
        CHECK(s && s->cap_frames == 4410, "tiny tlength: cap %u", s ? s->cap_frames : 0);
        if (s) w_pa_simple_free(s);
    }
    ss = game_ss; ss.channels = 1; ss.rate = 22050;
    s = w_pa_simple_new(NULL, "t", 1, NULL, "t", &ss, NULL, &game_attr, &err);
    CHECK(s && s->fs == 2 && s->buf_frames == 220 && s->prime_frames == 880 && s->cap_frames == 2200 &&
          s->low_frames == 1100, "mono geometry fs %u buf %u prime %u cap %u low %u", s ? s->fs : 0,
          s ? s->buf_frames : 0, s ? s->prime_frames : 0, s ? s->cap_frames : 0, s ? s->low_frames : 0);
    if (s) w_pa_simple_free(s);
    CHECK(fk.opens == fk.closes, "opens %d closes %d", fk.opens, fk.closes);
}

/* every byte the caller wrote arrives, in order, behind the priming silence, whatever the chunking */
static void test_integrity(void)
{
    static const size_t chunks[] = { 1, 3, 4, 7, 1000, 4096, 2, 6, 8192, 12345, 1, 1, 1, 1, 5, 20000, 3 };
    pa_stream *s;
    size_t total = 0, n = 0;
    unsigned char *data = malloc(200000), *got;
    int err = 0, rc = 0;
    size_t sil_frames = 0, pos = 0, i;

    fk_open(&s);
    if (!s) return;
    for (i = 0; i < sizeof chunks / sizeof chunks[0]; i++) {
        for (size_t k = 0; k < chunks[i]; k++)
            data[n + k] = pat(n + k);
        rc |= w_pa_simple_write(s, data + n, chunks[i], &err);
        n += chunks[i];
        if (i == 1) {                                      /* 1 + 3 bytes: the first whole frame -> the prime */
            sil_frames = s->prime_frames - 1;
        }
    }
    CHECK(rc == 0, "writes failed (%d)", err);
    CHECK(fk.idle_writes == 0, "the device ran dry during the test (a loaded machine?): the comparison is void");
    total = (size_t)fk.cap_len + s->fill_len;
    got = malloc(total + 16);
    memcpy(got, fk.cap, fk.cap_len);
    memcpy(got + fk.cap_len, s->hdr[s->fill].lpData, s->fill_len);
    /* silence first, then the stream up to the incomplete frame */
    CHECK(total == sil_frames * 4 + (n - s->carry_len), "total %zu, expected %zu (carry %u)", total,
          sil_frames * 4 + (n - s->carry_len), s->carry_len);
    for (i = 0; i < sil_frames * 4 && i < total; i++)
        if (got[i] != 0) { CHECK(0, "silence broken at byte %zu", i); break; }
    pos = sil_frames * 4;
    for (i = 0; pos + i < total; i++)
        if (got[pos + i] != data[i]) { CHECK(0, "stream differs at byte %zu (%u != %u)", i, got[pos + i], data[i]); break; }
    for (i = 0; i < s->carry_len; i++)
        CHECK(s->carry[i] == data[n - s->carry_len + i], "carry byte %zu", i);
    printf("  integrity: %zu bytes in, %zu silence + %zu data out, %u carried, %d buffers handed over\n", n,
           sil_frames * 4, total - sil_frames * 4, s->carry_len, fk.writes);
    w_pa_simple_free(s);
    CHECK(fk.opens == fk.closes, "opens %d closes %d", fk.opens, fk.closes);
    free(data);
    free(got);
}

/* writing faster than real time is held to real time */
static void test_throttle(void)
{
    static unsigned char buf[735 * 4];
    pa_stream *s;
    double t0, el;
    int err = 0, r = 0;

    fk_open(&s);
    if (!s) return;
    t0 = now_ms();
    for (int i = 0; i < 60 && r == 0; i++)                 /* 1.0 s of audio in 735-frame chunks */
        r = w_pa_simple_write(s, buf, sizeof buf, &err);
    el = now_ms() - t0;
    printf("  throttle: 1.0 s of audio accepted after %.0f ms (50..100 ms are still queued when it returns: 920..970)\n",
           el);
    CHECK(r == 0, "write failed %d", err);
    CHECK(el > 880.0 && el < 1050.0, "%.0f ms", el);
    w_pa_simple_free(s);
}

/* the game's pattern: one write per 1/60 s of the same amount of audio: never blocks, keeps its lead */
static void test_steady(void)
{
    static unsigned char buf[735 * 4];
    pa_stream *s;
    double t0, worst = 0, lead_min = 1e9, lead_max = 0;
    int err = 0, r = 0;

    fk_open(&s);
    if (!s) return;
    t0 = now_ms();
    for (int i = 0; i < 180; i++) {                        /* 3 s */
        double due = t0 + i * (1000.0 / 60.0), t, lead;

        while ((t = now_ms()) < due - 1.0)
            Sleep(1);
        while (now_ms() < due)
            YieldProcessor();
        t = now_ms();
        r |= w_pa_simple_write(s, buf, sizeof buf, &err);
        if (now_ms() - t > worst && i > 0) worst = now_ms() - t;
        lead = fk.next_free - now_ms();
        if (i >= 5) {
            if (lead < lead_min) lead_min = lead;
            if (lead > lead_max) lead_max = lead;
        }
    }
    printf("  steady: 180 writes at 60 Hz: longest write %.2f ms, lead after a write %.1f .. %.1f ms, device ran dry %d times\n",
           worst, lead_min, lead_max, fk.idle_writes);
    CHECK(r == 0, "write failed %d", err);
    CHECK(worst < 6.0, "a write blocked for %.2f ms in steady state", worst);
    CHECK(lead_min > 22.0 && lead_max < 60.0, "lead %.1f .. %.1f ms", lead_min, lead_max);
    CHECK(fk.idle_writes <= 1, "the device ran dry %d times", fk.idle_writes);

    /* a stall of the caller longer than the lead: the device runs dry and the lead is rebuilt */
    {
        size_t before, fill0 = s->fill_len, after;
        unsigned prime = s->prime_frames, fs = s->fs;

        Sleep(300);
        CHECK(au_inflight(s) == 0, "the device drained");
        before = fk.cap_len + s->fill_len;
        r = w_pa_simple_write(s, buf, sizeof buf, &err);
        after = fk.cap_len + s->fill_len;
        CHECK(r == 0, "write after the stall failed %d", err);
        CHECK(after - before + fill0 == (size_t)prime * fs, "after a dry spell %zu bytes were queued + %zu waiting, lead %zu",
              after - before, fill0, (size_t)prime * fs);
        CHECK(fk.next_free - now_ms() > 25.0, "lead rebuilt: %.1f ms", fk.next_free - now_ms());
    }
    w_pa_simple_free(s);
}

/* a device that returns nothing: one reset after 200 ms, the caller carries on; after three in a row it ends */
static void test_stall(void)
{
    static unsigned char buf[5000 * 4];                        /* more than the ceiling: one write must cross it */
    pa_stream *s;
    double t;
    int err = 0, r;

    fk_open(&s);
    if (!s) return;
    CHECKC(w_pa_simple_write(s, buf, sizeof buf, &err) == 0);   /* fine while it runs */
    fk.freeze = 1;
    t = now_ms();
    r = w_pa_simple_write(s, buf, sizeof buf, &err);            /* fills the ring, then waits for the frozen device */
    r |= w_pa_simple_write(s, buf, sizeof buf, &err);
    CHECK(r == 0, "the first stall must be survived (%d)", err);
    CHECK(fk.resets >= 1 && s->stalls >= 1, "device was reset (%d resets, %d stalls)", fk.resets, s->stalls);
    printf("  stall: first stall survived after %.0f ms, %d reset(s)\n", now_ms() - t, fk.resets);
    t = now_ms();
    for (int i = 0; i < 12 && r == 0; i++)
        r = w_pa_simple_write(s, buf, sizeof buf, &err);
    printf("  stall: dead device gave up after %.0f ms with error %d, %d reset(s)\n", now_ms() - t, err, fk.resets);
    CHECK(r == -1 && err == 11, "a dead device ends the stream: r=%d err=%d", r, err);
    CHECK(now_ms() - t < 2500.0, "gave up after %.0f ms", now_ms() - t);
    t = now_ms();
    err = 0;
    CHECK(w_pa_simple_write(s, buf, sizeof buf, &err) == -1 && err == 11, "later writes fail");
    CHECK(now_ms() - t < 5.0, "... at once (%.1f ms)", now_ms() - t);
    w_pa_simple_free(s);
    CHECK(fk.opens == fk.closes, "opens %d closes %d", fk.opens, fk.closes);

    /* a device that comes back: one stall, then healthy again */
    fk_open(&s);
    if (!s) return;
    CHECKC(w_pa_simple_write(s, buf, sizeof buf, &err) == 0);
    fk.freeze = 1;
    CHECKC(w_pa_simple_write(s, buf, sizeof buf, &err) == 0);   /* stalls once, then the reset frees the ring */
    fk.freeze = 0;
    CHECKC(s->stalls == 1);
    for (int i = 0; i < 20; i++)
        CHECKC(w_pa_simple_write(s, buf, 735 * 4, &err) == 0);
    CHECK(s->stalls == 0, "a healthy wait clears the stall count (%d)", s->stalls);
    w_pa_simple_free(s);
}

/* the tail of a write waits for a full buffer only while 20 ms are queued ahead of it; below that it goes out */
static void test_send_rule(void)
{
    static unsigned char buf[735 * 4];
    pa_stream *s;
    int err = 0;

    fk_open(&s);
    if (!s) return;
    fk.freeze = 1;                                             /* nothing completes unless fk_complete() says so */
    CHECKC(w_pa_simple_write(s, buf, 700 * 4, &err) == 0);     /* prime: silence + 700 frames = exactly 4 buffers */
    CHECK(s->fill_len == 0 && fk.writes == 4, "prime left %u bytes waiting, %d buffers sent", s->fill_len, fk.writes);
    CHECKC(w_pa_simple_write(s, buf, 100 * 4, &err) == 0);     /* 40 ms are queued: the tail waits */
    CHECK(s->fill_len == 400 && fk.writes == 4, "tail %u bytes, %d buffers sent", s->fill_len, fk.writes);
    fk_complete(3);                                            /* the device played 3 buffers: 10 ms are left */
    CHECKC(w_pa_simple_write(s, buf, 50 * 4, &err) == 0);
    CHECK(s->fill_len == 0 && fk.writes == 5, "queue low: the tail went out (%u bytes waiting, %d sent)", s->fill_len,
          fk.writes);
    w_pa_simple_free(s);
}

/* The game's loop: a write of dt seconds on an absolute 60 Hz schedule. A long frame starves the device; the
 * next write is a 46 ms burst (and, when the stall falls between the dt measurement and the write, a priming
 * write comes first). That must not leave later writes waiting at the ceiling (each wait stretches the frame,
 * the next dt and write are bigger, and the loop stays audio-bound at a lower rate). */
static void hitch_case(int before_write)
{
    pa_stream *s;
    double t0, last, worst = 0, frac = 0, el;
    static unsigned char buf[2048 * 4];
    int err = 0, r = 0;

    fk_open(&s);
    if (!s) return;
    t0 = last = now_ms();
    for (int i = 0; i < 240; i++) {
        double due = t0 + i * (1000.0 / 60.0), now, a, dt, want;
        int frames;

        while ((now = now_ms()) < due - 1.0)
            Sleep(1);
        while ((now = now_ms()) < due)
            YieldProcessor();
        dt = (now - last) / 1000.0;
        last = now;
        if (dt > 0.1) dt = 0.1;
        want = dt * 44100.0 + frac;
        frames = (int)want;
        frac = want - frames;
        if (frames > 2048) frames = 2048;
        if (i == 100 && before_write)
            Sleep(150);
        a = now_ms();
        if (frames > 0)
            r |= w_pa_simple_write(s, buf, (size_t)frames * 4, &err);
        if (i > 103 && now_ms() - a > worst) worst = now_ms() - a;
        if (i == 100 && !before_write)
            Sleep(150);                                        /* a long frame: the device runs dry */
    }
    el = now_ms() - t0;
    printf("  hitch (%s the write): 240 frames at 60 Hz with a 150 ms stall: %.0f ms (schedule %.0f), longest write after "
           "it %.2f ms\n", before_write ? "before" : "after", el, 240 * 1000.0 / 60.0, worst);
    CHECK(r == 0, "write failed %d", err);
    CHECK(worst < 6.0, "after the hitch a write waited %.2f ms", worst);
    CHECK(el < 240 * 1000.0 / 60.0 + 250.0, "the loop did not return to its schedule: %.0f ms", el);
    w_pa_simple_free(s);
}

static void test_hitch(void)
{
    hitch_case(0);
    hitch_case(1);
}

static void test_failures(void)
{
    static unsigned char buf[2000 * 4];
    pa_stream *s;
    int err = 0;

    fk_open(&s);
    if (!s) return;
    fk.fail_write = 1;
    CHECK(w_pa_simple_write(s, buf, sizeof buf, &err) == -1 && err == 11, "waveOutWrite failure -> %d", err);
    err = 0;
    CHECK(w_pa_simple_write(s, buf, 4, &err) == -1 && err == 11, "stays failed");
    w_pa_simple_free(s);
    CHECK(fk.opens == fk.closes, "opens %d closes %d", fk.opens, fk.closes);
    CHECK(w_pa_simple_write(NULL, buf, 4, &err) == -1 && err == 3, "NULL stream");
    w_pa_simple_free(NULL);
}

#endif /* FAKE_WAVE */

/* A hang (a lost wake-up, a join that never returns) ends the run with a message instead of waiting forever. */
static DWORD WINAPI watchdog(LPVOID p)
{
    Sleep((DWORD)(uintptr_t)p);
    printf("WATCHDOG: the test hung\n");
    fflush(stdout);
    ExitProcess(98);
    return 0;
}

int main(int argc, char **argv)
{
#ifndef FAKE_WAVE
    if (argc >= 3 && strcmp(argv[1], "--entry-child") == 0)
        return win_misc_main();
    (void)argc; (void)argv;
    CloseHandle(CreateThread(NULL, 0, watchdog, (LPVOID)(uintptr_t)120000, 0, NULL));
    printf("entry:\n");           test_entry();
    printf("args/env:\n");        test_args_env();
    printf("threads:\n");         test_threads();
    printf("usleep:\n");          test_usleep();
    printf("audio (real API):\n"); test_audio_real();
#else
    (void)argc; (void)argv;
    CloseHandle(CreateThread(NULL, 0, watchdog, (LPVOID)(uintptr_t)90000, 0, NULL));
    InitializeCriticalSection(&fk.cs);
    fk.thread = CreateThread(NULL, 0, fk_thread, NULL, 0, NULL);
    timeBeginPeriod(1);
    printf("audio ring (fake device):\n");
    test_new_errors();
    test_integrity();
    test_throttle();
    test_steady();
    test_hitch();
    test_stall();
    test_send_rule();
    test_failures();
    fk.stop = 1;
    WaitForSingleObject(fk.thread, 2000);
    timeEndPeriod(1);
#endif
    printf(fails ? "FAILED: %d check(s)\n" : "ALL PASSED\n", fails);
    return fails ? 1 : 0;
}
