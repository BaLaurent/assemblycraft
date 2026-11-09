/* win_gfx_test.c - standalone test of win/win_gfx.c; NOT part of the game (the Makefile builds only win/ itself).
 *
 * win_gfx.c is #included, so its statics (the lazy table, the callback slots) are reachable, and every OpenGL
 * and GLFW function it calls is replaced by a fake defined here: no opengl32, no GLFW, no window, so it runs
 * headless under wine. What is checked:
 *  - every one of the 82 wrappers forwards to the right function with every argument in the right place (a
 *    table-driven pass with a distinct value in each argument, including doubles, floats, 64-bit sizes and the
 *    stack arguments of glTexImage2D / glfwSetWindowMonitor), and returns what the callee returned;
 *  - the same for calls made by hand-written assembly with the registers and stack the game's code uses
 *    (render.asm TEXIMAGE, settings.asm's 7th argument on the stack, glFrustum in xmm0-5, ...), with rbx and
 *    r12-r15 and rsp intact afterwards, and a Win64 callee that scribbles its shadow space (a tail jump into
 *    the real function would corrupt the caller: the wrappers must not do that);
 *  - the callback trampolines: a Win64 caller (GLFW's side, in assembly) keeps rsi, rdi, rbx, r12-r15 and
 *    xmm6-15 across a call into a System V game callback that destroys them;
 *  - lazy resolution of the GL > 1.1 functions: no context, ARB fallback, the 1/2/3/-1 answers of some
 *    drivers, absent functions (ignored, one line on stderr), re-resolution after a context change, and
 *    the no-buffer-objects fallback (glGenBuffers names 0, glDrawArrays skipped);
 *  - the GLFW error log (first four of each kind).
 * Each assembly check has a negative control (a callee that does clobber what the check watches).
 *
 * Build and run, from the repository root (T = a scratch directory; wine needs the prefix inside a directory
 * you own):
 *   docker run --rm -u $(id -u):$(id -g) -v $PWD:/src -v T:/out -w /src ac-mingw x86_64-w64-mingw32-gcc -O2 \
 *       -std=gnu11 -Wall -Wextra -Iwin/glfw/include win/tests/win_gfx_test.c -o /out/win_gfx_test.exe
 *   WINEDEBUG=-all WINEPREFIX=T/prefix wine T/win_gfx_test.exe        (exit code 0 = every check passed) */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#undef WINGDIAPI
#define WINGDIAPI                                   /* the GL functions are defined below, not imported */
#define GLFW_INCLUDE_NONE
#include <GL/gl.h>
#include <GLFW/glfw3.h>

/* what win_gfx.c writes to stderr is captured instead */
#define GetStdHandle fake_GetStdHandle
#define WriteFile fake_WriteFile
static HANDLE fake_GetStdHandle(DWORD which);
static BOOL fake_WriteFile(HANDLE h, LPCVOID buf, DWORD len, LPDWORD written, LPOVERLAPPED ov);

#include "../win_gfx.c"

/* ---- test bookkeeping ------------------------------------------------------------------------- */

static int n_checks, n_fail;

#define EXPECT(cond, ...) \
    do { \
        n_checks++; \
        if (!(cond)) { \
            n_fail++; \
            printf("FAIL %s:%d: ", __func__, __LINE__); \
            printf(__VA_ARGS__); \
            printf("\n"); \
        } \
    } while (0)

/* the 82 functions the game imports (nm -D -u build/assemblycraft): each must be exercised by some check */
static const char *const all_wrappers[] = {
    "glActiveTexture", "glAlphaFunc", "glBegin", "glBindBuffer", "glBindTexture", "glBlendFunc", "glBufferData",
    "glClear", "glClearColor", "glClientActiveTexture", "glColor3f", "glColor4f", "glColor4ub", "glColorPointer",
    "glDepthMask", "glDisable", "glDisableClientState", "glDrawArrays", "glEnable", "glEnableClientState",
    "glEnd", "glFogf", "glFogfv", "glFogi", "glFrustum", "glGenBuffers", "glGenTextures", "glGetFloatv",
    "glIsEnabled", "glLineWidth", "glLoadIdentity", "glMatrixMode", "glMultiTexCoord2f", "glOrtho",
    "glPixelStorei", "glPopMatrix", "glPushMatrix", "glRotatef", "glScalef", "glScissor", "glTexCoord2i",
    "glTexCoordPointer", "glTexEnvi", "glTexImage2D", "glTexParameteri", "glTranslatef", "glVertex2f",
    "glVertex2i", "glVertex3f", "glVertexPointer", "glViewport",
    "glfwCreateWindow", "glfwDestroyWindow", "glfwGetCursorPos", "glfwGetFramebufferSize", "glfwGetKey",
    "glfwGetKeyName", "glfwGetMouseButton", "glfwGetPrimaryMonitor", "glfwGetTime", "glfwGetVideoMode",
    "glfwGetWindowAttrib", "glfwGetWindowPos", "glfwGetWindowSize", "glfwInit", "glfwMakeContextCurrent",
    "glfwPollEvents", "glfwRawMouseMotionSupported", "glfwSetCharCallback", "glfwSetInputMode",
    "glfwSetKeyCallback", "glfwSetMouseButtonCallback", "glfwSetScrollCallback", "glfwSetWindowMonitor",
    "glfwSetWindowShouldClose", "glfwSetWindowTitle", "glfwSwapBuffers", "glfwSwapInterval", "glfwTerminate",
    "glfwWindowHint", "glfwWindowHintString", "glfwWindowShouldClose",
};
#define N_WRAPPERS ((int)(sizeof all_wrappers / sizeof all_wrappers[0]))
static unsigned char exercised[N_WRAPPERS];

static void mark(const char *name)
{
    int i;

    for (i = 0; i < N_WRAPPERS; i++) {
        if (strcmp(all_wrappers[i], name) == 0) {
            exercised[i] = 1;
            return;
        }
    }
    n_fail++;
    printf("FAIL: %s is not in the import list\n", name);
}

/* ---- stderr capture --------------------------------------------------------------------------- */

static char err_buf[4096];
static size_t err_len;

static HANDLE fake_GetStdHandle(DWORD which)
{
    (void)which;
    return (HANDLE)(uintptr_t)0x5E;
}

static BOOL fake_WriteFile(HANDLE h, LPCVOID buf, DWORD len, LPDWORD written, LPOVERLAPPED ov)
{
    (void)h;
    (void)ov;
    if (err_len + len < sizeof err_buf) {
        memcpy(err_buf + err_len, buf, len);
        err_len += len;
        err_buf[err_len] = 0;
    }
    if (written != NULL)
        *written = len;
    return TRUE;
}

static int err_lines(void)
{
    int n = 0;
    size_t i;

    for (i = 0; i < err_len; i++)
        n += err_buf[i] == '\n';
    return n;
}

/* ---- call log: every fake records its name and the raw bytes of each argument ------------------ */

typedef struct {
    const char *name;
    int argc;
    uint64_t arg[9];                                /* the bytes of each argument, zero-extended to 8 */
} Call;

static Call calls[256];
static int ncalls;

static Call *rec_begin(const char *name, int argc)
{
    Call *c = &calls[ncalls < 255 ? ncalls : 255];

    ncalls++;
    memset(c, 0, sizeof *c);
    c->name = name;
    c->argc = argc;
    return c;
}

/* ---- X-macro machinery: one table row per function, expanded into a fake and into a check ------- */

#define CAT_(a, b) a##b
#define CAT(a, b) CAT_(a, b)
#define NARGS_(_0, _1, _2, _3, _4, _5, _6, _7, _8, _9, N, ...) N
#define NARGS(...) NARGS_(0 __VA_OPT__(,) __VA_ARGS__, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0)

#define EACH_0(m)
#define EACH_1(m, a) m(1, a)
#define EACH_2(m, a, b) EACH_1(m, a) m(2, b)
#define EACH_3(m, a, b, c) EACH_2(m, a, b) m(3, c)
#define EACH_4(m, a, b, c, d) EACH_3(m, a, b, c) m(4, d)
#define EACH_5(m, a, b, c, d, e) EACH_4(m, a, b, c, d) m(5, e)
#define EACH_6(m, a, b, c, d, e, f) EACH_5(m, a, b, c, d, e) m(6, f)
#define EACH_7(m, a, b, c, d, e, f, g) EACH_6(m, a, b, c, d, e, f) m(7, g)
#define EACH_8(m, a, b, c, d, e, f, g, h) EACH_7(m, a, b, c, d, e, f, g) m(8, h)
#define EACH_9(m, a, b, c, d, e, f, g, h, i) EACH_8(m, a, b, c, d, e, f, g, h) m(9, i)
#define EACH(m, ...) CAT(EACH_, NARGS(__VA_ARGS__))(m __VA_OPT__(,) __VA_ARGS__)

