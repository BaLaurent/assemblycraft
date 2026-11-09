; test_debugmenu.asm - the debug menu's logic (0.10.5): the F12 detector, the cheater mark (the header byte,
; a save and a load, the world list), and what the actions do: items, the item filter, levels and points,
; enemies, the clock, the teleport, stat bonuses, restore, god mode, fly, game mode, cooldowns, drops and
; the factions. The screen only draws and calls these, so the screen itself is checked live.
%include "common.inc"
%include "gl.inc"
default rel

global test_debug_f12_detector, test_debug_cheater_mark_roundtrip, test_debug_world_list_flag
global test_debug_give_items, test_debug_item_filter, test_debug_levels_and_points
global test_debug_spawn_and_kill, test_debug_time_and_teleport, test_debug_stat_bonus
global test_debug_vitals_and_toggles, test_debug_step_clock, test_debug_to_spawn_and_bed

extern world_clear, world_set, world_header, world_origin_x, world_origin_z, rng_seed
extern debug_open, debug_reset, debug_step, debug_press, debug_other_key, debug_poll, debug_close
extern debug_is_cheater, debug_mark_cheater, debug_give, debug_spawn, debug_kill_all, debug_heal_all
extern debug_set_time, debug_add_time, debug_stat_range, debug_bonus_add, debug_full_restore
extern debug_toggle_god, debug_toggle_fly, debug_toggle_mode, debug_reset_cooldowns, debug_clear_drops
extern debug_parse_int, debug_fill_coords, debug_go, debug_coord_fields, debug_item_nth, debug_item_count
extern debug_to_spawn, debug_to_bed
extern ui_input, player, body_init, game_time, game_mode, settings, sky_is_night
extern game_frame, frame_input, input_captured, game_open_screen, game_heavy_s, game_break_progress, brk_y
extern game_on_area_ready
extern mobs, mobs_clear, mob_spawn, mob_set_level, mob_count_type, mob_count_kind
extern drops, drops_clear, drops_spawn
extern inv, inv_clear, inv_add, inv_count
extern rpg_state, rpg_reset, rpg_level, rpg_points, rpg_attr_points, rpg_rank, rpg_attr, rpg_stat
extern rpg_spend, rpg_spend_attr, rpg_set_level, rpg_add_bonus_points, rpg_respec_free, rpg_recompute
extern rpg_bar_ability, rpg_save, rpg_load, rpg_migrated
extern surv, surv_max_health, survival_reset, survival_damage, survival_dot
extern combat_reset, combat_stamina
extern abilities_reset, abilities_cd, abilities_cd_total, abilities_bolt_cd
extern faction_reset, faction_add, faction_standing
extern game_new, game_save, game_load, game_teleport
extern file_read, file_write_atomic, mkdir_p, dir_remove_tree, str_copy, str_eq
extern saves_init, saves_scan, world_list, world_count
extern item_max_stack

%define WEBN(a, n) (NUM_ARCHETYPES + ((a) - 1) * 18 + (n))

section .rodata
align 4
k_half_w:   dd 0.3
k_height:   dd 1.8
k_speed:    dd 4.317
k_16_5:     dd 16.5
k_16:       dd 16.0
k_64:       dd 64.0
k_19_5:     dd 19.5
k_3_5:      dd 3.5
k_11:       dd 11.0
k_step:     dd 0.016666668              ; one fixed step: game_frame runs exactly one sim_step
d_world_str:   db "/tmp/assemblycraft-selftest-dbg-world", 0
d_regions_str: db "/tmp/assemblycraft-selftest-dbg-world/regions", 0
p_hdr:         db "/tmp/assemblycraft-selftest-dbg-world/world.hdr", 0
name_dbg:      db "Debugged", 0
name_other:    db "Elsewhere", 0
d_data:        db "/tmp/assemblycraft-selftest-dbg-data", 0
w_marked:      db "/tmp/assemblycraft-selftest-dbg-data/worlds/Marked", 0
w_plain:       db "/tmp/assemblycraft-selftest-dbg-data/worlds/Plain", 0
w_marked_regions: db "/tmp/assemblycraft-selftest-dbg-data/worlds/Marked/regions", 0
w_plain_regions:  db "/tmp/assemblycraft-selftest-dbg-data/worlds/Plain/regions", 0
p_marked_hdr:  db "/tmp/assemblycraft-selftest-dbg-data/worlds/Marked/world.hdr", 0
p_plain_hdr:   db "/tmp/assemblycraft-selftest-dbg-data/worlds/Plain/world.hdr", 0
n_marked:      db "Marked", 0
n_plain:       db "Plain", 0
t_0:           db "0", 0
t_999:         db "999", 0
t_5000:        db "5000", 0
t_80:          db "80", 0
t_m3000:       db "-3000", 0
t_abc:         db "abc", 0
t_huge:        db "99999999999", 0
t_m7:          db "-7", 0
t_p3:          db "+3", 0
t_sp5sp:       db "  5  ", 0
t_12:          db "12", 0
t_empty:       db 0
t_minus:       db "-", 0
t_1x:          db "1x", 0
t_mm1:         db "--1", 0
t_pickaxe:     db "pickaxe", 0
t_PICKAXE:     db "PICKAXE", 0
t_ickax:       db "iCkAx", 0
t_zzz:         db "zzz", 0

section .bss
alignb 8
d_world:    resb 64
dir_buf:    resb 128
file_buf:   resb WORLD_HDR_SIZE + 16
hdr_img:    resb WORLD_HDR_SIZE
out_i32:    resd 1

section .text

; STEPS n: the detector's clock runs n fixed steps (clobbers ebx)
%macro STEPS 1
    mov     ebx, %1
%%l:
    call    debug_step
    dec     ebx
    jnz     %%l
%endmacro

; PRESS n: an F12 press that must answer n
%macro PRESS 1
    call    debug_press
    cmp     eax, %1
    jne     .fail
%endmacro

; SETB x, y, z, id: one block set in the arena (clobbers the argument registers)
%macro SETB 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set
%endmacro
; SPAWN1: debug_spawn of one plain zombie at the player's level, which must be placed
%macro SPAWN1 0
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    xor     edx, edx
    mov     ecx, 1
    call    debug_spawn
    cmp     eax, 1
    jne     .fail
%endmacro

; fixture(): the state every debug test starts from: the arena of ready columns with a STONE floor at y = 10
; for x, z in 0..31, no mobs, drops or items, Survival at Normal difficulty, a fresh level-1 character
; (no debug bonus) with full health, the menu closed with its F12 count cleared and no cheater mark, the
; player standing at (16.5, 11, 16.5) facing north (yaw 0 looks towards -z)
fixture:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    mov     edi, 1234
    call    rng_seed
    call    mobs_clear
    call    drops_clear
    call    inv_clear
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [game_time], NEW_WORLD_TIME
    call    rpg_reset
    call    survival_reset
    call    combat_reset
    call    abilities_reset
    call    debug_reset
    mov     byte [world_header + WORLDHDR.cheater], 0
    mov     dword [ui_input + UIINPUT.key_pressed], -1
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    mov     dword [player + BODY.x], __float32__(16.5)
    mov     dword [player + BODY.y], __float32__(11.0)
    mov     dword [player + BODY.z], __float32__(16.5)
    xor     r12d, r12d                  ; z
.z:
    xor     ebx, ebx                    ; x
.x:
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 32
    jb      .x
    inc     r12d
    cmp     r12d, 32
    jb      .z
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- the F12 detector ---------------------------------------------------------------------------------

