; gunmodel.asm - first-person firearm models: each weapon is a few tinted boxes pointing to -Z
; (the muzzle) on the near-white atlas tile, plus a muzzle flash right after a shot.
%include "common.inc"
%include "gl.inc"
default rel

global gun_model_draw

extern render_box

%define C_METAL  0                      ; part colours (index into colours)
%define C_DARK   1
%define C_WOOD   2
%define C_BRASS  3
%define C_GREEN  4
%define C_RED    5                      ; only drawn while loaded (the rocket's warhead)
%define C_MAG    6
%define END      -1

; PART x0, y0, z0, x1, y1, z1, colour
%macro PART 7
    dd %1, %2, %3, %4, %5, %6
    dd %7
%endmacro
%define PART_SIZE 28

section .rodata
align 4
colours:
    dd 0.22, 0.22, 0.25                 ; metal
    dd 0.12, 0.12, 0.13                 ; dark
    dd 0.55, 0.33, 0.16                 ; wood
    dd 0.90, 0.70, 0.25                 ; brass
    dd 0.30, 0.45, 0.22                 ; green
    dd 0.75, 0.12, 0.10                 ; red
    dd 0.45, 0.25, 0.10                 ; magazine
shades:      dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8   ; +X -X +Y -Y +Z -Z
flash_shade: dd 1.0, 1.0, 1.0, 1.0, 1.0, 1.0
tiles:       times 6 db TILE_CHICKEN_BODY
             db 0, 0
f_one:       dd 1.0
f_flash_on:  dd 0.6                     ; kick above this shows the muzzle flash
f_flash_r:   dd 1.0
f_flash_g:   dd 0.85
f_flash_b:   dd 0.3
f_flash_w:   dd 0.07                    ; flash half size at full kick
f_flash_len: dd 0.16

pistol:
    PART -0.035, 0.0, -0.28,   0.035, 0.07, 0.02,   C_METAL
    PART -0.03, -0.16, -0.04,  0.03, 0.0, 0.04,     C_DARK
    PART -0.012, -0.05, -0.1,  0.012, 0.0, -0.04,   C_DARK  ; trigger guard
    dd END
musket:
    PART -0.02, 0.02, -1.05,   0.02, 0.06, -0.25,   C_METAL
    PART -0.045, -0.05, -0.75, 0.045, 0.04, 0.2,    C_WOOD
    PART -0.05, -0.16, 0.05,   0.05, 0.02, 0.35,    C_WOOD
    PART -0.02, 0.04, -0.05,   0.02, 0.09, 0.05,    C_METAL ; the flintlock
    dd END
shotgun:
    PART -0.045, 0.02, -0.8,   0.0, 0.065, -0.1,    C_METAL
    PART 0.0, 0.02, -0.8,      0.045, 0.065, -0.1,  C_METAL
    PART -0.04, -0.04, -0.6,   0.04, 0.02, -0.35,   C_WOOD
    PART -0.045, -0.04, -0.12, 0.045, 0.06, 0.12,   C_DARK
    PART -0.04, -0.13, 0.1,    0.04, 0.03, 0.45,    C_WOOD
    dd END
rifle:
    PART -0.015, 0.03, -0.7,   0.015, 0.06, -0.3,   C_DARK
    PART -0.04, -0.01, -0.48,  0.04, 0.06, -0.25,   C_WOOD
    PART -0.045, -0.02, -0.25, 0.045, 0.07, 0.15,   C_DARK
    PART -0.03, -0.2, -0.2,    0.03, -0.02, -0.1,   C_MAG
    PART -0.03, -0.28, -0.17,  0.03, -0.19, -0.06,  C_MAG
    PART -0.03, -0.14, 0.0,    0.03, -0.02, 0.06,   C_DARK
    PART -0.035, -0.08, 0.15,  0.035, 0.04, 0.45,   C_WOOD
    PART -0.008, 0.07, -0.66,  0.008, 0.1, -0.62,   C_DARK  ; front sight
    dd END
launcher:
    PART -0.065, -0.02, -0.55, 0.065, 0.11, 0.2,    C_GREEN
    PART -0.03, -0.18, -0.05,  0.03, -0.02, 0.03,   C_DARK
    PART -0.03, -0.16, -0.3,   0.03, -0.02, -0.24,  C_DARK  ; front grip
    PART -0.05, 0.0, -0.66,    0.05, 0.09, -0.55,   C_RED
    dd END
align 8
models:      dq pistol, musket, shotgun, rifle, launcher
muzzle_z:    dd -0.29, -1.06, -0.81, -0.71, -0.56
muzzle_y:    dd 0.035, 0.04, 0.042, 0.045, 0.06

section .bss
alignb 4
part_rgb:    resd 3
flash_box:   resd 6

section .text

; gun_model_draw(edi id, esi loaded, xmm0 light, xmm1 kick): the firearm id (PISTOL..) at the
; origin, muzzle towards -Z; a C_RED part only while loaded; a fullbright muzzle flash while
; kick > 0.6. The caller binds the atlas.
; rbx = part, r12d = loaded, r13d = g; [rsp] light, [rsp+4] kick
gun_model_draw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    lea     r13d, [rdi - PISTOL]
    cmp     r13d, NUM_GUNS
    jae     .ret
    mov     r12d, esi
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    lea     rax, [models]
    mov     rbx, [rax + r13*8]
.part:
    cmp     dword [rbx], END            ; the list ends with a lone END word
    je      .flash
    mov     eax, [rbx + 24]             ; colour
    cmp     eax, C_RED
    jne     .draw
    test    r12d, r12d
    jz      .next                       ; nothing in the tube
.draw:
    lea     rcx, [rax + rax*2]
    lea     rdx, [colours]
    movss   xmm0, [rdx + rcx*4]
    mulss   xmm0, [rsp]
    movss   xmm1, [rdx + rcx*4 + 4]
    mulss   xmm1, [rsp]
    movss   xmm2, [rdx + rcx*4 + 8]
    mulss   xmm2, [rsp]
    mov     rdi, rbx
    lea     rsi, [tiles]
    lea     rdx, [shades]
    call    render_box
.next:
    add     rbx, PART_SIZE
    jmp     .part
.flash:
    movss   xmm0, [rsp + 4]
    comiss  xmm0, [f_flash_on]
    jbe     .ret
    mulss   xmm0, [f_flash_w]           ; a yellow block bursting from the muzzle
    xorps   xmm1, xmm1
    subss   xmm1, xmm0
    movss   [flash_box], xmm1           ; x0 = -w
    movss   [flash_box + 12], xmm0      ; x1 = w
    lea     rax, [muzzle_y]
    movss   xmm2, [rax + r13*4]
    movaps  xmm3, xmm2
    subss   xmm2, xmm0
    addss   xmm3, xmm0
    movss   [flash_box + 4], xmm2
    movss   [flash_box + 16], xmm3
    lea     rax, [muzzle_z]
    movss   xmm2, [rax + r13*4]
    movss   [flash_box + 20], xmm2      ; z1 = muzzle
    subss   xmm2, [f_flash_len]
    movss   [flash_box + 8], xmm2       ; z0 = muzzle - length
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    lea     rdi, [flash_box]
    lea     rsi, [tiles]
    lea     rdx, [flash_shade]
    movss   xmm0, [f_flash_r]
    movss   xmm1, [f_flash_g]
    movss   xmm2, [f_flash_b]
    call    render_box
    mov     edi, GL_TEXTURE_2D
    call    glEnable
.ret:
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
