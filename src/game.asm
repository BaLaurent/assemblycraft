; game.asm - world session: new/load/save glue, fixed-step simulation, block and mob
; interaction for both game modes.
%include "common.inc"
default rel

global game_mode, game_time, game_target, game_has_target, game_break_progress
global game_open_table
global game_new, game_load, game_save, game_frame, game_respawn

extern world_header, world_get, world_set, world_load, world_save, world_generate, world_top_y
extern player, player_spawn, body_step, player_look, player_eye, player_forward
extern body_intersects_block, raycast, frame_input, settings
extern inv, inv_sel, inv_clear, inv_set_creative_default, inv_held
extern inv_consume_held, inv_damage_held, inv_find_hotbar
extern item_break_time, item_harvest_drop, item_attack_damage
extern item_tool, item_food, item_max_stack
extern block_hardness, block_dig_sound, block_step_sound
extern surv, survival_reset, survival_land, survival_step, survival_eat_step
extern survival_can_sprint, survival_exhaust
extern mobs_clear, mobs_populate, mobs_step, mobs_raycast, mob_hurt
extern mobs_intersect_block, mobs_save, mobs_load
extern audio_play, rng_next, str_copy
extern drops_clear, drops_spawn, drops_step, hand_swing

section .rodata
align 4
step_dt:      dd 0.016666668
repeat_dt:    dd 0.25
reach_surv:   dd 4.5
reach_crea:   dd 5.0
mob_reach:    dd 3.5
f_one:        dd 1.0
f_half:       dd 0.5
f_quarter:    dd 0.25
f_hundred:    dd 100.0
f_step_len:   dd 1.6
vol_step:     dd 0.35
vol_crack:    dd 0.4
vol_place:    dd 0.8
exh_attack:   dd 0.1
exh_break:    dd 0.005
abs_mask:     dd 0x7FFFFFFF

section .data
align 4
game_mode: dd MODE_CREATIVE
game_time: dd NEW_WORLD_TIME
game_break_progress: dd 0.0

section .bss
alignb 4
game_target:     resb RAYHIT_size
game_has_target: resd 1
game_open_table: resd 1
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

; reset_session(): per-session timers and targeting
reset_session:
    xor     eax, eax
    mov     [step_accum], eax
    mov     [break_timer], eax
    mov     [place_timer], eax
    mov     [break_cooldown], eax
    mov     [crack_timer], eax
    mov     [step_dist], eax
    mov     [game_has_target], eax
    mov     [game_open_table], eax
    mov     [game_break_progress], eax
    mov     dword [brk_y], -1
    ret

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
    call    mobs_populate
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
    ; survival stats
    call    survival_reset
    mov     eax, [rbx + WORLDHDR.health]
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    mov     ecx, 20
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
.alive:
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
    mov     rdi, rbx
    call    mobs_load
    call    drops_clear
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
    mov     eax, [game_time]
    mov     [rbx + WORLDHDR.time], eax
    mov     eax, [game_mode]
    mov     [rbx + WORLDHDR.mode], eax
    mov     rdi, rbx
    call    mobs_save
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
    call    reset_session
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

; held_id() -> eax id of the selected hotbar stack
held_id:
    mov     eax, [inv_sel]
    movzx   eax, byte [inv + INVENTORY.slots + rax*4 + ITEMSTACK.id]
    ret

; damage_held_tool(edi amount_if_sword, esi amount_otherwise): wear the held tool
damage_held_tool:
    mov     eax, [inv_sel]
    movzx   eax, byte [inv + INVENTORY.slots + rax*4 + ITEMSTACK.id]
    movzx   eax, byte [item_tool + rax]
    test    eax, eax
    jz      .ret
    cmp     eax, TOOL_SWORD
    cmovne  edi, esi
    jmp     inv_damage_held
.ret:
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
%define F_SIZE   112

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

    ; 3. look, scaled by sensitivity, optionally inverted
    cvtsi2ss xmm2, dword [settings + SETTINGS.sensitivity]
    divss   xmm2, [f_hundred]
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

    ; 4. fixed 1/60 s steps, at most 5 per frame
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
    lea     rdi, [rsp + F_EYE]
    lea     rsi, [rsp + F_DIR]
    movss   xmm0, [mob_reach]
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

    ; 6. attack the targeted mob (no block breaking this frame)
    cmp     dword [rsp + F_MOB], 0
    jl      .blocks
    mov     dword [game_break_progress], 0
    cmp     dword [frame_input + FRAMEINPUT.lmb_pressed], 0
    je      .place
    call    hand_swing
    call    held_id
    mov     edi, eax
    call    item_attack_damage
    mov     r12d, eax
    movss   xmm0, [rsp + F_DIR]         ; horizontal direction, normalised
    movss   xmm1, [rsp + F_DIR + 8]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2
    xorps   xmm3, xmm3
    comiss  xmm2, xmm3
    jbe     .hit_mob
    divss   xmm0, xmm2
    divss   xmm1, xmm2
.hit_mob:
    mov     edi, [rsp + F_MOB]
    mov     esi, r12d
    call    mob_hurt
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
    cmp     dword [frame_input + FRAMEINPUT.lmb_pressed], 0
    je      .no_swing
    call    hand_swing                  ; a click swings even at thin air
.no_swing:
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
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    mov     ecx, AIR
    call    world_set
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
    movss   xmm1, [rsp + F_DT]
    divss   xmm1, xmm0
    addss   xmm1, [game_break_progress]
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
    cmp     r12d, LEAVES
    jne     .drop_ready
    call    rng_next
    test    eax, 15
    jnz     .drop_ready
    mov     ebx, APPLE
.drop_ready:
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    mov     ecx, AIR
    call    world_set
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

    ; 9. place / use
.place:
    mov     edi, [frame_input + FRAMEINPUT.rmb_held]
    mov     esi, [frame_input + FRAMEINPUT.rmb_pressed]
    lea     rdx, [place_timer]
    movss   xmm0, [rsp + F_DT]
    call    repeat_fire
    test    eax, eax
    jz      .pick
    cmp     dword [game_has_target], 0
    je      .pick
    call    target_block
    cmp     eax, CRAFTING_TABLE
    jne     .not_table
    cmp     dword [frame_input + FRAMEINPUT.move + INPUT.down], 0
    jne     .not_table
    cmp     dword [frame_input + FRAMEINPUT.rmb_pressed], 0
    je      .not_table
    mov     dword [game_open_table], 1
    jmp     .pick
.not_table:
    call    held_id
    mov     r12d, eax
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .not_food
    cmp     byte [item_food + r12], 0
    jne     .pick                       ; eating runs per step
.not_food:
    test    r12d, r12d
    jz      .pick
    cmp     r12d, NUM_BLOCKS
    jae     .pick
    cmp     dword [game_target + RAYHIT.px], WORLD_X - 1
    ja      .pick
    cmp     dword [game_target + RAYHIT.py], WORLD_Y - 1
    ja      .pick
    cmp     dword [game_target + RAYHIT.pz], WORLD_Z - 1
    ja      .pick
    mov     edi, [game_target + RAYHIT.px]
    mov     esi, [game_target + RAYHIT.py]
    mov     edx, [game_target + RAYHIT.pz]
    call    world_get
    test    eax, eax
    jnz     .pick
    lea     rdi, [player]
    mov     esi, [game_target + RAYHIT.px]
    mov     edx, [game_target + RAYHIT.py]
    mov     ecx, [game_target + RAYHIT.pz]
    call    body_intersects_block
    test    eax, eax
    jnz     .pick
    mov     edi, [game_target + RAYHIT.px]
    mov     esi, [game_target + RAYHIT.py]
    mov     edx, [game_target + RAYHIT.pz]
    call    mobs_intersect_block
    test    eax, eax
    jnz     .pick
    mov     edi, [game_target + RAYHIT.px]
    mov     esi, [game_target + RAYHIT.py]
    mov     edx, [game_target + RAYHIT.pz]
    mov     ecx, r12d
    call    world_set
    mov     edi, r12d
    lea     rsi, [block_dig_sound]
    movss   xmm0, [vol_place]
    call    play_block_sound
    call    hand_swing
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .pick
    mov     edi, 1
    call    inv_consume_held

    ; 10. pick block
.pick:
    cmp     dword [frame_input + FRAMEINPUT.mmb_pressed], 0
    je      .ret
    cmp     dword [game_has_target], 0
    je      .ret
    call    target_block
    test    eax, eax
    jz      .ret
    cmp     dword [game_mode], MODE_CREATIVE
    jne     .pick_survival
    mov     ecx, [inv_sel]
    lea     rdx, [inv + INVENTORY.slots + rcx*4]
    mov     [rdx + ITEMSTACK.id], al
    mov     byte [rdx + ITEMSTACK.count], 1
    mov     word [rdx + ITEMSTACK.dmg], 0
    jmp     .ret
.pick_survival:
    mov     edi, eax
    call    inv_find_hotbar
    test    eax, eax
    js      .ret
    mov     [inv_sel], eax
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
                                        ; [rsp+24] x0, [rsp+28] z0, [rsp+32] dist
    lea     rsi, [frame_input + FRAMEINPUT.move]
    mov     rdi, rsp
    mov     ecx, INPUT_size
    rep     movsb
    call    survival_can_sprint
    test    eax, eax
    jnz     .sprint_ok
    mov     dword [rsp + INPUT.sprint], 0
.sprint_ok:
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
    call    drops_step
    inc     dword [game_time]
    add     rsp, 56
    pop     rbx
    pop     rbp
    ret
