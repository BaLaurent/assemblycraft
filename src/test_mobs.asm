; test_mobs.asm - mob ray picking, damage and drops, zombie attacks and parries, elites, villagers,
; the Fallen King, kill rewards, spawn rules.
%include "common.inc"
default rel

global test_mob_raycast_hits, test_mob_hurt_pig_drops_food
global test_zombie_attacks_player, test_mob_spawn_rules
global test_zombie_windup_can_be_parried, test_elite_saved_and_tougher, test_npc_immune_and_not_saved
global test_boss_phases_slam_and_summons, test_mob_kill_awards_xp_and_coins

extern mobs, mobs_clear, mobs_step, mob_spawn, mobs_raycast, mob_hurt, mob_count_type, mob_count_kind
extern mob_spawn_elite, mob_spawn_npc, mob_is_hostile, mob_strike, mobs_save, mobs_load
extern player, body_init, rng_seed, world_clear, world_set, world_mark_all_dirty, blocks
extern game_mode, game_time, settings, surv, survival_reset, inv, inv_clear
extern drops, drops_clear, arrows, arrows_clear, tnt_clear, fx_clear
extern combat_reset, combat_hit_flags, combat_guard_t
extern rpg_state, rpg_reset, structures_reset, light_cells, light_fill_sky

section .rodata
align 4
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_11:     dd 11.0
k_10_5:   dd 10.5
k_5_5:    dd 5.5
k_16_5:   dd 16.5
k_17_5:   dd 17.5
k_one:    dd 1.0
k_10:     dd 10.0
k_4:      dd 4.0
k_t_lo:   dd 4.69
k_t_hi:   dd 4.71
k_kb_w:   dd -6.0                       ; zombie at +x of the player: knockback runs towards -x
k_8_5:    dd 8.5
k_18_5:   dd 18.5
k_2_4:    dd 2.4
k_2_9:    dd 2.9
k_3_3:    dd 3.3
k_24:     dd 24.0
k_89:     dd 89.0
k_91:     dd 91.0
k_1e9:    dd 1.0e9
k_m1e9:   dd -1.0e9

section .text

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; fixture(): the state every mob test starts from (after world_clear): rng seed 1234, no mobs,
; Survival at Normal difficulty, early morning, fresh survival state, STONE floor at y = 10
; for x, z in 0..31
fixture:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     edi, 1234
    call    rng_seed
    call    mobs_clear
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [game_time], NEW_WORLD_TIME
    call    survival_reset
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

; reset_player(): standard player body (0.3 x 1.8, walk 4.317)
reset_player:
    push    rbp
    mov     rbp, rsp
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    pop     rbp
    ret

; SPAWN type, x constant, z constant: a mob standing at y = 11 -> eax slot or -1
%macro SPAWN 3
    mov     edi, %1
    movss   xmm0, [%2]
    movss   xmm1, [k_11]
    movss   xmm2, [%3]
    call    mob_spawn
%endmacro

test_mob_raycast_hits:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 40                     ; origin[3] @0, dir[3] @16
    call    world_clear
    call    fixture
    SPAWN   MOB_ZOMBIE, k_10_5, k_10_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    SETF    [rsp + 0], 10.5             ; ray from (10.5, 11.9, 5.5) along +z
    SETF    [rsp + 4], 11.9
    SETF    [rsp + 8], 5.5
    SETF    [rsp + 16], 0.0
    SETF    [rsp + 20], 0.0
    SETF    [rsp + 24], 1.0
    lea     rdi, [rsp]
    lea     rsi, [rsp + 16]
    movss   xmm0, [k_10]
    call    mobs_raycast
    cmp     eax, ebx
    jne     .fail
    ucomiss xmm0, [k_t_lo]              ; 4.69 < t < 4.71
    jbe     .fail
    ucomiss xmm0, [k_t_hi]
    jae     .fail
    lea     rdi, [rsp]
    lea     rsi, [rsp + 16]
    movss   xmm0, [k_4]                 ; out of reach
    call    mobs_raycast
    cmp     eax, -1
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    mov     eax, ebx
    add     rsp, 40
    pop     rbx
    pop     rbp
    ret

test_mob_hurt_pig_drops_food:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    call    inv_clear
    call    drops_clear
    SPAWN   MOB_PIG, k_5_5, k_5_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    imul    r12d, ebx, MOB_size
    lea     rax, [mobs]
    add     r12, rax                    ; the pig
    mov     edi, ebx
    mov     esi, 6
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]               ; hit direction (0, 1)
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.health], 4 ; 10 - 6
    jne     .fail
    cmp     dword [r12 + MOB.hurt], 10  ; hurt window in steps
    jne     .fail
    mov     edi, ebx                    ; still hurting: ignored
    mov     esi, 6
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    test    eax, eax
    jnz     .fail
    cmp     dword [r12 + MOB.type], MOB_PIG
    jne     .fail
    mov     dword [r12 + MOB.hurt], 0
    mov     edi, ebx
    mov     esi, 6
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.type], MOB_NONE
    jne     .fail
    cmp     byte [drops + DROP.id], PORKCHOP ; dropped on the ground, not in the inventory
    jne     .fail
    movzx   eax, byte [drops + DROP.count]
    dec     eax
    cmp     eax, 2                      ; 1..3
    ja      .fail
    cmp     byte [inv + INVENTORY.slots + ITEMSTACK.count], 0
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

test_zombie_attacks_player:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset                ; the guard is down: the blow is not parried
    mov     dword [game_time], 40000    ; night: the zombie must not burn during the test
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    SPAWN   MOB_ZOMBIE, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    call    mobs_step                            ; in reach: the arm goes up, no blow yet
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    cmp     dword [mobs + MOB.windup], 0
    jle     .fail
    mov     ebx, 20
.windup:                                         ; ...the blow comes down when the 20 steps are up
    call    mobs_step
    dec     ebx
    jnz     .windup
    cmp     dword [surv + SURVIVAL.health], 17   ; Normal difficulty hits for 3
    jne     .fail
    movss   xmm0, [player + BODY.kbx]            ; knocked away from the zombie
    ucomiss xmm0, [k_kb_w]
    jne     .fail
    cmp     dword [player + BODY.kbz], 0
    jne     .fail
    mov     ebx, 10
.again:
    call    mobs_step
    dec     ebx
    jnz     .again
    cmp     dword [surv + SURVIVAL.health], 17   ; the 60-step cooldown holds
    jne     .fail
    mov     edi, MOB_ZOMBIE                      ; ...and the zombie is still there
    call    mob_count_type
    cmp     eax, 1
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

test_mob_spawn_rules:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    lea     rdi, [blocks + (10 << 16)]  ; GRASS over the whole layer y = 10
    mov     ecx, WORLD_X * WORLD_Z
    mov     al, GRASS
    rep     stosb
    call    world_mark_all_dirty
    call    reset_player
    SETF    [player + BODY.x], 128.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 128.5
    mov     dword [game_time], 40000    ; deep night
    mov     ebx, 600
.night:
    call    mobs_step
    inc     dword [game_time]
    dec     ebx
    jnz     .night
    mov     edi, 1                      ; hostile mobs: zombies, skeletons, creepers, spiders
    call    mob_count_kind
    dec     eax
    cmp     eax, 11                     ; 1..12
    ja      .fail
    call    mobs_clear
    mov     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    mov     ebx, 600
.peaceful:
    call    mobs_step
    inc     dword [game_time]
    dec     ebx
    jnz     .peaceful
    mov     edi, 1
    call    mob_count_kind
    test    eax, eax
    jnz     .fail
    ; block light 8+ everywhere (a torch-lit area): no hostile mob spawns at night
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    lea     rdi, [light_cells]
    mov     ecx, WORLD_VOLUME
    mov     al, 0xF8                    ; sky 15, block 8
    rep     stosb
    mov     ebx, 600
.lit:
    call    mobs_step
    inc     dword [game_time]
    dec     ebx
    jnz     .lit
    mov     edi, 1
    call    mob_count_kind
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    call    light_fill_sky
    call    mobs_clear
    call    arrows_clear                ; skeletons and creepers may have left arrows, drops, TNT
    call    tnt_clear
    call    drops_clear
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- 0.6: telegraphs, parries, elites, villagers, the Fallen King, kill rewards -----------------

section .bss
alignb 16
hdr:        resb 1024                   ; stands in for a WORLDHDR: mobs_save / mobs_load touch only
                                        ; .mob_count (@300) and .mobs (@304..944)

section .text

; mob_ptr(edi idx) -> rax the mob in that slot
mob_ptr:
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rax, rcx
    ret

; strike(edi idx, esi dmg) -> eax mob_strike's result, knocking along +z
strike:
    sub     rsp, 8
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_strike
    add     rsp, 8
    ret

; drops_of(edi item) -> eax item entities lying in the world, edx their total count
drops_of:
    xor     eax, eax
    xor     edx, edx
    lea     rcx, [drops]
    mov     esi, MAX_DROPS
.l:
    cmp     [rcx + DROP.id], dil
    jne     .next
    inc     eax
    movzx   r8d, byte [rcx + DROP.count]
    add     edx, r8d
.next:
    add     rcx, DROP_size
    dec     esi
    jnz     .l
    ret

; arrow_stats() -> eax live arrows, edx 1 when every one is a mob's with damage 4, xmm0 the spread
; of their z velocities (max - min)
arrow_stats:
    xor     eax, eax
    mov     edx, 1
    movss   xmm1, [k_1e9]
    movss   xmm2, [k_m1e9]
    lea     rcx, [arrows]
    mov     esi, MAX_ARROWS
.l:
    cmp     dword [rcx + ARROWENT.live], 0
    je      .next
    inc     eax
    cmp     dword [rcx + ARROWENT.owner], 1
    jne     .bad
    cmp     dword [rcx + ARROWENT.damage], 4
    je      .ok
.bad:
    xor     edx, edx
.ok:
    movss   xmm0, [rcx + ARROWENT.vz]
    minss   xmm1, xmm0
    maxss   xmm2, xmm0
.next:
    add     rcx, ARROWENT_size
    dec     esi
    jnz     .l
    movaps  xmm0, xmm2
    subss   xmm0, xmm1
    ret

; kill_zombie(edi origin) -> eax 0 when a zombie spawned at (8.5, 11, 8.5) with that dungeon origin
; died to a 100-point strike
kill_zombie:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12d, edi
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     [rax + MOB.origin], r12d
    mov     edi, ebx
    mov     esi, 100
    call    strike
    cmp     eax, 1
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; A zombie in reach raises its arm for 20 steps before the blow. A player whose guard goes up on the
; very last of them parries it: nothing taken, the zombie reels back and stands dazed for 50 steps.
test_zombie_windup_can_be_parried:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset                ; guard down, no riposte, full stamina
    mov     dword [game_time], 40000    ; night: the zombie must not burn during the test
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    SETF    [player + BODY.yaw], 90.0   ; facing +x, towards the zombie: its blow is frontal
    SPAWN   MOB_ZOMBIE, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax                    ; the zombie
    call    mobs_step                   ; in reach: the arm goes up
    cmp     dword [r12 + MOB.windup], 20
    jne     .fail
    cmp     dword [r12 + MOB.input + INPUT.fwd], 0  ; and it stands still to swing
    jne     .fail
    mov     ebx, 19
.raise:                                 ; windup 19 .. 1: no blow yet
    call    mobs_step
    dec     ebx
    jnz     .raise
    cmp     dword [r12 + MOB.windup], 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    mov     dword [combat_guard_t], 0   ; the guard comes up on the very last step
    call    mobs_step                   ; the blow lands on a fresh guard
    cmp     dword [surv + SURVIVAL.health], 20      ; parried: nothing taken
    jne     .fail
    cmp     dword [r12 + MOB.stun], 50
    jne     .fail
    cmp     dword [r12 + MOB.windup], 0
    jne     .fail
    movss   xmm0, [r12 + BODY.kbx]      ; the zombie stands at +x of the player: it reels back along +x
    ucomiss xmm0, [k_one]
    jbe     .fail
    mov     ebx, 10
.dazed:                                 ; stunned: no steps toward the player, no new blow
    call    mobs_step
    cmp     dword [r12 + MOB.input + INPUT.fwd], 0
    jne     .fail
    cmp     dword [r12 + MOB.windup], 0
    jne     .fail
    dec     ebx
    jnz     .dazed
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    cmp     dword [r12 + MOB.stun], 40
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    combat_reset
    call    mobs_clear
    call    reset_player                ; yaw 90 was set
    call    fx_clear                    ; a parry throws sparks
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; An elite zombie has 2.5 x the health and moves faster, winds up for 16 steps and hits 1.5 x
; harder (rounded); it survives a save and load as an elite, its health clamped to 2.5 x base;
; villager records are not loaded.
test_elite_saved_and_tougher:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    call    inv_clear                   ; no armor
    mov     dword [game_time], 40000
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax                    ; the elite
    cmp     dword [r12 + MOB.health], 50            ; 2.5 x 20
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 50
    jne     .fail
    cmp     dword [r12 + MOB.elite], 1
    jne     .fail
    movss   xmm0, [r12 + BODY.speed]    ; 1.15 x 2.6 = 2.99
    ucomiss xmm0, [k_2_9]
    jbe     .fail
    lea     rdi, [hdr]
    call    mobs_save
    cmp     dword [hdr + WORLDHDR.mob_count], 1
    jne     .fail
    cmp     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_ZOMBIE | MOB_ELITE_BIT
    jne     .fail
    mov     dword [r12 + MOB.health], 30            ; wounded: the 30 survives the round trip
    lea     rdi, [hdr]
    call    mobs_save
    call    mobs_clear
    lea     rdi, [hdr]
    call    mobs_load
    lea     r12, [mobs]
    cmp     dword [r12 + MOB.type], MOB_ZOMBIE
    jne     .fail
    cmp     dword [r12 + MOB.elite], 1
    jne     .fail
    cmp     dword [r12 + MOB.health], 30
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 50
    jne     .fail
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.health], 999   ; an inflated record clamps to 2.5 x base
    call    mobs_clear
    lea     rdi, [hdr]
    call    mobs_load
    cmp     dword [mobs + MOB.health], 50
    jne     .fail
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_ZOMBIE  ; without the elite bit: a plain 20
    call    mobs_clear
    lea     rdi, [hdr]
    call    mobs_load
    cmp     dword [mobs + MOB.elite], 0
    jne     .fail
    cmp     dword [mobs + MOB.health], 20
    jne     .fail
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_MERCHANT | MOB_ELITE_BIT   ; not a saved type
    call    mobs_clear
    lea     rdi, [hdr]
    call    mobs_load
    cmp     dword [mobs + MOB.type], MOB_NONE
    jne     .fail
    call    mobs_clear                  ; an elite next to the player: 16-step wind-up, blow of 4
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_17_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    call    mobs_step
    cmp     dword [r12 + MOB.windup], 16
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    mov     ebx, 16
.swing:
    call    mobs_step
    dec     ebx
    jnz     .swing
    cmp     dword [surv + SURVIVAL.health], 16      ; Normal hits for 3, x 1.5 = 4.5 -> 4
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    combat_reset
    call    mobs_clear
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Villagers cannot be hurt, are not saved, stroll back toward their home when they stray beyond
; 6 blocks and turn to a player within 4. mob_is_hostile tells hostile mobs from the rest.
; Frame: slots [rsp] merchant, [rsp+4] elder, [rsp+8] pig, [rsp+12] zombie, [rsp+16] boss.
test_npc_immune_and_not_saved:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    mov     dword [game_time], 40000
    SETF    [player + BODY.x], 2.5      ; far from everyone
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 2.5
    mov     edi, MOB_MERCHANT
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    mob_spawn_npc
    test    eax, eax
    js      .fail
    mov     [rsp], eax
    SPAWN   MOB_ELDER, k_10_5, k_16_5
    test    eax, eax
    js      .fail
    mov     [rsp + 4], eax
    SPAWN   MOB_PIG, k_5_5, k_5_5
    test    eax, eax
    js      .fail
    mov     [rsp + 8], eax
    mov     edi, [rsp]
    call    mob_ptr
    mov     r12, rax                    ; the merchant
    cmp     dword [r12 + MOB.health], 20
    jne     .fail
    mov     byte [combat_hit_flags], HF_PLAYER
    mov     edi, [rsp]
    mov     esi, 5
    call    strike                      ; a villager shrugs it off
    test    eax, eax
    jnz     .fail
    mov     edi, [rsp]
    mov     esi, 5
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    test    eax, eax
    jnz     .fail
    cmp     dword [r12 + MOB.health], 20
    jne     .fail
    cmp     dword [r12 + MOB.hurt], 0
    jne     .fail
    cmp     dword [r12 + MOB.tagged], 0
    jne     .fail
    cmp     byte [combat_hit_flags], 0  ; the flags are consumed either way
    jne     .fail
    cmp     dword [r12 + MOB.type], MOB_MERCHANT
    jne     .fail
    mov     edi, [rsp]
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail
    mov     edi, [rsp + 8]
    call    mob_is_hostile              ; a pig is no enemy either
    test    eax, eax
    jnz     .fail
    lea     rdi, [hdr]
    call    mobs_save                   ; the villagers are skipped: only the pig is saved
    cmp     dword [hdr + WORLDHDR.mob_count], 1
    jne     .fail
    cmp     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_PIG
    jne     .fail
    SETF    [r12 + BODY.x], 24.5        ; 8 blocks east of home (16.5, 16.5): it walks back
    mov     ebx, 60
.home:
    call    mobs_step
    dec     ebx
    jnz     .home
    movss   xmm0, [r12 + BODY.x]
    ucomiss xmm0, [k_24]
    jae     .fail                       ; moved at least half a block west
    SETF    [r12 + BODY.x], 16.5        ; back home, the player 3 blocks east: it stands and faces him
    SETF    [r12 + BODY.z], 16.5
    SETF    [player + BODY.x], 19.5
    SETF    [player + BODY.z], 16.5
    call    mobs_step
    cmp     dword [r12 + MOB.input + INPUT.fwd], 0
    jne     .fail
    movss   xmm0, [r12 + BODY.yaw]      ; heading 90 degrees: forward is +x
    ucomiss xmm0, [k_89]
    jb      .fail
    ucomiss xmm0, [k_91]
    ja      .fail
    SETF    [player + BODY.x], 2.5      ; the player leaves before the hostile mobs appear
    SETF    [player + BODY.z], 2.5
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     [rsp + 12], eax
    SPAWN   MOB_BOSS, k_16_5, k_18_5
    test    eax, eax
    js      .fail
    mov     [rsp + 16], eax
    mov     edi, [rsp + 12]
    call    mob_is_hostile
    cmp     eax, 1
    jne     .fail
    mov     edi, [rsp + 16]
    call    mob_is_hostile
    cmp     eax, 1
    jne     .fail
    mov     edi, [rsp + 4]
    call    mob_is_hostile              ; the elder is not
    test    eax, eax
    jnz     .fail
    mov     edi, MAX_MOBS - 1           ; an empty slot
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail
    mov     edi, MAX_MOBS               ; no such slot
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail
    mov     edi, -1
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    mov     byte [combat_hit_flags], 0
    call    combat_reset
    call    mobs_clear
    mov     eax, ebx
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

