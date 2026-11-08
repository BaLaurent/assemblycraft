; combat.asm - the player's fighting rules: stamina and mana, the guard and its perfect parry, the
; dodge roll, the damage pipeline every hit the player lands on a mob goes through (combat_calc,
; combat_hit_mob), melee strikes (combo, crits, backstabs, riposte, warhammer stuns), the heavy
; attack, hits taken from monsters (parry, block, Mana Shield, thorns), the burn, chill and poison
; the player can suffer, and the timers the class abilities set. Timers count fixed 1/60 s steps and
; age in combat_step, which runs once per step. Stats come from rpg_stats (rpg.asm); the statuses of
; mobs are in status.asm.
%include "common.inc"
default rel

global combat_mana, combat_stamina
global combat_guard_t, combat_guard_break_t, combat_dodge_t, combat_dodge_cd
global combat_attack_cd, combat_combo, combat_combo_t, combat_riposte_t
global combat_crit_next_t, combat_warcry_t, combat_blade_t, combat_stealth_t
global combat_slow_t, combat_spend_t
global combat_burn_t, combat_chill_t, combat_poison_t, combat_poison, combat_phoenix_cd
global combat_hitstop, combat_hit_flags, combat_life_carry, combat_attacker
global combat_reset, combat_refill, combat_max_mana, combat_max_stamina, combat_step
global combat_spend, combat_pay, combat_set_guard, combat_dodge, combat_melee, combat_heavy
global player_take_hit, combat_speed_mult, combat_crit_roll, combat_crit_mult, combat_heal
global combat_hit_mob, combat_calc, combat_weapon_preview, combat_kb_mult, combat_player_status

extern rpg_stats, rpg_keystones, rpg_class, gear_powers, surv, surv_max_health, game_mode
extern player, player_eye, player_forward, sincos_deg, rng_next
extern inv_held, item_tool, item_gear, item_attack_damage
extern mobs, mob_strike, mob_hurt, mob_is_hostile, mob_resist, survival_damage, survival_dot
extern status_apply, status_damage_mult, abilities_cd
extern audio_play, fx_shake, fx_burst, dmgnum_text

%define SPEND_PAUSE    36               ; steps stamina regeneration waits after a spend
%define PARRY_BASE     6                ; a hit within this many steps (+ PARRY_WINDOW) of raising the guard is parried
%define BREAK_STEPS    60               ; steps a broken guard stays down
%define RIPOSTE_STEPS  60               ; steps after a parry or a perfect dodge that the next strike is a forced crit
%define DODGE_STEPS    16               ; steps of invulnerability in a roll
%define DODGE_COOLDOWN 30
%define WIND_COOLDOWN  60               ; Wind Runner: dodges cost nothing but recover twice as slowly
%define COMBO_WINDOW   45               ; steps a hit keeps the combo alive
%define DOT_PERIOD     30               ; steps between two burn / poison ticks the player takes
%define BURN_STEPS     180
%define CHILL_STEPS    120
%define POISON_STEPS   240
%define POISON_STACKS  5

; player_take_hit returns survival_damage's 0/1 as HIT_NONE / HIT_TAKEN
%if HIT_TAKEN != 1
%error "combat.asm: HIT_TAKEN must be 1"
%endif

; DOT_ARM: when neither a burn nor a poison runs yet, the first tick comes a full period after the
; one now starting
%macro DOT_ARM 0
    cmp     dword [combat_burn_t], 0
    jg      %%armed
    cmp     dword [combat_poison_t], 0
    jg      %%armed
    mov     dword [combat_dot_t], DOT_PERIOD
%%armed:
%endmacro

; the numeric value of a stat as a float
%macro STATF 2                          ; xmm register, stat id
    cvtsi2ss %1, dword [rpg_stats + %2 * 4]
%endmacro

section .rodata
align 4
melee_cd:    db 10, 14, 18, 14, 12, 7, 20, 14   ; melee cooldown in steps by held tool: none, pickaxe, axe, shovel, sword, dagger, hammer, spear
align 4
k_0:         dd 0.0
k_0_01:      dd 0.01                    ; a hit below this does no damage at all: the target is immune
k_1:         dd 1.0
k_2:         dd 2.0                     ; a warhammer's third combo hit
k_2_2:       dd 2.2                     ; the heavy attack's damage...
k_2_5:       dd 2.5                     ; ...and its knockback
k_4:         dd 4.0
k_5:         dd 5.0
k_7:         dd 7.0                     ; the Archmage staff's bolt
k_9:         dd 9.0                     ; a fully drawn bow
k_10:        dd 10.0
k_16:        dd 16.0                    ; dodge roll speed, blocks/s
k_20:        dd 20.0                    ; stamina of a heavy attack
k_25:        dd 25.0
k_36:        dd 36.0                    ; 6 blocks, squared: how far a storm arcs
k_60:        dd 60.0
k_100:       dd 100.0
k_120:       dd 120.0                   ; stamina of a block: 120 * damage / max health
k_600:       dd 600.0                   ; steps in 10 seconds
k_0_05:      dd 0.05
k_0_09:      dd 0.09
k_0_2:       dd 0.2                     ; stamina drained per sprinting step
k_0_25:      dd 0.25                    ; Inferno: spells on a burning foe
k_0_34:      dd 0.34                    ; cos of the arc a guard covers (about 70 degrees each side)
k_0_35:      dd 0.35                    ; camera shake of a critical hit
k_0_4:       dd 0.4                     ; speed multiplier while guarding
k_0_5:       dd 0.5
k_0_6:       dd 0.6                     ; speed multiplier while chilled
k_0_7:       dd 0.7                     ; speed multiplier while slowed
k_1_2:       dd 1.2                     ; blade dance speed; distance of a floating text from the eye
k_1_3:       dd 1.3                     ; war cry damage; Embers on a burning foe
k_1_5:       dd 1.5
k_1_6:       dd 1.6                     ; Executioner
k_len2:      dd 0.0001                  ; 0.01 blocks, squared
k_m0_3:      dd -0.3                    ; backstab: the mob faces away if dot(forward, to player) is below this
k_m1:        dd -1.0                    ; falling faster than this makes a strike crit
k_regen:     dd 0.33333334              ; stamina regained per step: 20 per second

section .data
align 4
combat_guard_t:       dd -1             ; steps the guard has been up; -1 = down
combat_attacker:      dd -1             ; index of the mob whose melee attack is being resolved; -1 = none

section .bss
align 4
; everything from combat_timers to combat_zero_end is zeroed by combat_reset; the timers age
; together in combat_step
combat_timers:
combat_guard_break_t: resd 1            ; > 0: the guard is broken and cannot be raised
combat_dodge_t:       resd 1            ; > 0: rolling, invulnerable
combat_dodge_cd:      resd 1
combat_attack_cd:     resd 1            ; melee cooldown
combat_combo_t:       resd 1            ; window left to continue the combo
combat_riposte_t:     resd 1            ; > 0: the next strike is a forced crit (after a parry or a perfect dodge)
combat_crit_next_t:   resd 1            ; > 0: the next strike is a forced crit (after Shadowstep)
combat_warcry_t:      resd 1            ; > 0: +30% melee damage, hits taken halved
combat_blade_t:       resd 1            ; > 0: Blade Dance
combat_stealth_t:     resd 1            ; > 0: unseen by monsters
combat_slow_t:        resd 1            ; > 0: slowed (Whirlwind)
combat_spend_t:       resd 1            ; > 0: stamina regeneration paused after a spend
combat_burn_t:        resd 1            ; > 0: burning, the player takes a burn tick every 30 steps
combat_chill_t:       resd 1            ; > 0: chilled, walking is slower
combat_poison_t:      resd 1            ; > 0: poisoned, the player takes a poison tick every 30 steps
combat_phoenix_cd:    resd 1            ; > 0: the Phoenix ring is recovering
combat_timers_end:
combat_combo:         resd 1            ; strikes in the running combo (0..2)
combat_hitstop:       resd 1            ; float seconds of freeze left (the game loop drains it)
combat_life_carry:    resd 1            ; float, lifesteal fraction not yet healed
combat_hit_flags:     resd 1            ; low byte = HF_*; set just before a mob damage call
combat_poison:        resd 1            ; poison stacks 0..5
combat_burn_tick:     resd 1            ; health a burn tick takes
combat_poison_tick:   resd 1            ; health a poison tick takes per stack
combat_dot_t:         resd 1            ; steps to the next burn / poison tick
combat_regen_carry:   resd 1            ; float, life regeneration not yet healed
combat_zero_end:
combat_mana:          resd 1            ; floats
combat_stamina:       resd 1

section .text

; combat_max_mana() -> xmm0 the mana pool
combat_max_mana:
    STATF   xmm0, STAT_MAX_MANA
    ret

; combat_max_stamina() -> xmm0 the stamina pool
combat_max_stamina:
    STATF   xmm0, STAT_MAX_STAMINA
    ret

; combat_refill(): mana and stamina to their maxima
combat_refill:
    STATF   xmm0, STAT_MAX_MANA
    movss   [combat_mana], xmm0
    STATF   xmm0, STAT_MAX_STAMINA
    movss   [combat_stamina], xmm0
    ret

; combat_reset(): every timer 0, guard down, no combo, no hit-stop, full mana and stamina
combat_reset:
    lea     rdi, [combat_timers]
    mov     ecx, (combat_zero_end - combat_timers) / 4
    xor     eax, eax
    rep     stosd
    mov     dword [combat_guard_t], -1
    mov     dword [combat_attacker], -1
    jmp     combat_refill

; combat_step(edi sprinting): once per fixed step. Pays this step's burn and poison tick, heals
; LIFE_REGEN (tenths of a point per second), ages the timers and the guard, regenerates mana, and
; drains (sprinting) or regenerates (idle for SPEND_PAUSE steps) stamina.
combat_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi                    ; sprinting
    call    dot_step                    ; before the timers age: the last step of a status still ticks
    mov     eax, [rpg_stats + STAT_LIFE_REGEN * 4]
    test    eax, eax
    jle     .aging
    cvtsi2ss xmm0, eax
    divss   xmm0, [k_600]
    addss   xmm0, [combat_regen_carry]
    roundss xmm1, xmm0, 9               ; heal the whole points, keep the fraction
    subss   xmm0, xmm1
    movss   [combat_regen_carry], xmm0
    cvttss2si edi, xmm1
    call    combat_heal
.aging:
    lea     rax, [combat_timers]
    lea     rdx, [combat_timers_end]
.age:
    cmp     dword [rax], 0
    jle     .aged
    dec     dword [rax]
.aged:
    add     rax, 4
    cmp     rax, rdx
    jb      .age
    cmp     dword [combat_burn_t], 0    ; a status that ran out takes its stacks and tick with it
    jg      .burning
    mov     dword [combat_burn_tick], 0
.burning:
    cmp     dword [combat_poison_t], 0
    jg      .poisoned
    mov     dword [combat_poison], 0
    mov     dword [combat_poison_tick], 0
.poisoned:
    cmp     dword [combat_guard_t], 0
    jl      .mana
    inc     dword [combat_guard_t]
.mana:
    STATF   xmm0, STAT_MANA_REGEN       ; per second
    divss   xmm0, [k_60]
    addss   xmm0, [combat_mana]
    STATF   xmm1, STAT_MAX_MANA
    minss   xmm0, xmm1
    movss   [combat_mana], xmm0
    movss   xmm0, [combat_stamina]
    test    ebx, ebx
    jnz     .sprint
    cmp     dword [combat_spend_t], 0
    jg      .clamp                      ; still paused after a spend
    STATF   xmm1, STAT_STAMINA_REGEN
    divss   xmm1, [k_100]
    addss   xmm1, [k_1]
    mulss   xmm1, [k_regen]
    addss   xmm0, xmm1
    jmp     .clamp
.sprint:
    cmp     dword [game_mode], MODE_CREATIVE
    je      .clamp                      ; creative sprints for free
    subss   xmm0, [k_0_2]
    mov     dword [combat_spend_t], SPEND_PAUSE
.clamp:
    xorps   xmm1, xmm1
    maxss   xmm0, xmm1
    STATF   xmm1, STAT_MAX_STAMINA
    minss   xmm0, xmm1
    movss   [combat_stamina], xmm0
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; dot_step(): while the player burns or is poisoned, every DOT_PERIOD steps the burn takes its tick
; and the poison its stacks times its tick (survival_dot: no armor, no invulnerability)
dot_step:
    sub     rsp, 8
    cmp     dword [combat_burn_t], 0
    jg      .active
    cmp     dword [combat_poison_t], 0
    jle     .ret
.active:
    dec     dword [combat_dot_t]
    jg      .ret
    mov     dword [combat_dot_t], DOT_PERIOD
    cmp     dword [combat_burn_t], 0
    jle     .poison
    mov     edi, [combat_burn_tick]
    mov     esi, CAUSE_FIRE
    call    survival_dot
.poison:
    cmp     dword [combat_poison_t], 0
    jle     .ret
    mov     edi, [combat_poison]
    imul    edi, [combat_poison_tick]
    mov     esi, CAUSE_POISON
    call    survival_dot
.ret:
    add     rsp, 8
    ret

; combat_spend(edi res, xmm0 amount) -> eax 1 if paid. RES_STAMINA or RES_MANA; nothing is taken
; when the pool is too small. Paying stamina pauses its regeneration. Creative always pays,
; and takes nothing.
combat_spend:
    cmp     dword [game_mode], MODE_CREATIVE
    je      .paid
    test    edi, edi                    ; RES_STAMINA
    jnz     .mana
    movss   xmm1, [combat_stamina]
    ucomiss xmm1, xmm0
    jb      .short
    subss   xmm1, xmm0
    movss   [combat_stamina], xmm1
    mov     dword [combat_spend_t], SPEND_PAUSE
    jmp     .paid
.mana:
    movss   xmm1, [combat_mana]
    ucomiss xmm1, xmm0
    jb      .short
    subss   xmm1, xmm0
    movss   [combat_mana], xmm1
.paid:
    mov     eax, 1
    ret
.short:
    xor     eax, eax
    ret

; combat_pay(edi res, xmm0 amount) -> eax 1 if paid. What an ability or a bolt costs: RES_STAMINA
; or RES_MANA, as combat_spend, except that with Blood Magic mana is paid in health, one point per
; 5 mana (rounded up), which must leave at least 1 health. Creative always pays, and takes nothing.
combat_pay:
    cmp     dword [game_mode], MODE_CREATIVE
    je      .paid
    cmp     edi, RES_MANA
    jne     .spend
    test    dword [rpg_keystones], 1 << KS_BLOOD_MAGIC
    jz      .spend
    divss   xmm0, [k_5]
    roundss xmm0, xmm0, 10              ; ceil
    cvttss2si ecx, xmm0
    mov     eax, [surv + SURVIVAL.health]
    cmp     eax, ecx
    jle     .short                      ; the cost must leave some health
    sub     eax, ecx
    mov     [surv + SURVIVAL.health], eax
    mov     dword [surv + SURVIVAL.hurt_flash], 6
.paid:
    mov     eax, 1
    ret
.spend:
    jmp     combat_spend
.short:
    xor     eax, eax
    ret

; combat_kb_mult() -> xmm0 factor on every knockback the player suffers: 0 with Juggernaut, else 1
combat_kb_mult:
    movss   xmm0, [k_1]
    test    dword [rpg_keystones], 1 << KS_JUGGERNAUT
    jz      .ret
    xorps   xmm0, xmm0
.ret:
    ret

; combat_player_status(edi kind, esi magnitude): the player suffers a status. STS_BURN: 3 s, a tick of
; max(old, 1, magnitude / 6) health; STS_CHILL: 2 s of slow walking; STS_POISON: one more stack (5),
; 4 s, a tick of max(old, 1, magnitude / 4) per stack. Other kinds are ignored. The first burn or
; poison ticks a full period after it starts.
combat_player_status:
    cmp     edi, STS_BURN
    je      .burn
    cmp     edi, STS_CHILL
    je      .chill
    cmp     edi, STS_POISON
    jne     .ret
    DOT_ARM
    mov     eax, [combat_poison]
    inc     eax
    cmp     eax, POISON_STACKS
    jbe     .stacks
    mov     eax, POISON_STACKS
.stacks:
    mov     [combat_poison], eax
    mov     dword [combat_poison_t], POISON_STEPS
    mov     eax, esi
    xor     edx, edx
    mov     ecx, 4
    div     ecx
    mov     ecx, 1
    cmp     eax, ecx
    cmovb   eax, ecx
    cmp     eax, [combat_poison_tick]
    jbe     .ret
    mov     [combat_poison_tick], eax
    ret
.burn:
    DOT_ARM
    mov     dword [combat_burn_t], BURN_STEPS
    mov     eax, esi
    xor     edx, edx
    mov     ecx, 6
    div     ecx
    mov     ecx, 1
    cmp     eax, ecx
    cmovb   eax, ecx
    cmp     eax, [combat_burn_tick]
    jbe     .ret
    mov     [combat_burn_tick], eax
    ret
.chill:
    mov     dword [combat_chill_t], CHILL_STEPS
.ret:
    ret

; combat_set_guard(edi wanted): once per frame. The guard goes up (timer 0) while wanted, not
; broken and with at least 1 stamina; otherwise it is down (-1).
combat_set_guard:
    test    edi, edi
    jz      .down
    cmp     dword [combat_guard_break_t], 0
    jg      .down
    movss   xmm0, [combat_stamina]
    ucomiss xmm0, [k_1]
    jb      .down
    cmp     dword [combat_guard_t], 0
    jge     .ret                        ; already up: combat_step keeps it counting
    mov     dword [combat_guard_t], 0
.ret:
    ret
.down:
    mov     dword [combat_guard_t], -1
    ret

; combat_speed_mult() -> xmm0 walking speed factor: move speed stat, guard 0.4, slow 0.7, chill 0.6, blade 1.2
combat_speed_mult:
    STATF   xmm0, STAT_MOVE_SPEED
    divss   xmm0, [k_100]
    addss   xmm0, [k_1]
    cmp     dword [combat_guard_t], 0
    jl      .unguarded
    mulss   xmm0, [k_0_4]
.unguarded:
    cmp     dword [combat_slow_t], 0
    jle     .unslowed
    mulss   xmm0, [k_0_7]
.unslowed:
    cmp     dword [combat_chill_t], 0
    jle     .unchilled
    mulss   xmm0, [k_0_6]
.unchilled:
    cmp     dword [combat_blade_t], 0
    jle     .done
    mulss   xmm0, [k_1_2]
.done:
    ret

; combat_crit_roll(edi forced) -> eax 1 for a critical hit: forced, or rng % 100 < CRIT_CHANCE
combat_crit_roll:
    mov     eax, 1
    test    edi, edi
    jnz     .ret
    sub     rsp, 8
    call    rng_next
    xor     edx, edx
    mov     ecx, 100
    div     ecx                         ; edx = 0..99
    xor     eax, eax
    cmp     edx, [rpg_stats + STAT_CRIT_CHANCE * 4]
    setl    al
    add     rsp, 8
.ret:
    ret

; combat_crit_mult() -> xmm0 critical damage factor: 1.5 + CRIT_DMG / 100, at least 1
combat_crit_mult:
    STATF   xmm0, STAT_CRIT_DMG
    divss   xmm0, [k_100]
    addss   xmm0, [k_1_5]
    maxss   xmm0, [k_1]
    ret

; combat_heal(edi half_hearts): health up by that much, to surv_max_health; nothing when dead
combat_heal:
    test    edi, edi
    jle     .done
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .done
    mov     eax, [surv + SURVIVAL.health]
    mov     ecx, [surv_max_health]
    cmp     eax, ecx
    jge     .done                       ; already full
    add     eax, edi
    cmp     eax, ecx
    cmovg   eax, ecx
    mov     [surv + SURVIVAL.health], eax
.done:
    ret

; text_in_front(edi txt): a floating text id 1.2 blocks along the view from the eye
text_in_front:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 40                     ; [rsp] eye[3], [rsp+16] view[3]
    mov     ebx, edi
    lea     rdi, [rsp]
    call    player_eye
    lea     rdi, [rsp + 16]
    call    player_forward
    movss   xmm0, [rsp + 16]
    mulss   xmm0, [k_1_2]
    addss   xmm0, [rsp]
    movss   xmm1, [rsp + 20]
    mulss   xmm1, [k_1_2]
    addss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 24]
    mulss   xmm2, [k_1_2]
    addss   xmm2, [rsp + 8]
    mov     edi, ebx
    call    dmgnum_text
    add     rsp, 40
    pop     rbx
    pop     rbp
    ret

; combat_dodge(rdi INPUT*) -> eax 1 if the player rolled. Needs the ground, no guard, no
; cooldown and stamina max(5, 25 * (1 - DODGE_COST / 100)), none with Wind Runner (whose rolls
; then recover in 60 steps instead of 30). Rolls along the input direction (backwards with no
; input): knockback speed 16, a hop, DODGE_STEPS of invulnerability.
combat_dodge:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    cmp     dword [player + BODY.on_ground], 0
    je      .no
    cmp     dword [combat_guard_t], 0
    jge     .no
    cmp     dword [combat_dodge_cd], 0
    jg      .no
    test    dword [rpg_keystones], 1 << KS_WIND_RUNNER
    jnz     .roll                       ; Wind Runner: dodging costs nothing
    STATF   xmm0, STAT_DODGE_COST
    divss   xmm0, [k_100]
    movss   xmm1, [k_1]
    subss   xmm1, xmm0
    mulss   xmm1, [k_25]
    maxss   xmm1, [k_5]
    movaps  xmm0, xmm1
    mov     edi, RES_STAMINA
    call    combat_spend
    test    eax, eax
    jz      .no
.roll:
    movss   xmm0, [player + BODY.yaw]
    call    sincos_deg                  ; xmm0 = sin yaw, xmm1 = cos yaw
    cvtsi2ss xmm2, dword [rbx + INPUT.fwd]
    cvtsi2ss xmm3, dword [rbx + INPUT.strafe]
    movaps  xmm4, xmm2
    mulss   xmm4, xmm0                  ; fwd * sin
    movaps  xmm5, xmm3
    mulss   xmm5, xmm1                  ; strafe * cos
    addss   xmm4, xmm5                  ; dx = fwd * sin + strafe * cos
    mulss   xmm3, xmm0                  ; strafe * sin
    mulss   xmm2, xmm1                  ; fwd * cos
    subss   xmm3, xmm2                  ; dz = strafe * sin - fwd * cos
    movaps  xmm5, xmm4
    mulss   xmm5, xmm5
    movaps  xmm6, xmm3
    mulss   xmm6, xmm6
    addss   xmm5, xmm6                  ; |d|^2
    xorps   xmm6, xmm6
    ucomiss xmm5, xmm6
    ja      .normalise
    xorps   xmm4, xmm4                  ; no input: straight back, -forward_h = (-sin, cos)
    subss   xmm4, xmm0
    movaps  xmm3, xmm1
    jmp     .launch
.normalise:
    sqrtss  xmm5, xmm5
    divss   xmm4, xmm5
    divss   xmm3, xmm5
.launch:
    mulss   xmm4, [k_16]
    mulss   xmm3, [k_16]
    movss   [player + BODY.kbx], xmm4
    movss   [player + BODY.kbz], xmm3
    mov     dword [player + BODY.vy], __float32__(3.5)
    mov     dword [combat_dodge_t], DODGE_STEPS
    mov     dword [combat_dodge_cd], DODGE_COOLDOWN
    test    dword [rpg_keystones], 1 << KS_WIND_RUNNER
    jz      .cooldown_set
    mov     dword [combat_dodge_cd], WIND_COOLDOWN
.cooldown_set:
    mov     edi, SND_DODGE
    movss   xmm0, [k_1]
    call    audio_play
    movss   xmm0, [player + BODY.x]     ; a puff of dust at the feet
    movss   xmm1, [player + BODY.y]
    movss   xmm2, [player + BODY.z]
    mov     edi, FX_SMOKE
    mov     esi, 6
    movss   xmm3, [k_1]
    call    fx_burst
    mov     eax, 1
    jmp     .out
.no:
    xor     eax, eax
.out:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; player_take_hit(edi amount, esi cause, xmm0 src_x, xmm1 src_z) -> eax HIT_*
; A monster hit on the player coming from (src_x, src_z). HIT_NONE in creative, when dead or
; while invulnerable, and while a roll is in progress (that one prints DODGED, and a perfect dodge
; makes the next strike a forced crit). A guard facing the source (dot with the horizontal view
; >= 0.34, or the source on top of us) parries the hit when raised within 6 + PARRY_WINDOW steps
; (no damage, riposte, sparks, hit-stop, a tenth of the health back with the Kingslayer; the caller
; stuns the attacker), else blocks it: stamina -= 120 * amount / max health * (1 - BLOCK_COST / 100)
; and survival_damage((amount + 3) / 4); when the stamina runs out the guard breaks and the hit lands
; in full. Otherwise it is taken in full (halved, at least 1, under a war cry). The Mana Shield turns
; part of what lands into a mana drain first. HIT_TAKEN iff survival_damage applied. A hit taken or
; blocked from the mob in combat_attacker is answered with THORNS damage.
; Frame: [rsp] src x, z; [rsp+8] forward_h x, z; [rsp+16] eye[3]; [rsp+28] result
player_take_hit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    mov     ebx, edi
    mov     r12d, esi
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    cmp     dword [game_mode], MODE_CREATIVE
    je      .none
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .none
    cmp     dword [surv + SURVIVAL.invuln], 0
    jg      .none
    movss   xmm0, [player + BODY.yaw]
    call    sincos_deg
    movss   [rsp + 8], xmm0             ; forward_h = (sin yaw, -cos yaw)
    xorps   xmm2, xmm2
    subss   xmm2, xmm1
    movss   [rsp + 12], xmm2
    cmp     dword [combat_dodge_t], 0   ; 1. rolling: nothing touches us
    jle     .arc
    mov     dword [combat_riposte_t], RIPOSTE_STEPS     ; and the next strike is a forced crit
    mov     edi, TXT_DODGED
    call    text_in_front
    jmp     .none
.arc:                                   ; 2. is the source in front of us?
    movss   xmm0, [rsp]
    subss   xmm0, [player + BODY.x]
    movss   xmm1, [rsp + 4]
    subss   xmm1, [player + BODY.z]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3                  ; |src - player|^2
    ucomiss xmm2, [k_len2]
    jb      .guard                      ; on top of us: counts as in front
    sqrtss  xmm2, xmm2
    mulss   xmm0, [rsp + 8]
    mulss   xmm1, [rsp + 12]
    addss   xmm0, xmm1
    divss   xmm0, xmm2                  ; dot(unit(src - player), forward_h)
    ucomiss xmm0, [k_0_34]
    jb      .taken                      ; behind or beside us
.guard:                                 ; 3. a raised guard
    cmp     dword [combat_guard_t], 0
    jl      .taken
    mov     eax, [rpg_stats + STAT_PARRY_WINDOW * 4]
    add     eax, PARRY_BASE
    cmp     [combat_guard_t], eax
    jge     .block
    mov     dword [combat_riposte_t], RIPOSTE_STEPS     ; perfect parry
    mov     edi, SND_PARRY
    movss   xmm0, [k_1]
    call    audio_play
    lea     rdi, [rsp + 16]
    call    player_eye
    movss   xmm0, [rsp + 16]
    addss   xmm0, [rsp]
    mulss   xmm0, [k_0_5]               ; sparks halfway to the attacker, at chest height
    movss   xmm1, [rsp + 20]
    movss   xmm2, [rsp + 24]
    addss   xmm2, [rsp + 4]
    mulss   xmm2, [k_0_5]
    mov     edi, FX_SPARK
    mov     esi, 12
    movss   xmm3, [k_4]
    call    fx_burst
    mov     dword [combat_hitstop], __float32__(0.1)
    mov     edi, TXT_PARRY
    call    text_in_front
    test    dword [gear_powers], 1 << LP_KINGSLAYER
    jz      .parried
    mov     eax, [surv_max_health]      ; the Kingslayer heals a tenth of the health
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    mov     edi, eax
    call    combat_heal
.parried:
    mov     eax, HIT_PARRIED
    jmp     .out
.block:
    cvtsi2ss xmm0, ebx
    mulss   xmm0, [k_120]
    cvtsi2ss xmm1, dword [surv_max_health]
    divss   xmm0, xmm1                  ; 120 * amount / max health
    STATF   xmm1, STAT_BLOCK_COST
    divss   xmm1, [k_100]
    movss   xmm2, [k_1]
    subss   xmm2, xmm1
    maxss   xmm2, [k_0]
    mulss   xmm0, xmm2                  ; * (1 - BLOCK_COST / 100)
    movss   xmm1, [combat_stamina]
    subss   xmm1, xmm0
    mov     dword [combat_spend_t], SPEND_PAUSE
    xorps   xmm2, xmm2
    ucomiss xmm1, xmm2
    jbe     .broken
    movss   [combat_stamina], xmm1
    lea     edi, [rbx + 3]
    shr     edi, 2                      ; a quarter of the damage, rounded up
    call    mana_shield
    mov     edi, eax
    mov     esi, r12d
    call    survival_damage
    mov     edi, SND_BLOCK
    movss   xmm0, [k_1]
    call    audio_play
    mov     edi, TXT_BLOCKED
    call    text_in_front
    mov     eax, HIT_BLOCKED
    jmp     .thorns
.broken:                                ; out of stamina: the guard breaks, the hit goes through
    mov     dword [combat_stamina], 0
    mov     dword [combat_guard_break_t], BREAK_STEPS
    mov     dword [combat_guard_t], -1
.taken:                                 ; 4. in full, or halved under a war cry
    mov     edi, ebx
    cmp     dword [combat_warcry_t], 0
    jle     .full
    shr     edi, 1
    mov     eax, 1
    cmp     edi, eax
    cmovl   edi, eax
.full:
    call    mana_shield
    mov     edi, eax
    mov     esi, r12d
    call    survival_damage
    test    eax, eax
    setnz   al
    movzx   eax, al                     ; HIT_TAKEN or HIT_NONE
.thorns:                                ; a taken or blocked hit from the attacker in combat_attacker hurts it back
    cmp     eax, HIT_TAKEN
    je      .thorn
    cmp     eax, HIT_BLOCKED
    jne     .out
.thorn:
    mov     ecx, [combat_attacker]
    test    ecx, ecx
    js      .out
    mov     edx, [rpg_stats + STAT_THORNS * 4]
    test    edx, edx
    jle     .out
    mov     [rsp + 28], eax
    cvtsi2ss xmm0, edx
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    mov     edi, ecx
    mov     esi, SRC_THORNS
    mov     edx, ELEM_PHYS | HITF_NOSTATUS
    call    combat_hit_mob
    mov     eax, [rsp + 28]
    jmp     .out
.none:
    xor     eax, eax
.out:
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mana_shield(edi amount) -> eax the amount that still lands. With the Mana Shield, 35 % of it
; (rounded down), at most what half the mana covers, is paid at 2 mana per point instead.
mana_shield:
    mov     eax, edi
    test    dword [rpg_keystones], 1 << KS_MANA_SHIELD
    jz      .ret
    imul    eax, eax, 35
    xor     edx, edx
    mov     ecx, 100
    div     ecx                         ; floor(amount * 35 / 100)
    movss   xmm0, [combat_mana]
    mulss   xmm0, [k_0_5]
    cvttss2si ecx, xmm0                 ; floor(mana / 2)
    cmp     eax, ecx
    cmova   eax, ecx
    test    eax, eax
    jz      .none
    lea     ecx, [rax + rax]
    cvtsi2ss xmm0, ecx
    movss   xmm1, [combat_mana]
    subss   xmm1, xmm0
    movss   [combat_mana], xmm1
    sub     edi, eax
.none:
    mov     eax, edi
.ret:
    ret

; ---- the damage pipeline -----------------------------------------------------------------------

; elem_mult(edi elem 0..4) -> xmm0 damage factor of an element: 1 + <element> DMG / 100 (1 for
; physical). Clobbers xmm1 and rax.
elem_mult:
    movss   xmm0, [k_1]
    test    edi, edi
    jz      .ret
    lea     rax, [rpg_stats + (STAT_FIRE_DMG - 1) * 4]
    cvtsi2ss xmm1, dword [rax + rdi*4]
    divss   xmm1, [k_100]
    addss   xmm0, xmm1
.ret:
    ret

; calc_parts(rdi MOB* or 0, esi src, edx flags, xmm0 base, rcx out float[5]) -> xmm0 total
; The damage pipeline of combat_calc and combat_hit_mob, split by element (out[ELEM_*]; the total
; is their sum). The base lands in the element of flags & 7, multiplied by the family factor F of
; the source (melee and melee skills: 1 + (MELEE + ALL) / 100; bow and ranged skills: RANGED;
; bolts and spells: SPELL, 25 % more with Inferno on a burning foe; thorns: 1) and by that element's
; 1 + <element> DMG / 100. A weapon attack (melee, bow, bolt) adds WEAPON_DMG * F physical and
; ADD_<element> * F * <element factor> of each element. A mob then resists each element by its
; mob_resist percent. Finally every part is multiplied by: the crit factor with HITF_CRIT; 1 +
; ELITE_DMG / 100 against an elite or the boss; status_damage_mult; Executioner (x1.6 for melee on a
; foe under 30 % health); Embers (x1.3 on a burning foe); Bloodrage (1 % per 2 % of the player's
; health missing, for all but thorns). Without a mob the resist, elite, status, Executioner, Embers,
; and Inferno terms are skipped. Pure: no random numbers, no side effects.
; rbx = MOB*, r12d = src, r13d = flags, r14 = out, r15d = element / loop counter
; Frame: [rsp] base, [rsp+4] F, [rsp+8] multiplier
calc_parts:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14, rcx
    movss   [rsp], xmm0
    movss   xmm0, [k_1]                 ; F, the family factor
    cmp     r12d, SRC_THORNS
    je      .f_set
    mov     eax, STAT_MELEE_DMG
    cmp     r12d, SRC_MELEE
    je      .family
    cmp     r12d, SRC_MELEE_SKILL
    je      .family
    mov     eax, STAT_RANGED_DMG
    cmp     r12d, SRC_BOW
    je      .family
    cmp     r12d, SRC_RANGED_SKILL
    je      .family
    mov     eax, STAT_SPELL_DMG
.family:
    lea     rdx, [rpg_stats]
    mov     eax, [rdx + rax*4]
    add     eax, [rpg_stats + STAT_ALL_DMG * 4]
    cvtsi2ss xmm0, eax
    divss   xmm0, [k_100]
    addss   xmm0, [k_1]
    cmp     r12d, SRC_BOLT
    je      .spell
    cmp     r12d, SRC_SPELL
    jne     .f_set
.spell:                                 ; Inferno: spells hit a burning foe 25 % harder
    test    rbx, rbx
    jz      .f_set
    test    dword [rpg_keystones], 1 << KS_INFERNO
    jz      .f_set
    cmp     dword [rbx + MOB.burn_t], 0
    jle     .f_set
    addss   xmm0, [k_0_25]
.f_set:
    movss   [rsp + 4], xmm0
    xorps   xmm0, xmm0                  ; the base lands in its element
    movups  [r14], xmm0
    mov     dword [r14 + 16], 0
    mov     r15d, r13d
    and     r15d, HITF_ELEM_MASK
    cmp     r15d, ELEM_POISON
    jbe     .elem_ok
    xor     r15d, r15d                  ; not an element we know: physical
.elem_ok:
    movss   xmm2, [rsp]
    mulss   xmm2, [rsp + 4]             ; base * F
    mov     edi, r15d
    call    elem_mult
    mulss   xmm2, xmm0
    movss   [r14 + r15*4], xmm2
    cmp     r12d, SRC_BOLT
    ja      .resist                     ; only weapon attacks (melee, bow, bolt) add the weapon's own damage
    cvtsi2ss xmm0, dword [rpg_stats + STAT_WEAPON_DMG * 4]
    mulss   xmm0, [rsp + 4]
    addss   xmm0, [r14]
    movss   [r14], xmm0
    mov     r15d, 1
.add:
    lea     rax, [rpg_stats + (STAT_ADD_FIRE - 1) * 4]
    cvtsi2ss xmm2, dword [rax + r15*4]
    mulss   xmm2, [rsp + 4]
    mov     edi, r15d
    call    elem_mult
    mulss   xmm2, xmm0
    addss   xmm2, [r14 + r15*4]
    movss   [r14 + r15*4], xmm2
    inc     r15d
    cmp     r15d, NUM_ELEMS
    jb      .add
.resist:
    test    rbx, rbx
    jz      .mult
    xor     r15d, r15d
.res:
    mov     edi, [rbx + MOB.type]
    mov     esi, r15d
    call    mob_resist                  ; signed percent: 100 = immune
    mov     ecx, 100
    sub     ecx, eax
    cvtsi2ss xmm0, ecx
    divss   xmm0, [k_100]
    mulss   xmm0, [r14 + r15*4]
    movss   [r14 + r15*4], xmm0
    inc     r15d
    cmp     r15d, NUM_ELEMS
    jb      .res
.mult:
    movss   xmm0, [k_1]
    movss   [rsp + 8], xmm0
    test    r13d, HITF_CRIT
    jz      .no_crit
    call    combat_crit_mult
    mulss   xmm0, [rsp + 8]
    movss   [rsp + 8], xmm0
.no_crit:
    test    rbx, rbx
    jz      .player_terms
    cmp     dword [rbx + MOB.elite], 0
    jne     .elite
    cmp     dword [rbx + MOB.type], MOB_BOSS
    jne     .no_elite
.elite:
    cvtsi2ss xmm0, dword [rpg_stats + STAT_ELITE_DMG * 4]
    divss   xmm0, [k_100]
    addss   xmm0, [k_1]
    mulss   xmm0, [rsp + 8]
    movss   [rsp + 8], xmm0
.no_elite:
    mov     rdi, rbx
    call    status_damage_mult
    mulss   xmm0, [rsp + 8]
    movss   [rsp + 8], xmm0
    test    dword [rpg_keystones], 1 << KS_EXECUTIONER
    jz      .no_exec
    cmp     r12d, SRC_MELEE
    je      .exec_src
    cmp     r12d, SRC_MELEE_SKILL
    jne     .no_exec
.exec_src:
    mov     eax, [rbx + MOB.health]
    imul    eax, eax, 10
    mov     ecx, [rbx + MOB.max_health]
    imul    ecx, ecx, 3
    cmp     eax, ecx
    jge     .no_exec
    movss   xmm0, [rsp + 8]             ; Executioner: a foe under 30 % health takes 60 % more
    mulss   xmm0, [k_1_6]
    movss   [rsp + 8], xmm0
.no_exec:
    test    dword [gear_powers], 1 << LP_EMBERS
    jz      .player_terms
    cmp     dword [rbx + MOB.burn_t], 0
    jle     .player_terms
    movss   xmm0, [rsp + 8]             ; Embers: burning foes take 30 % more
    mulss   xmm0, [k_1_3]
    movss   [rsp + 8], xmm0
.player_terms:                          ; Bloodrage: 1 % per 2 % of health missing
    test    dword [rpg_keystones], 1 << KS_BLOODRAGE
    jz      .total
    cmp     r12d, SRC_THORNS
    je      .total
    cvtsi2ss xmm0, dword [surv + SURVIVAL.health]
    cvtsi2ss xmm1, dword [surv_max_health]
    divss   xmm0, xmm1
    movss   xmm1, [k_1]
    subss   xmm1, xmm0                  ; the fraction missing
    maxss   xmm1, [k_0]
    mulss   xmm1, [k_0_5]
    addss   xmm1, [k_1]
    mulss   xmm1, [rsp + 8]
    movss   [rsp + 8], xmm1
.total:
    xorps   xmm1, xmm1
    xor     ecx, ecx
.sum:
    movss   xmm0, [r14 + rcx*4]
    mulss   xmm0, [rsp + 8]
    movss   [r14 + rcx*4], xmm0
    addss   xmm1, xmm0
    inc     ecx
    cmp     ecx, NUM_ELEMS
    jb      .sum
    movaps  xmm0, xmm1
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; combat_calc(edi mob or -1, esi src, edx flags, xmm0 base) -> xmm0 total
; What a hit of that source (SRC_*), flags (HITF_*: element, crit) and unscaled base would deal to
; the mob (-1 or an empty slot: to no particular mob), before rounding. Pure: no random numbers and
; no side effects. See calc_parts for the rules.
combat_calc:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32                     ; the five element parts
    xor     ecx, ecx
    cmp     edi, MAX_MOBS
    jae     .go
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rcx, rax
    cmp     dword [rcx + MOB.type], MOB_NONE
    jne     .go
    xor     ecx, ecx
.go:
    mov     rdi, rcx
    lea     rcx, [rsp]
    call    calc_parts
    leave
    ret

; combat_hit_mob(edi mob, esi src, edx flags, xmm0 base, xmm1 dirx, xmm2 dirz) -> eax damage dealt
; Every hit the player lands on a mob goes through here (guns, fire and blasts of TNT, creepers and
; rockets excepted). The damage is calc_parts' total, rounded, at least 1. Nothing happens and 0
; comes back for a villager, a free slot, a hit inside the hurt window (HITF_HURTWIN: mob_hurt
; instead of mob_strike) and a total under 0.01 (every part resisted away: "IMMUNE"). HITF_EXECUTE
; raises the damage to the mob's remaining health. The mob learns whose hit it is and its element
; (combat_hit_flags). Then, unless it died or HITF_NOSTATUS:
;   - every fire, frost, shock and poison part of at least 1 applies its status (frost three times
;     with HITF_CHILL3);
;   - a physical part of at least 1 bleeds: always with HITF_BLEED, else for melee, bow and melee
;     skills by a BLEED_CHANCE roll (none is drawn at 0 %);
;   - Inferno ignites on spells without fire; melee with Venom Blades or the Shadow Fang adds 2
;     poison stacks each; a crit from the Celestial Bow adds 3 shocks.
; Lifesteal heals the damage dealt (all but thorns). A crit with the Storm band arcs half of the
; damage as shock to 3 other hostile mobs within 6 blocks.
; rbx = MOB*, r12d = its index, r13d = src, r14d = flags, r15d = damage dealt
; Frame: [rsp] dirx, dirz; [rsp+8] the five scaled parts; [rsp+28] total; [rsp+32], [rsp+36] counters
combat_hit_mob:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56
    cmp     edi, MAX_MOBS
    jae     .refused
    imul    ebx, edi, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    mov     eax, [rbx + MOB.type]
    test    eax, eax
    jz      .refused
    cmp     eax, MOB_MERCHANT
    je      .refused
    cmp     eax, MOB_ELDER
    je      .refused
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    movss   [rsp], xmm1
    movss   [rsp + 4], xmm2
    mov     rdi, rbx
    mov     esi, r13d
    mov     edx, r14d
    lea     rcx, [rsp + 8]
    call    calc_parts
    movss   [rsp + 28], xmm0
    comiss  xmm0, [k_0_01]
    jae     .strike
    movss   xmm0, [rbx + BODY.x]        ; immune: "IMMUNE" over the head and nothing else
    movss   xmm1, [rbx + BODY.height]
    addss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    mov     edi, TXT_IMMUNE
    call    dmgnum_text
    jmp     .refused
.strike:
    cvtss2si r15d, xmm0                 ; round to nearest
    mov     ecx, 1
    cmp     r15d, ecx
    cmovl   r15d, ecx                   ; at least 1
    test    r14d, HITF_EXECUTE
    jz      .dealt
    mov     eax, [rbx + MOB.health]
    cmp     r15d, eax
    cmovl   r15d, eax                   ; the execution takes what is left
.dealt:
    xor     eax, eax                    ; the element with the largest part (the first wins a tie)
    movss   xmm0, [rsp + 8]
    mov     ecx, 1
.dominant:
    movss   xmm1, [rsp + 8 + rcx*4]
    comiss  xmm1, xmm0
    jbe     .not_larger
    movaps  xmm0, xmm1
    mov     eax, ecx
.not_larger:
    inc     ecx
    cmp     ecx, NUM_ELEMS
    jb      .dominant
    shl     eax, HF_ELEM_SHIFT
    or      eax, HF_PLAYER
    test    r14d, HITF_CRIT
    jz      .flags_set
    or      eax, HF_CRIT
.flags_set:
    mov     [combat_hit_flags], eax
    mov     edi, r12d
    mov     esi, r15d
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    test    r14d, HITF_HURTWIN
    jnz     .hurt
    call    mob_strike
    jmp     .struck
.hurt:
    call    mob_hurt
.struck:
    test    eax, eax
    jz      .refused                    ; inside the hurt window
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .afflicted                  ; it died: nothing left to afflict
    test    r14d, HITF_NOSTATUS
    jnz     .afflicted
    mov     dword [rsp + 32], 1         ; fire, frost, shock, poison: element - 1 = STS_*
.element:
    mov     ecx, [rsp + 32]
    movss   xmm0, [rsp + 8 + rcx*4]
    comiss  xmm0, [k_1]
    jb      .element_next
    mov     dword [rsp + 36], 1
    cmp     ecx, ELEM_FROST
    jne     .apply
    test    r14d, HITF_CHILL3
    jz      .apply
    mov     dword [rsp + 36], 3         ; a nova chills three times: a freeze at once
.apply:
    mov     edi, r12d
    mov     esi, [rsp + 32]
    dec     esi
    mov     ecx, [rsp + 32]
    movss   xmm0, [rsp + 8 + rcx*4]
    call    status_apply
    dec     dword [rsp + 36]
    jnz     .apply
.element_next:
    inc     dword [rsp + 32]
    cmp     dword [rsp + 32], NUM_ELEMS
    jb      .element
    movss   xmm0, [rsp + 8 + ELEM_PHYS * 4]
    comiss  xmm0, [k_1]
    jb      .no_bleed
    test    r14d, HITF_BLEED
    jnz     .bleed
    cmp     r13d, SRC_MELEE
    je      .bleed_roll
    cmp     r13d, SRC_BOW
    je      .bleed_roll
    cmp     r13d, SRC_MELEE_SKILL
    jne     .no_bleed
.bleed_roll:
    cmp     dword [rpg_stats + STAT_BLEED_CHANCE * 4], 0
    jle     .no_bleed
    call    rng_next
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    cmp     edx, [rpg_stats + STAT_BLEED_CHANCE * 4]
    jge     .no_bleed
.bleed:
    mov     edi, r12d
    mov     esi, STS_BLEED
    movss   xmm0, [rsp + 8 + ELEM_PHYS * 4]
    call    status_apply
.no_bleed:
    test    dword [rpg_keystones], 1 << KS_INFERNO
    jz      .no_inferno
    cmp     r13d, SRC_BOLT
    je      .inferno
    cmp     r13d, SRC_SPELL
    jne     .no_inferno
.inferno:
    movss   xmm0, [rsp + 8 + ELEM_FIRE * 4]
    comiss  xmm0, [k_1]
    jae     .no_inferno                 ; a fire part has ignited it already
    mov     edi, r12d
    mov     esi, STS_BURN
    movss   xmm0, [rsp + 28]
    call    status_apply
.no_inferno:
    cmp     r13d, SRC_MELEE
    jne     .no_melee_poison
    xor     eax, eax
    test    dword [rpg_keystones], 1 << KS_VENOM_BLADES
    jz      .no_venom
    add     eax, 2
.no_venom:
    test    dword [gear_powers], 1 << LP_SHADOW_FANG
    jz      .poison_stacks
    add     eax, 2
.poison_stacks:
    mov     [rsp + 36], eax
.poison:
    cmp     dword [rsp + 36], 0
    jle     .no_melee_poison
    mov     edi, r12d
    mov     esi, STS_POISON
    movss   xmm0, [rsp + 8 + ELEM_PHYS * 4]
    call    status_apply
    dec     dword [rsp + 36]
    jmp     .poison
.no_melee_poison:
    test    dword [gear_powers], 1 << LP_CELESTIAL
    jz      .afflicted
    cmp     r13d, SRC_BOW
    jne     .afflicted
    test    r14d, HITF_CRIT
    jz      .afflicted
    mov     dword [rsp + 36], 3         ; the Celestial Bow: a crit shocks three times
.shock:
    mov     edi, r12d
    mov     esi, STS_SHOCK
    xorps   xmm0, xmm0
    call    status_apply
    dec     dword [rsp + 36]
    jnz     .shock
.afflicted:
    cmp     r13d, SRC_THORNS
    je      .arcs
    mov     eax, [rpg_stats + STAT_LIFESTEAL * 4]
    test    eax, eax
    jle     .arcs
    imul    eax, r15d
    cvtsi2ss xmm0, eax
    divss   xmm0, [k_100]
    addss   xmm0, [combat_life_carry]
    roundss xmm1, xmm0, 9               ; heal the whole points, keep the fraction
    subss   xmm0, xmm1
    movss   [combat_life_carry], xmm0
    cvttss2si edi, xmm1
    call    combat_heal
.arcs:
    test    dword [gear_powers], 1 << LP_STORMS
    jz      .done
    test    r14d, HITF_CRIT
    jz      .done
    cmp     r13d, SRC_THORNS
    je      .done
    test    r14d, HITF_CHAIN
    jnz     .done
    mov     dword [rsp + 32], 0         ; slot being looked at
    mov     dword [rsp + 36], 0         ; arcs so far
.arc:
    mov     eax, [rsp + 32]
    cmp     eax, r12d
    je      .arc_next
    mov     edi, eax
    call    mob_is_hostile
    test    eax, eax
    jz      .arc_next
    imul    eax, dword [rsp + 32], MOB_size
    lea     rcx, [mobs]
    add     rcx, rax                    ; the other mob
    movss   xmm0, [rcx + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [rcx + BODY.y]
    subss   xmm1, [rbx + BODY.y]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rcx + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [k_36]
    jae     .arc_next                   ; farther than 6 blocks
    cvtsi2ss xmm0, r15d
    mulss   xmm0, [k_0_5]
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    mov     edi, [rsp + 32]
    mov     esi, SRC_THORNS
    mov     edx, ELEM_SHOCK | HITF_CHAIN | HITF_NOSTATUS
    call    combat_hit_mob
    inc     dword [rsp + 36]
    cmp     dword [rsp + 36], 3
    jae     .done
.arc_next:
    inc     dword [rsp + 32]
    cmp     dword [rsp + 32], MAX_MOBS
    jb      .arc
.done:
    mov     eax, r15d
    jmp     .out
.refused:
    xor     eax, eax
.out:
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- melee: the light strike and the heavy attack -----------------------------------------------

; strike_held() -> eax id of the held item (0 = bare hands)
strike_held:
    sub     rsp, 8
    call    inv_held
    xor     edx, edx
    cmp     byte [rax + ITEMSTACK.count], 0
    je      .done
    movzx   edx, byte [rax + ITEMSTACK.id]
.done:
    mov     eax, edx
    add     rsp, 8
    ret

; scaled_cd(edi steps) -> eax round(steps * 100 / (100 + ATTACK_SPEED)), at least 1; the speed
; never drops below a tenth of normal
scaled_cd:
    cvtsi2ss xmm0, edi
    mulss   xmm0, [k_100]
    cvtsi2ss xmm1, dword [rpg_stats + STAT_ATTACK_SPEED * 4]
    addss   xmm1, [k_100]
    maxss   xmm1, [k_10]
    divss   xmm0, xmm1
    cvtss2si eax, xmm0
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx
    ret

; melee_cd_for(edi item id) -> eax steps between two strikes with that item: its tool kind's cooldown
; shortened by ATTACK_SPEED, at least 4
melee_cd_for:
    sub     rsp, 8
    lea     rax, [item_tool]
    movzx   eax, byte [rax + rdi]
    lea     rcx, [melee_cd]
    movzx   edi, byte [rcx + rax]
    call    scaled_cd
    mov     ecx, 4
    cmp     eax, ecx
    cmovl   eax, ecx
    add     rsp, 8
    ret

; strike_cd(edi item id) -> eax melee_cd_for, halved (at least 4) during Blade Dance
strike_cd:
    sub     rsp, 8
    call    melee_cd_for
    cmp     dword [combat_blade_t], 0
    jle     .done
    shr     eax, 1
    mov     ecx, 4
    cmp     eax, ecx
    cmovb   eax, ecx
.done:
    add     rsp, 8
    ret

; strike_backstab(rdi MOB*) -> eax 1 when the mob faces away from the player: its facing (sin, -cos)
; has dot(forward, to player) below -0.3; 0 inside the mob
strike_backstab:
    push    rbx
    mov     rbx, rdi
    movss   xmm0, [rbx + BODY.yaw]
    call    sincos_deg
    movss   xmm2, [player + BODY.x]
    subss   xmm2, [rbx + BODY.x]
    movss   xmm3, [player + BODY.z]
    subss   xmm3, [rbx + BODY.z]
    movaps  xmm4, xmm2
    mulss   xmm4, xmm4
    movaps  xmm5, xmm3
    mulss   xmm5, xmm5
    addss   xmm4, xmm5                  ; |player - mob|^2
    xor     eax, eax
    ucomiss xmm4, [k_len2]
    jb      .done                       ; inside the mob: no facing to compare
    mulss   xmm2, xmm0                  ; dx * sin
    mulss   xmm3, xmm1                  ; dz * cos
    subss   xmm2, xmm3                  ; dot(forward, d) = dx * sin - dz * cos
    sqrtss  xmm4, xmm4
    divss   xmm2, xmm4
    ucomiss xmm2, [k_m0_3]
    jae     .done
    mov     eax, 1
.done:
    pop     rbx
    ret

; strike_crit() -> eax 1 for a critical strike: forced after a riposte or Shadowstep, in stealth, in
; Blade Dance and while falling faster than 1 block/s, else rolled (combat_crit_roll)
strike_crit:
    sub     rsp, 8
    xor     edi, edi
    cmp     dword [combat_riposte_t], 0
    jg      .forced
    cmp     dword [combat_crit_next_t], 0
    jg      .forced
    cmp     dword [combat_stealth_t], 0
    jg      .forced
    cmp     dword [combat_blade_t], 0
    jg      .forced
    cmp     dword [player + BODY.on_ground], 0
    jne     .roll
    movss   xmm0, [player + BODY.vy]
    ucomiss xmm0, [k_m1]
    jae     .roll
.forced:
    mov     edi, 1
.roll:
    call    combat_crit_roll
    add     rsp, 8
    ret

; stun_alive(rdi MOB*, esi steps): a mob that still lives and is neither the boss nor a juggernaut
; is stunned for at least that long
stun_alive:
    mov     eax, [rdi + MOB.type]
    cmp     eax, MOB_NONE
    je      .ret
    cmp     eax, MOB_BOSS
    je      .ret
    test    dword [rdi + MOB.affix], AFX_JUGGERNAUT
    jnz     .ret
    cmp     [rdi + MOB.stun], esi
    jge     .ret
    mov     [rdi + MOB.stun], esi
.ret:
    ret

; combat_melee(edi mob, xmm0 dirx, xmm1 dirz) -> eax 1 if a strike landed. (dirx, dirz) is the
; horizontal unit direction from the player to the mob. 0 while the attack cooldown runs, for a
; dead mob, or when the mob ignores the hit. The base damage is the held attack * 1.3 with a war
; cry * 1.5 on the third hit of a combo (2 with a warhammer; knockback 1.8) * (1 + BACKSTAB / 100)
; from behind * 1.5 on the boss from behind with Assassinate * 2 from stealth with Shadow Dance;
; combat_hit_mob adds everything else (stats, crit, elements, statuses, lifesteal). The crit is
; forced after a riposte or Shadowstep, in stealth, in Blade Dance and while falling faster than 1
; block/s. A landed strike spends those, sets the cooldown (by tool kind, shortened by ATTACK_SPEED),
; freezes the frame and makes the sounds; a warhammer also throws 1.5 times as far and stuns for 12
; steps; a backstab kill with the Shadow Fang resets Shadowstep.
; rbx = mob, r12d = its index, r13d = held item id (0 = bare hands), r14d = 1 for a crit,
; r15d = 1 for a strike from behind
; Frame: [rsp] dirx, dirz; [rsp+8] base damage; [rsp+12] knockback factor; [rsp+16] combo after the
; strike; [rsp+20] attack cooldown after the strike
combat_melee:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    cmp     dword [combat_attack_cd], 0
    jg      .no
    cmp     edi, MAX_MOBS
    jae     .no
    imul    ebx, edi, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .no
    mov     r12d, edi
    call    strike_held
    mov     r13d, eax
    mov     edi, eax
    call    strike_cd
    mov     [rsp + 20], eax
    mov     edi, r13d
    call    item_attack_damage
    cvtsi2ss xmm0, eax                  ; the held attack, * 1.3 with a war cry
    cmp     dword [combat_warcry_t], 0
    jle     .base_set
    mulss   xmm0, [k_1_3]
.base_set:
    movss   [rsp + 8], xmm0
    mov     dword [rsp + 12], __float32__(1.0)
    mov     eax, [combat_combo]         ; combo: this strike is the next of a running combo
    inc     eax
    cmp     dword [combat_combo_t], 0
    jg      .combo_have
    mov     eax, 1
.combo_have:
    cmp     eax, 3
    jb      .combo_store
    movss   xmm1, [k_1_5]               ; the third strike hits 1.5 times as hard (a warhammer: twice) ...
    lea     rcx, [item_tool]
    cmp     byte [rcx + r13], TOOL_HAMMER
    jne     .third
    movss   xmm1, [k_2]
.third:
    movss   xmm0, [rsp + 8]
    mulss   xmm0, xmm1
    movss   [rsp + 8], xmm0
    mov     dword [rsp + 12], __float32__(1.8)  ; ... and throws 1.8 times as far
    xor     eax, eax
.combo_store:
    mov     [rsp + 16], eax
    lea     rcx, [item_tool]
    cmp     byte [rcx + r13], TOOL_HAMMER
    jne     .backstab
    movss   xmm0, [rsp + 12]            ; a warhammer throws 1.5 times as far
    mulss   xmm0, [k_1_5]
    movss   [rsp + 12], xmm0
.backstab:
    mov     rdi, rbx
    call    strike_backstab
    mov     r15d, eax
    test    eax, eax
    jz      .shadow
    STATF   xmm0, STAT_BACKSTAB
    divss   xmm0, [k_100]
    addss   xmm0, [k_1]
    mulss   xmm0, [rsp + 8]
    movss   [rsp + 8], xmm0
    test    dword [rpg_keystones], 1 << KS_ASSASSINATE
    jz      .shadow
    cmp     dword [rbx + MOB.type], MOB_BOSS
    jne     .shadow
    movss   xmm0, [rsp + 8]             ; Assassinate: bosses take 50 % more from behind
    mulss   xmm0, [k_1_5]
    movss   [rsp + 8], xmm0
.shadow:
    test    dword [rpg_keystones], 1 << KS_SHADOW_DANCE
    jz      .crit
    cmp     dword [combat_stealth_t], 0
    jle     .crit
    movss   xmm0, [rsp + 8]             ; Shadow Dance: the first hit from stealth deals double
    addss   xmm0, xmm0
    movss   [rsp + 8], xmm0
.crit:
    call    strike_crit
    mov     r14d, eax
    xor     edx, edx                    ; flags: physical, crit, execute
    test    eax, eax
    jz      .execute
    or      edx, HITF_CRIT
.execute:
    test    r15d, r15d
    jz      .hit
    test    dword [rpg_keystones], 1 << KS_ASSASSINATE
    jz      .hit
    cmp     dword [rbx + MOB.type], MOB_BOSS
    je      .hit
    mov     eax, [rbx + MOB.health]
    shl     eax, 2
    cmp     eax, [rbx + MOB.max_health]
    jge     .hit
    or      edx, HITF_EXECUTE           ; Assassinate: a backstab kills a non-boss under 25 % health
.hit:
    mov     edi, r12d
    mov     esi, SRC_MELEE
    movss   xmm0, [rsp + 8]
    movss   xmm1, [rsp]
    mulss   xmm1, [rsp + 12]
    movss   xmm2, [rsp + 4]
    mulss   xmm2, [rsp + 12]
    call    combat_hit_mob
    test    eax, eax
    jz      .no
    mov     eax, [rsp + 20]             ; the strike landed
    mov     [combat_attack_cd], eax
    mov     eax, [rsp + 16]
    mov     [combat_combo], eax
    mov     dword [combat_combo_t], COMBO_WINDOW
    xor     eax, eax
    mov     [combat_riposte_t], eax     ; the riposte, Shadowstep's crit and stealth are spent
    mov     [combat_crit_next_t], eax
    mov     [combat_stealth_t], eax
    lea     rcx, [item_tool]
    cmp     byte [rcx + r13], TOOL_HAMMER
    jne     .fang
    mov     rdi, rbx                    ; a warhammer stuns what it leaves standing
    mov     esi, 12
    call    stun_alive
.fang:
    test    r15d, r15d
    jz      .feel
    test    dword [gear_powers], 1 << LP_SHADOW_FANG
    jz      .feel
    cmp     dword [rbx + MOB.type], MOB_NONE
    jne     .feel
    mov     dword [abilities_cd], 0     ; a backstab kill with the Shadow Fang resets Shadowstep
.feel:
    movss   xmm0, [k_0_05]              ; hit-stop
    test    r14d, r14d
    jz      .stop
    movss   xmm0, [k_0_09]
.stop:
    movss   [combat_hitstop], xmm0
    mov     edi, SND_SWING
    movss   xmm0, [k_0_6]
    call    audio_play
    test    r14d, r14d
    jz      .done
    mov     edi, SND_CRIT
    movss   xmm0, [k_1]
    call    audio_play
    movss   xmm0, [fx_shake]
    maxss   xmm0, [k_0_35]
    movss   [fx_shake], xmm0
.done:
    mov     eax, 1
    jmp     .out
.no:
    xor     eax, eax
.out:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; combat_heavy(edi mob, xmm0 dirx, xmm1 dirz) -> eax 1 if the heavy attack landed. Needs a held melee
; weapon (item_gear GK_MELEE), no attack cooldown, and 20 stamina (short of it: a dry click). The
; blow deals the held attack * 2.2 * (1 + BACKSTAB / 100) from behind, always bleeds, throws 2.5
; times as far and stuns what it leaves standing (a warhammer 40 steps, else 20; not the boss, not a
; juggernaut); it freezes the frame for 0.12 s, shakes the camera and sets a cooldown of 3/2 of the
; light strike's. The crit rules, and what a landed strike spends, are those of combat_melee.
; rbx = mob, r12d = its index, r13d = held item id, r14d = 1 for a crit
; Frame: [rsp] dirx, dirz; [rsp+8] base damage; [rsp+20] attack cooldown after the blow
combat_heavy:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    cmp     edi, MAX_MOBS
    jae     .no
    imul    ebx, edi, MOB_size
    lea     rax, [mobs]
    add     rbx, rax
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .no
    mov     r12d, edi
    call    strike_held
    mov     r13d, eax
    lea     rcx, [item_gear]
    cmp     byte [rcx + r13], GK_MELEE
    jne     .dry                        ; only a melee weapon swings heavy...
    cmp     dword [combat_attack_cd], 0
    jg      .dry                        ; ...and not while the last swing recovers
    mov     edi, RES_STAMINA
    movss   xmm0, [k_20]
    call    combat_pay
    test    eax, eax
    jnz     .paid
.dry:                                   ; refused (no weapon, cooling down, too tired): a dry click
    mov     edi, SND_DRY_FIRE
    movss   xmm0, [k_0_6]
    call    audio_play
    jmp     .no
.paid:
    mov     edi, r13d
    call    strike_cd
    lea     eax, [rax + rax*2]
    shr     eax, 1
    mov     [rsp + 20], eax             ; 3/2 of the light strike's cooldown
    mov     edi, r13d
    call    item_attack_damage
    cvtsi2ss xmm0, eax
    mulss   xmm0, [k_2_2]
    movss   [rsp + 8], xmm0
    mov     rdi, rbx
    call    strike_backstab
    test    eax, eax
    jz      .crit
    STATF   xmm0, STAT_BACKSTAB
    divss   xmm0, [k_100]
    addss   xmm0, [k_1]
    mulss   xmm0, [rsp + 8]
    movss   [rsp + 8], xmm0
.crit:
    call    strike_crit
    mov     r14d, eax
    mov     edx, HITF_BLEED
    test    eax, eax
    jz      .hit
    or      edx, HITF_CRIT
.hit:
    mov     edi, r12d
    mov     esi, SRC_MELEE
    movss   xmm0, [rsp + 8]
    movss   xmm1, [rsp]
    mulss   xmm1, [k_2_5]
    movss   xmm2, [rsp + 4]
    mulss   xmm2, [k_2_5]
    call    combat_hit_mob
    test    eax, eax
    jz      .no
    mov     eax, [rsp + 20]
    mov     [combat_attack_cd], eax
    xor     eax, eax
    mov     [combat_riposte_t], eax
    mov     [combat_crit_next_t], eax
    mov     [combat_stealth_t], eax
    mov     esi, 20
    lea     rcx, [item_tool]
    cmp     byte [rcx + r13], TOOL_HAMMER
    jne     .stun
    mov     esi, 40
.stun:
    mov     rdi, rbx
    call    stun_alive
    mov     dword [combat_hitstop], __float32__(0.12)
    movss   xmm0, [fx_shake]
    maxss   xmm0, [k_0_5]
    movss   [fx_shake], xmm0
    mov     edi, SND_HEAVY
    movss   xmm0, [k_1]
    call    audio_play
    mov     eax, 1
    jmp     .out
.no:
    xor     eax, eax
.out:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; combat_weapon_preview(rdi out dword[3]): what the held weapon does, for the character sheet: a
; normal hit, a critical hit, and attacks per 10 seconds. A bow is a full draw (9, x1.5 for the
; Celestial Bow; 60 steps, shortened by ATTACK_SPEED unless Deadeye); a mage's staff shoots shock
; bolts (4 every 24 steps; the Archmage staff 7 every 18, both shortened by ATTACK_SPEED); anything
; else is a melee strike with the held item (bare hands included).
; rbx = out, r12d = held item id, r13d = damage source. Frame: [rsp] base, [rsp+4] cooldown in
; steps, [rsp+8] element flags
combat_weapon_preview:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 24
    mov     rbx, rdi
    call    strike_held
    mov     r12d, eax
    lea     rcx, [item_gear]
    movzx   eax, byte [rcx + r12]
    cmp     eax, GK_BOW
    je      .bow
    cmp     eax, GK_STAFF
    jne     .melee
    call    rpg_class
    cmp     eax, CLASS_MAGE
    jne     .melee
    mov     r13d, SRC_BOLT              ; a mage's staff: shock bolts
    mov     dword [rsp + 8], ELEM_SHOCK
    movss   xmm0, [k_4]
    mov     edi, 24
    cmp     r12d, ARCHMAGE_STAFF
    jne     .bolt
    movss   xmm0, [k_7]
    mov     edi, 18
.bolt:
    movss   [rsp], xmm0
    call    scaled_cd
    jmp     .cd
.bow:
    mov     r13d, SRC_BOW
    mov     dword [rsp + 8], 0
    movss   xmm0, [k_9]
    cmp     r12d, CELESTIAL_BOW
    jne     .bow_base
    mulss   xmm0, [k_1_5]
.bow_base:
    movss   [rsp], xmm0
    mov     eax, 60
    test    dword [rpg_keystones], 1 << KS_DEADEYE
    jnz     .cd                         ; Deadeye: attack speed no longer speeds the draw
    mov     edi, 60
    call    scaled_cd
    jmp     .cd
.melee:
    mov     r13d, SRC_MELEE
    mov     dword [rsp + 8], 0
    mov     edi, r12d
    call    item_attack_damage
    cvtsi2ss xmm0, eax
    movss   [rsp], xmm0
    mov     edi, r12d
    call    melee_cd_for
.cd:
    mov     [rsp + 4], eax
    mov     edi, -1
    mov     esi, r13d
    mov     edx, [rsp + 8]
    movss   xmm0, [rsp]
    call    combat_calc
    cvtss2si eax, xmm0
    mov     [rbx], eax                  ; a normal hit
    mov     edi, -1
    mov     esi, r13d
    mov     edx, [rsp + 8]
    or      edx, HITF_CRIT
    movss   xmm0, [rsp]
    call    combat_calc
    cvtss2si eax, xmm0
    mov     [rbx + 4], eax              ; a critical hit
    movss   xmm0, [k_600]
    cvtsi2ss xmm1, dword [rsp + 4]
    divss   xmm0, xmm1
    cvtss2si eax, xmm0
    mov     [rbx + 8], eax              ; attacks per 10 seconds
    add     rsp, 24
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
