/* win_gfx.c - OpenGL and GLFW for the Windows build: the w_gl* / w_glfw* functions the game calls.
 *
 * The game's assembly is assembled with --gprefix w_, so its `call glClear` is a call to w_glClear here, made
 * with the System V AMD64 convention. Every function below is therefore SYSV (win.h) and forwards to the real
 * OpenGL / GLFW function, which uses the Win64 convention; mingw-gcc generates the register translation (stack
 * arguments, shadow space, the registers Win64 wants preserved) for each of them.
 *
 *  - OpenGL 1.1 functions are imported from opengl32.dll and forwarded unchanged.
 *  - OpenGL functions newer than 1.1 (multitexture, buffer objects) are not exported by opengl32.dll. They are
 *    looked up through glfwGetProcAddress on first use, with a context current, and cached until the current
 *    context changes (the pointers belong to a context). When a context does not have one, the call is ignored
 *    and a single line on stderr names the function. Without buffer objects glGenBuffers hands out name 0 and
 *    glDrawArrays draws nothing: the game only ever draws from buffer objects, so its offsets are not memory.
 *  - GLFW callbacks: the game passes System V function pointers. Each kind keeps its one pointer here and GLFW
 *    gets a Win64 trampoline that calls it through a SYSV pointer type; the previous pointer comes back to the
 *    game as it passed it in. The game has a single window, so the pointers are per kind, not per window.
 *  - GLFW errors are silent on Linux; here the first four of each kind go to stderr (the reason a window or
 *    context could not be created is otherwise lost).
 *
 * No window or GL state is kept here. Main (GL) thread only. Link: GLFW 3.4 static, opengl32, gdi32.
 * Test: win/tests/win_gfx_test.c (a fake for every GL / GLFW function, run under wine). */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#define GLFW_INCLUDE_NONE
#include <GL/gl.h>
#include <GLFW/glfw3.h>
#include "win.h"

/* ---- diagnostics ------------------------------------------------------------------------------ */

/* One WriteFile per line, so lines from different threads never interleave. */
static void stderr_line(const char *text, size_t len)
{
    HANDLE h = GetStdHandle(STD_ERROR_HANDLE);
    DWORD written;

    if (h != NULL && h != INVALID_HANDLE_VALUE)
        WriteFile(h, text, (DWORD)len, &written, NULL);
}

static void glfw_error(int code, const char *description)
{
    static unsigned char seen[32];
    unsigned kind = (unsigned)code & 31u;           /* 0x00010001 .. 0x00010011 */
    char line[256];
    int n;

    if (seen[kind] >= 4)
        return;
    seen[kind]++;
    n = snprintf(line, sizeof line, "glfw: error 0x%08X: %.160s\n", (unsigned)code,
                 description != NULL ? description : "");
    if (n > 0)
        stderr_line(line, (size_t)n < sizeof line ? (size_t)n : sizeof line - 1);
}

/* ---- OpenGL newer than 1.1 -------------------------------------------------------------------- */

typedef ptrdiff_t GLsizeiptr;                       /* OpenGL 1.5; the 1.1 header lacks it */

typedef void (APIENTRY *PFN_ActiveTexture)(GLenum texture);
typedef void (APIENTRY *PFN_ClientActiveTexture)(GLenum texture);
typedef void (APIENTRY *PFN_MultiTexCoord2f)(GLenum target, GLfloat s, GLfloat t);
typedef void (APIENTRY *PFN_BindBuffer)(GLenum target, GLuint buffer);
typedef void (APIENTRY *PFN_BufferData)(GLenum target, GLsizeiptr size, const void *data, GLenum usage);
typedef void (APIENTRY *PFN_GenBuffers)(GLsizei n, GLuint *buffers);

enum { LZ_UNRESOLVED, LZ_READY, LZ_ABSENT };        /* LazyGL.state, for the current context */

typedef struct {
    const char *core;                               /* the name since the OpenGL version below */
    const char *arb;                                /* the ARB extension's name, for older drivers */
    const char *since;
    GLFWglproc fn;                                  /* valid while state == LZ_READY */
    unsigned char state;
    unsigned char reported;                         /* the "absent" line was printed; never reset */
} LazyGL;

enum { LZ_ACTIVE_TEXTURE, LZ_CLIENT_ACTIVE_TEXTURE, LZ_MULTI_TEX_COORD_2F, LZ_BIND_BUFFER, LZ_BUFFER_DATA,
       LZ_GEN_BUFFERS, LZ_COUNT };

