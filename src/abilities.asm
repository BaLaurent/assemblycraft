; abilities.asm - the twenty abilities (four per archetype, taught by the skill web), the staff
; bolt of the Path of the Mage and the timers behind them.
;
; abilities_use(slot, eye, dir) casts what the ability bar holds in that slot (rpg_bar_ability; an
; empty slot dry-fires). The effect index and the cooldown index are the ability id,
; (archetype - 1) * 4 + slot of its archetype, so rebinding an ability does not reset its cooldown.
; It checks the cooldown and, for the three abilities that need one (blink, shadowstep, hunter's
; mark), a landing spot or a target; only then does it pay through combat_pay (Blood Magic pays
; mana in health), start the cooldown and fire, so a failed cast costs nothing and plays the
; dry-fire click. Resource, cost and base cooldown come from rpg_ability_info; the COOLDOWN_RED
; stat shortens the cooldown. The abilities that last (charge, whirlwind, meteor storm, arrow
; rain) keep their state in this file and abilities_step advances it once per fixed step; Bullseye
; and Fan the Hammer only start a timer in combat.asm that guns.asm reads, and the Powder Grenade
; and the Flashbang lob a PROJ_GRENADE that arrows.asm bursts (a flash is ab_flash_at). Nothing
; here scales a damage: a strike is a combat_hit_mob call and a projectile (a plain arrows.asm
; entity) carries an unscaled base; a critical roll is only a flag, and the pipeline applies the
; stats, the element, the resistances and the crit multiplier.
%include "common.inc"
default rel

global abilities_cd, abilities_cd_total, abilities_bolt_cd
global abilities_reset, abilities_step, abilities_use, abilities_staff_bolt, abilities_shift
global meteor_tgt, rain_tgt                 ; read by test_mobs (entities_rebase)
global ab_flash_at                          ; the flashbang burst at a point (arrows.asm calls it)

extern player, mobs
extern mobs_raycast, mob_is_hostile, yaw_from, ray_aabb
extern raycast, world_is_solid
extern arrows_spawn, fx_burst, fx_explosion, fx_shake
extern audio_play, hand_swing
extern inv_held, item_attack_damage
extern rng_next, sincos_deg
extern rpg_rank, rpg_stat, rpg_keystone, rpg_bar_ability, rpg_ability_info
extern gear_has_power
extern combat_pay, combat_crit_roll, combat_hit_mob
extern combat_stealth_t, combat_warcry_t, combat_slow_t
extern combat_blade_t, combat_crit_next_t
extern combat_bullseye_t, combat_fanhammer_t

; ab_crit hands combat_crit_roll's 0/1 on as the flag value
%if AF_CRIT != 1 || HITF_CRIT != AF_CRIT << 8
%error "abilities.asm: AF_CRIT must be 1 and HITF_CRIT AF_CRIT << 8"
%endif

; effect index = ability id = (archetype - 1) * 4 + slot
%define IDX_BLINK       5               ; mage, slot 1
%define IDX_MARK        11              ; archer, slot 3
%define IDX_SHADOW      12              ; rogue, slot 0
%define IDX_SMOKE       13              ; rogue, slot 1

%define CHARGE_STEPS    15
%define WHIRL_STEPS     90
%define WHIRL_PERIOD    30              ; a pulse every 30 steps: at 90, 60 and 30 steps left
%define WARCRY_STEPS    480
%define WARCRY_STUN     40              ; steps a war cry stuns
%define STEALTH_STEPS   300
%define DANCE_STEPS     1800            ; the smoke bomb's stealth under Shadow Dance
%define BLADE_STEPS     360
%define CRIT_NEXT_STEPS 120
%define MARK_STEPS      600
%define BULLSEYE_STEPS  300
%define FANHAMMER_STEPS 240
%define SLAM_STUN       40
%define SLAM_STUN_BOSS  15
%define FLASH_STUN      60              ; a flashbang's stun; the Fallen King's is shorter
%define FLASH_STUN_BOSS 20
%define METEORS         8
%define METEOR_GAP      22
%define RAIN_ARROWS     24
%define RAIN_GAP        5
%define KNIVES          8

; the unscaled damage of the projectiles
%define FIREBALL_DMG    8
%define METEOR_DMG      12
%define VOLLEY_DMG      6
%define EXPLOSIVE_DMG   10
%define RAIN_DMG        6
%define KNIFE_DMG       6
%define GRENADE_DMG     12

; abilities_use frame (rsp-relative)
%define U_EYE           0               ; qword eye*
%define U_DIR           8               ; qword dir*
%define U_PLAN          16              ; float plan[4]: landing spot x, y, z and the yaw there
%define U_TMP           32              ; int
%define U_FRAME         56

section .rodata
align 4
k_one:        dd 1.0
k_half:       dd 0.5
k_quarter:    dd 0.25
k_hundred:    dd 100.0
k_inv65536:   dd 0.000015258789
k_tiny:       dd 0.0001
k_abs:        dd 0x7FFFFFFF
k_chest:      dd 0.9                    ; player centre above the feet
k_eye_h:      dd 1.62                   ; eye above the feet
k_contact:    dd 0.001                  ; the free-box test's slack: touching a wall is free
k_box_xz:     dd 0.299                  ; half width 0.3 less the slack
k_box_top:    dd 1.799                  ; height 1.8 less the slack
k_vol:        dd 0.8
k_vol_fail:   dd 0.5
k_vol_bolt:   dd 0.35                   ; the staff's basic bolt: an attack spammed all fight long
k_2:          dd 2.0
k_25:         dd 2.5
k_3:          dd 3.0
k_4:          dd 4.0
k_6:          dd 6.0
k_charge_kb:  dd 22.0                   ; charge: push on the player, b/s
k_charge_hit: dd 2.0                    ; and the scale of the push on a mob it strikes
k_reach:      dd 0.9                    ; strike reach beyond the mob's half width
k_charge_dy:  dd 1.5
k_warcry_r:   dd 6.0                    ; radii: war cry 6 blocks, whirlwind 3.5, ground slam 4,
k_whirl_r:    dd 3.5                    ; frost nova 5 - each times 1 + AREA / 100
k_whirl_dy:   dd 2.0
k_whirl_push: dd 1.5
k_warcry_mul: dd 1.3                    ; whirlwind damage while the war cry lasts
k_fireball_v: dd 28.0
k_fireball_o: dd 0.5                    ; spawn distance from the eye
k_bolt_v:     dd 45.0
k_arrow_o:    dd 0.4
k_volley_v:   dd 40.0
k_explode_v:  dd 45.0
k_meteor_h:   dd 18.0
k_meteor_v:   dd -30.0
k_rain_h:     dd 14.0
k_rain_v:     dd -35.0
k_spread:     dd 4.0                    ; meteors and arrows land within +-4 blocks of the target
k_range:      dd 40.0                   ; targeting ray of meteor storm and arrow rain
k_meteor_far: dd 30.0                   ; ...and where they aim when it hits nothing
k_rain_far:   dd 25.0
k_shadow_rng: dd 12.0                   ; shadowstep sight, blocks
k_shadow_gap: dd 0.8                    ; behind the mob by its half width plus this
k_slam_r:     dd 4.0
k_slam_dy:    dd 2.0                    ; ground slam: within 2 blocks in height
k_slam_mul:   dd 1.5                    ; ...for 1.5 x the attack of the held item
k_slam_push:  dd 2.0                    ; outward shove of the strike
k_slam_vy:    dd 6.0                    ; and the launch of the mob it hit, b/s
k_slam_up:    dd 0.1                    ; the blast sits this far above the feet
k_slam_fx:    dd 1.2                    ; its radius
k_slam_shake: dd 0.6                    ; camera shake
k_nova_r:     dd 5.0
k_nova_dy:    dd 3.0                    ; frost nova: within 3 blocks in height
k_nova_base:  dd 6.0                    ; ...6 points of frost
k_nova_push:  dd 0.5
k_knife_v:    dd 30.0                   ; fan of knives: speed, b/s
k_knife_drop: dd 0.5                    ; ...thrown from this far below the eye
k_charge_dmg: dd 10.0                   ; charge: the base damage of its strike
k_grenade_o:  dd 0.5                    ; powder grenade and flashbang: spawn distance from the eye...
k_grenade_v:  dd 20.0                   ; ...and speed, b/s
k_flash_r:    dd 5.0                    ; the flashbang's radius, times 1 + AREA / 100
k_keg:        dd 1.5                    ; Powder Keg: a blast 50 % wider
k_flash_vol:  dd 0.6                    ; volume of the flash's bang

align 8
ab_effects:                             ; by effect index; each (rdi eye*, rsi dir*, rdx plan*)
    dq ab_charge, ab_warcry, ab_whirl, ab_slam
    dq ab_fireball, ab_blink, ab_meteor, ab_nova
    dq ab_volley, ab_explosive, ab_rain, ab_mark
    dq ab_shadowstep, ab_smoke, ab_blade, ab_knives
    dq ab_grenade, ab_bullseye, ab_fanhammer, ab_flashbang

section .bss
alignb 4
ab_state:                               ; everything abilities_reset clears
abilities_cd:       resd NUM_ABILITIES  ; steps left, by ability id
abilities_cd_total: resd NUM_ABILITIES  ; the cooldown each was started with (for the HUD)
abilities_bolt_cd:  resd 1              ; steps until the next staff bolt
bolt_n:       resd 1                    ; bolts under the Archmage's power since the last fireball
charge_t:     resd 1                    ; steps of charge left
charge_mask:  resq 1                    ; bit i = mob i was already struck by this charge (MAX_MOBS = 64)
charge_dx:    resd 1                    ; float: the charge's horizontal heading
charge_dz:    resd 1
whirl_t:      resd 1                    ; steps of whirlwind left
meteor_n:     resd 1                    ; meteors still to fall
meteor_t:     resd 1                    ; steps until the next
meteor_tgt:   resd 3                    ; float: where they fall
rain_n:       resd 1
rain_t:       resd 1
rain_tgt:     resd 3
ab_state_end:

section .text

; abilities_reset(): no cooldowns, no charge, whirlwind, storm or rain under way
abilities_reset:
    lea     rdi, [ab_state]
    mov     ecx, ab_state_end - ab_state
    xor     eax, eax
    rep     stosb
    ret

; abilities_step(): once per fixed step. Cooldowns tick down; the charge, whirlwind, meteor storm
; and arrow rain advance.
abilities_step:
    push    rbp
    mov     rbp, rsp
    lea     rdx, [abilities_cd]
    xor     ecx, ecx
.cd:
    cmp     dword [rdx + rcx*4], 0
    jle     .cd_next
    dec     dword [rdx + rcx*4]
.cd_next:
    inc     ecx
    cmp     ecx, NUM_ABILITIES
    jb      .cd
    cmp     dword [abilities_bolt_cd], 0
    jle     .lasting
    dec     dword [abilities_bolt_cd]
.lasting:
    call    ab_charge_step
    call    ab_whirl_step
    call    ab_meteor_step
    call    ab_rain_step
    pop     rbp
    ret

; abilities_use(edi slot 0..3, rsi eye float[3], rdx dir float[3] unit look direction) -> eax 1
; when the ability bound to that bar slot fired, 0 when it did not (no such slot: silently; an
; empty slot, cooling down, short of its resource, no valid target: nothing is paid, the dry-fire
; click plays). Every cast but the smoke bomb ends stealth.
; rbx = ABILINFO*, r12d = bar slot, r13d = ability id: the effect index and the cooldown index
abilities_use:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, U_FRAME
    mov     [rsp + U_EYE], rsi
    mov     [rsp + U_DIR], rdx
    mov     r12d, edi
    cmp     r12d, NUM_ABILITY_SLOTS
    jae     .none                       ; no such slot
    call    rpg_bar_ability
    mov     r13d, eax
    test    eax, eax
    js      .fail                       ; nothing bound to the slot
    lea     rax, [abilities_cd]
    cmp     dword [rax + r13*4], 0
    jg      .fail                       ; still cooling down
    mov     edi, r13d
    call    rpg_ability_info
    mov     rbx, rax
    cmp     r13d, IDX_BLINK
    je      .plan_blink
    cmp     r13d, IDX_MARK
    je      .plan_mark
    cmp     r13d, IDX_SHADOW
    jne     .pay
    mov     rdi, [rsp + U_EYE]
    mov     rsi, [rsp + U_DIR]
    lea     rdx, [rsp + U_PLAN]
    call    ab_shadow_plan
    jmp     .planned
.plan_blink:
    mov     rdi, [rsp + U_EYE]
    mov     rsi, [rsp + U_DIR]
    lea     rdx, [rsp + U_PLAN]
    call    ab_blink_plan
    jmp     .planned
.plan_mark:
    mov     rdi, [rsp + U_EYE]
    mov     rsi, [rsp + U_DIR]
    lea     rdx, [rsp + U_PLAN]
    call    ab_mark_plan
.planned:
    test    eax, eax
    jz      .fail                       ; nowhere to go, nobody to mark: nothing is paid
.pay:
    mov     edi, [rbx + ABILINFO.resource]
    cvtsi2ss xmm0, dword [rbx + ABILINFO.cost]
    call    combat_pay
    test    eax, eax
    jz      .fail
    mov     eax, [rbx + ABILINFO.cooldown]          ; cooldown steps = cd_s * 60 * (100 - COOLDOWN_RED) / 100
    imul    eax, eax, 60
    mov     [rsp + U_TMP], eax
    mov     edi, STAT_COOLDOWN_RED
    call    rpg_stat
    mov     ecx, 100
    sub     ecx, eax
    mov     eax, [rsp + U_TMP]
    imul    eax, ecx
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    lea     rdx, [abilities_cd]
    mov     [rdx + r13*4], eax
    lea     rdx, [abilities_cd_total]
    mov     [rdx + r13*4], eax
    lea     rax, [ab_effects]
    mov     rdi, [rsp + U_EYE]
    mov     rsi, [rsp + U_DIR]
    lea     rdx, [rsp + U_PLAN]
    call    [rax + r13*8]
    cmp     r13d, IDX_SMOKE
    je      .done
    mov     dword [combat_stealth_t], 0 ; casting gives a hider away; the smoke bomb is the hiding
.done:
    mov     eax, 1
    jmp     .ret
.fail:
    mov     edi, SND_DRY_FIRE
    movss   xmm0, [k_vol_fail]
    call    audio_play
.none:
    xor     eax, eax
.ret:
    add     rsp, U_FRAME
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; abilities_staff_bolt(rdi eye float[3], rsi dir float[3]) -> eax 1 when a bolt flew. A character who
; took the Path of the Mage, holding a staff: STAFF 5 mana, 24 steps between bolts, base damage 4;
; ARCHMAGE_STAFF 4 mana, 18 steps, base 7. The steps shrink with ATTACK_SPEED:
; round(steps * 100 / (100 + ATTACK_SPEED)). The bolt is a PROJ_BOLT carrying the unscaled base,
; AF_ATTACK, a shock element and the crit flag combat_crit_roll decides; under the Archmage's power
; every 4th bolt is a PROJ_FIREBALL for twice the base instead. 0 for anyone else (the staff is
; swung), while the previous bolt is still cooling down (silently) or when the mana is short (the
; click plays, and the next try waits one bolt cooldown, so a held button does not click every
; frame).
; rbx = mana cost, r12d = bolt cooldown, r13d = base damage; frame: eye[3] @0, dir[3] @12, scratch
; @24
abilities_staff_bolt:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40
    mov     rax, [rdi]
    mov     [rsp], rax
    mov     eax, [rdi + 8]
    mov     [rsp + 8], eax
    mov     rax, [rsi]
    mov     [rsp + 12], rax
    mov     eax, [rsi + 8]
    mov     [rsp + 20], eax
    call    inv_held
    movzx   eax, byte [rax + ITEMSTACK.id]
    mov     ebx, 5
    mov     r12d, 24
    mov     r13d, 4
    cmp     eax, STAFF
    je      .have
    mov     ebx, 4
    mov     r12d, 18
    mov     r13d, 7
    cmp     eax, ARCHMAGE_STAFF
    jne     .none
