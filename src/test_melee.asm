; test_melee.asm - guard and parry, the dodge roll, melee combos, crits and backstabs, stamina and
; mana regeneration, max health.
%include "common.inc"
default rel

global test_guard_blocks_and_parries, test_dodge_iframes_and_stamina
global test_melee_combo_crit_backstab, test_stamina_mana_regen_and_max_health

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

section .bss
align 4
inp: resb INPUT_size
tmp: resd 1

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
    mov     edi, 10
    mov     esi, CAUSE_FALL
    call    survival_damage
    CHK     [surv + SURVIVAL.health], 2
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
