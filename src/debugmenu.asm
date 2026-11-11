; debugmenu.asm - the debug menu and the cheater mark (0.10.5).
;
; F12 pressed three times, at most DEBUG_GAP_STEPS fixed steps (1.0 s) between presses, opens the menu while
; playing (debug_poll from app.asm's ST_PLAYING branch reads the key presses; debug_step, from the fixed step,
; is its clock). Any other key or a longer gap starts the count over. The first opening in a world sets
; WORLDHDR.cheater (never cleared by the game), which the world list, the HUD and the F3 overlay show.
; The menu is the app state ST_DEBUG: the world does not step and the cursor is free. debug_frame is its
; screen, drawn in the grimoire look: a parchment page with four tabs.
;
;   Player   level, XP, skill and attribute points, full restore, god mode, fly, game mode, and a scrolling
;            list of every stat with a flat debug bonus (debug_stat_bonus, added by rpg_recompute after the
;            caps, saved in WORLDHDR.debug_stats)
;   Items    a name filter over every item, +1 / +16 / +64 of the selected one, the four gun attachments
;   Enemies  a type, a level, elite or not and a count spawn in front of the player; kill all, heal all; the events
;            (events.asm): a temporary camp, a free caravan, a threat on the nearest camp, skip a wave, win
;   World    time of day, teleport (X Y Z, spawn, bed), faction standing, reset cooldowns, clear drops
;
; Every action is a plain function below (debug_give, debug_spawn, ...) so that the selftests drive them
; without a screen; the screen only calls them. Text on parchment is ink without a shadow (ui_text_ink).
%include "common.inc"
%include "theme.inc"
%include "gl.inc"
default rel

global debug_open, debug_reset, debug_step, debug_press, debug_other_key, debug_poll, debug_close
global debug_is_cheater, debug_mark_cheater
global debug_give, debug_spawn, debug_kill_all, debug_heal_all
global debug_set_time, debug_add_time, debug_stat_range, debug_bonus_add
global debug_full_restore, debug_toggle_god, debug_toggle_fly, debug_toggle_mode
global debug_reset_cooldowns, debug_clear_drops
global debug_parse_int, debug_fill_coords, debug_go, debug_coord_fields, debug_to_spawn, debug_to_bed
global debug_item_nth, debug_item_count, debug_frame

extern world_header, player, world_origin_x, world_origin_z, game_time, game_mode
extern surv, surv_max_health, combat_refill
extern rpg_stats, rpg_state, rpg_stat_info, rpg_recompute, debug_stat_bonus
extern rpg_set_level, rpg_add_bonus_points, rpg_respec_free, rpg_points, rpg_attr_points, rpg_xp_need
extern inv_add_dmg, inv_count, drops_spawn, drops_clear
extern mobs, mob_spawn, mob_set_level, make_elite, mob_count_kind, mobs_clear
extern world_is_solid, world_get, world_column_ready, sincos_deg
extern abilities_cd, abilities_cd_total, abilities_bolt_cd
extern faction_standing, faction_tier, faction_add, faction_names, tier_names
extern game_teleport, app_wait_area, app_goto, audio_play, hud_dt
extern ui_input, ui_w, ui_h, ui_mx, ui_my, ui_focus
extern ui_rect, ui_frame, ui_panel, ui_nine, ui_ribbon
extern ui_text_ink, ui_text_ink_centered, ui_text_width, ui_textfield, ui_item_icon
extern item_names, item_max_stack, gun_index
extern str_append, str_copy, str_len, i32_to_str
extern events_status, events_spawn_camp, events_spawn_caravan, events_force_threat, events_skip, events_finish
extern structures_nearest
extern net_role

%define DEBUG_GAP_STEPS   60            ; F12 presses at most this many fixed steps apart (1.0 s)
%define DEBUG_COORD_MAX   16000000      ; a teleport target stays within this on x and z
%define DEBUG_HOUR        3000          ; steps in one hour of the day (DAY_LENGTH / 24)
; moments of the day in steps from the start of the 72000-step day, which starts at 06:00: noon is 12:00, dusk
; 18:00 and midnight 00:00, each in the middle of its sky phase (sky.asm), dawn the middle of the sunrise (05:24)
%define DEBUG_DAWN        70200
%define DEBUG_NOON        18000
%define DEBUG_DUSK        36000
%define DEBUG_MIDNIGHT    54000
%define DEBUG_NOTE_FRAMES 300           ; the footer line stays this many frames
%define DEBUG_SPAWN_MAX   15            ; mobs one spawn can place (the rows of spawn_pattern)

section .rodata
align 4
k_step:       dd 0.016666668            ; one fixed step, seconds
k_row0:       dd 4.5                    ; spawn: the nearest row's distance in front of the player
k_row_step:   dd 1.5
k_lane_step:  dd 1.6
k_half:       dd 0.5
k_drop_y:     dd 0.5                    ; overflow drops appear this far above the feet
k_feet_eps:   dd 0.001
k_vol_click:  dd 0.6
; spawn pattern: (row, lane) of each mob, nearest and central first; row r is 4.5 + 1.5 r blocks in front,
; lane l is 1.6 l blocks to the right
spawn_pattern:
    db 0, 0,   0, -1,  0, 1,   0, -2,  0, 2
    db 1, 0,   1, -1,  1, 1,   1, -2,  1, 2
    db 2, 0,   2, -1,  2, 1,   2, -2,  2, 2

section .data
align 4
debug_open:   dd 0                      ; 1 while the menu is open (set by the third F12, cleared by debug_close)

section .bss
alignb 4
dbg_count:    resd 1                    ; F12 presses counted so far (0..2)
dbg_gap:      resd 1                    ; fixed steps since the last F12 press (saturating)
dbg_acc:      resd 1                    ; float seconds not yet turned into steps (debug_frame's own clock)
debug_coord_fields: resb 3 * TEXTFIELD_size     ; the teleport fields X, Y, Z
dbg_tf_search: resb TEXTFIELD_size      ; the item filter
dbg_tab:      resd 1                    ; 0 player, 1 items, 2 enemies, 3 world
dbg_note:     resb 64                   ; the footer line
dbg_note_t:   resd 1                    ; frames it stays
dbg_buf:      resb 96                   ; text being built
dbg_stat_scroll: resd 1                 ; first visible row of the stat list
dbg_item_sel: resd 1                    ; the selected item id, 0 = none
dbg_item_scroll: resd 1                 ; first visible row of the item list
dbg_search_len: resd 1                  ; length of the filter last frame (a change scrolls back to the top)
dbg_want_focus: resd 1                  ; the item filter takes the typing at the end of this frame (the tab was just opened)
dbg_att:        resd 1                  ; ATT_* bits the selected gun is given with
dbg_mob_type:   resd 1                  ; MOB_ZOMBIE .. MOB_BOSS
dbg_mob_level:  resd 1                  ; 0 = the player's level, else 1..60
dbg_mob_elite:  resd 1
dbg_mob_count:  resd 1                  ; 1, 5 or 10
dbg_px:         resd 1                  ; the page: x, y, width
dbg_py:         resd 1
dbg_pw:         resd 1
dbg_cx:         resd 1                  ; the content area of the open tab: x, y, width
dbg_cy:         resd 1
dbg_cw:         resd 1

section .text

; ---- the F12 detector and the cheater mark ----------------------------------------------------------

; debug_reset(): a new session (game_new / game_load / respawn): the menu is closed, the count starts over, the
; screen's choices are back at their defaults and its text fields empty
debug_reset:
    push    rbp
    mov     rbp, rsp
    xor     eax, eax
    mov     [debug_open], eax
    mov     [dbg_count], eax
    mov     [dbg_gap], eax
    mov     [dbg_acc], eax
    mov     [dbg_tab], eax
    mov     [dbg_note_t], eax
    mov     [dbg_stat_scroll], eax
    mov     [dbg_item_sel], eax
    mov     [dbg_item_scroll], eax
    mov     [dbg_search_len], eax
    mov     [dbg_want_focus], eax
    mov     [dbg_att], eax
    mov     [dbg_mob_level], eax
    mov     [dbg_mob_elite], eax
    mov     dword [dbg_mob_type], MOB_ZOMBIE
    mov     dword [dbg_mob_count], 1
    lea     rdi, [dbg_tf_search]
    mov     esi, 32
    call    field_clear
    lea     rdi, [debug_coord_fields]
    mov     esi, 10
    call    field_clear
    lea     rdi, [debug_coord_fields + TEXTFIELD_size]
    mov     esi, 10
    call    field_clear
    lea     rdi, [debug_coord_fields + 2 * TEXTFIELD_size]
    mov     esi, 10
    call    field_clear
    pop     rbp
    ret

; field_clear(rdi TEXTFIELD*, esi max): no text, at most max characters (leaf)
field_clear:
    mov     byte [rdi + TEXTFIELD.buf], 0
    mov     dword [rdi + TEXTFIELD.len], 0
    mov     [rdi + TEXTFIELD.max], esi
    ret

; debug_step(): once per fixed step (sim_step): the clock of the detector's gap. Saturates (leaf)
debug_step:
    mov     eax, [dbg_gap]
    cmp     eax, 0xFFFF
    jae     .ret
    inc     eax
    mov     [dbg_gap], eax
.ret:
    ret

; debug_other_key(): a key other than F12 was pressed: the count starts over (leaf)
debug_other_key:
    mov     dword [dbg_count], 0
    ret

; debug_press() -> eax 1 when this F12 press opened the menu, else 0. A press more than DEBUG_GAP_STEPS steps
; after the previous one starts a new count; the third press of a count toggles the menu: closed, it opens
; (the world is marked as cheated, the teleport fields take the player's position); open, it closes
; (debug_open 0, eax 0).
debug_press:
    push    rbp
    mov     rbp, rsp
    mov     eax, [dbg_count]
    test    eax, eax
    jz      .count
    cmp     dword [dbg_gap], DEBUG_GAP_STEPS
    jbe     .count
    xor     eax, eax                    ; too late: a new count
.count:
    inc     eax
    mov     dword [dbg_gap], 0
    cmp     eax, 3
    jb      .store
    mov     dword [dbg_count], 0
    cmp     dword [debug_open], 0
    jne     .close
    mov     dword [debug_open], 1
    call    debug_mark_cheater
    call    debug_fill_coords
    mov     eax, 1
    jmp     .ret
.close:
    mov     dword [debug_open], 0
    xor     eax, eax
    jmp     .ret
.store:
    mov     [dbg_count], eax
    xor     eax, eax
.ret:
    pop     rbp
    ret

; debug_poll() -> eax 1 when the menu was opened by this frame's key press: the last key pressed this frame
; (ui_input.key_pressed) is F12 (debug_press) or any other key (debug_other_key)
debug_poll:
    cmp     byte [net_role], NET_ROLE_GUEST
    je      .none                       ; a guest has no debug menu: it would change what the host owns
    mov     eax, [ui_input + UIINPUT.key_pressed]
    cmp     eax, KEY_F12
    je      debug_press
    test    eax, eax
    js      .none
    sub     rsp, 8
    call    debug_other_key
    add     rsp, 8
.none:
    xor     eax, eax
    ret

; debug_close(): the menu is closed (debug_open 0); the count starts over (leaf)
debug_close:
    mov     dword [debug_open], 0
    mov     dword [dbg_count], 0
    ret

; debug_mark_cheater(): the world header image carries the cheater mark (leaf)
debug_mark_cheater:
    mov     byte [world_header + WORLDHDR.cheater], 1
    ret

; debug_is_cheater() -> eax 1 when the world is marked as cheated, else 0. Leaf: only eax changes.
debug_is_cheater:
    xor     eax, eax
    cmp     byte [world_header + WORLDHDR.cheater], 0
    setne   al
    ret

; ---- items -------------------------------------------------------------------------------------------

; debug_give(edi id, esi count, edx dmg) -> eax the number of items handed out: count, at most the item's
; stack size, goes into the inventory (merging into undamaged stacks first, then free slots; dmg is the
; stack's damage word, a gun's rounds and attachments); what does not fit drops at the player's feet.
; 0 for an id that is no item or a count below 1.
; ebx = id, r12d = count, r13d = dmg
debug_give:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     r13d, edx
    xor     eax, eax
    cmp     ebx, NUM_ITEMS
    jae     .ret
    lea     rcx, [item_max_stack]
    movzx   ecx, byte [rcx + rbx]
    test    ecx, ecx
    jz      .ret                        ; not an item
    test    esi, esi
    jle     .ret
    cmp     esi, ecx
    cmova   esi, ecx                    ; one click gives one stack at most
    mov     r12d, esi
    mov     edi, ebx
    mov     edx, r13d
    call    inv_add_dmg
    test    eax, eax
    jz      .given
    mov     esi, eax                    ; the rest: dropped at the feet
    mov     edi, ebx
    mov     edx, r13d
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.y]
    addss   xmm1, [k_drop_y]
    movss   xmm2, [player + BODY.z]
    call    drops_spawn
.given:
    mov     eax, r12d
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; lower(eax c) -> eax the ASCII letter in lower case, anything else unchanged (leaf)
%macro LOWER 1
    lea     ecx, [%1 - 'A']
    cmp     ecx, 25
    ja      %%done
    add     %1, 32
%%done:
%endmacro

; name_match(rdi name, rsi needle) -> eax 1 when the needle occurs in the name, upper and lower case alike;
; an empty needle matches everything (leaf; clobbers rax, rcx, rdx, r8, r9, r10)
name_match:
    cmp     byte [rsi], 0
    je      .yes
.start:
    cmp     byte [rdi], 0
    je      .no
    mov     r9, rdi                     ; the name from here
    mov     r10, rsi                    ; the needle from its start
.cmp:
    movzx   eax, byte [r10]
    test    eax, eax
    jz      .yes
    movzx   edx, byte [r9]
    test    edx, edx
    jz      .no                         ; the name ended first: no later start can match either
    LOWER   eax
    LOWER   edx
    cmp     eax, edx
    jne     .next
    inc     r9
    inc     r10
    jmp     .cmp
.next:
    inc     rdi
    jmp     .start
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; debug_item_nth(edi n, rsi needle) -> eax the id of the n-th (from 0) item whose name contains the needle
; (upper and lower case alike), in id order; 0 when there are not that many. An item is an id with a stack size.
; ebx = id, r12d = n, r13 = needle, r14d = matches so far
debug_item_nth:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12d, edi
    mov     r13, rsi
    xor     r14d, r14d
    mov     ebx, 1
.id:
    cmp     ebx, NUM_ITEMS
    jae     .none
    lea     rax, [item_max_stack]
    cmp     byte [rax + rbx], 0
    je      .next
    lea     rax, [item_names]
    mov     rdi, [rax + rbx*8]
    mov     rsi, r13
    call    name_match
    test    eax, eax
    jz      .next
    cmp     r14d, r12d
    je      .found
    inc     r14d
.next:
    inc     ebx
    jmp     .id
.found:
    mov     eax, ebx
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; debug_item_count(rsi needle) -> eax how many items have the needle in their name (upper and lower case alike)
; ebx = id, r12 = needle, r13d = matches
debug_item_count:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12, rsi
    xor     r13d, r13d
    mov     ebx, 1
.id:
    cmp     ebx, NUM_ITEMS
    jae     .done
    lea     rax, [item_max_stack]
    cmp     byte [rax + rbx], 0
    je      .next
    lea     rax, [item_names]
    mov     rdi, [rax + rbx*8]
    mov     rsi, r12
    call    name_match
    add     r13d, eax
.next:
    inc     ebx
    jmp     .id
.done:
    mov     eax, r13d
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- enemies -----------------------------------------------------------------------------------------

; spawn_floor(edi x, esi z, edx feet) -> eax the y of a free cell to stand in at the local column (x, z): the
; cell and the one above are not solid and the cell is no water or lava, with solid ground under it, within
; two cells above and three below `feet`; -1 when the column is not loaded or has no such cell
; ebx = x, r12d = z, r13d = y being tried, r14d = lowest y
spawn_floor:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r12d, esi
    lea     r13d, [rdx + 2]
    lea     r14d, [rdx - 3]
    call    world_column_ready
    test    eax, eax
    jz      .none
.y:
    cmp     r13d, r14d
    jl      .none
    mov     edi, ebx
    lea     esi, [r13 - 1]
    mov     edx, r12d
    call    world_is_solid
    test    eax, eax
    jz      .next                       ; nothing to stand on
    mov     edi, ebx
    mov     esi, r13d
    mov     edx, r12d
    call    world_is_solid
    test    eax, eax
    jnz     .next
    mov     edi, ebx
    lea     esi, [r13 + 1]
    mov     edx, r12d
    call    world_is_solid
    test    eax, eax
    jnz     .next
    mov     edi, ebx
    mov     esi, r13d
    mov     edx, r12d
    call    world_get
    cmp     eax, WATER
    je      .next
    cmp     eax, LAVA
    je      .next
    mov     eax, r13d
    jmp     .ret
.next:
    dec     r13d
    jmp     .y
.none:
    mov     eax, -1
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; debug_spawn(edi type, esi level, edx elite, ecx count) -> eax the number spawned. Mobs of that type
; (MOB_ZOMBIE .. MOB_BOSS) stand on the ground 4.5 to 7.5 blocks in front of the player (spawn_pattern:
; rows 1.5 blocks apart, five lanes 1.6 apart), one per spot, at that level (0: the player's) and elite when
; edx is not 0. A spot without a floor (spawn_floor) is skipped; fewer than count come when the mob table is
; full or the spots run out. count is clamped to 1..DEBUG_SPAWN_MAX.
; ebx = type, r12d = level, r13d = elite, r14d = count, r15d = spawned; frame: [rsp] sin, [rsp+4] cos of the
; yaw, [rsp+8] pattern index, [rsp+12] x, [rsp+16] z (local cells), [rsp+20] mob slot
debug_spawn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    xor     r15d, r15d
    lea     eax, [rbx - MOB_ZOMBIE]
    cmp     eax, MOB_BOSS - MOB_ZOMBIE
    ja      .ret
    mov     eax, 1
    cmp     r14d, eax
    cmovl   r14d, eax
    mov     eax, DEBUG_SPAWN_MAX
    cmp     r14d, eax
    cmovg   r14d, eax
    movss   xmm0, [player + BODY.yaw]
    call    sincos_deg
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    mov     dword [rsp + 8], 0
.spot:
    cmp     r15d, r14d
    jae     .ret
    mov     eax, [rsp + 8]
    cmp     eax, DEBUG_SPAWN_MAX
    jae     .ret
    lea     rcx, [spawn_pattern]
    movsx   edx, byte [rcx + rax*2]     ; row
    movsx   eax, byte [rcx + rax*2 + 1] ; lane
    cvtsi2ss xmm2, edx
    mulss   xmm2, [k_row_step]
    addss   xmm2, [k_row0]              ; distance in front
    cvtsi2ss xmm3, eax
    mulss   xmm3, [k_lane_step]         ; distance to the right
    movss   xmm4, [rsp]                 ; sin
    movss   xmm5, [rsp + 4]             ; cos
    movaps  xmm0, xmm4                  ; x = px + sin * ahead + cos * right
    mulss   xmm0, xmm2
    movaps  xmm6, xmm5
    mulss   xmm6, xmm3
    addss   xmm0, xmm6
    addss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.z]     ; z = pz - cos * ahead + sin * right
    mulss   xmm5, xmm2
    subss   xmm1, xmm5
    mulss   xmm4, xmm3
    addss   xmm1, xmm4
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rsp + 12], eax
    roundss xmm1, xmm1, 9
    cvttss2si eax, xmm1
    mov     [rsp + 16], eax
    inc     dword [rsp + 8]
    movss   xmm0, [player + BODY.y]
    addss   xmm0, [k_feet_eps]
    roundss xmm0, xmm0, 9
    cvttss2si edx, xmm0
    mov     edi, [rsp + 12]
    mov     esi, [rsp + 16]
    call    spawn_floor
    test    eax, eax
    js      .spot                       ; no floor here: the next spot
    cvtsi2ss xmm1, eax                  ; the middle of the cell, on its floor
    cvtsi2ss xmm0, dword [rsp + 12]
    addss   xmm0, [k_half]
    cvtsi2ss xmm2, dword [rsp + 16]
    addss   xmm2, [k_half]
    mov     edi, ebx
    call    mob_spawn
    test    eax, eax
    js      .ret                        ; the mob table is full
    mov     [rsp + 20], eax
    test    r12d, r12d
    jz      .level_set
    mov     edi, eax
    mov     esi, r12d
    call    mob_set_level
.level_set:
    test    r13d, r13d
    jz      .counted
    mov     eax, [rsp + 20]
    imul    edx, eax, MOB_size
    lea     rcx, [mobs]
    add     rdx, rcx
    call    make_elite                  ; after the level: the number of affixes depends on it
.counted:
    inc     r15d
    jmp     .spot
.ret:
    mov     eax, r15d
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; debug_kill_all(): every mob is removed (animals, monsters, folk, the Fallen King). No drops, no XP.
debug_kill_all:
    jmp     mobs_clear

; debug_heal_all(): every mob that stands has its full health again (leaf)
debug_heal_all:
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
.mob:
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .next
    mov     eax, [rcx + MOB.max_health]
    mov     [rcx + MOB.health], eax
.next:
    add     rcx, MOB_size
    dec     edx
    jnz     .mob
    ret

; ---- world -------------------------------------------------------------------------------------------

