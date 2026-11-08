; test_hud.asm - the HUD's anchor in the world (world_to_ui) and the floating combat text (dmgnum).
%include "common.inc"
default rel

global test_world_to_ui_centres_forward, test_dmgnum_rises_and_expires

extern world_clear, player, body_init, player_eye, player_forward
extern settings, game_aim, ui_w, ui_h, world_to_ui
extern dmgnum_clear, dmgnum_spawn, dmgnum_text, dmgnum_step, dmgnum_count, dmgnum_list

; layout of one dmgnum_list entry (struc DMGNUM in dmgnum.asm)
%define DN_Y        4
%define DN_VALUE    20
%define DN_SIZE     24

section .rodata
align 4
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_16_5:   dd 16.5
k_10:     dd 10.0
k_35:     dd 35.0
k_12:     dd 12.0
k_5:      dd 5.0
k_m5:     dd -5.0
k_3:      dd 3.0
k_m3:     dd -3.0
k_2:      dd 2.0
k_m2:     dd -2.0
k_0:      dd 0.0
k_pt05:   dd 0.05
k_pt15:   dd 0.15
k_one:    dd 1.0

section .bss
alignb 4
t_eye:  resd 3
t_fwd:  resd 3
t_p:    resd 3
t_out:  resd 2                          ; world_to_ui result of the last t_project

section .text

; t_project(xmm0 dx, xmm1 dy, xmm2 dz) -> eax world_to_ui of eye + (dx, dy, dz); t_out = the pixel
t_project:
    sub     rsp, 24
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    lea     rdi, [t_eye]
    call    player_eye
    movss   xmm0, [t_eye]
    addss   xmm0, [rsp]
    movss   [t_p], xmm0
    movss   xmm0, [t_eye + 4]
    addss   xmm0, [rsp + 4]
    movss   [t_p + 4], xmm0
    movss   xmm0, [t_eye + 8]
    addss   xmm0, [rsp + 8]
    movss   [t_p + 8], xmm0
    lea     rdi, [t_p]
    lea     rsi, [t_out]
    call    world_to_ui
    add     rsp, 24
    ret

; test_world_to_ui_centres_forward: on a 320 x 240 screen with fov 70, yaw 35 and pitch 12 the point
; 5 blocks along player_forward lands at the centre (+-1), one behind the eye is not shown, a point
; to the right of the view lands right of the centre on the same row. With yaw 0 and pitch 0 a point
; at +x lands right of the centre (x = 263 for (3, 0, -5)), at -x left, above the line of sight
; higher on the screen (smaller y), below it lower; aiming down the sights (game_aim = 1) narrows the
; field of view, so the same point moves further out.
test_world_to_ui_centres_forward:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16                     ; [rsp] the caller's ui_w, ui_h, fov, game_aim
    call    world_clear
    mov     eax, [ui_w]
    mov     [rsp], eax
    mov     eax, [ui_h]
    mov     [rsp + 4], eax
    mov     eax, [settings + SETTINGS.fov]
    mov     [rsp + 8], eax
    mov     eax, [game_aim]
    mov     [rsp + 12], eax
    mov     dword [ui_w], 320
    mov     dword [ui_h], 240
    mov     dword [settings + SETTINGS.fov], 70
    mov     dword [game_aim], 0
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    movss   xmm0, [k_16_5]
    movss   [player + BODY.x], xmm0
    movss   xmm0, [k_10]
    movss   [player + BODY.y], xmm0
    movss   xmm0, [k_16_5]
    movss   [player + BODY.z], xmm0
    movss   xmm0, [k_35]
    movss   [player + BODY.yaw], xmm0
    movss   xmm0, [k_12]
    movss   [player + BODY.pitch], xmm0
    lea     rdi, [t_fwd]
    call    player_forward

    ; 5 blocks straight ahead: the screen centre
    movss   xmm3, [k_5]
    movss   xmm0, [t_fwd]
    mulss   xmm0, xmm3
    movss   xmm1, [t_fwd + 4]
    mulss   xmm1, xmm3
    movss   xmm2, [t_fwd + 8]
    mulss   xmm2, xmm3
    call    t_project
    cmp     eax, 1
    jne     .fail1
    mov     eax, [t_out]
    sub     eax, 160 - 1
    cmp     eax, 2
    ja      .fail2                      ; |x - 160| <= 1
    mov     eax, [t_out + 4]
    sub     eax, 120 - 1
    cmp     eax, 2
    ja      .fail2                      ; |y - 120| <= 1

    ; 5 blocks straight behind: not in front of the camera
    movss   xmm3, [k_m5]
    movss   xmm0, [t_fwd]
    mulss   xmm0, xmm3
    movss   xmm1, [t_fwd + 4]
    mulss   xmm1, xmm3
    movss   xmm2, [t_fwd + 8]
    mulss   xmm2, xmm3
    call    t_project
    test    eax, eax
    jnz     .fail3

    ; 5 ahead and 2 to the right, right = (-forward.z, 0, forward.x): right of the centre, same row
    movss   xmm0, [t_fwd + 8]
    mulss   xmm0, [k_m2]
    movss   xmm3, [t_fwd]
    mulss   xmm3, [k_5]
    addss   xmm0, xmm3                  ; dx = 5 fx - 2 fz
    movss   xmm1, [t_fwd + 4]
    mulss   xmm1, [k_5]                 ; dy = 5 fy
    movss   xmm2, [t_fwd]
    mulss   xmm2, [k_2]
    movss   xmm3, [t_fwd + 8]
    mulss   xmm3, [k_5]
    addss   xmm2, xmm3                  ; dz = 2 fx + 5 fz
    call    t_project
    cmp     eax, 1
    jne     .fail4
    cmp     dword [t_out], 160
    jle     .fail4
    mov     eax, [t_out + 4]
    sub     eax, 120 - 1
    cmp     eax, 2
    ja      .fail4

    ; yaw 0, pitch 0: the view runs along -z, +x is to the right
    mov     dword [player + BODY.yaw], 0
    mov     dword [player + BODY.pitch], 0
    movss   xmm0, [k_3]
    xorps   xmm1, xmm1
    movss   xmm2, [k_m5]
    call    t_project
    cmp     eax, 1
    jne     .fail5
    mov     r13d, [t_out]               ; x without aiming
    lea     eax, [r13 - 263 + 1]
    cmp     eax, 2
    ja      .fail5                      ; 160 + (3 / 5) / tan 35 * 120 = 262.8
    mov     eax, [t_out + 4]
    sub     eax, 120 - 1
    cmp     eax, 2
    ja      .fail5
    movss   xmm0, [k_m3]
    xorps   xmm1, xmm1
    movss   xmm2, [k_m5]
    call    t_project
    cmp     eax, 1
    jne     .fail5
    cmp     dword [t_out], 160
    jge     .fail5
    xorps   xmm0, xmm0
    movss   xmm1, [k_2]
    movss   xmm2, [k_m5]
    call    t_project
    cmp     eax, 1
    jne     .fail5
    cmp     dword [t_out + 4], 120
    jge     .fail5                      ; above the line of sight: smaller y
    xorps   xmm0, xmm0
    movss   xmm1, [k_m2]
    movss   xmm2, [k_m5]
    call    t_project
    cmp     eax, 1
    jne     .fail5
    cmp     dword [t_out + 4], 120
    jle     .fail5

    ; down the sights the field of view shrinks 30 %: the same point lies further out
    movss   xmm0, [k_one]
    movss   [game_aim], xmm0
    movss   xmm0, [k_3]
    xorps   xmm1, xmm1
    movss   xmm2, [k_m5]
    call    t_project
    cmp     eax, 1
    jne     .fail6
    cmp     dword [t_out], r13d
    jle     .fail6
    xor     eax, eax
    jmp     .out
.fail1:
    mov     eax, 1
    jmp     .out
.fail2:
    mov     eax, 2
    jmp     .out
.fail3:
    mov     eax, 3
    jmp     .out
.fail4:
    mov     eax, 4
    jmp     .out
.fail5:
    mov     eax, 5
    jmp     .out
.fail6:
    mov     eax, 6
.out:
    mov     ebx, eax
    mov     eax, [rsp]
    mov     [ui_w], eax
    mov     eax, [rsp + 4]
    mov     [ui_h], eax
    mov     eax, [rsp + 8]
    mov     [settings + SETTINGS.fov], eax
    mov     eax, [rsp + 12]
    mov     [game_aim], eax
    mov     eax, ebx
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; test_dmgnum_rises_and_expires: a number rises 0.01 per step (0.6 blocks/s), is still there after
; 49 steps and gone after the 50th; a word (TXT_PARRY) lives as long, an unknown word id is ignored;
; with all 32 entries taken a new one replaces the oldest instead of being dropped.
test_dmgnum_rises_and_expires:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16                     ; [rsp] float y at spawn
    call    world_clear
    call    dmgnum_clear
    call    dmgnum_count
    test    eax, eax
    jnz     .fail1
    movss   xmm0, [k_5]
    movss   xmm1, [k_10]
    movss   xmm2, [k_5]
    mov     edi, 7
    xor     esi, esi
    call    dmgnum_spawn
    call    dmgnum_count
    cmp     eax, 1
    jne     .fail2
    movss   xmm0, [dmgnum_list + DN_Y]
    movss   [rsp], xmm0
    mov     ebx, 10
.rise:
    call    dmgnum_step
    dec     ebx
    jnz     .rise
    movss   xmm0, [dmgnum_list + DN_Y]
    subss   xmm0, [rsp]                 ; 10 steps * 0.01
    comiss  xmm0, [k_pt05]
    jbe     .fail3
    comiss  xmm0, [k_pt15]
    jae     .fail3
    mov     ebx, 39
.age:
    call    dmgnum_step
    dec     ebx
    jnz     .age
    call    dmgnum_count                ; 49 steps old
    cmp     eax, 1
    jne     .fail4
    call    dmgnum_step
    call    dmgnum_count                ; the 50th step frees it
    test    eax, eax
    jnz     .fail5

    movss   xmm0, [k_5]
    movss   xmm1, [k_10]
    movss   xmm2, [k_5]
    mov     edi, TXT_PARRY
    call    dmgnum_text
    movss   xmm0, [k_5]
    movss   xmm1, [k_10]
    movss   xmm2, [k_5]
    mov     edi, 9
    call    dmgnum_text                 ; not a word: ignored
    call    dmgnum_count
    cmp     eax, 1
    jne     .fail6
    mov     ebx, 49
.word_age:
    call    dmgnum_step
    dec     ebx
    jnz     .word_age
    call    dmgnum_count
    cmp     eax, 1
    jne     .fail6
    call    dmgnum_step
    call    dmgnum_count
    test    eax, eax
    jnz     .fail6

    ; fill all 32 entries, one step apart so the first is the oldest, then add a 33rd
    xor     ebx, ebx
.fill:
    inc     ebx
    movss   xmm0, [k_5]
    movss   xmm1, [k_10]
    movss   xmm2, [k_5]
    mov     edi, ebx
    xor     esi, esi
    call    dmgnum_spawn
    cmp     ebx, 32
    jae     .full
    call    dmgnum_step
    jmp     .fill
.full:
    call    dmgnum_count
    cmp     eax, 32
    jne     .fail7
    movss   xmm0, [k_5]
    movss   xmm1, [k_10]
    movss   xmm2, [k_5]
    mov     edi, 99
    mov     esi, HF_CRIT
    call    dmgnum_spawn
    call    dmgnum_count
    cmp     eax, 32
    jne     .fail7
    cmp     dword [dmgnum_list + DN_VALUE], 99
    jne     .fail7                      ; the oldest (amount 1) was replaced
    cmp     dword [dmgnum_list + DN_SIZE + DN_VALUE], 2
    jne     .fail7
    xor     eax, eax
    jmp     .out
.fail1:
    mov     eax, 1
    jmp     .out
.fail2:
    mov     eax, 2
    jmp     .out
.fail3:
    mov     eax, 3
    jmp     .out
.fail4:
    mov     eax, 4
    jmp     .out
.fail5:
    mov     eax, 5
    jmp     .out
.fail6:
    mov     eax, 6
    jmp     .out
.fail7:
    mov     eax, 7
.out:
    mov     ebx, eax
    call    dmgnum_clear
    mov     eax, ebx
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret
