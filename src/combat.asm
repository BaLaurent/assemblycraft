; combat.asm - the player's fighting rules: stamina and mana, the guard and its perfect parry, the
; dodge roll, melee strikes (combo, crits, backstabs, riposte), hits taken from monsters, and the
; timers the class abilities set. Timers count fixed 1/60 s steps and age in combat_step, which
; runs once per step. Stats come from rpg_stats (rpg.asm).
%include "common.inc"
default rel

global combat_mana, combat_stamina
global combat_guard_t, combat_guard_break_t, combat_dodge_t, combat_dodge_cd
global combat_attack_cd, combat_combo, combat_combo_t, combat_riposte_t
global combat_crit_next_t, combat_warcry_t, combat_blade_t, combat_stealth_t
global combat_slow_t, combat_spend_t
global combat_hitstop, combat_hit_flags, combat_life_carry
global combat_reset, combat_refill, combat_max_mana, combat_max_stamina, combat_step
global combat_spend, combat_set_guard, combat_dodge, combat_melee, player_take_hit
global combat_speed_mult, combat_crit_roll, combat_crit_mult, combat_heal

extern rpg_stats, surv, surv_max_health, game_mode
extern player, player_eye, player_forward, sincos_deg, rng_next
extern inv_held, item_tool, item_attack_damage
extern mobs, mob_strike, survival_damage
extern audio_play, fx_shake, fx_burst, dmgnum_text

%define SPEND_PAUSE    36               ; steps stamina regeneration waits after a spend
%define PARRY_BASE     6                ; a hit within this many steps (+ PARRY_WINDOW) of raising the guard is parried
%define BREAK_STEPS    60               ; steps a broken guard stays down
%define RIPOSTE_STEPS  60               ; steps after a parry that the next strike is a forced crit
%define DODGE_STEPS    16               ; steps of invulnerability in a roll
%define DODGE_COOLDOWN 30
%define COMBO_WINDOW   45               ; steps a hit keeps the combo alive

; combat_melee builds the hit flags as HF_PLAYER + 0/1, and player_take_hit returns survival_damage's 0/1
%if HF_CRIT != 1
%error "combat.asm: HF_CRIT must be 1"
%endif
%if HIT_TAKEN != 1
%error "combat.asm: HIT_TAKEN must be 1"
%endif

; the numeric value of a stat as a float
%macro STATF 2                          ; xmm register, stat id
    cvtsi2ss %1, dword [rpg_stats + %2 * 4]
%endmacro

section .rodata
align 4
melee_cd:    db 10, 14, 18, 14, 12, 7   ; melee cooldown in steps by held tool: none, pickaxe, axe, shovel, sword, dagger
align 4
k_1:         dd 1.0
k_4:         dd 4.0
k_5:         dd 5.0
k_6:         dd 6.0
k_16:        dd 16.0                    ; dodge roll speed, blocks/s
k_25:        dd 25.0
k_60:        dd 60.0
k_100:       dd 100.0
k_0_05:      dd 0.05
k_0_09:      dd 0.09
k_0_2:       dd 0.2                     ; stamina drained per sprinting step
k_0_34:      dd 0.34                    ; cos of the arc a guard covers (about 70 degrees each side)
k_0_35:      dd 0.35                    ; camera shake of a critical hit
k_0_4:       dd 0.4                     ; speed multiplier while guarding
k_0_5:       dd 0.5
k_0_6:       dd 0.6
k_0_7:       dd 0.7                     ; speed multiplier while slowed
k_1_2:       dd 1.2                     ; blade dance speed; distance of a floating text from the eye
k_1_3:       dd 1.3                     ; war cry damage
k_1_5:       dd 1.5
k_len2:      dd 0.0001                  ; 0.01 blocks, squared
k_m0_3:      dd -0.3                    ; backstab: the mob faces away if dot(forward, to player) is below this
k_m1:        dd -1.0                    ; falling faster than this makes a strike crit
k_regen:     dd 0.33333334              ; stamina regained per step: 20 per second

section .data
align 4
combat_guard_t:       dd -1             ; steps the guard has been up; -1 = down

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
combat_riposte_t:     resd 1            ; > 0: the next strike is a forced crit (after a parry)
combat_crit_next_t:   resd 1            ; > 0: the next strike is a forced crit (after Shadowstep)
combat_warcry_t:      resd 1            ; > 0: +30% melee damage, hits taken halved
combat_blade_t:       resd 1            ; > 0: Blade Dance
combat_stealth_t:     resd 1            ; > 0: unseen by monsters
combat_slow_t:        resd 1            ; > 0: slowed (Whirlwind)
combat_spend_t:       resd 1            ; > 0: stamina regeneration paused after a spend
combat_timers_end:
combat_combo:         resd 1            ; strikes in the running combo (0..2)
combat_hitstop:       resd 1            ; float seconds of freeze left (the game loop drains it)
combat_life_carry:    resd 1            ; float, lifesteal fraction not yet healed
combat_hit_flags:     resd 1            ; low byte = HF_*; set just before a mob damage call
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
    jmp     combat_refill

; combat_step(edi sprinting): once per fixed step. Ages the timers and the guard, regenerates
; mana, and drains (sprinting) or regenerates (idle for SPEND_PAUSE steps) stamina.
combat_step:
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
    test    edi, edi
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

; combat_speed_mult() -> xmm0 walking speed factor: move speed stat, guard 0.4, slow 0.7, blade 1.2
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

; combat_crit_mult() -> xmm0 critical damage factor: 1.5 + CRIT_DMG / 100
combat_crit_mult:
    STATF   xmm0, STAT_CRIT_DMG
    divss   xmm0, [k_100]
    addss   xmm0, [k_1_5]
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
; cooldown and stamina max(5, 25 * (1 - DODGE_COST / 100)). Rolls along the input direction
; (backwards with no input): knockback speed 16, a hop, DODGE_STEPS of invulnerability.
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
; while invulnerable, and while a roll is in progress (that one prints DODGED). A guard facing
; the source (dot with the horizontal view >= 0.34, or the source on top of us) parries the hit
; when raised within 6 + PARRY_WINDOW steps (no damage, riposte, sparks, hit-stop; the caller
; stuns the attacker), else blocks it: stamina -= 6 * amount and survival_damage((amount + 3) / 4);
; when the stamina runs out the guard breaks and the hit lands in full. Otherwise it is taken in
; full (halved, at least 1, under a war cry). HIT_TAKEN iff survival_damage applied.
; Frame: [rsp] src x, z; [rsp+8] forward_h x, z; [rsp+16] eye[3]
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
    mov     eax, HIT_PARRIED
    jmp     .out
.block:
    cvtsi2ss xmm0, ebx
    mulss   xmm0, [k_6]
    movss   xmm1, [combat_stamina]
    subss   xmm1, xmm0                  ; 6 stamina per point of damage
    mov     dword [combat_spend_t], SPEND_PAUSE
    xorps   xmm2, xmm2
    ucomiss xmm1, xmm2
    jbe     .broken
    movss   [combat_stamina], xmm1
    lea     edi, [rbx + 3]
    shr     edi, 2                      ; a quarter of the damage, rounded up
    mov     esi, r12d
    call    survival_damage
    mov     edi, SND_BLOCK
    movss   xmm0, [k_1]
    call    audio_play
    mov     edi, TXT_BLOCKED
    call    text_in_front
    mov     eax, HIT_BLOCKED
    jmp     .out
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
    mov     esi, r12d
    call    survival_damage
    test    eax, eax
    setnz   al
    movzx   eax, al                     ; HIT_TAKEN or HIT_NONE
    jmp     .out
.none:
    xor     eax, eax
.out:
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

; combat_melee(edi mob, xmm0 dirx, xmm1 dirz) -> eax 1 if a strike landed. (dirx, dirz) is the
; horizontal unit direction from the player to the mob. 0 while the attack cooldown runs, for a
; dead mob, or when the mob ignores the hit. Damage = held attack * (1 + MELEE / 100) * 1.3 with a
; war cry * 1.5 on the third hit of a combo (knockback 1.8) * (1 + BACKSTAB / 100) from behind
; * the crit factor; the crit is forced after a riposte or Shadowstep, in stealth, in Blade
; Dance and while falling faster than 1 block/s. A landed strike spends those, sets the
; cooldown, steals life, freezes the frame and makes the sounds.
; Frame: [rsp] dirx, dirz; [rsp+8] damage factor; [rsp+12] knockback factor; [rsp+16] combo after
; the strike; [rsp+20] attack cooldown after the strike. rbx = mob, r12d = its index, r13d = held
; item id (0 = bare hands), r14d = 1 for a crit, r15d = damage dealt.
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
    call    inv_held
    xor     r13d, r13d
    cmp     byte [rax + ITEMSTACK.count], 0
    je      .have_held
    movzx   r13d, byte [rax + ITEMSTACK.id]
.have_held:
    lea     rax, [item_tool]            ; the cooldown follows the tool kind
    movzx   eax, byte [rax + r13]
    lea     rcx, [melee_cd]
    movzx   eax, byte [rcx + rax]
    cmp     dword [combat_blade_t], 0
    jle     .cd_set
    shr     eax, 1                      ; blade dance: twice as fast, at least 4 steps
    mov     ecx, 4
    cmp     eax, ecx
    cmovb   eax, ecx
.cd_set:
    mov     [rsp + 20], eax
    STATF   xmm0, STAT_MELEE_DMG        ; damage factor: (1 + MELEE / 100) * war cry
    divss   xmm0, [k_100]
    addss   xmm0, [k_1]
    cmp     dword [combat_warcry_t], 0
    jle     .factor_set
    mulss   xmm0, [k_1_3]
.factor_set:
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
    movss   xmm0, [rsp + 8]             ; the third strike hits 1.5 times as hard and throws 1.8 times as far
    mulss   xmm0, [k_1_5]
    movss   [rsp + 8], xmm0
    mov     dword [rsp + 12], __float32__(1.8)
    xor     eax, eax
.combo_store:
    mov     [rsp + 16], eax
    movss   xmm0, [rbx + BODY.yaw]      ; backstab: the mob's facing (sin, -cos) points away from the player
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
    ucomiss xmm4, [k_len2]
    jb      .crit                       ; inside the mob: no facing to compare
    mulss   xmm2, xmm0                  ; dx * sin
    mulss   xmm3, xmm1                  ; dz * cos
    subss   xmm2, xmm3                  ; dot(forward, d) = dx * sin - dz * cos
    sqrtss  xmm4, xmm4
    divss   xmm2, xmm4
    ucomiss xmm2, [k_m0_3]
    jae     .crit
    STATF   xmm0, STAT_BACKSTAB
    divss   xmm0, [k_100]
    addss   xmm0, [k_1]
    mulss   xmm0, [rsp + 8]
    movss   [rsp + 8], xmm0
.crit:
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
    mov     r14d, eax
    test    eax, eax
    jz      .strike
    call    combat_crit_mult
    mulss   xmm0, [rsp + 8]
    movss   [rsp + 8], xmm0
.strike:
    mov     edi, r13d
    call    item_attack_damage
    cvtsi2ss xmm0, eax
    mulss   xmm0, [rsp + 8]
    cvtss2si eax, xmm0                  ; round to nearest
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx                    ; at least 1
    mov     r15d, eax
    lea     eax, [r14 + HF_PLAYER]      ; HF_CRIT is 1
    mov     [combat_hit_flags], eax
    movss   xmm0, [rsp]
    mulss   xmm0, [rsp + 12]
    movss   xmm1, [rsp + 4]
    mulss   xmm1, [rsp + 12]
    mov     edi, r12d
    mov     esi, r15d
    call    mob_strike
    mov     dword [combat_hit_flags], 0
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
    mov     eax, [rpg_stats + STAT_LIFESTEAL * 4]
    test    eax, eax
    jz      .no_life
    imul    eax, r15d
    cvtsi2ss xmm0, eax
    divss   xmm0, [k_100]
    addss   xmm0, [combat_life_carry]
    roundss xmm1, xmm0, 9               ; heal the whole points, keep the fraction
    subss   xmm0, xmm1
    movss   [combat_life_carry], xmm0
    cvttss2si edi, xmm1
    call    combat_heal
.no_life:
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