#define EACHC_0(m)
#define EACHC_1(m, a) m(1, a)
#define EACHC_2(m, a, b) EACHC_1(m, a), m(2, b)
#define EACHC_3(m, a, b, c) EACHC_2(m, a, b), m(3, c)
#define EACHC_4(m, a, b, c, d) EACHC_3(m, a, b, c), m(4, d)
#define EACHC_5(m, a, b, c, d, e) EACHC_4(m, a, b, c, d), m(5, e)
#define EACHC_6(m, a, b, c, d, e, f) EACHC_5(m, a, b, c, d, e), m(6, f)
#define EACHC_7(m, a, b, c, d, e, f, g) EACHC_6(m, a, b, c, d, e, f), m(7, g)
#define EACHC_8(m, a, b, c, d, e, f, g, h) EACHC_7(m, a, b, c, d, e, f, g), m(8, h)
#define EACHC_9(m, a, b, c, d, e, f, g, h, i) EACHC_8(m, a, b, c, d, e, f, g, h), m(9, i)
#define EACHC(m, ...) CAT(EACHC_, NARGS(__VA_ARGS__))(m __VA_OPT__(,) __VA_ARGS__)

/* per-argument pieces: i = position (1-based), T = type */
#define P_DECL(i, T) T a##i
#define P_STORE(i, T) memcpy(&cur->arg[(i) - 1], &a##i, sizeof a##i);
/* a distinct value per argument; 8-byte types also get a bit above 2^32 so a truncated 64-bit value shows */
#define P_VAL(i, T) T v##i = (T)(uintptr_t)(base + (i) + (((uint64_t)(sizeof(T) == 8)) << 33));
#define P_VNAME(i, T) v##i
#define P_EXP(i, T) memcpy(&exp[(i) - 1], &v##i, sizeof v##i);

/* what every fake that returns something returns: 64 distinct bits, so a wrapper that truncates or converts it
 * shows (as a double it is not exactly representable as a float, as a pointer it has high bits) */
static const uint64_t ret_bits = 0x40D4A2B3C4D5E6F7u;

#define FAKE(id, str, ...) \
    void id(EACHC(P_DECL, __VA_ARGS__)) \
    { \
        Call *cur = rec_begin(str, NARGS(__VA_ARGS__)); \
        (void)cur; \
        EACH(P_STORE, __VA_ARGS__) \
    }

#define FAKE_R(R, id, str, ...) \
    R id(EACHC(P_DECL, __VA_ARGS__)) \
    { \
        Call *cur = rec_begin(str, NARGS(__VA_ARGS__)); \
        (void)cur; \
        EACH(P_STORE, __VA_ARGS__) \
        R r; \
        memcpy(&r, &ret_bits, sizeof r); \
        return r; \
    }

static uintptr_t next_base;

static void verify(const char *name, int argc, const uint64_t *exp)
{
    int i;

    mark(name);
    EXPECT(ncalls == 1, "%s: forwarded %d times, expected once", name, ncalls);
    if (ncalls != 1)
        return;
    EXPECT(strcmp(calls[0].name, name) == 0, "%s: forwarded to %s", name, calls[0].name);
    EXPECT(calls[0].argc == argc, "%s: forwarded with %d arguments, expected %d", name, calls[0].argc, argc);
    for (i = 0; i < argc; i++)
        EXPECT(calls[0].arg[i] == exp[i], "%s: argument %d arrived as 0x%llx, expected 0x%llx", name, i + 1,
               (unsigned long long)calls[0].arg[i], (unsigned long long)exp[i]);
}

