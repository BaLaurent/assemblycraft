; syscall_stub.asm - the Windows build's stand-in for the Linux `syscall` instruction.
; common.inc turns every `syscall` of the game into `call syscall_stub` (-DWIN64). The stub keeps the
; syscall contract the game relies on: rax = number, rdi rsi rdx r10 r8 r9 = arguments; on return rax
; is the result (or -errno) and EVERY other register except rcx and r11 is preserved (rdi, rsi, rdx,
; r8, r9, r10, rbx, rbp, r12-r15 and xmm0-15). The work is done by the C function
;     long win_syscall(long nr, long a1, long a2, long a3, long a4, long a5, long a6)
; (win/win_sys.c, declared __attribute__((sysv_abi))). The caller's rsp alignment is unknown, as for a
; real syscall, so the stub aligns it itself.
; Assembled WITHOUT --gprefix: the symbol is the final name w_syscall_stub (the game's externs are
; prefixed by --gprefix w_).
default rel
bits 64

global w_syscall_stub
extern win_syscall

section .text
w_syscall_stub:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48 + 256               ; saved gp registers + 16 xmm
    mov     [rsp + 0], rdi
    mov     [rsp + 8], rsi
    mov     [rsp + 16], rdx
    mov     [rsp + 24], r8
    mov     [rsp + 32], r9
    mov     [rsp + 40], r10
    movups  [rsp + 48 + 0 * 16], xmm0
    movups  [rsp + 48 + 1 * 16], xmm1
    movups  [rsp + 48 + 2 * 16], xmm2
    movups  [rsp + 48 + 3 * 16], xmm3
    movups  [rsp + 48 + 4 * 16], xmm4
    movups  [rsp + 48 + 5 * 16], xmm5
    movups  [rsp + 48 + 6 * 16], xmm6
    movups  [rsp + 48 + 7 * 16], xmm7
    movups  [rsp + 48 + 8 * 16], xmm8
    movups  [rsp + 48 + 9 * 16], xmm9
    movups  [rsp + 48 + 10 * 16], xmm10
    movups  [rsp + 48 + 11 * 16], xmm11
    movups  [rsp + 48 + 12 * 16], xmm12
    movups  [rsp + 48 + 13 * 16], xmm13
    movups  [rsp + 48 + 14 * 16], xmm14
    movups  [rsp + 48 + 15 * 16], xmm15
    mov     r11, r9                     ; a6 (goes on the stack)
    mov     r9, r8                      ; a5
    mov     r8, r10                     ; a4
    mov     rcx, rdx                    ; a3
    mov     rdx, rsi                    ; a2
    mov     rsi, rdi                    ; a1
    mov     rdi, rax                    ; nr
    and     rsp, -16
    sub     rsp, 16
    mov     [rsp], r11
    call    win_syscall
    lea     rsp, [rbp - 48 - 256]
    mov     rdi, [rsp + 0]
    mov     rsi, [rsp + 8]
    mov     rdx, [rsp + 16]
    mov     r8, [rsp + 24]
    mov     r9, [rsp + 32]
    mov     r10, [rsp + 40]
    movups  xmm0, [rsp + 48 + 0 * 16]
    movups  xmm1, [rsp + 48 + 1 * 16]
    movups  xmm2, [rsp + 48 + 2 * 16]
    movups  xmm3, [rsp + 48 + 3 * 16]
    movups  xmm4, [rsp + 48 + 4 * 16]
    movups  xmm5, [rsp + 48 + 5 * 16]
    movups  xmm6, [rsp + 48 + 6 * 16]
    movups  xmm7, [rsp + 48 + 7 * 16]
    movups  xmm8, [rsp + 48 + 8 * 16]
    movups  xmm9, [rsp + 48 + 9 * 16]
    movups  xmm10, [rsp + 48 + 10 * 16]
    movups  xmm11, [rsp + 48 + 11 * 16]
    movups  xmm12, [rsp + 48 + 12 * 16]
    movups  xmm13, [rsp + 48 + 13 * 16]
    movups  xmm14, [rsp + 48 + 14 * 16]
    movups  xmm15, [rsp + 48 + 15 * 16]
    mov     rsp, rbp
    pop     rbp
    ret