.have:
    mov     edi, ARCH_MAGE - 1          ; the Path of the Mage
    call    rpg_rank
    test    eax, eax
    jz      .none                       ; without it the staff is swung
    cmp     dword [abilities_bolt_cd], 0
    jg      .none
    cvtsi2ss xmm0, r12d                 ; the cooldown: steps * 100 / (100 + ATTACK_SPEED), rounded
    mulss   xmm0, [k_hundred]
    movss   [rsp + 24], xmm0
    mov     edi, STAT_ATTACK_SPEED
    call    rpg_stat
    cvtsi2ss xmm1, eax
    addss   xmm1, [k_hundred]
    movss   xmm0, [rsp + 24]
    divss   xmm0, xmm1
    cvtss2si r12d, xmm0
    mov     edi, RES_MANA
    cvtsi2ss xmm0, ebx
    call    combat_pay
    test    eax, eax
    jz      .dry
    call    ab_crit
    mov     [rsp + 24], eax             ; the crit flag
    mov     edi, LP_ARCHMAGE
    call    gear_has_power
    mov     edx, eax                    ; non-zero under the Archmage's power
    xor     ecx, ecx
    test    edx, edx
    jz      .counted                    ; no power: the count starts over
    mov     ecx, [bolt_n]
    inc     ecx
    and     ecx, 3
.counted:
    mov     [bolt_n], ecx
    test    edx, edx
    jz      .bolt
    test    ecx, ecx
    jz      .fireball                   ; the 4th bolt under the power
.bolt:
    lea     rdi, [rsp]
    lea     rsi, [rsp + 12]
    movss   xmm0, [k_arrow_o]
    movss   xmm1, [k_bolt_v]
    mov     edx, r13d
    mov     ecx, PROJ_BOLT
    mov     r8d, [rsp + 24]
    or      r8d, AF_ATTACK | (ELEM_SHOCK << AF_ELEM_SHIFT)
    call    ab_shoot
    mov     edi, SND_SPELL
    movss   xmm0, [k_vol_bolt]
    jmp     .play
.fireball:
    lea     rdi, [rsp]
    lea     rsi, [rsp + 12]
    movss   xmm0, [k_fireball_o]
    movss   xmm1, [k_fireball_v]
    lea     edx, [r13 + r13]
    mov     ecx, PROJ_FIREBALL
    mov     r8d, [rsp + 24]
    call    ab_shoot
    mov     edi, SND_FIREBALL
    movss   xmm0, [k_vol]
.play:
    call    audio_play
    mov     [abilities_bolt_cd], r12d
    mov     eax, 1
    jmp     .ret
.dry:
    mov     [abilities_bolt_cd], r12d
    mov     edi, SND_DRY_FIRE
    movss   xmm0, [k_vol_fail]
    call    audio_play
.none:
    xor     eax, eax
.ret:
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- helpers -----------------------------------------------------------------------------

; ab_rnd(xmm0 range) -> xmm0 uniform in [-range, range)
ab_rnd:
    sub     rsp, 24
    movss   [rsp], xmm0
    call    rng_next
    shr     eax, 8
    and     eax, 0xFFFF
    cvtsi2ss xmm0, eax
    mulss   xmm0, [k_inv65536]
    addss   xmm0, xmm0
    subss   xmm0, [k_one]
    mulss   xmm0, [rsp]
    add     rsp, 24
    ret

; ab_mult(edi stat) -> xmm0 = 1 + rpg_stat(stat) / 100
ab_mult:
    sub     rsp, 8
    call    rpg_stat
    cvtsi2ss xmm0, eax
    divss   xmm0, [k_hundred]
    addss   xmm0, [k_one]
    add     rsp, 8
    ret

; ab_crit() -> eax 1 (the value of AF_CRIT) when this hit rolls a critical against the crit chance,
; else 0. What a critical does to the damage is the pipeline's business.
ab_crit:
    sub     rsp, 8
    xor     edi, edi
    call    combat_crit_roll
    add     rsp, 8
    ret

; ab_sweep(xmm0 base, xmm1 radius, xmm2 dy limit, xmm3 push, edi src, esi flags, edx rolls) -> rax
; mask: every hostile mob whose horizontal distance from the player is below radius and whose
; feet are less than the dy limit above or below his takes combat_hit_mob(src, flags, base,
; outward * push); with rolls non-zero each hit rolls its own critical (HITF_CRIT). Bit i of rax is
; set for every mob i that was struck (64 bits: MAX_MOBS is 64).
; rbx = mob, r12d = index, r13 = mask, r14d = flags
%define S_BASE          0               ; frame: floats base, radius^2, dy limit, push, ...
%define S_R2            4
%define S_DY            8
%define S_PUSH          12
%define S_SRC           16              ; ...ints src, rolls, ...
%define S_ROLLS         20
%define S_DX            24              ; ...and the mob's offset from the player
%define S_DZ            28
%define S_FRAME         32
ab_sweep:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, S_FRAME
    movss   [rsp + S_BASE], xmm0
    mulss   xmm1, xmm1
    movss   [rsp + S_R2], xmm1
    movss   [rsp + S_DY], xmm2
    movss   [rsp + S_PUSH], xmm3
    mov     [rsp + S_SRC], edi
    mov     r14d, esi
    mov     [rsp + S_ROLLS], edx
    xor     r13d, r13d
    lea     rbx, [mobs]
    xor     r12d, r12d
.mob:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [player + BODY.x]
    movss   [rsp + S_DX], xmm0
    movss   xmm1, [rbx + BODY.z]
    subss   xmm1, [player + BODY.z]
    movss   [rsp + S_DZ], xmm1
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1                  ; horizontal distance^2
    comiss  xmm0, [rsp + S_R2]
    jae     .next
    movss   xmm0, [rbx + BODY.y]
    subss   xmm0, [player + BODY.y]
    movss   xmm1, [k_abs]
    andps   xmm1, xmm0                  ; |dy|
    comiss  xmm1, [rsp + S_DY]
    jae     .next
    mov     edi, r12d
    call    mob_is_hostile
    test    eax, eax
    jz      .next
    xor     eax, eax
    cmp     dword [rsp + S_ROLLS], 0
    je      .flags
    call    ab_crit
    shl     eax, 8                      ; HITF_CRIT
.flags:
    mov     edx, r14d
    or      edx, eax
    movss   xmm1, [rsp + S_DX]
    movss   xmm2, [rsp + S_DZ]
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    movaps  xmm4, xmm2
    mulss   xmm4, xmm4
    addss   xmm3, xmm4
    sqrtss  xmm3, xmm3                  ; horizontal distance
    comiss  xmm3, [k_tiny]
    jb      .still                      ; right on top of the player
    divss   xmm1, xmm3
    divss   xmm2, xmm3
    movss   xmm4, [rsp + S_PUSH]
    mulss   xmm1, xmm4
    mulss   xmm2, xmm4
    jmp     .strike
.still:
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
.strike:
    movss   xmm0, [rsp + S_BASE]
    mov     edi, r12d
    mov     esi, [rsp + S_SRC]
    call    combat_hit_mob
    test    eax, eax
    jz      .next
    bts     r13, r12
.next:
    add     rbx, MOB_size
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .mob
    mov     rax, r13
    add     rsp, S_FRAME
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ab_shoot(rdi eye float[3], rsi dir float[3], xmm0 offset, xmm1 speed, edx damage, ecx kind,
; r8d flags) -> eax arrow slot or -1: a projectile of the player's (no pickup) from eye + dir *
; offset along dir at speed blocks per second
ab_shoot:
    sub     rsp, 8
    movaps  xmm6, xmm0
    movaps  xmm7, xmm1
    movss   xmm3, [rsi]
    movss   xmm4, [rsi + 4]
    movss   xmm5, [rsi + 8]
    movaps  xmm0, xmm3
    mulss   xmm0, xmm6
    addss   xmm0, [rdi]
    movaps  xmm1, xmm4
    mulss   xmm1, xmm6
    addss   xmm1, [rdi + 4]
    movaps  xmm2, xmm5
    mulss   xmm2, xmm6
    addss   xmm2, [rdi + 8]
    mulss   xmm3, xmm7
    mulss   xmm4, xmm7
    mulss   xmm5, xmm7
    mov     esi, edx
    xor     edi, edi                    ; owner: the player
    xor     edx, edx                    ; nobody picks it up
    call    arrows_spawn
    add     rsp, 8
    ret

; ab_burst(edi kind, esi count, xmm0 speed): fx_burst at the player's chest
ab_burst:
    sub     rsp, 8
    movaps  xmm3, xmm0
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.y]
    addss   xmm1, [k_chest]
    movss   xmm2, [player + BODY.z]
    call    fx_burst
    add     rsp, 8
    ret

; ab_forward_h(rdi dir float[3], rsi out float[2]): the horizontal part of dir as a unit vector
; (x, z); the player's own heading when dir points straight up or down
; rbx = out
ab_forward_h:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rsi
    movss   xmm0, [rdi]
    movss   xmm1, [rdi + 8]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    sqrtss  xmm2, xmm2
    comiss  xmm2, [k_tiny]
    jb      .heading
    divss   xmm0, xmm2
    divss   xmm1, xmm2
    movss   [rbx], xmm0
    movss   [rbx + 4], xmm1
    jmp     .done
.heading:
    movss   xmm0, [player + BODY.yaw]
    call    sincos_deg                  ; the forward vector is (sin, -cos)
    movss   [rbx], xmm0
    xorps   xmm2, xmm2
    subss   xmm2, xmm1
    movss   [rbx + 4], xmm2
.done:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ab_target(rdi eye float[3], rsi dir float[3], xmm0 range, xmm1 fallback, rdx out float[3]):
; out = the centre of the first block the look ray meets within range, else the point fallback
; blocks along it
; rbx = out, r12 = eye, r13 = dir; frame: RAYHIT @0, fallback @24
ab_target:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 40
    mov     rbx, rdx
    mov     r12, rdi
    mov     r13, rsi
    movss   [rsp + 24], xmm1
    lea     rdx, [rsp]
    call    raycast                     ; rdi, rsi, xmm0 as passed
    test    eax, eax
    jz      .miss
%assign off 0
%rep 3
    cvtsi2ss xmm0, dword [rsp + off]
    addss   xmm0, [k_half]
    movss   [rbx + off], xmm0
%assign off off + 4
%endrep
    jmp     .done
.miss:
%assign off 0
%rep 3
    movss   xmm0, [r13 + off]
    mulss   xmm0, [rsp + 24]
    addss   xmm0, [r12 + off]
    movss   [rbx + off], xmm0
%assign off off + 4
%endrep
.done:
    add     rsp, 40
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ab_box_free(xmm0 x, xmm1 feet y, xmm2 z) -> eax 1 when no solid cell overlaps the player's box
; (0.6 wide, 1.8 tall) standing there. The box is 0.001 smaller on every side, so touching a wall
; or standing on the floor is free.
; Frame: cell bounds x0 x1 y0 y1 z0 z1 (int); r12d, r13d, r14d = the cell being tested
ab_box_free:
    push    rbp
    mov     rbp, rsp
    push    r12
    push    r13
    push    r14
    sub     rsp, 24
    movaps  xmm3, xmm0
    subss   xmm3, [k_box_xz]
    roundss xmm3, xmm3, 9
    cvttss2si eax, xmm3
    mov     [rsp], eax                  ; x0 = floor(x - 0.299)
    addss   xmm0, [k_box_xz]
    roundss xmm0, xmm0, 10
    cvttss2si eax, xmm0
    dec     eax
    mov     [rsp + 4], eax              ; x1 = ceil(x + 0.299) - 1
    movaps  xmm3, xmm1
    addss   xmm3, [k_contact]
    roundss xmm3, xmm3, 9
    cvttss2si eax, xmm3
    mov     [rsp + 8], eax              ; y0 = floor(y + 0.001)
    addss   xmm1, [k_box_top]
    roundss xmm1, xmm1, 10
    cvttss2si eax, xmm1
    dec     eax
    mov     [rsp + 12], eax             ; y1 = ceil(y + 1.799) - 1
    movaps  xmm3, xmm2
    subss   xmm3, [k_box_xz]
    roundss xmm3, xmm3, 9
    cvttss2si eax, xmm3
    mov     [rsp + 16], eax             ; z0
    addss   xmm2, [k_box_xz]
    roundss xmm2, xmm2, 10
    cvttss2si eax, xmm2
    dec     eax
    mov     [rsp + 20], eax             ; z1
    mov     r14d, [rsp + 16]
.z:
    mov     r13d, [rsp + 8]
.y:
    mov     r12d, [rsp]
.x:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    call    world_is_solid
    test    eax, eax
    jnz     .blocked
    inc     r12d
    cmp     r12d, [rsp + 4]
    jle     .x
    inc     r13d
    cmp     r13d, [rsp + 12]
    jle     .y
    inc     r14d
    cmp     r14d, [rsp + 20]
    jle     .z
    mov     eax, 1
    jmp     .done
.blocked:
    xor     eax, eax
.done:
    add     rsp, 24
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    ret

; ab_blink_plan(rdi eye float[3], rsi dir float[3], rdx out float[3]) -> eax 1 when the player can
; blink at least a block: marches along dir in quarter-block steps up to 8 blocks, the candidate
; feet being eye + dir * s - (0, 1.62, 0), until the box is no longer free; out = the last free
; candidate
; rbx = out, r12 = eye, r13 = dir, r14d = step, r15d = last free step; frame: candidate float[3]
ab_blink_plan:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     rbx, rdx
    mov     r12, rdi
    mov     r13, rsi
    xor     r15d, r15d
    mov     r14d, 1
.march:
    cvtsi2ss xmm3, r14d
    mulss   xmm3, [k_quarter]           ; s
    movss   xmm0, [r13]
    mulss   xmm0, xmm3
    addss   xmm0, [r12]
    movss   [rsp], xmm0
    movss   xmm1, [r13 + 4]
    mulss   xmm1, xmm3
    addss   xmm1, [r12 + 4]
    subss   xmm1, [k_eye_h]
    movss   [rsp + 4], xmm1
    movss   xmm2, [r13 + 8]
    mulss   xmm2, xmm3
    addss   xmm2, [r12 + 8]
    movss   [rsp + 8], xmm2
    call    ab_box_free
    test    eax, eax
    jz      .stop
    mov     r15d, r14d
    mov     eax, [rsp]
    mov     [rbx], eax
    mov     eax, [rsp + 4]
    mov     [rbx + 4], eax
    mov     eax, [rsp + 8]
    mov     [rbx + 8], eax
    inc     r14d
    cmp     r14d, 32
    jbe     .march
.stop:
    xor     eax, eax
    cmp     r15d, 4                     ; best >= 1 block
    setae   al
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ab_sight_mob(rdi eye float[3], rsi dir float[3], xmm0 range) -> eax index of the hostile mob the
; look ray meets within range and nearer than the first block (which cuts the range short), or -1
; rbx = eye, r12 = dir; frame: RAYHIT @0, lo @24, hi @36, t @48
ab_sight_mob:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 64
    mov     rbx, rdi
    mov     r12, rsi
    movss   [rsp + 48], xmm0            ; distance to the first block (the whole range: none)
    lea     rdx, [rsp]
    call    raycast                     ; rdi, rsi, xmm0 as passed
    test    eax, eax
    jz      .mobs
    xor     ecx, ecx