; The Fallen King (Normal): 300 health, a 36-step wind-up and a slam of 8 on a player 2 blocks
; away (one slam in 40 steps, the 70-step cooldown holds the next), skeletons rise when timer_a
; runs out, a volley of 5 arrows comes every 240 steps from phase 2 on, and below a third of his
; health the wind-up shortens to 24.
test_boss_phases_slam_and_summons:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    call    inv_clear                   ; no armor
    call    arrows_clear
    call    rpg_reset                   ; class 0: no armor bonus
    mov     dword [game_time], 40000
    SETF    [player + BODY.x], 18.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    SPAWN   MOB_BOSS, k_16_5, k_16_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax                    ; the boss, 2 blocks from the player
    cmp     dword [r12 + MOB.health], 300
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 300
    jne     .fail
    cmp     dword [r12 + MOB.timer_a], 600
    jne     .fail
    cmp     dword [r12 + MOB.timer_b], 240
    jne     .fail
    call    mobs_step                   ; the fists go up: wind-up 36, standing still
    cmp     dword [r12 + MOB.windup], 36
    jne     .fail
    movss   xmm0, [r12 + BODY.speed]    ; phase 1 walks at 2.4
    ucomiss xmm0, [k_2_4]
    jne     .fail
    mov     ebx, 39
.slam:                                  ; 40 steps in all: one slam of 8, no second
    call    mobs_step
    dec     ebx
    jnz     .slam
    cmp     dword [surv + SURVIVAL.health], 12
    jne     .fail
    cmp     dword [r12 + MOB.windup], 0
    jne     .fail
    cmp     dword [r12 + MOB.cooldown], 0
    jle     .fail
    mov     dword [r12 + MOB.timer_b], 1
    call    mobs_step                   ; phase 1 keeps to melee: the volley timer only recycles
    cmp     dword [r12 + MOB.timer_b], 240
    jne     .fail
    call    arrow_stats
    test    eax, eax
    jnz     .fail
    mov     dword [r12 + MOB.timer_a], 1
    call    mobs_step                   ; the timer runs out: two skeletons
    mov     edi, MOB_SKELETON
    call    mob_count_type
    cmp     eax, 2
    jne     .fail
    cmp     dword [r12 + MOB.timer_a], 600
    jne     .fail
    mov     dword [r12 + MOB.health], 90            ; 30 %: phase 3
    mov     dword [r12 + MOB.cooldown], 0
    mov     dword [r12 + MOB.windup], 0
    call    mobs_step
    cmp     dword [r12 + MOB.windup], 24
    jne     .fail
    movss   xmm0, [r12 + BODY.speed]    ; 1.4 x 2.4 = 3.36
    ucomiss xmm0, [k_3_3]
    jbe     .fail
    lea     rax, [mobs]                 ; the skeletons go (their own arrows would muddy the count)
    mov     ecx, MAX_MOBS
.skeletons:
    cmp     dword [rax + MOB.type], MOB_SKELETON
    jne     .not_skeleton
    mov     dword [rax + MOB.type], MOB_NONE
.not_skeleton:
    add     rax, MOB_size
    dec     ecx
    jnz     .skeletons
    call    arrows_clear
    mov     dword [r12 + MOB.timer_b], 1
    call    mobs_step                   ; phase 3: a volley of 5 arrows of 4, fanned about the aim
    call    arrow_stats
    cmp     eax, 5
    jne     .fail
    test    edx, edx
    jz      .fail
    ucomiss xmm0, [k_10]                ; the fan spans well over 10 blocks/s sideways
    jbe     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    call    arrows_clear                ; the skeletons may have shot
    call    fx_clear                    ; the slam's blast
    call    combat_reset
    call    rpg_reset
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Kills the player had a hand in (combat_hit_flags HF_PLAYER) pay XP (zombie 10) and consume the
; flags; untagged kills pay none; a hit tags a mob for 200 steps and raises its health bar for 180.
; Hostile mobs drop coins (one every other kill, an elite 3-5); the 8th kill of a dungeon's mobs
; clears it; the Fallen King drops his class's legendary, 30 coins and 4 diamonds and is recorded.
test_mob_kill_awards_xp_and_coins:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    call    rpg_reset
    call    drops_clear
    mov     dword [game_time], 40000    ; night: nothing burns
    mov     byte [rpg_state + RPGSAVE.class], CLASS_WARRIOR
    mov     byte [combat_hit_flags], HF_PLAYER
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    mov     esi, 100
    call    strike
    cmp     eax, 1
    jne     .fail
    cmp     byte [combat_hit_flags], 0
    jne     .fail
    cmp     dword [rpg_state + RPGSAVE.xp], 10      ; a zombie is worth 10
    jne     .fail
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5    ; untagged (no flags): no XP
    test    eax, eax
    js      .fail
    mov     edi, eax
    mov     esi, 100
    call    strike
    cmp     eax, 1
    jne     .fail
    cmp     dword [rpg_state + RPGSAVE.xp], 10
    jne     .fail
    mov     byte [combat_hit_flags], HF_PLAYER      ; a wound tags the mob, then the timers run down
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    mov     esi, 1
    call    strike
    mov     edi, ebx
    call    mob_ptr
    mov     r12, rax
    cmp     dword [r12 + MOB.health], 19
    jne     .fail
    cmp     dword [r12 + MOB.tagged], 200
    jne     .fail
    cmp     dword [r12 + MOB.bar], 180
    jne     .fail
    call    mobs_step
    cmp     dword [r12 + MOB.tagged], 199
    jne     .fail
    cmp     dword [r12 + MOB.bar], 179
    jne     .fail
    call    mobs_clear
    call    drops_clear                 ; coins: 12 untagged kills, a coin every other time
    mov     ebx, 12
