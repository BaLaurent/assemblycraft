; test_status.asm - the statuses a mob carries (status.asm): damage over time, poison stacks, chill
; and the freeze, shock, the mark, expiry, and the reward of a kill by a status.
%include "common.inc"
default rel

global test_status_effects

extern rpg_spend, rpg_ext, rpg_recompute
extern mobs, mobs_clear, mob_spawn, drops_clear
extern status_apply, status_step, status_speed_mult, status_damage_mult
extern rpg_reset, rpg_state, rpg_stats, rpg_keystones, gear_powers
extern combat_reset, combat_hit_flags, survival_reset, game_mode, settings
extern world_clear, rng_seed, inv_clear

section .rodata
align 16
absmask:  dd 0x7FFFFFFF, 0, 0, 0
align 4
k_eps:    dd 0.0001
k_5:      dd 5.0
k_10:     dd 10.0
k_11:     dd 11.0
k_16_5:   dd 16.5
k_0_6:    dd 0.6
k_0_8:    dd 0.8
k_0_8333: dd 0.8333333                  ; 0.5 * 10 / 6
k_1_2:    dd 1.2                        ; 0.08 * 10 * 1.5
k_1_25:   dd 1.25                       ; 0.5 * 10 * 1.5 / 6
k_1_15:   dd 1.15
k_1_495:  dd 1.495                      ; 1.15 * 1.3
k_1_0465: dd 1.0465                     ; 1.15 * 1.3 * 0.7

section .bss
align 4
tmp: resd 1

section .text
; take_path(edi arch 0..4): the character takes that archetype's path (0: none, a fresh character)
; at its current level, with the stats recomputed. Kits are poked given so the spend wears nothing;
; the spend refills mana and stamina. Clobbers the usual caller-saved registers.
take_path:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     ebx, edi
    movzx   r12d, byte [rpg_state + RPGSAVE.level]
    call    rpg_reset
    test    ebx, ebx
    jz      .done
    mov     byte [rpg_state + RPGSAVE.level], 50
    mov     byte [rpg_ext + RPGEXT.kits], 0xFF
    lea     edi, [rbx - 1]
    call    rpg_spend
    mov     byte [rpg_state + RPGSAVE.level], r12b
.done:
    mov     byte [rpg_state + RPGSAVE.level], r12b
    call    rpg_recompute
    add     rsp, 8
    pop     r12
    pop     rbx
    ret


; fail unless |float at %1 - float constant %2| < 1e-4 (NaN fails)
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

; APPLY kind, magnitude constant: status_apply(slot 0, kind, magnitude)
%macro APPLY 2
    xor     edi, edi
    mov     esi, %1
    movss   xmm0, [%2]
    call    status_apply
%endmacro

; fixture(): after world_clear: rng seed 1234, no mobs or drops, class none at level 1, Survival at
; Normal difficulty, fresh survival and combat state, no keystones and no legendary powers
fixture:
    sub     rsp, 8
    mov     edi, 1234
    call    rng_seed
    call    mobs_clear
    call    drops_clear
    call    inv_clear
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    call    rpg_reset
    mov     dword [rpg_keystones], 0
    mov     dword [gear_powers], 0
    call    survival_reset
    call    combat_reset
    add     rsp, 8
    ret

; cleanup(): leave no mobs, drops, class or poked stats behind
cleanup:
    sub     rsp, 8
    call    mobs_clear
    call    drops_clear
    call    inv_clear
    call    rpg_reset
    mov     dword [rpg_keystones], 0
    mov     dword [gear_powers], 0
    call    survival_reset
    call    combat_reset
    add     rsp, 8
    ret

; spawn(edi type) -> rbx the mob (slot 0 after mobs_clear): at (16.5, 11, 16.5), 100 health, level 1
spawn:
    sub     rsp, 8
    movss   xmm0, [k_16_5]
    movss   xmm1, [k_11]
    movss   xmm2, [k_16_5]
    call    mob_spawn
    imul    ecx, eax, MOB_size
    lea     rbx, [mobs]
    add     rbx, rcx
    mov     dword [rbx + MOB.health], 100
    mov     dword [rbx + MOB.max_health], 100
    mov     dword [rbx + MOB.level], 1
    add     rsp, 8
    ret

; steps(edi n >= 1): n times status_step
steps:
    push    rbp
    mov     rbp, rsp
    push    r12
    sub     rsp, 8
    mov     r12d, edi
.l:
    call    status_step
    dec     r12d
    jnz     .l
    add     rsp, 8
    pop     r12
    pop     rbp
    ret

; Burn deals its damage every 30 steps (the first at once), 6 times in 180 steps; status_apply sets
; the damage over time from the magnitude and DOT_DMG, and a weaker hit never lowers it; three
; applications of poison make three stacks that tick for round(3 * 0.08 * magnitude), capped at 10
; stacks (20 with the Viper); the third chill freezes (stun 90, 30 for the boss, 20 for a
; juggernaut), a fourth during the cooldown only chills; shock stops at 3 stacks; marks, shock and
; armor scale the damage a mob takes, a tick included; expired timers clear their stacks; a mob
; killed by a status pays its XP.
test_status_effects:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    fixture
    ; ---- 1. burn: 1 damage per tick, 6 ticks over 180 steps -------------------------------------
    mov     edi, MOB_ZOMBIE
    call    spawn
    mov     dword [rbx + MOB.burn_t], 180
    mov     dword [rbx + MOB.burn_dmg], __float32__(1.0)
    call    status_step                 ; step 1: the first tick
    CHK     [rbx + MOB.health], 99
    mov     edi, 29                     ; steps 2..30: nothing
    call    steps
    CHK     [rbx + MOB.health], 99
    call    status_step                 ; step 31: the second tick
    CHK     [rbx + MOB.health], 98
    mov     edi, 149                    ; to step 180
    call    steps
    CHK     [rbx + MOB.health], 94
    CHK     [rbx + MOB.burn_t], 0
    CHK     [rbx + MOB.burn_dmg], 0     ; the per-tick damage went with the timer
    mov     edi, 60                     ; and nothing more is coming
    call    steps
    CHK     [rbx + MOB.health], 94
    ; ---- 2. status_apply: burn and bleed are half the magnitude over six ticks -----------------
    call    mobs_clear
    mov     edi, MOB_ZOMBIE
    call    spawn
    APPLY   STS_BURN, k_10
    CHK     [rbx + MOB.burn_t], 180
    FNEAR   [rbx + MOB.burn_dmg], k_0_8333
    mov     dword [rbx + MOB.burn_t], 7
    APPLY   STS_BURN, k_5               ; a weaker hit restarts the timer but keeps the damage
    CHK     [rbx + MOB.burn_t], 180
    FNEAR   [rbx + MOB.burn_dmg], k_0_8333
    APPLY   STS_BLEED, k_10
    CHK     [rbx + MOB.bleed_t], 180
    FNEAR   [rbx + MOB.bleed_dmg], k_0_8333
    mov     dword [rpg_stats + STAT_DOT_DMG * 4], 50    ; +50 % damage over time
    APPLY   STS_BURN, k_10
    FNEAR   [rbx + MOB.burn_dmg], k_1_25
    ; ---- 3. poison: stacks, tick, DOT_DMG, caps ------------------------------------------------
    call    mobs_clear
    mov     dword [rpg_stats + STAT_DOT_DMG * 4], 0
    mov     edi, MOB_ZOMBIE
    call    spawn
    APPLY   STS_POISON, k_10
    APPLY   STS_POISON, k_10
    APPLY   STS_POISON, k_10
    CHK     [rbx + MOB.poison], 3
    CHK     [rbx + MOB.poison_t], 240
    FNEAR   [rbx + MOB.poison_dmg], k_0_8       ; 0.08 * 10 per stack and tick
    mov     dword [rbx + MOB.dot_tick], 1
    call    status_step                 ; 3 * 0.8 = 2.4: a tick of 2
    CHK     [rbx + MOB.health], 98
    mov     dword [rpg_stats + STAT_DOT_DMG * 4], 50
    APPLY   STS_POISON, k_10            ; a stronger stack raises the per-stack damage
    FNEAR   [rbx + MOB.poison_dmg], k_1_2
    mov     dword [rpg_stats + STAT_DOT_DMG * 4], 0
    mov     r12d, 10
.stack10:
    APPLY   STS_POISON, k_10
    dec     r12d
    jnz     .stack10
    CHK     [rbx + MOB.poison], 10      ; at most 10 stacks
    mov     dword [gear_powers], 1 << LP_VIPER
    mov     r12d, 20
.stack20:
    APPLY   STS_POISON, k_10
    dec     r12d
    jnz     .stack20
    CHK     [rbx + MOB.poison], 20      ; the Viper amulet doubles the cap
    mov     dword [gear_powers], 0
    ; ---- 4. chill: two stacks slow, the third freezes -------------------------------------------
    call    mobs_clear
    mov     edi, MOB_ZOMBIE
    call    spawn
    APPLY   STS_CHILL, k_10
    APPLY   STS_CHILL, k_10
    CHK     [rbx + MOB.chill], 2
    CHK     [rbx + MOB.chill_t], 120
    mov     rdi, rbx
    call    status_speed_mult
    movss   [tmp], xmm0
    FNEAR   [tmp], k_0_6                ; 1 - 0.2 * 2
    CHK     [rbx + MOB.stun], 0
    APPLY   STS_CHILL, k_10             ; the third chill: frozen
    CHK     [rbx + MOB.stun], 90
    CHK     [rbx + MOB.freeze_cd], 120
    CHK     [rbx + MOB.chill], 0
    CHK     [rbx + MOB.chill_t], 0
    mov     dword [rbx + MOB.stun], 0
    APPLY   STS_CHILL, k_10             ; during the cooldown it only chills
    CHK     [rbx + MOB.chill], 1
    APPLY   STS_CHILL, k_10
    APPLY   STS_CHILL, k_10
    APPLY   STS_CHILL, k_10
    CHK     [rbx + MOB.chill], 2        ; stopping at 2 stacks
    CHK     [rbx + MOB.stun], 0
    mov     dword [rbx + MOB.freeze_cd], 1
    call    status_step                 ; the cooldown ends...
    CHK     [rbx + MOB.freeze_cd], 0
    APPLY   STS_CHILL, k_10             ; ...and the next chill freezes at once (2 stacks + 1)
    CHK     [rbx + MOB.stun], 90
    call    mobs_clear                  ; a juggernaut thaws in 20 steps
    mov     edi, MOB_ZOMBIE
    call    spawn
    mov     dword [rbx + MOB.affix], AFX_JUGGERNAUT
    APPLY   STS_CHILL, k_10
    APPLY   STS_CHILL, k_10
    APPLY   STS_CHILL, k_10
    CHK     [rbx + MOB.stun], 20
    call    mobs_clear                  ; the boss in 30
    mov     edi, MOB_BOSS
    call    spawn
    APPLY   STS_CHILL, k_10
    APPLY   STS_CHILL, k_10
    APPLY   STS_CHILL, k_10
    CHK     [rbx + MOB.stun], 30
    ; ---- 5. shock, mark and armor scale the damage taken ---------------------------------------
    call    mobs_clear
    mov     edi, MOB_ZOMBIE
    call    spawn
    mov     r12d, 5
.shock:
    APPLY   STS_SHOCK, k_10
    dec     r12d
    jnz     .shock
    CHK     [rbx + MOB.shock], 3        ; at most 3 stacks
    CHK     [rbx + MOB.shock_t], 240
    mov     rdi, rbx
    call    status_damage_mult
    movss   [tmp], xmm0
    FNEAR   [tmp], k_1_15               ; 1 + 0.05 * 3
    mov     dword [rbx + MOB.mark_t], 100
    mov     rdi, rbx
    call    status_damage_mult
    movss   [tmp], xmm0
    FNEAR   [tmp], k_1_495              ; marked: 30 % more
    mov     dword [rbx + MOB.affix], AFX_ARMORED
    mov     rdi, rbx
    call    status_damage_mult
    movss   [tmp], xmm0
    FNEAR   [tmp], k_1_0465             ; armored: 30 % less
    ; a tick is scaled too: burn 20 per tick * (1.15 * 1.3 * 0.7) = 20.93 rounds to 21
    mov     dword [rbx + MOB.burn_t], 100
    mov     dword [rbx + MOB.burn_dmg], __float32__(20.0)
    call    status_step
    CHK     [rbx + MOB.health], 79
    ; ---- 6. expiry: a timer that runs out takes its stacks and damage with it -----------------
    call    mobs_clear
    mov     edi, MOB_ZOMBIE
    call    spawn
    mov     dword [rbx + MOB.poison_t], 2
    mov     dword [rbx + MOB.poison], 3
    mov     dword [rbx + MOB.poison_dmg], __float32__(0.8)
    mov     dword [rbx + MOB.chill_t], 1
    mov     dword [rbx + MOB.chill], 2
    mov     dword [rbx + MOB.shock_t], 1
    mov     dword [rbx + MOB.shock], 3
    mov     dword [rbx + MOB.mark_t], 1
    mov     dword [rbx + MOB.dot_tick], 5
    call    status_step
    CHK     [rbx + MOB.poison], 3       ; one step left
    CHK     [rbx + MOB.chill], 0
    CHK     [rbx + MOB.shock], 0
    CHK     [rbx + MOB.mark_t], 0
    call    status_step
    CHK     [rbx + MOB.poison_t], 0
    CHK     [rbx + MOB.poison], 0
    CHK     [rbx + MOB.poison_dmg], 0
    CHK     [rbx + MOB.health], 100     ; no tick fell due meanwhile
    ; ---- 7. a mob killed by a status pays the player's XP --------------------------------------
    call    mobs_clear
    mov     edi, ARCH_WARRIOR
    call    take_path
    mov     dword [rpg_state + RPGSAVE.xp], 0
    mov     edi, MOB_ZOMBIE
    call    spawn
    mov     dword [rbx + MOB.health], 1
    mov     dword [rbx + MOB.tagged], 100               ; the player hit it earlier
    mov     dword [rbx + MOB.burn_t], 60
    mov     dword [rbx + MOB.burn_dmg], __float32__(5.0)
    call    status_step
    CHK     [rbx + MOB.type], MOB_NONE                  ; it died of the burn
    CHK     [combat_hit_flags], 0                       ; the tick left no flags behind
    CHK     [rpg_state + RPGSAVE.xp], 10                ; and a tagged zombie's kill is worth 10 XP
    xor     eax, eax
    jmp     .done
.fail:
    mov     eax, 1
.done:
    mov     r12d, eax
    call    cleanup
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret
