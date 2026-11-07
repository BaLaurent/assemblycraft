; gl.inc - GLFW 3 / legacy OpenGL imports and enum values used by AssemblyCraft.
; Values copied from /usr/include/GLFW/glfw3.h and /usr/include/GL/gl.h, glext.h.

; ---- GLFW functions -------------------------------------------------------
extern glfwInit, glfwTerminate, glfwWindowHint, glfwWindowHintString
extern glfwCreateWindow, glfwDestroyWindow, glfwMakeContextCurrent, glfwSwapInterval
extern glfwWindowShouldClose, glfwPollEvents, glfwGetTime, glfwSwapBuffers
extern glfwGetFramebufferSize, glfwSetWindowTitle
extern glfwGetKey, glfwGetMouseButton, glfwGetCursorPos, glfwSetInputMode
extern glfwRawMouseMotionSupported, glfwSetScrollCallback

; ---- GL functions ---------------------------------------------------------
extern glViewport, glClearColor, glClear
extern glMatrixMode, glLoadIdentity, glFrustum, glOrtho, glRotatef, glTranslatef, glScalef
extern glEnable, glDisable, glEnableClientState, glDisableClientState
extern glGenBuffers, glBindBuffer, glBufferData
extern glVertexPointer, glTexCoordPointer, glColorPointer, glDrawArrays
extern glGenTextures, glBindTexture, glPixelStorei, glTexImage2D, glTexParameteri
extern glFogi, glFogf, glFogfv, glAlphaFunc, glBlendFunc
extern glColor4f, glLineWidth, glBegin, glEnd, glVertex3f, glVertex2i, glTexCoord2i

; ---- GLFW enums -----------------------------------------------------------
%define GLFW_TRUE              1
%define GLFW_PRESS             1
%define GLFW_DEPTH_BITS        0x21005
%define GLFW_CURSOR            0x33001
%define GLFW_CURSOR_NORMAL     0x34001
%define GLFW_CURSOR_DISABLED   0x34003
%define GLFW_RAW_MOUSE_MOTION  0x33005
%define GLFW_WAYLAND_APP_ID    0x26001
%define GLFW_X11_CLASS_NAME    0x24001

%define GLFW_STICKY_KEYS          0x33002
%define GLFW_STICKY_MOUSE_BUTTONS 0x33003

%define KEY_SPACE         32
%define KEY_1             49
%define KEY_9             57
%define KEY_A             65
%define KEY_D             68
%define KEY_F             70
%define KEY_S             83
%define KEY_W             87
%define KEY_ESCAPE        256
%define KEY_F5            294
%define KEY_LEFT_SHIFT    340
%define KEY_LEFT_CONTROL  341

%define MOUSE_LEFT    0
%define MOUSE_RIGHT   1
%define MOUSE_MIDDLE  2

; ---- GL enums -------------------------------------------------------------
%define GL_UNSIGNED_BYTE         0x1401
%define GL_SHORT                 0x1402
%define GL_LINES                 1
%define GL_LINE_LOOP             2
%define GL_QUADS                 7
%define GL_VERTEX_ARRAY          0x8074
%define GL_COLOR_ARRAY           0x8076
%define GL_TEXTURE_COORD_ARRAY   0x8078
%define GL_MODELVIEW             0x1700
%define GL_PROJECTION            0x1701
%define GL_TEXTURE               0x1702
%define GL_CULL_FACE             0x0B44
%define GL_DEPTH_TEST            0x0B71
%define GL_ALPHA_TEST            0x0BC0
%define GL_BLEND                 0x0BE2
%define GL_FOG                   0x0B60
%define GL_TEXTURE_2D            0x0DE1
%define GL_GREATER               0x0204
%define GL_ZERO                  0
%define GL_SRC_ALPHA             0x0302
%define GL_ONE_MINUS_SRC_ALPHA   0x0303
%define GL_ONE_MINUS_DST_COLOR   0x0307
%define GL_FOG_MODE              0x0B65
%define GL_FOG_COLOR             0x0B66
%define GL_FOG_START             0x0B63
%define GL_FOG_END               0x0B64
%define GL_LINEAR                0x2601
%define GL_RGBA                  0x1908
%define GL_UNPACK_ALIGNMENT      0x0CF5
%define GL_TEXTURE_WRAP_S        0x2802
%define GL_TEXTURE_WRAP_T        0x2803
%define GL_TEXTURE_MAG_FILTER    0x2800
%define GL_TEXTURE_MIN_FILTER    0x2801
%define GL_NEAREST               0x2600
%define GL_CLAMP_TO_EDGE         0x812F
%define GL_COLOR_BUFFER_BIT      0x4000
%define GL_DEPTH_BUFFER_BIT      0x100
%define GL_ARRAY_BUFFER          0x8892
%define GL_STATIC_DRAW           0x88E4