.cell:                                  ; the block's box [b, b + 1]
    cvtsi2ss xmm0, dword [rsp + rcx*4]
    movss   [rsp + 24 + rcx*4], xmm0
    addss   xmm0, [k_one]
    movss   [rsp + 36 + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 3
    jb      .cell
    mov     rdi, rbx
    mov     rsi, r12
    lea     rdx, [rsp + 24]
    lea     rcx, [rsp + 36]
    movss   xmm0, [rsp + 48]
    call    ray_aabb
    test    eax, eax
    jz      .mobs                       ; a grazing miss: the whole range
    movss   [rsp + 48], xmm0
.mobs:
    mov     rdi, rbx
    mov     rsi, r12
    movss   xmm0, [rsp + 48]
    call    mobs_raycast                ; only a mob nearer than the block counts
    test    eax, eax
    js      .done                       ; nobody: -1
    mov     ebx, eax
    mov     edi, eax
    call    mob_is_hostile
    test    eax, eax
    mov     eax, ebx
    mov     ecx, -1
    cmovz   eax, ecx                    ; a villager or an animal does not count
.done:
    add     rsp, 64
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ab_mark_plan(rdi eye float[3], rsi dir float[3], rdx out dword[1]) -> eax 1 when a hostile mob
; stands in sight within 40 blocks, nearer than any block; out = its index
; rbx = out
ab_mark_plan:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdx
    movss   xmm0, [k_range]
    call    ab_sight_mob                ; rdi, rsi: eye, dir
    test    eax, eax
    js      .none
    mov     [rbx], eax
    mov     eax, 1
    jmp     .done
.none:
    xor     eax, eax
.done:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ab_shadow_plan(rdi eye float[3], rsi dir float[3], rdx out float[4]) -> eax 1 when a hostile mob
; stands in sight within 12 blocks, nearer than any block, with room for the player behind it;
; out = x, y, z of that spot (behind the mob by its half width + 0.8, at its feet) and the yaw
; that faces the mob from there
; rbx = out, r12 = the mob
ab_shadow_plan:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rdx
    movss   xmm0, [k_shadow_rng]
    call    ab_sight_mob                ; rdi, rsi: eye, dir
    test    eax, eax
    js      .fail
    imul    r12d, eax, MOB_size
    lea     rax, [mobs]
    add     r12, rax
    movss   xmm0, [r12 + BODY.yaw]
    call    sincos_deg                  ; the mob's forward vector is (sin, -cos)
    movss   xmm2, [r12 + BODY.half_w]
    addss   xmm2, [k_shadow_gap]
    mulss   xmm0, xmm2
    mulss   xmm1, xmm2
    movss   xmm3, [r12 + BODY.x]
    subss   xmm3, xmm0
    movss   [rbx], xmm3                 ; x - sin d
    movss   xmm3, [r12 + BODY.z]
    addss   xmm3, xmm1
    movss   [rbx + 8], xmm3             ; z + cos d
    mov     eax, [r12 + BODY.y]
    mov     [rbx + 4], eax
    movss   xmm0, [rbx]
    movss   xmm1, [rbx + 4]
    movss   xmm2, [rbx + 8]
    call    ab_box_free
    test    eax, eax
    jz      .fail
    movss   xmm0, [r12 + BODY.x]
    subss   xmm0, [rbx]
    movss   xmm1, [r12 + BODY.z]
    subss   xmm1, [rbx + 8]
    call    yaw_from
    movss   [rbx + 12], xmm0
    mov     eax, 1
    jmp     .done
.fail:
    xor     eax, eax
.done:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- the twenty effects: each (rdi eye float[3], rsi dir float[3], rdx plan float[4]) ---------

; Charge: the player is shoved forward at 22 b/s (abilities_step does the striking)
ab_charge:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    mov     rdi, rsi
    lea     rsi, [rsp]
    call    ab_forward_h
    movss   xmm0, [rsp]
    movss   [charge_dx], xmm0
    mulss   xmm0, [k_charge_kb]
    movss   [player + BODY.kbx], xmm0
    movss   xmm0, [rsp + 4]
    movss   [charge_dz], xmm0
    mulss   xmm0, [k_charge_kb]
    movss   [player + BODY.kbz], xmm0
    mov     dword [charge_t], CHARGE_STEPS
    mov     qword [charge_mask], 0
    mov     edi, SND_WARCRY
    movss   xmm0, [k_vol]
    call    audio_play
    leave
    ret

; War Cry: the war cry's bonus lasts 480 steps, every hostile mob within 6 blocks (times 1 + AREA /
; 100) is stunned 40 steps (never shortening a longer stun)
; rbx = mob, r12d = index; frame: the player's chest float[3], the radius squared @12
ab_warcry:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     dword [combat_warcry_t], WARCRY_STEPS
    movss   xmm0, [player + BODY.x]
    movss   [rsp], xmm0
    movss   xmm0, [player + BODY.y]
    addss   xmm0, [k_chest]
    movss   [rsp + 4], xmm0
    movss   xmm0, [player + BODY.z]
    movss   [rsp + 8], xmm0
    mov     edi, STAT_AREA
    call    ab_mult
    mulss   xmm0, [k_warcry_r]
    mulss   xmm0, xmm0
    movss   [rsp + 12], xmm0
    lea     rbx, [mobs]
    xor     r12d, r12d
.mob:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [rsp]
    movss   xmm1, [rbx + BODY.height]
    mulss   xmm1, [k_half]
    addss   xmm1, [rbx + BODY.y]
    subss   xmm1, [rsp + 4]             ; from the middle of the body
    movss   xmm2, [rbx + BODY.z]
    subss   xmm2, [rsp + 8]
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm0, xmm1
    addss   xmm0, xmm2
    comiss  xmm0, [rsp + 12]
    jae     .next
    test    dword [rbx + MOB.affix], AFX_JUGGERNAUT
    jnz     .next                       ; juggernauts ignore stuns
    cmp     dword [rbx + MOB.stun], WARCRY_STUN
    jge     .next                       ; never shortening a longer stun
    mov     edi, r12d
    call    mob_is_hostile
    test    eax, eax
    jz      .next
    mov     dword [rbx + MOB.stun], WARCRY_STUN
.next:
    add     rbx, MOB_size
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .mob
    movss   xmm0, [k_3]
    mov     edi, FX_GOLD
    mov     esi, 24
    call    ab_burst
    mov     edi, SND_WARCRY
    movss   xmm0, [k_vol]
    call    audio_play
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Whirlwind: 90 steps of spinning, slowed to 70 %; abilities_step pulses it
ab_whirl:
    mov     dword [whirl_t], WHIRL_STEPS
    mov     dword [combat_slow_t], WHIRL_STEPS
    ret

; Ground Slam: every hostile mob within 4 blocks (times 1 + AREA / 100) and 2 in height takes 1.5 x
; the attack of the held item as a physical melee-skill hit, shoved outwards at 2; the survivors
; are launched at 6 b/s and stunned 40 steps (the Fallen King 15, a Juggernaut elite not at all);
; the floor bursts and the camera shakes
; rbx = mask of the mobs struck, r12d = index, r13 = mob; frame: the base damage float
ab_slam:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    inv_held
    movzx   edi, byte [rax + ITEMSTACK.id]
    call    item_attack_damage
    cvtsi2ss xmm0, eax
    mulss   xmm0, [k_slam_mul]
    movss   [rsp], xmm0
    mov     edi, STAT_AREA
    call    ab_mult
    movaps  xmm1, xmm0
    mulss   xmm1, [k_slam_r]
    movss   xmm0, [rsp]
    movss   xmm2, [k_slam_dy]
    movss   xmm3, [k_slam_push]
    mov     edi, SRC_MELEE_SKILL
    mov     esi, ELEM_PHYS
    mov     edx, 1
    call    ab_sweep
    mov     rbx, rax
    xor     r12d, r12d
.mob:
    bt      rbx, r12
    jnc     .next
    imul    r13d, r12d, MOB_size
    lea     rax, [mobs]
    add     r13, rax
    mov     eax, [r13 + MOB.type]
    test    eax, eax
    jz      .next                       ; it died of the blow
    movss   xmm0, [k_slam_vy]
    movss   [r13 + BODY.vy], xmm0
    mov     ecx, SLAM_STUN
    cmp     eax, MOB_BOSS
    jne     .stun
    mov     ecx, SLAM_STUN_BOSS
.stun:
    test    dword [r13 + MOB.affix], AFX_JUGGERNAUT
    jz      .set
    xor     ecx, ecx
.set:
    cmp     [r13 + MOB.stun], ecx       ; never shortening a longer stun
    jge     .next
    mov     [r13 + MOB.stun], ecx
.next:
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .mob
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.y]
    addss   xmm1, [k_slam_up]
    movss   xmm2, [player + BODY.z]
    movss   xmm3, [k_slam_fx]
    call    fx_explosion
    movss   xmm0, [fx_shake]
    maxss   xmm0, [k_slam_shake]
    movss   [fx_shake], xmm0
    mov     edi, SND_SLAM
    movss   xmm0, [k_vol]
    call    audio_play
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Fireball: a PROJ_FIREBALL for 8, crit as rolled, at 28 b/s from half a block ahead
; rbx = eye, r12 = dir
ab_fireball:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdi
    mov     r12, rsi
    call    ab_crit
    mov     r8d, eax
    mov     edx, FIREBALL_DMG
    mov     rdi, rbx
    mov     rsi, r12
    movss   xmm0, [k_fireball_o]
    movss   xmm1, [k_fireball_v]
    mov     ecx, PROJ_FIREBALL
    call    ab_shoot
    mov     edi, SND_FIREBALL
    movss   xmm0, [k_vol]
    call    audio_play
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Blink: the player appears at the planned spot (plan), motion and fall forgotten; sparks of magic
; at both ends
; rbx = plan
ab_blink:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdx
    movss   xmm0, [k_2]
    mov     edi, FX_MAGIC
    mov     esi, 20
    call    ab_burst
    mov     eax, [rbx]
    mov     [player + BODY.x], eax
    mov     eax, [rbx + 4]
    mov     [player + BODY.y], eax
    mov     eax, [rbx + 8]
    mov     [player + BODY.z], eax
    xor     eax, eax
    mov     [player + BODY.vy], eax
    mov     [player + BODY.kbx], eax
    mov     [player + BODY.kbz], eax
    mov     [player + BODY.fall], eax
    movss   xmm0, [k_2]
    mov     edi, FX_MAGIC
    mov     esi, 20
    call    ab_burst
    mov     edi, SND_BLINK
    movss   xmm0, [k_vol]
    call    audio_play
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Meteor Storm: aims at the first block in sight (40 blocks) or 30 blocks ahead, and starts 8
; meteors falling, the first on the next step
ab_meteor:
    push    rbp
    mov     rbp, rsp
    lea     rdx, [meteor_tgt]
    movss   xmm0, [k_range]
    movss   xmm1, [k_meteor_far]
    call    ab_target                   ; rdi, rsi: eye, dir
    mov     dword [meteor_n], METEORS
    mov     dword [meteor_t], 0
    pop     rbp
    ret

; Frost Nova: every hostile mob within 5 blocks (times 1 + AREA / 100) and 3 in height takes 6
; points of frost spell damage that chills it three times - the third freezes it - shoved
; outwards at 0.5; a burst of ice around the player
ab_nova:
    push    rbp
    mov     rbp, rsp
    mov     edi, STAT_AREA
    call    ab_mult
    movaps  xmm1, xmm0
    mulss   xmm1, [k_nova_r]
    movss   xmm0, [k_nova_base]
    movss   xmm2, [k_nova_dy]
    movss   xmm3, [k_nova_push]
    mov     edi, SRC_SPELL
    mov     esi, ELEM_FROST | HITF_CHILL3
    mov     edx, 1
    call    ab_sweep
    movss   xmm0, [k_6]
    mov     edi, FX_FROST
    mov     esi, 40
    call    ab_burst
    mov     edi, SND_FREEZE
    movss   xmm0, [k_vol]
    call    audio_play
    pop     rbp
    ret

; Volley: five arrows fanned at -20, -10, 0, 10 and 20 degrees of yaw (seven from -30 to 30 with
; Barrage), each carrying 6 and rolling its own crit, none taken from the quiver
; rbx = eye, r12 = dir, r13d = arrow, r14d = arrows; frame: this arrow's direction float[3]
ab_volley:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     rbx, rdi
    mov     r12, rsi
    mov     r14d, 5
    mov     edi, KS_BARRAGE
    call    rpg_keystone
    test    eax, eax
    jz      .fan
    mov     r14d, 7
.fan:
    xor     r13d, r13d
.arrow:
    lea     eax, [r13 + r13 + 1]
    sub     eax, r14d                   ; 2 i + 1 - n: -4 .. 4 for five arrows, -6 .. 6 for seven
    imul    eax, eax, 5                 ; ...times 5 degrees
    cvtsi2ss xmm0, eax
    call    sincos_deg                  ; xmm0 = sin, xmm1 = cos of the offset
    movss   xmm2, [r12]
    movss   xmm3, [r12 + 8]
    movaps  xmm4, xmm2
    mulss   xmm4, xmm1
    movaps  xmm5, xmm3
    mulss   xmm5, xmm0
    subss   xmm4, xmm5
    movss   [rsp], xmm4                 ; x cos - z sin
    movss   xmm4, [r12 + 4]
    movss   [rsp + 4], xmm4             ; the pitch stays
    mulss   xmm3, xmm1
    mulss   xmm2, xmm0
    addss   xmm3, xmm2
    movss   [rsp + 8], xmm3             ; z cos + x sin
    call    ab_crit
    mov     r8d, eax
    mov     edx, VOLLEY_DMG
    mov     rdi, rbx
    lea     rsi, [rsp]
    movss   xmm0, [k_arrow_o]
    movss   xmm1, [k_volley_v]
    mov     ecx, PROJ_ARROW
    call    ab_shoot
    inc     r13d
    cmp     r13d, r14d
    jb      .arrow
    mov     edi, SND_BOW
    movss   xmm0, [k_vol]
    call    audio_play
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Explosive Arrow: one arrow at 45 b/s for 10, crit as rolled, that blows up (fire) where it
; lands instead of sticking
; rbx = eye, r12 = dir
ab_explosive:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdi
    mov     r12, rsi
    call    ab_crit
    or      eax, AF_EXPLOSIVE
    mov     r8d, eax
    mov     edx, EXPLOSIVE_DMG
    mov     rdi, rbx
    mov     rsi, r12
    movss   xmm0, [k_arrow_o]
    movss   xmm1, [k_explode_v]
    mov     ecx, PROJ_ARROW
    call    ab_shoot
    mov     edi, SND_BOW
    movss   xmm0, [k_vol]
    call    audio_play
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Arrow Rain: aims like the meteor storm (25 blocks ahead when nothing is in sight) and starts 24
; arrows falling, the first on the next step
ab_rain:
    push    rbp
    mov     rbp, rsp
    lea     rdx, [rain_tgt]
    movss   xmm0, [k_range]
    movss   xmm1, [k_rain_far]
    call    ab_target
    mov     dword [rain_n], RAIN_ARROWS
    mov     dword [rain_t], 0
    pop     rbp
    ret

