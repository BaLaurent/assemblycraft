; test_mobs.asm - mob ray picking, damage and drops, zombie attacks and parries, elites, villagers,
; the Fallen King, kill rewards, spawn rules, mob levels and elite affixes.
%include "common.inc"
default rel

global test_mob_raycast_hits, test_mob_hurt_pig_drops_food
global test_zombie_attacks_player, test_mob_spawn_rules
global test_zombie_windup_can_be_parried, test_elite_saved_and_tougher, test_npc_immune_and_not_saved
global test_boss_phases_slam_and_summons, test_mob_kill_awards_xp_and_coins
global test_mob_levels_and_scaling, test_elite_affixes

extern mobs, mobs_clear, mobs_step, mob_spawn, mobs_raycast, mob_hurt, mob_count_type, mob_count_kind
extern mob_spawn_elite, mob_spawn_npc, mob_is_hostile, mob_strike, mobs_save, mobs_load
extern player, body_init, rng_seed, world_clear, world_set, world_mark_all_dirty, blocks
extern game_mode, game_time, settings, surv, survival_reset, inv, inv_clear
extern drops, drops_clear, arrows, arrows_clear, tnt_clear, fx_clear
extern combat_reset, combat_hit_flags, combat_guard_t
extern rpg_state, rpg_reset, structures_reset, light_cells, light_fill_sky
extern mob_set_level, mob_level_for, mob_dmg_mult, mob_resist, mob_affix_name
extern combat_burn_t, combat_chill_t, combat_poison_t, combat_poison, rpg_stats
extern explode_dmg_mult

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
k_6:      dd 6.0
k_1_71:   dd 1.71
k_1_73:   dd 1.73
k_2_985:  dd 2.985
k_2_995:  dd 2.995
k_3_88:   dd 3.88
k_3_89:   dd 3.89

section .text

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; fixture(): the state every mob test starts from (after world_clear): rng seed 1234, no mobs,
; Survival at Normal difficulty, early morning, a level-1 character without a class (the level
; the mobs spawn at), fresh survival state, STONE floor at y = 10 for x, z in 0..31
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
    call    rpg_reset
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
; harder (rounded); it survives a save and load as an elite with its level and affixes, its health
; clamped to 2.5 x base; a record without the elite bit is a plain zombie whatever its affix bits
; say; villager records are not loaded. Its affix is pinned to ARMORED, which changes none of that
; (a rolled one could add health, speed, a shorter wind-up or elemental damage).
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
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax                    ; the elite
    cmp     dword [r12 + MOB.affix], 0
    je      .fail                       ; it rolled an affix
    mov     dword [r12 + MOB.affix], AFX_ARMORED
    mov     edi, ebx
    mov     esi, 1
    call    mob_set_level               ; the health of an elite with that affix
    cmp     dword [r12 + MOB.health], 50            ; 2.5 x 20
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 50
    jne     .fail
    cmp     dword [r12 + MOB.elite], 1
    jne     .fail
    movss   xmm0, [r12 + BODY.speed]    ; 1.15 x 2.6 = 2.99 (a rolled SWIFT: more)
    ucomiss xmm0, [k_2_9]
    jbe     .fail
    lea     rdi, [hdr]
    call    mobs_save
    cmp     dword [hdr + WORLDHDR.mob_count], 1
    jne     .fail
    cmp     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_ZOMBIE | MOB_ELITE_BIT | (1 << MS_LEVEL_SHIFT) | (AFX_ARMORED << MS_AFFIX_SHIFT)
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
    cmp     dword [r12 + MOB.affix], AFX_ARMORED
    jne     .fail
    cmp     dword [r12 + MOB.level], 1
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
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_ZOMBIE | (1 << MS_LEVEL_SHIFT) | (AFX_JUGGERNAUT << MS_AFFIX_SHIFT)
    call    mobs_clear                  ; without the elite bit: a plain 20, the affix bits are ignored
    lea     rdi, [hdr]
    call    mobs_load
    cmp     dword [mobs + MOB.elite], 0
    jne     .fail
    cmp     dword [mobs + MOB.affix], 0
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
    mov     dword [r12 + MOB.affix], AFX_ARMORED
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
    cmp     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_PIG | (1 << MS_LEVEL_SHIFT)   ; a level-1 pig
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
; Hostile mobs drop coins (one every other kill: 1 + level / 10, an elite 3-5 + level / 5; gold find
; multiplies them); the 8th kill of a dungeon's mobs clears it; the Fallen King drops 30 + his level
; coins and 4 diamonds (his gear is gear.asm's) and is recorded.
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
    mov     dword [r12 + MOB.tagged], 0 ; a tick of burning (HF_DOT): it still tags the mob and raises
    mov     dword [r12 + MOB.bar], 0    ; its bar, but opens no hurt window and shoves and lifts nothing
    mov     dword [r12 + MOB.hurt], 0
    mov     dword [r12 + BODY.kbz], 0
    mov     dword [r12 + BODY.on_ground], 1
    mov     dword [r12 + BODY.vy], 0
    mov     byte [combat_hit_flags], HF_PLAYER | HF_DOT | (ELEM_FIRE << HF_ELEM_SHIFT)
    mov     edi, ebx
    mov     esi, 2
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.health], 17            ; 19 - 2
    jne     .fail
    cmp     dword [r12 + MOB.hurt], 0
    jne     .fail
    cmp     dword [r12 + BODY.kbz], 0
    jne     .fail
    cmp     dword [r12 + BODY.vy], 0
    jne     .fail
    cmp     dword [r12 + MOB.tagged], 200
    jne     .fail
    cmp     dword [r12 + MOB.bar], 180
    jne     .fail
    cmp     byte [combat_hit_flags], 0
    jne     .fail
    mov     byte [combat_hit_flags], HF_PLAYER | HF_DOT     ; the next tick lands at once
    mov     edi, ebx
    mov     esi, 2
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.health], 15
    jne     .fail
    mov     byte [combat_hit_flags], HF_PLAYER | HF_DOT     ; a burning kill pays XP like any other
    mov     edi, ebx
    mov     esi, 100
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.type], MOB_NONE
    jne     .fail
    cmp     dword [rpg_state + RPGSAVE.xp], 20
    jne     .fail
    SPAWN   MOB_PIG, k_5_5, k_5_5       ; a burning animal does not bolt, a blow sends it fleeing
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     byte [combat_hit_flags], HF_DOT
    mov     edi, ebx
    mov     esi, 1
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.panic], 0
    jne     .fail
    mov     edi, ebx
    mov     esi, 1
    xorps   xmm0, xmm0
    movss   xmm1, [k_one]
    call    mob_hurt
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.panic], 180
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
    call    drops_clear                 ; level 10 with 100 % gold find: a plain kill's coin pile is
    mov     byte [rpg_state + RPGSAVE.level], 10    ; (1 + 10 / 10) * 2 = 4 coins (untagged kills
    lea     rax, [rpg_stats]            ; pay no XP, so nothing recomputes the stat)
    mov     dword [rax + STAT_GOLD_FIND*4], 100
    mov     ebx, 12
.round10:
    xor     edi, edi
    call    kill_zombie
    test    eax, eax
    jnz     .fail
    dec     ebx
    jnz     .round10
    mov     edi, GOLD_COIN
    call    drops_of
    test    eax, eax
    jz      .fail                       ; 12 kills: some piles
    lea     ecx, [rax*4]
    cmp     edx, ecx                    ; ...each of 4 coins
    jne     .fail
    call    drops_clear                 ; an elite of level 10: (3 + rng % 3 + 10 / 5) * 2 = 10..14
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     edi, eax
    mov     esi, 1000
    call    strike
    cmp     eax, 1
    jne     .fail
    mov     edi, GOLD_COIN
    call    drops_of
    cmp     eax, 1
    jne     .fail
    sub     edx, 10
    cmp     edx, 4
    ja      .fail
    call    rpg_reset                   ; level 1 again, no gold find
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
    cmp     byte [rpg_state + RPGSAVE.level], 1     ; and 525 XP (500 + 25 for his level 1) raised the level
    jbe     .fail
    mov     edi, DIAMOND
    call    drops_of
    cmp     edx, 4
    jne     .fail
    mov     edi, GOLD_COIN
    call    drops_of
    cmp     edx, 31                     ; 30 + his level 1
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

; ---- 0.8: mob levels and elite affixes ---------------------------------------------------------

; LEVEL_FOR origin, level: mob_level_for(origin) must come to `level`
%macro LEVEL_FOR 2
    mov     edi, %1
    call    mob_level_for
    cmp     eax, %2
    jne     .fail
%endmacro

; RESIST type, elem, percent: mob_resist(type, elem) must come to `percent`
%macro RESIST 3
    mov     edi, %1
    mov     esi, %2
    call    mob_resist
    cmp     eax, %3
    jne     .fail
%endmacro

; stand_player(): no mobs, the player standing at (16.5, 11, 16.5)
stand_player:
    sub     rsp, 8
    call    mobs_clear
    SETF    [player + BODY.x], 16.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 16.5
    add     rsp, 8
    ret

; fresh_fight(): a new fight: no mobs, the player standing at (16.5, 11, 16.5) at full health with
; his guard down and no armor, nothing burning, chilled or poisoned, night
fresh_fight:
    sub     rsp, 8
    call    stand_player
    call    survival_reset
    call    combat_reset
    call    inv_clear
    mov     dword [combat_burn_t], 0
    mov     dword [combat_chill_t], 0
    mov     dword [combat_poison_t], 0
    mov     dword [combat_poison], 0
    mov     dword [game_time], 40000
    add     rsp, 8
    ret

; zombie_blow(edi affix, esi mob health or 0, edx fire resistance %) -> eax the player's health after
; the blow of a Normal zombie in reach of him (level 1, no armor, nothing burning, chilled or
; poisoned yet): the zombie stays a plain one with its affix bits poked to `affix`, and with health
; `esi` when that is not 0; the player's fire resistance is poked to `edx` for the blow. It lives
; on in slot 0. -1 when it did not spawn.
zombie_blow:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    call    fresh_fight
    lea     rax, [rpg_stats]
    mov     [rax + STAT_RES_FIRE*4], r13d
    SPAWN   MOB_ZOMBIE, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    mov     [mobs + MOB.affix], ebx     ; slot 0: stand_player emptied them all
    test    r12d, r12d
    jz      .steps
    mov     [mobs + MOB.health], r12d
.steps:
    mov     ebx, 21                     ; the arm goes up, the blow lands 20 steps later
.step:
    call    mobs_step
    dec     ebx
    jnz     .step
    mov     eax, [surv + SURVIVAL.health]
    jmp     .ret
.fail:
    mov     eax, -1
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; spider_bite(edi affix) -> eax the player's health after the bite of a Normal spider in reach of
; him (level 1, a fresh fight), its affix bits poked to `affix`; -1 when it did not spawn. It
; lives on in slot 0.
spider_bite:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    fresh_fight
    SPAWN   MOB_SPIDER, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    mov     [mobs + MOB.affix], ebx     ; slot 0
    mov     ebx, 13                     ; it rears up (1), the bite lands 12 steps later
.step:
    call    mobs_step
    dec     ebx
    jnz     .step
    mov     eax, [surv + SURVIVAL.health]
    jmp     .ret
.fail:
    mov     eax, -1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; parried_zombie(edi affix) -> eax the stun of a zombie (its affix bits poked to `affix`) whose
; blow the player parries with a guard raised on the last step; -1 when it did not spawn. It
; lives on in slot 0.
parried_zombie:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    fresh_fight
    SETF    [player + BODY.yaw], 90.0   ; facing +x, towards the zombie: its blow is frontal
    SPAWN   MOB_ZOMBIE, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    mov     [mobs + MOB.affix], ebx     ; slot 0
    mov     ebx, 20                     ; the arm goes up, the blow is due on the next step
.raise:
    call    mobs_step
    dec     ebx
    jnz     .raise
    mov     dword [combat_guard_t], 0   ; the guard comes up on the very last step
    call    mobs_step
    call    fx_clear                    ; a parry throws sparks
    mov     eax, [mobs + MOB.stun]
    jmp     .ret
.fail:
    mov     eax, -1
.ret:
    SETF    [player + BODY.yaw], 0.0
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; elite_windup(edi affix) -> eax the wind-up steps of an elite zombie, its affix poked to `affix`,
; after one step in reach of the player; -1 when it did not spawn
elite_windup:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    stand_player
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_17_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .none
    mov     [mobs + MOB.affix], ebx     ; slot 0
    call    mobs_step
    mov     eax, [mobs + MOB.windup]
    jmp     .ret
.none:
    mov     eax, -1
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; skeleton_shot(edi affix) -> eax 1 when a skeleton 8 blocks from the player, its affix bits
; poked to `affix`, shot an arrow in one step (arrows[0], the only one)
skeleton_shot:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    arrows_clear
    call    stand_player
    call    combat_reset
    mov     dword [game_time], 40000
    SPAWN   MOB_SKELETON, k_16_5, k_8_5
    test    eax, eax
    js      .none
    mov     [mobs + MOB.affix], ebx     ; slot 0
    call    mobs_step
    xor     eax, eax
    cmp     dword [arrows + ARROWENT.live], 0
    setne   al
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; affix_rolls(edi player level, esi count) -> eax 0 when 64 elite zombies spawned at that player
; level each carry exactly `count` affixes (distinct kinds: the bits of MOB.affix, one of the 8)
; and the speed that goes with their SWIFT bit; edx = the kinds rolled together, ecx = how many
; of the 64 were SWIFT.
; rbx = rolls left, r12d = count, r13d = kinds seen, r14d = SWIFT seen, r15 = the mob
affix_rolls:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     [rpg_state + RPGSAVE.level], dil
    mov     r12d, esi
    xor     r13d, r13d
    xor     r14d, r14d
    mov     ebx, 64
.roll:
    call    mobs_clear
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     r15, rax
    cmp     dword [r15 + MOB.elite], 1
    jne     .fail
    mov     eax, [r15 + MOB.affix]
    cmp     eax, 255
    ja      .fail
    or      r13d, eax
    xor     ecx, ecx                    ; count the set bits
.bits:
    test    eax, eax
    jz      .counted
    lea     edx, [rax - 1]
    and     eax, edx                    ; clears the lowest one
    inc     ecx
    jmp     .bits
.counted:
    cmp     ecx, r12d
    jne     .fail
    movss   xmm0, [r15 + BODY.speed]
    test    dword [r15 + MOB.affix], AFX_SWIFT
    jz      .plain
    inc     r14d
    ucomiss xmm0, [k_3_88]              ; 2.6 * 1.15 * 1.3 = 3.887
    jbe     .fail
    ucomiss xmm0, [k_3_89]
    jae     .fail
    jmp     .rolled
.plain:
    ucomiss xmm0, [k_2_985]             ; 2.6 * 1.15 = 2.99
    jbe     .fail
    ucomiss xmm0, [k_2_995]
    jae     .fail
.rolled:
    dec     ebx
    jnz     .roll
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     edx, r13d
    mov     ecx, r14d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; night_census() -> eax live mobs, edx elites among them, ecx elites whose affix is not exactly
; one kind
night_census:
    xor     eax, eax
    xor     edx, edx
    xor     r8d, r8d
    lea     rcx, [mobs]
    mov     esi, MAX_MOBS
.l:
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .next
    inc     eax
    cmp     dword [rcx + MOB.elite], 0
    je      .next
    inc     edx
    mov     edi, [rcx + MOB.affix]
    lea     r9d, [rdi - 1]
    test    edi, r9d
    jnz     .bad                        ; two or more kinds
    test    edi, edi
    jnz     .next                       ; exactly one
.bad:
    inc     r8d
.next:
    add     rcx, MOB_size
    dec     esi
    jnz     .l
    mov     ecx, r8d
    ret

; A mob starts at the player's level (a villager at 1; a dungeon's mobs two above, the crypt boss
; three above and at least 20) with the health of that level: a level-10 zombie 20 * (1 + 0.15 * 9)
; = 47, level 12 53, an elite of level 10 round(117.5) = 118, the Fallen King at 20 300 * 3.85 =
; 1155; mob_set_level heals it fully. A level-10 zombie's blow on the unarmored Normal player is
; round(3 * 1.72) = 5, an elite's round(round(3 * 1.5) * 1.72) = 7. A save keeps the level and the
; affixes in the type word (an elite of level 12 with MOLTEN | SWIFT reads back as such; a record
; without them takes the player's level and no affix).
test_mob_levels_and_scaling:
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
    mov     byte [rpg_state + RPGSAVE.class], CLASS_WARRIOR
    mov     byte [rpg_state + RPGSAVE.level], 10    ; poked: the stats stay as they are
    LEVEL_FOR 0, 10
    LEVEL_FOR 1, 12
    LEVEL_FOR 6, 12
    LEVEL_FOR 7, 10
    LEVEL_FOR 99, 20
    mov     byte [rpg_state + RPGSAVE.level], 25
    LEVEL_FOR 99, 28
    mov     byte [rpg_state + RPGSAVE.level], 10
    mov     edi, 1                      ; the blows' scale: 1.0 at level 1 (and below), 1.72 at 10
    call    mob_dmg_mult
    ucomiss xmm0, [k_one]
    jne     .fail
    xor     edi, edi
    call    mob_dmg_mult
    ucomiss xmm0, [k_one]
    jne     .fail
    mov     edi, 10
    call    mob_dmg_mult
    ucomiss xmm0, [k_1_71]
    jbe     .fail
    ucomiss xmm0, [k_1_73]
    jae     .fail
    lea     rdi, [mobs]                 ; a freed slot full of stale bytes: a spawn clears all the new fields
    mov     ecx, MOB_size
    mov     al, 0xFF
    rep     stosb
    mov     dword [mobs + MOB.type], MOB_NONE
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax                    ; a zombie at the player's level 10
    cmp     dword [r12 + MOB.level], 10
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 47
    jne     .fail
    cmp     dword [r12 + MOB.health], 47
    jne     .fail
    lea     rcx, [r12 + MOB.affix]      ; affix, statuses and timers: 15 fields, all zero
    mov     edx, (MOB_size - MOB.affix) / 4
.fresh:
    cmp     dword [rcx], 0
    jne     .fail
    add     rcx, 4
    dec     edx
    jnz     .fresh
    mov     dword [r12 + MOB.health], 5
    mov     edi, ebx
    mov     esi, 12
    call    mob_set_level               ; level 12: 20 * 2.65, healed
    cmp     dword [r12 + MOB.level], 12
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 53
    jne     .fail
    cmp     dword [r12 + MOB.health], 53
    jne     .fail
    mov     edi, ebx
    xor     esi, esi
    call    mob_set_level               ; levels run from 1...
    cmp     dword [r12 + MOB.level], 1
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 20
    jne     .fail
    mov     edi, ebx
    mov     esi, 1000
    call    mob_set_level               ; ...to 255, the one byte a save keeps
    cmp     dword [r12 + MOB.level], 255
    jne     .fail
    mov     edi, MAX_MOBS - 1           ; an empty slot and a slot that does not exist stay as they are
    mov     esi, 30
    call    mob_set_level
    cmp     dword [mobs + (MAX_MOBS - 1) * MOB_size + MOB.type], MOB_NONE
    jne     .fail
    cmp     dword [mobs + (MAX_MOBS - 1) * MOB_size + MOB.level], 0
    jne     .fail
    mov     edi, MAX_MOBS
    mov     esi, 30
    call    mob_set_level
    call    mobs_clear
    mov     edi, MOB_MERCHANT           ; a villager stays at level 1 with 20 health
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    mob_spawn_npc
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    cmp     dword [rax + MOB.level], 1
    jne     .fail
    cmp     dword [rax + MOB.max_health], 20
    jne     .fail
    call    mobs_clear
    mov     edi, MOB_ZOMBIE             ; an elite of level 10, its affix pinned to a plain one
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     dword [r12 + MOB.affix], AFX_ARMORED
    mov     edi, ebx
    mov     esi, 10
    call    mob_set_level
    cmp     dword [r12 + MOB.max_health], 118   ; round(20 * 2.35 * 2.5 = 117.5), in floats, once
    jne     .fail
    call    mobs_clear
    SPAWN   MOB_BOSS, k_16_5, k_16_5    ; the Fallen King, spawned at 10, then born in the crypt
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    cmp     dword [r12 + MOB.max_health], 705       ; 300 * 2.35
    jne     .fail
    mov     edi, 99
    call    mob_level_for
    mov     edi, ebx
    mov     esi, eax
    call    mob_set_level
    cmp     dword [r12 + MOB.level], 20
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 1155      ; 300 * 3.85
    jne     .fail
    cmp     dword [r12 + MOB.health], 1155
    jne     .fail
    call    stand_player                ; a level-10 zombie in reach of the unarmored player
    SPAWN   MOB_ZOMBIE, k_17_5, k_16_5
    test    eax, eax
    js      .fail
    mov     ebx, 21                     ; the arm goes up, the blow lands 20 steps later
.blow:
    call    mobs_step
    dec     ebx
    jnz     .blow
    cmp     dword [surv + SURVIVAL.health], 15      ; 20 - round(3 * 1.72)
    jne     .fail
    xor     edi, edi                    ; a spider's bite (Normal: 2): round(2 * 1.72) = 3
    call    spider_bite
    cmp     eax, 17
    jne     .fail
    call    stand_player                ; an elite: 3 * 1.5 -> 4, then x 1.72 -> 7
    call    survival_reset
    call    combat_reset
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_17_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     dword [mobs + MOB.affix], AFX_ARMORED
    mov     ebx, 17                     ; wind-up 16 steps
.eblow:
    call    mobs_step
    dec     ebx
    jnz     .eblow
    cmp     dword [surv + SURVIVAL.health], 13      ; 20 - round(round(3 * 1.5) * 1.72)
    jne     .fail
    call    mobs_clear                  ; the save: an elite of level 12 with MOLTEN | SWIFT
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_8_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_8_5]
    call    mob_spawn_elite
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     dword [r12 + MOB.affix], AFX_MOLTEN | AFX_SWIFT
    mov     edi, ebx
    mov     esi, 12
    call    mob_set_level
    cmp     dword [r12 + MOB.max_health], 132       ; round(20 * 2.65 * 2.5 = 132.5), to even
    jne     .fail
    mov     dword [r12 + MOB.health], 100
    lea     rdi, [hdr]
    call    mobs_save
    cmp     dword [hdr + WORLDHDR.mob_count], 1
    jne     .fail
    cmp     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_ZOMBIE | MOB_ELITE_BIT | (12 << MS_LEVEL_SHIFT) | ((AFX_MOLTEN | AFX_SWIFT) << MS_AFFIX_SHIFT)
    jne     .fail
    call    mobs_clear
    lea     rdi, [hdr]
    call    mobs_load
    lea     r12, [mobs]
    cmp     dword [r12 + MOB.type], MOB_ZOMBIE
    jne     .fail
    cmp     dword [r12 + MOB.elite], 1
    jne     .fail
    cmp     dword [r12 + MOB.level], 12
    jne     .fail
    cmp     dword [r12 + MOB.affix], AFX_MOLTEN | AFX_SWIFT
    jne     .fail
    cmp     dword [r12 + MOB.max_health], 132
    jne     .fail
    cmp     dword [r12 + MOB.health], 100
    jne     .fail
    movss   xmm0, [r12 + BODY.speed]    ; 2.6 * 1.15 * 1.3 = 3.887
    ucomiss xmm0, [k_3_88]
    jbe     .fail
    ucomiss xmm0, [k_3_89]
    jae     .fail
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_ZOMBIE | MOB_ELITE_BIT
    call    mobs_clear                  ; an older record: the player's level 10, no affix
    lea     rdi, [hdr]
    call    mobs_load
    cmp     dword [mobs + MOB.level], 10
    jne     .fail
    cmp     dword [mobs + MOB.affix], 0
    jne     .fail
    cmp     dword [mobs + MOB.max_health], 118
    jne     .fail
    cmp     dword [mobs + MOB.health], 100
    jne     .fail
    mov     dword [hdr + WORLDHDR.mobs + MOBSAVE.type], MOB_ZOMBIE
    call    mobs_clear
    lea     rdi, [hdr]
    call    mobs_load
    cmp     dword [mobs + MOB.level], 10
    jne     .fail
    cmp     dword [mobs + MOB.health], 47           ; the saved 100 clamps to a plain level-10 zombie's
    jne     .fail
    call    fresh_fight                 ; a level-10 creeper next to him: the fuse burns down, it blows
    mov     edi, MOB_CREEPER
    movss   xmm0, [k_18_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    mob_spawn
    test    eax, eax
    js      .fail
    mov     ebx, 95
.fuse:
    call    mobs_step
    dec     ebx
    jnz     .fuse
    mov     edi, MOB_CREEPER
    call    mob_count_type
    test    eax, eax
    jnz     .fail
    cmp     dword [explode_dmg_mult], 0 ; the blast's scale did not outlive it
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jge     .fail                       ; (and hurt him)
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    call    fx_clear
    call    tnt_clear
    call    combat_reset
    call    rpg_reset
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Elites roll affixes: one below level 15, two from 15 on, never the same kind twice, every kind
; possible; a SWIFT elite moves 2.6 * 1.15 * 1.3 and winds up in 12 steps instead of 16; a
; JUGGERNAUT has 1.5 x the health (75) and a hit shoves it not at all. A Normal zombie's blow of 3
; gains half of it as fire (MOLTEN: 5 in all, the player burns; 4 with 50 % fire resistance), 0.3
; as frost (FROZEN: 4, chilled), 0.3 as poison (VENOMOUS: 4, poisoned), 0.5 as shock (STORM: 5);
; a VAMPIRIC one heals half of what it deals (10 -> 11, never past its maximum). A skeleton's
; arrow carries the whole damage and the element of its first elemental affix. mob_resist and
; mob_affix_name. 4 % of a night's spawns are elite, with one affix at level 1.
test_elite_affixes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    fixture
    call    reset_player
    call    combat_reset
    call    inv_clear                   ; no armor
    mov     dword [game_time], 40000
    mov     edi, 5                      ; one affix below level 15...
    mov     esi, 1
    call    affix_rolls
    test    eax, eax
    jnz     .fail
    mov     r12d, edx                   ; the kinds seen
    mov     r13d, ecx                   ; the SWIFT ones
    mov     edi, 14
    mov     esi, 1
    call    affix_rolls
    test    eax, eax
    jnz     .fail
    or      r12d, edx
    add     r13d, ecx
    mov     edi, 15                     ; ...two from level 15 on, never the same kind twice
    mov     esi, 2
    call    affix_rolls
    test    eax, eax
    jnz     .fail
    or      r12d, edx
    add     r13d, ecx
    mov     edi, 20
    mov     esi, 2
    call    affix_rolls
    test    eax, eax
    jnz     .fail
    or      r12d, edx
    add     r13d, ecx
    cmp     r12d, 0xFF                  ; every one of the 8 kinds came up
    jne     .fail
    test    r13d, r13d
    jz      .fail                       ; some SWIFT ones...
    cmp     r13d, 4 * 64
    jae     .fail                       ; ...and some that were not
    mov     byte [rpg_state + RPGSAVE.level], 1
    mov     edi, AFX_SWIFT              ; a SWIFT elite winds up in 3/4 of 16 steps
    call    elite_windup
    cmp     eax, 12
    jne     .fail
    mov     edi, AFX_ARMORED            ; the others in 16
    call    elite_windup
    cmp     eax, 16
    jne     .fail
    call    mobs_clear                  ; JUGGERNAUT: 20 * 2.5 * 1.5 = 75 health, no knockback
    SPAWN   MOB_ZOMBIE, k_8_5, k_8_5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, eax
    call    mob_ptr
    mov     r12, rax
    mov     dword [r12 + MOB.elite], 1
    mov     dword [r12 + MOB.affix], AFX_JUGGERNAUT
    mov     edi, ebx
    mov     esi, 1
    call    mob_set_level
    cmp     dword [r12 + MOB.max_health], 75
    jne     .fail
    cmp     dword [r12 + MOB.health], 75
    jne     .fail
    mov     edi, ebx
    mov     esi, 5
    call    strike
    cmp     eax, 1
    jne     .fail
    cmp     dword [r12 + MOB.health], 70
    jne     .fail
    cmp     dword [r12 + BODY.kbx], 0
    jne     .fail
    cmp     dword [r12 + BODY.kbz], 0
    jne     .fail                       ; it stood firm...
    mov     dword [r12 + MOB.affix], 0
    mov     edi, ebx
    mov     esi, 5
    call    strike
    movss   xmm0, [r12 + BODY.kbz]
    ucomiss xmm0, [k_6]                 ; ...where an ordinary mob is shoved at 6 blocks/s
    jne     .fail
    xor     edi, edi                    ; a parried zombie reels back and is stunned for 50 steps...
    call    parried_zombie
    cmp     eax, 50
    jne     .fail
    movss   xmm0, [mobs + BODY.kbx]
    ucomiss xmm0, [k_one]
    jbe     .fail
    mov     edi, AFX_JUGGERNAUT         ; ...a juggernaut shrugs the riposte off
    call    parried_zombie
    test    eax, eax
    jnz     .fail
    cmp     dword [mobs + BODY.kbx], 0
    jne     .fail
    xor     edi, edi                    ; a plain zombie's blow: 20 - 3
    xor     esi, esi
    xor     edx, edx
    call    zombie_blow
    cmp     eax, 17
    jne     .fail
    mov     eax, [combat_burn_t]
    or      eax, [combat_chill_t]
    or      eax, [combat_poison_t]
    jnz     .fail
    mov     edi, AFX_MOLTEN             ; MOLTEN: + round(1.5) = 2 fire, and the player burns
    xor     esi, esi
    xor     edx, edx
    call    zombie_blow
    cmp     eax, 15
    jne     .fail
    cmp     dword [combat_burn_t], 180
    jne     .fail
    mov     edi, AFX_MOLTEN             ; 50 % fire resistance halves the part: 1
    xor     esi, esi
    mov     edx, 50
    call    zombie_blow
    cmp     eax, 16
    jne     .fail
    mov     edi, AFX_FROZEN             ; FROZEN: + round(0.9) = 1 frost, chilled
    xor     esi, esi
    xor     edx, edx
    call    zombie_blow
    cmp     eax, 16
    jne     .fail
    cmp     dword [combat_chill_t], 120
    jne     .fail
    mov     edi, AFX_VENOMOUS           ; VENOMOUS: + 1 poison, one stack of it
    xor     esi, esi
    xor     edx, edx
    call    zombie_blow
    cmp     eax, 16
    jne     .fail
    cmp     dword [combat_poison], 1
    jne     .fail
    cmp     dword [combat_poison_t], 0
    jle     .fail
    mov     edi, AFX_STORM              ; STORM: + round(1.5) = 2 shock, no status
    xor     esi, esi
    xor     edx, edx
    call    zombie_blow
    cmp     eax, 15
    jne     .fail
    mov     eax, [combat_burn_t]
    or      eax, [combat_chill_t]
    or      eax, [combat_poison_t]
    jnz     .fail
    xor     edi, edi                    ; a Normal spider's bite of 2...
    call    spider_bite
    cmp     eax, 18
    jne     .fail
    mov     edi, AFX_MOLTEN             ; ...MOLTEN: + round(1.0) = 1 fire, burning
    call    spider_bite
    cmp     eax, 17
    jne     .fail
    cmp     dword [combat_burn_t], 180
    jne     .fail
    mov     edi, AFX_VAMPIRIC           ; VAMPIRIC: half of the 3 dealt (1) heals it, 10 -> 11...
    mov     esi, 10
    xor     edx, edx
    call    zombie_blow
    cmp     eax, 17
    jne     .fail
    cmp     dword [mobs + MOB.health], 11
    jne     .fail
    mov     edi, AFX_VAMPIRIC           ; ...but never past its maximum
    xor     esi, esi
    xor     edx, edx
    call    zombie_blow
    cmp     dword [mobs + MOB.health], 20
    jne     .fail
    xor     edi, edi                    ; a skeleton's arrow: 3, no element...
    call    skeleton_shot
    test    eax, eax
    jz      .fail
    cmp     dword [arrows + ARROWENT.damage], 3
    jne     .fail
    cmp     dword [arrows + ARROWENT.flags], 0
    jne     .fail
    mov     edi, AFX_STORM | AFX_FROZEN | AFX_VAMPIRIC
    call    skeleton_shot               ; ...3 + 1 frost + 2 shock, frost (the first of them)
    test    eax, eax
    jz      .fail
    cmp     dword [arrows + ARROWENT.damage], 6
    jne     .fail
    cmp     dword [arrows + ARROWENT.flags], ELEM_FROST << AF_ELEM_SHIFT
    jne     .fail
    RESIST  MOB_ZOMBIE, ELEM_PHYS, 0
    RESIST  MOB_ZOMBIE, ELEM_FIRE, -50
    RESIST  MOB_ZOMBIE, ELEM_POISON, 25
    RESIST  MOB_CREEPER, ELEM_FROST, -25
    RESIST  MOB_CREEPER, ELEM_SHOCK, 50
    RESIST  MOB_SKELETON, ELEM_FROST, 25
    RESIST  MOB_SKELETON, ELEM_POISON, 100
    RESIST  MOB_SPIDER, ELEM_FIRE, -25
    RESIST  MOB_SPIDER, ELEM_POISON, 100
    RESIST  MOB_BOSS, ELEM_PHYS, 20
    RESIST  MOB_BOSS, ELEM_SHOCK, 20
    RESIST  MOB_BOSS, ELEM_POISON, 50
    RESIST  MOB_PIG, ELEM_FIRE, 0
    RESIST  MOB_NONE, ELEM_FIRE, 0      ; no such type, no such element
    RESIST  MOB_BOSS + 1, ELEM_FIRE, 0
    RESIST  MOB_ZOMBIE, NUM_ELEMS, 0
    xor     edi, edi
    call    mob_affix_name
    cmp     dword [rax], 'Molt'
    jne     .fail
    mov     edi, 6
    call    mob_affix_name
    cmp     dword [rax], 'Jugg'
    jne     .fail
    mov     edi, 7
    call    mob_affix_name
    cmp     dword [rax], 'Armo'
    jne     .fail
    mov     edi, 8
    call    mob_affix_name
    cmp     byte [rax], 0               ; no such affix: an empty string
    jne     .fail
    lea     rdi, [blocks + (10 << 16)]  ; 4 % of the night's spawns: GRASS for them to stand on
    mov     ecx, WORLD_X * WORLD_Z
    mov     al, GRASS
    rep     stosb
    call    world_mark_all_dirty
    call    stand_player
    SETF    [player + BODY.x], 128.5
    SETF    [player + BODY.z], 128.5
    mov     dword [game_time], 40020    ; a multiple of 60: the spawner acts on every step
    xor     r12d, r12d                  ; mobs spawned
    xor     r13d, r13d                  ; elites among them
    mov     ebx, 500
.night:
    call    mobs_clear
    call    mobs_step
    call    night_census
    add     r12d, eax
    add     r13d, edx
    test    ecx, ecx
    jnz     .fail                       ; every elite has exactly one affix at level 1
    dec     ebx
    jnz     .night
    cmp     r12d, 300                   ; the spawner found a place most of the time
    jb      .fail
    imul    eax, r13d, 100
    cmp     eax, r12d
    jb      .fail                       ; at least 1 % elite...
    imul    ecx, r12d, 10
    cmp     eax, ecx
    ja      .fail                       ; ...and at most 10 %
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    mobs_clear
    call    arrows_clear
    call    fx_clear
    call    combat_reset
    call    rpg_reset
    mov     dword [combat_burn_t], 0
    mov     dword [combat_chill_t], 0
    mov     dword [combat_poison_t], 0
    mov     dword [combat_poison], 0
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
