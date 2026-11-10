; gunmodel.asm - first-person firearm models: every weapon is a skinned box model (skins_gear.asm, 64 texels
; per block, the muzzle towards -Z) drawn by skin_model_draw, plus a muzzle flash right after a shot.
%include "common.inc"
%include "gl.inc"
default rel

global gun_model_draw

extern render_box, gun_index, skin_model_draw
extern m_gun_pistol, m_gun_musket, m_gun_shotgun, m_gun_rifle, m_gun_launcher, m_gun_revolver, m_gun_hrifle
extern m_gun_warhead

%define G_LAUNCHER (ROCKET_LAUNCHER - PISTOL)   ; gun index of the rocket launcher (its rocket is a second model)

section .rodata
align 4
flash_shade: dd 1.0, 1.0, 1.0, 1.0, 1.0, 1.0
tiles:       times 6 db TILE_CHICKEN_BODY
             db 0, 0
f_flash_on:  dd 0.6                     ; kick above this shows the muzzle flash
f_flash_r:   dd 1.0
f_flash_g:   dd 0.85
f_flash_b:   dd 0.3
f_flash_w:   dd 0.07                    ; flash half size at full kick
f_flash_len: dd 0.16

align 8
models:      dq m_gun_pistol, m_gun_musket, m_gun_shotgun, m_gun_rifle, m_gun_launcher, m_gun_revolver, m_gun_hrifle
muzzle_z:    dd -0.29, -1.06, -0.81, -0.71, -0.56, -0.31, -1.01
muzzle_y:    dd 0.035, 0.04, 0.042, 0.045, 0.06, 0.035, 0.047
%if (muzzle_z - models) != NUM_GUNS * 8 || (muzzle_y - muzzle_z) != NUM_GUNS * 4
%error "models, muzzle_z and muzzle_y need one entry per firearm (NUM_GUNS)"
%endif

section .bss
alignb 4
flash_box:   resd 6

section .text

; gun_model_draw(edi id, esi loaded, xmm0 light, xmm1 kick): the firearm id (gun_index >= 0) at the
; origin, muzzle towards -Z, as a skin model tinted by the light (skin_model_draw, which scales its
; 64 texels per block to blocks itself); the launcher's rocket (m_gun_warhead) only while loaded; a
; fullbright muzzle flash while kick > 0.6. The caller binds the atlas.
; rbx = model, r12d = loaded, r13d = g; [rsp] light, [rsp+4] kick
gun_model_draw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    call    gun_index                   ; clobbers eax only: esi, xmm0 and xmm1 are still the arguments
    test    eax, eax
    js      .ret
    mov     r13d, eax
    mov     r12d, esi
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    lea     rax, [models]
    mov     rbx, [rax + r13*8]
.model:
    mov     rdi, rbx
    xor     esi, esi                    ; no pose: rest, no held item, accent white
    xorps   xmm0, xmm0                  ; no walk swing
    movss   xmm1, [rsp]                 ; tint = the light
    movaps  xmm2, xmm1
    movaps  xmm3, xmm1
    call    skin_model_draw
    lea     rax, [m_gun_warhead]
    cmp     rbx, rax
    je      .flash                      ; that was the rocket
    cmp     r13d, G_LAUNCHER
    jne     .flash
    test    r12d, r12d
    jz      .flash                      ; nothing in the tube
    mov     rbx, rax
    jmp     .model
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
