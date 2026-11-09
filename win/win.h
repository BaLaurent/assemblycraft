/* win.h - shared declarations of the Windows platform layer (the C files in win/).
 * The game's assembly follows the System V AMD64 convention; everything the game calls or that calls
 * the game is declared SYSV. Calls into Win32/GLFW/OpenGL use the normal (ms_abi) convention. */
#ifndef AC_WIN_H
#define AC_WIN_H
#define SYSV __attribute__((sysv_abi))
#endif