.round:
    xor     edi, edi
    call    kill_zombie
    test    eax, eax
    jnz     .fail
    dec     ebx
    jnz     .round
    mov     edi, GOLD_COIN
    call    drops_of
    dec     eax
    cmp     eax, 10                     ; between 1 and 11 coins, never one per kill nor none
    ja      .fail
    call    drops_clear
    mov     edi, MOB_ZOMBIE             ; an elite drops 3..5 coins
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     edi, eax
    mov     esi, 200
    call    strike
    cmp     eax, 1
    jne     .fail
    mov     edi, GOLD_COIN
    call    drops_of
    cmp     eax, 1
    jne     .fail
    sub     edx, 3
    cmp     edx, 2
    ja      .fail
    mov     byte [rpg_state + RPGSAVE.class], CLASS_NONE    ; a dungeon's 8th kill clears it
    call    structures_reset
    mov     ebx, 7
.dungeon:
    mov     edi, 1
    call    kill_zombie
    test    eax, eax
    jnz     .fail
    dec     ebx
    jnz     .dungeon
    test    byte [rpg_state + RPGSAVE.cleared], 1
    jnz     .fail
    mov     edi, 1
    call    kill_zombie
    test    eax, eax
    jnz     .fail
    test    byte [rpg_state + RPGSAVE.cleared], 1
    jz      .fail
    call    drops_clear                 ; the Fallen King falls to an archer
    call    rpg_reset
    mov     byte [rpg_state + RPGSAVE.class], CLASS_ARCHER
    mov     byte [combat_hit_flags], HF_PLAYER | HF_CRIT
    SPAWN   MOB_BOSS, k_16_5, k_16_5
    test    eax, eax
    js      .fail
    mov     edi, eax
    mov     esi, 1000
    call    strike
    cmp     eax, 1
    jne     .fail
    mov     edi, MOB_BOSS
    call    mob_count_type
    test    eax, eax
    jnz     .fail
    test    byte [rpg_state + RPGSAVE.flags], 1     ; the realm remembers
    jz      .fail
    cmp     byte [rpg_state + RPGSAVE.level], 1     ; and 500 XP raised the level
    jbe     .fail
    mov     edi, CELESTIAL_BOW
    call    drops_of
    cmp     eax, 1
    jne     .fail
    mov     edi, DIAMOND
    call    drops_of
    cmp     edx, 4
    jne     .fail
    mov     edi, GOLD_COIN
    call    drops_of
    cmp     edx, 30
    jne     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    mov     byte [combat_hit_flags], 0
    call    mobs_clear
    call    drops_clear
    call    fx_clear                    ; the Fallen King's blast, level-up sparks
    call    structures_reset
    call    rpg_reset
    call    combat_reset
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret
