; hud.asm - in-world overlay on top of the ui.asm toolkit: hurt flash, crosshair, hotbar,
; hearts, armor and food, held-item name and the F3 debug lines. GUI units; hud_draw runs
; after ui_begin. The hotbar sits at x0 = ui_w/2 - 91, y0 = ui_h - 22.
%include "common.inc"
%include "gl.inc"
default rel

global hud_draw, hud_dt

extern ui_w, ui_h, ui_rect, ui_frame, ui_text, ui_text_width, ui_text_centered
extern ui_item_icon, ui_icon9
extern game_mode, game_time, game_target, game_has_target
extern app_state, app_show_debug, app_fps
extern surv, inv, inv_sel, player, mob_count_kind, sky_brightness, world_get
extern item_names, item_durability, armor_points
extern str_append, i32_to_str, f32_to_str

%define WHITE   0xFFFFFFFF

section .rodata
align 4
f_one:      dd 1.0
f_two:      dd 2.0
f_255:      dd 255.0
f_100:      dd 100.0
s_dbg_title: db "AssemblyCraft 0.3  ", 0
s_dbg_fps:  db " fps", 0
s_xyz:      db "XYZ: ", 0
s_sep:      db " / ", 0
s_facing:   db "Facing: yaw ", 0
s_pitch:    db " pitch ", 0
s_target:   db "Target: ", 0
s_none:     db "Target: none", 0
s_at:       db " at ", 0
s_space:    db " ", 0
s_mode:     db "Mode: ", 0
s_survival: db "Survival", 0
s_creative: db "Creative", 0
s_day:      db "  Day ", 0
s_colon:    db ":", 0
s_mobs:     db "Mobs: ", 0
s_hostile:  db " hostile, ", 0
s_passive:  db " passive", 0
s_light:    db "Light: ", 0
s_percent:  db "%", 0
s_health:   db "Health ", 0
s_food:     db "/20  Food ", 0
s_sat:      db "/20  Sat ", 0

section .data
align 4
last_sel:   dd -1                       ; hotbar slot and held id of the last frame
last_id:    dd -1

section .bss
alignb 4
hud_dt:     resd 1                      ; frame time in seconds, written by the app before hud_draw
name_timer: resd 1                      ; seconds left to show the held item's name
dbg_buf:    resb 128

section .text

; hud_draw(): everything the player sees on top of the world
hud_draw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, [ui_w]
    shr     ebx, 1
    sub     ebx, 91                     ; x0
    mov     r12d, [ui_h]
    sub     r12d, 22                    ; y0
    call    hud_flash
    call    hud_crosshair
    mov     edi, ebx
    mov     esi, r12d
    call    hud_hotbar
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .no_bars
    mov     edi, ebx
    mov     esi, r12d
    call    hud_bars
.no_bars:
    mov     edi, ebx
    mov     esi, r12d
    call    hud_held_name
    cmp     dword [app_show_debug], 0
    je      .ret
    call    hud_debug
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_flash(): red full-screen flash while the player is hurt (survival)
hud_flash:
    sub     rsp, 8
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .ret
    mov     eax, [surv + SURVIVAL.hurt_flash]
    test    eax, eax
    jle     .ret
    imul    eax, eax, 90
    xor     edx, edx
    mov     ecx, 20
    div     ecx                         ; alpha = hurt_flash * 90 / 20
    shl     eax, 24
    or      eax, 255                    ; RGBA(255, 0, 0, alpha)
    mov     r8d, eax
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    call    ui_rect
.ret:
    add     rsp, 8
    ret

; hud_crosshair(): a colour-inverting cross at the screen centre while playing
hud_crosshair:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    cmp     dword [app_state], ST_PLAYING
    jne     .ret
    mov     ebx, [ui_w]
    shr     ebx, 1                      ; cx
    mov     r12d, [ui_h]
    shr     r12d, 1                     ; cy
    mov     edi, GL_ONE_MINUS_DST_COLOR
    mov     esi, GL_ZERO
    call    glBlendFunc
    lea     edi, [rbx - 5]
    mov     esi, r12d
    mov     edx, 11
    mov     ecx, 1
    mov     r8d, WHITE
    call    ui_rect
    mov     edi, ebx
    lea     esi, [r12 - 5]
    mov     edx, 1
    mov     ecx, 5
    mov     r8d, WHITE
    call    ui_rect
    mov     edi, ebx
    lea     esi, [r12 + 1]
    mov     edx, 1
    mov     ecx, 5
    mov     r8d, WHITE
    call    ui_rect
    mov     edi, GL_SRC_ALPHA
    mov     esi, GL_ONE_MINUS_SRC_ALPHA
    call    glBlendFunc
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_durability(rdi stack, esi x, edx y): damage bar of a tool at the slot's icon (x, y)
hud_durability:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8                      ; [rsp] filled width
    movzx   eax, byte [rdi + ITEMSTACK.id]
    cmp     eax, NUM_ITEMS
    jae     .ret
    movzx   ecx, word [item_durability + rax*2]
    movzx   r8d, word [rdi + ITEMSTACK.dmg]
    test    ecx, ecx
    jz      .ret
    test    r8d, r8d
    jz      .ret
    cmp     r8d, ecx
    cmova   r8d, ecx                    ; damage never exceeds the durability
    lea     ebx, [rsi + 2]              ; bar x
    lea     r12d, [rdx + 14]            ; bar y
    mov     eax, ecx
    sub     eax, r8d
    imul    eax, 14
    xor     edx, edx
    div     ecx
    mov     [rsp], eax                  ; width = 14 * (dur - dmg) / dur
    mov     eax, r8d
    imul    eax, 255
    xor     edx, edx
    div     ecx
    mov     r13d, 255
    sub     r13d, eax
    shl     r13d, 8
    or      r13d, eax
    or      r13d, 0xFF000000            ; RGBA(255 * dmg / dur, 255 - that, 0, 255)
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 14
    mov     ecx, 2
    mov     r8d, RGBA(0, 0, 0, 255)
    call    ui_rect
    mov     edx, [rsp]
    test    edx, edx
    jz      .ret
    mov     edi, ebx
    mov     esi, r12d
    mov     ecx, 2
    mov     r8d, r13d
    call    ui_rect
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_hotbar(edi x0, esi y0): background, the nine slots, selection frame
; r12d = x0, r13d = y0, ebx = slot, r14 = stack, r15d = icon x; [rsp] count text
hud_hotbar:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     r12d, edi
    mov     r13d, esi
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, 182
    mov     ecx, 22
    mov     r8d, RGBA(0, 0, 0, 115)
    call    ui_rect
    xor     ebx, ebx
.slot:
    lea     r14, [inv + rbx*4]
    cmp     byte [r14 + ITEMSTACK.count], 0
    je      .next
    imul    r15d, ebx, 20
    lea     r15d, [r15 + r12 + 3]       ; icon x = x0 + 3 + 20 * slot
    movzx   edi, byte [r14 + ITEMSTACK.id]
    mov     esi, r15d
    lea     edx, [r13 + 3]
    mov     ecx, 16
    call    ui_item_icon
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .next
    mov     rdi, r14
    mov     esi, r15d
    lea     edx, [r13 + 3]
    call    hud_durability
    movzx   edi, byte [r14 + ITEMSTACK.count]
    cmp     edi, 1
    jbe     .next
    mov     rsi, rsp
    call    i32_to_str
    mov     byte [rax], 0
    mov     rdi, rsp
    mov     esi, 1
    call    ui_text_width
    lea     esi, [r15 + 17]
    sub     esi, eax                    ; right-aligned, ending at icon x + 17
    mov     rdi, rsp
    lea     edx, [r13 + 12]
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
.next:
    inc     ebx
    cmp     ebx, HOTBAR_SLOTS
    jb      .slot
    imul    edi, [inv_sel], 20
    add     edi, r12d
    mov     esi, r13d
    mov     edx, 22
    mov     ecx, 22
    mov     r8d, WHITE
    call    ui_frame
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; bar_tile(edi value, esi full tile) -> eax tile: full for >= 2, half for 1, else empty
bar_tile:
    mov     eax, esi
    cmp     edi, 2
    jge     .ret
    inc     eax
    cmp     edi, 1
    je      .ret
    inc     eax
.ret:
    ret

; hud_bars(edi x0, esi y0): ten hearts from the left, ten food icons from the right
hud_bars:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12d, edi
    lea     r13d, [rsi - 10]            ; icon row
    call    armor_points
    mov     [rsp], eax
    xor     ebx, ebx
.i:
    mov     edi, [surv + SURVIVAL.health]
    lea     eax, [rbx + rbx]
    sub     edi, eax                    ; hearts left for this icon
    mov     esi, TILE_HEART_FULL
    call    bar_tile
    mov     edi, eax
    lea     esi, [r12 + rbx*8]
    mov     edx, r13d
    call    ui_icon9
    mov     edi, [surv + SURVIVAL.food]
    lea     eax, [rbx + rbx]
    sub     edi, eax
    mov     esi, TILE_FOOD_FULL
    call    bar_tile
    mov     edi, eax
    mov     esi, 173                    ; x0 + 182 - 9 - 8 * i
    lea     eax, [rbx*8]
    sub     esi, eax
    add     esi, r12d
    mov     edx, r13d
    call    ui_icon9
    inc     ebx
    cmp     ebx, 10
    jb      .i
    cmp     dword [rsp], 0              ; armor row above the hearts, when worn
    je      .done
    xor     ebx, ebx
.armor:
    mov     edi, [rsp]
    lea     eax, [rbx + rbx]
    sub     edi, eax
    mov     esi, TILE_ARMOR_FULL
    call    bar_tile
    mov     edi, eax
    lea     esi, [r12 + rbx*8]
    lea     edx, [r13 - 10]
    call    ui_icon9
    inc     ebx
    cmp     ebx, 10
    jb      .armor
.done:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_held_name(edi x0, esi y0): the held item's name above the bar, fading out
hud_held_name:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12d, esi
    mov     eax, [inv_sel]
    lea     rcx, [inv + rax*4]
    movzx   ebx, byte [rcx + ITEMSTACK.id]
    cmp     byte [rcx + ITEMSTACK.count], 0
    jne     .have
    xor     ebx, ebx                    ; an empty stack holds nothing
.have:
    cmp     eax, [last_sel]
    jne     .changed
    cmp     ebx, [last_id]
    je      .shown
.changed:
    mov     [last_sel], eax
    mov     [last_id], ebx
    movss   xmm0, [f_two]
    movss   [name_timer], xmm0
.shown:
    movss   xmm0, [name_timer]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .ret
    subss   xmm0, [hud_dt]
    movss   [name_timer], xmm0
    comiss  xmm0, xmm1
    jbe     .ret
    test    ebx, ebx
    jz      .ret
    cmp     ebx, NUM_ITEMS
    jae     .ret
    mulss   xmm0, [f_two]               ; timer / 0.5
    minss   xmm0, [f_one]
    mulss   xmm0, [f_255]
    cvttss2si ecx, xmm0                 ; alpha = min(1, timer / 0.5) * 255
    shl     ecx, 24
    or      ecx, 0x00FFFFFF
    mov     edx, r12d
    sub     edx, 12                     ; just above the bar in creative,
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .row
    sub     edx, 12                     ; above the hearts in survival,
    push    rcx
    push    rdx
    call    armor_points
    pop     rdx
    pop     rcx
    test    eax, eax
    jz      .row
    sub     edx, 10                     ; and above the armor row when it shows
.row:
    lea     rax, [item_names]
    mov     rdi, [rax + rbx*8]
    mov     esi, [ui_w]
    shr     esi, 1
    mov     r8d, 1
    call    ui_text_centered
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; put2(edi value 0..99, rsi buf) -> rax past the two digits
put2:
    mov     eax, edi
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    add     al, '0'
    add     dl, '0'
    mov     [rsi], al
    mov     [rsi + 1], dl
    lea     rax, [rsi + 2]
    ret

; debug_emit(rdi end of the text in dbg_buf, esi line): draw dbg_buf as line number esi
debug_emit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     byte [rdi], 0
    mov     r12d, esi
    lea     rbx, [dbg_buf]
    mov     rdi, rbx
    mov     esi, 1
    call    ui_text_width
    mov     r13d, eax
    lea     esi, [r12 + r12*4]
    add     esi, esi
    inc     esi                         ; background y = 1 + 10 * line
    mov     edi, 1
    lea     edx, [r13 + 2]
    mov     ecx, 10
    mov     r8d, RGBA(0, 0, 0, 96)
    call    ui_rect
    mov     rdi, rbx
    mov     esi, 2
    lea     edx, [r12 + r12*4]
    add     edx, edx
    add     edx, 2                      ; text y = 2 + 10 * line
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; text builders: rbx is the write cursor into dbg_buf
%macro APPEND_STR 1
    mov     rdi, rbx
    lea     rsi, [%1]
    call    str_append
    mov     rbx, rax
