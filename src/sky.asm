; sky.asm - day/night cycle: sky brightness, sky colour, sun angle.
%include "common.inc"
default rel

global sky_brightness, sky_color, sky_angle, sky_is_night

section .rodata
align 4
k_one:     dd 1.0
k_quarter: dd 0.25
k_c075:    dd 0.75
k_c045:    dd 0.45
k_c055:    dd 0.55
k_c095:    dd 0.95
k_c10:     dd 10.0                      ; 1 / 0.10
k_c20:     dd 20.0                      ; 1 / 0.05
k_inv_b:   dd 1.3333334                 ; 1 / 0.75
k_deg:     dd 360.0
k_half:    dd 0.5
k_len:     dd 72000.0
night_rgb: dd 0.02, 0.03, 0.08
day_rgb:   dd 0.62, 0.80, 1.0

section .text

; sky_phase(edi time) -> xmm0 = (time mod DAY_LENGTH) / DAY_LENGTH
sky_phase:
    mov     eax, edi
    xor     edx, edx
    mov     ecx, DAY_LENGTH
    div     ecx
    cvtsi2ss xmm0, edx
    divss   xmm0, [k_len]
    ret

; sky_brightness(edi time) -> xmm0 in [0.25, 1.0]
sky_brightness:
    call    sky_phase
    movss   xmm1, [k_one]
    ucomiss xmm0, [k_c045]
    jb      .ret1                       ; day
    ucomiss xmm0, [k_c055]
    jb      .dusk
    ucomiss xmm0, [k_c095]
    jb      .night
    subss   xmm0, [k_c095]              ; dawn: 0.25 + (p - 0.95)/0.05 * 0.75
    mulss   xmm0, [k_c20]
    mulss   xmm0, [k_c075]
    addss   xmm0, [k_quarter]
    ret
.dusk:                                  ; 1 - (p - 0.45)/0.10 * 0.75
    subss   xmm0, [k_c045]
    mulss   xmm0, [k_c10]
    mulss   xmm0, [k_c075]
    subss   xmm1, xmm0
.ret1:
    movaps  xmm0, xmm1
    ret
.night:
    movss   xmm0, [k_quarter]
    ret

; sky_color(edi time, rsi out float[3]): rgb of the sky at that time
sky_color:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rsi                    ; out
    call    sky_brightness
    subss   xmm0, [k_quarter]
    mulss   xmm0, [k_inv_b]             ; t = (b - 0.25) / 0.75
    lea     rcx, [night_rgb]
    lea     rdx, [day_rgb]
    xor     eax, eax
.ch:
    movss   xmm1, [rdx + rax*4]
    movss   xmm2, [rcx + rax*4]
    subss   xmm1, xmm2
    mulss   xmm1, xmm0
    addss   xmm1, xmm2
    movss   [rbx + rax*4], xmm1
    inc     eax
    cmp     eax, 3
    jb      .ch
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; sky_angle(edi time) -> xmm0 degrees, 0..360
sky_angle:
    call    sky_phase
    mulss   xmm0, [k_deg]
    ret

; sky_is_night(edi time) -> eax 1 if brightness < 0.5
sky_is_night:
    sub     rsp, 8
    call    sky_brightness
    add     rsp, 8
    xor     eax, eax
    ucomiss xmm0, [k_half]
    setb    al
    ret