; debug_set_time(edi phase): the world clock moves forward to the next moment of that time of the day
; (phase steps from the start of the day, 0 .. DAY_LENGTH-1; DEBUG_DAWN, _NOON, _DUSK, _MIDNIGHT), the
; present one when it is exactly that. Time never runs backwards (leaf)
debug_set_time:
    mov     ecx, DAY_LENGTH
    mov     eax, [game_time]
    xor     edx, edx
    div     ecx                         ; eax = the day, edx = steps into it
    imul    eax, eax, DAY_LENGTH
    add     eax, edi
    mov     ecx, eax
    add     ecx, DAY_LENGTH
    cmp     eax, [game_time]
    cmovb   eax, ecx                    ; that moment has passed today: tomorrow's
    mov     [game_time], eax
    ret

; debug_add_time(edi steps): the world clock moves forward by that many steps (leaf)
debug_add_time:
    add     [game_time], edi
    ret

; debug_parse_int(rdi zstr, rsi int32* out) -> eax 1 and *out set, or 0 (nothing written): optional spaces, an
; optional sign, at least one digit, optional spaces. A value beyond +-DEBUG_COORD_MAX is cut to it (leaf)
debug_parse_int:
    xor     r8d, r8d                    ; the sign: 1 = negative
.lead:
    cmp     byte [rdi], ' '
    jne     .sign
    inc     rdi
    jmp     .lead
.sign:
    cmp     byte [rdi], '-'
    jne     .plus
    mov     r8d, 1
    inc     rdi
    jmp     .digits_start
.plus:
    cmp     byte [rdi], '+'
    jne     .digits_start
    inc     rdi
.digits_start:
    xor     eax, eax
    xor     r9d, r9d                    ; digits seen
.digit:
    movzx   ecx, byte [rdi]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .after
    imul    eax, eax, 10
    add     eax, ecx
    cmp     eax, DEBUG_COORD_MAX
    jbe     .keep
    mov     eax, DEBUG_COORD_MAX        ; keep reading, the value stays cut
.keep:
    inc     r9d
    inc     rdi
    jmp     .digit
.after:
    test    r9d, r9d
    jz      .bad
.trail:
    cmp     byte [rdi], ' '
    jne     .end
    inc     rdi
    jmp     .trail
.end:
    cmp     byte [rdi], 0
    jne     .bad
    test    r8d, r8d
    jz      .store
    neg     eax
.store:
    mov     [rsi], eax
    mov     eax, 1
    ret
.bad:
    xor     eax, eax
    ret

; debug_fill_coords(): the teleport fields X, Y, Z hold the player's absolute cell (the feet cell for Y)
; ebx = field, r12d = field index; frame: [rsp] the three values
debug_fill_coords:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    movss   xmm0, [player + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    add     eax, [world_origin_x]
    mov     [rsp], eax
    movss   xmm0, [player + BODY.y]
    addss   xmm0, [k_feet_eps]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    mov     [rsp + 4], eax
    movss   xmm0, [player + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    add     eax, [world_origin_z]
    mov     [rsp + 8], eax
    xor     r12d, r12d
.field:
    imul    ebx, r12d, TEXTFIELD_size
    lea     rax, [debug_coord_fields]
    add     rbx, rax
    mov     edi, [rsp + r12*4]
    lea     rsi, [rbx + TEXTFIELD.buf]
    call    i32_to_str
    mov     byte [rax], 0
    lea     rcx, [rbx + TEXTFIELD.buf]
    sub     rax, rcx
    mov     [rbx + TEXTFIELD.len], eax
    mov     dword [rbx + TEXTFIELD.max], 10
    inc     r12d
    cmp     r12d, 3
    jb      .field
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; debug_go() -> eax 1 when the player went to the cell the X, Y, Z fields name, 0 (nothing moved) when a field
; is no number. X and Z stay within +-DEBUG_COORD_MAX, Y within 1..254. game_teleport asks to stay in the
; exact cell unless it is blocked (pending 4: then he stands on the surface; the caller waits for the area to
; load first: app_wait_area, which runs game_on_area_ready).
; frame: [rsp] x, [rsp+4] y, [rsp+8] z
debug_go:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    lea     rdi, [debug_coord_fields + TEXTFIELD.buf]
    lea     rsi, [rsp]
    call    debug_parse_int
    test    eax, eax
    jz      .ret
    lea     rdi, [debug_coord_fields + TEXTFIELD_size + TEXTFIELD.buf]
    lea     rsi, [rsp + 4]
    call    debug_parse_int
    test    eax, eax
    jz      .ret
    lea     rdi, [debug_coord_fields + 2 * TEXTFIELD_size + TEXTFIELD.buf]
    lea     rsi, [rsp + 8]
    call    debug_parse_int
    test    eax, eax
    jz      .ret
    mov     esi, [rsp + 4]
    mov     eax, 1
    cmp     esi, eax
    cmovl   esi, eax
    mov     eax, 254
    cmp     esi, eax
    cmovg   esi, eax
    mov     edi, [rsp]
    mov     edx, [rsp + 8]
    mov     ecx, 4
    call    game_teleport
.ret:
    add     rsp, 16
    pop     rbp
    ret

; debug_to_spawn() -> eax 1: the player goes to the world spawn (WORLDHDR.spawn_x/y/z, an absolute cell) and
; stands on the surface of its column once the area around has loaded (game_teleport pending 1; the caller
; waits for the area: app_wait_area). Tail call: a leaf here.
debug_to_spawn:
    mov     edi, [world_header + WORLDHDR.spawn_x]
    mov     esi, [world_header + WORLDHDR.spawn_y]
    mov     edx, [world_header + WORLDHDR.spawn_z]
    mov     ecx, 1
    jmp     game_teleport

; debug_to_bed() -> eax 1 when a bed is set (WORLDHDR.bed_*, the absolute foot cell) and the player goes to
; it, standing beside it once the area has loaded (game_teleport pending 3: sleep_place_at_bed, and the
; world spawn when the bed is gone); 0 and nothing moves when no bed is set.
debug_to_bed:
    xor     eax, eax
    cmp     dword [world_header + WORLDHDR.bed_set], 0
    je      .ret
    mov     edi, [world_header + WORLDHDR.bed_x]
    mov     esi, [world_header + WORLDHDR.bed_y]
    mov     edx, [world_header + WORLDHDR.bed_z]
    mov     ecx, 3
    jmp     game_teleport
.ret:
    ret

; debug_reset_cooldowns(): every ability and the staff bolt are ready again (leaf)
debug_reset_cooldowns:
    xor     eax, eax
    lea     rdi, [abilities_cd]
    mov     ecx, NUM_ABILITIES
    rep     stosd
    lea     rdi, [abilities_cd_total]
    mov     ecx, NUM_ABILITIES
    rep     stosd
    mov     [abilities_bolt_cd], eax
    ret

; debug_clear_drops(): every item lying in the world is gone
debug_clear_drops:
    jmp     drops_clear

; ---- the character -----------------------------------------------------------------------------------

; debug_full_restore(): health, food, air, mana and stamina full
debug_full_restore:
    mov     eax, [surv_max_health]
    mov     [surv + SURVIVAL.health], eax
    mov     dword [surv + SURVIVAL.food], MAX_FOOD
    mov     dword [surv + SURVIVAL.saturation], __float32__(5.0)
    mov     dword [surv + SURVIVAL.exhaustion], 0
    mov     dword [surv + SURVIVAL.breath], MAX_BREATH
    jmp     combat_refill

; debug_toggle_god() -> eax 1 when god mode is now on: nothing hurts (survival_damage, survival_dot) (leaf)
debug_toggle_god:
    xor     dword [surv + SURVIVAL.god], 1
    mov     eax, [surv + SURVIVAL.god]
    ret

; debug_toggle_fly() -> eax 1 when the player now flies, in either game mode (leaf)
debug_toggle_fly:
    xor     dword [player + BODY.flying], 1
    mov     dword [player + BODY.vy], 0
    mov     eax, [player + BODY.flying]
    ret

; debug_toggle_mode() -> eax the game mode now: MODE_SURVIVAL or MODE_CREATIVE (leaf)
debug_toggle_mode:
    xor     dword [game_mode], 1
    mov     eax, [game_mode]
    ret

; debug_stat_range(edi stat) -> eax lowest, edx highest value the stat may have with the debug bonus on it:
; a flat stat 0 .. 999 (max health from 2), a percentage -90 .. 999 (so no multiplier or divisor reaches 0),
; a reduction stored positive (cooldowns, dodge and block cost) -900 .. 90, a resistance up to 90
debug_stat_range:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    rpg_stat_info
    movzx   ecx, byte [rax + STATINFO.fmt]
    mov     eax, -90
    mov     edx, 999
    cmp     ecx, FMT_FLAT
    je      .flat
    cmp     ecx, FMT_TENTH
    je      .flat
    cmp     ecx, FMT_NEGPCT
    jne     .kind_done
    mov     eax, -900
    mov     edx, 90
    jmp     .kind_done
.flat:
    xor     eax, eax
.kind_done:
    lea     ecx, [rbx - STAT_RES_FIRE]
    cmp     ecx, STAT_RES_POISON - STAT_RES_FIRE
    ja      .not_res
    mov     edx, 90
.not_res:
    cmp     ebx, STAT_MAX_HEALTH
    jne     .ret
    mov     eax, 2
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; debug_bonus_add(edi stat, esi delta) -> eax the change that was applied: the stat (as it is now, with its
; bonus) moves by delta, held within debug_stat_range, by raising or lowering its debug bonus; the stats are
; recomputed. 0 for an unknown stat or when it cannot move that way.
; ebx = stat, r12d = the change, r13d = the stat's value now
debug_bonus_add:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    xor     eax, eax
    cmp     edi, NUM_STATS
    jae     .ret
    mov     ebx, edi
    mov     r12d, esi
    lea     rax, [rpg_stats]
    mov     r13d, [rax + rbx*4]
    mov     edi, ebx
    call    debug_stat_range
    add     r12d, r13d                  ; where it would land ...
    cmp     r12d, edx
    cmovg   r12d, edx
    cmp     r12d, eax
    cmovl   r12d, eax                   ; ... held within its range
    sub     r12d, r13d
    jz      .none
    lea     rcx, [debug_stat_bonus]
    movsx   eax, word [rcx + rbx*2]
    add     eax, r12d
    mov     edx, DEBUG_BONUS_MAX
    cmp     eax, edx
    cmovg   eax, edx
    neg     edx
    cmp     eax, edx
    cmovl   eax, edx
    mov     [rcx + rbx*2], ax
    call    rpg_recompute
    mov     eax, r12d
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- the screen --------------------------------------------------------------------------------------

%define PNL_H       226                 ; the page's height: it fits the smallest GUI (320 x 240)
%define BTN14       14                  ; the height of a compact button
%define STAT_ROWS   10                  ; rows of the stat list
%define STAT_PITCH  15
%define ITEM_ROWS   10                  ; rows of the item list
%define ITEM_PITCH  14
%define ITEM_LIST_W 190
%define LEFT_COL    136                 ; the Player tab's left column and its gap: the stat list starts here

%macro ENTER_FRAME 1                    ; frame with %1 bytes of locals (%1 = 8 mod 16)
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, %1
%endmacro
%macro LEAVE_FRAME 1
    add     rsp, %1
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
%endmacro
; text building: r15 is the write cursor into dbg_buf
%macro APPZ 1                           ; append the string at label %1
    mov     rdi, r15
    lea     rsi, [%1]
    call    str_append
    mov     r15, rax
%endmacro
%macro APPP 0                           ; append the string rsi points to
    mov     rdi, r15
    call    str_append
    mov     r15, rax
%endmacro
%macro APPN 1                           ; append the decimal value of the 32-bit operand %1
    mov     edi, %1
    mov     rsi, r15
    call    i32_to_str
    mov     r15, rax
%endmacro
%macro SHOWBUF 3                        ; draw the text in dbg_buf (it ends at r15) at the content area's (%1, %2) in colour %3
    mov     byte [r15], 0
    lea     rdi, [dbg_buf]
    mov     esi, [dbg_cx]
    add     esi, %1
    mov     edx, [dbg_cy]
    add     edx, %2
    mov     ecx, %3
    mov     r8d, 1
    call    ui_text_ink
%endmacro
%macro DTXT 4                           ; the string at label %1 at the content area's (%2, %3) in colour %4
    lea     rdi, [%1]
    mov     esi, [dbg_cx]
    add     esi, %2
    mov     edx, [dbg_cy]
    add     edx, %3
    mov     ecx, %4
    mov     r8d, 1
    call    ui_text_ink
%endmacro
%macro DBTNR 4                          ; rdi = label, r9d = active; at the content area's (%1, %2), width %3, enabled %4 -> eax clicked
    mov     esi, [dbg_cx]
    add     esi, %1
    mov     edx, [dbg_cy]
    add     edx, %2
    mov     ecx, %3
    mov     r8d, %4
    call    dbtn
%endmacro
%macro DBTN 6                           ; the string at label %1 as a button at (%2, %3), width %4, enabled %5, active %6 -> eax clicked
    lea     rdi, [%1]
    mov     r9d, %6
    DBTNR   %2, %3, %4, %5
%endmacro

section .bss
alignb 4
dbg_clip:     resb 48                   ; dclip's copy of a label

section .rodata
s_title:        db "Debug menu", 0
s_tab_player:   db "Player", 0
s_tab_items:    db "Items", 0
s_tab_enemies:  db "Enemies", 0
s_tab_world:    db "World", 0
s_close_hint:   db "Esc or F12 x3 closes", 0
s_cheated:      db "This world is marked as cheated", 0
s_m5:           db "-5", 0
s_m1:           db "-1", 0
s_p1:           db "+1", 0
s_p5:           db "+5", 0
s_p10:          db "+10", 0
s_minus:        db "-", 0
s_plus:         db "+", 0
s_level:        db "Level ", 0
s_of_max:       db " / 50", 0
s_lvl_min:      db "Level 1", 0
s_lvl_max:      db "Level 50", 0
s_xp:           db "XP ", 0
s_slash:        db " / ", 0
s_max:          db "max", 0
s_level_up:     db "Level up", 0
s_respec:       db "Respec", 0
s_skill_pts:    db "Skill points: ", 0
s_attr_pts:     db "Attribute points: ", 0
s_restore:      db "Restore", 0
s_god_off:      db "God: off", 0
s_god_on:       db "God: on", 0
s_fly_off:      db "Fly: off", 0
s_fly_on:       db "Fly: on", 0
s_mode_surv:    db "Survival", 0
s_mode_creat:   db "Creative", 0
s_stats_head:   db "Stats: click 5, Shift 1", 0
s_n_restored:   db "Health, food, mana, stamina full", 0
s_n_respec:     db "All points refunded, no coins", 0
s_filter_hint:  db "Type to filter by name", 0
s_in_bag:       db "In bag: ", 0
s_g1:           db "+1", 0
s_g16:          db "+16", 0
s_g64:          db "+64", 0
s_attach:       db "Fit with:", 0
s_att_scope:    db "Scope", 0
s_att_mag:      db "Ext. magazine", 0
s_att_rifle:    db "Rifled barrel", 0
s_att_comp:     db "Compensator", 0
s_gave:         db "Gave ", 0
s_times:        db " x ", 0
s_lvl_colon:    db "Level: ", 0
s_yours:        db " (yours)", 0
s_yours_btn:    db "Yours", 0
s_elite_off:    db "Elite: no", 0
s_elite_on:     db "Elite: yes", 0
s_count:        db "Count:", 0
s_n1:           db "1", 0
s_n5:           db "5", 0
s_n10:          db "10", 0
s_spawn:        db "Spawn", 0
s_kill:         db "Kill all", 0
s_heal:         db "Heal all", 0
s_mobs_alive:   db "Mobs: ", 0
s_hostile:      db " hostile, ", 0
s_passive:      db " passive", 0
s_spawned:      db "Spawned ", 0
s_no_room:      db "No room in front of you", 0
s_n_killed:     db "Every mob removed", 0
s_n_healed:     db "Every mob healed", 0
s_hint_spawn:   db "Mobs appear 4 to 8 blocks in front of you", 0
s_events:       db "Events", 0
s_ev_camp:      db "Camp", 0
s_ev_caravan:   db "Caravan", 0
s_ev_threat:    db "Threat", 0
s_ev_wave:      db "Wave", 0
s_ev_win:       db "Win", 0
s_ev_started:   db "Event started", 0
s_ev_noroom:    db "No room for an event", 0
s_ev_done:      db "Done", 0
s_ev_no_camp:   db "No camp within 96 blocks", 0
s_ev_idle:      db "No event to skip", 0
s_nearest:      db "Nearest camp: ", 0
s_nearest_none: db "Nearest camp: none", 0
s_ev_space:     db " ", 0
s_ev_comma:     db ", ", 0
s_day:          db "Day ", 0
s_colon:        db ":", 0
s_gap:          db "   ", 0
s_dawn:         db "Dawn", 0
s_noon:         db "Noon", 0
s_dusk:         db "Dusk", 0
s_midnight:     db "Midnight", 0
s_hour:         db "+1 hour", 0
s_x:            db "X", 0
s_y:            db "Y", 0
s_z:            db "Z", 0
s_go:           db "Go", 0
s_to_spawn:     db "To spawn", 0
s_to_bed:       db "To bed", 0
s_reset_cd:     db "Reset cooldowns", 0
s_clear_drops:  db "Clear drops", 0
s_factions:     db "Factions", 0
s_m100:         db "-100", 0
s_p100:         db "+100", 0
s_fmax:         db "Max", 0
s_n_cooldowns:  db "Cooldowns reset", 0
s_n_drops:      db "Drops cleared", 0
s_bad_coords:   db "X, Y and Z must be whole numbers", 0
s_teleporting:  db "Teleporting", 0
s_mob0:         db "Zombie", 0
s_mob1:         db "Pig", 0
s_mob2:         db "Creeper", 0
s_mob3:         db "Skeleton", 0
s_mob4:         db "Spider", 0
s_mob5:         db "Chicken", 0
s_mob6:         db "Fallen King", 0
align 8
tab_names:      dq s_tab_player, s_tab_items, s_tab_enemies, s_tab_world
tab_funcs:      dq tab_player, tab_items, tab_enemies, tab_world
mob_names:      dq s_mob0, s_mob1, s_mob2, s_mob3, s_mob4, s_mob5, s_mob6      ; by MOB_ZOMBIE .. MOB_BOSS - 1
; button tables: label, a value, an x offset in the content area, a width
lv_btn_tab:     dq s_m5
                dd -5, 112
                dq s_m1
                dd -1, 138
                dq s_p1
                dd 1, 164
                dq s_p5
                dd 5, 190
count_tab:      dq s_n1
                dd 1, 132
                dq s_n5
                dd 5, 158
                dq s_n10
                dd 10, 184
time_tab:       dq s_dawn
                dd DEBUG_DAWN, 0, 52, 0
                dq s_noon
                dd DEBUG_NOON, 54, 52, 0
                dq s_dusk
                dd DEBUG_DUSK, 108, 52, 0
                dq s_midnight
                dd DEBUG_MIDNIGHT, 162, 62, 0
                dq s_hour
                dd -1, 226, 62, 0
fac_btn_tab:    dq s_m100
                dd -100, 109, 38, 0
                dq s_p100
                dd 100, 70, 38, 0
                dq s_fmax
                dd 2000, 31, 31, 0
att_tab:        dq s_att_scope
                dd ATT_SCOPE, 0
                dq s_att_mag
                dd ATT_EXTMAG, 0
                dq s_att_rifle
                dd ATT_RIFLED, 0
                dq s_att_comp
                dd ATT_COMP, 0
give_tab:       dq s_g1
                dd 1, 38
                dq s_g16
                dd 16, 54
                dq s_g64
                dd 64, 70

section .text

; dhit(edi x, esi y, edx w, ecx h) -> eax 1 when the mouse is inside the rectangle (leaf)
dhit:
    mov     eax, [ui_mx]
    sub     eax, edi
    cmp     eax, edx                    ; unsigned: also rejects mx < x
    jae     .no
    mov     eax, [ui_my]
    sub     eax, esi
    cmp     eax, ecx
    jae     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; dbtn(rdi label, esi x, edx y, ecx w, r8d enabled, r9d active) -> eax 1 when clicked: a BTN14 high button
; with the label centred; active lights it (a toggle that is on); a disabled one shows the faded plate and
; never clicks
; rbx = label, r12d = x, r13d = y, r14d = w, r15d = enabled; frame: [rsp] hover, [rsp+4] active
dbtn:
    ENTER_FRAME 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, r8d
    mov     [rsp + 4], r9d
    xor     eax, eax
    test    r15d, r15d
    jz      .hover_known
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, BTN14
    call    dhit
.hover_known:
    mov     [rsp], eax
    mov     edi, NINE_BUTTON_OFF
    test    r15d, r15d
    jz      .plate
    mov     edi, NINE_BUTTON
    or      eax, [rsp + 4]
    jz      .plate
    mov     edi, NINE_BUTTON_HOT
.plate:
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r14d
    mov     r8d, BTN14
    call    ui_nine
    mov     ecx, C_INK
    mov     eax, C_INK_SOFT
    test    r15d, r15d
    cmovz   ecx, eax
    mov     eax, C_RUBRIC
    cmp     dword [rsp + 4], 0
    cmovne  ecx, eax
    mov     rdi, rbx
    mov     esi, r14d
    shr     esi, 1
    add     esi, r12d
    lea     edx, [r13 + 3]
    mov     r8d, 1
    call    ui_text_ink_centered
    xor     eax, eax
    cmp     dword [rsp], 0
    je      .ret
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .ret
    mov     edi, SND_CLICK
    movss   xmm0, [k_vol_click]
    call    audio_play
    mov     eax, 1
.ret:
    LEAVE_FRAME 8

; dclip(rdi src, esi maxw) -> rax a copy of the string (at most 47 characters) cut so that its ink fits maxw
dclip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12d, esi
    lea     rbx, [dbg_clip]
    mov     rsi, rdi
    mov     rdi, rbx
    mov     edx, 47
    call    str_copy
.fit:
    mov     rdi, rbx
    mov     esi, 1
    call    ui_text_width
    cmp     eax, r12d
    jle     .done
    mov     rdi, rbx
    call    str_len
    test    rax, rax
    jz      .done
    mov     byte [rbx + rax - 1], 0
    jmp     .fit
.done:
    mov     rax, rbx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; fmt_value(edi stat, esi value, rdx buf) -> rax past the last character (no NUL): the value as the stat
; list shows it, signed when negative; a stat counted in tenths (life regen) with one decimal
fmt_value:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12d, esi
    mov     r13, rdx
    call    rpg_stat_info
    cmp     byte [rax + STATINFO.fmt], FMT_TENTH
    jne     .plain
    mov     rbx, r13
    test    r12d, r12d
    jns     .abs
    mov     byte [rbx], '-'
    inc     rbx
    neg     r12d
.abs:
    mov     eax, r12d
    xor     edx, edx
    mov     ecx, 10
    div     ecx                         ; eax = whole points, edx = the tenth
    mov     r12d, edx
    mov     edi, eax
    mov     rsi, rbx
    call    i32_to_str
    mov     byte [rax], '.'
    add     r12d, '0'
    mov     [rax + 1], r12b
    add     rax, 2
    jmp     .ret
.plain:
    mov     edi, r12d
    mov     rsi, r13
    call    i32_to_str
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; put2d(edi n, rsi buf) -> rax past the two digits written: n (0..99) with a leading zero (leaf)
put2d:
    mov     eax, edi
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    add     al, '0'
    mov     [rsi], al
    add     dl, '0'
    mov     [rsi + 1], dl
    lea     rax, [rsi + 2]
    ret

; dnote(rdi zstr): the footer shows this text for DEBUG_NOTE_FRAMES frames (at most 63 characters)
dnote:
    sub     rsp, 8
    mov     rsi, rdi
    lea     rdi, [dbg_note]
    mov     edx, 63
    call    str_copy
    mov     dword [dbg_note_t], DEBUG_NOTE_FRAMES
    add     rsp, 8
    ret

; dclose(): the menu is closed and the game goes on (the cursor is captured again by app_goto)
dclose:
    sub     rsp, 8
    call    debug_close
    mov     qword [ui_focus], 0
    mov     edi, ST_PLAYING
    call    app_goto
    add     rsp, 8
    ret

; tp_finish(): the player was moved by game_teleport: the area around is waited for behind the loading
; screen, then the menu closes (the caller draws nothing more this frame)
tp_finish:
    sub     rsp, 8
    lea     rdi, [s_teleporting]
    lea     rsi, [player]
    call    app_wait_area
    call    debug_close
    add     rsp, 8
    ret

; page_geometry(): the page (width at most 380, centred, 226 high, 8 from the top at least) and its content
; area under the tabs
page_geometry:
    mov     eax, [ui_w]
    sub     eax, 8
    mov     ecx, 380
    cmp     eax, ecx
    cmovg   eax, ecx
    mov     [dbg_pw], eax
    mov     ecx, [ui_w]
    sub     ecx, eax
    shr     ecx, 1
    mov     [dbg_px], ecx
    add     ecx, 10
    mov     [dbg_cx], ecx
    sub     eax, 20
    mov     [dbg_cw], eax
    mov     ecx, [ui_h]
    sub     ecx, PNL_H
    sar     ecx, 1
    mov     edx, 8
    cmp     ecx, edx
    cmovl   ecx, edx
    mov     [dbg_py], ecx
    add     ecx, 32
    mov     [dbg_cy], ecx
    ret

; draw_tabs(): the four tabs over the page; a click on one opens it (the item filter takes the typing at once)
; ebx = tab, r12d = x, r13d = y
draw_tabs:
    ENTER_FRAME 8
    xor     ebx, ebx
.tab:
    imul    r12d, ebx, 72
    add     r12d, [dbg_px]
    add     r12d, 10
    mov     r13d, [dbg_py]
    add     r13d, 8
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, 70
    mov     ecx, 16
    call    dhit
    test    eax, eax
    jz      .draw
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .draw
    cmp     [dbg_tab], ebx
    je      .draw
    mov     [dbg_tab], ebx
    mov     qword [ui_focus], 0
    cmp     ebx, 1
    jne     .sound
    mov     dword [dbg_want_focus], 1   ; (the click that opened the tab would defocus the field this frame)
.sound:
    mov     edi, SND_CLICK
    movss   xmm0, [k_vol_click]
    call    audio_play
.draw:
    mov     edi, NINE_BUTTON
    mov     eax, NINE_BUTTON_HOT
    cmp     [dbg_tab], ebx
    cmove   edi, eax
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, 70
    mov     r8d, 16
    call    ui_nine
    lea     rax, [tab_names]
    mov     rdi, [rax + rbx*8]
    lea     esi, [r12 + 35]
    lea     edx, [r13 + 5]
    mov     ecx, C_INK
    mov     eax, C_RUBRIC
    cmp     [dbg_tab], ebx
    cmove   ecx, eax
    mov     r8d, 1
    call    ui_text_ink_centered
    inc     ebx
    cmp     ebx, 4
    jb      .tab
    LEAVE_FRAME 8

; draw_footer(): a gold rule, the key hint at the right and at the left the last action's note, or while
; there is none the reminder that the world is marked as cheated (cut to fit)
; r12d = x of the hint, r13d = y of the text
draw_footer:
    ENTER_FRAME 8
    mov     edi, [dbg_px]
    add     edi, 8
    mov     esi, [dbg_py]
    add     esi, PNL_H - 20
    mov     edx, [dbg_pw]
    sub     edx, 16
    mov     ecx, 1
    mov     r8d, C_GOLD_DEEP
    call    ui_rect
    mov     r13d, [dbg_py]
    add     r13d, PNL_H - 14
    lea     rdi, [s_close_hint]
    mov     esi, 1
    call    ui_text_width
    mov     r12d, [dbg_px]
    add     r12d, [dbg_pw]
    sub     r12d, 10
    sub     r12d, eax
    lea     rdi, [s_close_hint]
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, C_INK_SOFT
    mov     r8d, 1
    call    ui_text_ink
    lea     rdi, [s_cheated]
    mov     ecx, C_RUBRIC
    cmp     dword [dbg_note_t], 0
    je      .left
    dec     dword [dbg_note_t]
    lea     rdi, [dbg_note]
    mov     ecx, C_INK
.left:
    mov     ebx, ecx
    mov     esi, r12d                   ; room: from the page's left edge to the hint
    sub     esi, [dbg_px]
    sub     esi, 18
    call    dclip
    mov     rdi, rax
    mov     esi, [dbg_px]
    add     esi, 10
    mov     edx, r13d
    mov     ecx, ebx
    mov     r8d, 1
    call    ui_text_ink
    LEAVE_FRAME 8

; ---- the Player tab ----------------------------------------------------------------------------------
; Left column (LEFT_COL wide): level, XP, skill and attribute points, restore, god mode, fly, game mode.
; Right column: the stat list with a - and a + button per stat (click: 5, with Shift: 1).
; r12d = the level, r13d = the step of a stat button; frame: [rsp] row, [rsp+4] stat, [rsp+8] row y,
; [rsp+12] list x, [rsp+16] list width, [rsp+20] label width, [rsp+24] x of the - button
tab_player:
    ENTER_FRAME 40
    movzx   r12d, byte [rpg_state + RPGSAVE.level]
    lea     r15, [dbg_buf]
    APPZ    s_level
    APPN    r12d
    APPZ    s_of_max
    SHOWBUF 0, 0, C_RUBRIC
    DBTN    s_m5, 0, 12, 30, 1, 0
    test    eax, eax
    jz      .lv_m1
    lea     edi, [r12 - 5]
    call    rpg_set_level
.lv_m1:
    DBTN    s_m1, 32, 12, 30, 1, 0
    test    eax, eax
    jz      .lv_p1
    lea     edi, [r12 - 1]
    call    rpg_set_level
.lv_p1:
    DBTN    s_p1, 64, 12, 30, 1, 0
    test    eax, eax
    jz      .lv_p5
    lea     edi, [r12 + 1]
    call    rpg_set_level
.lv_p5:
    DBTN    s_p5, 96, 12, 30, 1, 0
    test    eax, eax
    jz      .lv_min
    lea     edi, [r12 + 5]
    call    rpg_set_level
.lv_min:
    DBTN    s_lvl_min, 0, 28, 63, 1, 0
    test    eax, eax
    jz      .lv_max
    mov     edi, 1
    call    rpg_set_level
.lv_max:
    DBTN    s_lvl_max, 65, 28, 63, 1, 0
    test    eax, eax
    jz      .xp
    mov     edi, MAX_LEVEL
    call    rpg_set_level
.xp:
    mov     edi, r12d
    call    rpg_xp_need
    mov     ebx, eax
    lea     r15, [dbg_buf]
    APPZ    s_xp
    test    ebx, ebx
    jz      .xp_max
    APPN    [rpg_state + RPGSAVE.xp]
    APPZ    s_slash
    APPN    ebx
    jmp     .xp_show
.xp_max:
    APPZ    s_max
.xp_show:
    SHOWBUF 0, 46, C_INK
    xor     r14d, r14d
    cmp     r12d, MAX_LEVEL
    setb    r14b
    DBTN    s_level_up, 0, 58, 63, r14d, 0
    test    eax, eax
    jz      .respec
    lea     edi, [r12 + 1]
    call    rpg_set_level
.respec:
    DBTN    s_respec, 65, 58, 63, 1, 0
    test    eax, eax
    jz      .skill
    call    rpg_respec_free
    lea     rdi, [s_n_respec]
    call    dnote
.skill:
    call    rpg_points
    mov     ebx, eax
    lea     r15, [dbg_buf]
    APPZ    s_skill_pts
    APPN    ebx
    SHOWBUF 0, 76, C_INK
    DBTN    s_p1, 0, 88, 63, 1, 0
    test    eax, eax
    jz      .skill10
    mov     edi, 1
    xor     esi, esi
    call    rpg_add_bonus_points
.skill10:
    DBTN    s_p10, 65, 88, 63, 1, 0
    test    eax, eax
    jz      .attr
    mov     edi, 10
    xor     esi, esi
    call    rpg_add_bonus_points
.attr:
    call    rpg_attr_points
    mov     ebx, eax
    lea     r15, [dbg_buf]
    APPZ    s_attr_pts
    APPN    ebx
    SHOWBUF 0, 106, C_INK
    DBTN    s_p1, 0, 118, 63, 1, 0
    test    eax, eax
    jz      .attr10
    xor     edi, edi
    mov     esi, 1
    call    rpg_add_bonus_points
.attr10:
    DBTN    s_p10, 65, 118, 63, 1, 0
    test    eax, eax
    jz      .restore
    xor     edi, edi
    mov     esi, 10
    call    rpg_add_bonus_points
.restore:
    DBTN    s_restore, 0, 136, 63, 1, 0
    test    eax, eax
    jz      .god
    call    debug_full_restore
    lea     rdi, [s_n_restored]
    call    dnote
.god:
    lea     rdi, [s_god_off]
    lea     rax, [s_god_on]
    cmp     dword [surv + SURVIVAL.god], 0
    cmovne  rdi, rax
    mov     r9d, [surv + SURVIVAL.god]
    DBTNR   65, 136, 63, 1
    test    eax, eax
    jz      .fly
    call    debug_toggle_god
.fly:
    lea     rdi, [s_fly_off]
    lea     rax, [s_fly_on]
    cmp     dword [player + BODY.flying], 0
    cmovne  rdi, rax
    mov     r9d, [player + BODY.flying]
    DBTNR   0, 152, 63, 1
    test    eax, eax
    jz      .mode
    call    debug_toggle_fly
.mode:
    lea     rdi, [s_mode_surv]
    lea     rax, [s_mode_creat]
    cmp     dword [game_mode], MODE_SURVIVAL
    cmovne  rdi, rax
    xor     r9d, r9d
    DBTNR   65, 152, 63, 1
    test    eax, eax
    jz      .stats
    call    debug_toggle_mode
.stats:
    mov     eax, [dbg_cx]               ; the right column: the list of every stat
    add     eax, LEFT_COL
    mov     [rsp + 12], eax
    mov     eax, [dbg_cw]
    sub     eax, LEFT_COL
    mov     [rsp + 16], eax
    sub     eax, 66                     ; the value and the two buttons
    mov     [rsp + 20], eax
    mov     eax, [rsp + 12]
    add     eax, [rsp + 16]
    sub     eax, 31
    mov     [rsp + 24], eax
    mov     r13d, 5
    cmp     dword [ui_input + UIINPUT.shift], 0
    je      .step_set
    mov     r13d, 1
.step_set:
    DTXT    s_stats_head, LEFT_COL, 0, C_RUBRIC
    mov     edi, [rsp + 12]             ; the wheel over the list scrolls it
    mov     esi, [dbg_cy]
    add     esi, 14
    mov     edx, [rsp + 16]
    mov     ecx, STAT_ROWS * STAT_PITCH
    call    dhit
    mov     ecx, [dbg_stat_scroll]
    test    eax, eax
    jz      .scroll_clamp
    sub     ecx, [ui_input + UIINPUT.scroll]
.scroll_clamp:
    mov     eax, NUM_STATS - STAT_ROWS
    cmp     ecx, eax
    cmovg   ecx, eax
    xor     edx, edx
    test    ecx, ecx
    cmovs   ecx, edx
    mov     [dbg_stat_scroll], ecx
    mov     dword [rsp], 0
.stat_row:
    mov     eax, [rsp]
    cmp     eax, STAT_ROWS
    jae     .stats_done
    add     eax, [dbg_stat_scroll]
    cmp     eax, NUM_STATS
    jae     .stats_done
    mov     [rsp + 4], eax
    imul    eax, [rsp], STAT_PITCH
    add     eax, [dbg_cy]
    add     eax, 14
    mov     [rsp + 8], eax
    mov     edi, [rsp + 12]
    mov     esi, [rsp + 8]
    mov     edx, [rsp + 16]
    mov     ecx, STAT_PITCH - 1
    call    dhit
    test    eax, eax
    jz      .no_wash
    mov     edi, [rsp + 12]
    mov     esi, [rsp + 8]
    mov     edx, [rsp + 16]
    mov     ecx, STAT_PITCH - 1
    mov     r8d, C_HOVER
    call    ui_rect
.no_wash:
    mov     edi, [rsp + 4]
    call    rpg_stat_info
    mov     rdi, [rax + STATINFO.label]
    mov     esi, [rsp + 20]
    call    dclip
    mov     rdi, rax
    mov     esi, [rsp + 12]
    add     esi, 2
    mov     edx, [rsp + 8]
    add     edx, 3
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    mov     edi, [rsp + 4]              ; the value, in rubric while a debug bonus is on it
    lea     rax, [rpg_stats]
    mov     esi, [rax + rdi*4]
    lea     rdx, [dbg_buf]
    call    fmt_value
    mov     byte [rax], 0
    mov     eax, [rsp + 4]
    lea     rcx, [debug_stat_bonus]
    movsx   edx, word [rcx + rax*2]
    mov     ecx, C_INK
    mov     eax, C_RUBRIC
    test    edx, edx
    cmovnz  ecx, eax
    lea     rdi, [dbg_buf]
    mov     esi, [rsp + 12]
    add     esi, [rsp + 20]
    add     esi, 4
    mov     edx, [rsp + 8]
    add     edx, 3
    mov     r8d, 1
    call    ui_text_ink
    lea     rdi, [s_minus]
    mov     esi, [rsp + 24]
    mov     edx, [rsp + 8]
    mov     ecx, 15
    mov     r8d, 1
    xor     r9d, r9d
    call    dbtn
    test    eax, eax
    jz      .plus
    mov     edi, [rsp + 4]
    mov     esi, r13d
    neg     esi
    call    debug_bonus_add
.plus:
    lea     rdi, [s_plus]
    mov     esi, [rsp + 24]
    add     esi, 16
    mov     edx, [rsp + 8]
    mov     ecx, 15
    mov     r8d, 1
    xor     r9d, r9d
    call    dbtn
    test    eax, eax
    jz      .stat_next
    mov     edi, [rsp + 4]
    mov     esi, r13d
    call    debug_bonus_add
.stat_next:
    inc     dword [rsp]
    jmp     .stat_row
.stats_done:
    LEAVE_FRAME 40

; ---- the Items tab -----------------------------------------------------------------------------------
; A name filter, the list of the items it matches (the wheel scrolls it; a click selects) and, for the
; selected one, +1 / +16 / +64 into the inventory (a gun can be given with attachments fitted already).
; ebx = the selected item, r12d = matches, r13d = the stack's damage word (a gun's attachments),
; r14d = 1 for a gun; frame: [rsp] row, [rsp+4] item, [rsp+8] row y, [rsp+12] right column x,
; [rsp+16] its width, [rsp+20] count being given
tab_items:
    ENTER_FRAME 40
    lea     rdi, [dbg_tf_search]
    mov     esi, [dbg_cx]
    mov     edx, [dbg_cy]
    mov     ecx, ITEM_LIST_W
    call    ui_textfield
    cmp     dword [dbg_want_focus], 0
    je      .no_focus
    mov     dword [dbg_want_focus], 0
    lea     rax, [dbg_tf_search]
    mov     [ui_focus], rax
.no_focus:
    cmp     dword [dbg_tf_search + TEXTFIELD.len], 0
    jne     .no_hint
    lea     rax, [dbg_tf_search]
    cmp     [ui_focus], rax
    je      .no_hint
    DTXT    s_filter_hint, 5, 6, C_INK_SOFT     ; an empty field that is not being typed in says what it is for
.no_hint:
    mov     eax, [dbg_tf_search + TEXTFIELD.len]
    cmp     eax, [dbg_search_len]
    je      .filter_same
    mov     [dbg_search_len], eax       ; another filter: back to the top of the list
    mov     dword [dbg_item_scroll], 0
.filter_same:
    lea     rsi, [dbg_tf_search + TEXTFIELD.buf]
    call    debug_item_count
    mov     r12d, eax
    mov     edi, [dbg_cx]
    mov     esi, [dbg_cy]
    add     esi, 24
    mov     edx, ITEM_LIST_W
    mov     ecx, ITEM_ROWS * ITEM_PITCH
    call    dhit
    mov     ecx, [dbg_item_scroll]
    test    eax, eax
    jz      .scroll_clamp
    sub     ecx, [ui_input + UIINPUT.scroll]
.scroll_clamp:
    mov     eax, r12d
    sub     eax, ITEM_ROWS
    xor     edx, edx
    test    eax, eax
    cmovs   eax, edx
    cmp     ecx, eax
    cmovg   ecx, eax
    test    ecx, ecx
    cmovs   ecx, edx
    mov     [dbg_item_scroll], ecx
    mov     dword [rsp], 0
.row:
    mov     eax, [rsp]
    cmp     eax, ITEM_ROWS
    jae     .rows_done
    add     eax, [dbg_item_scroll]
    mov     edi, eax
    lea     rsi, [dbg_tf_search + TEXTFIELD.buf]
    call    debug_item_nth
    test    eax, eax
    jz      .rows_done
    mov     [rsp + 4], eax
    imul    ecx, [rsp], ITEM_PITCH
    add     ecx, [dbg_cy]
    add     ecx, 24
    mov     [rsp + 8], ecx
    mov     edi, [dbg_cx]
    mov     esi, [rsp + 8]
    mov     edx, ITEM_LIST_W
    mov     ecx, ITEM_PITCH
    call    dhit
    test    eax, eax
    jz      .not_hot
    mov     edi, [dbg_cx]
    mov     esi, [rsp + 8]
    mov     edx, ITEM_LIST_W
    mov     ecx, ITEM_PITCH
    mov     r8d, C_HOVER
    call    ui_rect
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .not_hot
    mov     eax, [rsp + 4]
    cmp     eax, [dbg_item_sel]
    je      .not_hot
    mov     [dbg_item_sel], eax         ; another item: its attachments start over
    mov     dword [dbg_att], 0
.not_hot:
    mov     eax, [rsp + 4]
    cmp     eax, [dbg_item_sel]
    jne     .unselected
    mov     edi, [dbg_cx]
    mov     esi, [rsp + 8]
    mov     edx, ITEM_LIST_W
    mov     ecx, ITEM_PITCH
    mov     r8d, C_GOLD_DEEP
    call    ui_frame
.unselected:
    mov     edi, [rsp + 4]
    mov     esi, [dbg_cx]
    add     esi, 1
    mov     edx, [rsp + 8]
    add     edx, 1
    mov     ecx, 12
    call    ui_item_icon
    mov     eax, [rsp + 4]
    lea     rcx, [item_names]
    mov     rdi, [rcx + rax*8]
    mov     esi, [dbg_cx]
    add     esi, 16
    mov     edx, [rsp + 8]
    add     edx, 3
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    inc     dword [rsp]
    jmp     .row
.rows_done:
    mov     eax, [dbg_cx]               ; the right column
    add     eax, ITEM_LIST_W + 8
    mov     [rsp + 12], eax
    mov     eax, [dbg_cw]
    sub     eax, ITEM_LIST_W + 8
    mov     [rsp + 16], eax
    mov     ebx, [dbg_item_sel]
    test    ebx, ebx
    jz      .ret
    mov     edi, ebx
    mov     esi, [rsp + 12]
    mov     edx, [dbg_cy]
    mov     ecx, 18
    call    ui_item_icon
    lea     rcx, [item_names]
    mov     rdi, [rcx + rbx*8]
    mov     esi, [rsp + 16]
    sub     esi, 22
    call    dclip
    mov     rdi, rax
    mov     esi, [rsp + 12]
    add     esi, 22
    mov     edx, [dbg_cy]
    add     edx, 5
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    mov     edi, ebx
    call    inv_count
    mov     r13d, eax
    lea     r15, [dbg_buf]
    APPZ    s_in_bag
    APPN    r13d
    SHOWBUF ITEM_LIST_W + 8, 24, C_INK_SOFT
    mov     edi, ebx
    call    gun_index
    xor     r14d, r14d
    xor     r13d, r13d
    test    eax, eax
    js      .not_gun
    mov     r14d, 1
    mov     r13d, [dbg_att]             ; a gun is given with the attachments chosen below
.not_gun:
    mov     dword [rsp + 24], 0         ; the give buttons: +1, +16, +64
.give:
    mov     eax, [rsp + 24]
    lea     rdx, [give_tab]
    imul    ecx, eax, 16
    mov     rdi, [rdx + rcx]
    mov     eax, [rdx + rcx + 8]
    mov     [rsp + 20], eax
    mov     edx, [rdx + rcx + 12]
    add     edx, [dbg_cy]
    mov     esi, [rsp + 12]
    mov     ecx, [rsp + 16]
    mov     r8d, 1
    xor     r9d, r9d
    call    dbtn
    test    eax, eax
    jz      .give_next
    mov     edi, ebx
    mov     esi, [rsp + 20]
    mov     edx, r13d
    call    debug_give
    mov     r12d, eax
    lea     r15, [dbg_buf]              ; "Gave 16 x Stone"
    APPZ    s_gave
    APPN    r12d
    APPZ    s_times
    lea     rcx, [item_names]
    mov     rsi, [rcx + rbx*8]
    APPP
    mov     byte [r15], 0
    lea     rdi, [dbg_buf]
    call    dnote
.give_next:
    inc     dword [rsp + 24]
    cmp     dword [rsp + 24], 3
    jb      .give
    test    r14d, r14d
    jz      .ret
    DTXT    s_attach, ITEM_LIST_W + 8, 90, C_RUBRIC
    mov     dword [rsp + 24], 0         ; the four attachment toggles
.att:
    mov     eax, [rsp + 24]
    lea     rdx, [att_tab]
    imul    ecx, eax, 16
    mov     rdi, [rdx + rcx]
    mov     r12d, [rdx + rcx + 8]       ; its ATT_* bit
    imul    edx, eax, 16
    add     edx, 102
    add     edx, [dbg_cy]
    mov     esi, [rsp + 12]
    mov     ecx, [rsp + 16]
    mov     r8d, 1
    xor     r9d, r9d
    test    [dbg_att], r12d
    setnz   r9b
    call    dbtn
    test    eax, eax
    jz      .att_next
    xor     [dbg_att], r12d
.att_next:
    inc     dword [rsp + 24]
    cmp     dword [rsp + 24], 4
    jb      .att
.ret:
    LEAVE_FRAME 40

; ---- the Enemies tab ---------------------------------------------------------------------------------
; The type (a grid of toggles), the level (0 = the player's), elite or not, the count, then Spawn, Kill all
; and Heal all. Under them the Events rows (y 128, 140, 158; the page leaves 174 above its footer): the running event's
; status, its five buttons (Camp, Caravan, Threat, Wave, Win) and the nearest camp's faction and absolute cell.
; r12d = the player's level, r13d = a level step; frame: [rsp] button width, [rsp+4] spawned
tab_enemies:
    ENTER_FRAME 24
    movzx   r12d, byte [rpg_state + RPGSAVE.level]
    mov     eax, [dbg_cw]
    sub     eax, 6
    shr     eax, 2
    mov     [rsp], eax
    xor     ebx, ebx
.type:
    mov     eax, ebx
    and     eax, 3
    mov     ecx, [rsp]
    add     ecx, 2
    imul    eax, ecx
    add     eax, [dbg_cx]
    mov     esi, eax
    mov     eax, ebx
    shr     eax, 2
    imul    eax, eax, 16
    add     eax, [dbg_cy]
    mov     edx, eax
    lea     rax, [mob_names]
    mov     rdi, [rax + rbx*8]
    mov     ecx, [rsp]
    mov     r8d, 1
    xor     r9d, r9d
    lea     eax, [rbx + 1]
    cmp     [dbg_mob_type], eax
    sete    r9b
    call    dbtn
    test    eax, eax
    jz      .type_next
    lea     eax, [rbx + 1]
    mov     [dbg_mob_type], eax
.type_next:
    inc     ebx
    cmp     ebx, 7
    jb      .type
    lea     r15, [dbg_buf]              ; "Level: 23 (yours)" or "Level: 40"
    APPZ    s_lvl_colon
    mov     eax, [dbg_mob_level]
    test    eax, eax
    jnz     .level_fixed
    APPN    r12d
    APPZ    s_yours
    jmp     .level_show
.level_fixed:
    APPN    eax
.level_show:
    SHOWBUF 0, 39, C_INK
    xor     ebx, ebx
.lv_btn:
    lea     rax, [lv_btn_tab]
    mov     ecx, ebx
    shl     ecx, 4
    mov     rdi, [rax + rcx]
    mov     r13d, [rax + rcx + 8]
    mov     esi, [rax + rcx + 12]
    add     esi, [dbg_cx]
    mov     edx, [dbg_cy]
    add     edx, 36
    mov     ecx, 24
    mov     r8d, 1
    xor     r9d, r9d
    call    dbtn
    test    eax, eax
    jz      .lv_next
    mov     eax, [dbg_mob_level]
    test    eax, eax
    cmovz   eax, r12d                   ; "yours" counts as the player's level
    add     eax, r13d
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx
    mov     ecx, 60
    cmp     eax, ecx
    cmovg   eax, ecx
    mov     [dbg_mob_level], eax
.lv_next:
    inc     ebx
    cmp     ebx, 4
    jb      .lv_btn
    DBTN    s_yours_btn, 216, 36, 48, 1, 0
    test    eax, eax
    jz      .elite
    mov     dword [dbg_mob_level], 0
.elite:
    lea     rdi, [s_elite_off]
    lea     rax, [s_elite_on]
    cmp     dword [dbg_mob_elite], 0
    cmovne  rdi, rax
    mov     r9d, [dbg_mob_elite]
    DBTNR   0, 56, 80, 1
    test    eax, eax
    jz      .count
    xor     dword [dbg_mob_elite], 1
.count:
    DTXT    s_count, 90, 59, C_INK
    xor     ebx, ebx
.count_btn:
    lea     rax, [count_tab]
    mov     ecx, ebx
    shl     ecx, 4
    mov     rdi, [rax + rcx]
    mov     r13d, [rax + rcx + 8]
    mov     esi, [rax + rcx + 12]
    add     esi, [dbg_cx]
    mov     edx, [dbg_cy]
    add     edx, 56
    mov     ecx, 24
    cmp     r13d, 10
    jb      .count_w
    mov     ecx, 30
.count_w:
    mov     r8d, 1
    xor     r9d, r9d
    cmp     [dbg_mob_count], r13d
    sete    r9b
    call    dbtn
    test    eax, eax
    jz      .count_next
    mov     [dbg_mob_count], r13d
.count_next:
    inc     ebx
    cmp     ebx, 3
    jb      .count_btn
    DBTN    s_spawn, 0, 78, 100, 1, 0
    test    eax, eax
    jz      .kill
    mov     edi, [dbg_mob_type]
    mov     esi, [dbg_mob_level]
    mov     edx, [dbg_mob_elite]
    mov     ecx, [dbg_mob_count]
    call    debug_spawn
    test    eax, eax
    jz      .nothing
    mov     ebx, eax
    lea     r15, [dbg_buf]
    APPZ    s_spawned
    APPN    ebx
    mov     byte [r15], 0
    lea     rdi, [dbg_buf]
    call    dnote
    jmp     .kill
.nothing:
    lea     rdi, [s_no_room]
    call    dnote
.kill:
    DBTN    s_kill, 104, 78, 90, 1, 0
    test    eax, eax
    jz      .heal
    call    debug_kill_all
    lea     rdi, [s_n_killed]
    call    dnote
.heal:
    DBTN    s_heal, 196, 78, 90, 1, 0
    test    eax, eax
    jz      .info
    call    debug_heal_all
    lea     rdi, [s_n_healed]
    call    dnote
.info:
    lea     r15, [dbg_buf]
    APPZ    s_mobs_alive
    mov     edi, 1
    call    mob_count_kind
    APPN    eax
    APPZ    s_hostile
    xor     edi, edi
    call    mob_count_kind
    APPN    eax
    APPZ    s_passive
    SHOWBUF 0, 100, C_INK
    DTXT    s_hint_spawn, 0, 116, C_INK_SOFT
    DTXT    s_events, 0, 128, C_RUBRIC
    lea     rdi, [dbg_buf]
    call    events_status               ; rax = the end of the status text
    mov     r15, rax
    SHOWBUF 52, 128, C_INK
    DBTN    s_ev_camp, 0, 140, 50, 1, 0
    test    eax, eax
    jz      .ev_caravan
    lea     rdi, [player]
    call    events_spawn_camp
    lea     rdi, [s_ev_started]
    lea     rsi, [s_ev_noroom]
    test    eax, eax
    cmovz   rdi, rsi
    call    dnote
.ev_caravan:
    DBTN    s_ev_caravan, 52, 140, 62, 1, 0
    test    eax, eax
    jz      .ev_threat
    lea     rdi, [player]
    call    events_spawn_caravan
    lea     rdi, [s_ev_started]
    lea     rsi, [s_ev_noroom]
    test    eax, eax
    cmovz   rdi, rsi
    call    dnote
.ev_threat:
    DBTN    s_ev_threat, 116, 140, 56, 1, 0
    test    eax, eax
    jz      .ev_wave
    call    events_force_threat
    lea     rdi, [s_ev_done]
    lea     rsi, [s_ev_no_camp]
    test    eax, eax
    cmovz   rdi, rsi
    call    dnote
.ev_wave:
    DBTN    s_ev_wave, 174, 140, 50, 1, 0
    test    eax, eax
    jz      .ev_win
    call    events_skip
    lea     rdi, [s_ev_done]
    lea     rsi, [s_ev_idle]
    test    eax, eax
    cmovz   rdi, rsi
    call    dnote
.ev_win:
    DBTN    s_ev_win, 226, 140, 46, 1, 0
    test    eax, eax
    jz      .ev_camp_line
    mov     edi, 1
    call    events_finish
    lea     rdi, [s_ev_done]
    call    dnote
.ev_camp_line:
    mov     edi, SITE_CAMP
    xor     esi, esi
    call    structures_nearest
    test    rax, rax
    jz      .ev_no_camp
    mov     rbx, rax
    lea     r15, [dbg_buf]              ; "Nearest camp: Bandits 1200, -340" (absolute cell)
    APPZ    s_nearest
    mov     eax, [rbx + SITE.index]
    lea     rcx, [faction_names]
    mov     rsi, [rcx + rax*8]
    APPP
    APPZ    s_ev_space
    mov     eax, [rbx + SITE.x]
    add     eax, [world_origin_x]
    APPN    eax
    APPZ    s_ev_comma
    mov     eax, [rbx + SITE.z]
    add     eax, [world_origin_z]
    APPN    eax
    SHOWBUF 0, 158, C_INK_SOFT
    jmp     .ev_done
.ev_no_camp:
    DTXT    s_nearest_none, 0, 158, C_INK_SOFT
.ev_done:
    LEAVE_FRAME 24

; ---- the World tab -----------------------------------------------------------------------------------
; The clock and its presets, the teleport (X Y Z fields, spawn, bed), reset cooldowns, clear drops and
; the five factions' standing. A teleport waits for the area, then closes the menu.
; r12d = Enter pressed in a field, r13d = a table row's value, r14d = its width; frame: [rsp] faction,
; [rsp+4] its row y
tab_world:
    ENTER_FRAME 24
    mov     eax, [game_time]            ; "Day 3   14:30": the day starts at 06:00 (50 steps a minute)
    xor     edx, edx
    mov     ecx, DAY_LENGTH
    div     ecx
    lea     r12d, [rax + 1]
    mov     eax, edx
    xor     edx, edx
    mov     ecx, 50
    div     ecx
    xor     edx, edx
    mov     ecx, 60
    div     ecx
    mov     r13d, edx                   ; minute
    add     eax, 6
    cmp     eax, 24
    jb      .hour_ok
    sub     eax, 24
.hour_ok:
    mov     r14d, eax                   ; hour
    lea     r15, [dbg_buf]
    APPZ    s_day
    APPN    r12d
    APPZ    s_gap
    mov     edi, r14d
    mov     rsi, r15
    call    put2d
    mov     r15, rax
    APPZ    s_colon
    mov     edi, r13d
    mov     rsi, r15
    call    put2d
    mov     r15, rax
    SHOWBUF 0, 2, C_RUBRIC
    xor     ebx, ebx
.time_btn:
    lea     rax, [time_tab]
    mov     ecx, ebx
    imul    ecx, ebx, 24
    mov     rdi, [rax + rcx]
    mov     r13d, [rax + rcx + 8]
    mov     esi, [rax + rcx + 12]
    add     esi, [dbg_cx]
    mov     r14d, [rax + rcx + 16]
    mov     edx, [dbg_cy]
    add     edx, 11
    mov     ecx, r14d
    mov     r8d, 1
    xor     r9d, r9d
    call    dbtn
    test    eax, eax
    jz      .time_next
    cmp     r13d, -1
    je      .time_hour
    mov     edi, r13d
    call    debug_set_time
    jmp     .time_next
.time_hour:
    mov     edi, DEBUG_HOUR
    call    debug_add_time
.time_next:
    inc     ebx
    cmp     ebx, 5
    jb      .time_btn
    DTXT    s_x, 0, 34, C_INK           ; the teleport row
    lea     rdi, [debug_coord_fields]
    mov     esi, [dbg_cx]
    add     esi, 8
    mov     edx, [dbg_cy]
    add     edx, 29
    mov     ecx, 54
    call    ui_textfield
    mov     r12d, eax
    DTXT    s_y, 68, 34, C_INK
    lea     rdi, [debug_coord_fields + TEXTFIELD_size]
    mov     esi, [dbg_cx]
    add     esi, 76
    mov     edx, [dbg_cy]
    add     edx, 29
    mov     ecx, 38
    call    ui_textfield
    or      r12d, eax
    DTXT    s_z, 118, 34, C_INK
    lea     rdi, [debug_coord_fields + 2 * TEXTFIELD_size]
    mov     esi, [dbg_cx]
    add     esi, 126
    mov     edx, [dbg_cy]
    add     edx, 29
    mov     ecx, 54
    call    ui_textfield
    or      r12d, eax
    DBTN    s_go, 186, 32, 36, 1, 0
    or      r12d, eax
    test    r12d, r12d
    jz      .no_go
    call    debug_go
    test    eax, eax
    jz      .bad_coords
    call    tp_finish
    jmp     .ret
.bad_coords:
    lea     rdi, [s_bad_coords]
    call    dnote
.no_go:
    DBTN    s_to_spawn, 0, 53, 62, 1, 0
    test    eax, eax
    jz      .bed
    call    debug_to_spawn
    call    tp_finish
    jmp     .ret
.bed:
    xor     r13d, r13d
    cmp     dword [world_header + WORLDHDR.bed_set], 0
    setne   r13b
    DBTN    s_to_bed, 64, 53, 50, r13d, 0
    test    eax, eax
    jz      .cooldowns
    call    debug_to_bed
    call    tp_finish
    jmp     .ret
.cooldowns:
    DBTN    s_reset_cd, 0, 69, 112, 1, 0
    test    eax, eax
    jz      .drops
    call    debug_reset_cooldowns
    lea     rdi, [s_n_cooldowns]
    call    dnote
.drops:
    DBTN    s_clear_drops, 114, 69, 80, 1, 0
    test    eax, eax
    jz      .factions
    call    debug_clear_drops
    lea     rdi, [s_n_drops]
    call    dnote
.factions:
    DTXT    s_factions, 0, 86, C_RUBRIC
    xor     ebx, ebx
.fac:
    imul    eax, ebx, 15
    add     eax, [dbg_cy]
    add     eax, 97
    mov     [rsp + 4], eax
    lea     rax, [faction_names]
    mov     rdi, [rax + rbx*8]
    mov     esi, [dbg_cx]
    mov     edx, [rsp + 4]
    add     edx, 3
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    mov     edi, ebx
    call    faction_standing
    lea     r15, [dbg_buf]
    APPN    eax
    mov     byte [r15], 0
    lea     rdi, [dbg_buf]
    mov     esi, [dbg_cx]
    add     esi, 74
    mov     edx, [rsp + 4]
    add     edx, 3
    mov     ecx, C_INK
    mov     r8d, 1
    call    ui_text_ink
    mov     edi, ebx
    call    faction_tier
    lea     rcx, [tier_names]
    mov     rdi, [rcx + rax*8]
    mov     esi, [dbg_cx]
    add     esi, 112
    mov     edx, [rsp + 4]
    add     edx, 3
    mov     ecx, C_INK_SOFT
    mov     r8d, 1
    call    ui_text_ink
    xor     r15d, r15d
.fac_btn:
    lea     rax, [fac_btn_tab]
    imul    ecx, r15d, 24
    mov     rdi, [rax + rcx]
    mov     r13d, [rax + rcx + 8]       ; the change
    mov     esi, [dbg_cx]
    add     esi, [dbg_cw]
    sub     esi, [rax + rcx + 12]       ; x counted back from the right edge
    mov     r14d, [rax + rcx + 16]
    mov     edx, [rsp + 4]
    mov     ecx, r14d
    mov     r8d, 1
    xor     r9d, r9d
    call    dbtn
    test    eax, eax
    jz      .fac_next
    mov     edi, ebx
    mov     esi, r13d
    call    faction_add
.fac_next:
    inc     r15d
    cmp     r15d, 3
    jb      .fac_btn
    inc     ebx
    cmp     ebx, NUM_FACTIONS
    jb      .fac
.ret:
    LEAVE_FRAME 24

; debug_frame(): the screen of ST_DEBUG, once per frame after ui_begin. The frame's time is turned into
; steps for the F12 count (the world is paused, nothing else ticks it); the third F12 or Escape closes the
; menu. Then a dimmer, the page with its ribbon and tabs, the open tab and the footer.
; frame: [rsp] unused
debug_frame:
    ENTER_FRAME 8
    cmp     byte [net_role], NET_ROLE_OFF
    jne     .poll                       ; a multiplayer world keeps stepping (sim_step runs debug_step): no clock here
    movss   xmm0, [hud_dt]
    addss   xmm0, [dbg_acc]
.steps:
    comiss  xmm0, [k_step]
    jb      .steps_done
    subss   xmm0, [k_step]
    movss   [dbg_acc], xmm0
    call    debug_step
    movss   xmm0, [dbg_acc]
    jmp     .steps
.steps_done:
    movss   [dbg_acc], xmm0
.poll:
    call    debug_poll
    cmp     dword [debug_open], 0
    je      .close
    cmp     dword [ui_input + UIINPUT.escape], 0
    jne     .close
    call    page_geometry
    xor     edi, edi
    xor     esi, esi
    mov     edx, [ui_w]
    mov     ecx, [ui_h]
    mov     r8d, C_DIM
    call    ui_rect
    mov     edi, [dbg_px]
    mov     esi, [dbg_py]
    mov     edx, [dbg_pw]
    mov     ecx, PNL_H
    call    ui_panel
    lea     rdi, [s_title]
    mov     esi, [dbg_pw]
    shr     esi, 1
    add     esi, [dbg_px]
    mov     edx, [dbg_py]
    sub     edx, 7
    call    ui_ribbon
    call    draw_tabs
    mov     edi, [dbg_px]
    add     edi, 8
    mov     esi, [dbg_py]
    add     esi, 27
    mov     edx, [dbg_pw]
    sub     edx, 16
    mov     ecx, 1
    mov     r8d, C_GOLD_DEEP
    call    ui_rect
    mov     eax, [dbg_tab]
    lea     rcx, [tab_funcs]
    call    qword [rcx + rax*8]
    cmp     dword [debug_open], 0
    je      .close                      ; a teleport closed it
    call    draw_footer
    jmp     .ret
.close:
    call    dclose
.ret:
    LEAVE_FRAME 8
