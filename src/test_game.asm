; test_game.asm - a whole session through a 0.9 world directory (the header image keeps the character,
; the origin, the breath, the bed and the site records; a bad world.hdr changes nothing; a dead
; player comes back at the world spawn; a new world's player stands on the surface once the area is
; ready and its animals take the new character's level), the floating-origin rebase trigger, the
; hook that clears out what stood in a column that unloads, the dig path of game_frame (what a
; Survival player gets for the leaves he digs), and (0.10) the faction standings in the header
; (a new world's start, the round trip, the clamp on load) and what game_frame does with a click
; aimed at a shrine or a folk.
%include "common.inc"
default rel

global test_game_save_load_roundtrip, test_game_rebase_trigger
global test_faction_save_load, test_shrine_and_folk_dispatch

extern world_clear, world_header, world_set, rng_seed, game_new, game_save, game_load, game_rebase
extern game_on_area_ready, game_unload_box, game_time, game_mode, game_target, game_has_target
extern game_open_npc, app_state, input_captured
extern brk_x, brk_y, brk_z, world_origin_x, world_origin_z
extern surv, inv, player, mobs, mobs_clear, mob_count_type, mob_spawn, rpg_state
extern str_eq, str_copy, file_read, file_write_atomic, mkdir_p, dir_remove_tree
extern game_frame, frame_input, inv_sel, inv_clear, drops, drops_clear, world_get
extern combat_reset, survival_reset, body_init, settings
extern game_open_screen, game_heavy_s, game_break_progress
extern faction_reset, screen_faction, trade_open, trade_title, folk_spawn, combat_guard_t

section .rodata
align 4
k_pig_x:  dd 10.5
k_pig_y:  dd 20.0
k_pig_z1: dd 10.5
k_pig_z2: dd 14.5
k_half:   dd 0.5
k_edge:   dd 63.5                       ; floor 63: the last column of the box 48..63
k_over:   dd 64.5                       ; one past it
k_row:    dd 48.5                       ; floor 48: its first row
d_world_str: db "/tmp/assemblycraft-selftest-game", 0
d_regions: db "/tmp/assemblycraft-selftest-game/regions", 0
d_missing: db "/tmp/assemblycraft-selftest-game-missing", 0
p_hdr:    db "/tmp/assemblycraft-selftest-game/world.hdr", 0
name_rt:  db "Round Trip", 0
name_x:   db "x", 0
align 4
k_one:    dd 1.0
k_p_half_w: dd 0.3                     ; the player's box and walking speed
k_p_height: dd 1.8
k_p_speed: dd 4.317
k_step:   dd 0.016666668               ; one fixed step: game_frame runs exactly one sim_step
k_folk_x: dd 8.5                       ; a folk on the arena's floor, in the player's line of sight
k_folk_y: dd 10.0
k_folk_z: dd 6.5
s_stk_trader: db "Stonekin Trader", 0

section .bss
dir_buf:  resb 128
d_world:  resb 64
file_buf: resb WORLD_HDR_SIZE + 16
saved:    resd 3                       ; the caller's game_mode, game_time and difficulty

section .text

; spawn_pigs() -> eax pigs alive: two pigs at fixed spots (local cells well inside every bound)
spawn_pigs:
    push    rbp
    mov     rbp, rsp
    mov     edi, MOB_PIG
    movss   xmm0, [k_pig_x]
    movss   xmm1, [k_pig_y]
    movss   xmm2, [k_pig_z1]
    call    mob_spawn
    mov     edi, MOB_PIG
    movss   xmm0, [k_pig_x]
    movss   xmm1, [k_pig_y]
    movss   xmm2, [k_pig_z2]
    call    mob_spawn
    mov     edi, MOB_PIG
    call    mob_count_type
    pop     rbp
    ret

; dig_leaf(edi block, esi held item) -> eax: the id of the drop that digging `block` as a Survival player
; with `held` in his hand leaves (0: no drop), or -1 when the block still stands. A STONE floor (x, z 4..12
; at y 9), the player at (8.5, 10, 8.5) looking along -z at the `block` cell (8, 11, 6), by day in
; Peaceful with nothing else about, the left button pressed: game_frame with a one-second dt digs it (a
; second frame when the pause after a dig is still running).
; ebx = block, r12d = held, r13d = floor x, then the frames run, r14d = floor z.
dig_leaf:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r12d, esi
    call    world_clear
    call    mobs_clear
    call    drops_clear
    mov     r14d, 4
.fz:
    mov     r13d, 4
.fx:
    mov     edi, r13d
    mov     esi, 9
    mov     edx, r14d
    mov     ecx, STONE
    call    world_set
    inc     r13d
    cmp     r13d, 12
    jbe     .fx
    inc     r14d
    cmp     r14d, 12
    jbe     .fz
    mov     edi, 8
    mov     esi, 11
    mov     edx, 6
    mov     ecx, ebx
    call    world_set
    lea     rdi, [player]
    movss   xmm0, [k_p_half_w]
    movss   xmm1, [k_p_height]
    movss   xmm2, [k_p_speed]
    call    body_init
    mov     dword [player + BODY.x], __float32__(8.5)
    mov     dword [player + BODY.y], __float32__(10.0)
    mov     dword [player + BODY.z], __float32__(8.5)
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [game_time], 6007
    mov     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    call    survival_reset
    call    combat_reset
    call    inv_clear
    mov     dword [inv_sel], 0
    test    r12d, r12d
    jz      .bare
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.id], r12b
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.count], 1
.bare:
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    mov     dword [frame_input + FRAMEINPUT.slot], -1
    mov     dword [frame_input + FRAMEINPUT.lmb_held], 1
    mov     dword [frame_input + FRAMEINPUT.lmb_pressed], 1
    mov     dword [input_captured], 1
    mov     dword [game_open_screen], 0
    mov     dword [game_heavy_s], __float32__(-1.0)
    mov     dword [game_break_progress], 0
    mov     dword [brk_y], -1
    xor     r13d, r13d
.frame:
    movss   xmm0, [k_one]
    call    game_frame
    inc     r13d
    mov     edi, 8
    mov     esi, 11
    mov     edx, 6
    call    world_get
    test    eax, eax
    jz      .dug
    cmp     r13d, 4
    jb      .frame
    mov     eax, -1
    jmp     .out
.dug:
    lea     rsi, [drops]
    mov     ecx, MAX_DROPS
    xor     eax, eax
.scan:
    movzx   edx, byte [rsi + DROP.id]
    test    edx, edx
    jz      .free
    mov     eax, edx
    jmp     .out
.free:
    add     rsi, DROP_size
    dec     ecx
    jnz     .scan
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; apple_digs(edi block) -> eax: how many of 120 bare-handed digs of `block` leave an APPLE, -1 when one of
; them leaves anything else (or the block stands)
apple_digs:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    xor     r12d, r12d
    mov     r13d, 120
.dig:
    mov     edi, ebx
    xor     esi, esi
    call    dig_leaf
    test    eax, eax
    jz      .next
    cmp     eax, APPLE
    jne     .bad
    inc     r12d
.next:
    dec     r13d
    jnz     .dig
    mov     eax, r12d
    jmp     .out
.bad:
    mov     eax, -1
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

test_game_save_load_roundtrip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    mov     edi, 7
    call    rng_seed
    lea     rdi, [d_world]              ; the world directory path, in memory a callee may write to
    lea     rsi, [d_world_str]
    mov     edx, 63
    call    str_copy
    lea     rdi, [d_world]              ; a clean world directory with its regions/
    call    dir_remove_tree
    lea     rdi, [dir_buf]
    lea     rsi, [d_regions]
    mov     edx, 127
    call    str_copy
    lea     rdi, [dir_buf]
    call    mkdir_p
    test    eax, eax
    jnz     .fail
    mov     edi, 42
    mov     esi, MODE_SURVIVAL
    lea     rdx, [name_rt]
    lea     rcx, [d_world]
    call    game_new
    mov     dword [surv + SURVIVAL.health], 45      ; above the bare 20: the amulet's +33 holds it
    mov     dword [surv + SURVIVAL.food], 9
    mov     dword [surv + SURVIVAL.breath], 321
    lea     rax, [inv + INVENTORY.slots + 3*4]
    mov     byte [rax + ITEMSTACK.id], STONE_PICKAXE
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 7
    lea     rax, [inv + INVENTORY.armor + 1*4]
    mov     byte [rax + ITEMSTACK.id], IRON_CHESTPLATE
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 3
    lea     rax, [inv + INVENTORY.jewelry + 0*4]    ; a rare ring (rarity 2, tier 3, seed 5) ...
    mov     byte [rax + ITEMSTACK.id], RING
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 0x8C05
    lea     rax, [inv + INVENTORY.jewelry + 2*4]    ; ... an amulet in the third cell ...
    mov     byte [rax + ITEMSTACK.id], AMULET
    mov     byte [rax + ITEMSTACK.count], 1
    mov     word [rax + ITEMSTACK.dmg], 0xFC01      ; epic, tier 15, seed 1: +33 max health
    lea     rax, [inv + INVENTORY.jewelry + 1*4]    ; ... and a sword in the second, which a load must drop
    mov     byte [rax + ITEMSTACK.id], IRON_SWORD
    mov     byte [rax + ITEMSTACK.count], 1
    ; what the header image itself carries: a bed and two site records
    mov     dword [world_header + WORLDHDR.bed_x], 1234
    mov     dword [world_header + WORLDHDR.bed_y], 70
    mov     dword [world_header + WORLDHDR.bed_z], -567
    mov     dword [world_header + WORLDHDR.bed_set], 1
    mov     dword [world_header + WORLDHDR.site_count], 2
    mov     dword [world_header + WORLDHDR.sites + SITESTATE.rx], 5
    mov     dword [world_header + WORLDHDR.sites + SITESTATE.rz], -3
    mov     byte [world_header + WORLDHDR.sites + SITESTATE.slot], 1
    mov     byte [world_header + WORLDHDR.sites + SITESTATE.kind], SITE_DUNGEON
    mov     byte [world_header + WORLDHDR.sites + SITESTATE.kills], 3
    mov     byte [world_header + WORLDHDR.sites + SITESTATE.flags], 0
    mov     dword [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.rx], -1
    mov     dword [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.rz], 0
    mov     byte [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.slot], 0
    mov     byte [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.kind], SITE_CRYPT
    mov     byte [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.kills], 0
    mov     byte [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.flags], SS_CLEARED
    mov     dword [world_origin_x], 1024            ; the origin away from 0, the player in local cells
    mov     dword [world_origin_z], -512
    mov     dword [player + BODY.x], __float32__(100.5)
    mov     dword [player + BODY.y], __float32__(70.0)
    mov     dword [player + BODY.z], __float32__(-20.25)
    mov     dword [game_time], 12345
    call    spawn_pigs
    mov     ebx, eax
    lea     rdi, [d_world]
    call    game_save
    test    eax, eax
    jnz     .fail
    lea     rdi, [p_hdr]                            ; world.hdr is one whole v6 header
    lea     rsi, [file_buf]
    mov     edx, WORLD_HDR_SIZE + 16
    call    file_read
    cmp     rax, WORLD_HDR_SIZE
    jne     .fail
    mov     rax, "ACRAFT06"
    cmp     [file_buf], rax
    jne     .fail
    mov     byte [rpg_state + RPGSAVE.level], 30    ; a strong character in the session...
    mov     edi, 1
    mov     esi, MODE_CREATIVE
    lea     rdx, [name_x]
    xor     ecx, ecx
    call    game_new
    cmp     byte [rpg_state + RPGSAVE.level], 1     ; ...does not leak into a new world: the character
    jne     .fail                                   ; is fresh, and so are the animals that come with the area
    call    world_clear                             ; the terrain the area wait would have left: ground at (8, 30, 8)
    mov     edi, 8
    mov     esi, 30
    mov     edx, 8
    mov     ecx, STONE
    call    world_set
    mov     dword [player + BODY.x], __float32__(8.5)
    mov     dword [player + BODY.y], __float32__(99.0)
    mov     dword [player + BODY.z], __float32__(8.5)
    call    game_on_area_ready                      ; a new world: the player stands on the surface ...
    test    eax, eax
    jnz     .fail
    cmp     dword [player + BODY.y], __float32__(31.0)
    jne     .fail
    mov     dword [player + BODY.y], __float32__(99.0)
    call    game_on_area_ready                      ; ... once
    cmp     dword [player + BODY.y], __float32__(99.0)
    jne     .fail
    lea     rax, [mobs]
    mov     ecx, MAX_MOBS
