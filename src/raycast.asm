; raycast.asm - voxel ray traversal (Amanatides-Woo DDA).
%include "common.inc"
default rel

global raycast

extern world_get

section .rodata
align 4
c_far:  dd 1.0e30                       ; tMax / tDelta of an axis the ray never crosses
c_one:  dd 1.0

section .text

; Frame (rsp-relative): int cell[3], prev[3], step[3]; float tMax[3], tDelta[3], maxdist.
%define RC_CELL 0
%define RC_PREV 16
%define RC_STEP 32
%define RC_TMAX 48
%define RC_TDLT 64
%define RC_MAX  80

; raycast(rdi float origin[3], rsi float dir[3], rdx RAYHIT* out, xmm0 maxdist) -> eax hit 0/1
; Walks the cells the ray enters, in order, for at most 64 steps or until the next cell
; boundary lies beyond maxdist. On a hit, out = { b = block hit, p = cell entered before it }.
raycast:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 96
    movss   [rsp + RC_MAX], xmm0
    mov     rbx, rdx
    xor     ecx, ecx
.setup:                                 ; one pass per axis
    movss   xmm0, [rdi + rcx*4]         ; o
    movss   xmm1, [rsi + rcx*4]         ; d
    roundss xmm2, xmm0, 9               ; floor(o)
    cvttss2si eax, xmm2
    mov     [rsp + RC_CELL + rcx*4], eax
    mov     [rsp + RC_PREV + rcx*4], eax
    movss   xmm5, [c_far]               ; tMax
    movaps  xmm6, xmm5                  ; tDelta
    xor     edx, edx                    ; step
    xorps   xmm3, xmm3
    ucomiss xmm1, xmm3
    jp      .axis_done                  ; NaN direction: treat the axis as not moving
    ja      .pos
    jb      .neg
    jmp     .axis_done                  ; d == 0
.pos:
    mov     edx, 1
    movss   xmm3, [c_one]
    movaps  xmm6, xmm3
    divss   xmm6, xmm1                  ; tDelta = 1/d
    addss   xmm2, xmm3
    subss   xmm2, xmm0                  ; cell + 1 - o
    divss   xmm2, xmm1
    movaps  xmm5, xmm2                  ; tMax
    jmp     .axis_done
.neg:
    mov     edx, -1
    xorps   xmm4, xmm4
    subss   xmm4, xmm1                  ; -d
    movss   xmm6, [c_one]
    divss   xmm6, xmm4                  ; tDelta = 1/-d
    subss   xmm0, xmm2                  ; o - cell
    divss   xmm0, xmm4
    movaps  xmm5, xmm0                  ; tMax
.axis_done:
    mov     [rsp + RC_STEP + rcx*4], edx
    movss   [rsp + RC_TMAX + rcx*4], xmm5
    movss   [rsp + RC_TDLT + rcx*4], xmm6
    inc     ecx
    cmp     ecx, 3
    jb      .setup

    mov     r12d, 64
.loop:
    mov     edi, [rsp + RC_CELL]
    mov     esi, [rsp + RC_CELL + 4]
    mov     edx, [rsp + RC_CELL + 8]
    call    world_get
    test    eax, eax
    jz      .pass
    cmp     eax, FIRE
    jne     .hit                        ; flames never stop a ray
.pass:
    movss   xmm0, [rsp + RC_TMAX]       ; a = axis with the smallest tMax (ties: x, then y)
    xor     ecx, ecx
    movss   xmm1, [rsp + RC_TMAX + 4]
    ucomiss xmm0, xmm1
    jbe     .not_y
    movaps  xmm0, xmm1
    mov     ecx, 1
.not_y:
    movss   xmm1, [rsp + RC_TMAX + 8]
    ucomiss xmm0, xmm1
    jbe     .not_z
    movaps  xmm0, xmm1
    mov     ecx, 2
.not_z:
    ucomiss xmm0, [rsp + RC_MAX]
    ja      .miss                       ; next boundary is out of reach
    mov     rax, [rsp + RC_CELL]        ; prev = cell
    mov     [rsp + RC_PREV], rax
    mov     eax, [rsp + RC_CELL + 8]
    mov     [rsp + RC_PREV + 8], eax
    mov     eax, [rsp + RC_STEP + rcx*4]
    add     [rsp + RC_CELL + rcx*4], eax
    addss   xmm0, [rsp + RC_TDLT + rcx*4]
    movss   [rsp + RC_TMAX + rcx*4], xmm0
    dec     r12d
    jnz     .loop
.miss:
    xor     eax, eax
    jmp     .ret
.hit:
    mov     eax, [rsp + RC_CELL]
    mov     [rbx + RAYHIT.bx], eax
    mov     eax, [rsp + RC_CELL + 4]
    mov     [rbx + RAYHIT.by], eax
    mov     eax, [rsp + RC_CELL + 8]
    mov     [rbx + RAYHIT.bz], eax
    mov     eax, [rsp + RC_PREV]
    mov     [rbx + RAYHIT.px], eax
    mov     eax, [rsp + RC_PREV + 4]
    mov     [rbx + RAYHIT.py], eax
    mov     eax, [rsp + RC_PREV + 8]
    mov     [rbx + RAYHIT.pz], eax
    mov     eax, 1
.ret:
    add     rsp, 96
    pop     r12
    pop     rbx
    pop     rbp
    ret