#define CHECK_FN(name, ...) \
    static void check_##name(void) \
    { \
        const uintptr_t base = (next_base += 16); \
        uint64_t exp[9] = { 0 }; \
        EACH(P_VAL, __VA_ARGS__) \
        EACH(P_EXP, __VA_ARGS__) \
        (void)base; \
        (void)exp; \
        ncalls = 0; \
        w_##name(EACHC(P_VNAME, __VA_ARGS__)); \
        verify(#name, NARGS(__VA_ARGS__), exp); \
    }

#define CHECK_FN_R(R, name, ...) \
    static void check_##name(void) \
    { \
        const uintptr_t base = (next_base += 16); \
        uint64_t exp[9] = { 0 }; \
        R want; \
        R got; \
        memcpy(&want, &ret_bits, sizeof want); \
        EACH(P_VAL, __VA_ARGS__) \
        EACH(P_EXP, __VA_ARGS__) \
        (void)base; \
        (void)exp; \
        ncalls = 0; \
        got = w_##name(EACHC(P_VNAME, __VA_ARGS__)); \
        verify(#name, NARGS(__VA_ARGS__), exp); \
        EXPECT(memcmp(&got, &want, sizeof got) == 0, #name ": the callee's return value was not passed back"); \
    }

/* The table. X: a function with its own name; L: a GL > 1.1 function the wrapper looks up by name (its fake is
 * f_<name>); R: a function that returns something. glClear (assembly fake), glIsEnabled, glfwInit,
 * glfwMakeContextCurrent and the four callback setters are hand-written below. */
#define ROWS_VOID(X, L) \
    L(glActiveTexture, GLenum) \
    X(glAlphaFunc, GLenum, GLclampf) \
    X(glBegin, GLenum) \
    L(glBindBuffer, GLenum, GLuint) \
    X(glBindTexture, GLenum, GLuint) \
    X(glBlendFunc, GLenum, GLenum) \
    L(glBufferData, GLenum, GLsizeiptr, const void *, GLenum) \
    X(glClearColor, GLclampf, GLclampf, GLclampf, GLclampf) \
    L(glClientActiveTexture, GLenum) \
    X(glColor3f, GLfloat, GLfloat, GLfloat) \
    X(glColor4f, GLfloat, GLfloat, GLfloat, GLfloat) \
    X(glColor4ub, GLubyte, GLubyte, GLubyte, GLubyte) \
    X(glColorPointer, GLint, GLenum, GLsizei, const void *) \
    X(glDepthMask, GLboolean) \
    X(glDisable, GLenum) \
    X(glDisableClientState, GLenum) \
    X(glDrawArrays, GLenum, GLint, GLsizei) \
    X(glEnable, GLenum) \
    X(glEnableClientState, GLenum) \
    X(glEnd) \
    X(glFogf, GLenum, GLfloat) \
    X(glFogfv, GLenum, const GLfloat *) \
    X(glFogi, GLenum, GLint) \
    X(glFrustum, GLdouble, GLdouble, GLdouble, GLdouble, GLdouble, GLdouble) \
    L(glGenBuffers, GLsizei, GLuint *) \
    X(glGenTextures, GLsizei, GLuint *) \
    X(glGetFloatv, GLenum, GLfloat *) \
    X(glLineWidth, GLfloat) \
    X(glLoadIdentity) \
    X(glMatrixMode, GLenum) \
    L(glMultiTexCoord2f, GLenum, GLfloat, GLfloat) \
    X(glOrtho, GLdouble, GLdouble, GLdouble, GLdouble, GLdouble, GLdouble) \
    X(glPixelStorei, GLenum, GLint) \
    X(glPopMatrix) \
    X(glPushMatrix) \
    X(glRotatef, GLfloat, GLfloat, GLfloat, GLfloat) \
    X(glScalef, GLfloat, GLfloat, GLfloat) \
    X(glScissor, GLint, GLint, GLsizei, GLsizei) \
    X(glTexCoord2i, GLint, GLint) \
    X(glTexCoordPointer, GLint, GLenum, GLsizei, const void *) \
    X(glTexEnvi, GLenum, GLenum, GLint) \
    X(glTexImage2D, GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *) \
    X(glTexParameteri, GLenum, GLenum, GLint) \
    X(glTranslatef, GLfloat, GLfloat, GLfloat) \
    X(glVertex2f, GLfloat, GLfloat) \
    X(glVertex2i, GLint, GLint) \
    X(glVertex3f, GLfloat, GLfloat, GLfloat) \
    X(glVertexPointer, GLint, GLenum, GLsizei, const void *) \
    X(glViewport, GLint, GLint, GLsizei, GLsizei) \
    X(glfwDestroyWindow, GLFWwindow *) \
    X(glfwGetCursorPos, GLFWwindow *, double *, double *) \
    X(glfwGetFramebufferSize, GLFWwindow *, int *, int *) \
    X(glfwGetWindowPos, GLFWwindow *, int *, int *) \
    X(glfwGetWindowSize, GLFWwindow *, int *, int *) \
    X(glfwPollEvents) \
    X(glfwSetInputMode, GLFWwindow *, int, int) \
    X(glfwSetWindowMonitor, GLFWwindow *, GLFWmonitor *, int, int, int, int, int) \
    X(glfwSetWindowShouldClose, GLFWwindow *, int) \
    X(glfwSetWindowTitle, GLFWwindow *, const char *) \
    X(glfwSwapBuffers, GLFWwindow *) \
    X(glfwSwapInterval, int) \
    X(glfwTerminate) \
    X(glfwWindowHint, int, int) \
    X(glfwWindowHintString, int, const char *)

#define ROWS_RET(X) \
    X(GLFWwindow *, glfwCreateWindow, int, int, const char *, GLFWmonitor *, GLFWwindow *) \
    X(int, glfwGetKey, GLFWwindow *, int) \
    X(const char *, glfwGetKeyName, int, int) \
    X(int, glfwGetMouseButton, GLFWwindow *, int) \
    X(GLFWmonitor *, glfwGetPrimaryMonitor) \
    X(double, glfwGetTime) \
    X(const GLFWvidmode *, glfwGetVideoMode, GLFWmonitor *) \
    X(int, glfwGetWindowAttrib, GLFWwindow *, int) \
    X(int, glfwRawMouseMotionSupported) \
    X(int, glfwWindowShouldClose, GLFWwindow *)

#define FAKE_X(name, ...) FAKE(name, #name, __VA_ARGS__)
#define FAKE_L(name, ...) FAKE(f_##name, #name, __VA_ARGS__)
#define FAKE_RET(R, name, ...) FAKE_R(R, name, #name, __VA_ARGS__)
#define CHECK_X(name, ...) CHECK_FN(name, __VA_ARGS__)
#define CHECK_RET(R, name, ...) CHECK_FN_R(R, name, __VA_ARGS__)
#define LIST_X(name, ...) { #name, check_##name },
#define LIST_RET(R, name, ...) { #name, check_##name },

ROWS_VOID(FAKE_X, FAKE_L)
ROWS_RET(FAKE_RET)
ROWS_VOID(CHECK_X, CHECK_X)
ROWS_RET(CHECK_RET)

static const struct {
    const char *name;
    void (*run)(void);
} generic_checks[] = {
    ROWS_VOID(LIST_X, LIST_X)
    ROWS_RET(LIST_RET)
};

/* ---- fakes with behaviour of their own --------------------------------------------------------- */

static GLFWwindow *cur_ctx;                         /* glfwGetCurrentContext */
static GLFWerrorfun error_fn;                       /* registered with glfwSetErrorCallback */
static GLFWkeyfun fk_key;                           /* what GLFW holds for each callback kind */
static GLFWcharfun fk_char;
static GLFWmousebuttonfun fk_mouse;
static GLFWscrollfun fk_scroll;
static int fake_init_result = 1;
static unsigned char fake_enabled;

typedef struct {
    const char *name;
    GLFWglproc fn;
} GpaEntry;

static GpaEntry gpa_tab[] = {
    { "glActiveTexture", (GLFWglproc)f_glActiveTexture },
    { "glClientActiveTexture", (GLFWglproc)f_glClientActiveTexture },
    { "glMultiTexCoord2f", (GLFWglproc)f_glMultiTexCoord2f },
    { "glBindBuffer", (GLFWglproc)f_glBindBuffer },
    { "glBufferData", (GLFWglproc)f_glBufferData },
    { "glGenBuffers", (GLFWglproc)f_glGenBuffers },
    { "glActiveTextureARB", NULL },
    { "glClientActiveTextureARB", NULL },
    { "glMultiTexCoord2fARB", NULL },
    { "glBindBufferARB", NULL },
    { "glBufferDataARB", NULL },
    { "glGenBuffersARB", NULL },
};
#define N_GPA ((int)(sizeof gpa_tab / sizeof gpa_tab[0]))
static const char *gpa_log[64];                     /* the names glfwGetProcAddress was asked for, in order */
static int n_gpa_log;

static void gpa_set(const char *name, GLFWglproc fn)
{
    int i;

    for (i = 0; i < N_GPA; i++) {
        if (strcmp(gpa_tab[i].name, name) == 0) {
            gpa_tab[i].fn = fn;
            return;
        }
    }
    n_fail++;
    printf("FAIL: gpa_set: no entry %s\n", name);
}

static int gpa_count(const char *name)
{
    int i, n = 0;

    for (i = 0; i < n_gpa_log; i++)
        n += strcmp(gpa_log[i], name) == 0;
    return n;
}

GLFWglproc glfwGetProcAddress(const char *name)
{
    int i;

    if (n_gpa_log < 64)
        gpa_log[n_gpa_log++] = name;
    for (i = 0; i < N_GPA; i++)
        if (strcmp(gpa_tab[i].name, name) == 0)
            return gpa_tab[i].fn;
    return NULL;
}

GLFWwindow *glfwGetCurrentContext(void)
{
    return cur_ctx;
}

GLFWerrorfun glfwSetErrorCallback(GLFWerrorfun cb)
{
    GLFWerrorfun previous = error_fn;

    error_fn = cb;
    return previous;
}

int glfwInit(void)
{
    rec_begin("glfwInit", 0);
    return fake_init_result;
}

void glfwMakeContextCurrent(GLFWwindow *window)
{
    Call *cur = rec_begin("glfwMakeContextCurrent", 1);

    memcpy(&cur->arg[0], &window, sizeof window);
    cur_ctx = window;
}

GLboolean glIsEnabled(GLenum cap)
{
    Call *cur = rec_begin("glIsEnabled", 1);

    memcpy(&cur->arg[0], &cap, sizeof cap);
    return fake_enabled;
}

#define FAKE_SETTER(id, Fn, slot, str) \
    Fn id(GLFWwindow *window, Fn cb) \
    { \
        Fn previous = slot; \
        Call *cur = rec_begin(str, 2); \
        memcpy(&cur->arg[0], &window, sizeof window); \
        memcpy(&cur->arg[1], &cb, sizeof cb); \
        slot = cb; \
        return previous; \
    }
FAKE_SETTER(glfwSetKeyCallback, GLFWkeyfun, fk_key, "glfwSetKeyCallback")
FAKE_SETTER(glfwSetCharCallback, GLFWcharfun, fk_char, "glfwSetCharCallback")
FAKE_SETTER(glfwSetMouseButtonCallback, GLFWmousebuttonfun, fk_mouse, "glfwSetMouseButtonCallback")
FAKE_SETTER(glfwSetScrollCallback, GLFWscrollfun, fk_scroll, "glfwSetScrollCallback")

/* ---- assembly: the game's way of calling, and a Win64 caller like GLFW ------------------------- */

const uint64_t sv_magic[5] = {                      /* rbx r12 r13 r14 r15 while the wrappers run */
    0x1111111111111111u, 0x2222222222222222u, 0x3333333333333333u, 0x4444444444444444u, 0x5555555555555555u
};
const uint64_t ms_magic[7] = {                      /* rsi rdi rbx r12 r13 r14 r15 around a trampoline call */
    0x5151515151515151u, 0x7171717171717171u, 0x6161616161616161u, 0x1212121212121212u, 0x1313131313131313u,
    0x1414141414141414u, 0x1515151515151515u
};
const uint64_t xm_magic[20] = {                     /* xmm6..xmm15, 16 bytes each */
    0x0606060606060606u, 0x6060606060606060u, 0x0707070707070707u, 0x7070707070707070u, 0x0808080808080808u,
    0x8080808080808080u, 0x0909090909090909u, 0x9090909090909090u, 0x0a0a0a0a0a0a0a0au, 0xa0a0a0a0a0a0a0a0u,
    0x0b0b0b0b0b0b0b0bu, 0xb0b0b0b0b0b0b0b0u, 0x0c0c0c0c0c0c0c0cu, 0xc0c0c0c0c0c0c0c0u, 0x0d0d0d0d0d0d0d0du,
    0xd0d0d0d0d0d0d0d0u, 0x0e0e0e0e0e0e0e0eu, 0xe0e0e0e0e0e0e0e0u, 0x0f0f0f0f0f0f0f0fu, 0xf0f0f0f0f0f0f0f0u
};
const double dk[12] = { -1.0 / 3.0, 2.0 / 3.0, -0.2, 0.2, 0.1, 1000.7, 0.0, 1280.0, 720.0, 0.0, -1.0, 1.0 };
const double scroll_xy[2] = { 1.0 / 3.0, 2.0 / 7.0 };
const float fk[16] = { 0.25f, 0.75f, 10.5f, 1.5f, 2.5f, 3.5f, 4.5f, 5.5f, 6.5f, 7.5f, 8.5f, 9.5f };
GLFWwindow *const win_sentinel = (GLFWwindow *)(uintptr_t)0x7A11D0;
unsigned char probe_pixels[16];
uint64_t snap[32][6];                               /* rbx r12-r15 rsp after each call of asm_game_calls */
uint64_t snap_rsp0;
unsigned clear_arg;
int clear_calls;
const uint64_t canary[4] = { 0xC0DEC0DE00000001u, 0xC0DEC0DE00000002u, 0xC0DEC0DE00000003u, 0xC0DEC0DE00000004u };
uint64_t canary_out[4];
uint64_t gcb[5];                                    /* rdi rsi rdx rcx r8 as the game callback saw them */
double gcb_d[2];                                    /* xmm0 xmm1 */
int gcb_calls;

#define ASM_SNAP_MACRO \
    ".macro SNAP k\n" \
    "    mov QWORD PTR [rip+snap+\\k*48+0], rbx\n" \
    "    mov QWORD PTR [rip+snap+\\k*48+8], r12\n" \
    "    mov QWORD PTR [rip+snap+\\k*48+16], r13\n" \
    "    mov QWORD PTR [rip+snap+\\k*48+24], r14\n" \
    "    mov QWORD PTR [rip+snap+\\k*48+32], r15\n" \
    "    mov QWORD PTR [rip+snap+\\k*48+40], rsp\n" \
    ".endm\n"

#define ASM_CMP_MACRO \
    ".macro CMPREG reg, idx, bit\n" \
    "    cmp \\reg, QWORD PTR [rip+ms_magic+\\idx*8]\n" \
    "    je 1f\n" \
    "    or eax, \\bit\n" \
    "1:\n" \
    ".endm\n"

__asm__(
    ".intel_syntax noprefix\n"
    ASM_SNAP_MACRO
    ASM_CMP_MACRO
    ".text\n"
    ".p2align 4\n"

    /* a Win64 callee: records ecx, then scribbles its whole shadow space (allowed to) */
    ".globl glClear\n"
    "glClear:\n"
    "    mov DWORD PTR [rip+clear_arg], ecx\n"
    "    inc DWORD PTR [rip+clear_calls]\n"
    "    mov rax, -1\n"
    "    mov QWORD PTR [rsp+8], rax\n"
    "    mov QWORD PTR [rsp+16], rax\n"
    "    mov QWORD PTR [rsp+24], rax\n"
    "    mov QWORD PTR [rsp+32], rax\n"
    "    ret\n"

    /* a System V callee that breaks the callee-saved registers (negative control for SNAP) */
    ".p2align 4\n"
    "asm_clobber_regs:\n"
    "    mov rbx, -1\n"
    "    mov r12, -1\n"
    "    mov r13, -1\n"
    "    mov r14, -1\n"
    "    mov r15, -1\n"
    "    ret\n"

    /* SysV: void asm_shadow_check(int via_wrapper). Canaries sit where a Win64 callee reached by a tail jump
     * would put its shadow space. via_wrapper = 0 calls the fake directly: the control, it must break them */
    ".p2align 4\n"
    ".globl asm_shadow_check\n"
    "asm_shadow_check:\n"
    "    push rbp\n"
    "    mov rbp, rsp\n"
    "    sub rsp, 32\n"
    "    mov rax, QWORD PTR [rip+canary+0]\n"
    "    mov QWORD PTR [rsp+0], rax\n"
    "    mov rax, QWORD PTR [rip+canary+8]\n"
    "    mov QWORD PTR [rsp+8], rax\n"
    "    mov rax, QWORD PTR [rip+canary+16]\n"
    "    mov QWORD PTR [rsp+16], rax\n"
    "    mov rax, QWORD PTR [rip+canary+24]\n"
    "    mov QWORD PTR [rsp+24], rax\n"
    "    test edi, edi\n"
    "    mov edi, 0x4100\n"
    "    mov ecx, 0x4100\n"
    "    jz 1f\n"
    "    call w_glClear\n"
    "    jmp 2f\n"
    "1:  call glClear\n"
    "2:  mov rax, QWORD PTR [rsp+0]\n"
    "    mov QWORD PTR [rip+canary_out+0], rax\n"
    "    mov rax, QWORD PTR [rsp+8]\n"
    "    mov QWORD PTR [rip+canary_out+8], rax\n"
    "    mov rax, QWORD PTR [rsp+16]\n"
    "    mov QWORD PTR [rip+canary_out+16], rax\n"
    "    mov rax, QWORD PTR [rsp+24]\n"
    "    mov QWORD PTR [rip+canary_out+24], rax\n"
    "    mov rsp, rbp\n"
    "    pop rbp\n"
    "    ret\n"

    /* SysV: void asm_game_calls(void): 17 calls as the game's code makes them, then the control */
    ".p2align 4\n"
    ".globl asm_game_calls\n"
    "asm_game_calls:\n"
    "    push rbp\n"
    "    mov rbp, rsp\n"
    "    push rbx\n"
    "    push r12\n"
    "    push r13\n"
    "    push r14\n"
    "    push r15\n"
    "    sub rsp, 88\n"
    "    mov rbx, QWORD PTR [rip+sv_magic+0]\n"
    "    mov r12, QWORD PTR [rip+sv_magic+8]\n"
    "    mov r13, QWORD PTR [rip+sv_magic+16]\n"
    "    mov r14, QWORD PTR [rip+sv_magic+24]\n"
    "    mov r15, QWORD PTR [rip+sv_magic+32]\n"
    "    mov QWORD PTR [rip+snap_rsp0], rsp\n"
    /* 0: glTexImage2D as render.asm's TEXIMAGE: format, type, pixels as qwords at [rsp], [rsp+8], [rsp+16] */
    "    mov QWORD PTR [rsp], 0x1908\n"
    "    mov QWORD PTR [rsp+8], 0x1401\n"
    "    lea rax, [rip+probe_pixels]\n"
    "    mov QWORD PTR [rsp+16], rax\n"
    "    mov edi, 0xDE1\n"
    "    xor esi, esi\n"
    "    mov edx, 0x1908\n"
    "    mov ecx, 256\n"
    "    mov r8d, 128\n"
    "    xor r9d, r9d\n"
    "    call w_glTexImage2D\n"
    "    SNAP 0\n"
    /* 1: glFrustum: six doubles in xmm0-5 */
    "    movsd xmm0, QWORD PTR [rip+dk+0]\n"
    "    movsd xmm1, QWORD PTR [rip+dk+8]\n"
    "    movsd xmm2, QWORD PTR [rip+dk+16]\n"
    "    movsd xmm3, QWORD PTR [rip+dk+24]\n"
    "    movsd xmm4, QWORD PTR [rip+dk+32]\n"
    "    movsd xmm5, QWORD PTR [rip+dk+40]\n"
    "    call w_glFrustum\n"
    "    SNAP 1\n"
    /* 2: glOrtho(0, w, h, 0, -1, 1) as ui.asm */
    "    xorpd xmm0, xmm0\n"
    "    movsd xmm1, QWORD PTR [rip+dk+56]\n"
    "    movsd xmm2, QWORD PTR [rip+dk+64]\n"
    "    xorpd xmm3, xmm3\n"
    "    movsd xmm4, QWORD PTR [rip+dk+80]\n"
    "    movsd xmm5, QWORD PTR [rip+dk+88]\n"
    "    call w_glOrtho\n"
    "    SNAP 2\n"
    /* 3: glBufferData with a size above 4 GiB in rsi (shl rsi, 4) */
    "    mov edi, 0x8892\n"
    "    mov esi, 0x10000000\n"
    "    shl rsi, 4\n"
    "    lea rdx, [rip+probe_pixels]\n"
    "    mov ecx, 0x88E4\n"
    "    call w_glBufferData\n"
    "    SNAP 3\n"
    /* 4: glColor4ub as ui.asm's set_color */
    "    mov edi, 0x11\n"
    "    mov esi, 0x22\n"
    "    mov edx, 0x33\n"
    "    mov ecx, 0xFF\n"
    "    call w_glColor4ub\n"
    "    SNAP 4\n"
    /* 5: glMultiTexCoord2f: an int and two floats */
    "    mov edi, 0x84C1\n"
    "    movss xmm0, DWORD PTR [rip+fk+0]\n"
    "    movss xmm1, DWORD PTR [rip+fk+4]\n"
    "    call w_glMultiTexCoord2f\n"
    "    SNAP 5\n"
    /* 6: glRotatef */
    "    movss xmm0, DWORD PTR [rip+fk+8]\n"
    "    movss xmm1, DWORD PTR [rip+fk+12]\n"
    "    movss xmm2, DWORD PTR [rip+fk+16]\n"
    "    movss xmm3, DWORD PTR [rip+fk+20]\n"
    "    call w_glRotatef\n"
    "    SNAP 6\n"
    /* 7: glfwSetWindowMonitor as settings.asm leaves a window: the 7th argument is a qword at [rsp] */
    "    mov QWORD PTR [rsp], -1\n"
    "    mov rdi, QWORD PTR [rip+win_sentinel]\n"
    "    xor esi, esi\n"
    "    mov edx, 100\n"
    "    mov ecx, 200\n"
    "    mov r8d, 1280\n"
    "    mov r9d, 720\n"
    "    call w_glfwSetWindowMonitor\n"
    "    SNAP 7\n"
    /* 8, 9: array pointers are buffer offsets */
    "    mov edi, 3\n"
    "    mov esi, 0x1402\n"
    "    mov edx, 16\n"
    "    xor ecx, ecx\n"
    "    call w_glVertexPointer\n"
    "    SNAP 8\n"
    "    mov edi, 4\n"
    "    mov esi, 0x1401\n"
    "    mov edx, 16\n"
    "    mov ecx, 12\n"
    "    call w_glColorPointer\n"
    "    SNAP 9\n"
    /* 10: glDrawArrays(GL_QUADS, first, count) */
    "    mov edi, 7\n"
    "    mov esi, 12\n"
    "    mov edx, 34\n"
    "    call w_glDrawArrays\n"
    "    SNAP 10\n"
    /* 11: glAlphaFunc(func, ref) */
    "    mov edi, 0x204\n"
    "    movss xmm0, DWORD PTR [rip+fk+24]\n"
    "    call w_glAlphaFunc\n"
    "    SNAP 11\n"
    /* 12: glFogfv(pname, pointer) */
    "    mov edi, 0xB66\n"
    "    lea rsi, [rip+probe_pixels]\n"
    "    call w_glFogfv\n"
    "    SNAP 12\n"
    /* 13: glClearColor */
    "    movss xmm0, DWORD PTR [rip+fk+28]\n"
    "    movss xmm1, DWORD PTR [rip+fk+32]\n"
    "    movss xmm2, DWORD PTR [rip+fk+36]\n"
    "    movss xmm3, DWORD PTR [rip+fk+40]\n"
    "    call w_glClearColor\n"
    "    SNAP 13\n"
    /* 14: glfwSetWindowTitle(window, text) */
    "    mov rdi, QWORD PTR [rip+win_sentinel]\n"
    "    lea rsi, [rip+probe_pixels]\n"
    "    call w_glfwSetWindowTitle\n"
    "    SNAP 14\n"
    /* 15: glfwGetFramebufferSize(window, int *, int *) */
    "    mov rdi, QWORD PTR [rip+win_sentinel]\n"
    "    lea rsi, [rip+probe_pixels+4]\n"
    "    lea rdx, [rip+probe_pixels+8]\n"
    "    call w_glfwGetFramebufferSize\n"
    "    SNAP 15\n"
    /* 16: glfwGetTime: a double comes back in xmm0 */
    "    call w_glfwGetTime\n"
    "    movsd QWORD PTR [rip+gcb_d], xmm0\n"
    "    SNAP 16\n"
    /* control: a callee that clobbers rbx and r12-r15 must show in the snapshot */
    "    call asm_clobber_regs\n"
    "    SNAP 31\n"
    "    add rsp, 88\n"
    "    pop r15\n"
    "    pop r14\n"
    "    pop r13\n"
    "    pop r12\n"
    "    pop rbx\n"
    "    pop rbp\n"
    "    ret\n"

    /* SysV: void asm_tail_jump(void): app.asm's app_request_quit, which ends in `jmp glfwSetWindowShouldClose` */
    ".p2align 4\n"
    ".globl asm_tail_jump\n"
    "asm_tail_jump:\n"
    "    mov rdi, QWORD PTR [rip+win_sentinel]\n"
    "    mov esi, 1\n"
    "    jmp w_glfwSetWindowShouldClose\n"

    /* SysV game callbacks: record every argument register, then destroy everything a System V callee may */
    ".macro GAMECB name\n"
    ".p2align 4\n"
    ".globl \\name\n"
    "\\name:\n"
    "    mov QWORD PTR [rip+gcb+0], rdi\n"
    "    mov QWORD PTR [rip+gcb+8], rsi\n"
    "    mov QWORD PTR [rip+gcb+16], rdx\n"
    "    mov QWORD PTR [rip+gcb+24], rcx\n"
    "    mov QWORD PTR [rip+gcb+32], r8\n"
    "    movsd QWORD PTR [rip+gcb_d+0], xmm0\n"
    "    movsd QWORD PTR [rip+gcb_d+8], xmm1\n"
    "    inc DWORD PTR [rip+gcb_calls]\n"
    "    mov rsi, -1\n"
    "    mov rdi, -1\n"
    ".irp k,6,7,8,9,10,11,12,13,14,15\n"
    "    pcmpeqd xmm\\k, xmm\\k\n"
    ".endr\n"
    "    ret\n"
    ".endm\n"
    "GAMECB game_cb_a\n"
    "GAMECB game_cb_b\n"

    /* Win64: int asm_ms_dispatch(void *callback). GLFW's side: window in rcx, then 11, 22, 33 in edx, r8d,
     * r9d, 44 on the stack, 1.5 and 2.5 in xmm1, xmm2 (whichever the callback kind reads). rsi, rdi, rbx,
     * r12-r15 and xmm6-15 hold magic values; returns a mask of the ones that changed (0 = all intact) */
    ".p2align 4\n"
    ".globl asm_ms_dispatch\n"
    "asm_ms_dispatch:\n"
    "    push rbp\n"
    "    mov rbp, rsp\n"
    "    push rsi\n"
    "    push rdi\n"
    "    push rbx\n"
    "    push r12\n"
    "    push r13\n"
    "    push r14\n"
    "    push r15\n"
    "    sub rsp, 0xD8\n"
    ".irp k,6,7,8,9,10,11,12,13,14,15\n"
    "    movups XMMWORD PTR [rsp+0x30+16*(\\k-6)], xmm\\k\n"
    "    movups xmm\\k, XMMWORD PTR [rip+xm_magic+16*(\\k-6)]\n"
    ".endr\n"
    "    mov rsi, QWORD PTR [rip+ms_magic+0]\n"
    "    mov rdi, QWORD PTR [rip+ms_magic+8]\n"
    "    mov rbx, QWORD PTR [rip+ms_magic+16]\n"
    "    mov r12, QWORD PTR [rip+ms_magic+24]\n"
    "    mov r13, QWORD PTR [rip+ms_magic+32]\n"
    "    mov r14, QWORD PTR [rip+ms_magic+40]\n"
    "    mov r15, QWORD PTR [rip+ms_magic+48]\n"
    "    mov rax, rcx\n"
    "    mov rcx, QWORD PTR [rip+win_sentinel]\n"
    "    mov edx, 11\n"
    "    mov r8d, 22\n"
    "    mov r9d, 33\n"
    "    mov DWORD PTR [rsp+0x20], 44\n"
    "    movsd xmm1, QWORD PTR [rip+scroll_xy+0]\n"
    "    movsd xmm2, QWORD PTR [rip+scroll_xy+8]\n"
    "    call rax\n"
    "    xor eax, eax\n"
    "    CMPREG rsi, 0, 1\n"
    "    CMPREG rdi, 1, 2\n"
    "    CMPREG rbx, 2, 4\n"
    "    CMPREG r12, 3, 8\n"
    "    CMPREG r13, 4, 16\n"
    "    CMPREG r14, 5, 32\n"
    "    CMPREG r15, 6, 64\n"
    ".irp k,6,7,8,9,10,11,12,13,14,15\n"
    "    movups xmm0, XMMWORD PTR [rip+xm_magic+16*(\\k-6)]\n"
    "    pcmpeqb xmm0, xmm\\k\n"
    "    pmovmskb ecx, xmm0\n"
    "    cmp ecx, 0xFFFF\n"
    "    je 1f\n"
    "    or eax, 0x100\n"
    "1:\n"
    "    movups xmm\\k, XMMWORD PTR [rsp+0x30+16*(\\k-6)]\n"
    ".endr\n"
    "    add rsp, 0xD8\n"
    "    pop r15\n"
    "    pop r14\n"
    "    pop r13\n"
    "    pop r12\n"
    "    pop rbx\n"
    "    pop rdi\n"
    "    pop rsi\n"
    "    pop rbp\n"
    "    ret\n"
    ".att_syntax prefix\n"
);

SYSV void asm_shadow_check(int via_wrapper);
SYSV void asm_game_calls(void);
SYSV void asm_tail_jump(void);
extern void game_cb_a(void);
extern void game_cb_b(void);
int asm_ms_dispatch(void *callback);                /* Win64 */

/* ---- the tests -------------------------------------------------------------------------------- */

static GLFWwindow *const win_a = (GLFWwindow *)(uintptr_t)0xA0A0A0;
static GLFWwindow *const win_b = (GLFWwindow *)(uintptr_t)0xB0B0B0;

/* a fresh world for each group: a current context, all six functions resolvable by their core names */
static void reset_env(void)
{
    int i;

    ncalls = 0;
    err_len = 0;
    err_buf[0] = 0;
    n_gpa_log = 0;
    cur_ctx = win_a;
    gpa_set("glActiveTexture", (GLFWglproc)f_glActiveTexture);
    gpa_set("glClientActiveTexture", (GLFWglproc)f_glClientActiveTexture);
    gpa_set("glMultiTexCoord2f", (GLFWglproc)f_glMultiTexCoord2f);
    gpa_set("glBindBuffer", (GLFWglproc)f_glBindBuffer);
    gpa_set("glBufferData", (GLFWglproc)f_glBufferData);
    gpa_set("glGenBuffers", (GLFWglproc)f_glGenBuffers);
    for (i = 6; i < N_GPA; i++)
        gpa_tab[i].fn = NULL;
    lazy_reset();
    for (i = 0; i < LZ_COUNT; i++)
        lazy[i].reported = 0;
}

static void test_generic(void)
{
    size_t i;

    reset_env();
    for (i = 0; i < sizeof generic_checks / sizeof generic_checks[0]; i++)
        generic_checks[i].run();
    EXPECT(sizeof generic_checks / sizeof generic_checks[0] == 74, "%u generic rows, expected 74",
           (unsigned)(sizeof generic_checks / sizeof generic_checks[0]));
    EXPECT(err_len == 0, "a wrapper wrote to stderr: %s", err_buf);
}

static void test_is_enabled(void)
{
    unsigned r;

    reset_env();
    mark("glIsEnabled");
    fake_enabled = 0;
    r = w_glIsEnabled(0xDE1);
    EXPECT(r == 0, "glIsEnabled(false) = %u", r);
    EXPECT(ncalls == 1 && calls[0].arg[0] == 0xDE1, "glIsEnabled: the capability was not forwarded");
    fake_enabled = 0xFF;                            /* any non-zero GLboolean: a whole 1 in eax */
    r = w_glIsEnabled(0xDE1);
    EXPECT(r == 1, "glIsEnabled(true) = %u, expected 1", r);
}

static void test_init_and_context(void)
{
    int r;

    reset_env();
    mark("glfwInit");
    mark("glfwMakeContextCurrent");
    fake_init_result = 1;
    r = w_glfwInit();
    EXPECT(r == 1, "glfwInit returned %d", r);
    EXPECT(error_fn != NULL, "glfwInit did not register the error callback first");
    fake_init_result = 0;
    r = w_glfwInit();
    EXPECT(r == 0, "glfwInit failure was not passed back (%d)", r);
    fake_init_result = 1;

    ncalls = 0;
    w_glfwMakeContextCurrent(win_b);
    EXPECT(ncalls == 1 && strcmp(calls[0].name, "glfwMakeContextCurrent") == 0 &&
           calls[0].arg[0] == (uint64_t)(uintptr_t)win_b, "glfwMakeContextCurrent was not forwarded");
    EXPECT(cur_ctx == win_b, "the context did not change");
}

static void test_glfw_error_log(void)
{
    int i;

    reset_env();
    w_glfwInit();
    EXPECT(error_fn != NULL, "no error callback");
    if (error_fn == NULL)
        return;
    error_fn(0x00010008, "WGL: Failed to make context current");
    EXPECT(strcmp(err_buf, "glfw: error 0x00010008: WGL: Failed to make context current\n") == 0,
           "error line is [%s]", err_buf);
    err_len = 0;
    err_buf[0] = 0;
    for (i = 0; i < 100; i++)
        error_fn(0x00010003, "Invalid key");        /* a benign error repeated every frame: capped */
    EXPECT(err_lines() == 4, "%d lines for one repeated error, expected 4", err_lines());
    error_fn(0x00010007, "a different error");      /* ... without hiding a different one */
    EXPECT(err_lines() == 5, "a different error code was suppressed (%d lines)", err_lines());
    error_fn(0x00010001, NULL);                     /* a NULL description is legal */
    EXPECT(err_lines() == 6, "an error without description was lost");
}

static void test_lazy(void)
{
    ncalls = 0;
    reset_env();

    /* no current context: nothing is resolved (glfwGetProcAddress would raise an error), nothing forwarded */
    cur_ctx = NULL;
    w_glActiveTexture(0x84C1);
    EXPECT(ncalls == 0 && n_gpa_log == 0, "without a context: %d calls, %d lookups", ncalls, n_gpa_log);
    EXPECT(err_len == 0, "without a context a line was written: %s", err_buf);

    /* with one it resolves once and is cached */
    cur_ctx = win_a;
    w_glActiveTexture(0x84C2);
    w_glActiveTexture(0x84C3);
    EXPECT(ncalls == 2 && strcmp(calls[0].name, "glActiveTexture") == 0 && calls[0].arg[0] == 0x84C2 &&
           calls[1].arg[0] == 0x84C3, "glActiveTexture was not forwarded (%d calls)", ncalls);
    EXPECT(gpa_count("glActiveTexture") == 1, "looked up %d times, expected once", gpa_count("glActiveTexture"));
    EXPECT(gpa_count("glActiveTextureARB") == 0, "the ARB name was tried although the core name resolved");

    /* a context change throws the pointers away: MakeContextCurrent, DestroyWindow and Terminate */
    w_glfwMakeContextCurrent(win_b);
    w_glActiveTexture(1);
    EXPECT(gpa_count("glActiveTexture") == 2, "no new lookup after glfwMakeContextCurrent");
    w_glfwDestroyWindow(win_b);
    w_glActiveTexture(2);
    EXPECT(gpa_count("glActiveTexture") == 3, "no new lookup after glfwDestroyWindow");
    w_glfwTerminate();
    w_glActiveTexture(3);
    EXPECT(gpa_count("glActiveTexture") == 4, "no new lookup after glfwTerminate");

    /* the ARB spelling for a driver that only has the extension */
    reset_env();
    gpa_set("glBindBuffer", NULL);
    gpa_set("glBindBufferARB", (GLFWglproc)f_glBindBuffer);
    ncalls = 0;
    w_glBindBuffer(0x8892, 5);
    EXPECT(ncalls == 1 && calls[0].arg[0] == 0x8892 && calls[0].arg[1] == 5, "the ARB entry point was not used");
    EXPECT(gpa_count("glBindBuffer") == 1 && gpa_count("glBindBufferARB") == 1,
           "lookups: core %d, ARB %d", gpa_count("glBindBuffer"), gpa_count("glBindBufferARB"));
    EXPECT(err_len == 0, "a line was written although the ARB name resolved");

    /* an absent function: ignored, one line naming it, however often it is called or the context changes */
    reset_env();
    gpa_set("glMultiTexCoord2f", NULL);
    ncalls = 0;
    w_glMultiTexCoord2f(0x84C1, 1.0f, 2.0f);
    w_glMultiTexCoord2f(0x84C1, 3.0f, 4.0f);
    EXPECT(ncalls == 0, "an absent function was forwarded (%d)", ncalls);
    EXPECT(err_lines() == 1 && strstr(err_buf, "glMultiTexCoord2f") != NULL && strstr(err_buf, "1.3") != NULL,
           "message: [%s]", err_buf);
    EXPECT(strncmp(err_buf, "gfx: ", 5) == 0, "message does not start with gfx: [%s]", err_buf);
    EXPECT(gpa_count("glMultiTexCoord2f") == 1 && gpa_count("glMultiTexCoord2fARB") == 1,
           "an absent function was looked up again on every call");
    w_glfwMakeContextCurrent(win_b);
    w_glMultiTexCoord2f(0x84C1, 5.0f, 6.0f);
    EXPECT(ncalls == 1 && err_lines() == 1, "after a context change the line came again or the call went through");

    /* a driver's "not supported" answers (1, 2, 3, -1) are not function pointers */
    {
        static const uintptr_t odd[4] = { 1, 2, 3, (uintptr_t)-1 };
        int i;

        for (i = 0; i < 4; i++) {
            reset_env();
            gpa_set("glClientActiveTexture", (GLFWglproc)odd[i]);
            ncalls = 0;
            w_glClientActiveTexture(0x84C0);
            EXPECT(ncalls == 0, "the driver answer %lld was called", (long long)odd[i]);
            EXPECT(strstr(err_buf, "glClientActiveTexture") != NULL, "no message for the driver answer %lld",
                   (long long)odd[i]);
        }
    }

    /* an ordinary high address is fine */
    reset_env();
    ncalls = 0;
    w_glClientActiveTexture(0x84C1);
    EXPECT(ncalls == 1, "a normal pointer was not used");
}

static void test_no_buffers(void)
{
    GLuint names[6];
    int i;

    reset_env();
    gpa_set("glGenBuffers", NULL);
    for (i = 0; i < 6; i++)
        names[i] = 0xAAAAAAAAu;
    ncalls = 0;
    w_glGenBuffers(5, names);                       /* absent: names 0, and only the 5 asked for */
    EXPECT(names[0] == 0 && names[4] == 0 && names[5] == 0xAAAAAAAAu, "glGenBuffers without the function wrote "
           "%x %x ... %x", names[0], names[4], names[5]);
    EXPECT(ncalls == 0, "glGenBuffers was forwarded although absent");
    w_glGenBuffers(0, NULL);                        /* no crash on nothing to do */
    w_glGenBuffers(-1, names);
    EXPECT(strstr(err_buf, "glGenBuffers") != NULL, "no message naming glGenBuffers: [%s]", err_buf);

    err_len = 0;
    err_buf[0] = 0;
    ncalls = 0;
    w_glBindBuffer(0x8892, 1);                      /* the others are fine but buffers as a whole are not */
    w_glBufferData(0x8892, 64, probe_pixels, 0x88E4);
    EXPECT(ncalls == 2, "glBindBuffer / glBufferData were not forwarded (%d)", ncalls);
    ncalls = 0;
    w_glDrawArrays(7, 0, 4);
    w_glDrawArrays(7, 4, 4);
    EXPECT(ncalls == 0, "glDrawArrays was forwarded without buffer objects (%d)", ncalls);
    EXPECT(err_lines() == 1 && strstr(err_buf, "glDrawArrays") != NULL, "glDrawArrays note: [%s]", err_buf);

    /* the other functions still work, and so does drawing once a context with buffers is current */
    ncalls = 0;
    w_glActiveTexture(0x84C1);
    EXPECT(ncalls == 1, "an unrelated lazy function stopped working");
    gpa_set("glGenBuffers", (GLFWglproc)f_glGenBuffers);
    w_glfwMakeContextCurrent(win_b);
    ncalls = 0;
    w_glDrawArrays(7, 0, 4);
    EXPECT(ncalls == 1 && strcmp(calls[0].name, "glDrawArrays") == 0, "glDrawArrays stayed off with buffers back");
    w_glGenBuffers(3, names);
    EXPECT(ncalls == 2 && strcmp(calls[1].name, "glGenBuffers") == 0, "glGenBuffers was not forwarded");

    /* no context at all: nothing can be told, drawing is left to GL (it ignores calls without a context) */
    reset_env();
    cur_ctx = NULL;
    ncalls = 0;
    w_glDrawArrays(7, 0, 4);
    EXPECT(ncalls == 1, "glDrawArrays without a context was swallowed");
}

static void test_callback_registration(void)
{
    reset_env();
    mark("glfwSetKeyCallback");
    mark("glfwSetCharCallback");
    mark("glfwSetMouseButtonCallback");
    mark("glfwSetScrollCallback");
    fk_key = NULL;
    fk_char = NULL;
    fk_mouse = NULL;
    fk_scroll = NULL;
    game_key = NULL;
    game_char = NULL;
    game_mouse_button = NULL;
    game_scroll = NULL;

#define REGISTER_TEST(Setter, GameFn, fake_slot, tramp, what) \
    do { \
        GameFn a = (GameFn)game_cb_a, b = (GameFn)game_cb_b; \
        EXPECT(Setter(win_a, a) == NULL, what ": the first previous callback is not NULL"); \
        EXPECT(fake_slot != NULL && (void *)fake_slot != (void *)a, what ": GLFW did not get a trampoline"); \
        EXPECT((void *)fake_slot == (void *)tramp, what ": GLFW got something else than the trampoline"); \
        EXPECT(Setter(win_a, b) == a, what ": the previous callback was not returned"); \
        EXPECT((void *)fake_slot == (void *)tramp, what ": the trampoline was replaced"); \
        EXPECT(Setter(win_a, NULL) == b, what ": the second previous callback was not returned"); \
        EXPECT(fake_slot == NULL, what ": unsetting did not unset GLFW's callback"); \
        EXPECT(Setter(win_a, a) == NULL, what ": the previous callback after unsetting is not NULL"); \
        Setter(win_a, NULL); \
    } while (0)
    REGISTER_TEST(w_glfwSetKeyCallback, GameKeyFn, fk_key, key_trampoline, "key");
    REGISTER_TEST(w_glfwSetCharCallback, GameCharFn, fk_char, char_trampoline, "char");
    REGISTER_TEST(w_glfwSetMouseButtonCallback, GameMouseButtonFn, fk_mouse, mouse_button_trampoline, "mouse");
    REGISTER_TEST(w_glfwSetScrollCallback, GameScrollFn, fk_scroll, scroll_trampoline, "scroll");
}

/* the registered trampoline, called as GLFW would, with the game's System V callback behind it */
static void dispatch_one(const char *what, void *trampoline, int expect_intact)
{
    int mask;

    memset(gcb, 0, sizeof gcb);
    memset(gcb_d, 0, sizeof gcb_d);
    gcb_calls = 0;
    mask = asm_ms_dispatch(trampoline);
    if (expect_intact)
        EXPECT(mask == 0, "%s: the Win64 caller lost registers across the trampoline (mask 0x%x)", what, mask);
    else
        EXPECT(mask == (1 | 2 | 0x100), "%s: control: a System V callee that destroys rsi, rdi, xmm6-15 went "
               "unnoticed by the check (mask 0x%x)", what, mask);
    EXPECT(gcb_calls == 1, "%s: the game callback ran %d times", what, gcb_calls);
}

static void test_callback_dispatch(void)
{
    uint64_t w = (uint64_t)(uintptr_t)win_sentinel;

    reset_env();
    w_glfwSetKeyCallback(win_a, (GameKeyFn)game_cb_a);
    w_glfwSetCharCallback(win_a, (GameCharFn)game_cb_a);
    w_glfwSetMouseButtonCallback(win_a, (GameMouseButtonFn)game_cb_a);
    w_glfwSetScrollCallback(win_a, (GameScrollFn)game_cb_a);

    dispatch_one("key", (void *)fk_key, 1);         /* (window, key, scancode, action, mods) */
    EXPECT(gcb[0] == w && (uint32_t)gcb[1] == 11 && (uint32_t)gcb[2] == 22 && (uint32_t)gcb[3] == 33 &&
           (uint32_t)gcb[4] == 44, "key callback got %llx %x %x %x %x", (unsigned long long)gcb[0],
           (uint32_t)gcb[1], (uint32_t)gcb[2], (uint32_t)gcb[3], (uint32_t)gcb[4]);

    dispatch_one("char", (void *)fk_char, 1);       /* (window, codepoint) */
    EXPECT(gcb[0] == w && (uint32_t)gcb[1] == 11, "char callback got %llx %x", (unsigned long long)gcb[0],
           (uint32_t)gcb[1]);

    dispatch_one("mouse", (void *)fk_mouse, 1);     /* (window, button, action, mods) */
    EXPECT(gcb[0] == w && (uint32_t)gcb[1] == 11 && (uint32_t)gcb[2] == 22 && (uint32_t)gcb[3] == 33,
           "mouse callback got %llx %x %x %x", (unsigned long long)gcb[0], (uint32_t)gcb[1], (uint32_t)gcb[2],
           (uint32_t)gcb[3]);

    dispatch_one("scroll", (void *)fk_scroll, 1);   /* (window, xoffset, yoffset): doubles in xmm0, xmm1 */
    EXPECT(gcb[0] == w && gcb_d[0] == scroll_xy[0] && gcb_d[1] == scroll_xy[1], "scroll callback got %llx %g %g",
           (unsigned long long)gcb[0], gcb_d[0], gcb_d[1]);

    /* control: the same caller straight into the System V callback sees rsi, rdi, xmm6-15 destroyed */
    dispatch_one("control", (void *)game_cb_a, 0);

    /* unset: the trampoline GLFW may still hold does nothing and does not crash */
    w_glfwSetKeyCallback(win_a, NULL);
    gcb_calls = 0;
    EXPECT(asm_ms_dispatch((void *)key_trampoline) == 0 && gcb_calls == 0, "an unset key callback still ran");
}

static uint64_t bits32(float f)
{
    uint64_t u = 0;

    memcpy(&u, &f, sizeof f);
    return u;
}

static uint64_t bits64(double d)
{
    uint64_t u;

    memcpy(&u, &d, sizeof d);
    return u;
}

static void test_asm_game_calls(void)
{
    typedef struct {
        const char *name;
        int argc;
        uint64_t arg[9];
    } Want;
    static Want want[17];
    unsigned char *px = probe_pixels;
    int i, n = 0;
    uint64_t sz = 0x100000000u;
    double d;

    reset_env();
    gcb_d[0] = gcb_d[1] = 0;
    memset(snap, 0, sizeof snap);
    ncalls = 0;

#define W_U32(v) ((uint64_t)(uint32_t)(v))
#define W_F32(f) bits32(f)
#define W_F64(f) bits64(f)
#define W_PTR(p) ((uint64_t)(uintptr_t)(p))
#define W(...) (want[n++] = (Want){ __VA_ARGS__ })
    W("glTexImage2D", 9, { 0xDE1, 0, 0x1908, 256, 128, 0, 0x1908, 0x1401, W_PTR(px) });
    W("glFrustum", 6, { W_F64(dk[0]), W_F64(dk[1]), W_F64(dk[2]), W_F64(dk[3]), W_F64(dk[4]), W_F64(dk[5]) });
    W("glOrtho", 6, { W_F64(0.0), W_F64(dk[7]), W_F64(dk[8]), W_F64(0.0), W_F64(dk[10]), W_F64(dk[11]) });
    W("glBufferData", 4, { 0x8892, sz, W_PTR(px), 0x88E4 });
    W("glColor4ub", 4, { 0x11, 0x22, 0x33, 0xFF });
    W("glMultiTexCoord2f", 3, { 0x84C1, W_F32(fk[0]), W_F32(fk[1]) });
    W("glRotatef", 4, { W_F32(fk[2]), W_F32(fk[3]), W_F32(fk[4]), W_F32(fk[5]) });
    W("glfwSetWindowMonitor", 7, { W_PTR(win_sentinel), 0, 100, 200, 1280, 720, W_U32(-1) });
    W("glVertexPointer", 4, { 3, 0x1402, 16, 0 });
    W("glColorPointer", 4, { 4, 0x1401, 16, 12 });
    W("glDrawArrays", 3, { 7, 12, 34 });
    W("glAlphaFunc", 2, { 0x204, W_F32(fk[6]) });
    W("glFogfv", 2, { 0xB66, W_PTR(px) });
    W("glClearColor", 4, { W_F32(fk[7]), W_F32(fk[8]), W_F32(fk[9]), W_F32(fk[10]) });
    W("glfwSetWindowTitle", 2, { W_PTR(win_sentinel), W_PTR(px) });
    W("glfwGetFramebufferSize", 3, { W_PTR(win_sentinel), W_PTR(px + 4), W_PTR(px + 8) });
    W("glfwGetTime", 0, { 0 });

    asm_game_calls();
    EXPECT(ncalls == n, "the assembly caller made %d forwarded calls, expected %d", ncalls, n);
    for (i = 0; i < n && i < ncalls; i++) {
        int a;

        EXPECT(strcmp(calls[i].name, want[i].name) == 0, "call %d went to %s, expected %s", i, calls[i].name,
               want[i].name);
        EXPECT(calls[i].argc == want[i].argc, "%s: %d arguments, expected %d", want[i].name, calls[i].argc,
               want[i].argc);
        for (a = 0; a < want[i].argc && a < 9; a++)
            EXPECT(calls[i].arg[a] == want[i].arg[a], "%s: argument %d arrived as 0x%llx, expected 0x%llx",
                   want[i].name, a + 1, (unsigned long long)calls[i].arg[a], (unsigned long long)want[i].arg[a]);
    }
    d = gcb_d[0];
    {
        uint64_t got_bits;

        memcpy(&got_bits, &d, sizeof d);
        EXPECT(got_bits == ret_bits, "glfwGetTime came back as %g in xmm0", d);
    }

    for (i = 0; i <= 16; i++) {
        EXPECT(snap[i][0] == sv_magic[0] && snap[i][1] == sv_magic[1] && snap[i][2] == sv_magic[2] &&
               snap[i][3] == sv_magic[3] && snap[i][4] == sv_magic[4], "call %d changed rbx or r12-r15", i);
        EXPECT(snap[i][5] == snap_rsp0, "call %d left rsp changed (%llx vs %llx)", i,
               (unsigned long long)snap[i][5], (unsigned long long)snap_rsp0);
    }
    EXPECT(snap[31][0] != sv_magic[0] && snap[31][4] != sv_magic[4],
           "control: a callee that clobbers rbx and r12-r15 went unnoticed by the check");
}

static void test_shadow_space(void)
{
    int i, bad;

    reset_env();
    mark("glClear");
    clear_calls = 0;
    memset(canary_out, 0, sizeof canary_out);
    asm_shadow_check(1);
    EXPECT(clear_calls == 1 && clear_arg == 0x4100, "glClear: %d calls, argument 0x%x", clear_calls, clear_arg);
    for (bad = 0, i = 0; i < 4; i++)
        bad += canary_out[i] != canary[i];
    EXPECT(bad == 0, "a Win64 callee scribbling its shadow space reached the caller's frame (%d words)", bad);

    clear_calls = 0;
    asm_shadow_check(0);                            /* control: the callee without the wrapper's frame */
    for (bad = 0, i = 0; i < 4; i++)
        bad += canary_out[i] != canary[i];
    EXPECT(clear_calls == 1 && bad == 4, "control: the canaries survived a callee that scribbles them (%d)", bad);
}

static void test_tail_jump(void)
{
    reset_env();
    ncalls = 0;
    asm_tail_jump();
    EXPECT(ncalls == 1 && strcmp(calls[0].name, "glfwSetWindowShouldClose") == 0 &&
           calls[0].arg[0] == (uint64_t)(uintptr_t)win_sentinel && calls[0].arg[1] == 1,
           "glfwSetWindowShouldClose through a tail jump: %d calls", ncalls);
}

static void test_all_exercised(void)
{
    int i;

    for (i = 0; i < N_WRAPPERS; i++)
        EXPECT(exercised[i], "%s was never exercised", all_wrappers[i]);
}

#define GROUP(fn) \
    do { \
        int before = n_fail; \
        fn(); \
        printf("%s %s\n", n_fail == before ? "ok  " : "FAIL", #fn); \
    } while (0)

int main(void)
{
    GROUP(test_generic);
    GROUP(test_is_enabled);
    GROUP(test_init_and_context);
    GROUP(test_glfw_error_log);
    GROUP(test_lazy);
    GROUP(test_no_buffers);
    GROUP(test_callback_registration);
    GROUP(test_callback_dispatch);
    GROUP(test_asm_game_calls);
    GROUP(test_shadow_space);
    GROUP(test_tail_jump);
    GROUP(test_all_exercised);
    printf("win_gfx_test: %d checks, %d failed\n", n_checks, n_fail);
    return n_fail != 0;
}