#define LAZY(core, since) { core, core "ARB", since, NULL, LZ_UNRESOLVED, 0 }

static LazyGL lazy[LZ_COUNT] = {
    [LZ_ACTIVE_TEXTURE]        = LAZY("glActiveTexture", "1.3"),
    [LZ_CLIENT_ACTIVE_TEXTURE] = LAZY("glClientActiveTexture", "1.3"),
    [LZ_MULTI_TEX_COORD_2F]    = LAZY("glMultiTexCoord2f", "1.3"),
    [LZ_BIND_BUFFER]           = LAZY("glBindBuffer", "1.5"),
    [LZ_BUFFER_DATA]           = LAZY("glBufferData", "1.5"),
    [LZ_GEN_BUFFERS]           = LAZY("glGenBuffers", "1.5"),
};

/* glfwGetProcAddress, minus the values some WGL drivers return for an unsupported name (1, 2, 3 or -1). */
static GLFWglproc lookup(const char *name)
{
    GLFWglproc p = glfwGetProcAddress(name);
    uintptr_t v = (uintptr_t)p;

    return (v <= 3 || v == (uintptr_t)-1) ? NULL : p;
}

static void report_absent(const LazyGL *l)
{
    char line[160];
    int n = snprintf(line, sizeof line, "gfx: %s needs OpenGL %s, which this context does not provide; "
                     "calls to it are ignored\n", l->core, l->since);

    if (n > 0)
        stderr_line(line, (size_t)n < sizeof line ? (size_t)n : sizeof line - 1);
}

/* The entry point of lazy[id], resolved now when it has not been yet; NULL when the context lacks it. Nothing
 * can be resolved without a current context: then NULL comes back and the next call tries again. */
static GLFWglproc lazy_get(int id)
{
    LazyGL *l = &lazy[id];

    if (l->state == LZ_UNRESOLVED) {
        if (glfwGetCurrentContext() == NULL)
            return NULL;
        l->fn = lookup(l->core);
        if (l->fn == NULL)
            l->fn = lookup(l->arb);
        l->state = l->fn != NULL ? LZ_READY : LZ_ABSENT;
        if (l->fn == NULL && !l->reported) {
            l->reported = 1;
            report_absent(l);
        }
    }
    return l->fn;
}

/* The pointers belong to the context they were resolved in: forget them when the context changes or goes. */
static void lazy_reset(void)
{
    int i;

    for (i = 0; i < LZ_COUNT; i++) {
        lazy[i].fn = NULL;
        lazy[i].state = LZ_UNRESOLVED;
    }
}

/* 1 when this context has no buffer objects (any of the three the game uses is absent). */
static int buffers_absent(void)
{
    (void)lazy_get(LZ_BIND_BUFFER);
    (void)lazy_get(LZ_BUFFER_DATA);
    (void)lazy_get(LZ_GEN_BUFFERS);
    return lazy[LZ_BIND_BUFFER].state == LZ_ABSENT || lazy[LZ_BUFFER_DATA].state == LZ_ABSENT ||
           lazy[LZ_GEN_BUFFERS].state == LZ_ABSENT;
}

/* ---- OpenGL wrappers (alphabetical) ----------------------------------------------------------- */

SYSV void w_glActiveTexture(GLenum texture)
{
    PFN_ActiveTexture fn = (PFN_ActiveTexture)lazy_get(LZ_ACTIVE_TEXTURE);

    if (fn != NULL)
        fn(texture);
}

SYSV void w_glAlphaFunc(GLenum func, GLclampf ref)
{
    glAlphaFunc(func, ref);
}

SYSV void w_glBegin(GLenum mode)
{
    glBegin(mode);
}

SYSV void w_glBindBuffer(GLenum target, GLuint buffer)
{
    PFN_BindBuffer fn = (PFN_BindBuffer)lazy_get(LZ_BIND_BUFFER);

    if (fn != NULL)
        fn(target, buffer);
}

SYSV void w_glBindTexture(GLenum target, GLuint texture)
{
    glBindTexture(target, texture);
}

SYSV void w_glBlendFunc(GLenum sfactor, GLenum dfactor)
{
    glBlendFunc(sfactor, dfactor);
}

SYSV void w_glBufferData(GLenum target, GLsizeiptr size, const void *data, GLenum usage)
{
    PFN_BufferData fn = (PFN_BufferData)lazy_get(LZ_BUFFER_DATA);

    if (fn != NULL)
        fn(target, size, data, usage);
}

SYSV void w_glClear(GLbitfield mask)
{
    glClear(mask);
}

SYSV void w_glClearColor(GLclampf red, GLclampf green, GLclampf blue, GLclampf alpha)
{
    glClearColor(red, green, blue, alpha);
}

SYSV void w_glClientActiveTexture(GLenum texture)
{
    PFN_ClientActiveTexture fn = (PFN_ClientActiveTexture)lazy_get(LZ_CLIENT_ACTIVE_TEXTURE);

    if (fn != NULL)
        fn(texture);
}

SYSV void w_glColor3f(GLfloat red, GLfloat green, GLfloat blue)
{
    glColor3f(red, green, blue);
}

SYSV void w_glColor4f(GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha)
{
    glColor4f(red, green, blue, alpha);
}

SYSV void w_glColor4ub(GLubyte red, GLubyte green, GLubyte blue, GLubyte alpha)
{
    glColor4ub(red, green, blue, alpha);
}

SYSV void w_glColorPointer(GLint size, GLenum type, GLsizei stride, const void *pointer)
{
    glColorPointer(size, type, stride, pointer);
}

SYSV void w_glDepthMask(GLboolean flag)
{
    glDepthMask(flag);
}

SYSV void w_glDisable(GLenum cap)
{
    glDisable(cap);
}

SYSV void w_glDisableClientState(GLenum array)
{
    glDisableClientState(array);
}

SYSV void w_glDrawArrays(GLenum mode, GLint first, GLsizei count)
{
    static unsigned char reported;

    if (buffers_absent()) {                         /* the arrays are buffer offsets: nothing to read from */
        if (!reported) {
            static const char note[] = "gfx: no buffer objects, glDrawArrays is ignored\n";

            reported = 1;
            stderr_line(note, sizeof note - 1);
        }
        return;
    }
    glDrawArrays(mode, first, count);
}

SYSV void w_glEnable(GLenum cap)
{
    glEnable(cap);
}

SYSV void w_glEnableClientState(GLenum array)
{
    glEnableClientState(array);
}

SYSV void w_glEnd(void)
{
    glEnd();
}

SYSV void w_glFogf(GLenum pname, GLfloat param)
{
    glFogf(pname, param);
}

SYSV void w_glFogfv(GLenum pname, const GLfloat *params)
{
    glFogfv(pname, params);
}

SYSV void w_glFogi(GLenum pname, GLint param)
{
    glFogi(pname, param);
}

SYSV void w_glFrustum(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble zNear,
                      GLdouble zFar)
{
    glFrustum(left, right, bottom, top, zNear, zFar);
}

SYSV void w_glGenBuffers(GLsizei n, GLuint *buffers)
{
    PFN_GenBuffers fn = (PFN_GenBuffers)lazy_get(LZ_GEN_BUFFERS);

    if (fn != NULL)
        fn(n, buffers);
    else if (n > 0 && buffers != NULL)
        memset(buffers, 0, (size_t)n * sizeof *buffers);    /* no buffer objects: every name is 0 */
}

SYSV void w_glGenTextures(GLsizei n, GLuint *textures)
{
    glGenTextures(n, textures);
}

SYSV void w_glGetFloatv(GLenum pname, GLfloat *params)
{
    glGetFloatv(pname, params);
}

/* The GLboolean as a whole 0/1 dword, so a caller may test eax as well as al. */
SYSV unsigned w_glIsEnabled(GLenum cap)
{
    return glIsEnabled(cap) != GL_FALSE;
}

SYSV void w_glLineWidth(GLfloat width)
{
    glLineWidth(width);
}

SYSV void w_glLoadIdentity(void)
{
    glLoadIdentity();
}

SYSV void w_glMatrixMode(GLenum mode)
{
    glMatrixMode(mode);
}

SYSV void w_glMultiTexCoord2f(GLenum target, GLfloat s, GLfloat t)
{
    PFN_MultiTexCoord2f fn = (PFN_MultiTexCoord2f)lazy_get(LZ_MULTI_TEX_COORD_2F);

    if (fn != NULL)
        fn(target, s, t);
}

SYSV void w_glOrtho(GLdouble left, GLdouble right, GLdouble bottom, GLdouble top, GLdouble zNear,
                    GLdouble zFar)
{
    glOrtho(left, right, bottom, top, zNear, zFar);
}

SYSV void w_glPixelStorei(GLenum pname, GLint param)
{
    glPixelStorei(pname, param);
}

SYSV void w_glPopMatrix(void)
{
    glPopMatrix();
}

SYSV void w_glPushMatrix(void)
{
    glPushMatrix();
}

SYSV void w_glRotatef(GLfloat angle, GLfloat x, GLfloat y, GLfloat z)
{
    glRotatef(angle, x, y, z);
}

SYSV void w_glScalef(GLfloat x, GLfloat y, GLfloat z)
{
    glScalef(x, y, z);
}

SYSV void w_glScissor(GLint x, GLint y, GLsizei width, GLsizei height)
{
    glScissor(x, y, width, height);
}

SYSV void w_glTexCoord2i(GLint s, GLint t)
{
    glTexCoord2i(s, t);
}

SYSV void w_glTexCoordPointer(GLint size, GLenum type, GLsizei stride, const void *pointer)
{
    glTexCoordPointer(size, type, stride, pointer);
}

SYSV void w_glTexEnvi(GLenum target, GLenum pname, GLint param)
{
    glTexEnvi(target, pname, param);
}

SYSV void w_glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height,
                         GLint border, GLenum format, GLenum type, const void *pixels)
{
    glTexImage2D(target, level, internalformat, width, height, border, format, type, pixels);
}

SYSV void w_glTexParameteri(GLenum target, GLenum pname, GLint param)
{
    glTexParameteri(target, pname, param);
}

SYSV void w_glTranslatef(GLfloat x, GLfloat y, GLfloat z)
{
    glTranslatef(x, y, z);
}

SYSV void w_glVertex2f(GLfloat x, GLfloat y)
{
    glVertex2f(x, y);
}

SYSV void w_glVertex2i(GLint x, GLint y)
{
    glVertex2i(x, y);
}

SYSV void w_glVertex3f(GLfloat x, GLfloat y, GLfloat z)
{
    glVertex3f(x, y, z);
}

SYSV void w_glVertexPointer(GLint size, GLenum type, GLsizei stride, const void *pointer)
{
    glVertexPointer(size, type, stride, pointer);
}

SYSV void w_glViewport(GLint x, GLint y, GLsizei width, GLsizei height)
{
    glViewport(x, y, width, height);
}

/* ---- GLFW callbacks --------------------------------------------------------------------------- */

typedef void (SYSV *GameKeyFn)(GLFWwindow *window, int key, int scancode, int action, int mods);
typedef void (SYSV *GameCharFn)(GLFWwindow *window, unsigned int codepoint);
typedef void (SYSV *GameMouseButtonFn)(GLFWwindow *window, int button, int action, int mods);
typedef void (SYSV *GameScrollFn)(GLFWwindow *window, double xoffset, double yoffset);

static GameKeyFn game_key;
static GameCharFn game_char;
static GameMouseButtonFn game_mouse_button;
static GameScrollFn game_scroll;

static void key_trampoline(GLFWwindow *window, int key, int scancode, int action, int mods)
{
    if (game_key != NULL)
        game_key(window, key, scancode, action, mods);
}

static void char_trampoline(GLFWwindow *window, unsigned int codepoint)
{
    if (game_char != NULL)
        game_char(window, codepoint);
}

static void mouse_button_trampoline(GLFWwindow *window, int button, int action, int mods)
{
    if (game_mouse_button != NULL)
        game_mouse_button(window, button, action, mods);
}

static void scroll_trampoline(GLFWwindow *window, double xoffset, double yoffset)
{
    if (game_scroll != NULL)
        game_scroll(window, xoffset, yoffset);
}

/* ---- GLFW wrappers (alphabetical) ------------------------------------------------------------- */

SYSV GLFWwindow *w_glfwCreateWindow(int width, int height, const char *title, GLFWmonitor *monitor,
                                    GLFWwindow *share)
{
    return glfwCreateWindow(width, height, title, monitor, share);
}

SYSV void w_glfwDestroyWindow(GLFWwindow *window)
{
    glfwDestroyWindow(window);
    lazy_reset();
}

SYSV void w_glfwGetCursorPos(GLFWwindow *window, double *xpos, double *ypos)
{
    glfwGetCursorPos(window, xpos, ypos);
}

SYSV void w_glfwGetFramebufferSize(GLFWwindow *window, int *width, int *height)
{
    glfwGetFramebufferSize(window, width, height);
}

SYSV int w_glfwGetKey(GLFWwindow *window, int key)
{
    return glfwGetKey(window, key);
}

SYSV const char *w_glfwGetKeyName(int key, int scancode)
{
    return glfwGetKeyName(key, scancode);
}

SYSV int w_glfwGetMouseButton(GLFWwindow *window, int button)
{
    return glfwGetMouseButton(window, button);
}

SYSV GLFWmonitor *w_glfwGetPrimaryMonitor(void)
{
    return glfwGetPrimaryMonitor();
}

SYSV double w_glfwGetTime(void)
{
    return glfwGetTime();
}

SYSV const GLFWvidmode *w_glfwGetVideoMode(GLFWmonitor *monitor)
{
    return glfwGetVideoMode(monitor);
}

SYSV int w_glfwGetWindowAttrib(GLFWwindow *window, int attrib)
{
    return glfwGetWindowAttrib(window, attrib);
}

SYSV void w_glfwGetWindowPos(GLFWwindow *window, int *xpos, int *ypos)
{
    glfwGetWindowPos(window, xpos, ypos);
}

SYSV void w_glfwGetWindowSize(GLFWwindow *window, int *width, int *height)
{
    glfwGetWindowSize(window, width, height);
}

SYSV int w_glfwInit(void)
{
    glfwSetErrorCallback(glfw_error);               /* allowed before glfwInit: init failures are reported too */
    return glfwInit();
}

SYSV void w_glfwMakeContextCurrent(GLFWwindow *window)
{
    glfwMakeContextCurrent(window);
    lazy_reset();
}

SYSV void w_glfwPollEvents(void)
{
    glfwPollEvents();
}

SYSV int w_glfwRawMouseMotionSupported(void)
{
    return glfwRawMouseMotionSupported();
}

SYSV GameCharFn w_glfwSetCharCallback(GLFWwindow *window, GameCharFn callback)
{
    GameCharFn previous = game_char;

    game_char = callback;
    glfwSetCharCallback(window, callback != NULL ? char_trampoline : NULL);
    return previous;
}

SYSV void w_glfwSetInputMode(GLFWwindow *window, int mode, int value)
{
    glfwSetInputMode(window, mode, value);
}

SYSV GameKeyFn w_glfwSetKeyCallback(GLFWwindow *window, GameKeyFn callback)
{
    GameKeyFn previous = game_key;

    game_key = callback;
    glfwSetKeyCallback(window, callback != NULL ? key_trampoline : NULL);
    return previous;
}

SYSV GameMouseButtonFn w_glfwSetMouseButtonCallback(GLFWwindow *window, GameMouseButtonFn callback)
{
    GameMouseButtonFn previous = game_mouse_button;

    game_mouse_button = callback;
    glfwSetMouseButtonCallback(window, callback != NULL ? mouse_button_trampoline : NULL);
    return previous;
}

SYSV GameScrollFn w_glfwSetScrollCallback(GLFWwindow *window, GameScrollFn callback)
{
    GameScrollFn previous = game_scroll;

    game_scroll = callback;
    glfwSetScrollCallback(window, callback != NULL ? scroll_trampoline : NULL);
    return previous;
}

SYSV void w_glfwSetWindowMonitor(GLFWwindow *window, GLFWmonitor *monitor, int xpos, int ypos, int width,
                                 int height, int refreshRate)
{
    glfwSetWindowMonitor(window, monitor, xpos, ypos, width, height, refreshRate);
}

SYSV void w_glfwSetWindowShouldClose(GLFWwindow *window, int value)
{
    glfwSetWindowShouldClose(window, value);
}

SYSV void w_glfwSetWindowTitle(GLFWwindow *window, const char *title)
{
    glfwSetWindowTitle(window, title);
}

SYSV void w_glfwSwapBuffers(GLFWwindow *window)
{
    glfwSwapBuffers(window);
}

SYSV void w_glfwSwapInterval(int interval)
{
    glfwSwapInterval(interval);
}

SYSV void w_glfwTerminate(void)
{
    glfwTerminate();
    lazy_reset();
}

SYSV void w_glfwWindowHint(int hint, int value)
{
    glfwWindowHint(hint, value);
}

SYSV void w_glfwWindowHintString(int hint, const char *value)
{
    glfwWindowHintString(hint, value);
}

SYSV int w_glfwWindowShouldClose(GLFWwindow *window)
{
    return glfwWindowShouldClose(window);
}
