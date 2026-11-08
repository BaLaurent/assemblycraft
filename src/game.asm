; game.asm - world session: new/load/save glue (a world is a directory with world.hdr), the floating
; origin (rebase), the area hooks of the streamed world, fixed-step simulation, block, mob, boat and
; bed interaction for both game modes.
%include "common.inc"
default rel

global game_mode, game_time, game_target, game_has_target, game_break_progress
global game_open_screen, game_open_cont, game_bow_charge, game_aim, game_open_npc, game_heavy_s
global game_new, game_load, game_save, game_frame, game_respawn
global game_rebase, game_shift_origin, game_unload_box, game_on_area_ready
global brk_x, brk_y, brk_z              ; the dig cell (the rebase test reads and sets it)

extern world_header, world_get, world_set, world_top_y
extern world_origin_x, world_origin_z, world_rebase, world_save_dirty
extern stream_begin, gen_find_spawn, floor_i
extern file_read, file_write_atomic, str_append
extern player, player_shift, body_init, body_step, player_look, player_eye, player_forward
extern raycast, frame_input, settings
extern inv, inv_sel, inv_clear, inv_set_creative_default, inv_held
extern inv_consume_held, inv_damage_held, inv_find_hotbar, inv_container
extern inv_count, inv_remove_one
extern item_break_time, item_harvest_drop, item_attack_damage
extern item_tool, item_food, item_max_stack, item_armor_slot, item_gear
extern block_hardness, block_dig_sound, block_step_sound
extern surv, survival_reset, survival_land, survival_step, survival_eat_step
extern survival_can_sprint, survival_exhaust
extern mobs, mobs_clear, mobs_populate, mobs_step, mobs_raycast, mob_hurt
extern mobs_save, mobs_load, mobs_shift, mobs_remove_box, folk_interact
extern audio_play, audio_play_at, rng_next, str_copy, input_captured
extern drops_clear, drops_spawn, drops_step, drops_shift, drops_remove_box, hand_swing
extern arrows_clear, arrows_step, arrows_spawn, arrows_shift
extern tnt_clear, tnt_step, tnt_prime, tnt_shift, tnt_remove_box
extern cont_at, cont_create, cont_block_removed, conts_step
extern gun_reset, gun_step, gun_fire, gun_reload_start, gun_index, gun_automatic
extern fire_clear, fire_place, fire_step, fire_shift, fire_remove_box
extern fx_clear, fx_step, fx_shift
extern rpg_reset, rpg_load, rpg_save, rpg_on_death, rpg_on_block_mined, rpg_class, rpg_stat
extern rpg_recompute, rpg_stats, rpg_keystones, status_step
extern combat_reset, combat_set_guard, combat_dodge, combat_melee, combat_heavy, combat_step, combat_heal
extern combat_speed_mult, combat_crit_roll, combat_max_mana
extern combat_guard_t, combat_hitstop, combat_mana, combat_stamina
extern abilities_reset, abilities_step, abilities_use, abilities_staff_bolt, abilities_shift
extern dmgnum_clear, dmgnum_step, dmgnum_shift
extern structures_reset, structures_step, structures_refresh, structures_shift
extern boats_clear, boats_step, boats_raycast, boats_place, boats_mount, boats_dismount
extern boats_break, boats_save, boats_load, boats_shift, boat_riding
extern sleep_use_bed, sleep_step, sleep_cancel, sleep_respawn_target, sleep_place_at_bed, sleep_active
extern app_state, app_goto
extern surv_max_health
extern place_block, block_use, block_removed, block_is_usable, block_base

section .rodata
align 4
step_dt:      dd 0.016666668
repeat_dt:    dd 0.25
reach_surv:   dd 4.5
reach_crea:   dd 5.0
mob_reach:    dd 3.5
mob_reach_spear: dd 4.5
f_one:        dd 1.0
f_half:       dd 0.5
f_quarter:    dd 0.25
f_hundred:    dd 100.0
f_step_len:   dd 1.6
vol_step:     dd 0.35
vol_crack:    dd 0.4
exh_attack:   dd 0.1
exh_break:    dd 0.005
abs_mask:     dd 0x7FFFFFFF
bow_start:    dd 0.001
bow_offset:   dd 0.3                   ; arrow spawn distance in front of the eye
bow_speed:    dd 45.0
bow_min:      dd 0.1                   ; weakest shot that leaves the bow
f_two:        dd 2.0
f_three:      dd 3.0
f_eight:      dd 8.0
vol_bow:      dd 0.8
aim_rate:     dd 12.0                  ; aiming eases in/out at min(1, 12 dt) per frame
aim_spread:   dd 0.75                  ; fully aimed: a quarter of the hip spread
aim_look:     dd 0.4                   ; fully aimed: 60 % look sensitivity
walk_speed:   dd 4.317
heavy_time:   dd 0.5                   ; seconds the button is held for a heavy attack
barrage_dmg:  dd 0.6                   ; Barrage's extra arrows do 60 % of the damage
sin6:         dd 0.10452846            ; sin and cos of 6 degrees: Barrage's spread
cos6:         dd 0.9945219
mana_potion:  dd 50.0
vol_drink:    dd 0.8
f_p_half_w:   dd 0.3                   ; the player's box (the walking speed is walk_speed)
f_p_height:   dd 1.8
lim_pos:      dd 65536.0               ; a saved position beyond this (or no number at all) is unusable
lim_y:        dd 256.0
m_v6:         db "ACRAFT06"
s_hdr_name:   db "/world.hdr", 0

section .data
align 4
game_mode: dd MODE_CREATIVE
game_time: dd NEW_WORLD_TIME
game_break_progress: dd 0.0
game_aim: dd 0.0                       ; float 0 (hip) .. 1 (down the sights)
game_heavy_s: dd __float32__(-1.0)     ; float seconds the left button has been held for a heavy attack; -1 = idle

section .bss
alignb 8
game_open_cont:  resq 1                 ; CONTAINER* of the furnace/chest to open
game_target:     resb RAYHIT_size
game_has_target: resd 1
game_open_screen: resd 1                ; 0, ST_CRAFTING, ST_FURNACE, ST_CHEST, ST_TRADE, ST_DIALOG
game_open_npc:   resd 1                 ; mob index of the merchant/elder whose screen opens
game_bow_charge: resd 1                 ; float seconds drawn, 0 = not drawing
step_accum:      resd 1
break_timer:     resd 1                 ; creative repeat timer
place_timer:     resd 1
break_cooldown:  resd 1                 ; survival: pause after a block breaks
crack_timer:     resd 1                 ; survival: next crack sound
step_dist:       resd 1                 ; walked distance since the last footstep
brk_x:           resd 1                 ; block being broken
brk_y:           resd 1
brk_z:           resd 1
pending_new:     resd 1                 ; a new world: stand on the surface and populate once the area is ready
pending_respawn: resd 1                 ; bit 0: stand on the ground, bit 1: find the bed; 0: nothing pending
region_x:        resd 1                 ; the player's region (absolute 512-block cell) at the last check
region_z:        resd 1
boat_hit:        resd 1                 ; the boat under the crosshair (nearer than any block) or -1
alignb 8
hdr_buf:         resb WORLD_HDR_SIZE + 64   ; game_load reads the header here before committing it
path_buf:        resb 4096              ; <dir>/world.hdr

section .text

; reset_session(): per-session timers, targeting and combat state
reset_session:
    push    rbp
    mov     rbp, rsp
    xor     eax, eax
    mov     [step_accum], eax
    mov     [break_timer], eax
    mov     [place_timer], eax
    mov     [break_cooldown], eax
    mov     [crack_timer], eax
    mov     [step_dist], eax
    mov     [game_has_target], eax
    mov     [game_open_screen], eax
    mov     [game_open_npc], eax
    mov     [game_open_cont], rax
    mov     [game_bow_charge], eax
    mov     [game_break_progress], eax
    mov     [game_aim], eax
    mov     dword [game_heavy_s], __float32__(-1.0)
    mov     dword [brk_y], -1
    mov     dword [boat_hit], -1
    call    sleep_cancel
    call    combat_reset
    call    abilities_reset
    call    dmgnum_clear
    pop     rbp
    jmp     gun_reset                   ; and the firearm's cooldown, reload and recoil

; hdr_path(rdi dir) -> rax path_buf holding "<dir>/world.hdr" (a dir over 4000 bytes is cut)
hdr_path:
    sub     rsp, 8
    mov     rsi, rdi
    lea     rdi, [path_buf]
    mov     edx, 4000
    call    str_copy
    mov     rdi, rax
    lea     rsi, [s_hdr_name]
    call    str_append
    mov     byte [rax], 0
    lea     rax, [path_buf]
    add     rsp, 8
    ret

; player_place(edi x, esi y, edx z): a new player body standing in the middle of that absolute cell
; (feet on its floor), looking a little down; world_origin_x/z must already be set
player_place:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    lea     rdi, [player]
    movss   xmm0, [f_p_half_w]
    movss   xmm1, [f_p_height]
    movss   xmm2, [walk_speed]
    call    body_init
    sub     ebx, [world_origin_x]
    cvtsi2ss xmm0, ebx
    addss   xmm0, [f_half]
    movss   [player + BODY.x], xmm0
    cvtsi2ss xmm0, r12d
    movss   [player + BODY.y], xmm0
    sub     r13d, [world_origin_z]
    cvtsi2ss xmm0, r13d
    addss   xmm0, [f_half]
    movss   [player + BODY.z], xmm0
    mov     dword [player + BODY.pitch], __float32__(30.0)
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; game_new(edi seed, esi mode, rdx name, rcx dir or 0)
; A new world: header, character and session reset. The spawn comes from the generator; the terrain
; streams in afterwards (app_wait_area), then game_on_area_ready stands the player on the surface and
; populates the world. dir is where its regions are saved (0: nowhere).
game_new:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16                     ; [rsp] spawn x, y, z (absolute)
    mov     ebx, edi
    mov     r12d, esi
    mov     r13, rdx
    mov     r14, rcx
    lea     rdi, [world_header]
    mov     ecx, WORLD_HDR_SIZE / 8
    xor     eax, eax
    rep     stosq
    mov     rax, [m_v6]
    mov     [world_header + WORLDHDR.magic], rax
    mov     [world_header + WORLDHDR.seed], ebx
    mov     [world_header + WORLDHDR.mode], r12d
    mov     dword [world_header + WORLDHDR.time], NEW_WORLD_TIME
    lea     rdi, [world_header + WORLDHDR.name]
    mov     rsi, r13
    mov     edx, 32
    call    str_copy
    mov     edi, ebx                    ; the new session first: it drops the old world and sets
    mov     rsi, r14                    ; the seed the spawn search needs
    call    stream_begin
    mov     rdi, rsp
    call    gen_find_spawn
    mov     eax, [rsp]
    mov     [world_header + WORLDHDR.spawn_x], eax
    and     eax, -REBASE_STEP           ; the origin: the spawn's 512-block cell
    mov     [world_origin_x], eax
    mov     [world_header + WORLDHDR.origin_x], eax
    mov     eax, [rsp + 4]
    mov     [world_header + WORLDHDR.spawn_y], eax
    mov     eax, [rsp + 8]
    mov     [world_header + WORLDHDR.spawn_z], eax
    and     eax, -REBASE_STEP
    mov     [world_origin_z], eax
    mov     [world_header + WORLDHDR.origin_z], eax
    mov     [game_mode], r12d
    mov     dword [game_time], NEW_WORLD_TIME
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    call    player_place
    call    survival_reset
    call    inv_clear
    cmp     r12d, MODE_CREATIVE
    jne     .no_kit
    call    inv_set_creative_default
.no_kit:
    mov     dword [inv_sel], 0
    call    mobs_clear
    call    drops_clear
    call    arrows_clear
    call    tnt_clear
    call    fire_clear
    call    fx_clear
    call    boats_clear
    mov     qword [inv_container], 0
    call    rpg_reset                   ; the animals that come with the area take the fresh character's level
    call    structures_reset
    mov     dword [pending_new], 1
    mov     dword [pending_respawn], 0
    call    reset_session
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

%macro POS_LIMIT 2                      ; jump to .bad_pos unless |player.%1| < the float at %2 (xmm2 = abs mask)
    movss   xmm0, [player + BODY.%1]
    andps   xmm0, xmm2
    movss   xmm1, [%2]
    ucomiss xmm1, xmm0
    jbe     .bad_pos
%endmacro

; game_load(rdi dir) -> eax 0 ok / 1 missing / 2 invalid / 3 I/O error
; Reads <dir>/world.hdr (exactly WORLD_HDR_SIZE bytes, magic "ACRAFT06"); nothing changes unless it is
; good. Then the streaming session of the world starts and the character, the origin, the mobs and the
; boats are restored (bed, sites and spawn stay in the header image world_header). A player who is
; dead or has no usable position respawns at the bed or the world spawn. The terrain streams in
; afterwards (app_wait_area, then game_on_area_ready).
game_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12, rdi
    call    hdr_path
    mov     rdi, rax
    lea     rsi, [hdr_buf]
    mov     edx, WORLD_HDR_SIZE + 1
    call    file_read
    cmp     rax, -ENOENT
    je      .missing
    test    rax, rax
    js      .ioerr
    cmp     rax, WORLD_HDR_SIZE
    jne     .invalid
    mov     rax, [hdr_buf]
    cmp     rax, [m_v6]
    jne     .invalid
    lea     rsi, [hdr_buf]
    lea     rdi, [world_header]
    mov     ecx, WORLD_HDR_SIZE / 8
    rep     movsq
    lea     rbx, [world_header]
    mov     edi, [rbx + WORLDHDR.seed]  ; the world's session: the old world goes, the seed is set
    mov     rsi, r12
    call    stream_begin
    mov     eax, [rbx + WORLDHDR.origin_x]  ; the origin: multiples of REBASE_STEP only
    and     eax, -REBASE_STEP
    mov     [rbx + WORLDHDR.origin_x], eax
    mov     [world_origin_x], eax
    mov     eax, [rbx + WORLDHDR.origin_z]
    and     eax, -REBASE_STEP
    mov     [rbx + WORLDHDR.origin_z], eax
    mov     [world_origin_z], eax
    ; mode
    mov     eax, [rbx + WORLDHDR.mode]
    cmp     eax, MODE_CREATIVE
    jbe     .mode_ok
    mov     eax, MODE_SURVIVAL
.mode_ok:
    mov     [game_mode], eax
    mov     eax, [rbx + WORLDHDR.time]
    mov     [game_time], eax
    ; player body, with the box and transient state fixed up
    lea     rsi, [rbx + WORLDHDR.player]
    lea     rdi, [player]
    mov     ecx, BODY_size
    rep     movsb
    xor     eax, eax
    mov     [player + BODY.vx], eax
    mov     [player + BODY.vy], eax
    mov     [player + BODY.vz], eax
    mov     [player + BODY.on_ground], eax
    mov     [player + BODY.kbx], eax
    mov     [player + BODY.kbz], eax
    mov     [player + BODY.fall], eax
    mov     [player + BODY.blocked], eax
    mov     eax, [f_p_half_w]           ; the player's box, as game_new's body_init sets it
    mov     [player + BODY.half_w], eax
    mov     eax, [f_p_height]
    mov     [player + BODY.height], eax
    mov     eax, [walk_speed]
    mov     [player + BODY.speed], eax
    and     dword [player + BODY.flying], 1
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .fly_ok
    mov     dword [player + BODY.flying], 0
.fly_ok:
    xor     r13d, r13d                  ; 1: the saved position cannot be used (dead player, garbage)
    movss   xmm2, [abs_mask]
    POS_LIMIT x, lim_pos
    POS_LIMIT z, lim_pos
    movss   xmm0, [player + BODY.y]
    xorps   xmm1, xmm1
    ucomiss xmm0, xmm1
    jb      .bad_pos                    ; below 0 or not a number
    movss   xmm1, [lim_y]
    ucomiss xmm1, xmm0
    jbe     .bad_pos
    jmp     .pos_ok
.bad_pos:
    mov     r13d, 1
.pos_ok:
    ; hotbar selection
    mov     eax, [rbx + WORLDHDR.sel]
    xor     ecx, ecx
    cmp     eax, HOTBAR_SLOTS
    cmovae  eax, ecx
    mov     [inv_sel], eax
    ; inventory: drop anything that is not a valid stack
    call    inv_clear
    xor     ecx, ecx
.slot:
    mov     eax, [rbx + WORLDHDR.inventory + rcx*4]
    movzx   edx, al                     ; id
    cmp     edx, NUM_ITEMS
    jae     .next
    movzx   r8d, byte [item_max_stack + rdx]
    test    r8d, r8d
    jz      .next
    movzx   r9d, byte [rbx + WORLDHDR.inventory + rcx*4 + ITEMSTACK.count]
    test    r9d, r9d
    jz      .next
    cmp     r9d, r8d
    ja      .next
    mov     [inv + INVENTORY.slots + rcx*4], eax
.next:
    inc     ecx
    cmp     ecx, INV_SLOTS
    jb      .slot
    ; armor: a slot keeps only a single piece made for it
    xor     ecx, ecx
.armor:
    mov     eax, [rbx + WORLDHDR.armor + rcx*4]
    movzx   edx, al
    cmp     edx, NUM_ITEMS
    jae     .armor_next
    movzx   r8d, byte [item_armor_slot + rdx]
    lea     r9d, [ecx + 1]
    cmp     r8d, r9d
    jne     .armor_next
    cmp     byte [rbx + WORLDHDR.armor + rcx*4 + ITEMSTACK.count], 1
    jne     .armor_next
    mov     [inv + INVENTORY.armor + rcx*4], eax
.armor_next:
    inc     ecx
    cmp     ecx, 4
    jb      .armor
    ; jewelry: a ring in each of the first two cells, an amulet in the third, one of each only
    xor     ecx, ecx
.jewel:
    mov     eax, [rbx + WORLDHDR.jewelry + rcx*4]
    movzx   edx, al
    cmp     edx, NUM_ITEMS
    jae     .jewel_next
    cmp     byte [rbx + WORLDHDR.jewelry + rcx*4 + ITEMSTACK.count], 1
    jne     .jewel_next
    mov     r9d, GK_RING
    mov     r10d, GK_AMULET
    cmp     ecx, 2
    cmove   r9d, r10d
    lea     r8, [item_gear]
    movzx   r8d, byte [r8 + rdx]
    cmp     r8d, r9d
    jne     .jewel_next
    mov     [inv + INVENTORY.jewelry + rcx*4], eax
.jewel_next:
    inc     ecx
    cmp     ecx, 3
    jb      .jewel
    ; RPG progression (sets surv_max_health with the gear just restored), then the survival
    ; stats clamped to it
    mov     rdi, rbx
    call    rpg_load
    call    survival_reset
    mov     eax, [rbx + WORLDHDR.health]
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    mov     ecx, [surv_max_health]
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [surv + SURVIVAL.health], eax
    mov     eax, [rbx + WORLDHDR.food]
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    mov     ecx, 20
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [surv + SURVIVAL.food], eax
    mov     eax, [rbx + WORLDHDR.saturation]
    mov     [surv + SURVIVAL.saturation], eax
    mov     eax, [rbx + WORLDHDR.exhaustion]
    mov     [surv + SURVIVAL.exhaustion], eax
    mov     eax, [rbx + WORLDHDR.breath]    ; air left: 0..MAX_BREATH (anything else is a full lung)
    mov     ecx, MAX_BREATH
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [surv + SURVIVAL.breath], eax
    cmp     dword [surv + SURVIVAL.health], 0
    jne     .alive
    call    survival_reset
    call    rpg_on_death                ; died, then quit from the death screen: same XP loss
    mov     r13d, 1                     ; ... and back at the bed or the spawn
.alive:
    cmp     dword [rbx + WORLDHDR.bed_set], 1   ; header state that must be sane: bed flag, site count
    jbe     .bed_ok
    mov     dword [rbx + WORLDHDR.bed_set], 0
.bed_ok:
    cmp     dword [rbx + WORLDHDR.site_count], MAX_SITESTATES
    jbe     .sites_ok
    mov     dword [rbx + WORLDHDR.site_count], 0
.sites_ok:
    mov     rdi, rbx
    call    mobs_load
    call    drops_clear
    call    arrows_clear
    call    tnt_clear
    call    fire_clear                  ; fires are not saved
    call    fx_clear
    call    boats_clear
    mov     rdi, rbx
    call    boats_load
    call    structures_reset
    mov     qword [inv_container], 0
    mov     dword [pending_new], 0
    mov     dword [pending_respawn], 0
    call    reset_session
    test    r13d, r13d
    jz      .done
    call    respawn_at_target           ; after the mobs and boats are in: the origin shift moves them too
.done:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
.missing:
    mov     eax, 1
    jmp     .ret
.invalid:
    mov     eax, 2
    jmp     .ret
.ioerr:
    mov     eax, 3
    jmp     .ret

; game_save(rdi dir) -> eax 0 or the first -errno
; Writes <dir>/world.hdr (atomically) from the live state, then every modified column of the world.
game_save:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12, rdi
    lea     rbx, [world_header]
    mov     rax, [m_v6]
    mov     [rbx + WORLDHDR.magic], rax
    lea     rsi, [player]
    lea     rdi, [rbx + WORLDHDR.player]
    mov     ecx, BODY_size
    rep     movsb
    mov     eax, [surv + SURVIVAL.health]
    mov     [rbx + WORLDHDR.health], eax
    mov     eax, [surv + SURVIVAL.food]
    mov     [rbx + WORLDHDR.food], eax
    mov     eax, [surv + SURVIVAL.saturation]
    mov     [rbx + WORLDHDR.saturation], eax
    mov     eax, [surv + SURVIVAL.exhaustion]
    mov     [rbx + WORLDHDR.exhaustion], eax
    mov     eax, [surv + SURVIVAL.breath]
    mov     [rbx + WORLDHDR.breath], eax
    mov     eax, [inv_sel]
    mov     [rbx + WORLDHDR.sel], eax
    lea     rsi, [inv + INVENTORY.slots]
    lea     rdi, [rbx + WORLDHDR.inventory]
    mov     ecx, INV_SLOTS * 4
    rep     movsb
    lea     rsi, [inv + INVENTORY.armor]
    lea     rdi, [rbx + WORLDHDR.armor]
    mov     ecx, 16
    rep     movsb
    lea     rsi, [inv + INVENTORY.jewelry]
    lea     rdi, [rbx + WORLDHDR.jewelry]
    mov     ecx, 12                     ; ring, ring, amulet
    rep     movsb
    mov     eax, [game_time]
    mov     [rbx + WORLDHDR.time], eax
    mov     eax, [game_mode]
    mov     [rbx + WORLDHDR.mode], eax
    mov     eax, [world_origin_x]
    mov     [rbx + WORLDHDR.origin_x], eax
    mov     eax, [world_origin_z]
    mov     [rbx + WORLDHDR.origin_z], eax
    mov     rdi, rbx
    call    boats_save
    mov     rdi, rbx
    call    mobs_save
    mov     rdi, rbx
    call    rpg_save
    mov     rdi, r12
    call    hdr_path
    mov     rdi, rax
    lea     rsi, [world_header]
    mov     edx, WORLD_HDR_SIZE
    call    file_write_atomic
    mov     ebx, eax                    ; the header's result: the columns are written regardless
    mov     rdi, r12
    call    world_save_dirty
    test    ebx, ebx
    cmovnz  eax, ebx                    ; the first error wins
    pop     r12
    pop     rbx
    pop     rbp
    ret

; respawn_at_target(): the player goes to the bed when one is set, else to the world spawn. The
; origin moves to the target's 512-block cell (game_shift_origin: every entity follows), the body is
; made new there, and pending_respawn asks game_on_area_ready to settle the player once the area
; around has loaded (bit 0: stand on the ground; bit 1: a bed: sleep_place_at_bed).
respawn_at_target:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24                     ; [rsp] target x, y, z (absolute)
    cmp     dword [boat_riding], 0
    je      .afoot
    call    boats_dismount
.afoot:
    mov     rdi, rsp
    call    sleep_respawn_target        ; eax 1 and the bed's foot cell (local) when a bed is set
    mov     ebx, eax
    test    ebx, ebx
    jz      .spawn
    mov     eax, [world_origin_x]
    add     [rsp], eax
    mov     eax, [world_origin_z]
    add     [rsp + 8], eax
    jmp     .target
.spawn:
    mov     eax, [world_header + WORLDHDR.spawn_x]
    mov     [rsp], eax
    mov     eax, [world_header + WORLDHDR.spawn_y]
    mov     [rsp + 4], eax
    mov     eax, [world_header + WORLDHDR.spawn_z]
    mov     [rsp + 8], eax
.target:
    mov     edi, [rsp]
    and     edi, -REBASE_STEP
    sub     edi, [world_origin_x]
    mov     esi, [rsp + 8]
    and     esi, -REBASE_STEP
    sub     esi, [world_origin_z]
    mov     eax, edi
    or      eax, esi
    jz      .in_cell
    call    game_shift_origin
.in_cell:
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    call    player_place
    mov     eax, 1
    test    ebx, ebx
    jz      .pending
    or      eax, 2
.pending:
    mov     [pending_respawn], eax
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; game_respawn(): full stats, back at the bed (or the world spawn); the app then waits for the area
game_respawn:
    push    rbp
    mov     rbp, rsp
    call    survival_reset
    call    rpg_on_death
    call    reset_session               ; combat state too, and any sleep
    call    respawn_at_target
    pop     rbp
    ret

; game_rebase(): when the player is REBASE_AT blocks or more from the local origin on an axis, the
; origin moves by a multiple of REBASE_STEP (the player's cell floored to it), so coordinates stay
; small; every position follows (game_shift_origin). An axis still within bounds stays as it is.
game_rebase:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     eax, REBASE_AT
    cvtsi2ss xmm3, eax
    movss   xmm2, [abs_mask]
    xor     ebx, ebx                    ; dx
    xor     r12d, r12d                  ; dz
    movss   xmm0, [player + BODY.x]
    movaps  xmm1, xmm0
    andps   xmm1, xmm2
    comiss  xmm1, xmm3
    jb      .x_done                     ; (also when it is not a number)
    roundss xmm0, xmm0, 9
    cvttss2si ebx, xmm0
    and     ebx, -REBASE_STEP
.x_done:
    movss   xmm0, [player + BODY.z]
    movaps  xmm1, xmm0
    andps   xmm1, xmm2
    comiss  xmm1, xmm3
    jb      .z_done
    roundss xmm0, xmm0, 9
    cvttss2si r12d, xmm0
    and     r12d, -REBASE_STEP
.z_done:
    mov     eax, ebx
    or      eax, r12d
    jz      .ret
    mov     edi, ebx
    mov     esi, r12d
    call    game_shift_origin
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

%macro SHIFT_CALL 1                     ; %1(dx, dz) with the pair kept in ebx / r12d
    mov     edi, ebx
    mov     esi, r12d
    call    %1
%endmacro

; game_shift_origin(edi dx, esi dz): the local frame's origin moves by (dx, dz), multiples of
; REBASE_STEP: the world keeps its data, every stored position (player, mobs, drops, arrows, TNT,
; fires, particles, damage numbers, ability targets, boats, this module's target and dig cells)
; drops by (dx, dz), and the site cache is rebuilt.
game_shift_origin:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    call    world_rebase
    SHIFT_CALL player_shift
    SHIFT_CALL mobs_shift
    SHIFT_CALL drops_shift
    SHIFT_CALL arrows_shift
    SHIFT_CALL tnt_shift
    SHIFT_CALL fire_shift
    SHIFT_CALL fx_shift
    SHIFT_CALL dmgnum_shift
    SHIFT_CALL abilities_shift
    SHIFT_CALL boats_shift
    sub     [game_target + RAYHIT.bx], ebx
    sub     [game_target + RAYHIT.px], ebx
    sub     [game_target + RAYHIT.bz], r12d
    sub     [game_target + RAYHIT.pz], r12d
    cmp     dword [brk_y], -1
    je      .no_dig
    sub     [brk_x], ebx
    sub     [brk_z], r12d
.no_dig:
    SHIFT_CALL structures_shift
    pop     r12
    pop     rbx
    pop     rbp
    ret

; game_unload_box(edi x0, esi z0, edx x1, ecx z1): a column is going away (local cell box, inclusive).
; An open merchant or elder screen whose NPC stands in it closes first; then the mobs, drops, primed
; TNT and fires inside the box are removed.
game_unload_box:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     eax, [app_state]
    cmp     eax, ST_TRADE
    je      .talking
    cmp     eax, ST_DIALOG
    jne     .remove
.talking:
    mov     eax, [game_open_npc]
    cmp     eax, MAX_MOBS
    jae     .remove
    imul    eax, eax, MOB_size
    lea     rcx, [mobs]
    movss   xmm0, [rcx + rax + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si edx, xmm0
    movss   xmm0, [rcx + rax + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    cmp     edx, ebx
    jl      .remove
    cmp     edx, r13d
    jg      .remove
    cmp     eax, r12d
    jl      .remove
    cmp     eax, r14d
    jg      .remove
    mov     edi, ST_PLAYING             ; the NPC goes with the column: back to the game
    call    app_goto
.remove:
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r14d
    call    mobs_remove_box
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r14d
    call    drops_remove_box
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r14d
    call    tnt_remove_box
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r14d
    call    fire_remove_box
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; game_on_area_ready() -> eax 1 when the area around the player must be waited for again
; The columns around the player are lit and meshed: settle what the entry into the world was waiting
; for. A respawn at a bed asks sleep_place_at_bed (a bed that is gone sends the player to the world
; spawn, which is another area: eax = 1); a new world or a respawn at the spawn stands the player on
; the surface; a new world is populated. The site cache is rebuilt.
game_on_area_ready:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    test    dword [pending_respawn], 2
    jz      .ground
    call    sleep_place_at_bed
    test    eax, eax
    jnz     .placed
    call    respawn_at_target           ; sleep_place_at_bed cleared the bed: now the world spawn
    mov     eax, 1
    jmp     .ret
.placed:
    mov     dword [pending_respawn], 0
.ground:
    mov     eax, [pending_new]
    or      eax, [pending_respawn]
    jz      .done
    movss   xmm0, [player + BODY.x]
    call    floor_i
    mov     ebx, eax
    movss   xmm0, [player + BODY.z]
    call    floor_i
    mov     esi, eax
    mov     edi, ebx
    call    world_top_y
    inc     eax                         ; the cell above the surface
    cvtsi2ss xmm0, eax
    movss   [player + BODY.y], xmm0
    cmp     dword [pending_new], 0
    je      .done
    call    mobs_populate
.done:
    mov     dword [pending_new], 0
    mov     dword [pending_respawn], 0
    call    structures_refresh
    call    note_region
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; player_region() -> eax rx, edx rz: the player's 512 x 512 block region (absolute)
player_region:
    sub     rsp, 8
    movss   xmm0, [player + BODY.x]
    call    floor_i
    add     eax, [world_origin_x]
    sar     eax, 9
    mov     [rsp], eax
    movss   xmm0, [player + BODY.z]
    call    floor_i
    add     eax, [world_origin_z]
    sar     eax, 9
    mov     edx, eax
    mov     eax, [rsp]
    add     rsp, 8
    ret

; note_region(): remember the player's region as the one the site cache was built for
note_region:
    sub     rsp, 8
    call    player_region
    mov     [region_x], eax
    mov     [region_z], edx
    add     rsp, 8
    ret

; check_region(): rebuild the site cache when the player has crossed into another region
check_region:
    sub     rsp, 8
    call    player_region
    cmp     eax, [region_x]
    jne     .changed
    cmp     edx, [region_z]
    je      .ret
.changed:
    mov     [region_x], eax
    mov     [region_z], edx
    call    structures_refresh
.ret:
    add     rsp, 8
    ret

; repeat_fire(edi held, esi pressed, rdx float* timer, xmm0 dt) -> eax fire
; Fires on press, then every 0.25 s while held; the timer is zeroed on release.
repeat_fire:
    test    esi, esi
    jz      .not_pressed
    movss   xmm1, [repeat_dt]
    movss   [rdx], xmm1
    mov     eax, 1
    ret
.not_pressed:
    test    edi, edi
    jz      .released
    movss   xmm1, [rdx]
    subss   xmm1, xmm0
    xorps   xmm2, xmm2
    xor     eax, eax
    comiss  xmm1, xmm2
    ja      .store
    addss   xmm1, [repeat_dt]
    mov     eax, 1
.store:
    movss   [rdx], xmm1
    ret
.released:
    mov     dword [rdx], 0
    xor     eax, eax
    ret

; play_block_sound(edi block, rsi table, xmm0 vol): table[block] sound, nothing for AIR
play_block_sound:
    test    edi, edi
    jz      .ret
    movzx   edi, byte [rsi + rdi]
    jmp     audio_play
.ret:
    ret

; target_block() -> eax id of game_target's block
target_block:
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    jmp     world_get

; remove_target_block(): game_target's block becomes AIR; a furnace or chest spills, a door
; loses its other half and whatever hung on the block (torches, ladders) pops off
remove_target_block:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    target_block
    mov     ebx, eax                    ; the id that goes away
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    call    cont_block_removed
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    mov     ecx, AIR
    call    world_set
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    mov     ecx, ebx
    call    block_removed
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; held_id() -> eax id of the selected hotbar stack
held_id:
    mov     eax, [inv_sel]
    movzx   eax, byte [inv + INVENTORY.slots + rax*4 + ITEMSTACK.id]
    ret

; try_potion() -> eax 1 when this frame's RMB press drank the held potion: a health potion
; heals 4 hearts, a mana potion restores 50 mana; survival uses it up
try_potion:
    push    rbp
    mov     rbp, rsp
    xor     eax, eax
    cmp     dword [frame_input + FRAMEINPUT.rmb_pressed], 0
    je      .ret
    call    held_id
    cmp     eax, HEALTH_POTION
    je      .health
    cmp     eax, MANA_POTION
    jne     .none
    call    combat_max_mana
    movaps  xmm2, xmm0                  ; a mana potion restores max(50, half the maximum)
    mulss   xmm2, [f_half]
    maxss   xmm2, [mana_potion]
    movss   xmm1, [combat_mana]
    addss   xmm1, xmm2
    minss   xmm1, xmm0
    movss   [combat_mana], xmm1
    jmp     .drunk
.health:
    mov     eax, [surv_max_health]      ; a health potion heals max(8, 3/10 of the maximum)
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    lea     edi, [rax + rax*2]
    mov     eax, 8
    cmp     edi, eax
    cmovl   edi, eax
    call    combat_heal
.drunk:
    mov     edi, SND_DRINK
    movss   xmm0, [vol_drink]
    call    audio_play
    call    hand_swing
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .done
    mov     edi, 1
    call    inv_consume_held
.done:
    mov     eax, 1
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    pop     rbp
    ret

; want_guard(edi targeted mob or -1) -> eax 1 when the player raises the guard this frame:
; RMB held with a sword, axe or dagger, unless this frame's RMB press talks to a merchant or
; elder or uses a block (crafting table, furnace, chest, door, trapdoor)
want_guard:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    xor     eax, eax
    cmp     dword [frame_input + FRAMEINPUT.rmb_held], 0
    je      .ret
    call    held_id
    movzx   eax, byte [item_tool + rax]
    cmp     eax, TOOL_SWORD
    je      .melee
    cmp     eax, TOOL_AXE
    je      .melee
    cmp     eax, TOOL_DAGGER
    je      .melee
    cmp     eax, TOOL_HAMMER
    je      .melee
    cmp     eax, TOOL_SPEAR
    jne     .no
.melee:
    mov     eax, 1
    cmp     dword [frame_input + FRAMEINPUT.rmb_pressed], 0
    je      .ret
    test    ebx, ebx
    js      .block
    imul    ecx, ebx, MOB_size
    lea     rdx, [mobs]
    mov     ecx, [rdx + rcx + MOB.type]
    cmp     ecx, MOB_FOLK
    je      .no
.block:
    cmp     dword [boat_hit], 0
    jl      .at_block
    cmp     dword [boat_riding], 0
    je      .no                         ; the press boards the boat: no guard
.at_block:
    cmp     dword [game_has_target], 0
    je      .ret
    call    target_block
    mov     edi, eax
    call    block_is_usable
    test    eax, eax
    jnz     .no
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; damage_held_tool(edi amount_if_blade, esi amount_otherwise): wear the held tool; swords and
; daggers take the first amount
damage_held_tool:
    mov     eax, [inv_sel]
    movzx   eax, byte [inv + INVENTORY.slots + rax*4 + ITEMSTACK.id]
    movzx   eax, byte [item_tool + rax]
    test    eax, eax
    jz      .ret
    cmp     eax, TOOL_SWORD
    je      .blade
    cmp     eax, TOOL_DAGGER
    je      .blade
    mov     edi, esi
.blade:
    jmp     inv_damage_held
.ret:
    ret

; unit_h(rsi dir float[3]) -> xmm0, xmm1 the horizontal part (x, z) of a direction scaled to length
; 1 ((0, 0) for a vertical one)
unit_h:
    movss   xmm0, [rsi]
    movss   xmm1, [rsi + 8]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2
    xorps   xmm3, xmm3
    comiss  xmm2, xmm3
    jbe     .ret
    divss   xmm0, xmm2
    divss   xmm1, xmm2
.ret:
    ret

; heavy_track(edi mob under the crosshair or -1, rsi dir float[3], xmm0 dt): the button logic of the
; heavy attack, once per frame while the melee branch of game_frame runs. game_heavy_s counts the
; seconds the left button has been held since a press made with a melee weapon (item_gear GK_MELEE)
; in hand and the guard down, on a mob or where no block is in reach; -1 when idle. Releasing after
; 0.5 s or more lands a heavy blow on the mob (combat_heavy; a landed one wears the tool and tires
; like a light one) or just swings at the air. Releasing sooner, a raised guard, another item in
; hand or an open screen cancel it.
; rbx = mob. Frame: [rsp] unit dir x, [rsp+4] z, [rsp+8] dt
heavy_track:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    mov     ebx, edi
    movss   [rsp + 8], xmm0
    call    unit_h
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    call    held_id
    lea     rcx, [item_gear]
    cmp     byte [rcx + rax], GK_MELEE
    jne     .cancel
    cmp     dword [input_captured], 1
    jne     .cancel
    cmp     dword [game_open_screen], 0
    jne     .cancel
    movss   xmm0, [game_heavy_s]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jae     .charging
    cmp     dword [frame_input + FRAMEINPUT.lmb_pressed], 0
    je      .out                        ; idle
    cmp     dword [combat_guard_t], 0
    jge     .out
    test    ebx, ebx
    jns     .start
    cmp     dword [game_has_target], 0
    jne     .out                        ; a block is in reach: the click digs
.start:
    mov     dword [game_heavy_s], 0
    jmp     .out
.charging:
    cmp     dword [frame_input + FRAMEINPUT.lmb_held], 0
    je      .release
    cmp     dword [combat_guard_t], 0
    jge     .cancel
    addss   xmm0, [rsp + 8]
    movss   [game_heavy_s], xmm0
    jmp     .out
.release:
    comiss  xmm0, [heavy_time]
    jb      .cancel                     ; too soon: the light attack was all of it
    mov     dword [game_heavy_s], __float32__(-1.0)
    test    ebx, ebx
    js      .air
    mov     edi, ebx
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    combat_heavy
    test    eax, eax
    jz      .out
    call    hand_swing                  ; the drawn-back weapon comes down
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .out
    mov     edi, 1
    mov     esi, 2
    call    damage_held_tool
    movss   xmm0, [exh_attack]
    call    survival_exhaust
    jmp     .out
.air:
    call    hand_swing
    jmp     .out
.cancel:
    mov     dword [game_heavy_s], __float32__(-1.0)
.out:
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; Frame layout of game_frame
%define F_EYE    0                      ; float[3]
%define F_DIR    12                     ; float[3]
%define F_DT     24                     ; float
%define F_MOB    28                     ; int: targeted mob or -1
%define F_HIT    32                     ; RAYHIT scratch (24)
%define F_BOAT   56                     ; int: the boat under the crosshair (nearer than any block) or -1
%define F_TBLK   60                     ; float: distance to the block hit
%define F_TMOB   64                     ; float: distance to the mob hit
%define F_TBOAT  68                     ; float: distance to the boat hit
%define F_SCR    96                     ; scratch: screen to open / bow power
%define F_FORCE  112                    ; int: 1 when Deadeye forces the arrow's crit
%define F_SIZE   128

; bow_barrage(rdi game_frame's frame): Barrage. Two more arrows fly 6 degrees to either side of a
; shot just fired from that frame (same eye, direction, power and flags): 60 % of its damage, at
; least 1; they use no ammo and cannot be picked up.
; r12d = their damage. Frame: [rsp] side (+1 / -1), [rsp+4] arrows left
bow_barrage:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdi
    cvtsi2ss xmm0, dword [rbx + F_SCR + 4]
    mulss   xmm0, [barrage_dmg]
    cvtss2si r12d, xmm0
    mov     eax, 1
    cmp     r12d, eax
    cmovl   r12d, eax
    mov     dword [rsp], __float32__(1.0)
    mov     dword [rsp + 4], 2
.arrow:
    movss   xmm0, [rbx + F_DIR]         ; the direction turned about the vertical by 6 degrees
    movss   xmm1, [rbx + F_DIR + 8]
    movss   xmm2, [cos6]
    movss   xmm3, [sin6]
    mulss   xmm3, [rsp]                 ; +- sin 6
    movaps  xmm4, xmm0
    mulss   xmm4, xmm2
    movaps  xmm5, xmm1
    mulss   xmm5, xmm3
    addss   xmm4, xmm5                  ; x' = x cos + z sin
    mulss   xmm0, xmm3
    mulss   xmm1, xmm2
    subss   xmm1, xmm0                  ; z' = z cos - x sin
    movss   xmm6, [rbx + F_SCR]
    mulss   xmm6, [bow_speed]           ; power * speed
    movaps  xmm3, xmm4
    mulss   xmm3, xmm6                  ; vx
    movss   xmm4, [rbx + F_DIR + 4]
    mulss   xmm4, xmm6                  ; vy: the pitch stays
    movaps  xmm5, xmm1
    mulss   xmm5, xmm6                  ; vz
    movss   xmm7, [bow_offset]
    movss   xmm0, [rbx + F_DIR]
    mulss   xmm0, xmm7
    addss   xmm0, [rbx + F_EYE]
    movss   xmm1, [rbx + F_DIR + 4]
    mulss   xmm1, xmm7
    addss   xmm1, [rbx + F_EYE + 4]
    movss   xmm2, [rbx + F_DIR + 8]
    mulss   xmm2, xmm7
    addss   xmm2, [rbx + F_EYE + 8]
    xor     edi, edi                    ; owner: the player
    mov     esi, r12d
    xor     edx, edx                    ; nothing to pick up
    mov     ecx, PROJ_ARROW
    mov     r8d, [rbx + F_SCR + 8]
    call    arrows_spawn
    movss   xmm0, [rsp]
    xorps   xmm1, xmm1
    subss   xmm1, xmm0
    movss   [rsp], xmm1                 ; the other side
    dec     dword [rsp + 4]
    jnz     .arrow
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; game_frame(xmm0 float dt)
game_frame:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, F_SIZE
    movss   [rsp + F_DT], xmm0

    ; 1. hotbar slot: number key, then wheel (wheel up = previous slot)
    mov     eax, [frame_input + FRAMEINPUT.slot]
    test    eax, eax
    js      .no_slot
    mov     [inv_sel], eax
.no_slot:
    mov     eax, [inv_sel]
    sub     eax, [frame_input + FRAMEINPUT.scroll]
    cdq
    mov     ecx, HOTBAR_SLOTS
    idiv    ecx
    test    edx, edx
    jns     .sel_pos
    add     edx, HOTBAR_SLOTS
.sel_pos:
    mov     [inv_sel], edx

    ; 2. fly toggle (creative only)
    cmp     dword [frame_input + FRAMEINPUT.toggle_fly], 0
    je      .no_fly
    cmp     dword [game_mode], MODE_CREATIVE
    jne     .no_fly
    xor     dword [player + BODY.flying], 1
    mov     dword [player + BODY.vy], 0
.no_fly:

    ; 3. look, scaled by sensitivity (and down while aiming), optionally inverted
    cvtsi2ss xmm2, dword [settings + SETTINGS.sensitivity]
    divss   xmm2, [f_hundred]
    movss   xmm3, [game_aim]
    mulss   xmm3, [aim_look]
    movss   xmm4, [f_one]
    subss   xmm4, xmm3
    mulss   xmm2, xmm4                  ; x (1 - 0.4 aim)
    movss   xmm0, [frame_input + FRAMEINPUT.look_dx]
    mulss   xmm0, xmm2
    movss   xmm1, [frame_input + FRAMEINPUT.look_dy]
    mulss   xmm1, xmm2
    cmp     dword [settings + SETTINGS.invert_mouse], 0
    je      .look
    xorps   xmm2, xmm2
    subss   xmm2, xmm1
    movaps  xmm1, xmm2
.look:
    call    player_look

    ; 4. fixed 1/60 s steps, at most 5 per frame; a hit-stop freezes the simulation
    movss   xmm0, [combat_hitstop]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .no_hitstop
    subss   xmm0, [rsp + F_DT]
    maxss   xmm0, xmm1
    movss   [combat_hitstop], xmm0
    jmp     .steps_done
.no_hitstop:
    movss   xmm0, [step_accum]
    addss   xmm0, [rsp + F_DT]
    movss   [step_accum], xmm0
    xor     ebx, ebx
.step:
    movss   xmm0, [step_accum]
    comiss  xmm0, [step_dt]
    jb      .steps_done
    cmp     ebx, 5
    jae     .steps_capped
    call    sim_step
    movss   xmm0, [step_accum]
    subss   xmm0, [step_dt]
    movss   [step_accum], xmm0
    inc     ebx
    jmp     .step
.steps_capped:
    mov     dword [step_accum], 0
.steps_done:

    ; 5. targets: block, then a mob nearer than any block
    lea     rdi, [rsp + F_EYE]
    call    player_eye
    lea     rdi, [rsp + F_DIR]
    call    player_forward
    movss   xmm0, [reach_crea]
    cmp     dword [game_mode], MODE_CREATIVE
    je      .reach
    movss   xmm0, [reach_surv]
.reach:
    lea     rdi, [rsp + F_EYE]
    lea     rsi, [rsp + F_DIR]
    lea     rdx, [game_target]
    call    raycast
    mov     [game_has_target], eax
    movss   [rsp + F_TBLK], xmm0        ; how far the block hit is (the reach when there is none)
    call    held_id                     ; a spear reaches 4.5 blocks, everything else 3.5
    movss   xmm0, [mob_reach]
    lea     rcx, [item_tool]
    cmp     byte [rcx + rax], TOOL_SPEAR
    jne     .mob_ray
    movss   xmm0, [mob_reach_spear]
.mob_ray:
    lea     rdi, [rsp + F_EYE]
    lea     rsi, [rsp + F_DIR]
    call    mobs_raycast
    mov     [rsp + F_MOB], eax
    movss   [rsp + F_TMOB], xmm0
    test    eax, eax
    js      .mob_done
    lea     rdi, [rsp + F_EYE]          ; a block in front of the mob hides it
    lea     rsi, [rsp + F_DIR]
    lea     rdx, [rsp + F_HIT]
    call    raycast
    test    eax, eax
    jz      .mob_done
    mov     dword [rsp + F_MOB], -1
.mob_done:
    lea     rdi, [rsp + F_EYE]          ; a boat in reach, unless a block is in front of it
    lea     rsi, [rsp + F_DIR]
    movss   xmm0, [reach_surv]
    call    boats_raycast
    mov     [rsp + F_BOAT], eax
    movss   [rsp + F_TBOAT], xmm0
    test    eax, eax
    js      .boat_done
    cmp     dword [game_has_target], 0
    je      .boat_done
    comiss  xmm0, [rsp + F_TBLK]
    jb      .boat_done                  ; nearer than the block
    mov     dword [rsp + F_BOAT], -1
.boat_done:
    mov     eax, [rsp + F_BOAT]
    mov     [boat_hit], eax

    ; 5b. combat input while playing: guard (RMB with a melee weapon), dodge, abilities
    cmp     dword [input_captured], 1
    jne     .no_combat
    cmp     dword [game_open_screen], 0
    jne     .no_combat
    mov     edi, [rsp + F_MOB]
    call    want_guard
    mov     edi, eax
    call    combat_set_guard
    cmp     dword [frame_input + FRAMEINPUT.dodge], 0
    je      .no_dodge
    lea     rdi, [frame_input + FRAMEINPUT.move]
    call    combat_dodge
.no_dodge:
    xor     ebx, ebx
.ability:
    cmp     dword [frame_input + FRAMEINPUT.ability + rbx*4], 0
    je      .next_ability
    mov     edi, ebx
    lea     rsi, [rsp + F_EYE]
    lea     rdx, [rsp + F_DIR]
    call    abilities_use
.next_ability:
    inc     ebx
    cmp     ebx, 4
    jb      .ability
    jmp     .combat_done
.no_combat:
    xor     edi, edi
    call    combat_set_guard
.combat_done:

    ; 6. buttons, in ownership order: a folk (talk), a held firearm (section 12), a mage's
    ; staff (bolts), then melee on the targeted mob. The first three never punch, dig, use or
    ; place.
    mov     eax, [rsp + F_MOB]
    test    eax, eax
    js      .not_npc
    imul    eax, eax, MOB_size
    lea     rcx, [mobs]
    cmp     dword [rcx + rax + MOB.type], MOB_FOLK
    jne     .not_npc
    mov     dword [game_heavy_s], __float32__(-1.0)     ; no heavy attack on folk
    mov     dword [game_break_progress], 0
    mov     dword [break_cooldown], 0
    mov     dword [brk_y], -1
    cmp     dword [frame_input + FRAMEINPUT.rmb_pressed], 0
    je      .pick
    mov     edi, [rsp + F_MOB]
    call    folk_interact
    test    eax, eax
    jz      .pick
    mov     [game_open_screen], eax
    mov     eax, [rsp + F_MOB]
    mov     [game_open_npc], eax
    jmp     .pick
.not_npc:
    call    held_id
    mov     edi, eax
    call    gun_index
    test    eax, eax
    js      .unarmed
    mov     dword [game_heavy_s], __float32__(-1.0)     ; ...nor with a firearm
    mov     dword [game_break_progress], 0
    mov     dword [break_cooldown], 0
    mov     dword [brk_y], -1
    jmp     .pick
.unarmed:
    call    held_id
    cmp     eax, STAFF
    je      .staff
    cmp     eax, ARCHMAGE_STAFF
    jne     .melee
.staff:
    call    rpg_class
    cmp     eax, CLASS_MAGE
    jne     .melee                      ; any other class swings the staff
    mov     dword [game_heavy_s], __float32__(-1.0)     ; ...nor with a mage's staff
    mov     dword [game_break_progress], 0
    mov     dword [break_cooldown], 0
    mov     dword [brk_y], -1
    cmp     dword [frame_input + FRAMEINPUT.lmb_held], 0
    je      .pick
    lea     rdi, [rsp + F_EYE]
    lea     rsi, [rsp + F_DIR]
    call    abilities_staff_bolt
    jmp     .pick
.melee:
    cmp     dword [frame_input + FRAMEINPUT.lmb_pressed], 0
    je      .no_boat_break              ; a click on a boat nearer than the block and mob hits
    mov     eax, [rsp + F_BOAT]         ; breaks it (not the one the player rides)
    test    eax, eax
    js      .no_boat_break
    lea     ecx, [rax + 1]
    cmp     ecx, [boat_riding]
    je      .no_boat_break
    cmp     dword [rsp + F_MOB], 0
    jl      .boat_first
    movss   xmm0, [rsp + F_TBOAT]
    comiss  xmm0, [rsp + F_TMOB]
    jae     .no_boat_break              ; the mob is nearer
.boat_first:
    mov     edi, eax
    call    boats_break
    call    hand_swing
    mov     dword [game_heavy_s], __float32__(-1.0)
    mov     dword [game_break_progress], 0
    mov     dword [brk_y], -1
    jmp     .place
.no_boat_break:
    mov     edi, [rsp + F_MOB]
    lea     rsi, [rsp + F_DIR]
    movss   xmm0, [rsp + F_DT]
    call    heavy_track                 ; holding the button for 0.5 s winds up a heavy attack
    cmp     dword [rsp + F_MOB], 0
    jl      .blocks
    mov     dword [game_break_progress], 0
    cmp     dword [frame_input + FRAMEINPUT.lmb_pressed], 0
    je      .place
    call    hand_swing
    lea     rsi, [rsp + F_DIR]
    call    unit_h                      ; the horizontal direction to the mob
    mov     edi, [rsp + F_MOB]
    call    combat_melee
    test    eax, eax
    jz      .place
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .place
    mov     edi, 1
    mov     esi, 2
    call    damage_held_tool
    movss   xmm0, [exh_attack]
    call    survival_exhaust
    jmp     .place

.blocks:
    cmp     dword [combat_guard_t], 0
    jge     .break_reset                ; a raised guard never digs
    cmp     dword [frame_input + FRAMEINPUT.lmb_pressed], 0
    je      .no_swing
    call    hand_swing                  ; a click swings even at thin air
.no_swing:
    movss   xmm0, [game_heavy_s]        ; winding up a heavy attack: no digging
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jae     .break_reset
    cmp     dword [game_mode], MODE_CREATIVE
    jne     .survival_break

    ; 7. creative: instant break, repeating every 0.25 s
    mov     dword [game_break_progress], 0
    mov     edi, [frame_input + FRAMEINPUT.lmb_held]
    mov     esi, [frame_input + FRAMEINPUT.lmb_pressed]
    lea     rdx, [break_timer]
    movss   xmm0, [rsp + F_DT]
    call    repeat_fire
    test    eax, eax
    jz      .place
    cmp     dword [game_has_target], 0
    je      .place
    call    target_block
    cmp     eax, BEDROCK
    je      .place
    mov     r12d, eax
    call    remove_target_block
    mov     edi, r12d
    lea     rsi, [block_dig_sound]
    movss   xmm0, [f_one]
    call    play_block_sound
    jmp     .place

    ; 8. survival: timed breaking with the held tool
.survival_break:
    cmp     dword [frame_input + FRAMEINPUT.lmb_held], 0
    je      .break_reset
    cmp     dword [game_has_target], 0
    je      .break_reset
    call    target_block
    mov     r12d, eax
    xorps   xmm0, xmm0
    comiss  xmm0, [block_hardness + r12*4]
    ja      .break_reset                ; unbreakable
    mov     eax, [game_target + RAYHIT.bx]
    cmp     eax, [brk_x]
    jne     .new_target
    mov     eax, [game_target + RAYHIT.by]
    cmp     eax, [brk_y]
    jne     .new_target
    mov     eax, [game_target + RAYHIT.bz]
    cmp     eax, [brk_z]
    je      .same_target
.new_target:
    mov     eax, [game_target + RAYHIT.bx]
    mov     [brk_x], eax
    mov     eax, [game_target + RAYHIT.by]
    mov     [brk_y], eax
    mov     eax, [game_target + RAYHIT.bz]
    mov     [brk_z], eax
    mov     dword [game_break_progress], 0
    mov     dword [crack_timer], 0
.same_target:
    movss   xmm0, [break_cooldown]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .dig
    subss   xmm0, [rsp + F_DT]
    movss   [break_cooldown], xmm0
    jmp     .place
.dig:
    call    hand_swing                  ; keep swinging while digging
    call    held_id
    mov     edi, r12d
    mov     esi, eax
    call    item_break_time
    movss   xmm1, [f_one]               ; zero break time (TNT): broken at once, no dt/0
    xorps   xmm2, xmm2
    comiss  xmm0, xmm2
    jbe     .progress
    movss   xmm1, [rsp + F_DT]
    divss   xmm1, xmm0
    addss   xmm1, [game_break_progress]
.progress:
    movss   [game_break_progress], xmm1
    movss   xmm0, [crack_timer]
    subss   xmm0, [rsp + F_DT]
    movss   [crack_timer], xmm0
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    ja      .no_crack
    addss   xmm0, [repeat_dt]
    movss   [crack_timer], xmm0
    mov     edi, r12d
    lea     rsi, [block_step_sound]
    movss   xmm0, [vol_crack]
    call    play_block_sound
.no_crack:
    movss   xmm0, [game_break_progress]
    comiss  xmm0, [f_one]
    jb      .place
    ; broken: harvest, remove, wear the tool
    call    held_id
    mov     edi, r12d
    mov     esi, eax
    call    item_harvest_drop
    mov     ebx, eax
    test    eax, eax
    jz      .no_mined_xp
    mov     edi, r12d                   ; ore XP for a real harvest
    call    rpg_on_block_mined
.no_mined_xp:
    cmp     r12d, LEAVES
    je      .leaves
    cmp     r12d, PINE_LEAVES
    je      .leaves
    cmp     r12d, BIRCH_LEAVES
    jne     .not_leaves
.leaves:
    call    held_id
    cmp     byte [item_tool + rax], TOOL_AXE
    jne     .leaf_roll
    mov     ebx, r12d                   ; an axe takes the leaves themselves
    jmp     .drop_ready
.leaf_roll:
    call    rng_next
    test    eax, 15
    jnz     .drop_ready
    mov     ebx, APPLE
    jmp     .drop_ready
.not_leaves:
    cmp     r12d, GRAVEL
    jne     .drop_ready
    call    rng_next
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    test    edx, edx
    jnz     .drop_ready
    mov     ebx, FLINT
.drop_ready:
    call    remove_target_block
    mov     edi, r12d
    lea     rsi, [block_dig_sound]
    movss   xmm0, [f_one]
    call    play_block_sound
    test    ebx, ebx                    ; the harvest pops out of the block
    jz      .no_drop
    cvtsi2ss xmm0, dword [game_target + RAYHIT.bx]
    addss   xmm0, [f_half]
    cvtsi2ss xmm1, dword [game_target + RAYHIT.by]
    addss   xmm1, [f_quarter]
    cvtsi2ss xmm2, dword [game_target + RAYHIT.bz]
    addss   xmm2, [f_half]
    mov     edi, ebx
    mov     esi, 1
    xor     edx, edx
    call    drops_spawn
.no_drop:
    mov     edi, 2
    mov     esi, 1
    call    damage_held_tool
    movss   xmm0, [exh_break]
    call    survival_exhaust
    mov     dword [game_break_progress], 0
    mov     dword [break_cooldown], __float32__(0.25)
    mov     dword [brk_y], -1
    jmp     .place
.break_reset:
    mov     dword [game_break_progress], 0
    mov     dword [break_cooldown], 0
    mov     dword [brk_y], -1

    ; 9. place / use (not while guarding); potions are drunk with a press, target or not
.place:
    cmp     dword [combat_guard_t], 0
    jge     .pick
    mov     edi, [frame_input + FRAMEINPUT.rmb_held]
    mov     esi, [frame_input + FRAMEINPUT.rmb_pressed]
    lea     rdx, [place_timer]
    movss   xmm0, [rsp + F_DT]
    call    repeat_fire
    test    eax, eax
    jz      .pick
    cmp     dword [frame_input + FRAMEINPUT.rmb_pressed], 0
    je      .no_boat_click              ; a boat is boarded or put down by a fresh click only
    cmp     dword [boat_riding], 0      ; a boat in front (nearer than the block hit) is boarded,
    jne     .boat_item                  ; even with a boat in hand
    mov     eax, [rsp + F_BOAT]
    test    eax, eax
    js      .boat_item
    mov     edi, eax
    call    boats_mount
    jmp     .pick
.boat_item:
    call    held_id
    cmp     eax, BOAT
    jne     .no_boat_click
    lea     rdi, [rsp + F_EYE]
    lea     rsi, [rsp + F_DIR]
    call    boats_place
    test    eax, eax
    jz      .no_boat_click              ; no water to put it on: the click goes on as an ordinary use
    call    hand_swing
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .pick
    mov     edi, 1
    call    inv_consume_held
    jmp     .pick
.no_boat_click:
    cmp     dword [game_has_target], 0
    jne     .use
    call    try_potion
    jmp     .pick
.use:
    call    target_block
    mov     ebx, eax
    cmp     dword [frame_input + FRAMEINPUT.move + INPUT.down], 0
    jne     .not_use
    cmp     dword [frame_input + FRAMEINPUT.rmb_pressed], 0
    je      .not_use
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    call    block_use                   ; a door or trapdoor swings
    test    eax, eax
    jz      .not_door
    call    hand_swing
    jmp     .pick
.not_door:
    movzx   eax, byte [block_base + rbx]    ; a bed: the right click sleeps in it (a rider leaves his boat) or sets the respawn
    cmp     eax, BED
    jne     .not_bed
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    call    sleep_use_bed
    call    hand_swing
    jmp     .pick
.not_bed:
    cmp     ebx, CRAFTING_TABLE
    jne     .not_table
    mov     dword [game_open_screen], ST_CRAFTING
    jmp     .pick
.not_table:
    mov     r12d, CONT_FURNACE
    mov     dword [rsp + F_SCR], ST_FURNACE
    cmp     ebx, FURNACE
    je      .open_cont
    cmp     ebx, FURNACE_LIT
    je      .open_cont
    mov     r12d, CONT_CHEST
    mov     dword [rsp + F_SCR], ST_CHEST
    cmp     ebx, CHEST
    jne     .not_cont
.open_cont:
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    call    cont_at
    test    rax, rax
    jnz     .have_cont
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    mov     ecx, r12d
    call    cont_create
    test    rax, rax
    jz      .pick                       ; every container record is in use
.have_cont:
    mov     [game_open_cont], rax
    mov     eax, [rsp + F_SCR]
    mov     [game_open_screen], eax
    jmp     .pick
.not_cont:
    call    held_id
    cmp     eax, FLINT_AND_STEEL
    jne     .not_use
    cmp     ebx, TNT
    je      .light_tnt
    mov     edi, [game_target + RAYHIT.px] ; anything else: fire on the face struck
    mov     esi, [game_target + RAYHIT.py]
    mov     edx, [game_target + RAYHIT.pz]
    call    fire_place
    test    eax, eax
    jz      .pick
    mov     edi, SND_FUSE
    movss   xmm0, [f_half]
    call    audio_play
    jmp     .struck
.light_tnt:
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    mov     ecx, 80
    call    tnt_prime
    mov     edi, SND_FUSE
    cvtsi2ss xmm0, dword [game_target + RAYHIT.bx]
    addss   xmm0, [f_half]
    cvtsi2ss xmm1, dword [game_target + RAYHIT.by]
    addss   xmm1, [f_half]
    cvtsi2ss xmm2, dword [game_target + RAYHIT.bz]
    addss   xmm2, [f_half]
    movss   xmm3, [f_one]
    call    audio_play_at
.struck:
    call    hand_swing
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .pick
    mov     edi, 1
    call    inv_damage_held
    jmp     .pick
.not_use:
    call    try_potion
    test    eax, eax
    jnz     .pick
    call    held_id
    mov     r12d, eax
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .not_food
    cmp     byte [item_food + r12], 0
    jne     .pick                       ; eating runs per step
.not_food:
    test    r12d, r12d
    jz      .pick
    mov     edi, r12d
    lea     rsi, [game_target]
    call    place_block                 ; checks the item and the cell, picks the variant, plays the sound
    test    eax, eax
    jz      .pick
    call    hand_swing
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .pick
    mov     edi, 1
    call    inv_consume_held

    ; 10. pick block
.pick:
    cmp     dword [frame_input + FRAMEINPUT.mmb_pressed], 0
    je      .bow
    cmp     dword [game_has_target], 0
    je      .bow
    call    target_block
    movzx   eax, byte [block_base + rax] ; the item form of the block: a lit furnace gives a furnace
    test    eax, eax
    jz      .bow                        ; flames have no item
.pick_id:
    cmp     dword [game_mode], MODE_CREATIVE
    jne     .pick_survival
    mov     ecx, [inv_sel]
    lea     rdx, [inv + INVENTORY.slots + rcx*4]
    mov     [rdx + ITEMSTACK.id], al
    mov     byte [rdx + ITEMSTACK.count], 1
    mov     word [rdx + ITEMSTACK.dmg], 0
    jmp     .bow
.pick_survival:
    mov     edi, eax
    call    inv_find_hotbar
    test    eax, eax
    js      .bow
    mov     [inv_sel], eax

    ; 11. bow: draw while RMB is held, shoot on release. The Celestial Bow needs no arrows.
.bow:
    call    held_id
    mov     [rsp + F_SCR + 12], eax
    cmp     eax, CELESTIAL_BOW
    je      .is_bow
    cmp     eax, BOW
    jne     .bow_reset
.is_bow:
    movss   xmm0, [game_bow_charge]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    ja      .bow_drawing
    cmp     dword [frame_input + FRAMEINPUT.rmb_pressed], 0
    je      .gun
    cmp     dword [game_open_screen], 0
    jne     .gun
    cmp     dword [game_mode], MODE_CREATIVE
    je      .bow_draw
    cmp     dword [rsp + F_SCR + 12], CELESTIAL_BOW
    je      .bow_draw
    mov     edi, ARROW
    call    inv_count
    test    eax, eax
    jz      .gun
.bow_draw:
    movss   xmm0, [bow_start]
    movss   [game_bow_charge], xmm0
    jmp     .gun
.bow_drawing:
    cmp     dword [frame_input + FRAMEINPUT.rmb_held], 0
    je      .bow_release
    movss   xmm1, [rsp + F_DT]          ; the draw speeds up with ATTACK_SPEED, but not with Deadeye
    test    dword [rpg_keystones], 1 << KS_DEADEYE
    jnz     .draw_step
    cvtsi2ss xmm2, dword [rpg_stats + STAT_ATTACK_SPEED * 4]
    divss   xmm2, [f_hundred]
    addss   xmm2, [f_one]
    mulss   xmm1, xmm2
.draw_step:
    addss   xmm0, xmm1
    movss   [game_bow_charge], xmm0
    jmp     .gun
.bow_release:
    cmp     dword [input_captured], 1
    jne     .bow_reset                  ; released inside a screen: no shot
    movaps  xmm2, xmm0                  ; the draw as held, for Deadeye
    minss   xmm0, [f_one]               ; f
    movaps  xmm1, xmm0
    mulss   xmm1, xmm0
    addss   xmm1, xmm0
    addss   xmm1, xmm0
    divss   xmm1, [f_three]             ; power = (f^2 + 2f) / 3
    comiss  xmm1, [bow_min]
    jb      .bow_reset
    movss   [rsp + F_SCR], xmm1
    xor     eax, eax                    ; Deadeye: a fully drawn shot always crits
    test    dword [rpg_keystones], 1 << KS_DEADEYE
    jz      .force_set
    comiss  xmm2, [f_one]
    setae   al
.force_set:
    mov     [rsp + F_FORCE], eax
    ; damage = 1 + round(8 power), x3/2 (integer) for the Celestial Bow; the damage pipeline applies
    ; RANGED_DMG and the crit when the arrow lands
    mulss   xmm1, [f_eight]
    cvtss2si eax, xmm1
    inc     eax
    cmp     dword [rsp + F_SCR + 12], CELESTIAL_BOW
    jne     .bow_plain
    lea     eax, [rax + rax*2]
    shr     eax, 1
.bow_plain:
    mov     [rsp + F_SCR + 4], eax
    mov     edi, [rsp + F_FORCE]
    call    combat_crit_roll            ; forced by Deadeye, else rolled
    mov     ecx, AF_ATTACK              ; a weapon attack, not a skill
    test    eax, eax
    jz      .flags_set
    or      ecx, AF_CRIT
.flags_set:
    mov     [rsp + F_SCR + 8], ecx
.bow_fire:
    ; survival: the arrow is used up unless the bow is celestial or Quiver saves it; only a
    ; used-up arrow can be picked up again
    xor     ebx, ebx
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .bow_consumed
    cmp     dword [rsp + F_SCR + 12], CELESTIAL_BOW
    je      .bow_consumed
    call    rng_next
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    mov     ebx, edx
    mov     edi, STAT_ARROW_SAVE
    call    rpg_stat
    cmp     ebx, eax
    setge   bl
    movzx   ebx, bl
.bow_consumed:
    mov     esi, [rsp + F_SCR + 4]      ; the damage before the pipeline
    mov     edx, ebx                    ; pickup
    movss   xmm6, [rsp + F_SCR]
    mulss   xmm6, [bow_speed]
    movss   xmm3, [rsp + F_DIR]
    movss   xmm4, [rsp + F_DIR + 4]
    movss   xmm5, [rsp + F_DIR + 8]
    movss   xmm7, [bow_offset]
    movaps  xmm0, xmm3
    mulss   xmm0, xmm7
    addss   xmm0, [rsp + F_EYE]
    movaps  xmm1, xmm4
    mulss   xmm1, xmm7
    addss   xmm1, [rsp + F_EYE + 4]
    movaps  xmm2, xmm5
    mulss   xmm2, xmm7
    addss   xmm2, [rsp + F_EYE + 8]
    mulss   xmm3, xmm6
    mulss   xmm4, xmm6
    mulss   xmm5, xmm6
    xor     edi, edi                    ; owner: player
    mov     ecx, PROJ_ARROW
    mov     r8d, [rsp + F_SCR + 8]
    call    arrows_spawn
    test    dword [rpg_keystones], 1 << KS_BARRAGE
    jz      .bow_ammo
    mov     rdi, rsp
    call    bow_barrage                 ; Barrage: two more arrows, 6 degrees to either side
.bow_ammo:
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .bow_sound
    test    ebx, ebx
    jz      .bow_sound
    mov     edi, ARROW
    call    inv_remove_one
.bow_sound:
    mov     edi, SND_BOW
    movss   xmm0, [vol_bow]
    call    audio_play
.bow_reset:
    mov     dword [game_bow_charge], 0

.gun:
    ; 12. firearm: RMB aims down the sights (game_aim eases towards 1), LMB fires (held LMB
    ; keeps an automatic firing), R reloads. Aiming tightens the spread.
    call    held_id
    mov     ebx, eax
    mov     edi, eax
    call    gun_index
    xor     r12d, r12d                  ; 1 = armed and in control this frame
    test    eax, eax
    js      .aim
    cmp     dword [game_open_screen], 0
    jne     .aim
    cmp     dword [input_captured], 1
    jne     .aim
    mov     r12d, 1
.aim:
    xorps   xmm1, xmm1                  ; aim target
    test    r12d, r12d
    jz      .ease
    cmp     dword [frame_input + FRAMEINPUT.rmb_held], 0
    je      .ease
    movss   xmm1, [f_one]
.ease:
    movss   xmm2, [rsp + F_DT]
    mulss   xmm2, [aim_rate]
    minss   xmm2, [f_one]               ; min(1, 12 dt)
    subss   xmm1, [game_aim]
    mulss   xmm1, xmm2
    addss   xmm1, [game_aim]
    movss   [game_aim], xmm1
    test    r12d, r12d
    jz      .ret
    cmp     dword [frame_input + FRAMEINPUT.reload], 0
    je      .trigger
    call    gun_reload_start
.trigger:
    cmp     dword [frame_input + FRAMEINPUT.lmb_pressed], 0
    jne     .fire
    cmp     dword [frame_input + FRAMEINPUT.lmb_held], 0
    je      .ret
    mov     edi, ebx
    call    gun_automatic
    test    eax, eax
    jz      .ret
.fire:
    movss   xmm0, [game_aim]
    mulss   xmm0, [aim_spread]
    movss   xmm1, [f_one]
    subss   xmm1, xmm0
    movaps  xmm0, xmm1                  ; spread scale 1 - 0.75 aim
    lea     rdi, [rsp + F_EYE]
    lea     rsi, [rsp + F_DIR]
    call    gun_fire
.ret:
    add     rsp, F_SIZE
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sim_step(): one fixed step of player physics (or of the boat he rides), survival, footsteps, the
; other boats, mobs and time
sim_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 56                     ; [rsp] INPUT copy, [rsp+20] was_on_ground,
                                        ; [rsp+24] x0, [rsp+28] z0, [rsp+32] dist,
                                        ; [rsp+36] landed fall distance, [rsp+40] sprinting
                                        ; (drains stamina), [rsp+44] 1 when the step began in a boat
    call    rpg_recompute               ; the character first: gear, ranks and attributes may have changed
    lea     rsi, [frame_input + FRAMEINPUT.move]
    mov     rdi, rsp
    mov     ecx, INPUT_size
    rep     movsb
    cmp     dword [sleep_active], 0     ; asleep: moving, jumping or sneaking wakes the player up,
    je      .awake                      ; otherwise nothing moves
    mov     eax, [rsp + INPUT.fwd]
    or      eax, [rsp + INPUT.strafe]
    or      eax, [rsp + INPUT.jump]
    or      eax, [rsp + INPUT.down]
    jnz     .wake
    mov     dword [rsp + INPUT.sprint], 0
    jmp     .awake
.wake:
    call    sleep_cancel
.awake:
    xor     eax, eax                    ; in a boat the boat does the moving: no sprinting
    cmp     dword [boat_riding], 0
    setne   al
    mov     [rsp + 44], eax
    test    eax, eax
    jz      .afoot
    mov     dword [rsp + INPUT.sprint], 0
.afoot:
    call    survival_can_sprint
    test    eax, eax
    jnz     .sprint_ok
    mov     dword [rsp + INPUT.sprint], 0
.sprint_ok:
    ; survival: sprinting needs stamina and drains it while running forward on foot
    mov     dword [rsp + 40], 0
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .speed
    movss   xmm0, [combat_stamina]
    comiss  xmm0, [f_one]
    jae     .stamina_ok
    mov     dword [rsp + INPUT.sprint], 0
.stamina_ok:
    cmp     dword [rsp + INPUT.sprint], 0
    je      .speed
    cmp     dword [rsp + INPUT.fwd], 0
    jle     .speed
    cmp     dword [player + BODY.flying], 0
    jne     .speed
    mov     dword [rsp + 40], 1
.speed:
    call    combat_speed_mult           ; skills, guard, whirlwind and blade dance
    mulss   xmm0, [walk_speed]
    movss   [player + BODY.speed], xmm0
    mov     eax, [player + BODY.on_ground]
    mov     [rsp + 20], eax
    mov     eax, [player + BODY.x]
    mov     [rsp + 24], eax
    mov     eax, [player + BODY.z]
    mov     [rsp + 28], eax
    cmp     dword [rsp + 44], 0
    jne     .ride
    lea     rdi, [player]
    mov     rsi, rsp
    call    body_step
    jmp     .stepped
.ride:
    mov     rdi, rsp
    call    boats_step                  ; the boat sails on and carries the player with it
    xorps   xmm0, xmm0
.stepped:
    movss   [rsp + 36], xmm0            ; landed fall distance
    movss   xmm1, [player + BODY.x]
    subss   xmm1, [rsp + 24]
    mulss   xmm1, xmm1
    movss   xmm2, [player + BODY.z]
    subss   xmm2, [rsp + 28]
    mulss   xmm2, xmm2
    addss   xmm1, xmm2
    sqrtss  xmm1, xmm1
    cmp     dword [rsp + 44], 0
    je      .walked
    xorps   xmm1, xmm1                  ; carried by a boat: no exhaustion, no footsteps
.walked:
    movss   [rsp + 32], xmm1
    call    game_rebase                 ; 1024 blocks from the origin on an axis: move the origin
    ; jumped = was_on_ground && jump && !flying && not carried by a boat
    xor     ebx, ebx
    cmp     dword [rsp + 44], 0
    jne     .jump_done
    cmp     dword [rsp + 20], 0
    je      .jump_done
    cmp     dword [rsp + INPUT.jump], 0
    je      .jump_done
    cmp     dword [player + BODY.flying], 0
    jne     .jump_done
    mov     ebx, 1
.jump_done:
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .footsteps
    movss   xmm0, [rsp + 36]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .no_land
    call    survival_land
.no_land:
    mov     rdi, rsp
    movss   xmm0, [rsp + 32]
    mov     esi, ebx
    call    survival_step
    mov     edi, [frame_input + FRAMEINPUT.rmb_held]
    call    survival_eat_step
.footsteps:
    cmp     dword [player + BODY.flying], 0
    jne     .mobs
    cmp     dword [player + BODY.on_ground], 0
    je      .mobs
    movss   xmm0, [rsp + 32]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .mobs
    addss   xmm0, [step_dist]
    movss   [step_dist], xmm0
    comiss  xmm0, [f_step_len]
    jb      .mobs
    mov     dword [step_dist], 0
    movss   xmm0, [player + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    movss   xmm0, [player + BODY.y]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    dec     esi
    movss   xmm0, [player + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si edx, xmm0
    call    world_get
    mov     edi, eax
    lea     rsi, [block_step_sound]
    movss   xmm0, [vol_step]
    call    play_block_sound
.mobs:
    call    mobs_step
    call    status_step
    call    drops_step
    call    arrows_step
    call    tnt_step
    call    gun_step
    mov     edi, [rsp + 40]
    call    combat_step
    call    abilities_step
    call    dmgnum_step
    cmp     dword [rsp + 44], 0         ; the boats the player does not ride sail on too
    jne     .boats_done
    mov     rdi, rsp
    call    boats_step
.boats_done:
    call    check_region                ; the site cache follows the player across regions
    call    structures_step
    call    fire_step
    call    fx_step
    call    conts_step
    inc     dword [game_time]
    call    sleep_step
    add     rsp, 56
    pop     rbx
    pop     rbp
    ret
