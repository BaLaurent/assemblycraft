; test_melee.asm - guard and parry, the dodge roll, melee combos, crits and backstabs, stamina and
; mana regeneration, max health; the damage pipeline (combat_calc / combat_hit_mob, projectiles and
; blasts), heavy attacks, attack speed and the weapon preview, and what the player suffers and
; defends against (burn, poison, chill, thorns, Mana Shield, Phoenix, blocks, falls, Juggernaut).
%include "common.inc"
default rel

global test_guard_blocks_and_parries, test_dodge_iframes_and_stamina
global test_melee_combo_crit_backstab, test_stamina_mana_regen_and_max_health
global test_damage_pipeline, test_heavy_attack_and_speed, test_player_statuses_and_defenses

extern combat_mana, combat_stamina, combat_guard_t, combat_guard_break_t, combat_dodge_t
extern combat_dodge_cd, combat_attack_cd, combat_combo, combat_riposte_t, combat_crit_next_t
extern combat_warcry_t, combat_blade_t, combat_stealth_t, combat_spend_t, combat_hitstop
extern combat_reset, combat_step, combat_spend, combat_set_guard, combat_dodge
extern combat_melee, combat_speed_mult, player_take_hit
extern rpg_state, rpg_stats, rpg_reset, rpg_recompute
extern surv, surv_max_health, survival_reset, survival_damage, survival_step, game_mode, settings
extern player, body_init, world_clear, rng_seed
extern mobs, mobs_clear, mob_spawn, drops_clear
extern inv, inv_sel, inv_clear
extern combat_hit_mob, combat_calc, combat_heavy, combat_pay, combat_weapon_preview, combat_kb_mult
extern combat_attacker, combat_player_status
extern combat_burn_t, combat_chill_t, combat_poison_t, combat_poison, combat_phoenix_cd
extern combat_hit_flags
extern survival_dot, survival_land, rpg_keystones, gear_powers, abilities_cd
extern arrows, arrows_clear, arrows_spawn, arrows_step, explode_at, explode_magic, explode_dmg_mult
extern world_set
extern game_frame, frame_input, input_captured, game_heavy_s, game_bow_charge, game_open_screen
extern game_time, world_get

section .rodata
align 16
absmask:  dd 0x7FFFFFFF, 0, 0, 0
align 4
k_eps:    dd 0.005
k_0:      dd 0.0
k_0_05:   dd 0.05
k_0_09:   dd 0.09
k_0_1:    dd 0.1
k_0_3:    dd 0.3
k_0_4:    dd 0.4
k_1_8:    dd 1.8
k_3_5:    dd 3.5
k_4:      dd 4.0
k_4_317:  dd 4.317
k_11:     dd 11.0
k_14_5:   dd 14.5                       ; 2 blocks in front of the player (he looks along -z)
k_15_5:   dd 15.5                       ; 1 block in front
k_16:     dd 16.0
k_16_5:   dd 16.5
k_18_5:   dd 18.5                       ; 2 blocks behind
k_20:     dd 20.0
k_180:    dd 180.0
k_30:     dd 30.0
k_48:     dd 48.0
k_50:     dd 50.0
k_70:     dd 70.0
k_70_333: dd 70.33333
k_75:     dd 75.0
k_80:     dd 80.0
k_82:     dd 82.0
k_90_333: dd 90.33333
k_100:    dd 100.0
k_m1:     dd -1.0
k_m6:     dd -6.0
k_m10_8:  dd -10.8
k_m16:    dd -16.0
; floats of the pipeline and defense tests (f<value>, the point written _; fm = minus)
f1:       dd 1.0
f2_5:     dd 2.5
f3:       dd 3.0
f5:       dd 5.0
f6:       dd 6.0
f8:       dd 8.0
f10:      dd 10.0
f11_5:    dd 11.5                       ; chest height of an arrow's flight
f11_9:    dd 11.9                       ; the middle of a standing player's or zombie's body at y = 11
f12:      dd 12.0
f12_5:    dd 12.5
f13:      dd 13.0
f15:      dd 15.0
f17:      dd 17.0
f17_5:    dd 17.5
f19_5:    dd 19.5
f20_5:    dd 20.5
f25:      dd 25.0
f40_5:    dd 40.5
f8_4:     dd 8.4
f88:      dd 88.0
f94:      dd 94.0
fm30:     dd -30.0
f0_6:     dd 0.6
k_0_12:   dd 0.12                       ; hit-stop of a heavy attack
k_m15:    dd -15.0                      ; a heavy attack throws 2.5 times a light strike's 6 along -z
k_m16_2:  dd -16.2                      ; a warhammer's third strike: 6 * 1.8 * 1.5 along -z
k_step:   dd 0.016666668                ; one simulation step
f0_5:     dd 0.5
f50:      dd 50.0
f50_5:    dd 50.5

section .bss
align 4
inp: resb INPUT_size
tmp: resd 1
pv:  resd 4                              ; combat_weapon_preview's answer

section .text

; fail unless |float at %1 - float constant %2| < 0.005 (NaN fails)
%macro FNEAR 2
    movss   xmm0, %1
    subss   xmm0, [%2]
    andps   xmm0, [absmask]
    ucomiss xmm0, [k_eps]
    jp      .fail
    jae     .fail
%endmacro

; fail unless the dword at %1 equals %2
%macro CHK 2
    cmp     dword %1, %2
    jne     .fail
%endmacro

; fixture(): the state every melee test starts from, after world_clear: no mobs, drops or items,
; class none (20 health, 100 stamina, no mana), Survival at Normal difficulty, fresh survival and
; combat state, the player (0.3 x 1.8) at (16.5, 11, 16.5) on the ground looking along -z (yaw 0)
fixture:
    sub     rsp, 8
    mov     edi, 1234
    call    rng_seed
    call    mobs_clear
    call    drops_clear
    call    inv_clear
    mov     dword [inv_sel], 0
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [rpg_keystones], 0
    mov     dword [gear_powers], 0
    call    rpg_reset
    call    survival_reset
    call    combat_reset
    lea     rdi, [player]
    movss   xmm0, [k_0_3]
    movss   xmm1, [k_1_8]
    movss   xmm2, [k_4_317]
    call    body_init
    mov     dword [player + BODY.x], __float32__(16.5)
    mov     dword [player + BODY.y], __float32__(11.0)
    mov     dword [player + BODY.z], __float32__(16.5)
    mov     dword [player + BODY.on_ground], 1
    add     rsp, 8
    ret

; cleanup(): leave no mobs, drops, items, class or combat state behind
cleanup:
    sub     rsp, 8
    call    mobs_clear
    mov     dword [rpg_keystones], 0
    mov     dword [gear_powers], 0
    call    drops_clear
    call    inv_clear
    call    rpg_reset
    call    survival_reset
    call    combat_reset
    add     rsp, 8
    ret

; steps(edi n >= 1): n times combat_step(0)
steps:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
.l:
    xor     edi, edi
    call    combat_step
    dec     ebx
    jnz     .l
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; surv_steps(edi n >= 1): n times survival_step with no movement and no input
surv_steps:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    lea     rdi, [inp]
    mov     ecx, INPUT_size
    xor     eax, eax
    rep     stosb
.l:
    lea     rdi, [inp]
    xorps   xmm0, xmm0
    xor     esi, esi
    call    survival_step
    dec     ebx
    jnz     .l
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; hit(edi amount, xmm0 src_x, xmm1 src_z) -> eax: player_take_hit(amount, CAUSE_ZOMBIE, src) with
; the invulnerability of the previous hit cleared
hit:
    sub     rsp, 8
    mov     dword [surv + SURVIVAL.invuln], 0
    mov     esi, CAUSE_ZOMBIE
    call    player_take_hit
    add     rsp, 8
    ret

; HIT_FRONT / HIT_BEHIND amount -> eax: a hit from 2 blocks in front of / behind the player
%macro HIT_FRONT 1
    mov     edi, %1
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_14_5]
    call    hit
%endmacro
%macro HIT_BEHIND 1
    mov     edi, %1
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_18_5]
    call    hit
%endmacro

; spawn_zombie(xmm0 yaw) -> eax slot (0 after fixture, -1 on failure): a zombie one block in front
; of the player at y = 11 with that yaw and 100 health
spawn_zombie:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    movss   [rsp], xmm0
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_15_5]
    call    mob_spawn
    test    eax, eax
    js      .ret
    imul    ecx, eax, MOB_size
    lea     rdx, [mobs]
    add     rcx, rdx
    mov     edx, [rsp]
    mov     [rcx + BODY.yaw], edx
    mov     dword [rcx + MOB.health], 100
.ret:
    leave
    ret

; strike() -> eax damage dealt to mob 0 by combat_melee straight ahead (-z); 0 when refused. The
; mob's health is reset to 100 first so it never dies.
strike:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     rbx, [mobs]
    mov     dword [rbx + MOB.health], 100
    xor     edi, edi
    xorps   xmm0, xmm0
    movss   xmm1, [k_m1]
    call    combat_melee
    mov     eax, 100
    sub     eax, [rbx + MOB.health]
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; swing() -> eax combat_melee on slot 0 straight ahead (-z); no health reset
swing:
    sub     rsp, 8
    xor     edi, edi
    xorps   xmm0, xmm0
    movss   xmm1, [k_m1]
    call    combat_melee
    add     rsp, 8
    ret

; set_class(edi class): the class byte and the stats it implies, crit chance 0 so the numbers
; are exact, then a fresh combat state (full pools, no timers)
set_class:
    sub     rsp, 8
    mov     [rpg_state + RPGSAVE.class], dil
    call    rpg_recompute
    mov     dword [rpg_stats + STAT_CRIT_CHANCE * 4], 0
    call    combat_reset
    add     rsp, 8
    ret

; ---- guard: parry, block, break --------------------------------------------------------------

test_guard_blocks_and_parries:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     edi, 1
    call    combat_set_guard
    CHK     [combat_guard_t], 0
    call    combat_speed_mult           ; walking is slowed to 0.4 while guarding
    movss   [tmp], xmm0
    FNEAR   [tmp], k_0_4
    ; 1. a frontal hit the moment the guard is up is a perfect parry
    HIT_FRONT 3
    cmp     eax, HIT_PARRIED
    jne     .fail
    CHK     [surv + SURVIVAL.health], 20
    CHK     [combat_riposte_t], 60
    CHK     [combat_guard_t], 0         ; the guard stays up
    FNEAR   [combat_stamina], k_100
    FNEAR   [combat_hitstop], k_0_1
    ; 2. ten steps later the window is closed: a block costs 6 stamina per point, 1 health
    mov     edi, 10
    call    steps
    HIT_FRONT 3
    cmp     eax, HIT_BLOCKED
    jne     .fail
    CHK     [surv + SURVIVAL.health], 19
    FNEAR   [combat_stamina], k_82
    ; 3. a hit from behind ignores the guard
    HIT_BEHIND 3
    cmp     eax, HIT_TAKEN
    jne     .fail
    CHK     [surv + SURVIVAL.health], 16
    ; 4. a block that empties the stamina breaks the guard, and the hit goes through
    mov     dword [combat_stamina], __float32__(5.0)
    mov     edi, 10
    call    steps
    HIT_FRONT 3
    cmp     eax, HIT_TAKEN
    jne     .fail
    CHK     [surv + SURVIVAL.health], 13
    CHK     [combat_guard_break_t], 60
    CHK     [combat_guard_t], -1
    FNEAR   [combat_stamina], k_0
    ; 5. a broken guard cannot be raised
    mov     edi, 1
    call    combat_set_guard
    CHK     [combat_guard_t], -1
    ; 6. PARRY_WINDOW widens the parry window: 6 + 2 steps
    call    combat_reset
    mov     dword [rpg_stats + STAT_PARRY_WINDOW * 4], 2
    mov     edi, 1
    call    combat_set_guard
    mov     edi, 7
    call    steps
    HIT_FRONT 3
    cmp     eax, HIT_PARRIED            ; guard timer 7 < 8
    jne     .fail
    mov     edi, 1
    call    steps
    HIT_FRONT 3
    cmp     eax, HIT_BLOCKED            ; guard timer 8
    jne     .fail
    CHK     [surv + SURVIVAL.health], 12
    ; 7. a war cry halves the damage taken (at least 1)
    mov     dword [combat_warcry_t], 100
    HIT_BEHIND 5
    cmp     eax, HIT_TAKEN
    jne     .fail
    CHK     [surv + SURVIVAL.health], 10
    ; 8. creative takes nothing
    mov     dword [game_mode], MODE_CREATIVE
    HIT_FRONT 3
    test    eax, eax
    jnz     .fail
    CHK     [surv + SURVIVAL.health], 10
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- dodge roll ------------------------------------------------------------------------------

test_dodge_iframes_and_stamina:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    lea     rdi, [inp]
    mov     ecx, INPUT_size
    xor     eax, eax
    rep     stosb
    mov     dword [inp + INPUT.fwd], 1
    ; 1. roll forward (-z): knockback 16, a hop, 16 steps of invulnerability, 25 stamina
    lea     rdi, [inp]
    call    combat_dodge
    cmp     eax, 1
    jne     .fail
    FNEAR   [player + BODY.kbx], k_0
    FNEAR   [player + BODY.kbz], k_m16
    FNEAR   [player + BODY.vy], k_3_5
    CHK     [combat_dodge_t], 16
    CHK     [combat_dodge_cd], 30
    FNEAR   [combat_stamina], k_75
    ; 2. nothing lands during the roll
    HIT_FRONT 3
    test    eax, eax                    ; HIT_NONE
    jnz     .fail
    CHK     [surv + SURVIVAL.health], 20
    ; 3. no second roll during the cooldown, and it takes no stamina
    lea     rdi, [inp]
    call    combat_dodge
    test    eax, eax
    jnz     .fail
    FNEAR   [combat_stamina], k_75
    ; 4. cooldown over, but not in the air
    mov     edi, 30
    call    steps
    CHK     [combat_dodge_cd], 0
    CHK     [combat_dodge_t], 0
    mov     dword [player + BODY.on_ground], 0
    lea     rdi, [inp]
    call    combat_dodge
    test    eax, eax
    jnz     .fail
    FNEAR   [combat_stamina], k_75
    ; 5. nor with the guard up
    mov     dword [player + BODY.on_ground], 1
    mov     edi, 1
    call    combat_set_guard
    lea     rdi, [inp]
    call    combat_dodge
    test    eax, eax
    jnz     .fail
    xor     edi, edi
    call    combat_set_guard
    CHK     [combat_guard_t], -1
    ; 6. the roll is over: a hit lands
    HIT_FRONT 3
    cmp     eax, HIT_TAKEN
    jne     .fail
    CHK     [surv + SURVIVAL.health], 17
    ; 7. strafing right rolls along +x
    mov     dword [inp + INPUT.fwd], 0
    mov     dword [inp + INPUT.strafe], 1
    lea     rdi, [inp]
    call    combat_dodge
    cmp     eax, 1
    jne     .fail
    FNEAR   [player + BODY.kbx], k_16
    FNEAR   [player + BODY.kbz], k_0
    FNEAR   [combat_stamina], k_50
    ; 8. no input rolls straight back: looking along +x (yaw 90), back is -x
    mov     dword [inp + INPUT.strafe], 0
    mov     dword [combat_dodge_cd], 0
    mov     dword [player + BODY.yaw], __float32__(90.0)
    lea     rdi, [inp]
    call    combat_dodge
    cmp     eax, 1
    jne     .fail
    FNEAR   [player + BODY.kbx], k_m16
    FNEAR   [player + BODY.kbz], k_0
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- melee: combo, crit, backstab ------------------------------------------------------------

test_melee_combo_crit_backstab:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.id], IRON_SWORD    ; attack 7, cooldown 12
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.count], 1
    mov     edi, CLASS_WARRIOR          ; MELEE +10%
    call    set_class
    movss   xmm0, [k_180]               ; a zombie facing the player
    call    spawn_zombie
    test    eax, eax
    jnz     .fail
    lea     rbx, [mobs]
    ; hit 1: 7 * 1.1 = 7.7 -> 8, thrown 6 b/s along -z
    call    strike
    cmp     eax, 8
    jne     .fail
    CHK     [combat_attack_cd], 12
    FNEAR   [rbx + BODY.kbz], k_m6
    FNEAR   [combat_hitstop], k_0_05
    ; the cooldown refuses an immediate second strike
    call    strike
    test    eax, eax
    jnz     .fail
    ; hit 2 after the cooldown: 8 again
    mov     edi, 12
    call    steps
    call    strike
    cmp     eax, 8
    jne     .fail
    ; hit 3 completes the combo: 7 * 1.1 * 1.5 = 11.55 -> 12, thrown 1.8 times as far
    mov     edi, 12
    call    steps
    call    strike
    cmp     eax, 12
    jne     .fail
    CHK     [combat_combo], 0
    FNEAR   [rbx + BODY.kbz], k_m10_8
    ; the zombie turns its back on us: a Warrior has no backstab bonus, 8
    mov     edi, 12
    call    steps
    mov     dword [rbx + BODY.yaw], 0
    call    strike
    cmp     eax, 8
    jne     .fail
    ; Rogue (no MELEE, BACKSTAB +100%): 7 * 2 = 14 from behind, 7 from the front
    mov     edi, CLASS_ROGUE
    call    set_class
    call    strike
    cmp     eax, 14
    jne     .fail
    mov     edi, 12
    call    steps
    mov     dword [rbx + BODY.yaw], __float32__(180.0)
    call    strike
    cmp     eax, 7
    jne     .fail
    ; the dagger swings every 7 steps (iron dagger attack 5, from behind 10)
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.id], IRON_DAGGER
    mov     edi, CLASS_ROGUE
    call    set_class
    mov     dword [rbx + BODY.yaw], 0
    call    strike
    cmp     eax, 10
    jne     .fail
    CHK     [combat_attack_cd], 7
    ; back to the Warrior with the sword: every forced crit is 7 * 1.1 * 1.5 = 11.55 -> 12
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.id], IRON_SWORD
    mov     dword [rbx + BODY.yaw], __float32__(180.0)
    mov     edi, CLASS_WARRIOR
    call    set_class
    mov     dword [combat_riposte_t], 60            ; after a parry
    call    strike
    cmp     eax, 12
    jne     .fail
    CHK     [combat_riposte_t], 0                   ; spent
    FNEAR   [combat_hitstop], k_0_09                ; a crit freezes longer
    mov     edi, CLASS_WARRIOR
    call    set_class
    mov     dword [combat_crit_next_t], 120         ; after Shadowstep
    call    strike
    cmp     eax, 12
    jne     .fail
    CHK     [combat_crit_next_t], 0
    mov     edi, CLASS_WARRIOR
    call    set_class
    mov     dword [combat_stealth_t], 300           ; from the shadows, which it ends
    call    strike
    cmp     eax, 12
    jne     .fail
    CHK     [combat_stealth_t], 0
    mov     edi, CLASS_WARRIOR
    call    set_class
    mov     dword [combat_blade_t], 100             ; Blade Dance: always crit, half the cooldown
    call    strike
    cmp     eax, 12
    jne     .fail
    CHK     [combat_attack_cd], 6
    CHK     [combat_blade_t], 100
    mov     edi, CLASS_WARRIOR
    call    set_class
    mov     dword [player + BODY.on_ground], 0      ; plunging onto it
    mov     dword [player + BODY.vy], __float32__(-5.0)
    call    strike
    cmp     eax, 12
    jne     .fail
    mov     dword [player + BODY.on_ground], 1
    mov     dword [player + BODY.vy], 0
    ; lifesteal: 25% of 8 = 2 half hearts
    mov     edi, CLASS_WARRIOR
    call    set_class
    mov     dword [rpg_stats + STAT_LIFESTEAL * 4], 25
    mov     dword [surv + SURVIVAL.health], 10
    call    strike
    cmp     eax, 8
    jne     .fail
    CHK     [surv + SURVIVAL.health], 12
    ; keystones and powers of the strike (class none, an iron sword: 7). Assassinate kills a backstabbed
    ; foe under a quarter of its health, but the boss takes 50 % more instead; Shadow Dance doubles a
    ; strike from stealth; a backstab kill with the Shadow Fang makes Shadowstep ready again
    xor     edi, edi
    call    set_class
    mov     dword [rpg_keystones], 1 << KS_ASSASSINATE
    movss   xmm0, [k_0]
    call    mobs_clear
    call    spawn_zombie                        ; yaw 0: his back is turned
    mov     dword [rbx + MOB.max_health], 100
    mov     dword [rbx + MOB.health], 24        ; 24 * 4 = 96 < 100
    call    swing
    cmp     eax, 1
    jne     .fail
    CHK     [rbx + MOB.type], MOB_NONE          ; executed
    call    combat_reset
    movss   xmm0, [k_180]
    call    mobs_clear
    call    spawn_zombie                        ; facing us: an ordinary strike
    mov     dword [rbx + MOB.max_health], 100
    mov     dword [rbx + MOB.health], 24
    call    swing
    CHK     [rbx + MOB.health], 17
    call    combat_reset
    mov     edi, MOB_BOSS
    call    spawn_mob
    mov     dword [rbx + BODY.yaw], 0
    mov     dword [rbx + MOB.health], 24
    call    swing
    CHK     [rbx + MOB.health], 16              ; 7 * 1.5 * 0.8 = 8.4: hit harder, not executed
    call    combat_reset
    mov     dword [rpg_keystones], 1 << KS_SHADOW_DANCE
    movss   xmm0, [k_180]
    call    mobs_clear
    call    spawn_zombie
    mov     dword [combat_stealth_t], 300
    call    swing
    CHK     [rbx + MOB.health], 79              ; 7 * 2 * 1.5 (the crit of the stealth) = 21
    CHK     [combat_stealth_t], 0
    call    combat_reset
    mov     dword [rpg_keystones], 0
    mov     dword [gear_powers], 1 << LP_SHADOW_FANG
    mov     dword [abilities_cd], 100
    movss   xmm0, [k_0]
    call    mobs_clear
    call    spawn_zombie
    mov     dword [rbx + MOB.health], 5
    call    swing                               ; a backstab that kills
    CHK     [rbx + MOB.type], MOB_NONE
    CHK     [abilities_cd], 0
    call    combat_reset
    mov     dword [abilities_cd], 100
    movss   xmm0, [k_180]
    call    mobs_clear
    call    spawn_zombie
    mov     dword [rbx + MOB.health], 5
    call    swing                               ; a kill, but not from behind
    CHK     [rbx + MOB.type], MOB_NONE
    CHK     [abilities_cd], 100
    call    combat_reset
    movss   xmm0, [k_0]
    call    mobs_clear
    call    spawn_zombie
    call    swing                               ; a backstab, but no kill
    CHK     [abilities_cd], 100
    mov     dword [gear_powers], 0
    mov     dword [abilities_cd], 0
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- stamina, mana, max health ---------------------------------------------------------------

test_stamina_mana_regen_and_max_health:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    ; spending 30 of 100 stamina; regeneration then waits 36 steps
    mov     edi, RES_STAMINA
    movss   xmm0, [k_30]
    call    combat_spend
    cmp     eax, 1
    jne     .fail
    FNEAR   [combat_stamina], k_70
    CHK     [combat_spend_t], 36
    mov     edi, RES_STAMINA            ; more than there is: refused, nothing taken
    movss   xmm0, [k_80]
    call    combat_spend
    test    eax, eax
    jnz     .fail
    FNEAR   [combat_stamina], k_70
    mov     edi, 35
    call    steps
    FNEAR   [combat_stamina], k_70
    mov     edi, 1
    call    steps                       ; step 36: 20 per second = 1/3 per step
    FNEAR   [combat_stamina], k_70_333
    mov     edi, 60
    call    steps
    FNEAR   [combat_stamina], k_90_333
    mov     edi, 120
    call    steps
    FNEAR   [combat_stamina], k_100     ; capped at the maximum
    ; sprinting drains 0.2 per step and pauses regeneration
    mov     dword [combat_stamina], __float32__(50.0)
    mov     ebx, 10
.sprint:
    mov     edi, 1
    call    combat_step
    dec     ebx
    jnz     .sprint
    FNEAR   [combat_stamina], k_48
    CHK     [combat_spend_t], 36
    ; creative pays everything and takes nothing
    mov     dword [game_mode], MODE_CREATIVE
    mov     edi, RES_STAMINA
    movss   xmm0, [k_80]
    call    combat_spend
    cmp     eax, 1
    jne     .fail
    FNEAR   [combat_stamina], k_48
    mov     dword [game_mode], MODE_SURVIVAL
    ; a Mage regenerates 4 mana per second, and pays spells from it
    mov     edi, CLASS_MAGE
    call    set_class
    FNEAR   [combat_mana], k_100
    mov     dword [combat_mana], 0
    mov     edi, 60
    call    steps
    FNEAR   [combat_mana], k_4
    mov     edi, RES_MANA
    movss   xmm0, [k_30]
    call    combat_spend                ; 4 mana: not enough
    test    eax, eax
    jnz     .fail
    mov     dword [combat_mana], __float32__(50.0)
    mov     edi, RES_MANA
    movss   xmm0, [k_30]
    call    combat_spend
    cmp     eax, 1
    jne     .fail
    FNEAR   [combat_mana], k_20
    ; a Warrior has 24 half hearts, and a fresh survival state starts with all of them
    mov     edi, CLASS_WARRIOR
    call    set_class
    CHK     [surv_max_health], 24
    call    survival_reset
    CHK     [surv + SURVIVAL.health], 24
    ; regeneration climbs to the raised maximum, not to 20: fed (a heart per 240 steps) ...
    mov     dword [surv + SURVIVAL.health], 22
    mov     edi, 500
    call    surv_steps
    CHK     [surv + SURVIVAL.health], 24
    mov     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL   ; ... and peaceful (a heart per second)
    mov     dword [surv + SURVIVAL.health], 22
    mov     edi, 200
    call    surv_steps
    CHK     [surv + SURVIVAL.health], 24
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    ; the RPG armor bonus counts like worn armor points: 10 of them turn a 10-point mob hit into
    ; (10 * 15 + 12) / 25 = 6, and a boss slam too, but not a fall
    mov     dword [rpg_stats + STAT_ARMOR_BONUS * 4], 10
    call    survival_reset
    mov     edi, 10
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    CHK     [surv + SURVIVAL.health], 18
    mov     dword [surv + SURVIVAL.invuln], 0
    mov     edi, 10
    mov     esi, CAUSE_BOSS
    call    survival_damage
    CHK     [surv + SURVIVAL.health], 12
    mov     dword [surv + SURVIVAL.invuln], 0
    mov     edi, 5
    mov     esi, CAUSE_FALL
    call    survival_damage
    CHK     [surv + SURVIVAL.health], 6         ; a fall of 5 is 6 at 24 health, armor or not: 12 - 6
    mov     dword [rpg_stats + STAT_ARMOR_BONUS * 4], 30        ; capped at 20: (10 * 5 + 12) / 25 = 2
    call    survival_reset
    mov     edi, 10
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    CHK     [surv + SURVIVAL.health], 22
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    cleanup
    cmp     dword [surv_max_health], 20 ; class none again
    je      .done
    mov     ebx, 1
.done:
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- the damage pipeline, heavy attacks, the player's statuses and defenses -----------------------

; POKE stat, value: rpg_stats[stat] = value
%macro POKE 2
    mov     dword [rpg_stats + %1 * 4], %2
%endmacro

; HELD id: the selected hotbar stack holds one such item (count 0: bare hands)
%macro HELD 1
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.id], %1
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.count], 1
    mov     word [inv + INVENTORY.slots + ITEMSTACK.dmg], 0
%endmacro

; CALC mob, src, flags, base, expected: fail unless combat_calc is within 0.005 of expected
%macro CALC 5
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    movss   xmm0, [%4]
    call    combat_calc
    movss   [tmp], xmm0
    FNEAR   [tmp], %5
%endmacro

; HM mob, src, flags, base: combat_hit_mob straight ahead (-z) -> eax damage dealt
%macro HM 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    movss   xmm0, [%4]
    xorps   xmm1, xmm1
    movss   xmm2, [k_m1]
    call    combat_hit_mob
%endmacro

; PH src, flags, base: HM on slot 0 after its health is back to 100 -> eax damage dealt
%macro PH 3
    mov     dword [rbx + MOB.health], 100
    HM      0, %1, %2, %3
%endmacro

; FRESH type: slot 0 is a new mob of that type (rbx points at it)
%macro FRESH 1
    mov     edi, %1
    call    spawn_mob
%endmacro

; spawn_mob(edi type) -> rbx the mob in slot 0 (the mobs are cleared first): one block in front of the
; player, facing him, 100 health, level 1
spawn_mob:
    push    rbp
    mov     rbp, rsp
    push    r12
    sub     rsp, 8
    mov     r12d, edi
    call    mobs_clear
    mov     edi, r12d
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_15_5]
    call    mob_spawn
    imul    ecx, eax, MOB_size
    lea     rbx, [mobs]
    add     rbx, rcx
    mov     dword [rbx + BODY.yaw], __float32__(180.0)
    mov     dword [rbx + MOB.health], 100
    mov     dword [rbx + MOB.max_health], 100
    mov     dword [rbx + MOB.level], 1
    add     rsp, 8
    pop     r12
    pop     rbp
    ret

; add_mob(edi type, xmm0 x, xmm1 z) -> eax slot: one more mob there at y = 11, 100 health, level 1
add_mob:
    sub     rsp, 8
    movaps  xmm2, xmm1
    movss   xmm1, [k_11]
    call    mob_spawn
    imul    ecx, eax, MOB_size
    lea     rdx, [mobs]
    mov     dword [rdx + rcx + MOB.health], 100
    mov     dword [rdx + rcx + MOB.max_health], 100
    mov     dword [rdx + rcx + MOB.level], 1
    add     rsp, 8
    ret

; shoot(edi kind, esi damage, edx flags): a player's projectile leaves (16.5, 11.5, 15.5) at 30 blocks/s
; along -z and flies for 12 steps
shoot:
    push    rbp
    mov     rbp, rsp
    push    r12
    sub     rsp, 8
    mov     r8d, edx
    mov     r12d, edi                   ; arrows_clear uses rdi and rcx
    call    arrows_clear
    mov     ecx, r12d
    movss   xmm0, [k_16_5]
    movss   xmm1, [f11_5]
    movss   xmm2, [k_15_5]
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    movss   xmm5, [fm30]
    xor     edi, edi
    xor     edx, edx
    call    arrows_spawn
    mov     r12d, 12
.fly:
    call    arrows_step
    dec     r12d
    jnz     .fly
    add     rsp, 8
    pop     r12
    pop     rbp
    ret

; test_damage_pipeline: the pipeline of combat_calc / combat_hit_mob, its statuses and keystone terms,
; and the projectiles and blasts that go through it
test_damage_pipeline:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    ; ---- 1. a pig: base 5 with MELEE +20 % is 6 -------------------------------------------------
    FRESH   MOB_PIG
    POKE    STAT_MELEE_DMG, 20
    PH      SRC_MELEE, 0, f5
    cmp     eax, 6
    jne     .fail
    CHK     [rbx + MOB.health], 94
    POKE    STAT_MELEE_DMG, 0
    ; ---- 2. added fire damage: 4 + 2 fire is 6 and sets a pig alight; a zombie's fire part is 2 * 1.5 -
    POKE    STAT_ADD_FIRE, 2
    PH      SRC_MELEE, 0, k_4
    cmp     eax, 6
    jne     .fail
    CHK     [rbx + MOB.burn_t], 180
    FRESH   MOB_ZOMBIE
    PH      SRC_MELEE, 0, k_4
    cmp     eax, 7
    jne     .fail
    CHK     [rbx + MOB.burn_t], 180
    POKE    STAT_ADD_FIRE, 0
    ; ---- 3. a skeleton is immune to poison: nothing happens and nothing is dealt ---------------------
    FRESH   MOB_SKELETON
    PH      SRC_SPELL, ELEM_POISON, f5
    test    eax, eax
    jnz     .fail
    CHK     [rbx + MOB.health], 100
    CHK     [rbx + MOB.poison], 0
    ; ---- 4. the multipliers: crit, shock, mark, elites -----------------------------------------
    FRESH   MOB_ZOMBIE
    POKE    STAT_CRIT_DMG, 50
    CALC    -1, SRC_MELEE, HITF_CRIT, f10, k_20
    POKE    STAT_CRIT_DMG, -100
    CALC    -1, SRC_MELEE, HITF_CRIT, f10, f10         ; never below 1.0
    POKE    STAT_CRIT_DMG, 0
    CALC    -1, SRC_MELEE, HITF_CRIT, f10, f15         ; 1.5
    CALC    -1, SRC_MELEE, 0, f10, f10
    mov     dword [rbx + MOB.shock], 2
    CALC    0, SRC_MELEE, 0, f10, f12                  ; +10 % per shock stack
    mov     dword [rbx + MOB.shock], 0
    mov     dword [rbx + MOB.mark_t], 100
    CALC    0, SRC_MELEE, 0, f10, f13                  ; marked: +30 %
    mov     dword [rbx + MOB.mark_t], 0
    POKE    STAT_ELITE_DMG, 50
    CALC    0, SRC_MELEE, 0, f10, f10                  ; not an elite
    mov     dword [rbx + MOB.elite], 1
    CALC    0, SRC_MELEE, 0, f10, f15                  ; an elite: +50 %
    CALC    -1, SRC_MELEE, 0, f10, f10                 ; no mob, no elite term
    FRESH   MOB_BOSS
    CALC    0, SRC_MELEE, 0, f10, f12                  ; the boss: +50 % of the 20 % it resists
    POKE    STAT_ELITE_DMG, 0
    ; ---- 5. the Executioner: melee on a foe under 30 % health deals 60 % more ----------------------
    FRESH   MOB_ZOMBIE
    mov     dword [rbx + MOB.max_health], 20
    mov     dword [rbx + MOB.health], 5
    mov     dword [rpg_keystones], 1 << KS_EXECUTIONER
    CALC    0, SRC_MELEE, 0, f10, k_16
    CALC    0, SRC_MELEE_SKILL, 0, f10, k_16
    CALC    0, SRC_BOW, 0, f10, f10
    mov     dword [rbx + MOB.health], 6                ; 30 % exactly is not under
    CALC    0, SRC_MELEE, 0, f10, f10
    mov     dword [rpg_keystones], 0
    ; ---- 6. lifesteal heals the damage dealt, keeping the fraction; thorns steal nothing ----------
    FRESH   MOB_ZOMBIE
    POKE    STAT_LIFESTEAL, 50
    mov     dword [surv + SURVIVAL.health], 10
    PH      SRC_MELEE, 0, f8
    cmp     eax, 8
    jne     .fail
    CHK     [surv + SURVIVAL.health], 14
    mov     dword [surv + SURVIVAL.health], 10
    PH      SRC_MELEE, 0, f3                           ; 1.5: one point now, the half is kept...
    CHK     [surv + SURVIVAL.health], 11
    PH      SRC_MELEE, 0, f3                           ; ...and 2 the next time
    CHK     [surv + SURVIVAL.health], 13
    PH      SRC_THORNS, 0, f8
    CHK     [surv + SURVIVAL.health], 13
    POKE    STAT_LIFESTEAL, 0
    ; ---- 7. the family factor, ALL damage, weapon damage, element damage ----------------------------
    POKE    STAT_MELEE_DMG, 20
    POKE    STAT_ALL_DMG, 10
    CALC    -1, SRC_MELEE, 0, f10, f13                 ; (20 + 10) %
    CALC    -1, SRC_MELEE_SKILL, 0, f10, f13
    CALC    -1, SRC_BOW, 0, f10, k_11                  ; no RANGED: only the 10 % ALL
    CALC    -1, SRC_SPELL, 0, f10, k_11
    CALC    -1, SRC_THORNS, 0, f10, f10                ; thorns take no family factor
    POKE    STAT_ALL_DMG, 0
    POKE    STAT_WEAPON_DMG, 2
    CALC    -1, SRC_MELEE, 0, f5, f8_4                 ; (5 + 2) * 1.2
    CALC    -1, SRC_SPELL, 0, f5, f5                   ; a spell is no weapon: no weapon damage
    POKE    STAT_MELEE_DMG, 0
    POKE    STAT_WEAPON_DMG, 0
    POKE    STAT_FIRE_DMG, 50
    CALC    -1, SRC_MELEE, ELEM_FIRE, f10, f15         ; the base is fire: +50 %
    POKE    STAT_FIRE_DMG, 0
    POKE    STAT_ADD_FROST, 3
    POKE    STAT_FROST_DMG, 100
    CALC    -1, SRC_MELEE, 0, f10, k_16                ; 10 + 3 * 2
    CALC    -1, SRC_SPELL, 0, f10, f10                 ; spells add no element damage
    POKE    STAT_ADD_FROST, 0
    POKE    STAT_FROST_DMG, 0
    ; ---- 8. Bloodrage, Embers and Inferno ------------------------------------------------------------
    mov     dword [rpg_keystones], 1 << KS_BLOODRAGE
    mov     dword [surv + SURVIVAL.health], 10         ; half of 20 is missing: +25 %
    CALC    -1, SRC_MELEE, 0, f10, f12_5
    CALC    -1, SRC_THORNS, 0, f10, f10
    mov     dword [surv + SURVIVAL.health], 20
    CALC    -1, SRC_MELEE, 0, f10, f10
    mov     dword [rpg_keystones], 0
    FRESH   MOB_ZOMBIE
    mov     dword [gear_powers], 1 << LP_EMBERS
    CALC    0, SRC_MELEE, 0, f10, f10                  ; not burning
    mov     dword [rbx + MOB.burn_t], 60
    CALC    0, SRC_MELEE, 0, f10, f13                  ; burning: +30 %
    mov     dword [gear_powers], 0
    mov     dword [rpg_keystones], 1 << KS_INFERNO
    CALC    0, SRC_SPELL, 0, f10, f12_5                ; Inferno: spells on a burning foe +25 %
    CALC    0, SRC_BOLT, 0, f10, f12_5
    CALC    0, SRC_MELEE, 0, f10, f10
    mov     dword [rbx + MOB.burn_t], 0
    CALC    0, SRC_SPELL, 0, f10, f10
    mov     dword [rpg_keystones], 0
    ; ---- 9. statuses: bleeding, no status flag, chill three times, Inferno, Venom Blades, Celestial -
    FRESH   MOB_ZOMBIE
    PH      SRC_MELEE, 0, f5
    CHK     [rbx + MOB.bleed_t], 0
    FRESH   MOB_ZOMBIE
    PH      SRC_MELEE, HITF_BLEED, f5
    CHK     [rbx + MOB.bleed_t], 180
    POKE    STAT_BLEED_CHANCE, 100
    FRESH   MOB_ZOMBIE
    PH      SRC_BOW, 0, f5                             ; a bow shot, a melee skill and melee roll for it
    CHK     [rbx + MOB.bleed_t], 180
    FRESH   MOB_ZOMBIE
    PH      SRC_MELEE_SKILL, 0, f5
    CHK     [rbx + MOB.bleed_t], 180
    FRESH   MOB_ZOMBIE
    PH      SRC_SPELL, 0, f5                           ; a spell never bleeds
    CHK     [rbx + MOB.bleed_t], 0
    POKE    STAT_BLEED_CHANCE, 0
    FRESH   MOB_ZOMBIE
    PH      SRC_MELEE, ELEM_FIRE | HITF_NOSTATUS, f5
    CHK     [rbx + MOB.burn_t], 0
    FRESH   MOB_ZOMBIE
    PH      SRC_MELEE, ELEM_FIRE, f5
    CHK     [rbx + MOB.burn_t], 180
    FRESH   MOB_ZOMBIE
    HM      0, SRC_SPELL, ELEM_FROST, f6               ; one chill...
    CHK     [rbx + MOB.chill], 1
    FRESH   MOB_ZOMBIE
    HM      0, SRC_SPELL, ELEM_FROST | HITF_CHILL3, f6 ; ...or three at once: frozen
    cmp     eax, 6
    jne     .fail
    CHK     [rbx + MOB.stun], 90
    FRESH   MOB_ZOMBIE
    mov     dword [rpg_keystones], 1 << KS_INFERNO
    PH      SRC_SPELL, 0, f6                           ; a spell without fire burns anyway
    CHK     [rbx + MOB.burn_t], 180
    FRESH   MOB_ZOMBIE
    PH      SRC_MELEE, 0, f6
    CHK     [rbx + MOB.burn_t], 0
    mov     dword [rpg_keystones], 1 << KS_VENOM_BLADES
    FRESH   MOB_ZOMBIE
    PH      SRC_MELEE, 0, f5                           ; Venom Blades: two poison stacks per melee hit
    CHK     [rbx + MOB.poison], 2
    mov     dword [gear_powers], 1 << LP_SHADOW_FANG
    FRESH   MOB_ZOMBIE
    PH      SRC_MELEE, 0, f5                           ; and the Shadow Fang two more
    CHK     [rbx + MOB.poison], 4
    FRESH   MOB_ZOMBIE
    PH      SRC_MELEE_SKILL, 0, f5
    CHK     [rbx + MOB.poison], 0
    mov     dword [rpg_keystones], 0
    mov     dword [gear_powers], 1 << LP_CELESTIAL
    FRESH   MOB_ZOMBIE
    PH      SRC_BOW, HITF_CRIT, f5                     ; a crit from the Celestial Bow shocks three times
    CHK     [rbx + MOB.shock], 3
    FRESH   MOB_ZOMBIE
    PH      SRC_BOW, 0, f5
    CHK     [rbx + MOB.shock], 0
    FRESH   MOB_ZOMBIE
    PH      SRC_MELEE, HITF_CRIT, f5
    CHK     [rbx + MOB.shock], 0
    mov     dword [gear_powers], 0
    ; ---- 10. execute, the hurt window, and refused targets ------------------------------------------
    FRESH   MOB_ZOMBIE
    mov     dword [rbx + MOB.health], 30
    mov     dword [rbx + MOB.max_health], 30
    HM      0, SRC_MELEE, HITF_EXECUTE, f1             ; the execution takes what is left
    cmp     eax, 30
    jne     .fail
    CHK     [rbx + MOB.type], MOB_NONE
    FRESH   MOB_ZOMBIE
    HM      0, SRC_MELEE, HITF_HURTWIN, f3
    cmp     eax, 3
    jne     .fail
    HM      0, SRC_MELEE, HITF_HURTWIN, f3             ; inside the hurt window: refused
    test    eax, eax
    jnz     .fail
    CHK     [combat_hit_flags], 0                      ; the refused hit left no player tag behind
    CHK     [rbx + MOB.health], 97
    HM      0, SRC_MELEE, 0, f3                        ; a plain strike counts anyway
    cmp     eax, 3
    jne     .fail
    CHK     [rbx + MOB.health], 94
    HM      5, SRC_MELEE, 0, f3                        ; an empty slot
    test    eax, eax
    jnz     .fail
    HM      99, SRC_MELEE, 0, f3                       ; no such slot
    test    eax, eax
    jnz     .fail
    FRESH   MOB_MERCHANT
    HM      0, SRC_MELEE, 0, f3                        ; a villager cannot be hurt
    test    eax, eax
    jnz     .fail
    CHK     [rbx + MOB.health], 100
    ; ---- 11. the Storm band: a crit arcs half of its damage as shock to 3 other hostile mobs nearby --
    FRESH   MOB_ZOMBIE
    mov     edi, MOB_PIG                               ; slot 1: not hostile, skipped
    movss   xmm0, [f17]
    movss   xmm1, [k_15_5]
    call    add_mob
    mov     edi, MOB_ZOMBIE                            ; slots 2..5 within 6 blocks, slot 6 beyond
    movss   xmm0, [f17_5]
    movss   xmm1, [k_15_5]
    call    add_mob
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [k_18_5]
    movss   xmm1, [k_15_5]
    call    add_mob
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [f19_5]
    movss   xmm1, [k_15_5]
    call    add_mob
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [f20_5]
    movss   xmm1, [k_15_5]
    call    add_mob
    mov     edi, MOB_ZOMBIE
    movss   xmm0, [f40_5]
    movss   xmm1, [k_15_5]
    call    add_mob
    mov     dword [gear_powers], 1 << LP_STORMS
    HM      0, SRC_MELEE, HITF_CRIT, f10               ; 10 * 1.5 = 15
    cmp     eax, 15
    jne     .fail
    CHK     [mobs + 0 * MOB_size + MOB.health], 85
    CHK     [mobs + 1 * MOB_size + MOB.health], 100    ; the pig is skipped
    CHK     [mobs + 2 * MOB_size + MOB.health], 92     ; 7.5 -> 8
    CHK     [mobs + 3 * MOB_size + MOB.health], 92
    CHK     [mobs + 4 * MOB_size + MOB.health], 92
    CHK     [mobs + 5 * MOB_size + MOB.health], 100    ; only three arcs
    CHK     [mobs + 6 * MOB_size + MOB.health], 100    ; and none beyond 6 blocks
    CHK     [mobs + 2 * MOB_size + MOB.shock], 0       ; an arc afflicts nothing
    mov     dword [mobs + 0 * MOB_size + MOB.health], 100
    HM      0, SRC_MELEE, 0, f10                       ; no crit: no arc
    CHK     [mobs + 2 * MOB_size + MOB.health], 92
    mov     dword [gear_powers], 0
    ; ---- 12. explode_magic: element, radius with AREA, falloff with the distance ---------------------
    FRESH   MOB_ZOMBIE                                 ; slot 0 at (16.5, 15.5)
    mov     edi, MOB_PIG                               ; slot 1 two blocks east of it
    movss   xmm0, [k_18_5]
    movss   xmm1, [k_15_5]
    call    add_mob
    mov     edi, MOB_ZOMBIE                            ; slot 2 four blocks east: out of 2.5, in 5
    movss   xmm0, [f20_5]
    movss   xmm1, [k_15_5]
    call    add_mob
    movss   xmm0, [k_16_5]                             ; the blast: the middle of the first zombie's body
    movss   xmm1, [f11_9]
    movss   xmm2, [k_15_5]
    movss   xmm3, [f2_5]
    mov     edi, 10
    mov     esi, SRC_SPELL
    mov     edx, ELEM_FIRE
    call    explode_magic
    CHK     [mobs + 0 * MOB_size + MOB.health], 85     ; 10 fire * 1.5 (a zombie burns easily)
    CHK     [mobs + 1 * MOB_size + MOB.health], 94     ; 10 * (1 - 0.5 * 2 / 2.5) = 6
    CHK     [mobs + 2 * MOB_size + MOB.health], 100    ; out of range
    CHK     [mobs + 0 * MOB_size + MOB.burn_t], 180
    POKE    STAT_AREA, 100                             ; AREA doubles the radius: 5 blocks
    mov     dword [mobs + 0 * MOB_size + MOB.health], 100
    movss   xmm0, [k_16_5]
    movss   xmm1, [f11_9]
    movss   xmm2, [k_15_5]
    movss   xmm3, [f2_5]
    mov     edi, 10
    mov     esi, SRC_SPELL
    mov     edx, ELEM_FIRE
    call    explode_magic
    CHK     [mobs + 2 * MOB_size + MOB.health], 91     ; 10 * (1 - 0.5 * 4 / 5) = 6, fire * 1.5 = 9
    POKE    STAT_AREA, 0
    ; ---- 13. projectiles through the pipeline: arrow, knife, bolt, explosive arrow -----------------
    FRESH   MOB_ZOMBIE
    mov     dword [rbx + BODY.z], __float32__(10.5)    ; six blocks ahead of the arrows
    POKE    STAT_RANGED_DMG, 20
    mov     edi, PROJ_ARROW
    mov     esi, 9
    mov     edx, AF_ATTACK
    call    shoot
    CHK     [rbx + MOB.health], 89                     ; round(9 * 1.2) = 11
    CHK     [arrows + ARROWENT.live], 0
    POKE    STAT_RANGED_DMG, 0
    FRESH   MOB_ZOMBIE
    mov     dword [rbx + BODY.z], __float32__(10.5)
    mov     edi, PROJ_KNIFE
    mov     esi, 4
    mov     edx, AF_BLEED
    call    shoot
    CHK     [rbx + MOB.health], 96
    CHK     [rbx + MOB.bleed_t], 180
    CHK     [arrows + ARROWENT.live], 0
    FRESH   MOB_ZOMBIE
    mov     dword [rbx + BODY.z], __float32__(10.5)
    mov     edi, PROJ_BOLT
    mov     esi, 4
    mov     edx, AF_ATTACK | (ELEM_SHOCK << AF_ELEM_SHIFT)
    call    shoot
    CHK     [rbx + MOB.health], 96
    CHK     [rbx + MOB.shock], 1
    FRESH   MOB_ZOMBIE
    mov     dword [rbx + BODY.z], __float32__(10.5)
    mov     edi, PROJ_ARROW
    mov     esi, 10
    mov     edx, AF_EXPLOSIVE
    call    shoot
    cmp     dword [rbx + MOB.health], 95
    jg      .fail                                      ; the blast hurt it...
    CHK     [rbx + MOB.burn_t], 180                    ; ...with fire
    CHK     [arrows + ARROWENT.live], 0
    call    mobs_clear                                 ; a knife into a wall is gone at once, not stuck
    mov     edi, 16
    mov     esi, 11
    mov     edx, 12
    mov     ecx, STONE
    call    world_set
    mov     edi, PROJ_KNIFE
    mov     esi, 4
    xor     edx, edx
    call    shoot
    CHK     [arrows + ARROWENT.live], 0
    mov     edi, 16
    mov     esi, 11
    mov     edx, 12
    xor     ecx, ecx
    call    world_set
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    arrows_clear
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret


; HEAVY: combat_heavy on slot 0 straight ahead -> eax 1 if it landed
%macro HEAVY 0
    xor     edi, edi
    xorps   xmm0, xmm0
    movss   xmm1, [k_m1]
    call    combat_heavy
%endmacro

; CDOF id, steps: a strike with that item leaves that cooldown (slot 0 at full health, no cooldown)
%macro CDOF 2
    HELD    %1
    mov     dword [combat_attack_cd], 0
    call    strike
    CHK     [combat_attack_cd], %2
%endmacro

; PREVIEW hit, crit hit, attacks per 10 s: combat_weapon_preview of what is held
%macro PREVIEW 3
    lea     rdi, [pv]
    call    combat_weapon_preview
    CHK     [pv], %1
    CHK     [pv + 4], %2
    CHK     [pv + 8], %3
%endmacro

; test_heavy_attack_and_speed: the cooldown of each tool kind and what ATTACK_SPEED does to it; the heavy
; attack (damage, stamina, bleed, stun, cooldown, and when it is refused); the warhammer; the weapon
; preview of the character sheet
test_heavy_attack_and_speed:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    xor     edi, edi
    call    set_class                   ; class none: no stat bonuses, 100 stamina
    FRESH   MOB_ZOMBIE
    ; ---- 1. the cooldown a strike leaves, by the tool in hand ----------------------------------
    CDOF    IRON_SWORD, 12
    CDOF    IRON_DAGGER, 7
    CDOF    IRON_AXE, 18
    CDOF    IRON_PICKAXE, 14
    CDOF    IRON_SHOVEL, 14
    CDOF    IRON_HAMMER, 20
    CDOF    IRON_SPEAR, 14
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.count], 0
    mov     dword [combat_attack_cd], 0
    call    strike
    CHK     [combat_attack_cd], 10              ; bare hands
    POKE    STAT_ATTACK_SPEED, 50               ; cooldown * 100 / 150
    CDOF    IRON_SWORD, 8
    CDOF    IRON_HAMMER, 13
    CDOF    IRON_DAGGER, 5
    POKE    STAT_ATTACK_SPEED, 100              ; twice as fast, but never under 4 steps
    CDOF    IRON_SWORD, 6
    CDOF    IRON_DAGGER, 4
    POKE    STAT_ATTACK_SPEED, 0
    ; ---- 2. the heavy attack ------------------------------------------------------------------------
    call    combat_reset
    FRESH   MOB_ZOMBIE
    HELD    IRON_SWORD
    HEAVY
    cmp     eax, 1
    jne     .fail
    CHK     [rbx + MOB.health], 85              ; round(7 * 2.2) = 15
    FNEAR   [combat_stamina], k_80              ; 20 stamina
    CHK     [rbx + MOB.stun], 20
    CHK     [rbx + MOB.bleed_t], 180            ; it always bleeds
    CHK     [combat_attack_cd], 18              ; 3/2 of a light strike's 12
    FNEAR   [combat_hitstop], k_0_12
    FNEAR   [rbx + BODY.kbz], k_m15             ; thrown 2.5 times as far as a light strike
    HEAVY                                       ; the cooldown refuses a second one
    test    eax, eax
    jnz     .fail
    FNEAR   [combat_stamina], k_80
    mov     dword [combat_attack_cd], 0
    mov     dword [combat_stamina], __float32__(10.0)
    mov     dword [rbx + MOB.health], 100
    mov     dword [rbx + MOB.stun], 0
    mov     dword [rbx + MOB.bleed_t], 0
    HEAVY                                       ; too tired: a dry click, nothing is paid or done
    test    eax, eax
    jnz     .fail
    FNEAR   [combat_stamina], f10
    CHK     [rbx + MOB.health], 100
    CHK     [rbx + MOB.stun], 0
    CHK     [rbx + MOB.bleed_t], 0
    call    combat_reset
    FRESH   MOB_ZOMBIE
    HELD    IRON_HAMMER
    HEAVY
    cmp     eax, 1
    jne     .fail
    CHK     [rbx + MOB.health], 80              ; round(9 * 2.2) = 20
    CHK     [rbx + MOB.stun], 40                ; a warhammer stuns twice as long
    CHK     [combat_attack_cd], 30
    call    combat_reset
    FRESH   MOB_ZOMBIE
    HELD    IRON_PICKAXE                        ; only melee weapons swing heavy
    HEAVY
    test    eax, eax
    jnz     .fail
    HELD    BOW
    HEAVY
    test    eax, eax
    jnz     .fail
    FNEAR   [combat_stamina], k_100
    CHK     [rbx + MOB.health], 100
    HELD    IRON_SWORD                          ; the boss and juggernauts are never stunned
    FRESH   MOB_BOSS
    HEAVY
    cmp     eax, 1
    jne     .fail
    CHK     [rbx + MOB.stun], 0
    call    combat_reset
    FRESH   MOB_ZOMBIE
    mov     dword [rbx + MOB.affix], AFX_JUGGERNAUT
    HEAVY
    cmp     eax, 1
    jne     .fail
    CHK     [rbx + MOB.stun], 0
    ; ---- 3. a warhammer: a light hit stuns 12, the third of a combo hits twice and throws further --------
    call    combat_reset
    FRESH   MOB_ZOMBIE
    HELD    IRON_HAMMER
    call    strike
    cmp     eax, 9
    jne     .fail
    CHK     [rbx + MOB.stun], 12
    mov     edi, 20
    call    steps
    call    strike
    cmp     eax, 9
    jne     .fail
    mov     edi, 20
    call    steps
    call    strike
    cmp     eax, 18                             ; 9 * 2
    jne     .fail
    FNEAR   [rbx + BODY.kbz], k_m16_2
    call    combat_reset
    FRESH   MOB_BOSS
    call    strike
    CHK     [rbx + MOB.stun], 0
    call    combat_reset
    FRESH   MOB_ZOMBIE
    mov     dword [rbx + MOB.affix], AFX_JUGGERNAUT
    call    strike
    CHK     [rbx + MOB.stun], 0
    ; ---- 4. the weapon preview: hit, crit hit, attacks per 10 seconds -----------------------------
    HELD    IRON_SWORD
    PREVIEW 7, 10, 50                           ; 7, 10.5 rounds to even, 600 / 12
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.count], 0
    PREVIEW 1, 2, 60
    mov     edi, CLASS_WARRIOR                  ; MELEE +10 %
    call    set_class
    HELD    IRON_SWORD
    PREVIEW 8, 12, 50
    xor     edi, edi
    call    set_class
    HELD    BOW
    PREVIEW 9, 14, 10                           ; a full draw: 9, 13.5, 60 steps
    HELD    CELESTIAL_BOW
    PREVIEW 14, 20, 10                          ; 9 * 1.5 = 13.5 -> 14; 20.25
    POKE    STAT_ATTACK_SPEED, 50
    PREVIEW 14, 20, 15                          ; the draw takes 40 steps
    mov     dword [rpg_keystones], 1 << KS_DEADEYE
    PREVIEW 14, 20, 10                          ; Deadeye: attack speed no longer speeds it
    mov     dword [rpg_keystones], 0
    POKE    STAT_ATTACK_SPEED, 0
    mov     edi, CLASS_MAGE                     ; SPELL +10 %: shock bolts
    call    set_class
    HELD    STAFF
    PREVIEW 4, 7, 25                            ; 4.4, 6.6, every 24 steps
    HELD    ARCHMAGE_STAFF
    PREVIEW 8, 12, 33                           ; 7.7, 11.55, every 18 steps
    call    frame_checks                ; whole frames: the heavy attack's button logic, reach, digging, the bow, potions
    test    eax, eax
    jnz     .fail
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; test_player_statuses_and_defenses: burning, poison and chill on the player; thorns; the Mana Shield;
; the Phoenix ring; a perfect dodge's riposte; blocking costs by max health; falls and fire by max
; health; the Kingslayer's parry; Blood Magic; Wind Runner; life regeneration; elemental arrows,
; Juggernaut and the blast of an explosion
test_player_statuses_and_defenses:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    fixture
    xor     edi, edi
    call    set_class
    ; ---- 1. burning: 2 health every 30 steps (the first after 30), through invulnerability -----------
    mov     edi, STS_BURN
    mov     esi, 12
    call    combat_player_status
    CHK     [combat_burn_t], 180
    mov     dword [surv + SURVIVAL.invuln], 100
    mov     edi, 29
    call    steps
    CHK     [surv + SURVIVAL.health], 20
    mov     edi, 1
    call    steps
    CHK     [surv + SURVIVAL.health], 18
    mov     edi, 150                            ; the ticks of steps 60, 90, 120, 150 and 180
    call    steps
    CHK     [surv + SURVIVAL.health], 8
    CHK     [combat_burn_t], 0
    CHK     [surv + SURVIVAL.invuln], 100       ; a burn neither respects invulnerability nor starts it
    mov     edi, 60
    call    steps
    CHK     [surv + SURVIVAL.health], 8
    ; ---- 2. poison: stacks to 5, each ticking for its share; it runs out after 4 seconds ------------
    call    survival_reset
    call    combat_reset
    mov     ebx, 6
.poison:
    mov     edi, STS_POISON
    mov     esi, 8
    call    combat_player_status
    dec     ebx
    jnz     .poison
    CHK     [combat_poison], 5
    CHK     [combat_poison_t], 240
    mov     edi, 30
    call    steps
    CHK     [surv + SURVIVAL.health], 10        ; 5 stacks * 2
    call    survival_reset
    call    combat_reset
    mov     edi, STS_POISON
    mov     esi, 4
    call    combat_player_status
    mov     edi, 239
    call    steps
    CHK     [surv + SURVIVAL.health], 13        ; seven ticks of 1
    mov     edi, 1
    call    steps
    CHK     [surv + SURVIVAL.health], 12        ; the eighth, on the last step
    CHK     [combat_poison_t], 0
    CHK     [combat_poison], 0
    mov     edi, 60
    call    steps
    CHK     [surv + SURVIVAL.health], 12
    ; ---- 3. chill slows walking to 0.6 for 2 seconds ------------------------------------------------
    call    combat_reset
    mov     edi, STS_CHILL
    xor     esi, esi
    call    combat_player_status
    CHK     [combat_chill_t], 120
    call    combat_speed_mult
    movss   [tmp], xmm0
    FNEAR   [tmp], f0_6
    mov     edi, 120
    call    steps
    call    combat_speed_mult
    movss   [tmp], xmm0
    FNEAR   [tmp], f1
    ; ---- 4. thorns hurt the attacker back of a taken or blocked hit, never of a parried one ---------
    call    survival_reset
    call    combat_reset
    FRESH   MOB_ZOMBIE
    mov     dword [rbx + MOB.health], 20
    POKE    STAT_THORNS, 3
    mov     dword [combat_attacker], 0
    HIT_BEHIND 3
    cmp     eax, HIT_TAKEN
    jne     .fail
    CHK     [rbx + MOB.health], 17
    mov     dword [combat_attacker], -1         ; nobody to hurt
    HIT_BEHIND 3
    CHK     [rbx + MOB.health], 17
    mov     dword [combat_attacker], 0
    mov     edi, 1
    call    combat_set_guard
    mov     edi, 10
    call    steps
    HIT_FRONT 3
    cmp     eax, HIT_BLOCKED
    jne     .fail
    CHK     [rbx + MOB.health], 14
    call    combat_reset                        ; a parry is no blow taken
    mov     edi, 1
    call    combat_set_guard
    HIT_FRONT 3
    cmp     eax, HIT_PARRIED
    jne     .fail
    CHK     [rbx + MOB.health], 14
    mov     dword [combat_attacker], -1
    POKE    STAT_THORNS, 0
    ; ---- 5. the Mana Shield pays 35 % of a hit in mana, 2 per point ------------------------------------
    call    survival_reset
    call    combat_reset
    mov     dword [rpg_keystones], 1 << KS_MANA_SHIELD
    mov     dword [combat_mana], __float32__(100.0)
    HIT_BEHIND 10
    cmp     eax, HIT_TAKEN
    jne     .fail
    FNEAR   [combat_mana], f94                  ; 3 points absorbed
    CHK     [surv + SURVIVAL.health], 13        ; 7 landed
    mov     dword [combat_mana], __float32__(4.0)
    HIT_BEHIND 10                               ; 4 mana cover 2 points
    FNEAR   [combat_mana], k_0
    CHK     [surv + SURVIVAL.health], 5
    mov     dword [rpg_keystones], 0
    call    survival_reset
    mov     dword [combat_mana], __float32__(100.0)
    HIT_BEHIND 10                               ; without the keystone nothing is paid
    FNEAR   [combat_mana], k_100
    CHK     [surv + SURVIVAL.health], 10
    ; ---- 6. the Phoenix ring: once per 2 minutes a killing blow leaves half the health -------------------
    call    survival_reset
    call    combat_reset
    mov     dword [gear_powers], 1 << LP_PHOENIX
    mov     dword [surv + SURVIVAL.health], 3
    mov     edi, 100
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage
    cmp     eax, 1
    jne     .fail
    CHK     [surv + SURVIVAL.health], 10
    CHK     [surv + SURVIVAL.dead], 0
    CHK     [surv + SURVIVAL.invuln], 60
    CHK     [combat_phoenix_cd], 7200
    mov     dword [surv + SURVIVAL.invuln], 0
    mov     edi, 100
    mov     esi, CAUSE_ZOMBIE
    call    survival_damage                     ; cooling down: this one kills
    CHK     [surv + SURVIVAL.dead], 1
    CHK     [surv + SURVIVAL.health], 0
    CHK     [surv + SURVIVAL.death_cause], CAUSE_ZOMBIE
    call    survival_reset
    mov     dword [combat_phoenix_cd], 1
    mov     edi, 1
    call    steps
    CHK     [combat_phoenix_cd], 0
    mov     dword [surv + SURVIVAL.health], 2
    mov     edi, 5
    mov     esi, CAUSE_FIRE
    call    survival_dot                        ; a lethal burn tick is undone as well
    CHK     [surv + SURVIVAL.health], 10
    CHK     [surv + SURVIVAL.dead], 0
    mov     dword [gear_powers], 0
    ; ---- 7. a hit avoided by a dodge makes the next strike a forced crit -----------------------------
    call    survival_reset
    call    combat_reset
    mov     dword [combat_dodge_t], 5
    HIT_FRONT 3
    test    eax, eax
    jnz     .fail
    CHK     [surv + SURVIVAL.health], 20
    CHK     [combat_riposte_t], 60
    ; ---- 8. a block costs 120 * damage / max health stamina, less with BLOCK_COST ------------------------
    call    survival_reset
    call    combat_reset
    mov     dword [surv_max_health], 40
    mov     dword [surv + SURVIVAL.health], 40
    mov     edi, 1
    call    combat_set_guard
    mov     edi, 10
    call    steps
    HIT_FRONT 4
    cmp     eax, HIT_BLOCKED
    jne     .fail
    FNEAR   [combat_stamina], f88               ; 120 * 4 / 40 = 12
    POKE    STAT_BLOCK_COST, 50
    HIT_FRONT 4
    FNEAR   [combat_stamina], k_82              ; half of that: 6
    POKE    STAT_BLOCK_COST, 0
    ; ---- 9. falls and fire are given for 20 health: they scale with the maximum --------------------------
    call    survival_reset
    mov     dword [surv_max_health], 40
    mov     dword [surv + SURVIVAL.health], 40
    movss   xmm0, [f5]
    call    survival_land                       ; ceil(5 - 3) = 2 -> 4
    CHK     [surv + SURVIVAL.health], 36
    mov     dword [surv + SURVIVAL.invuln], 0
    mov     edi, 1
    mov     esi, CAUSE_FIRE
    call    survival_damage                     ; a fire cell: 1 -> 2
    CHK     [surv + SURVIVAL.health], 34
    call    survival_reset                      ; regeneration heals a twentieth of the maximum per tick: 2 at 40
    mov     dword [surv + SURVIVAL.health], 30
    mov     edi, 240
    call    surv_steps
    CHK     [surv + SURVIVAL.health], 32
    mov     dword [surv + SURVIVAL.food], 0     ; hunger stops at 1 * max / 20 = 2 health on Normal, 2 a tick
    mov     dword [surv + SURVIVAL.saturation], 0
    mov     dword [surv + SURVIVAL.health], 7
    mov     edi, 1200
    call    surv_steps
    CHK     [surv + SURVIVAL.health], 1         ; 7 -> 5 -> 3 -> 1: only above the floor does it bite
    mov     dword [surv_max_health], 20         ; the standard character again
    ; ---- 10. the Kingslayer heals a tenth of the health when it parries ---------------------------------
    call    survival_reset
    call    combat_reset
    mov     dword [gear_powers], 1 << LP_KINGSLAYER
    mov     dword [surv + SURVIVAL.health], 10
    mov     edi, 1
    call    combat_set_guard
    HIT_FRONT 3
    cmp     eax, HIT_PARRIED
    jne     .fail
    CHK     [surv + SURVIVAL.health], 12
    mov     dword [gear_powers], 0
    ; ---- 11. Blood Magic pays mana in health, 1 per 5 (rounded up), never the last point ----------------
    call    survival_reset
    call    combat_reset
    mov     dword [rpg_keystones], 1 << KS_BLOOD_MAGIC
    mov     dword [combat_mana], 0
    mov     edi, RES_MANA
    movss   xmm0, [f25]
    call    combat_pay
    cmp     eax, 1
    jne     .fail
    CHK     [surv + SURVIVAL.health], 15
    CHK     [surv + SURVIVAL.hurt_flash], 6
    FNEAR   [combat_mana], k_0
    mov     dword [surv + SURVIVAL.health], 5
    mov     edi, RES_MANA
    movss   xmm0, [f25]
    call    combat_pay                          ; 5 health would leave none
    test    eax, eax
    jnz     .fail
    CHK     [surv + SURVIVAL.health], 5
    mov     dword [game_mode], MODE_CREATIVE
    mov     edi, RES_MANA
    movss   xmm0, [f25]
    call    combat_pay                          ; creative always pays and takes nothing
    cmp     eax, 1
    jne     .fail
    CHK     [surv + SURVIVAL.health], 5
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [rpg_keystones], 0
    mov     dword [combat_mana], __float32__(100.0)
    mov     edi, RES_MANA
    movss   xmm0, [f25]
    call    combat_pay                          ; without the keystone mana is mana
    cmp     eax, 1
    jne     .fail
    FNEAR   [combat_mana], k_75
    CHK     [surv + SURVIVAL.health], 5
    ; ---- 12. Wind Runner: dodging is free, and slower to recover ------------------------------------
    call    combat_reset
    mov     dword [player + BODY.on_ground], 1
    mov     dword [combat_stamina], 0
    lea     rdi, [inp]
    mov     ecx, INPUT_size
    xor     eax, eax
    rep     stosb
    mov     dword [inp + INPUT.fwd], 1
    lea     rdi, [inp]
    call    combat_dodge                        ; no stamina: refused
    test    eax, eax
    jnz     .fail
    mov     dword [rpg_keystones], 1 << KS_WIND_RUNNER
    lea     rdi, [inp]
    call    combat_dodge
    cmp     eax, 1
    jne     .fail
    FNEAR   [combat_stamina], k_0
    CHK     [combat_dodge_cd], 60
    mov     dword [rpg_keystones], 0
    ; ---- 13. life regeneration: tenths of a point per second ------------------------------------------
    call    survival_reset
    call    combat_reset
    POKE    STAT_LIFE_REGEN, 30                 ; 3 per second
    mov     dword [surv + SURVIVAL.health], 10
    mov     edi, 70
    call    steps
    CHK     [surv + SURVIVAL.health], 13        ; 3.5 points: 3 healed, half kept
    POKE    STAT_LIFE_REGEN, 0
    ; ---- 14. a skeleton's elemental arrow afflicts the player; Juggernaut takes no knockback ----------
    call    survival_reset
    call    combat_reset
    mov     edi, ELEM_POISON << AF_ELEM_SHIFT
    call    mob_arrow
    CHK     [surv + SURVIVAL.health], 17
    CHK     [combat_poison], 1
    CHK     [combat_poison_t], 240
    FNEAR   [player + BODY.kbz], k_4            ; shoved along +z
    call    survival_reset
    call    combat_reset
    mov     edi, ELEM_FIRE << AF_ELEM_SHIFT
    call    mob_arrow
    CHK     [combat_burn_t], 180
    call    survival_reset
    call    combat_reset
    mov     edi, ELEM_FROST << AF_ELEM_SHIFT
    call    mob_arrow
    CHK     [combat_chill_t], 120
    call    survival_reset
    call    combat_reset
    mov     dword [rpg_keystones], 1 << KS_JUGGERNAUT
    xor     edi, edi
    call    mob_arrow
    CHK     [surv + SURVIVAL.health], 17
    FNEAR   [player + BODY.kbz], k_0            ; no knockback
    call    combat_kb_mult
    movss   [tmp], xmm0
    FNEAR   [tmp], k_0
    mov     dword [rpg_keystones], 0
    call    combat_kb_mult
    movss   [tmp], xmm0
    FNEAR   [tmp], f1
    ; ---- 15. a blast hurts by max health / 20 (or explode_dmg_mult) and throws, unless Juggernaut -----
    mov     dword [settings + SETTINGS.difficulty], DIFF_EASY   ; 12 at full strength
    call    survival_reset
    mov     dword [player + BODY.kbx], 0
    mov     dword [player + BODY.on_ground], 1
    mov     dword [player + BODY.vy], 0
    call    blast
    CHK     [surv + SURVIVAL.health], 11        ; 12 * 0.75 = 9
    cmp     dword [player + BODY.kbx], 0
    je      .fail                               ; thrown away from the blast...
    movss   xmm0, [player + BODY.vy]
    comiss  xmm0, [k_0]
    jbe     .fail                               ; ...and up
    call    survival_reset
    mov     dword [surv_max_health], 40
    mov     dword [surv + SURVIVAL.health], 40
    call    blast
    CHK     [surv + SURVIVAL.health], 22        ; twice the health, twice the damage: 18
    call    survival_reset
    mov     dword [surv + SURVIVAL.health], 100
    mov     dword [explode_dmg_mult], __float32__(3.0)
    call    blast
    CHK     [surv + SURVIVAL.health], 73        ; a creeper of level 3: 27
    mov     dword [explode_dmg_mult], 0
    mov     dword [surv_max_health], 20         ; the standard character again
    call    survival_reset
    mov     dword [rpg_keystones], 1 << KS_JUGGERNAUT
    mov     dword [player + BODY.kbx], 0
    mov     dword [player + BODY.vy], 0
    call    blast
    CHK     [surv + SURVIVAL.health], 11
    FNEAR   [player + BODY.kbx], k_0            ; it hurts but does not throw...
    FNEAR   [player + BODY.vy], k_0             ; ...nor up
    mov     dword [rpg_keystones], 0
    xor     ebx, ebx
    jmp     .ret
.fail:
    mov     ebx, 1
.ret:
    mov     dword [explode_dmg_mult], 0
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    call    arrows_clear
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; mob_arrow(edi flags): a skeleton's arrow (3 damage) flies at 30 blocks/s along +z from 2 blocks in front
; of the player; 12 steps
mob_arrow:
    push    rbp
    mov     rbp, rsp
    push    r12
    sub     rsp, 8
    mov     r8d, edi
    call    arrows_clear
    movss   xmm0, [k_16_5]
    movss   xmm1, [f11_5]
    movss   xmm2, [k_14_5]
    xorps   xmm3, xmm3
    xorps   xmm4, xmm4
    movss   xmm5, [k_30]
    mov     edi, 1
    mov     esi, 3
    xor     edx, edx
    mov     ecx, PROJ_ARROW
    call    arrows_spawn
    mov     r12d, 12
.fly:
    call    arrows_step
    dec     r12d
    jnz     .fly
    add     rsp, 8
    pop     r12
    pop     rbp
    ret

; blast(): explode_at, radius 3, centred 1.5 blocks west of the player's body middle (y 11.9)
blast:
    sub     rsp, 8
    movss   xmm0, [f15]
    movss   xmm1, [f11_9]
    movss   xmm2, [k_16_5]
    movss   xmm3, [f3]
    call    explode_at
    add     rsp, 8
    ret

; ---- whole frames: the heavy attack's button logic, the spear's reach, digging, the bow, potions ---

; frame(edi lmb_held, esi lmb_pressed, edx rmb_held, ecx rmb_pressed): one 1/60 s game_frame with those buttons
frame:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    mov     [rsp], edi
    mov     [rsp + 4], esi
    mov     [rsp + 8], edx
    mov     [rsp + 12], ecx
    lea     rdi, [frame_input]
    mov     ecx, FRAMEINPUT_size
    xor     eax, eax
    rep     stosb
    mov     dword [frame_input + FRAMEINPUT.slot], -1
    mov     eax, [rsp]
    mov     [frame_input + FRAMEINPUT.lmb_held], eax
    mov     eax, [rsp + 4]
    mov     [frame_input + FRAMEINPUT.lmb_pressed], eax
    mov     eax, [rsp + 8]
    mov     [frame_input + FRAMEINPUT.rmb_held], eax
    mov     eax, [rsp + 12]
    mov     [frame_input + FRAMEINPUT.rmb_pressed], eax
    movss   xmm0, [k_step]
    call    game_frame
    leave
    ret

; frames(edi n, esi lmb_held, edx rmb_held): n frames with that held state and no presses
frames:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
.l:
    mov     edi, r13d
    xor     esi, esi
    mov     edx, r14d
    xor     ecx, ecx
    call    frame
    dec     r12d
    jnz     .l
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    ret

%macro PRESS 0                          ; the left button goes down
    mov     edi, 1
    mov     esi, 1
    xor     edx, edx
    xor     ecx, ecx
    call    frame
%endmacro
%macro RELEASE 0                        ; every button up
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    xor     ecx, ecx
    call    frame
%endmacro
%macro IDLE 1                           ; n frames of nothing
    mov     edi, %1
    xor     esi, esi
    xor     edx, edx
    call    frames
%endmacro
%macro HOLD 1                           ; n frames with the left button held
    mov     edi, %1
    mov     esi, 1
    xor     edx, edx
    call    frames
%endmacro
%macro RPRESS 0                         ; the right button goes down
    xor     edi, edi
    xor     esi, esi
    mov     edx, 1
    mov     ecx, 1
    call    frame
%endmacro
%macro PLACE 1                          ; the zombie (rbx) stands still at that z, not pushed: it cannot leave the crosshair
    mov     dword [rbx + BODY.z], __float32__(%1)
    mov     dword [rbx + BODY.speed], 0
    mov     dword [rbx + BODY.kbx], 0
    mov     dword [rbx + BODY.kbz], 0
%endmacro
%macro RHOLD 1                          ; n frames with the right button held
    mov     edi, %1
    xor     esi, esi
    mov     edx, 1
    call    frames
%endmacro

; frame_setup(): the world of the frame checks: Creative at night on a stone platform (x, z 12..20 at
; y 10), the player at (16.5, 11, 16.5) looking along -z, no mobs, an empty hand
frame_setup:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    mov     dword [game_mode], MODE_CREATIVE
    mov     dword [game_time], 40000
    mov     dword [input_captured], 1
    mov     dword [game_open_screen], 0
    mov     dword [game_heavy_s], __float32__(-1.0)
    mov     dword [game_bow_charge], 0
    mov     r12d, 12
.z:
    mov     ebx, 12
.x:
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 20
    jbe     .x
    inc     r12d
    cmp     r12d, 20
    jbe     .z
    pop     r12
    pop     rbx
    pop     rbp
    ret

; frame_checks() -> eax 0 when the game frame does what the combat rules say: a left button held on a
; mob for 0.5 s lands a heavy blow on release (a short click or another tool does not), the guard
; and a villager-free crosshair decide whether a charge starts, a spear reaches 4.5 blocks, a click on
; a block digs instead of charging, the bow shoots 1 + round(8 power) (13 for the Celestial Bow) with
; the attack flag, costs an arrow and never wears, and potions heal max(8, ...) / restore max(50, ...)
frame_checks:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    frame_setup
    ; ---- A. a heavy attack: hold the left button on a mob for half a second, release ---------------
    FRESH   MOB_ZOMBIE
    PLACE   14.5                                       ; 2 blocks ahead
    HELD    IRON_SWORD
    PRESS                                              ; a light strike, and the charge starts
    CHK     [rbx + MOB.health], 93
    CHK     [game_heavy_s], 0
    HOLD    31
    movss   xmm0, [game_heavy_s]
    comiss  xmm0, [f0_5]
    jb      .fail
    PLACE   14.5                                       ; however far the light blow threw it, it stands there again
    RELEASE                                            ; after 0.5 s: the heavy blow
    CHK     [rbx + MOB.health], 78
    CHK     [rbx + MOB.stun], 20
    CHK     [rbx + MOB.bleed_t], 180
    CHK     [game_heavy_s], 0xBF800000                 ; idle again: -1.0
    ; ---- B. a short click is a light strike and nothing more -----------------------------------------
    call    combat_reset                               ; no combo from the section before
    FRESH   MOB_ZOMBIE
    PLACE   14.5
    IDLE    40                                         ; the cooldown of the heavy blow runs out
    PRESS
    CHK     [rbx + MOB.health], 93
    HOLD    10
    RELEASE
    CHK     [rbx + MOB.health], 93
    CHK     [game_heavy_s], 0xBF800000
    ; ---- C. no charge with a tool in hand, nor with the guard going up -------------------------------
    call    combat_reset
    HELD    IRON_PICKAXE
    IDLE    40
    PRESS
    CHK     [game_heavy_s], 0xBF800000
    RELEASE
    HELD    IRON_SWORD
    IDLE    40
    mov     edi, 1
    mov     esi, 1
    mov     edx, 1
    mov     ecx, 1
    call    frame                                      ; both buttons: the guard goes up
    CHK     [game_heavy_s], 0xBF800000
    RELEASE
    ; ---- D. a spear reaches 4.5 blocks, a sword 3.5 ----------------------------------------------------
    call    combat_reset
    FRESH   MOB_ZOMBIE
    PLACE   12.3                                       ; 4.2 blocks away
    HELD    IRON_SWORD
    PRESS
    CHK     [rbx + MOB.health], 100                    ; out of a sword's reach
    RELEASE
    HELD    IRON_SPEAR
    IDLE    40
    PRESS
    CHK     [rbx + MOB.health], 94                     ; within a spear's: 6
    RELEASE
    ; ---- E. a click on a block digs; on thin air it starts a charge ------------------------------------
    call    mobs_clear
    mov     edi, 16
    mov     esi, 12
    mov     edx, 14
    mov     ecx, STONE
    call    world_set
    HELD    IRON_SWORD
    IDLE    40
    PRESS                                              ; Creative breaks it at once
    mov     edi, 16
    mov     esi, 12
    mov     edx, 14
    call    world_get
    test    eax, eax
    jnz     .fail
    CHK     [game_heavy_s], 0xBF800000
    RELEASE
    IDLE    5
    PRESS                                              ; nothing in reach: the charge starts
    CHK     [game_heavy_s], 0
    mov     edi, 16                                    ; a block in reach now: the held button does not dig it
    mov     esi, 12
    mov     edx, 14
    mov     ecx, STONE
    call    world_set
    HOLD    40
    mov     edi, 16
    mov     esi, 12
    mov     edx, 14
    call    world_get
    cmp     eax, STONE
    jne     .fail
    RELEASE                                            ; a swing at the air
    CHK     [game_heavy_s], 0xBF800000
    ; ---- F. the bow in Creative: damage 1 + round(8 power), 13 for the Celestial Bow ------------------
    HELD    BOW
    call    arrows_clear
    RPRESS
    RHOLD   60
    RELEASE                                            ; a full draw
    CHK     [arrows + ARROWENT.live], 1
    CHK     [arrows + ARROWENT.damage], 9
    CHK     [arrows + ARROWENT.flags], AF_ATTACK
    CHK     [arrows + ARROWENT.owner], 0
    CHK     [arrows + ARROWENT.kind], PROJ_ARROW
    CHK     [game_bow_charge], 0
    call    arrows_clear
    RPRESS
    RHOLD   29
    RELEASE                                            ; half a draw: power 0.40, 1 + round(3.2)
    CHK     [arrows + ARROWENT.damage], 4
    HELD    CELESTIAL_BOW
    call    arrows_clear
    RPRESS
    RHOLD   60
    RELEASE
    CHK     [arrows + ARROWENT.damage], 13             ; 9 * 3 / 2
    CHK     [arrows + ARROWENT.flags], AF_ATTACK
    ; ---- G. the bow in Survival costs an arrow and never wears ------------------------------------------
    mov     dword [game_mode], MODE_SURVIVAL
    call    arrows_clear
    HELD    BOW
    mov     byte [inv + INVENTORY.slots + 4 + ITEMSTACK.id], ARROW
    mov     byte [inv + INVENTORY.slots + 4 + ITEMSTACK.count], 5
    RPRESS
    RHOLD   60
    RELEASE
    CHK     [arrows + ARROWENT.damage], 9
    CHK     [arrows + ARROWENT.pickup], 1              ; a used-up arrow can be picked up again
    cmp     byte [inv + INVENTORY.slots + 4 + ITEMSTACK.count], 4
    jne     .fail
    cmp     word [inv + INVENTORY.slots + ITEMSTACK.dmg], 0
    jne     .fail                                      ; the bow did not wear
    ; ---- H. potions: a health potion heals 8 (at 20 health), a mana potion restores 50 ---------------
    HELD    HEALTH_POTION
    mov     byte [inv + INVENTORY.slots + ITEMSTACK.count], 2
    mov     dword [surv + SURVIVAL.health], 5
    RPRESS
    CHK     [surv + SURVIVAL.health], 13
    cmp     byte [inv + INVENTORY.slots + ITEMSTACK.count], 1
    jne     .fail
    mov     byte [rpg_state + RPGSAVE.class], CLASS_MAGE        ; 100 mana
    HELD    MANA_POTION
    mov     dword [combat_mana], 0
    RPRESS
    movss   xmm0, [combat_mana]
    comiss  xmm0, [f50]
    jb      .fail                                      ; at least 50 (and a few steps of regeneration)
    comiss  xmm0, [f50_5]
    jae     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [game_time], NEW_WORLD_TIME
    mov     dword [input_captured], 0
    mov     dword [game_heavy_s], __float32__(-1.0)
    mov     dword [game_bow_charge], 0
    mov     ebx, eax
    call    arrows_clear
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret