; test_hud.asm - the HUD's anchor in the world (world_to_ui), the floating combat text (dmgnum: rise,
; expiry, colour / size / alpha by element, crit and DoT, the new words) and the heart levels.
%include "common.inc"
default rel

global test_world_to_ui_centres_forward, test_dmgnum_rises_and_expires

extern world_clear, player, body_init, player_eye, player_forward
extern settings, game_aim, ui_w, ui_h, world_to_ui
extern dmgnum_clear, dmgnum_spawn, dmgnum_text, dmgnum_step, dmgnum_count, dmgnum_list, dmgnum_style
extern hud_heart_level, hud_ability_pos

; layout of one dmgnum_list entry (struc DMGNUM in dmgnum.asm)
%define DN_Y        4
%define DN_VALUE    20
%define DN_SIZE     28

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

; dmgnum_style cases: flags passed to dmgnum_spawn, expected rgb (alpha 0), scale, alpha cap
%define STYLE_ROWS 11
style_rows:
    dd 0, RGBA(255, 255, 255, 0), 1, 255                                ; plain physical: white
    dd 1 << HF_ELEM_SHIFT, RGBA(255, 140, 40, 0), 1, 255                ; fire
    dd (2 << HF_ELEM_SHIFT) | HF_CRIT, RGBA(130, 200, 255, 0), 2, 255   ; frost crit: frost colour, big
    dd 3 << HF_ELEM_SHIFT, RGBA(255, 240, 90, 0), 1, 255                ; shock
    dd 4 << HF_ELEM_SHIFT, RGBA(120, 220, 80, 0), 1, 255                ; poison
    dd HF_CRIT, RGBA(255, 220, 60, 0), 2, 255                           ; physical crit: gold
    dd HF_DOT, RGBA(220, 50, 50, 0), 1, 217                             ; bleed tick: red, 85%
    dd HF_DOT | (1 << HF_ELEM_SHIFT), RGBA(255, 140, 40, 0), 1, 217    ; burn tick
    dd HF_DOT | HF_CRIT | (4 << HF_ELEM_SHIFT), RGBA(120, 220, 80, 0), 1, 217   ; a DoT never grows
    dd 7 << HF_ELEM_SHIFT, RGBA(255, 255, 255, 0), 1, 255               ; unknown element: physical
    dd HF_PLAYER | (2 << HF_ELEM_SHIFT), RGBA(130, 200, 255, 0), 1, 255 ; other flag bits do not matter

; word cases: TXT_* id, expected rgb, scale
%define WORD_ROWS 6
word_rows:
    dd TXT_PARRY, RGBA(255, 215, 0, 0), 2
    dd TXT_BLOCKED, RGBA(180, 180, 200, 0), 1
    dd TXT_DODGED, RGBA(150, 220, 255, 0), 1
    dd TXT_STUNNED, RGBA(255, 160, 60, 0), 1
    dd TXT_FROZEN, RGBA(130, 200, 255, 0), 1
    dd TXT_IMMUNE, RGBA(200, 200, 200, 0), 1

%define ABILITY_ROWS 5

; hud_ability_pos cases: x0, y0, top of the left stack -> slot 0 x, y, above the stack
ability_rows:
    dd 149, 218, 203, 56, 219, 0
    dd 69, 218, 203, 69, 181, 1
    dd 95, 218, 203, 2, 219, 0
    dd 94, 218, 203, 94, 181, 1
    dd 79, 218, 187, 79, 165, 1

; hud_heart_level cases: heart index, health, max health, expected 2 full / 1 half / 0 empty
%define HEART_ROWS 14
heart_rows:
    dd 0, 2, 20, 2
    dd 0, 1, 20, 1
    dd 0, 0, 20, 0
    dd 4, 9, 20, 1
    dd 4, 10, 20, 2
    dd 0, 1, 10, 2
    dd 9, 10, 10, 2
    dd 9, 9, 10, 0
    dd 2, 25, 100, 1
    dd 2, 30, 100, 2
    dd 2, 24, 100, 0
    dd 1, 5, 40, 0
    dd 1, 6, 40, 1
    dd 9, 44, 44, 2

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
    call    check_dmgnum_styles
    test    eax, eax
    jnz     .out
    call    check_heart_levels
    test    eax, eax
    jnz     .out
    call    check_ability_pos
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

; check_dmgnum_styles() -> eax 0, else 100 + the failing style row, 200 + the failing word row, or 300
; (an unknown word id was not ignored)
; ebx = row, r12 = row pointer
check_dmgnum_styles:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    call    dmgnum_clear
    xor     ebx, ebx
.row:
    cmp     ebx, STYLE_ROWS
    jae     .words
    imul    eax, ebx, 16
    lea     r12, [style_rows]
    add     r12, rax
    movss   xmm0, [k_5]
    movss   xmm1, [k_10]
    movss   xmm2, [k_5]
    mov     edi, ebx
    mov     esi, [r12]
    call    dmgnum_spawn
    imul    eax, ebx, DN_SIZE
    lea     rdi, [dmgnum_list]
    add     rdi, rax                    ; spawn order = slot order in a cleared list
    call    dmgnum_style
    cmp     eax, [r12 + 4]
    jne     .bad_row
    cmp     edx, [r12 + 8]
    jne     .bad_row
    cmp     ecx, [r12 + 12]
    jne     .bad_row
    inc     ebx
    jmp     .row
.bad_row:
    lea     eax, [rbx + 100]
    jmp     .ret
.words:
    call    dmgnum_clear
    xor     ebx, ebx
.word:
    cmp     ebx, WORD_ROWS
    jae     .unknown
    imul    eax, ebx, 12
    lea     r12, [word_rows]
    add     r12, rax
    movss   xmm0, [k_5]
    movss   xmm1, [k_10]
    movss   xmm2, [k_5]
    mov     edi, [r12]
    call    dmgnum_text
    imul    eax, ebx, DN_SIZE
    lea     rdi, [dmgnum_list]
    add     rdi, rax
    call    dmgnum_style
    cmp     eax, [r12 + 4]
    jne     .bad_word
    cmp     edx, [r12 + 8]
    jne     .bad_word
    cmp     ecx, 255
    jne     .bad_word
    inc     ebx
    jmp     .word
.bad_word:
    lea     eax, [rbx + 200]
    jmp     .ret
.unknown:
    movss   xmm0, [k_5]
    movss   xmm1, [k_10]
    movss   xmm2, [k_5]
    mov     edi, TXT_IMMUNE + 1
    call    dmgnum_text                 ; one past the last word: ignored
    call    dmgnum_count
    cmp     eax, WORD_ROWS
    mov     eax, 300
    jne     .ret
    xor     eax, eax
.ret:
    mov     ebx, eax
    call    dmgnum_clear
    mov     eax, ebx
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; check_ability_pos() -> eax 0, else 500 + the failing ability_rows row
; hud_ability_pos puts the four slots left of the hotbar while that fits on screen (x0 - 93 >= 2),
; else in a row 2 over the left stack: GUI widths 480, 320 (x0 69 would start at -24), the exact
; edge, one under it and 341 with a tall stack
check_ability_pos:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    xor     ebx, ebx
.row:
    cmp     ebx, ABILITY_ROWS
    jae     .ok
    imul    eax, ebx, 24
    lea     r12, [ability_rows]
    add     r12, rax
    mov     edi, [r12]
    mov     esi, [r12 + 4]
    mov     edx, [r12 + 8]
    call    hud_ability_pos
    cmp     eax, [r12 + 12]
    jne     .bad
    cmp     edx, [r12 + 16]
    jne     .bad
    cmp     ecx, [r12 + 20]
    jne     .bad
    inc     ebx
    jmp     .row
.bad:
    lea     eax, [rbx + 500]
    jmp     .ret
.ok:
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; check_heart_levels() -> eax 0, else 400 + the failing heart_rows row
; ebx = row, r12 = row pointer
check_heart_levels:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    xor     ebx, ebx
.row:
    cmp     ebx, HEART_ROWS
    jae     .ok
    imul    eax, ebx, 16
    lea     r12, [heart_rows]
    add     r12, rax
    mov     edi, [r12]
    mov     esi, [r12 + 4]
    mov     edx, [r12 + 8]
    call    hud_heart_level
    cmp     eax, [r12 + 12]
    jne     .bad
    inc     ebx
    jmp     .row
.bad:
    lea     eax, [rbx + 400]
    jmp     .ret
.ok:
    xor     eax, eax
.ret:
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret
