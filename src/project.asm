; project.asm - world_to_ui: where a world position lands on the screen, for the overlays that
; follow things in the world (damage numbers, mob health bars, name tags).
%include "common.inc"
default rel

global world_to_ui

extern player, player_eye, settings, game_aim, ui_w, ui_h, sincos_deg

section .rodata
align 4
c_half:     dd 0.5
c_aim_zoom: dd 0.3                      ; fully aimed the FOV narrows by 30 % (render.asm)
c_near:     dd 0.05                     ; points nearer than this along the view direction are not shown
c_lim:      dd 16384.0                  ; far-off points are clamped, so the int result never overflows
c_nlim:     dd -16384.0
c_one:      dd 1.0

section .text

; world_to_ui(rdi float pos[3], rsi int32 out[2]) -> eax 1 if pos is in front of the camera
;   (out = GUI-unit x, y), else 0 and out is left alone
; The camera basis is the one render_world builds from yaw and pitch:
;   right   = (cos y, 0, sin y)
;   up      = (sin y sin p, cos p, -cos y sin p)
;   forward = (sin y cos p, -sin p, -cos y cos p)           (= player_forward)
; rel = pos - eye; xc, yc, zc = rel . right, rel . up, rel . forward; visible when zc > 0.05.
; With t = tan(fov (1 - 0.3 game_aim) / 2), the vertical field of view spans the screen height:
;   x = ui_w/2 + (xc/zc) / t * ui_h/2,   y = ui_h/2 - (yc/zc) / t * ui_h/2     (rounded)
; frame: [rsp] eye, [rsp+16] rel, [rsp+32] sin yaw, cos yaw, sin pitch, cos pitch,
;        [rsp+48] xc, yc, zc
world_to_ui:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 64
    mov     rbx, rdi
    mov     r12, rsi
    mov     rdi, rsp
    call    player_eye
    movss   xmm0, [rbx]
    subss   xmm0, [rsp]
    movss   [rsp + 16], xmm0
    movss   xmm0, [rbx + 4]
    subss   xmm0, [rsp + 4]
    movss   [rsp + 20], xmm0
    movss   xmm0, [rbx + 8]
    subss   xmm0, [rsp + 8]
    movss   [rsp + 24], xmm0
    movss   xmm0, [player + BODY.yaw]
    call    sincos_deg
    movss   [rsp + 32], xmm0
    movss   [rsp + 36], xmm1
    movss   xmm0, [player + BODY.pitch]
    call    sincos_deg
    movss   [rsp + 40], xmm0
    movss   [rsp + 44], xmm1

    ; zc = rel.x sin y cos p - rel.y sin p - rel.z cos y cos p
    movss   xmm0, [rsp + 16]
    mulss   xmm0, [rsp + 32]
    mulss   xmm0, [rsp + 44]
    movss   xmm1, [rsp + 20]
    mulss   xmm1, [rsp + 40]
    subss   xmm0, xmm1
    movss   xmm1, [rsp + 24]
    mulss   xmm1, [rsp + 36]
    mulss   xmm1, [rsp + 44]
    subss   xmm0, xmm1
    comiss  xmm0, [c_near]
    jbe     .behind                     ; also catches NaN
    movss   [rsp + 56], xmm0

    ; xc = rel.x cos y + rel.z sin y
    movss   xmm0, [rsp + 16]
    mulss   xmm0, [rsp + 36]
    movss   xmm1, [rsp + 24]
    mulss   xmm1, [rsp + 32]
    addss   xmm0, xmm1
    movss   [rsp + 48], xmm0
    ; yc = rel.x sin y sin p + rel.y cos p - rel.z cos y sin p
    movss   xmm0, [rsp + 16]
    mulss   xmm0, [rsp + 32]
    mulss   xmm0, [rsp + 40]
    movss   xmm1, [rsp + 20]
    mulss   xmm1, [rsp + 44]
    addss   xmm0, xmm1
    movss   xmm1, [rsp + 24]
    mulss   xmm1, [rsp + 36]
    mulss   xmm1, [rsp + 40]
    subss   xmm0, xmm1
    movss   [rsp + 52], xmm0

    ; scale = (ui_h / 2) / t = (ui_h / 2) cos a / sin a for a = fov (1 - 0.3 aim) / 2
    cvtsi2ss xmm0, dword [settings + SETTINGS.fov]
    movss   xmm1, [game_aim]
    mulss   xmm1, [c_aim_zoom]
    movss   xmm2, [c_one]
    subss   xmm2, xmm1
    mulss   xmm0, xmm2
    mulss   xmm0, [c_half]
    call    sincos_deg                  ; xmm0 = sin a, xmm1 = cos a
    divss   xmm1, xmm0
    cvtsi2ss xmm2, dword [ui_h]
    mulss   xmm2, [c_half]
    mulss   xmm1, xmm2                  ; scale in GUI units per unit of xc / zc
    movss   xmm3, [rsp + 56]            ; zc
    movss   xmm0, [rsp + 48]
    divss   xmm0, xmm3
    mulss   xmm0, xmm1
    cvtsi2ss xmm2, dword [ui_w]
    mulss   xmm2, [c_half]
    addss   xmm0, xmm2                  ; x
    movss   xmm2, [rsp + 52]
    divss   xmm2, xmm3
    mulss   xmm2, xmm1
    cvtsi2ss xmm1, dword [ui_h]
    mulss   xmm1, [c_half]
    subss   xmm1, xmm2                  ; y
    movss   xmm2, [c_lim]
    minss   xmm0, xmm2
    minss   xmm1, xmm2
    movss   xmm2, [c_nlim]
    maxss   xmm0, xmm2
    maxss   xmm1, xmm2
    cvtss2si eax, xmm0
    mov     [r12], eax
    cvtss2si eax, xmm1
    mov     [r12 + 4], eax
    mov     eax, 1
    jmp     .ret
.behind:
    xor     eax, eax
.ret:
    add     rsp, 64
    pop     r12
    pop     rbx
    pop     rbp
    ret