.new_mob:
    cmp     dword [rax + MOB.type], MOB_NONE
    je      .new_next
    cmp     dword [rax + MOB.level], 1
    jne     .fail
.new_next:
    add     rax, MOB_size
    dec     ecx
    jnz     .new_mob
    cmp     dword [world_header + WORLDHDR.bed_set], 0      ; nor does the old world's bed or sites
    jne     .fail
    cmp     dword [world_header + WORLDHDR.site_count], 0
    jne     .fail
    lea     rdi, [d_world]
    call    game_load
    test    eax, eax
    jnz     .fail
    cmp     dword [surv + SURVIVAL.health], 45
    jne     .fail
    cmp     dword [surv + SURVIVAL.food], 9
    jne     .fail
    cmp     dword [surv + SURVIVAL.breath], 321
    jne     .fail
    lea     rax, [inv + INVENTORY.slots + 3*4]
    cmp     byte [rax + ITEMSTACK.id], STONE_PICKAXE
    jne     .fail
    cmp     byte [rax + ITEMSTACK.count], 1
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 7
    jne     .fail
    lea     rax, [inv + INVENTORY.armor + 1*4]
    cmp     byte [rax + ITEMSTACK.id], IRON_CHESTPLATE
    jne     .fail
    cmp     byte [rax + ITEMSTACK.count], 1
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 3
    jne     .fail
    lea     rax, [inv + INVENTORY.jewelry + 0*4]
    cmp     byte [rax + ITEMSTACK.id], RING
    jne     .fail
    cmp     byte [rax + ITEMSTACK.count], 1
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 0x8C05
    jne     .fail
    lea     rax, [inv + INVENTORY.jewelry + 2*4]
    cmp     byte [rax + ITEMSTACK.id], AMULET
    jne     .fail
    cmp     word [rax + ITEMSTACK.dmg], 0xFC01
    jne     .fail
    lea     rax, [inv + INVENTORY.jewelry + 1*4]
    cmp     byte [rax + ITEMSTACK.count], 0
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_x], 1234     ; the header image came back whole
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_y], 70
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_z], -567
    jne     .fail
    cmp     dword [world_header + WORLDHDR.bed_set], 1
    jne     .fail
    cmp     dword [world_header + WORLDHDR.site_count], 2
    jne     .fail
    cmp     dword [world_header + WORLDHDR.sites + SITESTATE.rx], 5
    jne     .fail
    cmp     dword [world_header + WORLDHDR.sites + SITESTATE.rz], -3
    jne     .fail
    cmp     byte [world_header + WORLDHDR.sites + SITESTATE.kills], 3
    jne     .fail
    cmp     byte [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.kind], SITE_CRYPT
    jne     .fail
    cmp     byte [world_header + WORLDHDR.sites + SITESTATE_size + SITESTATE.flags], SS_CLEARED
    jne     .fail
    cmp     dword [world_origin_x], 1024                    ; the origin and the local position
    jne     .fail
    cmp     dword [world_origin_z], -512
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(100.5)
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(70.0)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(-20.25)
    jne     .fail
    cmp     dword [game_time], 12345
    jne     .fail
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .fail
    mov     edi, MOB_PIG
    call    mob_count_type
    cmp     eax, ebx
    jne     .fail
    lea     rdi, [world_header + WORLDHDR.name]
    lea     rsi, [name_rt]
    call    str_eq
    test    eax, eax
    jz      .fail
    ; a bad world.hdr is refused and leaves the session alone
    mov     dword [game_time], 777
    lea     rdi, [d_missing]                        ; no such world: 1
    call    game_load
    cmp     eax, 1
    jne     .fail
    cmp     dword [game_time], 777
    jne     .fail
    lea     rdi, [file_buf]                         ; a header cut short: 2
    mov     ecx, WORLD_HDR_SIZE / 8
    xor     eax, eax
    rep     stosq
    lea     rdi, [p_hdr]
    lea     rsi, [file_buf]
    mov     edx, 100
    call    file_write_atomic
    lea     rdi, [d_world]
    call    game_load
    cmp     eax, 2
    jne     .fail
    mov     rax, "ACRAFT05"                         ; a whole header of another version: 2
    mov     [file_buf], rax
    lea     rdi, [p_hdr]
    lea     rsi, [file_buf]
    mov     edx, WORLD_HDR_SIZE
    call    file_write_atomic
    lea     rdi, [d_world]
    call    game_load
    cmp     eax, 2
    jne     .fail
    cmp     dword [game_time], 777
    jne     .fail
    ; the player died (health 0 saved): the next load brings him back at the world spawn, with the
    ; origin in the spawn's 512-block cell and the player in the middle of the spawn cell
    mov     dword [surv + SURVIVAL.health], 0
    mov     dword [world_header + WORLDHDR.bed_set], 0      ; no bed: the world spawn is the target
    lea     rdi, [d_world]
    call    game_save
    test    eax, eax
    jnz     .fail
    lea     rdi, [d_world]
    call    game_load
    test    eax, eax
    jnz     .fail
    cmp     dword [surv + SURVIVAL.health], 0
    je      .fail
    mov     eax, [world_header + WORLDHDR.spawn_x]
    and     eax, -REBASE_STEP
    cmp     [world_origin_x], eax
    jne     .fail
    mov     eax, [world_header + WORLDHDR.spawn_z]
    and     eax, -REBASE_STEP
    cmp     [world_origin_z], eax
    jne     .fail
    movss   xmm0, [player + BODY.x]
    subss   xmm0, [k_half]
    cvttss2si eax, xmm0
    add     eax, [world_origin_x]
    cmp     eax, [world_header + WORLDHDR.spawn_x]
    jne     .fail
    movss   xmm0, [player + BODY.z]
    subss   xmm0, [k_half]
    cvttss2si eax, xmm0
    add     eax, [world_origin_z]
    cmp     eax, [world_header + WORLDHDR.spawn_z]
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    game_on_area_ready                      ; no pending respawn left behind
    lea     rdi, [d_world]
    call    dir_remove_tree
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; game_rebase: past 1024 blocks from the local origin on an axis, the origin moves by a multiple of
; 512 (the player's floored cell) and everything follows; an axis within bounds is left alone. The
; rest of the test is about game.asm too: the unload hook, and digging leaves with game_frame: an axe
; takes LEAVES, PINE_LEAVES and BIRCH_LEAVES themselves; a bare hand gets an APPLE now and then (and
; nothing else); dirt gives dirt (dig_leaf, apple_digs).
test_game_rebase_trigger:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    mov     eax, [game_mode]
    mov     [saved], eax
    mov     eax, [game_time]
    mov     [saved + 4], eax
    mov     eax, [settings + SETTINGS.difficulty]
    mov     [saved + 8], eax
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    mov     dword [player + BODY.x], __float32__(1030.25)
    mov     dword [player + BODY.y], __float32__(70.0)
    mov     dword [player + BODY.z], __float32__(-2050.5)
    mov     dword [game_has_target], 1
    mov     dword [game_target + RAYHIT.bx], 1040
    mov     dword [game_target + RAYHIT.by], 69
    mov     dword [game_target + RAYHIT.bz], -2040
    mov     dword [game_target + RAYHIT.px], 1041
    mov     dword [game_target + RAYHIT.py], 69
    mov     dword [game_target + RAYHIT.pz], -2041
    mov     dword [brk_x], 1040                     ; a block being dug
    mov     dword [brk_y], 69
    mov     dword [brk_z], -2040
    call    game_rebase
    cmp     dword [world_origin_x], 1024            ; floor(1030.25) sar 9 shl 9
    jne     .fail
    cmp     dword [world_origin_z], -2560           ; floor(-2050.5) = -2051: -5 * 512
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(6.25)
    jne     .fail
    cmp     dword [player + BODY.y], __float32__(70.0)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(509.5)
    jne     .fail
    cmp     dword [game_target + RAYHIT.bx], 16
    jne     .fail
    cmp     dword [game_target + RAYHIT.by], 69
    jne     .fail
    cmp     dword [game_target + RAYHIT.bz], 520
    jne     .fail
    cmp     dword [game_target + RAYHIT.px], 17
    jne     .fail
    cmp     dword [game_target + RAYHIT.pz], 519
    jne     .fail
    cmp     dword [brk_x], 16
    jne     .fail
    cmp     dword [brk_z], 520
    jne     .fail
    call    game_rebase                             ; now within bounds on both axes: nothing moves
    cmp     dword [world_origin_x], 1024
    jne     .fail
    cmp     dword [world_origin_z], -2560
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(6.25)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(509.5)
    jne     .fail
    mov     dword [player + BODY.x], __float32__(-1100.5)   ; one axis out, the other at 700: that one stays
    mov     dword [player + BODY.z], __float32__(700.25)
    mov     dword [brk_y], -1                       ; no dig under way: its cell is left alone
    mov     dword [brk_x], 5
    mov     dword [brk_z], 5
    call    game_rebase
    cmp     dword [world_origin_x], -512            ; 1024 + (floor(-1100.5) = -1101 -> -1536)
    jne     .fail
    cmp     dword [world_origin_z], -2560
    jne     .fail
    cmp     dword [player + BODY.x], __float32__(435.5)
    jne     .fail
    cmp     dword [player + BODY.z], __float32__(700.25)
    jne     .fail
    cmp     dword [brk_x], 5
    jne     .fail
    cmp     dword [brk_z], 5
    jne     .fail
    ; the hook for a column that goes away: what stands in the box leaves; a trade, dialog or leader
    ; screen open on a folk inside it closes first, one open on a folk outside stays
    call    mobs_clear
    mov     edi, MOB_PIG
    movss   xmm0, [k_edge]
    movss   xmm1, [k_pig_y]
    movss   xmm2, [k_row]
    call    mob_spawn                               ; inside, on the box's last column and first row
    test    eax, eax
    js      .fail
    mov     [rsp], eax
    mov     edi, MOB_PIG
    movss   xmm0, [k_over]
    movss   xmm1, [k_pig_y]
    movss   xmm2, [k_row]
    call    mob_spawn                               ; outside, one column further
    test    eax, eax
    js      .fail
    mov     [rsp + 4], eax
    mov     dword [input_captured], 1               ; the cursor is captured: app_goto leaves GLFW alone
    mov     dword [app_state], ST_TRADE
    mov     eax, [rsp + 4]
    mov     [game_open_npc], eax
    mov     edi, 48
    mov     esi, 48
    mov     edx, 63
    mov     ecx, 63
    call    game_unload_box
    cmp     dword [app_state], ST_TRADE             ; the screen's folk is outside: it stays open
    jne     .fail
    lea     rcx, [mobs]
    mov     eax, [rsp]
    imul    eax, eax, MOB_size
    cmp     dword [rcx + rax + MOB.type], MOB_NONE  ; the pig inside is gone
    jne     .fail
    mov     eax, [rsp + 4]
    imul    eax, eax, MOB_size
    cmp     dword [rcx + rax + MOB.type], MOB_PIG   ; the one outside is not
    jne     .fail
    mov     edi, MOB_PIG
    movss   xmm0, [k_edge]
    movss   xmm1, [k_pig_y]
    movss   xmm2, [k_row]
    call    mob_spawn                               ; a folk inside, with its screen open
    test    eax, eax
    js      .fail
    mov     [game_open_npc], eax
    mov     edi, 48
    mov     esi, 48
    mov     edx, 63
    mov     ecx, 63
    call    game_unload_box
    cmp     dword [app_state], ST_PLAYING           ; back in the game
    jne     .fail
    mov     edi, MOB_PIG                            ; ... and so does a leader's screen
    movss   xmm0, [k_edge]
    movss   xmm1, [k_pig_y]
    movss   xmm2, [k_row]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     [game_open_npc], eax
    mov     dword [app_state], ST_LEADER
    mov     edi, 48
    mov     esi, 48
    mov     edx, 63
    mov     ecx, 63
    call    game_unload_box
    cmp     dword [app_state], ST_PLAYING
    jne     .fail
    ; the dig path: leaves dug with an axe come out as themselves, whichever tree they grew on ...
    mov     edi, 1234
    call    rng_seed
    mov     edi, LEAVES
    mov     esi, IRON_AXE
    call    dig_leaf
    cmp     eax, LEAVES
    jne     .fail
    mov     edi, PINE_LEAVES
    mov     esi, IRON_AXE
    call    dig_leaf
    cmp     eax, PINE_LEAVES
    jne     .fail
    mov     edi, BIRCH_LEAVES
    mov     esi, IRON_AXE
    call    dig_leaf
    cmp     eax, BIRCH_LEAVES
    jne     .fail
    mov     edi, DIRT                   ; (a plain block gives its table drop, as before)
    xor     esi, esi
    call    dig_leaf
    cmp     eax, DIRT
    jne     .fail
    ; ... and with a bare hand they sometimes give an apple (one in sixteen), never anything else
    mov     edi, LEAVES
    call    apple_digs
    sub     eax, 1
    cmp     eax, 39                     ; 1..40 apples in 120 digs
    ja      .fail
    mov     edi, PINE_LEAVES
    call    apple_digs
    sub     eax, 1
    cmp     eax, 39
    ja      .fail
    mov     edi, BIRCH_LEAVES
    call    apple_digs
    sub     eax, 1
    cmp     eax, 39
    ja      .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    mobs_clear
    mov     dword [app_state], ST_TITLE
    mov     dword [input_captured], 0
    mov     dword [game_open_npc], 0
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    mov     dword [game_has_target], 0
    mov     dword [brk_y], -1
    mov     eax, [saved]
    mov     [game_mode], eax
    mov     eax, [saved + 4]
    mov     [game_time], eax
    mov     eax, [saved + 8]
    mov     [settings + SETTINGS.difficulty], eax
    call    drops_clear
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    call    inv_clear
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- 0.10: factions ---------------------------------------------------------------------------

; frame_arena(): the room a game_frame test needs, dig_leaf's set-up without its target block and
; click: a STONE floor (x, z 4..12 at y 9), the player at (8.5, 10, 8.5) looking along -z, Survival,
; by day in Peaceful with nothing else about (no mobs, drops or items), the cursor captured, no
; screen open and no button down. ebx = floor x, r12d = floor z.
frame_arena:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    mobs_clear
    call    drops_clear
    mov     r12d, 4
.fz:
    mov     ebx, 4
.fx:
    mov     edi, ebx
    mov     esi, 9
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 12
    jbe     .fx
    inc     r12d
    cmp     r12d, 12
    jbe     .fz
    lea     rdi, [player]
    movss   xmm0, [k_p_half_w]
    movss   xmm1, [k_p_height]
    movss   xmm2, [k_p_speed]
    call    body_init
    mov     dword [player + BODY.x], __float32__(8.5)
    mov     dword [player + BODY.y], __float32__(10.0)
    mov     dword [player + BODY.z], __float32__(8.5)
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [game_time], 6007
    mov     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    call    survival_reset
    call    combat_reset
    call    inv_clear
    mov     dword [inv_sel], 0
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
    pop     r12
    pop     rbx
    pop     rbp
    ret

; The faction standings live in the header image (WORLDHDR.standing, .champions): game_new starts
; them at 200, -100, -100, 0, 0 with no champion defeated; game_save / game_load carry them through
; the file (Bandits 321 and champions 0b101 survive a round trip that zeroed them); a world.hdr
; edited by hand loads clamped: Bandits 5000 -> 1000, Beastfolk -4000 -> -1000, the Ashen Cult 400
; -> 199, stray champion bits (0xE5) -> 0x05.
test_faction_save_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    mov     eax, [game_mode]
    mov     [saved], eax
    mov     eax, [game_time]
    mov     [saved + 4], eax
    mov     edi, 7
    call    rng_seed
    lea     rdi, [d_world]
    lea     rsi, [d_world_str]
    mov     edx, 63
    call    str_copy
    lea     rdi, [d_world]
    call    dir_remove_tree
    lea     rdi, [dir_buf]
    lea     rsi, [d_regions]
    mov     edx, 127
    call    str_copy
    lea     rdi, [dir_buf]
    call    mkdir_p
    test    eax, eax
    jnz     .fail
    mov     edi, 42
    mov     esi, MODE_SURVIVAL
    lea     rdx, [name_rt]
    lea     rcx, [d_world]
    call    game_new
    cmp     word [world_header + WORLDHDR.standing + FAC_VILLAGERS*2], 200     ; a new world's start
    jne     .fail
    cmp     word [world_header + WORLDHDR.standing + FAC_BANDITS*2], -100
    jne     .fail
    cmp     word [world_header + WORLDHDR.standing + FAC_CULT*2], -100
    jne     .fail
    cmp     word [world_header + WORLDHDR.standing + FAC_BEASTFOLK*2], 0
    jne     .fail
    cmp     word [world_header + WORLDHDR.standing + FAC_STONEKIN*2], 0
    jne     .fail
    cmp     byte [world_header + WORLDHDR.champions], 0
    jne     .fail
    mov     word [world_header + WORLDHDR.standing + FAC_BANDITS*2], 321
    mov     byte [world_header + WORLDHDR.champions], 0b101
    lea     rdi, [d_world]
    call    game_save
    test    eax, eax
    jnz     .fail
    mov     qword [world_header + WORLDHDR.standing], 0     ; ... zeroed in the session ...
    mov     qword [world_header + WORLDHDR.standing + 8], 0
    mov     byte [world_header + WORLDHDR.champions], 0
    lea     rdi, [d_world]
    call    game_load
    test    eax, eax
    jnz     .fail
    cmp     word [world_header + WORLDHDR.standing + FAC_BANDITS*2], 321       ; ... and back from the file
    jne     .fail
    cmp     word [world_header + WORLDHDR.standing + FAC_VILLAGERS*2], 200
    jne     .fail
    cmp     word [world_header + WORLDHDR.standing + FAC_CULT*2], -100
    jne     .fail
    cmp     byte [world_header + WORLDHDR.champions], 0b101
    jne     .fail
    lea     rdi, [p_hdr]                            ; a header edited by hand: out of range on disk
    lea     rsi, [file_buf]
    mov     edx, WORLD_HDR_SIZE + 16
    call    file_read
    cmp     rax, WORLD_HDR_SIZE
    jne     .fail
    mov     word [file_buf + WORLDHDR.standing + FAC_BANDITS*2], 5000
    mov     word [file_buf + WORLDHDR.standing + FAC_CULT*2], 400
    mov     word [file_buf + WORLDHDR.standing + FAC_BEASTFOLK*2], -4000
    mov     byte [file_buf + WORLDHDR.champions], 0xE5
    lea     rdi, [p_hdr]
    lea     rsi, [file_buf]
    mov     edx, WORLD_HDR_SIZE
    call    file_write_atomic
    lea     rdi, [d_world]
    call    game_load
    test    eax, eax
    jnz     .fail
    cmp     word [world_header + WORLDHDR.standing + FAC_BANDITS*2], 1000
    jne     .fail
    cmp     word [world_header + WORLDHDR.standing + FAC_CULT*2], 199
    jne     .fail
    cmp     word [world_header + WORLDHDR.standing + FAC_BEASTFOLK*2], -1000
    jne     .fail
    cmp     word [world_header + WORLDHDR.standing + FAC_VILLAGERS*2], 200     ; what was in range stays
    jne     .fail
    cmp     byte [world_header + WORLDHDR.champions], 0x05
    jne     .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    game_on_area_ready                      ; no pending respawn left behind
    lea     rdi, [d_world]
    call    dir_remove_tree
    mov     dword [world_origin_x], 0
    mov     dword [world_origin_z], 0
    call    faction_reset
    mov     eax, [saved]
    mov     [game_mode], eax
    mov     eax, [saved + 4]
    mov     [game_time], eax
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; game_frame's click handling for the 0.10 targets, in the arena of frame_arena. A shrine of the
; Stonekin (SHRINE + FAC_STONEKIN, a faction that is neither id 0 nor the base) 2 blocks ahead:
; the right click opens ST_SHRINE for faction 4. A Stonekin trader in the same line of sight at
; standing 200: the right click opens ST_TRADE with the folk as game_open_npc, screen_faction 4 and
; "Stonekin Trader" as the trade title, and is spent on the talk (a health potion in hand is not
; drunk; a sword in hand and the button held does not raise the guard on the press); the left
; click goes on to the melee branch like on any mob (a sword in hand starts charging a heavy
; attack: game_heavy_s leaves -1). At nothing the same right press with a sword raises the guard
; (combat_guard_t >= 0).
; ebx = the folk's slot
test_shrine_and_folk_dispatch:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     eax, [game_mode]
    mov     [saved], eax
    mov     eax, [game_time]
    mov     [saved + 4], eax
    mov     eax, [settings + SETTINGS.difficulty]
    mov     [saved + 8], eax
    call    frame_arena
    mov     edi, 8                                  ; the shrine, in the line of sight
    mov     esi, 11
    mov     edx, 6
    mov     ecx, SHRINE + FAC_STONEKIN
    call    world_set
    mov     dword [screen_faction], FAC_VILLAGERS
    mov     dword [frame_input + FRAMEINPUT.rmb_pressed], 1
    mov     dword [frame_input + FRAMEINPUT.rmb_held], 1
    movss   xmm0, [k_step]
    call    game_frame
    cmp     dword [game_open_screen], ST_SHRINE
    jne     .fail
    cmp     dword [screen_faction], FAC_STONEKIN
    jne     .fail
    mov     dword [game_open_screen], 0
    mov     dword [game_mode], MODE_CREATIVE        ; a creative left click does not break it
    mov     dword [frame_input + FRAMEINPUT.rmb_pressed], 0
    mov     dword [frame_input + FRAMEINPUT.rmb_held], 0
    mov     dword [frame_input + FRAMEINPUT.lmb_pressed], 1
    mov     dword [frame_input + FRAMEINPUT.lmb_held], 1
    movss   xmm0, [k_step]
    call    game_frame
    mov     edi, 8
    mov     esi, 11
    mov     edx, 6
    call    world_get
    cmp     eax, SHRINE + FAC_STONEKIN
    jne     .fail
    mov     dword [frame_input + FRAMEINPUT.lmb_pressed], 0 ; nor does a creative pick give it as an item
    mov     dword [frame_input + FRAMEINPUT.lmb_held], 0
    mov     dword [frame_input + FRAMEINPUT.mmb_pressed], 1
    movss   xmm0, [k_step]
    call    game_frame
    mov     dword [frame_input + FRAMEINPUT.mmb_pressed], 0
    mov     eax, [inv_sel]
    lea     rcx, [inv + INVENTORY.slots]
    cmp     byte [rcx + rax*4 + ITEMSTACK.id], SHRINE
    je      .fail
    mov     dword [game_mode], MODE_SURVIVAL        ; frame_arena's mode
    mov     dword [frame_input + FRAMEINPUT.lmb_pressed], 0
    mov     dword [frame_input + FRAMEINPUT.lmb_held], 0
    mov     dword [frame_input + FRAMEINPUT.rmb_pressed], 1
    mov     dword [frame_input + FRAMEINPUT.rmb_held], 1
    mov     edi, 8                                  ; the shrine away, a folk in its place
    mov     esi, 11
    mov     edx, 6
    xor     ecx, ecx
    call    world_set
    xor     edi, edi
    call    trade_open                              ; the trade title the folk must change
    mov     dword [screen_faction], FAC_VILLAGERS
    mov     word [world_header + WORLDHDR.standing + FAC_STONEKIN*2], 200
    mov     edi, FAC_STONEKIN
    mov     esi, ROLE_TRADER
    xor     edx, edx
    movss   xmm0, [k_folk_x]
    movss   xmm1, [k_folk_y]
    movss   xmm2, [k_folk_z]
    call    folk_spawn
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     dword [game_open_npc], -1
    lea     rax, [inv + INVENTORY.slots]            ; a health potion in hand: a click that is not
    mov     byte [rax + ITEMSTACK.id], HEALTH_POTION    ; spent on the talk would drink it
    mov     byte [rax + ITEMSTACK.count], 1
    movss   xmm0, [k_step]
    call    game_frame
    cmp     dword [game_open_screen], ST_TRADE
    jne     .fail
    cmp     [game_open_npc], ebx
    jne     .fail
    cmp     dword [screen_faction], FAC_STONEKIN
    jne     .fail
    mov     rdi, [trade_title]
    lea     rsi, [s_stk_trader]
    call    str_eq
    test    eax, eax
    jz      .fail
    lea     rax, [inv + INVENTORY.slots]
    cmp     byte [rax + ITEMSTACK.count], 1         ; the click was spent on the talk
    jne     .fail
    mov     dword [game_open_screen], 0             ; a sword and the button held: the press talks and
    mov     dword [game_open_npc], -1               ; does not raise the guard
    lea     rax, [inv + INVENTORY.slots]
    mov     byte [rax + ITEMSTACK.id], IRON_SWORD
    movss   xmm0, [k_step]
    call    game_frame
    cmp     dword [game_open_screen], ST_TRADE
    jne     .fail
    cmp     dword [combat_guard_t], 0
    jge     .fail
    mov     dword [game_open_screen], 0             ; the left button
    mov     dword [frame_input + FRAMEINPUT.rmb_pressed], 0
    mov     dword [frame_input + FRAMEINPUT.rmb_held], 0
    mov     dword [frame_input + FRAMEINPUT.lmb_pressed], 1
    mov     dword [frame_input + FRAMEINPUT.lmb_held], 1
    movss   xmm0, [k_step]
    call    game_frame
    movss   xmm0, [game_heavy_s]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jb      .fail                                   ; still idle: the folk swallowed the click
    call    mobs_clear                              ; nobody there: the right press raises the guard
    mov     dword [game_open_screen], 0
    mov     dword [frame_input + FRAMEINPUT.lmb_pressed], 0
    mov     dword [frame_input + FRAMEINPUT.lmb_held], 0
    mov     dword [frame_input + FRAMEINPUT.rmb_pressed], 1
    mov     dword [frame_input + FRAMEINPUT.rmb_held], 1
    movss   xmm0, [k_step]
    call    game_frame
    cmp     dword [combat_guard_t], 0
    jl      .fail
    xor     ebx, ebx
    jmp     .done
.fail:
    mov     ebx, 1
.done:
    call    mobs_clear
    call    inv_clear
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    mov     dword [input_captured], 0
    mov     dword [game_open_screen], 0
    mov     dword [game_open_npc], 0
    mov     dword [game_heavy_s], __float32__(-1.0)
    mov     dword [game_has_target], 0
    mov     dword [screen_faction], FAC_VILLAGERS
    xor     edi, edi
    call    trade_open
    call    faction_reset
    mov     eax, [saved]
    mov     [game_mode], eax
    mov     eax, [saved + 4]
    mov     [game_time], eax
    mov     eax, [saved + 8]
    mov     [settings + SETTINGS.difficulty], eax
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