; Hunter's Mark: the mob the plan holds takes 30% more damage for 600 steps (the pipeline reads its
; mark timer); gold sparks over its head
; rbx = mob
ab_mark:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    imul    eax, [rdx], MOB_size
    lea     rbx, [mobs]
    add     rbx, rax
    mov     dword [rbx + MOB.mark_t], MARK_STEPS
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [rbx + BODY.height]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [k_2]
    mov     edi, FX_GOLD
    mov     esi, 12
    call    fx_burst
    mov     edi, SND_SPELL
    movss   xmm0, [k_vol]
    call    audio_play
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Shadowstep: the player appears at the planned spot behind the mob, facing it, pitch level; his
; next hit within 120 steps is a crit. Sparks of magic at both ends.
; rbx = plan
ab_shadowstep:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdx
    movss   xmm0, [k_2]
    mov     edi, FX_MAGIC
    mov     esi, 16
    call    ab_burst
    mov     eax, [rbx]
    mov     [player + BODY.x], eax
    mov     eax, [rbx + 4]
    mov     [player + BODY.y], eax
    mov     eax, [rbx + 8]
    mov     [player + BODY.z], eax
    mov     eax, [rbx + 12]
    mov     [player + BODY.yaw], eax
    xor     eax, eax
    mov     [player + BODY.pitch], eax
    mov     [player + BODY.vy], eax
    mov     [player + BODY.kbx], eax
    mov     [player + BODY.kbz], eax
    mov     [player + BODY.fall], eax
    mov     dword [combat_crit_next_t], CRIT_NEXT_STEPS
    movss   xmm0, [k_2]
    mov     edi, FX_MAGIC
    mov     esi, 16
    call    ab_burst
    mov     edi, SND_BLINK
    movss   xmm0, [k_vol]
    call    audio_play
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; Smoke Bomb: a cloud around the player and 300 steps of stealth (1800 under Shadow Dance)
ab_smoke:
    push    rbp
    mov     rbp, rsp
    movss   xmm0, [k_25]
    mov     edi, FX_SMOKE
    mov     esi, 40
    call    ab_burst
    mov     edi, KS_SHADOW_DANCE
    call    rpg_keystone
    mov     ecx, STEALTH_STEPS
    mov     edx, DANCE_STEPS
    test    eax, eax
    cmovnz  ecx, edx
    mov     [combat_stealth_t], ecx
    mov     edi, SND_SMOKE
    movss   xmm0, [k_vol]
    call    audio_play
    pop     rbp
    ret

; Blade Dance: 360 steps of crits at double attack speed
ab_blade:
    push    rbp
    mov     rbp, rsp
    mov     dword [combat_blade_t], BLADE_STEPS
    movss   xmm0, [k_3]
    mov     edi, FX_MAGIC
    mov     esi, 20
    call    ab_burst
    mov     edi, SND_WARCRY
    movss   xmm0, [k_vol]
    call    audio_play
    pop     rbp
    ret

; Fan of Knives: eight PROJ_KNIFE thrown level from half a block below the eye, 45 degrees apart
; starting along the player's heading, 30 b/s, 6 each, bleeding, each rolling its own crit; nobody
; picks them up again
; rbx = eye, r12d = knife; frame: sin and cos of the knife's heading
ab_knives:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    mov     rbx, rdi
    xor     r12d, r12d
.knife:
    imul    eax, r12d, 45
    cvtsi2ss xmm0, eax
    addss   xmm0, [player + BODY.yaw]
    call    sincos_deg                  ; xmm0 = sin, xmm1 = cos: the heading is (sin, -cos)
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    call    ab_crit
    or      eax, AF_BLEED
    mov     r8d, eax
    movss   xmm3, [rsp]
    mulss   xmm3, [k_knife_v]           ; vx
    movss   xmm5, [rsp + 4]
    mulss   xmm5, [k_knife_v]
    xorps   xmm6, xmm6
    subss   xmm6, xmm5
    movaps  xmm5, xmm6                  ; vz = -30 cos
    xorps   xmm4, xmm4                  ; level
    movss   xmm0, [rbx]
    movss   xmm1, [rbx + 4]
    subss   xmm1, [k_knife_drop]
    movss   xmm2, [rbx + 8]
    xor     edi, edi                    ; the player's
    mov     esi, KNIFE_DMG
    xor     edx, edx                    ; nobody picks it up
    mov     ecx, PROJ_KNIFE
    call    arrows_spawn
    inc     r12d
    cmp     r12d, KNIVES
    jb      .knife
    mov     edi, SND_KNIVES
    movss   xmm0, [k_vol]
    call    audio_play
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Powder Grenade: a PROJ_GRENADE for 12, crit as rolled, lobbed at 20 b/s from half a block ahead;
; it bursts into flame where it lands (arrows.asm)
; rbx = eye, r12 = dir
ab_grenade:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rdi
    mov     r12, rsi
    call    ab_crit
    mov     r8d, eax
    mov     edx, GRENADE_DMG
    mov     rdi, rbx
    mov     rsi, r12
    movss   xmm0, [k_grenade_o]
    movss   xmm1, [k_grenade_v]
    mov     ecx, PROJ_GRENADE
    call    ab_shoot
    mov     edi, SND_BOW
    movss   xmm0, [k_vol]
    call    audio_play
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Bullseye: 300 steps of firearm shots that fly true and crit more (guns.asm reads the timer)
ab_bullseye:
    push    rbp
    mov     rbp, rsp
    mov     dword [combat_bullseye_t], BULLSEYE_STEPS
    movss   xmm0, [k_3]
    mov     edi, FX_GOLD
    mov     esi, 16
    call    ab_burst
    mov     edi, SND_SPELL
    movss   xmm0, [k_vol]
    call    audio_play
    pop     rbp
    ret

; Fan the Hammer: 240 steps of firearms that fire twice as fast and keep their rounds (guns.asm
; reads the timer)
ab_fanhammer:
    push    rbp
    mov     rbp, rsp
    mov     dword [combat_fanhammer_t], FANHAMMER_STEPS
    movss   xmm0, [k_3]
    mov     edi, FX_SPARK
    mov     esi, 20
    call    ab_burst
    mov     edi, SND_WARCRY
    movss   xmm0, [k_vol]
    call    audio_play
    pop     rbp
    ret

; Flashbang: a PROJ_GRENADE for no damage, flagged AF_FLASH, lobbed like the powder grenade; where
; it lands arrows.asm calls ab_flash_at instead of exploding
ab_flashbang:
    push    rbp
    mov     rbp, rsp
    xor     edx, edx
    mov     ecx, PROJ_GRENADE
    mov     r8d, AF_FLASH
    movss   xmm0, [k_grenade_o]
    movss   xmm1, [k_grenade_v]
    call    ab_shoot                    ; rdi, rsi: eye, dir
    mov     edi, SND_BOW
    movss   xmm0, [k_vol]
    call    audio_play
    pop     rbp
    ret

; ab_flash_at(xmm0 x, xmm1 y, xmm2 z): a flashbang bursts at that point. Every hostile mob whose body
; middle is within 5 blocks of it (times 1 + AREA / 100, times 1.5 with Powder Keg) is stunned 60
; steps (the Fallen King 20, a Juggernaut elite not at all), never shortening a longer stun; gold
; sparks and a bang. No damage.
; rbx = mob, r12d = index; frame: the point float[3], the radius squared @12
ab_flash_at:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 16
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    mov     edi, STAT_AREA
    call    ab_mult
    mulss   xmm0, [k_flash_r]
    movss   [rsp + 12], xmm0            ; the radius
    mov     edi, KS_POWDER_KEG
    call    rpg_keystone
    movss   xmm0, [rsp + 12]
    test    eax, eax
    jz      .radius
    mulss   xmm0, [k_keg]               ; Powder Keg: 50 % wider
.radius:
    mulss   xmm0, xmm0
    movss   [rsp + 12], xmm0
    lea     rbx, [mobs]
    xor     r12d, r12d
.mob:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [rsp]
    movss   xmm1, [rbx + BODY.height]
    mulss   xmm1, [k_half]
    addss   xmm1, [rbx + BODY.y]
    subss   xmm1, [rsp + 4]             ; from the middle of the body
    movss   xmm2, [rbx + BODY.z]
    subss   xmm2, [rsp + 8]
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    mulss   xmm2, xmm2
    addss   xmm0, xmm1
    addss   xmm0, xmm2
    comiss  xmm0, [rsp + 12]
    jae     .next
    test    dword [rbx + MOB.affix], AFX_JUGGERNAUT
    jnz     .next                       ; juggernauts ignore stuns
    mov     edi, r12d
    call    mob_is_hostile
    test    eax, eax
    jz      .next
    mov     ecx, FLASH_STUN
    cmp     dword [rbx + MOB.type], MOB_BOSS
    jne     .stun
    mov     ecx, FLASH_STUN_BOSS
.stun:
    cmp     [rbx + MOB.stun], ecx
    jge     .next                       ; never shortening a longer stun
    mov     [rbx + MOB.stun], ecx
.next:
    add     rbx, MOB_size
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .mob
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    movss   xmm3, [k_6]
    mov     edi, FX_GOLD
    mov     esi, 40
    call    fx_burst
    mov     edi, SND_EXPLODE
    movss   xmm0, [k_flash_vol]
    call    audio_play
    add     rsp, 16
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- the lasting abilities, once per step -------------------------------------------------------

; ab_charge_step(): while the charge lasts, every hostile mob the player touches (horizontal
; distance < its half width + 0.9, within 1.5 blocks in height) and has not struck yet takes a
; 10 point physical melee-skill hit along the charge and is stunned 30 steps
; rbx = mob, r12d = index, r13 = mask of the struck
ab_charge_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    cmp     dword [charge_t], 0
    jle     .done
    dec     dword [charge_t]
    mov     r13, [charge_mask]
    lea     rbx, [mobs]
    xor     r12d, r12d
.mob:
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next
    bt      r13, r12
    jc      .next
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [player + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    subss   xmm1, [player + BODY.z]
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1                  ; horizontal distance^2
    movss   xmm2, [rbx + BODY.half_w]
    addss   xmm2, [k_reach]
    mulss   xmm2, xmm2
    comiss  xmm0, xmm2
    jae     .next
    movss   xmm0, [rbx + BODY.y]
    subss   xmm0, [player + BODY.y]
    movss   xmm1, [k_abs]
    andps   xmm1, xmm0                  ; |dy|
    comiss  xmm1, [k_charge_dy]
    jae     .next
    mov     edi, r12d
    call    mob_is_hostile
    test    eax, eax
    jz      .next
    mov     edi, r12d
    mov     esi, SRC_MELEE_SKILL
    xor     edx, edx                    ; physical
    movss   xmm0, [k_charge_dmg]
    movss   xmm1, [charge_dx]
    mulss   xmm1, [k_charge_hit]
    movss   xmm2, [charge_dz]
    mulss   xmm2, [k_charge_hit]
    call    combat_hit_mob
    bts     r13, r12
    cmp     dword [rbx + MOB.type], MOB_NONE
    je      .next                       ; it died
    test    dword [rbx + MOB.affix], AFX_JUGGERNAUT
    jnz     .next                       ; juggernauts ignore stuns
    cmp     dword [rbx + MOB.stun], 30
    jge     .next                       ; never shortening a longer stun (a freeze)
    mov     dword [rbx + MOB.stun], 30
.next:
    add     rbx, MOB_size
    inc     r12d
    cmp     r12d, MAX_MOBS
    jb      .mob
    mov     [charge_mask], r13
.done:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ab_whirl_step(): a pulse when 90, 60 and 30 steps are left, then one step less
ab_whirl_step:
    push    rbp
    mov     rbp, rsp
    mov     eax, [whirl_t]
    test    eax, eax
    jle     .done
    xor     edx, edx
    mov     ecx, WHIRL_PERIOD
    div     ecx
    test    edx, edx
    jnz     .tick
    call    ab_whirl_pulse
.tick:
    dec     dword [whirl_t]
.done:
    pop     rbp
    ret

; ab_whirl_pulse(): one spin: every hostile mob within 3.5 blocks (times 1 + AREA / 100) and 2 in
; height takes the attack of the held item (x1.3 under the war cry) as a physical melee-skill hit,
; thrown outwards at 1.5; sparks, the whirl sound and the arm swings
; frame: the base damage float
ab_whirl_pulse:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    call    inv_held
    movzx   edi, byte [rax + ITEMSTACK.id]
    call    item_attack_damage
    cvtsi2ss xmm0, eax
    cmp     dword [combat_warcry_t], 0
    jle     .base
    mulss   xmm0, [k_warcry_mul]
.base:
    movss   [rsp], xmm0
    mov     edi, STAT_AREA
    call    ab_mult
    movaps  xmm1, xmm0
    mulss   xmm1, [k_whirl_r]
    movss   xmm0, [rsp]
    movss   xmm2, [k_whirl_dy]
    movss   xmm3, [k_whirl_push]
    mov     edi, SRC_MELEE_SKILL
    mov     esi, ELEM_PHYS
    xor     edx, edx                    ; the whirlwind never rolled a crit
    call    ab_sweep
    movss   xmm0, [k_4]
    mov     edi, FX_SPARK
    mov     esi, 16
    call    ab_burst
    mov     edi, SND_WHIRL
    movss   xmm0, [k_vol]
    call    audio_play
    call    hand_swing
    leave
    ret

; ab_meteor_step(): the next meteor falls when its wait is over (the first one at once): a
; fireball (AF_BIG) at the target + (U(-4, 4), 18, U(-4, 4)) falling at 30 b/s; then 22 steps wait
; frame: where it starts float[3]
ab_meteor_step:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    cmp     dword [meteor_n], 0
    jle     .done
    mov     eax, [meteor_t]
    test    eax, eax
    jz      .drop
    dec     eax
    mov     [meteor_t], eax
    jnz     .done
.drop:
    movss   xmm0, [k_spread]
    call    ab_rnd
    addss   xmm0, [meteor_tgt]
    movss   [rsp], xmm0
    movss   xmm0, [meteor_tgt + 4]
    addss   xmm0, [k_meteor_h]
    movss   [rsp + 4], xmm0
    movss   xmm0, [k_spread]
    call    ab_rnd
    addss   xmm0, [meteor_tgt + 8]
    movss   [rsp + 8], xmm0
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    xorps   xmm3, xmm3
    movss   xmm4, [k_meteor_v]
    xorps   xmm5, xmm5
    xor     edi, edi
    mov     esi, METEOR_DMG
    xor     edx, edx
    mov     ecx, PROJ_FIREBALL
    mov     r8d, AF_BIG
    call    arrows_spawn
    dec     dword [meteor_n]
    mov     dword [meteor_t], METEOR_GAP
.done:
    leave
    ret

; ab_rain_step(): the next arrow falls when its wait is over (the first one at once): at the
; target + (U(-4, 4), 14, U(-4, 4)) falling at 35 b/s; then 5 steps wait
; frame: where it starts float[3]
ab_rain_step:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 16
    cmp     dword [rain_n], 0
    jle     .done
    mov     eax, [rain_t]
    test    eax, eax
    jz      .drop
    dec     eax
    mov     [rain_t], eax
    jnz     .done
.drop:
    movss   xmm0, [k_spread]
    call    ab_rnd
    addss   xmm0, [rain_tgt]
    movss   [rsp], xmm0
    movss   xmm0, [rain_tgt + 4]
    addss   xmm0, [k_rain_h]
    movss   [rsp + 4], xmm0
    movss   xmm0, [k_spread]
    call    ab_rnd
    addss   xmm0, [rain_tgt + 8]
    movss   [rsp + 8], xmm0
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    xorps   xmm3, xmm3
    movss   xmm4, [k_rain_v]
    xorps   xmm5, xmm5
    xor     edi, edi
    mov     esi, RAIN_DMG
    xor     edx, edx
    mov     ecx, PROJ_ARROW
    xor     r8d, r8d
    call    arrows_spawn
    dec     dword [rain_n]
    mov     dword [rain_t], RAIN_GAP
.done:
    leave
    ret

; abilities_shift(edi dx, esi dz): the origin moved by (dx, dz) blocks: the local x and z of the
; meteor storm's and the arrow rain's target drop by that much (exact: multiples of 512). Nothing
; else here is a position: charge_dx / charge_dz are a heading.
abilities_shift:
    cvtsi2ss xmm0, edi
    cvtsi2ss xmm1, esi
    movss   xmm2, [meteor_tgt]
    subss   xmm2, xmm0
    movss   [meteor_tgt], xmm2
    movss   xmm2, [meteor_tgt + 8]
    subss   xmm2, xmm1
    movss   [meteor_tgt + 8], xmm2
    movss   xmm2, [rain_tgt]
    subss   xmm2, xmm0
    movss   [rain_tgt], xmm2
    movss   xmm2, [rain_tgt + 8]
    subss   xmm2, xmm1
    movss   [rain_tgt + 8], xmm2
    ret
