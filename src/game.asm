; game.asm - world session: new/load/save glue, fixed-step simulation, block and mob
; interaction for both game modes.
%include "common.inc"
default rel

global game_mode, game_time, game_target, game_has_target, game_break_progress
global game_open_screen, game_open_cont, game_bow_charge, game_aim, game_open_npc, game_heavy_s
global game_new, game_load, game_save, game_frame, game_respawn

extern world_header, world_get, world_set, world_load, world_save, world_generate, world_top_y
extern player, player_spawn, body_step, player_look, player_eye, player_forward
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
extern mobs_save, mobs_load
extern audio_play, audio_play_at, rng_next, str_copy, input_captured
extern drops_clear, drops_spawn, drops_step, hand_swing
extern arrows_clear, arrows_step, arrows_spawn, tnt_clear, tnt_step, tnt_prime
extern cont_at, cont_create, cont_block_removed, conts_step, conts_validate
extern gun_reset, gun_step, gun_fire, gun_reload_start, gun_index, gun_automatic
extern fire_clear, fire_place, fire_step, fire_rebuild, fx_clear, fx_step
extern rpg_reset, rpg_load, rpg_save, rpg_on_death, rpg_on_block_mined, rpg_class, rpg_stat
extern rpg_recompute, rpg_stats, rpg_keystones, status_step
extern combat_reset, combat_set_guard, combat_dodge, combat_melee, combat_heavy, combat_step, combat_heal
extern combat_speed_mult, combat_crit_roll, combat_max_mana
extern combat_guard_t, combat_hitstop, combat_mana, combat_stamina
extern abilities_reset, abilities_step, abilities_use, abilities_staff_bolt
extern dmgnum_clear, dmgnum_step
extern structures_plan, structures_reset, structures_spawn_npcs, structures_step
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
    call    combat_reset
    call    abilities_reset
    call    dmgnum_clear
    pop     rbp
    jmp     gun_reset                   ; and the firearm's cooldown, reload and recoil

; game_new(edi seed, esi mode, rdx name)
game_new:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13, rdx
    lea     rdi, [world_header]
    mov     ecx, WORLD_HDR_SIZE
    xor     eax, eax
    rep     stosb
    mov     edi, ebx
    call    world_generate
    mov     [world_header + WORLDHDR.mode], r12d
    mov     dword [world_header + WORLDHDR.time], NEW_WORLD_TIME
    lea     rdi, [world_header + WORLDHDR.name]
    mov     rsi, r13
    mov     edx, 32
    call    str_copy
    mov     edi, 128
    mov     esi, 128
    call    world_top_y
    inc     eax
    mov     dword [world_header + WORLDHDR.spawn_x], 128
    mov     [world_header + WORLDHDR.spawn_y], eax
    mov     dword [world_header + WORLDHDR.spawn_z], 128
    mov     [game_mode], r12d
    mov     dword [game_time], NEW_WORLD_TIME
    call    player_spawn
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
    mov     qword [inv_container], 0
    call    rpg_reset                   ; first: new mobs take the (fresh) character's level
    call    mobs_populate
    call    structures_reset
    call    structures_spawn_npcs
    call    reset_session
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; game_load(rdi path) -> eax as world_load (0 ok / 1 missing / 2 invalid / 3 I/O)
game_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_load
    test    eax, eax
    jnz     .ret
    lea     rbx, [world_header]
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
    mov     dword [player + BODY.half_w], __float32__(0.3)
    mov     dword [player + BODY.height], __float32__(1.8)
    mov     dword [player + BODY.speed], __float32__(4.317)
    and     dword [player + BODY.flying], 1
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .fly_ok
    mov     dword [player + BODY.flying], 0
.fly_ok:
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
    cmp     dword [surv + SURVIVAL.health], 0
    jne     .alive
    call    survival_reset
    call    player_spawn
    call    rpg_on_death                ; died, then quit from the death screen: same XP loss
.alive:
    call    conts_validate
    call    fire_rebuild                ; the table of the FIRE blocks just loaded
    mov     rdi, rbx
    call    mobs_load
    mov     edi, [rbx + WORLDHDR.seed]  ; the sites are planned again from the seed
    call    structures_plan
    call    structures_reset
    call    structures_spawn_npcs
    call    drops_clear
    call    arrows_clear
    call    tnt_clear
    call    fx_clear
    mov     qword [inv_container], 0
    call    reset_session
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; game_save(rdi path) -> eax as world_save
game_save:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12, rdi
    lea     rbx, [world_header]
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
    mov     rdi, rbx
    call    mobs_save
    mov     rdi, rbx
    call    rpg_save
    mov     rdi, r12
    call    world_save
    pop     r12
    pop     rbx
    pop     rbp
    ret

; game_respawn(): full stats, back at the world spawn
game_respawn:
    push    rbp
    mov     rbp, rsp
    call    survival_reset
    call    player_spawn
    call    rpg_on_death
    call    reset_session               ; combat state too
    pop     rbp
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
    cmp     ecx, MOB_MERCHANT
    je      .no
    cmp     ecx, MOB_ELDER
    je      .no
.block:
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
%define F_INP    56                     ; INPUT copy (20)
%define F_X0     76
%define F_Z0     80
%define F_WAS    84
%define F_LAND   88
%define F_DIST   92
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

    ; 6. buttons, in ownership order: a merchant or elder (talk), a held firearm (section
    ; 12), a mage's staff (bolts), then melee on the targeted mob. The first three never
    ; punch, dig, use or place.
    mov     eax, [rsp + F_MOB]
    test    eax, eax
    js      .not_npc
    imul    eax, eax, MOB_size
    lea     rcx, [mobs]
    mov     eax, [rcx + rax + MOB.type]
    mov     ecx, ST_TRADE
    cmp     eax, MOB_MERCHANT
    je      .npc
    mov     ecx, ST_DIALOG
    cmp     eax, MOB_ELDER
    jne     .not_npc
.npc:
    mov     dword [game_heavy_s], __float32__(-1.0)     ; no heavy attack on a villager
    mov     dword [game_break_progress], 0
    mov     dword [break_cooldown], 0
    mov     dword [brk_y], -1
    cmp     dword [frame_input + FRAMEINPUT.rmb_pressed], 0
    je      .pick
    mov     [game_open_screen], ecx
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
    jne     .not_leaves
    call    held_id
    cmp     byte [item_tool + rax], TOOL_AXE
    jne     .leaf_roll
    mov     ebx, LEAVES                 ; an axe takes the leaves themselves
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

; sim_step(): one fixed step of player physics, survival, footsteps, mobs and time
sim_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 56                     ; [rsp] INPUT copy, [rsp+20] was_on_ground,
                                        ; [rsp+24] x0, [rsp+28] z0, [rsp+32] dist,
                                        ; [rsp+40] sprinting (drains stamina)
    call    rpg_recompute               ; the character first: gear, ranks and attributes may have changed
    lea     rsi, [frame_input + FRAMEINPUT.move]
    mov     rdi, rsp
    mov     ecx, INPUT_size
    rep     movsb
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
    lea     rdi, [player]
    mov     rsi, rsp
    call    body_step
    movss   [rsp + 36], xmm0            ; landed fall distance
    movss   xmm1, [player + BODY.x]
    subss   xmm1, [rsp + 24]
    mulss   xmm1, xmm1
    movss   xmm2, [player + BODY.z]
    subss   xmm2, [rsp + 28]
    mulss   xmm2, xmm2
    addss   xmm1, xmm2
    sqrtss  xmm1, xmm1
    movss   [rsp + 32], xmm1
    ; jumped = was_on_ground && jump && !flying
    xor     ebx, ebx
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
    call    structures_step
    call    fire_step
    call    fx_step
    call    conts_step
    inc     dword [game_time]
    add     rsp, 56
    pop     rbx
    pop     rbp
    ret