; Three presses with at most 60 steps between them open the menu and mark the world; two presses, a gap of
; 61 steps (the late press starts a new count, it does not finish the old one) or another key in between
; do not; a frame without a key does not count as another key; the third press of an open menu closes it;
; debug_close and debug_reset close it too.
test_debug_f12_detector:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    fixture
    PRESS   0                           ; exactly one second between presses is still in time
    STEPS   60
    PRESS   0
    STEPS   60
    cmp     dword [debug_open], 0
    jne     .fail
    cmp     byte [world_header + WORLDHDR.cheater], 0
    jne     .fail                       ; nothing marks the world before the menu opens
    PRESS   1
    cmp     dword [debug_open], 1
    jne     .fail
    cmp     byte [world_header + WORLDHDR.cheater], 1
    jne     .fail
    call    debug_is_cheater
    cmp     eax, 1
    jne     .fail
    lea     rdi, [debug_coord_fields + TEXTFIELD.buf]   ; the teleport fields hold the player's cell (16, 11, 16)
    lea     rsi, [t_16]
    call    str_eq
    cmp     eax, 1
    jne     .fail
    lea     rdi, [debug_coord_fields + TEXTFIELD_size + TEXTFIELD.buf]
    lea     rsi, [t_11]
    call    str_eq
    cmp     eax, 1
    jne     .fail
    lea     rdi, [debug_coord_fields + 2 * TEXTFIELD_size + TEXTFIELD.buf]
    lea     rsi, [t_16]
    call    str_eq
    cmp     eax, 1
    jne     .fail
    PRESS   0                           ; open: three more presses close it
    PRESS   0
    PRESS   0
    cmp     dword [debug_open], 0
    jne     .fail
    call    fixture                     ; two presses do not open it
    PRESS   0
    STEPS   10
    PRESS   0
    cmp     dword [debug_open], 0
    jne     .fail
    cmp     byte [world_header + WORLDHDR.cheater], 0
    jne     .fail
    call    fixture                     ; a gap of 61 steps: the late press is the first of a new count
    PRESS   0
    PRESS   0
    STEPS   61
    PRESS   0
    cmp     dword [debug_open], 0
    jne     .fail
    PRESS   0
    cmp     dword [debug_open], 0
    jne     .fail
    PRESS   1                           ; ... which two more presses finish
    call    fixture                     ; another key in between starts the count over
    PRESS   0
    PRESS   0
    call    debug_other_key
    PRESS   0
    PRESS   0
    cmp     dword [debug_open], 0
    jne     .fail
    PRESS   1
    call    fixture                     ; the same through the frame's key press (debug_poll)
    mov     dword [ui_input + UIINPUT.key_pressed], KEY_F12
    call    debug_poll
    test    eax, eax
    jnz     .fail
    call    debug_poll
    test    eax, eax
    jnz     .fail
    mov     dword [ui_input + UIINPUT.key_pressed], KEY_W
    call    debug_poll                  ; a W press: the two F12 presses are forgotten
    test    eax, eax
    jnz     .fail
    mov     dword [ui_input + UIINPUT.key_pressed], KEY_F12
    call    debug_poll
    call    debug_poll
    test    eax, eax
    jnz     .fail
    mov     dword [ui_input + UIINPUT.key_pressed], -1
    call    debug_poll                  ; a frame without a key press changes nothing
    test    eax, eax
    jnz     .fail
    cmp     dword [debug_open], 0
    jne     .fail
    mov     dword [ui_input + UIINPUT.key_pressed], KEY_F12
    call    debug_poll
    cmp     eax, 1
    jne     .fail
    cmp     dword [debug_open], 1
    jne     .fail
    call    debug_close                 ; closing: the flag drops, the mark stays, three presses open it again
    cmp     dword [debug_open], 0
    jne     .fail
    cmp     byte [world_header + WORLDHDR.cheater], 1
    jne     .fail
    PRESS   0
    PRESS   0
    PRESS   1
    call    debug_reset                 ; a new session: closed, and a half count is forgotten
    cmp     dword [debug_open], 0
    jne     .fail
    PRESS   0
    call    debug_reset
    PRESS   0
    PRESS   0
    cmp     dword [debug_open], 0
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    mov     byte [world_header + WORLDHDR.cheater], 0
    mov     dword [ui_input + UIINPUT.key_pressed], -1
    call    debug_reset
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- the cheater mark ---------------------------------------------------------------------------------

; dump_hdr(): world.hdr read into file_buf -> eax 0 when it is one whole header
dump_hdr:
    sub     rsp, 8
    lea     rdi, [p_hdr]
    lea     rsi, [file_buf]
    mov     edx, WORLD_HDR_SIZE + 16
    call    file_read
    xor     ecx, ecx
    cmp     rax, WORLD_HDR_SIZE
    setne   cl
    mov     eax, ecx
    add     rsp, 8
    ret

; A new world is not cheated; debug_mark_cheater sets the header byte at offset 605; a save writes it
; (and the debug stat bonus next to it), a new world starts clean, a load brings both back; a header whose
; byte is 0 (a save from before the menu) loads as not cheated; the third F12 marks a loaded world again.
test_debug_cheater_mark_roundtrip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    fixture
    lea     rdi, [d_world]
    lea     rsi, [d_world_str]
    mov     edx, 63
    call    str_copy
    lea     rdi, [d_world]
    call    dir_remove_tree
    lea     rdi, [dir_buf]
    lea     rsi, [d_regions_str]
    mov     edx, 127
    call    str_copy
    lea     rdi, [dir_buf]
    call    mkdir_p
    test    eax, eax
    jnz     .fail
    mov     edi, 42
    mov     esi, MODE_SURVIVAL
    lea     rdx, [name_dbg]
    lea     rcx, [d_world]
    call    game_new
    call    debug_is_cheater
    test    eax, eax
    jnz     .fail                       ; a new world is clean
    cmp     byte [world_header + 605], 0
    jne     .fail
    mov     edi, STAT_MELEE_DMG         ; a debug stat bonus rides along with the mark
    mov     esi, 5
    call    debug_bonus_add
    call    debug_mark_cheater
    call    debug_is_cheater
    cmp     eax, 1
    jne     .fail
    cmp     byte [world_header + 605], 1
    jne     .fail                       ; the mark is the byte at offset 605
    lea     rdi, [d_world]
    call    game_save
    test    eax, eax
    jnz     .fail
    call    dump_hdr
    test    eax, eax
    jnz     .fail
    cmp     byte [file_buf + 605], 1
    jne     .fail
    cmp     word [file_buf + 16656 + STAT_MELEE_DMG * 2], 5
    jne     .fail                       ; the bonus is the word at 16656 + 2 * stat
    PRESS   0                           ; a menu open when its world is replaced is closed in the next one
    PRESS   0
    PRESS   1
    mov     edi, 1                      ; another new world: neither the mark nor the bonus
    mov     esi, MODE_CREATIVE
    lea     rdx, [name_other]
    xor     ecx, ecx
    call    game_new
    cmp     dword [debug_open], 0
    jne     .fail
    call    debug_is_cheater
    test    eax, eax
    jnz     .fail
    mov     edi, STAT_MELEE_DMG
    call    rpg_stat
    test    eax, eax
    jnz     .fail
    PRESS   0
    PRESS   0
    PRESS   1
    lea     rdi, [d_world]              ; the load brings both back
    call    game_load
    test    eax, eax
    jnz     .fail
    cmp     dword [debug_open], 0
    jne     .fail
    call    debug_is_cheater
    cmp     eax, 1
    jne     .fail
    mov     edi, STAT_MELEE_DMG
    call    rpg_stat
    cmp     eax, 5
    jne     .fail
    mov     byte [file_buf + 605], 0    ; a header from before the menu: not cheated
    lea     rdi, [p_hdr]
    lea     rsi, [file_buf]
    mov     edx, WORLD_HDR_SIZE
    call    file_write_atomic
    test    eax, eax
    jnz     .fail
    lea     rdi, [d_world]
    call    game_load
    test    eax, eax
    jnz     .fail
    call    debug_is_cheater
    test    eax, eax
    jnz     .fail
    PRESS   0                           ; the third F12 marks the loaded world
    PRESS   0
    PRESS   1
    call    debug_is_cheater
    cmp     eax, 1
    jne     .fail
    lea     rdi, [d_world]
    call    game_save
    test    eax, eax
    jnz     .fail
    call    dump_hdr
    test    eax, eax
    jnz     .fail
    cmp     byte [file_buf + 605], 1
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    lea     rdi, [d_world]
    call    dir_remove_tree
    mov     byte [world_header + WORLDHDR.cheater], 0
    call    debug_reset
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; make_world(rdi dir, rsi regions dir, rdx header path, rcx name, r8d cheater) -> eax 0 / -errno: a 0.9 world
; directory with a world.hdr (magic, name, seed 7, the cheater byte as given)
; rbx = header path, r12d = cheater
make_world:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdx
    mov     r12d, r8d
    mov     r13, rcx
    lea     rdi, [dir_buf]              ; mkdir_p writes into its path: a copy, and it makes <dir> on the way
    mov     edx, 127                    ; to <dir>/regions
    call    str_copy
    lea     rdi, [dir_buf]
    call    mkdir_p
    test    eax, eax
    jnz     .ret
    lea     rdi, [hdr_img]
    mov     ecx, WORLD_HDR_SIZE
    xor     eax, eax
    rep     stosb
    mov     rax, "ACRAFT06"
    mov     [hdr_img + WORLDHDR.magic], rax
    lea     rdi, [hdr_img + WORLDHDR.name]
    mov     rsi, r13
    mov     edx, 32
    call    str_copy
    mov     dword [hdr_img + WORLDHDR.seed], 7
    mov     [hdr_img + WORLDHDR.cheater], r12b
    mov     rdi, rbx
    lea     rsi, [hdr_img]
    mov     edx, WORLD_HDR_SIZE
    call    file_write_atomic
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; entry_of(rdi name) -> rax the world_list entry of that name, 0 when there is none
; r12 = name, ebx = index, r13 = the entry
entry_of:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12, rdi
    xor     ebx, ebx
.l:
    cmp     ebx, [world_count]
    jae     .none
    mov     eax, ebx
    shl     eax, 7                      ; WORLDENTRY_size = 128
    lea     r13, [world_list]
    add     r13, rax
    lea     rdi, [r13 + WORLDENTRY.name]
    mov     rsi, r12
    call    str_eq
    cmp     eax, 1
    je      .found
    inc     ebx
    jmp     .l
.found:
    mov     rax, r13
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

; The world list reads the mark of each world's header: the world whose byte 605 is 1 lists with
; WORLDENTRY.cheater 1, the other with 0.
test_debug_world_list_flag:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    fixture
    lea     rdi, [d_data]
    call    dir_remove_tree
    xor     edi, edi
    lea     rsi, [d_data]
    call    saves_init
    test    eax, eax
    jnz     .fail
    lea     rdi, [w_marked]
    lea     rsi, [w_marked_regions]
    lea     rdx, [p_marked_hdr]
    lea     rcx, [n_marked]
    mov     r8d, 1
    call    make_world
    test    eax, eax
    jnz     .fail
    lea     rdi, [w_plain]
    lea     rsi, [w_plain_regions]
    lea     rdx, [p_plain_hdr]
    lea     rcx, [n_plain]
    xor     r8d, r8d
    call    make_world
    test    eax, eax
    jnz     .fail
    call    saves_scan
    cmp     eax, 2
    jne     .fail
    lea     rdi, [n_marked]
    call    entry_of
    test    rax, rax
    jz      .fail
    cmp     dword [rax + WORLDENTRY.valid], 1
    jne     .fail
    cmp     dword [rax + WORLDENTRY.cheater], 1
    jne     .fail
    lea     rdi, [n_plain]
    call    entry_of
    test    rax, rax
    jz      .fail
    cmp     dword [rax + WORLDENTRY.valid], 1
    jne     .fail
    cmp     dword [rax + WORLDENTRY.cheater], 0
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    lea     rdi, [d_data]
    call    dir_remove_tree
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- items --------------------------------------------------------------------------------------------

; slot_of(edi id) -> rax the first inventory slot holding that item with a count, 0 when none
slot_of:
    lea     rax, [inv]
    xor     ecx, ecx
.l:
    cmp     byte [rax + ITEMSTACK.count], 0
    je      .next
    cmp     [rax + ITEMSTACK.id], dil
    je      .ret
.next:
    add     rax, 4
    inc     ecx
    cmp     ecx, INV_SLOTS
    jb      .l
    xor     eax, eax
.ret:
    ret

; A click gives up to one stack of the item (a tool: one), merging into the stack already there and then a
; free slot; the number handed out is the answer; a gun is given with the damage word asked for (its
; attachments); an id that is no item, or a count below 1, gives nothing; what does not fit lies at the
; player's feet.
test_debug_give_items:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    fixture
    mov     edi, COBBLE
    mov     esi, 16
    xor     edx, edx
    call    debug_give
    cmp     eax, 16
    jne     .fail
    cmp     byte [inv + INVENTORY.slots + ITEMSTACK.id], COBBLE
    jne     .fail
    cmp     byte [inv + INVENTORY.slots + ITEMSTACK.count], 16
    jne     .fail
    mov     edi, COBBLE                 ; merges into the same stack
    mov     esi, 16
    xor     edx, edx
    call    debug_give
    cmp     eax, 16
    jne     .fail
    cmp     byte [inv + INVENTORY.slots + ITEMSTACK.count], 32
    jne     .fail
    cmp     byte [inv + INVENTORY.slots + 4 + ITEMSTACK.count], 0
    jne     .fail
    mov     edi, COBBLE                 ; a click gives at most a stack: 64 of 100 asked; the first stack
    mov     esi, 100                    ; fills up to 64 and the rest goes to the next slot
    xor     edx, edx
    call    debug_give
    cmp     eax, 64
    jne     .fail
    cmp     byte [inv + INVENTORY.slots + ITEMSTACK.count], 64
    jne     .fail
    cmp     byte [inv + INVENTORY.slots + 4 + ITEMSTACK.id], COBBLE
    jne     .fail
    cmp     byte [inv + INVENTORY.slots + 4 + ITEMSTACK.count], 32
    jne     .fail
    mov     edi, IRON_PICKAXE           ; a tool stacks to 1: +64 gives one
    mov     esi, 64
    xor     edx, edx
    call    debug_give
    cmp     eax, 1
    jne     .fail
    mov     edi, IRON_PICKAXE
    call    inv_count
    cmp     eax, 1
    jne     .fail
    mov     edi, PISTOL                 ; a gun with a scope and an extended magazine fitted
    mov     esi, 1
    mov     edx, ATT_SCOPE | ATT_EXTMAG
    call    debug_give
    cmp     eax, 1
    jne     .fail
    mov     edi, PISTOL
    call    slot_of
    test    rax, rax
    jz      .fail
    cmp     word [rax + ITEMSTACK.dmg], ATT_SCOPE | ATT_EXTMAG
    jne     .fail
    xor     edi, edi                    ; air, an unused id, an id past the table, no count, a negative count
    mov     esi, 5
    xor     edx, edx
    call    debug_give
    test    eax, eax
    jnz     .fail
    mov     edi, FIRST_ITEM - 3
    mov     esi, 5
    xor     edx, edx
    call    debug_give
    test    eax, eax
    jnz     .fail
    mov     edi, NUM_ITEMS
    mov     esi, 5
    xor     edx, edx
    call    debug_give
    test    eax, eax
    jnz     .fail
    mov     edi, COBBLE
    xor     esi, esi
    xor     edx, edx
    call    debug_give
    test    eax, eax
    jnz     .fail
    mov     edi, COBBLE
    mov     esi, -5
    xor     edx, edx
    call    debug_give
    test    eax, eax
    jnz     .fail
    lea     rdi, [drops]                ; nothing lay on the ground so far
    xor     ecx, ecx
.no_drops:
    cmp     byte [rdi + DROP.id], 0
    jne     .fail
    add     rdi, DROP_size
    inc     ecx
    cmp     ecx, MAX_DROPS
    jb      .no_drops
    call    inv_clear                   ; a full bag: 36 full stacks of stone; the 16 more drop at the feet
    xor     ecx, ecx
.fill:
    lea     rax, [inv + INVENTORY.slots + rcx*4]
    mov     byte [rax + ITEMSTACK.id], STONE
    mov     byte [rax + ITEMSTACK.count], 64
    mov     word [rax + ITEMSTACK.dmg], 0
    inc     ecx
    cmp     ecx, INV_SLOTS
    jb      .fill
    mov     edi, STONE
    mov     esi, 16
    xor     edx, edx
    call    debug_give
    cmp     eax, 16
    jne     .fail
    mov     edi, STONE
    call    inv_count
    cmp     eax, 64 * INV_SLOTS
    jne     .fail
    lea     rdi, [drops]
    xor     ecx, ecx
    xor     edx, edx                    ; stone dropped, counted
.drop:
    cmp     byte [rdi + DROP.id], STONE
    jne     .drop_next
    movzx   eax, byte [rdi + DROP.count]
    add     edx, eax
.drop_next:
    add     rdi, DROP_size
    inc     ecx
    cmp     ecx, MAX_DROPS
    jb      .drop
    cmp     edx, 16
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    drops_clear
    call    inv_clear
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; The item filter matches a piece of a name in any case: "pickaxe", "PICKAXE" and "iCkAx" find the five
; pickaxes in id order; an empty filter lists every item (an id with a stack size, not air); a filter that
; matches nothing lists nothing; n counts from 0 and runs out.
test_debug_item_filter:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     rsi, [t_pickaxe]
    call    debug_item_count
    cmp     eax, 5
    jne     .fail
    lea     rsi, [t_PICKAXE]
    call    debug_item_count
    cmp     eax, 5
    jne     .fail
    lea     rsi, [t_ickax]
    call    debug_item_count
    cmp     eax, 5
    jne     .fail
    xor     edi, edi
    lea     rsi, [t_pickaxe]
    call    debug_item_nth
    cmp     eax, WOOD_PICKAXE
    jne     .fail
    mov     edi, 4
    lea     rsi, [t_PICKAXE]
    call    debug_item_nth
    cmp     eax, DIAMOND_PICKAXE
    jne     .fail
    mov     edi, 5
    lea     rsi, [t_pickaxe]
    call    debug_item_nth
    test    eax, eax
    jnz     .fail
    lea     rsi, [t_zzz]
    call    debug_item_count
    test    eax, eax
    jnz     .fail
    xor     edi, edi
    lea     rsi, [t_zzz]
    call    debug_item_nth
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx                    ; the empty filter: every id with a stack size, from id 1
    mov     edx, 1
.every:
    lea     rax, [item_max_stack]
    cmp     byte [rax + rdx], 0
    setne   al
    movzx   eax, al
    add     ebx, eax
    inc     edx
    cmp     edx, NUM_ITEMS
    jb      .every
    lea     rsi, [t_empty]
    call    debug_item_count
    cmp     eax, ebx
    jne     .fail
    xor     edi, edi
    lea     rsi, [t_empty]
    call    debug_item_nth
    cmp     eax, 1                      ; stone is the first item
    jne     .fail
    lea     edi, [rbx - 1]
    lea     rsi, [t_empty]
    call    debug_item_nth
    cmp     eax, COMPENSATOR            ; the last item
    jne     .fail
    mov     edi, ebx
    lea     rsi, [t_empty]
    call    debug_item_nth
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- the character ------------------------------------------------------------------------------------

; The level setter clamps to 1..50 and empties the XP bar; raising pays out like a level-up (health full),
; lowering does not; skill and attribute points can be added on top of the level's, and they count when
; the rules are checked (the web: ranks within level + points); a level or a bonus too low for the spent
; ranks or attribute points hands them all back; the free respec hands everything back for no coins and
; keeps the bonus points.
test_debug_levels_and_points:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    fixture
    mov     dword [surv + SURVIVAL.health], 1
    mov     dword [rpg_state + RPGSAVE.xp], 7
    mov     edi, 30
    call    rpg_set_level
    cmp     eax, 30
    jne     .fail
    call    rpg_level
    cmp     eax, 30
    jne     .fail
    cmp     dword [rpg_state + RPGSAVE.xp], 0
    jne     .fail
    call    rpg_points
    cmp     eax, 30
    jne     .fail
    call    rpg_attr_points
    cmp     eax, 87
    jne     .fail
    mov     eax, [surv_max_health]
    cmp     eax, 20 + 2 * 29
    jne     .fail
    cmp     [surv + SURVIVAL.health], eax
    jne     .fail                       ; a higher level: full health
    mov     dword [surv + SURVIVAL.health], 1
    mov     edi, 20
    call    rpg_set_level
    cmp     dword [surv + SURVIVAL.health], 1
    jne     .fail                       ; a lower one: nothing is refilled
    mov     edi, 20
    call    rpg_set_level
    cmp     dword [surv + SURVIVAL.health], 1
    jne     .fail                       ; the same level: neither
    xor     edi, edi                    ; clamped
    call    rpg_set_level
    cmp     eax, 1
    jne     .fail
    mov     edi, 99
    call    rpg_set_level
    cmp     eax, MAX_LEVEL
    jne     .fail
    mov     edi, -4
    call    rpg_set_level
    cmp     eax, 1
    jne     .fail
    mov     edi, 20                     ; skill points on top of the level's
    call    rpg_set_level
    mov     edi, 5
    mov     esi, 7
    call    rpg_add_bonus_points
    call    rpg_points
    cmp     eax, 25
    jne     .fail
    call    rpg_attr_points
    cmp     eax, 57 + 7
    jne     .fail
    mov     edi, 10
    xor     esi, esi
    call    rpg_add_bonus_points
    call    rpg_points
    cmp     eax, 35
    jne     .fail
    mov     edi, -100                   ; the bonus never goes below 0
    mov     esi, -100
    call    rpg_add_bonus_points
    call    rpg_points
    cmp     eax, 20
    jne     .fail
    call    rpg_attr_points
    cmp     eax, 57
    jne     .fail
    call    fixture                     ; at level 1 the bonus pays for more than the path
    mov     edi, 2
    xor     esi, esi
    call    rpg_add_bonus_points
    mov     edi, 0
    call    rpg_spend
    cmp     eax, 1
    jne     .fail
    mov     edi, WEBN(1, 0)
    call    rpg_spend
    cmp     eax, 1
    jne     .fail
    mov     edi, WEBN(1, 0)
    call    rpg_spend
    cmp     eax, 1
    jne     .fail
    mov     edi, WEBN(1, 0)
    call    rpg_spend
    test    eax, eax
    jnz     .fail                       ; level 1 + 2 bonus points: three in all
    call    fixture                     ; level 20: the path and five ranks of Weapon Mastery, ten Strength
    mov     edi, 20
    call    rpg_set_level
    mov     edi, 0
    call    rpg_spend
    mov     ebx, 5
.ranks:
    mov     edi, WEBN(1, 0)
    call    rpg_spend
    cmp     eax, 1
    jne     .fail
    dec     ebx
    jnz     .ranks
    mov     ebx, 10
.attrs:
    mov     edi, ATTR_STR
    call    rpg_spend_attr
    cmp     eax, 1
    jne     .fail
    dec     ebx
    jnz     .attrs
    mov     edi, 10                     ; 6 ranks fit under level 10: they stay
    call    rpg_set_level
    mov     edi, WEBN(1, 0)
    call    rpg_rank
    cmp     eax, 5
    jne     .fail
    call    rpg_points
    cmp     eax, 4
    jne     .fail
    mov     edi, 2
    xor     esi, esi
    call    rpg_add_bonus_points
    mov     edi, 4                      ; level 4 + 2 points = 6 holds the 6 ranks; but the ten Strength points
    call    rpg_set_level               ; are more than level 4 pays (9): they go back at once
    mov     edi, WEBN(1, 0)
    call    rpg_rank
    cmp     eax, 5
    jne     .fail
    mov     edi, ATTR_STR
    call    rpg_attr
    test    eax, eax
    jnz     .fail
    mov     edi, -1                     ; one point less: 5 < 6, the ranks go back too
    xor     esi, esi
    call    rpg_add_bonus_points
    mov     edi, WEBN(1, 0)
    call    rpg_rank
    test    eax, eax
    jnz     .fail
    xor     edi, edi
    call    rpg_rank
    test    eax, eax
    jnz     .fail
    xor     edi, edi
    call    rpg_bar_ability
    cmp     eax, -1
    jne     .fail                       ; the bar is empty again
    call    rpg_points
    cmp     eax, 5
    jne     .fail
    call    fixture                     ; attribute points: ten spent, the bonus keeps them valid
    mov     edi, 20
    call    rpg_set_level
    mov     ebx, 10
.attrs2:
    mov     edi, ATTR_STR
    call    rpg_spend_attr
    dec     ebx
    jnz     .attrs2
    xor     edi, edi
    mov     esi, 4
    call    rpg_add_bonus_points
    mov     edi, 3                      ; level 3 pays 6, the bonus 4: 10 allowed
    call    rpg_set_level
    mov     edi, ATTR_STR
    call    rpg_attr
    cmp     eax, 10
    jne     .fail
    xor     edi, edi
    mov     esi, -1
    call    rpg_add_bonus_points        ; 9 allowed: all ten go back
    mov     edi, ATTR_STR
    call    rpg_attr
    test    eax, eax
    jnz     .fail
    call    rpg_attr_points
    cmp     eax, 6 + 3
    jne     .fail
    call    fixture                     ; the free respec
    mov     edi, GOLD_COIN
    mov     esi, 100
    call    inv_add
    mov     edi, 20
    call    rpg_set_level
    mov     edi, 3
    mov     esi, 4
    call    rpg_add_bonus_points
    mov     edi, 0
    call    rpg_spend
    mov     edi, WEBN(1, 0)
    call    rpg_spend
    mov     edi, ATTR_STR
    call    rpg_spend_attr
    call    rpg_respec_free
    mov     edi, WEBN(1, 0)
    call    rpg_rank
    test    eax, eax
    jnz     .fail
    mov     edi, ATTR_STR
    call    rpg_attr
    test    eax, eax
    jnz     .fail
    mov     edi, GOLD_COIN
    call    inv_count
    cmp     eax, 100
    jne     .fail                       ; no coins were taken
    call    rpg_points
    cmp     eax, 20 + 3
    jne     .fail                       ; the bonus points stay
    call    rpg_attr_points
    cmp     eax, 57 + 4
    jne     .fail
    call    fixture                     ; a level too low for the ranks takes them back by itself
    mov     edi, 20
    call    rpg_set_level
    mov     edi, 0
    call    rpg_spend
    mov     ebx, 5
.ranks3:
    mov     edi, WEBN(1, 0)
    call    rpg_spend
    dec     ebx
    jnz     .ranks3
    mov     edi, 5                      ; 6 ranks do not fit under level 5
    call    rpg_set_level
    mov     edi, WEBN(1, 0)
    call    rpg_rank
    test    eax, eax
    jnz     .fail
    xor     edi, edi
    call    rpg_rank
    test    eax, eax
    jnz     .fail
    call    rpg_points
    cmp     eax, 5
    jne     .fail
    call    fixture                     ; bonus points count when a save is loaded: 6 ranks and 10 Strength
    mov     edi, 20                     ; points under level 4, 2 skill points and 4 attribute points
    call    rpg_set_level
    mov     edi, 0
    call    rpg_spend
    mov     ebx, 5
.ranks4:
    mov     edi, WEBN(1, 0)
    call    rpg_spend
    dec     ebx
    jnz     .ranks4
    mov     ebx, 10
.attrs4:
    mov     edi, ATTR_STR
    call    rpg_spend_attr
    dec     ebx
    jnz     .attrs4
    mov     edi, 2
    mov     esi, 4
    call    rpg_add_bonus_points
    mov     edi, 4
    call    rpg_set_level               ; 4 + 2 = 6 ranks, 9 + 4 = 13 attribute points: both stay
    mov     edi, WEBN(1, 0)
    call    rpg_rank
    cmp     eax, 5
    jne     .fail
    mov     edi, ATTR_STR
    call    rpg_attr
    cmp     eax, 10
    jne     .fail
    lea     rdi, [world_header]
    call    rpg_save
    call    rpg_reset
    lea     rdi, [world_header]
    call    rpg_load
    mov     edi, WEBN(1, 0)
    call    rpg_rank
    cmp     eax, 5
    jne     .fail                       ; the loaded web is valid with the saved bonus points
    mov     edi, ATTR_STR
    call    rpg_attr
    cmp     eax, 10
    jne     .fail
    mov     word [world_header + WORLDHDR.rpgx + RPGEXT.bonus_ap], 0
    lea     rdi, [world_header]
    call    rpg_load                    ; without the 4 attribute points 10 > 9: the load hands them back
    mov     edi, ATTR_STR
    call    rpg_attr
    test    eax, eax
    jnz     .fail
    mov     word [world_header + WORLDHDR.rpgx + RPGEXT.bonus_sp], 0
    lea     rdi, [world_header]
    call    rpg_load                    ; ... and without the 2 skill points 6 > 4: the web goes back
    mov     edi, WEBN(1, 0)
    call    rpg_rank
    test    eax, eax
    jnz     .fail
    mov     byte [rpg_migrated], 0
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    rpg_reset
    call    survival_reset
    call    inv_clear
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- enemies ------------------------------------------------------------------------------------------

; mobs_ok(edi type, esi level (0: any), edx elite) -> eax the number of mobs of that type, every one of
; them at that level and elite or not as asked, standing at y 11 (on the floor), 4 to 8 blocks from the
; player at (16.5, 16.5); -1 when one of them is not so
mobs_ok:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     rax, [mobs]
    mov     ecx, MAX_MOBS
    xor     ebx, ebx
.l:
    cmp     [rax + MOB.type], edi
    jne     .next
    test    esi, esi
    jz      .any_level
    cmp     [rax + MOB.level], esi
    jne     .bad
.any_level:
    cmp     [rax + MOB.elite], edx
    jne     .bad
    cmp     dword [rax + BODY.y], __float32__(11.0)
    jne     .bad
    movss   xmm0, [rax + BODY.x]
    subss   xmm0, [k_16_5]
    mulss   xmm0, xmm0
    movss   xmm1, [rax + BODY.z]
    subss   xmm1, [k_16_5]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [k_16]
    jb      .bad
    comiss  xmm0, [k_64]
    ja      .bad
    inc     ebx
.next:
    add     rax, MOB_size
    dec     ecx
    jnz     .l
    mov     eax, ebx
    jmp     .ret
.bad:
    mov     eax, -1
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Spawn: N mobs of a type stand on the floor 4 to 8 blocks in front of the player (north for yaw 0, east for
; yaw 90), at the level asked (0: the player's), elite or not; a count is clamped to 1..15; a bad type
; spawns nothing; without a floor nothing spawns; a full table gives fewer. Kill all empties the table, heal
; all fills every health.
test_debug_spawn_and_kill:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    fixture
    mov     edi, MOB_ZOMBIE
    mov     esi, 25
    xor     edx, edx
    mov     ecx, 5
    call    debug_spawn
    cmp     eax, 5
    jne     .fail
    mov     edi, MOB_ZOMBIE
    call    mob_count_type
    cmp     eax, 5
    jne     .fail
    mov     edi, MOB_ZOMBIE
    mov     esi, 25
    xor     edx, edx
    call    mobs_ok
    cmp     eax, 5
    jne     .fail
    lea     rax, [mobs]                 ; ... all north of the player (yaw 0 looks towards -z) ...
    mov     ecx, MAX_MOBS
.north:
    cmp     dword [rax + MOB.type], MOB_NONE
    je      .north_next
    movss   xmm0, [rax + BODY.z]
    comiss  xmm0, [k_16_5]
    jae     .fail
    cmp     dword [rax + MOB.health], 0
    jle     .fail
.north_next:
    add     rax, MOB_size
    dec     ecx
    jnz     .north
    mov     edi, 7                      ; a spawn at the player's level
    call    rpg_set_level
    mov     edi, MOB_PIG
    xor     esi, esi
    xor     edx, edx
    mov     ecx, 1
    call    debug_spawn
    cmp     eax, 1
    jne     .fail
    mov     edi, MOB_PIG
    mov     esi, 7
    xor     edx, edx
    call    mobs_ok
    cmp     eax, 1
    jne     .fail
    call    mobs_clear                  ; elite skeletons of level 10, more than a plain one of that level
    mov     edi, MOB_SKELETON
    mov     esi, 10
    mov     edx, 1
    mov     ecx, 2
    call    debug_spawn
    cmp     eax, 2
    jne     .fail
    mov     edi, MOB_SKELETON
    mov     esi, 10
    mov     edx, 1
    call    mobs_ok
    cmp     eax, 2
    jne     .fail
    mov     edi, MOB_SKELETON
    movss   xmm0, [k_3_5]               ; a plain level-10 skeleton at (3.5, 11, 3.5) for the health
    movss   xmm1, [k_11]
    movss   xmm2, [k_3_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    mov     esi, 10
    call    mob_set_level
    imul    ecx, ebx, MOB_size
    lea     rax, [mobs]
    add     rax, rcx
    mov     r12d, [rax + MOB.max_health]
    mov     ebx, 2                      ; (the spawned ones: the elite health is above it)
    lea     rax, [mobs]
    mov     ecx, MAX_MOBS
.elite_health:
    cmp     dword [rax + MOB.elite], 0
    je      .elite_next
    cmp     [rax + MOB.max_health], r12d
    jle     .fail
    cmp     dword [rax + MOB.affix], 0
    je      .fail
    dec     ebx
.elite_next:
    add     rax, MOB_size
    dec     ecx
    jnz     .elite_health
    test    ebx, ebx
    jnz     .fail
    call    mobs_clear                  ; facing east
    mov     dword [player + BODY.yaw], __float32__(90.0)
    mov     edi, MOB_CREEPER
    xor     esi, esi
    xor     edx, edx
    mov     ecx, 3
    call    debug_spawn
    cmp     eax, 3
    jne     .fail
    lea     rax, [mobs]
    mov     ecx, MAX_MOBS
.east:
    cmp     dword [rax + MOB.type], MOB_NONE
    je      .east_next
    movss   xmm0, [rax + BODY.x]
    comiss  xmm0, [k_19_5]
    jb      .fail                       ; 16.5 + 4.5 - rounding: at least 19.5 east
.east_next:
    add     rax, MOB_size
    dec     ecx
    jnz     .east
    mov     dword [player + BODY.yaw], 0
    call    mobs_clear                  ; counts: 0 gives one, 99 gives the most one call places
    mov     edi, MOB_SPIDER
    xor     esi, esi
    xor     edx, edx
    xor     ecx, ecx
    call    debug_spawn
    cmp     eax, 1
    jne     .fail
    call    mobs_clear
    mov     edi, MOB_CHICKEN
    xor     esi, esi
    xor     edx, edx
    mov     ecx, 99
    call    debug_spawn
    cmp     eax, 15
    jne     .fail
    call    mobs_clear                  ; no such type
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    mov     ecx, 3
    call    debug_spawn
    test    eax, eax
    jnz     .fail
    mov     edi, MOB_FOLK
    xor     esi, esi
    xor     edx, edx
    mov     ecx, 3
    call    debug_spawn
    test    eax, eax
    jnz     .fail
    xor     r12d, r12d                  ; a full table: 4 calls of 15, the fifth places only 4
.fill:
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    xor     edx, edx
    mov     ecx, 15
    call    debug_spawn
    cmp     eax, 15
    jne     .fail
    inc     r12d
    cmp     r12d, 4
    jb      .fill
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    xor     edx, edx
    mov     ecx, 15
    call    debug_spawn
    cmp     eax, MAX_MOBS - 60
    jne     .fail
    mov     edi, MOB_ZOMBIE
    call    mob_count_type
    cmp     eax, MAX_MOBS
    jne     .fail
    lea     rax, [mobs]                 ; heal all: everyone back to full health
    mov     ecx, MAX_MOBS
.hurt:
    mov     dword [rax + MOB.health], 1
    add     rax, MOB_size
    dec     ecx
    jnz     .hurt
    call    debug_heal_all
    lea     rax, [mobs]
    mov     ecx, MAX_MOBS
.healed:
    mov     edx, [rax + MOB.max_health]
    cmp     edx, 1
    jle     .fail
    cmp     [rax + MOB.health], edx
    jne     .fail
    add     rax, MOB_size
    dec     ecx
    jnz     .healed
    call    debug_kill_all              ; kill all
    mov     edi, 1
    call    mob_count_kind
    test    eax, eax
    jnz     .fail
    xor     edi, edi
    call    mob_count_kind
    test    eax, eax
    jnz     .fail
    call    mobs_clear
    SETB    16, 10, 12, AIR             ; the floor's height: a spot takes a floor from 2 cells above the feet
    SETB    16, 7, 12, STONE            ; down to 3 below: (16, 12) has its floor at y 7, a free cell at y 8 ...
    SPAWN1
    cmp     dword [mobs + BODY.y], __float32__(8.0)
    jne     .fail
    cmp     dword [mobs + BODY.x], __float32__(16.5)
    jne     .fail
    call    mobs_clear
    SETB    16, 7, 12, AIR              ; ... with the floor one lower the spot has no floor in reach: the next
    SETB    16, 6, 12, STONE            ; spot (one lane left) takes the mob, on the common floor
    SPAWN1
    cmp     dword [mobs + BODY.y], __float32__(11.0)
    jne     .fail
    cmp     dword [mobs + BODY.x], __float32__(14.5)
    jne     .fail
    call    mobs_clear
    SETB    16, 6, 12, AIR
    SETB    16, 10, 12, STONE
    SETB    16, 11, 12, STONE
    SETB    16, 12, 12, STONE           ; a floor at y 12 (the player's feet are at 11): a free cell at y 13, in reach
    SPAWN1
    cmp     dword [mobs + BODY.y], __float32__(13.0)
    jne     .fail
    cmp     dword [mobs + BODY.x], __float32__(16.5)
    jne     .fail
    call    mobs_clear
    SETB    16, 13, 12, STONE           ; ... one higher is out of reach: the next spot again
    SPAWN1
    cmp     dword [mobs + BODY.y], __float32__(11.0)
    jne     .fail
    cmp     dword [mobs + BODY.x], __float32__(14.5)
    jne     .fail
    call    mobs_clear
    SETB    16, 11, 12, AIR             ; a gap one cell high under a ceiling (stone at y 12 and 13): no room to stand
    SPAWN1
    cmp     dword [mobs + BODY.y], __float32__(11.0)
    jne     .fail
    cmp     dword [mobs + BODY.x], __float32__(14.5)
    jne     .fail
    call    mobs_clear
    SETB    16, 12, 12, AIR
    SETB    16, 13, 12, AIR
    SETB    16, 11, 12, WATER           ; nobody is spawned into water ...
    SPAWN1
    cmp     dword [mobs + BODY.x], __float32__(14.5)
    jne     .fail
    call    mobs_clear
    SETB    16, 11, 12, LAVA            ; ... or lava
    SPAWN1
    cmp     dword [mobs + BODY.x], __float32__(14.5)
    jne     .fail
    call    mobs_clear
    SETB    16, 11, 12, AIR
    xor     r12d, r12d                  ; without a floor there is nowhere to stand: nothing spawns
    xor     ebx, ebx
.hole_z:
    xor     r12d, r12d
.hole_x:
    mov     edi, r12d
    mov     esi, 10
    mov     edx, ebx
    xor     ecx, ecx
    call    world_set
    inc     r12d
    cmp     r12d, 32
    jb      .hole_x
    inc     ebx
    cmp     ebx, 32
    jb      .hole_z
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    xor     edx, edx
    mov     ecx, 3
    call    debug_spawn
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     dword [player + BODY.yaw], 0
    push    rax
    call    mobs_clear
    call    rpg_reset
    pop     rax
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- world --------------------------------------------------------------------------------------------

; parse(rdi text) -> eax 1 and out_i32 the number, or 0
parse:
    sub     rsp, 8
    lea     rsi, [out_i32]
    call    debug_parse_int
    add     rsp, 8
    ret

; PARSE text, expected: the text must be a number with that value
%macro PARSE 2
    lea     rdi, [%1]
    call    parse
    cmp     eax, 1
    jne     .fail
    cmp     dword [out_i32], %2
    jne     .fail
%endmacro
; PARSE_BAD text: the text must be refused
%macro PARSE_BAD 1
    lea     rdi, [%1]
    call    parse
    test    eax, eax
    jnz     .fail
%endmacro

; set_field(edi i, rsi text): the teleport field i holds that text
set_field:
    imul    edi, edi, TEXTFIELD_size
    lea     rax, [debug_coord_fields]
    add     rdi, rax
    lea     rdi, [rdi + TEXTFIELD.buf]
    mov     edx, 32
    jmp     str_copy

; The clock moves forward to the next dawn, noon, dusk or midnight (the present moment when it is exactly
; that, never backwards) and by an hour; the numbers of the teleport fields are read with a sign and spaces
; and cut at 16 million; the fields are filled with the player's absolute cell; Go moves the player to that
; cell (the origin follows into its 512-block square, no speed is left, Y stays within 1..254) and a field
; that is no number moves nobody.
test_debug_time_and_teleport:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    fixture
    mov     dword [game_time], 100
    mov     edi, 18000                  ; DEBUG_NOON
    call    debug_set_time
    cmp     dword [game_time], 18000
    jne     .fail
    mov     edi, 18000                  ; the present moment counts
    call    debug_set_time
    cmp     dword [game_time], 18000
    jne     .fail
    mov     dword [game_time], 18001    ; one step past noon: tomorrow's
    mov     edi, 18000
    call    debug_set_time
    cmp     dword [game_time], 18000 + DAY_LENGTH
    jne     .fail
    mov     dword [game_time], 60000
    mov     edi, 70200                  ; DEBUG_DAWN
    call    debug_set_time
    cmp     dword [game_time], 70200
    jne     .fail
    mov     edi, 54000                  ; DEBUG_MIDNIGHT: the next day's
    call    debug_set_time
    cmp     dword [game_time], 54000 + DAY_LENGTH
    jne     .fail
    mov     edi, [game_time]
    call    sky_is_night
    cmp     eax, 1
    jne     .fail
    mov     edi, 18000
    call    debug_set_time
    cmp     dword [game_time], 18000 + 2 * DAY_LENGTH
    jne     .fail
    mov     edi, [game_time]
    call    sky_is_night
    test    eax, eax
    jnz     .fail
    mov     edi, 36000                  ; DEBUG_DUSK
    call    debug_set_time
    cmp     dword [game_time], 36000 + 2 * DAY_LENGTH
    jne     .fail
    mov     edi, 3000                   ; an hour
    call    debug_add_time
    cmp     dword [game_time], 39000 + 2 * DAY_LENGTH
    jne     .fail
    PARSE   t_12, 12
    PARSE   t_m7, -7
    PARSE   t_p3, 3
    PARSE   t_sp5sp, 5
    PARSE   t_huge, 16000000
    PARSE_BAD t_empty
    PARSE_BAD t_minus
    PARSE_BAD t_1x
    PARSE_BAD t_mm1
    mov     dword [world_origin_x], 1024    ; the fields take the absolute cell of the feet
    mov     dword [world_origin_z], -512
    mov     dword [player + BODY.x], __float32__(100.5)
    mov     dword [player + BODY.y], __float32__(70.0)
    mov     dword [player + BODY.z], __float32__(-20.25)
    call    debug_fill_coords
    lea     rdi, [debug_coord_fields + TEXTFIELD.buf]
    lea     rsi, [t_1124]
    call    str_eq
    cmp     eax, 1
    jne     .fail
    cmp     dword [debug_coord_fields + TEXTFIELD.len], 4
    jne     .fail
    lea     rdi, [debug_coord_fields + TEXTFIELD_size + TEXTFIELD.buf]
    lea     rsi, [t_70]
    call    str_eq
    cmp     eax, 1
    jne     .fail
    lea     rdi, [debug_coord_fields + 2 * TEXTFIELD_size + TEXTFIELD.buf]
    lea     rsi, [t_m533]
    call    str_eq
    cmp     eax, 1
    jne     .fail
    cmp     dword [debug_coord_fields + 2 * TEXTFIELD_size + TEXTFIELD.len], 4
    jne     .fail
    mov     dword [world_origin_x], 0   ; Go: (5000, 80, -3000)
    mov     dword [world_origin_z], 0
    mov     dword [player + BODY.vx], __float32__(3.0)
    mov     dword [player + BODY.vy], __float32__(-4.0)
    xor     edi, edi
    lea     rsi, [t_5000]
    call    set_field
    mov     edi, 1
    lea     rsi, [t_80]
    call    set_field
    mov     edi, 2
    lea     rsi, [t_m3000]
    call    set_field
    call    debug_go
    cmp     eax, 1
    jne     .fail
    cmp     dword [world_origin_x], 4608    ; 5000 & -512
    jne     .fail
    cmp     dword [world_origin_z], -3072   ; -3000 & -512
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(392.5)
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(80.0)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(72.5)
    jne     .fail
    cmp     dword [player + BODY.vx], 0
    jne     .fail
    cmp     dword [player + BODY.vy], 0
    jne     .fail
    call    debug_fill_coords           ; and the fields read the same cell back
    lea     rdi, [debug_coord_fields + TEXTFIELD.buf]
    lea     rsi, [t_5000]
    call    str_eq
    cmp     eax, 1
    jne     .fail
    lea     rdi, [debug_coord_fields + 2 * TEXTFIELD_size + TEXTFIELD.buf]
    lea     rsi, [t_m3000]
    call    str_eq
    cmp     eax, 1
    jne     .fail
    xor     edi, edi                    ; a field that is no number: nobody moves
    lea     rsi, [t_abc]
    call    set_field
    call    debug_go
    test    eax, eax
    jnz     .fail
    cmp     dword [world_origin_x], 4608
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(392.5)
    jne     .fail
    xor     edi, edi                    ; Y stays within 1..254, X within 16 million
    lea     rsi, [t_huge]
    call    set_field
    mov     edi, 1
    lea     rsi, [t_0]
    call    set_field
    call    debug_go
    cmp     eax, 1
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(1.0)
    jne     .fail
    cmp     dword [world_origin_x], 16000000
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(0.5)
    jne     .fail
    mov     edi, 1
    lea rsi, [t_999]
    call    set_field
    call    debug_go
    cmp     eax, 1
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(254.0)
    jne     .fail
    mov     dword [world_origin_x], 0   ; landing, in the arena (the origin is back at 0): an exact cell that is free
    mov     dword [world_origin_z], 0   ; keeps its height once the area is ready ...
    mov     edi, 16
    mov     esi, 20
    mov     edx, 16
    mov     ecx, 4
    call    game_teleport
    call    game_on_area_ready
    cmp     dword [player + BODY.y], __float32__(20.0)
    jne     .fail
    mov     edi, 16                     ; ... one with its feet in the floor takes the player up to the surface ...
    mov     esi, 10
    mov     edx, 16
    mov     ecx, 4
    call    game_teleport
    call    game_on_area_ready
    cmp     dword [player + BODY.y], __float32__(11.0)
    jne     .fail
    SETB    16, 21, 16, STONE           ; ... and so does one with its head in a block (the surface is the block's top)
    mov     edi, 16
    mov     esi, 20
    mov     edx, 16
    mov     ecx, 4
    call    game_teleport
    call    game_on_area_ready
    cmp     dword [player + BODY.y], __float32__(22.0)
    jne     .fail
    SETB    16, 21, 16, AIR
    mov     edi, 16                     ; pending 0 leaves even a cell in the floor as it is
    mov     esi, 10
    mov     edx, 16
    xor     ecx, ecx
    call    game_teleport
    call    game_on_area_ready
    cmp     dword [player + BODY.y], __float32__(10.0)
    jne     .fail
    mov     dword [player + BODY.y], __float32__(30.0)
    call    game_on_area_ready          ; the request is used up
    cmp     dword [player + BODY.y], __float32__(30.0)
    jne     .fail
    xor     edi, edi                    ; Go with the fields in the floor: the same landing (pending 4)
    lea     rsi, [t_16]
    call    set_field
    mov     edi, 1
    lea     rsi, [t_10]
    call    set_field
    mov     edi, 2
    lea     rsi, [t_16]
    call    set_field
    call    debug_go
    cmp     eax, 1
    jne     .fail
    call    game_on_area_ready
    cmp     dword [player + BODY.y], __float32__(11.0)
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    call    debug_reset
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- spawn and bed ------------------------------------------------------------------------------------

; To spawn takes the player to the world spawn and To bed to the bed (standing beside it, on the floor around
; it), the two not mixed up; with no bed set To bed answers 0 and nobody moves; a bed that is gone (its cell
; is air) sends the player to the world spawn and clears bed_set, as a respawn does.
test_debug_to_spawn_and_bed:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    fixture
    mov     dword [world_header + WORLDHDR.spawn_x], 24
    mov     dword [world_header + WORLDHDR.spawn_y], 40  ; in the air: the surface landing puts the player on the floor
    mov     dword [world_header + WORLDHDR.spawn_z], 6
    mov     dword [world_header + WORLDHDR.bed_set], 0
    SETB    20, 11, 20, BED + DIR_E          ; a bed: the foot at (20, 11, 20), the head east of it
    SETB    21, 11, 20, BED + 4 + DIR_E
    call    debug_to_bed                    ; no bed set: nothing happens
    test    eax, eax
    jnz     .fail
    cmp     dword [player + BODY.x], __float32__(16.5)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(16.5)
    jne     .fail
    call    debug_to_spawn
    cmp     eax, 1
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(24.5)   ; first in the middle of the spawn cell (x, z), up in the air
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(40.0)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(6.5)
    jne     .fail
    call    game_on_area_ready
    test    eax, eax
    jnz     .fail
    cmp     dword [player + BODY.x], __float32__(24.5)   ; at the world spawn, on the floor
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(11.0)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(6.5)
    jne     .fail
    mov     dword [world_header + WORLDHDR.bed_x], 20
    mov     dword [world_header + WORLDHDR.bed_y], 11
    mov     dword [world_header + WORLDHDR.bed_z], 20
    mov     dword [world_header + WORLDHDR.bed_set], 1
    call    debug_to_bed
    cmp     eax, 1
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(20.5)   ; first in the bed's foot cell: its area is the one that loads
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(11.0)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(20.5)
    jne     .fail
    call    game_on_area_ready
    test    eax, eax
    jnz     .fail
    cmp     dword [player + BODY.x], __float32__(20.5)   ; beside the bed: the first free neighbour of its foot, north
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(11.0)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(19.5)
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_set], 1
    jne     .fail
    call    debug_to_spawn                  ; and back to the spawn: a bed does not change where To spawn goes
    call    game_on_area_ready
    cmp     dword [player + BODY.x], __float32__(24.5)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(6.5)
    jne     .fail
    SETB    20, 11, 20, AIR                 ; the bed is gone: the world spawn, and no bed any more
    call    debug_to_bed
    cmp     eax, 1
    jne     .fail
    mov     dword [player + BODY.x], __float32__(1.5)
    mov     dword [player + BODY.z], __float32__(1.5)
    call    game_on_area_ready
    cmp     eax, 1                          ; (the world spawn is another area: it must be waited for again)
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_set], 0
    jne     .fail
    call    game_on_area_ready
    test    eax, eax
    jnz     .fail
    cmp     dword [player + BODY.x], __float32__(24.5)
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(11.0)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(6.5)
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    mov     dword [world_header + WORLDHDR.bed_set], 0
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- stats --------------------------------------------------------------------------------------------

; A debug bonus moves the stat as it stands (it survives every recompute, goes past the caps, and
; changes surv_max_health), within safe ranges (no reload speed below -90, no reduction above 90, no flat
; stat below 0, max health at least 2); it is saved with the header and loaded back (each bonus within
; +-5000); a new character has none.
test_debug_stat_bonus:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    fixture
    mov     edi, STAT_MELEE_DMG
    mov     esi, 5
    call    debug_bonus_add
    cmp     eax, 5
    jne     .fail
    mov     edi, STAT_MELEE_DMG
    call    rpg_stat
    cmp     eax, 5
    jne     .fail
    mov     edi, STAT_MELEE_DMG
    mov     esi, 5
    call    debug_bonus_add
    call    rpg_recompute               ; the game recomputes every step: the bonus stays
    call    rpg_recompute
    mov     edi, STAT_MELEE_DMG
    call    rpg_stat
    cmp     eax, 10
    jne     .fail
    mov     edi, STAT_MELEE_DMG
    mov     esi, -3
    call    debug_bonus_add
    cmp     eax, -3
    jne     .fail
    mov     edi, STAT_MELEE_DMG
    call    rpg_stat
    cmp     eax, 7
    jne     .fail
    mov     edi, STAT_CRIT_CHANCE       ; past the cap of 75 (the bonus comes after the caps)
    mov     esi, 100
    call    debug_bonus_add
    cmp     eax, 100
    jne     .fail
    mov     edi, STAT_CRIT_CHANCE
    call    rpg_stat
    cmp     eax, 100
    jne     .fail
    mov     edi, STAT_MAX_HEALTH        ; max health follows: 20 + 10
    mov     esi, 10
    call    debug_bonus_add
    cmp     dword [surv_max_health], 30
    jne     .fail
    mov     edi, STAT_RELOAD_SPEED      ; a reload speed of -100 would divide by zero: -90 is the floor
    mov     esi, -500
    call    debug_bonus_add
    cmp     eax, -90
    jne     .fail
    mov     edi, STAT_RELOAD_SPEED
    call    rpg_stat
    cmp     eax, -90
    jne     .fail
    mov     edi, STAT_RELOAD_SPEED
    mov     esi, -1
    call    debug_bonus_add
    test    eax, eax
    jnz     .fail                       ; nothing moves past the floor
    mov     edi, STAT_COOLDOWN_RED      ; a reduction stays under 100%
    mov     esi, 500
    call    debug_bonus_add
    cmp     eax, 90
    jne     .fail
    mov     edi, STAT_RES_FIRE
    mov     esi, 500
    call    debug_bonus_add
    cmp     eax, 90
    jne     .fail
    mov     edi, STAT_THORNS            ; a flat stat does not go below 0
    mov     esi, -5
    call    debug_bonus_add
    test    eax, eax
    jnz     .fail
    mov     edi, STAT_MAX_HEALTH        ; max health keeps 2
    mov     esi, -1000
    call    debug_bonus_add
    mov     edi, STAT_MAX_HEALTH
    call    rpg_stat
    cmp     eax, 2
    jne     .fail
    cmp     dword [surv_max_health], 2
    jne     .fail
    mov     edi, NUM_STATS              ; no such stat
    mov     esi, 5
    call    debug_bonus_add
    test    eax, eax
    jnz     .fail
    mov     edi, STAT_MAX_HEALTH        ; the ranges themselves
    call    debug_stat_range
    cmp     eax, 2
    jne     .fail
    cmp     edx, 999
    jne     .fail
    mov     edi, STAT_CRIT_DMG
    call    debug_stat_range
    cmp     eax, -90
    jne     .fail
    cmp     edx, 999
    jne     .fail
    mov     edi, STAT_COOLDOWN_RED
    call    debug_stat_range
    cmp     eax, -900
    jne     .fail
    cmp     edx, 90
    jne     .fail
    mov     edi, STAT_LIFE_REGEN
    call    debug_stat_range
    test    eax, eax
    jnz     .fail
    cmp     edx, 999
    jne     .fail
    call    rpg_reset                   ; a new character has no bonus
    mov     edi, STAT_CRIT_CHANCE
    call    rpg_stat
    test    eax, eax
    jnz     .fail
    mov     edi, STAT_MELEE_DMG         ; save and load through the header image
    mov     esi, 12
    call    debug_bonus_add
    mov     edi, STAT_ATTACK_SPEED
    mov     esi, -20
    call    debug_bonus_add
    lea     rdi, [world_header]
    call    rpg_save
    cmp     word [world_header + WORLDHDR.debug_stats + STAT_MELEE_DMG * 2], 12
    jne     .fail
    cmp     word [world_header + WORLDHDR.debug_stats + STAT_ATTACK_SPEED * 2], -20
    jne     .fail
    call    rpg_reset
    mov     edi, STAT_MELEE_DMG
    call    rpg_stat
    test    eax, eax
    jnz     .fail
    lea     rdi, [world_header]
    call    rpg_load
    mov     edi, STAT_MELEE_DMG
    call    rpg_stat
    cmp     eax, 12
    jne     .fail
    mov     edi, STAT_ATTACK_SPEED
    call    rpg_stat
    cmp     eax, -20
    jne     .fail
    mov     word [world_header + WORLDHDR.debug_stats + STAT_MELEE_DMG * 2], 30000   ; a damaged save is cut
    mov     word [world_header + WORLDHDR.debug_stats + STAT_RANGED_DMG * 2], -30000
    lea     rdi, [world_header]
    call    rpg_load
    mov     edi, STAT_MELEE_DMG
    call    rpg_stat
    cmp     eax, DEBUG_BONUS_MAX
    jne     .fail
    mov     edi, STAT_RANGED_DMG
    call    rpg_stat
    cmp     eax, -DEBUG_BONUS_MAX
    jne     .fail
    mov     word [world_header + WORLDHDR.debug_stats + STAT_MAX_HEALTH * 2], -30000   ; ... and max health keeps 2
    lea     rdi, [world_header]
    call    rpg_load
    mov     edi, STAT_MAX_HEALTH
    call    rpg_stat
    cmp     eax, 2
    jne     .fail
    cmp     dword [surv_max_health], 2
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    lea     rdi, [world_header + WORLDHDR.debug_stats]    ; leave the header image clean
    mov     ecx, 92
    xor     eax, eax
    rep     stosb
    call    rpg_reset
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- the clock ----------------------------------------------------------------------------------------

; run_frames(edi n >= 1): n times game_frame(1/60 s), which runs exactly one sim_step
run_frames:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
.l:
    movss   xmm0, [k_step]
    call    game_frame
    dec     ebx
    jnz     .l
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; frame_state(): what game_frame needs (test_lava's check_frames): by day in Peaceful and Creative with
; nothing else about, the cursor captured, no screen open, no button down
frame_state:
    sub     rsp, 8
    mov     dword [game_time], 6007
    mov     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    mov     dword [game_mode], MODE_CREATIVE
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    mov     dword [frame_input + FRAMEINPUT.slot], -1
    mov     dword [input_captured], 1
    mov     dword [game_open_screen], 0
    mov     dword [game_heavy_s], __float32__(-1.0)
    mov     dword [game_break_progress], 0
    mov     dword [brk_y], -1
    add     rsp, 8
    ret

; The detector's clock is the game's own fixed step (sim_step calls debug_step once per step): 61 steps of
; game_frame between two presses are too late for the third one, 60 are in time.
test_debug_step_clock:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    fixture
    call    frame_state
    PRESS   0
    PRESS   0
    mov     edi, 61
    call    run_frames
    PRESS   0                           ; late: the first of a new count
    cmp     dword [debug_open], 0
    jne     .fail
    call    debug_reset
    PRESS   0
    PRESS   0
    mov     edi, 60
    call    run_frames
    PRESS   1                           ; in time
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    mobs_clear
    call    inv_clear
    call    drops_clear
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    mov     dword [game_open_screen], 0
    mov     dword [game_heavy_s], __float32__(-1.0)
    mov     dword [game_mode], MODE_SURVIVAL
    mov     byte [world_header + WORLDHDR.cheater], 0
    call    debug_reset
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- vitals and toggles -------------------------------------------------------------------------------

; Restore fills health, food, air and stamina; god mode stops damage and damage over time and can be turned
; off again; fly toggles the body's flight in either mode; the mode toggle flips Survival and Creative; reset
; cooldowns clears every ability cooldown and the bolt; clear drops empties the ground; a faction's standing
; moves by the amounts of the buttons (+-100, Max reaches the limit: 1000, the Ashen Cult 199).
test_debug_vitals_and_toggles:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    fixture
    mov     dword [surv + SURVIVAL.health], 3
    mov     dword [surv + SURVIVAL.food], 2
    mov     dword [surv + SURVIVAL.breath], 5
    mov     dword [surv + SURVIVAL.saturation], 0
    mov     dword [surv + SURVIVAL.exhaustion], __float32__(3.0)
    mov     dword [combat_stamina], 0
    call    debug_full_restore
    mov     eax, [surv_max_health]
    cmp     [surv + SURVIVAL.health], eax
    jne     .fail
    cmp     dword [surv + SURVIVAL.food], 20
    jne     .fail
    cmp     dword [surv + SURVIVAL.breath], MAX_BREATH
    jne     .fail
    cmp     dword [combat_stamina], __float32__(100.0)
    jne     .fail
    cmp     dword [surv + SURVIVAL.saturation], __float32__(5.0)
    jne     .fail
    cmp     dword [surv + SURVIVAL.exhaustion], 0
    jne     .fail
    mov     dword [surv + SURVIVAL.health], 15  ; god mode: nothing hurts
    call    debug_toggle_god
    cmp     eax, 1
    jne     .fail
    mov     edi, 5
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    test    eax, eax
    jnz     .fail
    mov     edi, 3
    mov     esi, CAUSE_POISON
    call    survival_dot
    test    eax, eax
    jnz     .fail
    cmp     dword [surv + SURVIVAL.health], 15
    jne     .fail
    call    debug_toggle_god            ; ... and off again: it hurts
    test    eax, eax
    jnz     .fail
    mov     edi, 5
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    cmp     eax, 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 10
    jne     .fail
    mov     dword [player + BODY.vy], __float32__(-3.0)
    call    debug_toggle_fly
    cmp     eax, 1
    jne     .fail
    cmp     dword [player + BODY.flying], 1
    jne     .fail
    cmp     dword [player + BODY.vy], 0
    jne     .fail                       ; the fall speed is gone
    call    debug_toggle_fly
    test    eax, eax
    jnz     .fail
    cmp     dword [player + BODY.flying], 0
    jne     .fail
    call    debug_toggle_mode
    cmp     eax, MODE_CREATIVE
    jne     .fail
    cmp     dword [game_mode], MODE_CREATIVE
    jne     .fail
    call    debug_toggle_mode
    cmp     eax, MODE_SURVIVAL
    jne     .fail
    mov     dword [abilities_cd + 3 * 4], 100
    mov     dword [abilities_cd + (NUM_ABILITIES - 1) * 4], 9
    mov     dword [abilities_cd_total + 3 * 4], 100
    mov     dword [abilities_bolt_cd], 7
    call    debug_reset_cooldowns
    xor     ecx, ecx
.cd:
    cmp     dword [abilities_cd + rcx*4], 0
    jne     .fail
    cmp     dword [abilities_cd_total + rcx*4], 0
    jne     .fail
    inc     ecx
    cmp     ecx, NUM_ABILITIES
    jb      .cd
    cmp     dword [abilities_bolt_cd], 0
    jne     .fail
    mov     edi, STONE                  ; drops on the ground
    mov     esi, 3
    xor     edx, edx
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_16_5]
    movss   xmm2, [k_16_5]
    call    drops_spawn
    cmp     byte [drops + DROP.id], STONE
    jne     .fail
    call    debug_clear_drops
    lea     rdi, [drops]
    xor     ecx, ecx
.drops:
    cmp     byte [rdi + DROP.id], 0
    jne     .fail
    add     rdi, DROP_size
    inc     ecx
    cmp     ecx, MAX_DROPS
    jb      .drops
    call    faction_reset               ; villagers 200, bandits -100, the cult -100
    mov     edi, FAC_BANDITS
    mov     esi, 100
    call    faction_add
    cmp     eax, 0
    jne     .fail
    mov     edi, FAC_BANDITS
    mov     esi, -100
    call    faction_add
    cmp     eax, -100
    jne     .fail
    mov     edi, FAC_VILLAGERS
    mov     esi, 2000
    call    faction_add
    cmp     eax, STANDING_MAX
    jne     .fail
    mov     edi, FAC_CULT
    mov     esi, 2000
    call    faction_add
    cmp     eax, CULT_MAX
    jne     .fail
    mov     edi, FAC_CULT
    call    faction_standing
    cmp     eax, CULT_MAX
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    mov     dword [surv + SURVIVAL.god], 0
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [player + BODY.flying], 0
    call    faction_reset
    call    drops_clear
    call    survival_reset
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

section .rodata
t_1124:        db "1124", 0
t_70:          db "70", 0
t_m533:        db "-533", 0
t_16:          db "16", 0
t_10:          db "10", 0
t_11:          db "11", 0