%endmacro
%macro APPEND_INT 1                     ; 32-bit memory operand
    mov     edi, %1
    mov     rsi, rbx
    call    i32_to_str
    mov     rbx, rax
%endmacro
%macro APPEND_EAX 0
    mov     edi, eax
    mov     rsi, rbx
    call    i32_to_str
    mov     rbx, rax
%endmacro
%macro APPEND_F32 2                     ; float memory operand, decimals
    movss   xmm0, %1
    mov     rdi, rbx
    mov     esi, %2
    call    f32_to_str
    mov     rbx, rax
%endmacro
%macro EMIT 0                           ; draw the finished line, start the next one
    mov     rdi, rbx
    mov     esi, r12d
    call    debug_emit
    inc     r12d
    lea     rbx, [dbg_buf]
%endmacro

; hud_debug(): the F3 lines. rbx = write cursor, r12d = line;
; stack: [rsp] day, [rsp+4] hour, [rsp+8] minute
hud_debug:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    xor     r12d, r12d
    lea     rbx, [dbg_buf]

    APPEND_STR s_dbg_title
    APPEND_INT [app_fps]
    APPEND_STR s_dbg_fps
    EMIT

    APPEND_STR s_xyz
    APPEND_F32 [player + BODY.x], 2
    APPEND_STR s_sep
    APPEND_F32 [player + BODY.y], 2
    APPEND_STR s_sep
    APPEND_F32 [player + BODY.z], 2
    EMIT

    APPEND_STR s_facing
    cvttss2si eax, [player + BODY.yaw]
    APPEND_EAX
    APPEND_STR s_pitch
    cvttss2si eax, [player + BODY.pitch]
    APPEND_EAX
    EMIT

    cmp     dword [game_has_target], 0
    jne     .has_target
    APPEND_STR s_none
    jmp     .target_done
.has_target:
    APPEND_STR s_target
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    call    world_get
    cmp     eax, NUM_ITEMS
    jb      .named
    xor     eax, eax
.named:
    lea     rcx, [item_names]
    mov     rsi, [rcx + rax*8]
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
    APPEND_STR s_at
    APPEND_INT [game_target + RAYHIT.bx]
    APPEND_STR s_space
    APPEND_INT [game_target + RAYHIT.by]
    APPEND_STR s_space
    APPEND_INT [game_target + RAYHIT.bz]
.target_done:
    EMIT

    mov     eax, [game_time]            ; day number, and the clock: the day starts at 06:00
    xor     edx, edx
    mov     ecx, DAY_LENGTH
    div     ecx
    inc     eax
    mov     [rsp], eax
    mov     eax, edx
    xor     edx, edx
    mov     ecx, 50                     ; 72000 steps = 1440 minutes
    div     ecx
    xor     edx, edx
    mov     ecx, 60
    div     ecx
    mov     [rsp + 8], edx              ; minute
    add     eax, 6
    cmp     eax, 24
    jb      .hour_ok
    sub     eax, 24
.hour_ok:
    mov     [rsp + 4], eax              ; hour
    APPEND_STR s_mode
    lea     rsi, [s_survival]
    lea     rax, [s_creative]
    cmp     dword [game_mode], MODE_SURVIVAL
    cmovne  rsi, rax
    mov     rdi, rbx
    call    str_append
    mov     rbx, rax
    APPEND_STR s_day
    APPEND_INT [rsp]
    APPEND_STR s_space
    mov     edi, [rsp + 4]
    mov     rsi, rbx
    call    put2
    mov     rbx, rax
    APPEND_STR s_colon
    mov     edi, [rsp + 8]
    mov     rsi, rbx
    call    put2
    mov     rbx, rax
    EMIT

    APPEND_STR s_mobs
    mov     edi, 1
    call    mob_count_kind
    APPEND_EAX
    APPEND_STR s_hostile
    xor     edi, edi
    call    mob_count_kind
    APPEND_EAX
    APPEND_STR s_passive
    EMIT

    APPEND_STR s_light
    mov     edi, [game_time]
    call    sky_brightness
    mulss   xmm0, [f_100]
    cvttss2si eax, xmm0
    APPEND_EAX
    APPEND_STR s_percent
    EMIT

    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .ret
    APPEND_STR s_health
    APPEND_INT [surv + SURVIVAL.health]
    APPEND_STR s_food
    APPEND_INT [surv + SURVIVAL.food]
    APPEND_STR s_sat
    APPEND_F32 [surv + SURVIVAL.saturation], 1
    EMIT
.ret:
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
