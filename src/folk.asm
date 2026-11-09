; folk.asm - faction folk: every faction member is one MOB_FOLK mob whose MOB.faction, .role and
; .fclass (common.inc ROLE_*, FCLASS_*) say who it is. This file holds what makes them people:
; spawning and arming them (a fighter's class gives it health, speed, a weapon and its element), the
; AI of the fighters (targets, melee, arrows, bolts, patrols, sleeping champions) and of everyone
; else (strolling, fleeing, captives, travellers), what a right-click opens, what a blow from the
; player does to their standing (provoking, waking, scaring), what their death and loot are, the name
; plate text and the travelling trader. mobs.asm calls into it from mob_ai, mob_damage, mob_drops,
; mob_scale, mob_is_hostile and mobs_step.
%include "common.inc"
default rel

global folk_spawn, folk_init, folk_make_champion, folk_ai, folk_interact, folk_hostile
global folk_on_player_hit, folk_on_death, folk_drops, folk_hit_by, folk_name, folk_travel_tick
global folk_weapon_affix, folk_class_health, folk_base_speed, folk_is_fighter, folk_scare, folk_free_captive

extern mobs, mob_spawn, mob_scale, make_elite, mob_level_for, yaw_from
extern mob_blow, mob_melee_hit, mob_arrow_flags, knock_player, mob_reel, mob_stunned_text
extern mob_strike, folk_strike_mob, mob_coins, spawn_near_player
extern gear_affixes, gear_roll, gear_tier_for_level, gear_drop_from_mob, item_attack
extern drops_spawn, arrows_spawn, audio_play_at, fx_burst, status_apply
extern player, raycast, rng_next, sky_is_night
extern game_mode, game_time, settings, surv, combat_hit_flags, combat_stealth_t
extern hud_banner, str_append
extern faction_standing, faction_tier, faction_add, faction_on_kill, faction_enemies, faction_hostile
extern faction_defeat_champion
extern faction_names, faction_members, champion_names, screen_faction
extern trade_open, structures_nearest, structures_mark_freed
extern mob_index, mob_tgt_body, mob_tgt_slot
extern net_role, net_self, net_hit_peer, net_peer_body, net_nearest_target, net_slot_ok, net_interact_out

%define SEE_STEPS     20                ; a fighter looks for a new target this often
%define PROVOKE_STEPS 600               ; a blow on a folk keeps its faction's fighters after the player this long
%define FLEE_STEPS    120               ; a scared non-fighter runs this long
%define GREET_STEPS   1200              ; a guard greets a friend again after this
%define PATROL_STUCK  120               ; blocked steps in a row after which a patrol turns round
%define RAGE_WINDUP   8                 ; a berserker below half health
%define RAGE_COOLDOWN 20
%define WHIFF_COOLDOWN 20               ; a blow that found nobody there
%define TRAVEL_PERIOD 3600              ; the travelling trader may come at the start of every 3600th step...
%define TRAVEL_TRIES  8                 ; ...tries this many spots around the player...
%define TRAVEL_LIFE   18000             ; ...and stays this long
%define COL_RED       RGBA(255, 85, 85, 255)
%define COL_GREEN     RGBA(140, 255, 90, 255)
%define COL_GOLD      RGBA(255, 215, 60, 255)
%define COL_ALERT     RGBA(255, 90, 60, 255)

; folk_fight frame (rsp-relative)
%define FT_DX    0                      ; float: from this folk to its target
%define FT_DZ    4
%define FT_D2    8                      ; float: horizontal distance^2
%define FT_DY    12                     ; float: the target's feet minus its own
%define FT_TX    16                     ; float[3]: the target's feet
%define FT_COOL  28                     ; int: cooldown after a melee blow
%define FT_FRAME 48

section .rodata
align 4
; per class (FCLASS_NONE row = every non-fighter)
fc_health:  dd 20, 18, 32, 16, 24
fc_speed:   dd 2.0, 2.6, 2.2, 2.4, 3.0
fc_windup:  dd 0, 0, 28, 0, 12          ; melee wind-up and the cooldown after the blow
fc_cool:    dd 0, 0, 70, 0, 30
fc_kb:      dd 0.0, 0.0, 1.5, 0.0, 1.0  ; x the knockback speed on the player
fc_wid:     db 0, BOW, IRON_HAMMER, STAFF, IRON_SWORD           ; weapon below tier 6
            db 0, BOW, DIAMOND_HAMMER, STAFF, DIAMOND_SWORD     ; ...and from tier 6
fc_base:    db 0, 3, 0, 4, 0            ; the ranged classes' base damage
fc_sub:     db 0, 0, 4, 0, 3            ; a melee class's base damage: item_attack(weapon) - this
align 4
c_diff:     dd 0.0, 0.67, 1.0, 1.33     ; damage on the player by difficulty
c_spread:   dd 0.0, 1.5, 1.0, 0.5       ; an archer's aim error at the player by difficulty
c_one:      dd 1.0
c_half:     dd 0.5
c_tiny:     dd 0.0001
c_see2:     dd 256.0                    ; enemies within 16 blocks are noticed...
c_lose2:    dd 576.0                    ; ...and kept in mind to 24
c_watch2:   dd 144.0                    ; a captive's guards watch from 12
c_home2:    dd 36.0                     ; they walk home from beyond 6 blocks
c_talk2:    dd 16.0                     ; they turn to a player within 4
c_reach2:   dd 4.0                      ; a melee folk closes to 2 blocks...
c_strike2:  dd 5.76                     ; ...and its blow lands on a target within 2.4
c_reach_y2: dd 2.25                     ; ...and within 1.5 up or down
c_arch_near2: dd 36.0                   ; archers keep 6..12 blocks away
c_arch_far2: dd 144.0
c_aco_near2: dd 25.0                    ; acolytes 5..10
c_aco_far2: dd 100.0
c_shoot2:   dd 225.0                    ; they shoot within 15
c_eye:      dd 1.62
c_aim_up:   dd 1.0                      ; the middle of a target: 1 block above its feet
c_muzzle:   dd 0.6
c_arrow_v:  dd 24.0
c_bolt_v:   dd 18.0
c_lift:     dd 10.0                     ; upward aim per second of flight against gravity
c_cent:     dd 0.01
c_folk_spread: dd 0.5                   ; an archer's aim error at another folk
c_rage:     dd 1.3
c_flee:     dd 1.5
c_kb:       dd 6.0
c_vol:      dd 0.8
c_512_2:    dd 262144.0
elem_afx:   db AFX_MOLTEN, AFX_FROZEN, AFX_STORM, AFX_VENOMOUS   ; STAT_ADD_FIRE, FROST, SHOCK, POISON
s_no_speak: db " leader won't speak with you", 0
s_no_trade: db " won't trade with you yet", 0
s_watching: db "Its guards are watching", 0
s_freed_a:  db "Freed a ", 0
s_freed_b:  db " captive (+25)", 0
s_wakes:    db " wakes!", 0
s_fallen:   db " has fallen!", 0
s_well_met: db ": Well met, friend", 0
s_elder:    db "Elder", 0
s_merchant: db "Merchant", 0
s_chief:    db " Chief", 0
s_trader:   db " Trader", 0
s_worker:   db " Worker", 0
s_captive:  db "Captive ", 0
s_travelling: db "Travelling ", 0
s_space:    db " ", 0
s_archer:   db "Archer", 0
s_brute:    db "Brute", 0
s_acolyte:  db "Acolyte", 0
s_berserker: db "Berserker", 0
align 8
class_names: dq 0, s_archer, s_brute, s_acolyte, s_berserker

section .text

; APPEND zstr: the text goes on at r12 (end of the line being built), r12 moves past it
%macro APPEND 1
    mov     rdi, r12
    lea     rsi, [%1]
    call    str_append
    mov     r12, rax
%endmacro

; BANNER rgba: shows the NUL-terminated line that starts at [rsp]
%macro BANNER 1
    mov     byte [r12], 0
    lea     rdi, [rsp]
    mov     esi, %1
    call    hud_banner
%endmacro

; ---- who it is --------------------------------------------------------------------------------

; folk_spawn(edi faction, esi role, edx fclass, xmm0 x, xmm1 y, xmm2 z) -> eax slot index, or -1
; (no free slot): a MOB_FOLK at (x, y, z), home there, with that faction, role and class, armed and
; at its class's health (folk_init)
folk_spawn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     edi, MOB_FOLK
    call    mob_spawn
    test    eax, eax
    js      .ret
    mov     edi, eax
    mov     esi, ebx
    mov     edx, r12d
    mov     ecx, r13d
    call    folk_init
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_init(edi slot, esi faction, edx role, ecx fclass) -> eax slot: the mob in that slot (a MOB_FOLK
; fresh from mob_spawn, or a spawn_near_player one) becomes that faction's member: the fields, the
; walking speed of its class (folk_base_speed), its weapon and element when it fights (folk_arm) and
; the health of its class and level (mob_scale)
folk_init:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12d, edi
    cmp     edi, MAX_MOBS
    jae     .ret
    imul    eax, edi, MOB_size
    lea     rbx, [mobs]
    add     rbx, rax
    mov     [rbx + MOB.faction], sil
    mov     [rbx + MOB.role], dl
    mov     [rbx + MOB.fclass], cl
    mov     rdi, rbx
    call    folk_base_speed
    movss   [rbx + BODY.speed], xmm0
    mov     rdi, rbx
    call    folk_arm
    mov     rdi, rbx
    call    mob_scale
.ret:
    mov     eax, r12d
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_make_champion(edi slot): the folk in that slot becomes its faction's champion: level = the
; player's + 5, an elite (make_elite: affixes, 2.5 x the health of that level), asleep (FF_ASLEEP),
; and rearmed for its new level with a LOOT_ELITE roll. A slot that holds no folk is left alone.
folk_make_champion:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    cmp     edi, MAX_MOBS
    jae     .ret
    imul    eax, edi, MOB_size
    lea     rbx, [mobs]
    add     rbx, rax
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .ret
    xor     edi, edi
    call    mob_level_for               ; the player's level
    add     eax, 5
    mov     [rbx + MOB.level], eax
    or      byte [rbx + MOB.fflags], FF_ASLEEP
    mov     rdx, rbx
    call    make_elite                  ; resets the affixes, so the weapon's element comes after it
    mov     rdi, rbx
    call    folk_arm
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_class_row(rdi mob) -> eax the class row 1..4 of a fighter that has a class, else 0 (the
; non-fighter row). Leaf: eax, ecx.
folk_class_row:
    movzx   ecx, byte [rdi + MOB.role]
    xor     eax, eax
    cmp     ecx, ROLE_GUARD
    je      .fighter
    cmp     ecx, ROLE_CHAMPION
    je      .fighter
    cmp     ecx, ROLE_PATROL
    jne     .ret
.fighter:
    movzx   eax, byte [rdi + MOB.fclass]
    cmp     eax, NUM_FCLASSES
    jb      .ret
    xor     eax, eax
.ret:
    ret

; folk_class_health(rdi mob) -> eax the base health of that folk before its level and elite factors
; (mob_scale): its class's for a fighter, 20 for everyone else. Leaf: eax, ecx; keeps rdi.
folk_class_health:
    sub     rsp, 8
    call    folk_class_row
    add     rsp, 8
    mov     eax, [fc_health + rax*4]
    ret

; folk_base_speed(rdi mob) -> xmm0 its walking speed in blocks/s: its class's for a fighter, 2 for
; the rest, 0 for a captive. Leaf: eax, ecx, xmm0; keeps rdi.
folk_base_speed:
    sub     rsp, 8
    call    folk_class_row
    add     rsp, 8
    movss   xmm0, [fc_speed + rax*4]
    cmp     byte [rdi + MOB.role], ROLE_CAPTIVE
    jne     .ret
    xorps   xmm0, xmm0
.ret:
    ret

; folk_is_fighter(rdi mob) -> eax 1 for a GUARD, a CHAMPION or a PATROL. Leaf: eax, ecx.
folk_is_fighter:
    movzx   ecx, byte [rdi + MOB.role]
    xor     eax, eax
    cmp     ecx, ROLE_GUARD
    je      .yes
    cmp     ecx, ROLE_CHAMPION
    je      .yes
    cmp     ecx, ROLE_PATROL
    jne     .ret
.yes:
    mov     eax, 1
.ret:
    ret

; folk_weapon_affix(edi wid, esi wdmg, edx faction, ecx fclass) -> eax the AFX_* bit of a fighter's
; element, 0 for none: the first elemental affix (STAT_ADD_FIRE, FROST, SHOCK, POISON -> MOLTEN,
; FROZEN, STORM, VENOMOUS) of the weapon (gear_affixes), else MOLTEN for an Ashen Cult acolyte, else 0.
; Pure. Frame: [rsp] GEARAFFIX[5].
folk_weapon_affix:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 48
    mov     ebx, edx
    mov     r12d, ecx
    mov     rdx, rsp
    call    gear_affixes                ; edi = the weapon, esi = its dmg word
    xor     ecx, ecx
.scan:
    cmp     ecx, eax
    jae     .none
    mov     edx, [rsp + rcx*8]          ; the affix's stat
    sub     edx, STAT_ADD_FIRE
    cmp     edx, 3
    jbe     .elem
    inc     ecx
    jmp     .scan
.elem:
    movzx   eax, byte [elem_afx + rdx]
    jmp     .ret
.none:
    xor     eax, eax
    cmp     ebx, FAC_CULT
    jne     .ret
    cmp     r12d, FCLASS_ACOLYTE
    jne     .ret
    mov     eax, AFX_MOLTEN
.ret:
    add     rsp, 48
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_arm(rdi mob): a fighter with a class takes its weapon for its level (the class's, the heavier
; one from gear tier 6), a fresh gear roll of it (LOOT_ELITE for a champion, LOOT_MOB for the rest)
; and, in MOB.affix, the element of that weapon (folk_weapon_affix). Anyone else is left alone.
folk_arm:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rdi
    call    folk_class_row
    test    eax, eax
    jz      .ret
    mov     r12d, eax                   ; the class
    mov     edi, [rbx + MOB.level]
    call    gear_tier_for_level
    mov     esi, eax                    ; the tier
    xor     ecx, ecx
    cmp     eax, 6
    setae   cl
    lea     ecx, [rcx + rcx*4]          ; second row from tier 6: NUM_FCLASSES (5) entries on
    add     ecx, r12d
    movzx   edi, byte [fc_wid + rcx]
    mov     [rbx + MOB.wid], dil
    xor     edx, edx                    ; LOOT_MOB
    mov     ecx, LOOT_ELITE
    cmp     byte [rbx + MOB.role], ROLE_CHAMPION
    cmove   edx, ecx
    call    gear_roll                   ; edi = the weapon, esi = the tier
    mov     [rbx + MOB.wdmg], ax
    movzx   edi, byte [rbx + MOB.wid]
    movzx   esi, ax
    movzx   edx, byte [rbx + MOB.faction]
    movzx   ecx, byte [rbx + MOB.fclass]
    call    folk_weapon_affix
    or      [rbx + MOB.affix], eax
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_base(rdi mob) -> eax the damage a blow or shot of this fighter starts from, before its level,
; elite state and the difficulty: an archer's 3, an acolyte's 4, a brute's item_attack(weapon) - 4, a
; berserker's item_attack(weapon) - 3; at least 1. Leaf: eax, ecx, edx.
folk_base:
    movzx   ecx, byte [rdi + MOB.fclass]
    cmp     ecx, NUM_FCLASSES
    jae     .one
    movzx   eax, byte [fc_sub + rcx]
    test    eax, eax
    jnz     .melee
    movzx   eax, byte [fc_base + rcx]
    jmp     .floor
.melee:
    movzx   edx, byte [rdi + MOB.wid]
    lea     rcx, [item_attack]
    movzx   edx, byte [rcx + rdx]
    sub     edx, eax
    mov     eax, edx
.floor:
    mov     edx, 1
    cmp     eax, edx
    cmovl   eax, edx
    ret
.one:
    mov     eax, 1
    ret

; folk_base_d(rdi mob) -> eax folk_base x {0, 0.67, 1.0, 1.33}[difficulty], rounded, at least 1: what
; this fighter's blow starts from against the player
folk_base_d:
    push    rbx
    mov     rbx, rdi
    call    folk_base
    mov     ecx, [settings + SETTINGS.difficulty]
    mov     edx, DIFF_HARD
    cmp     ecx, edx
    cmova   ecx, edx
    cvtsi2ss xmm0, eax
    mulss   xmm0, [c_diff + rcx*4]
    cvtss2si eax, xmm0
    mov     edx, 1
    cmp     eax, edx
    cmovl   eax, edx
    pop     rbx
    ret

; ---- hostility --------------------------------------------------------------------------------

; folk_wants_any(rdi mob) -> eax 1 when this fighter counts a player an enemy right now, whoever he is: the game
; is in Survival above Peaceful, and either the faction's standing is below 0 or the folk is provoked
folk_wants_any:
    push    rbx
    mov     rbx, rdi
    xor     eax, eax
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .ret
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    je      .ret
    mov     eax, 1
    cmp     dword [rbx + MOB.provoked], 0
    jg      .ret
    movzx   edi, byte [rbx + MOB.faction]
    call    faction_hostile
.ret:
    pop     rbx
    ret

; folk_wants_player(rdi mob) -> eax 1 when this fighter counts the local player an enemy right now: folk_wants_any,
; and the player lives and is not hidden in smoke
folk_wants_player:
    sub     rsp, 8
    call    folk_wants_any
    test    eax, eax
    jz      .ret
    xor     eax, eax
    cmp     dword [surv + SURVIVAL.dead], 0
    jne     .ret
    cmp     dword [combat_stealth_t], 0
    jg      .ret
    mov     eax, 1
.ret:
    add     rsp, 8
    ret

; folk_wants_slot(rdi mob, esi slot) -> eax 1 when this fighter counts the player in that peer slot an enemy right
; now: folk_wants_any, and he lives and is not hidden in smoke (net_slot_ok)
folk_wants_slot:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     r12d, esi
    call    folk_wants_any
    test    eax, eax
    jz      .ret
    mov     edi, r12d
    mov     esi, 1
    call    net_slot_ok
.ret:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; folk_player_body(rdi mob) -> rax the BODY of the player this folk deals with, edx his peer slot: the local
; player offline; online (a folk acts on a host) the player it is after (target 1: MOB.peer) while he is in
; the game, else the nearest one who lives (net_nearest_target), the local player when nobody does. Clobbers
; ecx and the SSE registers.
folk_player_body:
    lea     rax, [player]
    xor     edx, edx
    cmp     byte [net_role], NET_ROLE_OFF
    je      .ret
    push    rbx
    mov     rbx, rdi
    cmp     dword [rbx + MOB.target], 1
    jne     .nearest
    mov     edi, [rbx + MOB.peer]
    call    net_peer_body               ; rax = his body, 0 when he has left
    test    rax, rax
    jz      .nearest
    mov     edx, [rbx + MOB.peer]
    pop     rbx
    ret
.nearest:
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    xor     edi, edi
    call    net_nearest_target
    test    rax, rax
    jnz     .got
    lea     rax, [player]
    movzx   edx, byte [net_self]
.got:
    pop     rbx
.ret:
    ret

; folk_hostile(rdi mob) -> eax 1 when that folk counts as hostile to the player: a fighter that is
; awake and either has the player for its target or wants him for one (folk_wants_player). Health
; bars, ability targets, the Storm arc, blasts and the bed check treat only such folk as enemies.
folk_hostile:
    push    rbx
    mov     rbx, rdi
    call    folk_is_fighter
    test    eax, eax
    jz      .ret
    xor     eax, eax
    test    byte [rbx + MOB.fflags], FF_ASLEEP
    jnz     .ret
    mov     eax, 1
    cmp     dword [rbx + MOB.target], 1
    je      .ret
    mov     rdi, rbx
    call    folk_wants_player
.ret:
    pop     rbx
    ret

; folk_wake(rdi mob): a sleeping champion wakes: FF_ASLEEP goes and "<name> wakes!" shows. Awake
; folk are left alone. Frame: [rsp] the line.
folk_wake:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 64
    test    byte [rdi + MOB.fflags], FF_ASLEEP
    jz      .ret
    mov     rbx, rdi
    and     byte [rbx + MOB.fflags], ~FF_ASLEEP
    movzx   eax, byte [rbx + MOB.faction]
    cmp     eax, NUM_FACTIONS
    jae     .ret
    lea     r12, [rsp]
    lea     rcx, [champion_names]
    mov     rsi, [rcx + rax*8]
    mov     rdi, r12
    call    str_append
    mov     r12, rax
    APPEND  s_wakes
    BANNER  COL_ALERT
.ret:
    add     rsp, 64
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_scare(rdi mob, xmm0 dirx, xmm1 dirz): a folk that is no fighter and no captive runs from a
; blow that came along (dirx, dirz): it heads along it for PANIC_STEPS and holds no target. A fighter
; or a captive is left alone.
folk_scare:
    push    rbx
    mov     rbx, rdi
    call    folk_is_fighter
    test    eax, eax
    jnz     .ret
    cmp     byte [rbx + MOB.role], ROLE_CAPTIVE
    je      .ret
    mov     dword [rbx + MOB.panic], FLEE_STEPS
    mov     dword [rbx + MOB.target], 0
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
.ret:
    pop     rbx
    ret

; folk_on_player_hit(rdi mob): the player struck this folk (mob_damage, HF_PLAYER). It is provoked
; for PROVOKE_STEPS, and so is every fighter of its faction within 16 blocks; a sleeping champion
; among them wakes. A fighter takes the player for its target at once; a non-fighter (a captive
; excepted) panics and runs from him. Whatever burning or poison it carries is the player's now.
; rbx = the mob, r12 = the folk being looked at, r13d = its faction, r14d = slots left
folk_on_player_hit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    and     byte [rbx + MOB.fflags], ~FF_FOLKDOT
    cmp     byte [net_role], NET_ROLE_OFF
    je      .peer_set
    mov     eax, [net_hit_peer]         ; online: it goes for the player who hit it
    mov     [rbx + MOB.peer], eax
.peer_set:
    mov     dword [rbx + MOB.provoked], PROVOKE_STEPS
    movzx   r13d, byte [rbx + MOB.faction]
    mov     rdi, rbx
    call    folk_is_fighter
    test    eax, eax
    jz      .scared
    mov     rdi, rbx
    call    folk_wake
    mov     dword [rbx + MOB.target], 1
    jmp     .allies
.scared:
    cmp     byte [rbx + MOB.role], ROLE_CAPTIVE
    je      .allies
    mov     dword [rbx + MOB.panic], FLEE_STEPS
    mov     dword [rbx + MOB.target], 1
.allies:
    lea     r12, [mobs]
    mov     r14d, MAX_MOBS
.ally:
    cmp     dword [r12 + MOB.type], MOB_FOLK
    jne     .next
    cmp     r12, rbx
    je      .next
    cmp     [r12 + MOB.faction], r13b
    jne     .next
    movss   xmm0, [r12 + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [r12 + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_see2]
    jae     .next
    mov     rdi, r12
    call    folk_is_fighter
    test    eax, eax
    jz      .next
    mov     dword [r12 + MOB.provoked], PROVOKE_STEPS
    mov     rdi, r12
    call    folk_wake
.next:
    add     r12, MOB_size
    dec     r14d
    jnz     .ally
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_hit_by(edi idx, esi dmg, edx elem, xmm0 dirx, xmm1 dirz): a projectile of a rival faction
; (arrows.asm) hit the folk in slot idx: dmg through mob_strike (inside the hurt window too), no
; player tag, no provocation; an elemental one (elem = ELEM_FIRE..ELEM_POISON) also puts that element's
; status of max(1, dmg / 2) on it (a burn it dies of is nobody's kill: FF_FOLKDOT); a sleeping
; champion wakes (without a banner); one that is no fighter runs from the shot (folk_scare).
; rbx = the mob, r12d = slot, r13d = dmg, r14d = elem; frame: [rsp] dirx, [rsp+4] dirz
folk_hit_by:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    cmp     edi, MAX_MOBS
    jae     .ret
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    imul    eax, edi, MOB_size
    lea     rbx, [mobs]
    add     rbx, rax
    mov     byte [combat_hit_flags], 0
    call    mob_strike                  ; edi, esi, xmm0, xmm1 as passed
    test    eax, eax
    jz      .ret
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .ret                        ; it fell
    and     byte [rbx + MOB.fflags], ~FF_ASLEEP
    lea     eax, [r14 - 1]
    cmp     eax, 3
    ja      .scare                      ; no element: ELEM_PHYS or unknown
    mov     esi, eax                    ; ELEM_* - 1 = STS_*
    mov     eax, r13d
    shr     eax, 1
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx
    cvtsi2ss xmm0, eax
    mov     edi, r12d
    call    status_apply
    or      byte [rbx + MOB.fflags], FF_FOLKDOT
.scare:
    mov     rdi, rbx
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    folk_scare
.ret:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_on_death(rdi mob): called when a folk dies (mob_damage), before its loot. A player's kill (the
; mob is tagged) costs its faction standing (faction_on_kill; a leader or champion counts big); the
; player's kill of a champion also marks it defeated for good (faction_defeat_champion) with the
; banner "<name> has fallen!". Any other death changes nothing. Frame: [rsp] the line.
folk_on_death:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 64
    mov     rbx, rdi
    cmp     dword [rbx + MOB.tagged], 0
    jle     .ret
    movzx   edi, byte [rbx + MOB.faction]
    cmp     edi, NUM_FACTIONS
    jae     .ret
    xor     esi, esi
    movzx   eax, byte [rbx + MOB.role]
    mov     ecx, 1
    cmp     eax, ROLE_LEADER
    cmove   esi, ecx
    cmp     eax, ROLE_CHAMPION
    cmove   esi, ecx
    call    faction_on_kill
    cmp     byte [rbx + MOB.role], ROLE_CHAMPION
    jne     .ret
    movzx   edi, byte [rbx + MOB.faction]
    call    faction_defeat_champion
    movzx   eax, byte [rbx + MOB.faction]
    lea     r12, [rsp]
    lea     rcx, [champion_names]
    mov     rsi, [rcx + rax*8]
    mov     rdi, r12
    call    str_append
    mov     r12, rax
    APPEND  s_fallen
    BANNER  COL_GOLD
.ret:
    add     rsp, 64
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- loot -------------------------------------------------------------------------------------

; folk_drop_weapon(rdi mob): the weapon it carries (with its roll) pops out of it; nothing for the unarmed
folk_drop_weapon:
    push    rbx
    sub     rsp, 16
    mov     rbx, rdi
    movzx   edi, byte [rbx + MOB.wid]
    test    edi, edi
    jz      .ret
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.height]
    mulss   xmm1, [c_half]
    addss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    mov     esi, 1
    movzx   edx, word [rbx + MOB.wdmg]
    call    drops_spawn
.ret:
    add     rsp, 16
    pop     rbx
    ret

; folk_drops(rdi mob): the loot of a dead folk (mob_drops calls it instead of the type tables):
; a guard or patrol 1 + level / 10 coins and, one time in four, its weapon; a champion the player
; slew (tagged) its weapon, the gear of the Fallen King's kind (gear_drop_from_mob: his class's
; legendary, 3 boss rolls and a jewel one time in four) and 20 + level coins, one that died some
; other way (it comes back) a guard's; a leader 5 + level / 5 coins; a trader or traveller 3; a
; worker or captive nothing.
folk_drops:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rdi
    movzx   eax, byte [rbx + MOB.role]
    cmp     eax, ROLE_GUARD
    je      .fighter
    cmp     eax, ROLE_PATROL
    je      .fighter
    cmp     eax, ROLE_CHAMPION
    je      .champion
    cmp     eax, ROLE_LEADER
    je      .leader
    cmp     eax, ROLE_TRADER
    je      .trade
    cmp     eax, ROLE_TRAVELLER
    jne     .ret
.trade:
    mov     edx, 3
    jmp     .coins
.fighter:
    call    rng_next
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    cmp     edx, 25
    jae     .fighter_coins
    mov     rdi, rbx
    call    folk_drop_weapon
.fighter_coins:
    mov     eax, [rbx + MOB.level]
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    lea     edx, [rax + 1]
    jmp     .coins
.champion:
    cmp     dword [rbx + MOB.tagged], 0
    jle     .fighter                    ; not the player's kill: it is not defeated, so no hoard
    mov     rdi, rbx
    call    folk_drop_weapon
    mov     rdi, rbx
    call    gear_drop_from_mob
    mov     edx, [rbx + MOB.level]
    add     edx, 20
    jmp     .coins
.leader:
    mov     eax, [rbx + MOB.level]
    xor     edx, edx
    mov     ecx, 5
    div     ecx
    lea     edx, [rax + 5]
.coins:
    mov     rdi, rbx
    call    mob_coins
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- names ------------------------------------------------------------------------------------

; folk_name(rdi mob, rsi out) -> rax the end of the name written at out (no NUL): a champion its own
; name; the Villagers' leader "Elder" and trader "Merchant"; another leader "<Member> Chief", trader
; "<Member> Trader", a fighter "<Member> <Class>", a worker "<Member> Worker", a captive "Captive
; <Member>", a traveller "Travelling <Member>" (Member: Villager, Bandit, Cultist, Beastkin, Stonekin)
; rbx = the mob, r12 = the end of the line, r13d = the faction
folk_name:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    movzx   r13d, byte [rbx + MOB.faction]
    cmp     r13d, NUM_FACTIONS
    jb      .known
    xor     r13d, r13d
.known:
    movzx   eax, byte [rbx + MOB.role]
    cmp     eax, ROLE_CHAMPION
    je      .champion
    cmp     eax, ROLE_LEADER
    je      .leader
    cmp     eax, ROLE_TRADER
    je      .trader
    cmp     eax, ROLE_GUARD
    je      .fighter
    cmp     eax, ROLE_PATROL
    je      .fighter
    cmp     eax, ROLE_WORKER
    je      .worker
    cmp     eax, ROLE_CAPTIVE
    je      .captive
    cmp     eax, ROLE_TRAVELLER
    je      .traveller
    jmp     .member
.champion:
    lea     rcx, [champion_names]
    mov     rsi, [rcx + r13*8]
    mov     rdi, r12
    call    str_append
    mov     r12, rax
    jmp     .done
.leader:
    test    r13d, r13d
    jnz     .chief
    APPEND  s_elder
    jmp     .done
.chief:
    call    folk_member
    APPEND  s_chief
    jmp     .done
.trader:
    test    r13d, r13d
    jnz     .shop
    APPEND  s_merchant
    jmp     .done
.shop:
    call    folk_member
    APPEND  s_trader
    jmp     .done
.fighter:
    call    folk_member
    movzx   eax, byte [rbx + MOB.fclass]
    cmp     eax, NUM_FCLASSES
    jae     .done
    test    eax, eax
    jz      .done
    APPEND  s_space
    movzx   eax, byte [rbx + MOB.fclass]    ; (str_append clobbered rax)
    lea     rcx, [class_names]
    mov     rsi, [rcx + rax*8]
    mov     rdi, r12
    call    str_append
    mov     r12, rax
    jmp     .done
.worker:
    call    folk_member
    APPEND  s_worker
    jmp     .done
.captive:
    APPEND  s_captive
    jmp     .member
.traveller:
    APPEND  s_travelling
.member:
    call    folk_member
.done:
    mov     rax, r12
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_member(): the member word of faction r13d goes on at r12 (folk_name's registers); r12 moves past it
folk_member:
    sub     rsp, 8
    lea     rcx, [faction_members]
    mov     rsi, [rcx + r13*8]
    mov     rdi, r12
    call    str_append
    mov     r12, rax
    add     rsp, 8
    ret

; ---- AI ---------------------------------------------------------------------------------------

; folk_ai(rdi mob) -> eax what mob_ai does with this folk's step: 0 its input and heading are set,
; 1 they are set and the heading is on purpose (hunting, patrolling, walking home, running away: it
; halts at a shore instead of turning about), 2 the shared wander. The provoked and greeting timers
; count down; a fighter goes to folk_fight, anyone else to folk_npc.
folk_ai:
    push    rbx
    mov     rbx, rdi
    cmp     dword [rbx + MOB.provoked], 0
    jle     .calm
    dec     dword [rbx + MOB.provoked]
.calm:
    cmp     dword [rbx + MOB.greet], 0
    jle     .roles
    dec     dword [rbx + MOB.greet]
.roles:
    call    folk_is_fighter
    mov     rdi, rbx
    test    eax, eax
    jz      .npc
    call    folk_fight
    jmp     .ret
.npc:
    call    folk_npc
.ret:
    pop     rbx
    ret

; folk_npc(rdi mob) -> eax as folk_ai: a leader, trader, worker, traveller or captive. It walks at
; the pace of folk_base_speed. A traveller whose time is up (timer_a) and who stands more than 24
; blocks from the player is gone. A captive stands and turns to a player within 4. A scared one
; (MOB.panic) runs from the player (target 1) or straight on at 1.5 x its speed. Otherwise: the 0.9
; rule, it walks home from beyond 6 blocks, turns to a player within 4 and else wanders.
; Frame: [rsp] to the player dx, dz, distance^2; [rsp+12] to home dx, dz, distance^2
folk_npc:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 40
    mov     rbx, rdi
    call    folk_base_speed
    movss   [rbx + BODY.speed], xmm0
    mov     rdi, rbx
    call    folk_player_body            ; the player it looks at: the nearest one online
    movss   xmm0, [rax + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm1, [rax + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    movss   [rsp + 4], xmm1
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   [rsp + 8], xmm0
    cmp     byte [rbx + MOB.role], ROLE_TRAVELLER
    jne     .roles
    cmp     dword [rbx + MOB.timer_a], 0
    jg      .roles
    comiss  xmm0, [c_lose2]
    jbe     .roles
    mov     dword [rbx + MOB.type], MOB_NONE    ; its time is up and nobody watches: it moves on
    xor     eax, eax
    jmp     .ret
.roles:
    cmp     byte [rbx + MOB.role], ROLE_CAPTIVE
    jne     .free
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    comiss  xmm0, [c_talk2]
    jb      .face
    xor     eax, eax
    jmp     .ret
.free:
    cmp     dword [rbx + MOB.panic], 0
    jle     .calm
    dec     dword [rbx + MOB.panic]
    cmp     dword [rbx + MOB.target], 1
    jne     .run
    xorps   xmm0, xmm0
    subss   xmm0, [rsp]                 ; away from the player
    xorps   xmm1, xmm1
    subss   xmm1, [rsp + 4]
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
.run:
    movss   xmm0, [rbx + BODY.speed]
    mulss   xmm0, [c_flee]
    movss   [rbx + BODY.speed], xmm0
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    mov     dword [rbx + MOB.ai_timer], 0
    mov     eax, 1
    jmp     .ret
.calm:
    movss   xmm0, [rbx + MOB.home_x]
    subss   xmm0, [rbx + BODY.x]
    movss   [rsp + 12], xmm0
    movss   xmm1, [rbx + MOB.home_z]
    subss   xmm1, [rbx + BODY.z]
    movss   [rsp + 16], xmm1
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_home2]
    jbe     .at_home
    movss   xmm0, [rsp + 12]
    movss   xmm1, [rsp + 16]
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    mov     dword [rbx + MOB.ai_timer], 0
    mov     eax, 1
    jmp     .ret
.at_home:
    movss   xmm0, [rsp + 8]
    comiss  xmm0, [c_talk2]
    jae     .wander
.face:
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    mov     dword [rbx + MOB.ai_timer], 0
    xor     eax, eax
    jmp     .ret
.wander:
    mov     eax, 2
.ret:
    add     rsp, 40
    pop     rbx
    pop     rbp
    ret

; folk_find_target(rdi mob) -> eax the nearest enemy within 16 blocks (3 dimensions): 1 for the
; player when this fighter wants him for one (folk_wants_player), 2 + slot for a folk of a rival
; faction that is no captive; 0 for none.
; rbx = the mob, r12 = the folk looked at, r13d = its slot; frame: [rsp] best distance^2, [rsp+4] best code
folk_find_target:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     eax, [c_see2]
    mov     [rsp], eax                  ; only an enemy nearer than 16 blocks counts
    mov     dword [rsp + 4], 0
    cmp     byte [net_role], NET_ROLE_OFF
    je      .wants_local
    mov     rdi, rbx
    call    folk_wants_any              ; online: any player will do, the nearest one who lives and is not hidden
    test    eax, eax
    jz      .mobs
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    mov     edi, 1
    call    net_nearest_target          ; rax = his body or 0, edx = his peer slot
    test    rax, rax
    jz      .mobs
    mov     [mob_tgt_slot], edx         ; (folk_fight makes it the folk's peer when the player is the target)
    movss   xmm0, [rax + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [rax + BODY.y]
    subss   xmm1, [rbx + BODY.y]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rax + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [rsp]
    jae     .mobs
    movss   [rsp], xmm0
    mov     dword [rsp + 4], 1
    jmp     .mobs
.wants_local:
    call    folk_wants_player
    test    eax, eax
    jz      .mobs
    movss   xmm0, [player + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [player + BODY.y]
    subss   xmm1, [rbx + BODY.y]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [player + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [rsp]
    jae     .mobs
    movss   [rsp], xmm0
    mov     dword [rsp + 4], 1
.mobs:
    lea     r12, [mobs]
    xor     r13d, r13d
.loop:
    cmp     dword [r12 + MOB.type], MOB_FOLK
    jne     .next
    cmp     r12, rbx
    je      .next
    cmp     byte [r12 + MOB.role], ROLE_CAPTIVE
    je      .next
    movzx   edi, byte [rbx + MOB.faction]
    movzx   esi, byte [r12 + MOB.faction]
    call    faction_enemies
    test    eax, eax
    jz      .next
    movss   xmm0, [r12 + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [r12 + BODY.y]
    subss   xmm1, [rbx + BODY.y]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [r12 + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [rsp]
    jae     .next
    movss   [rsp], xmm0
    lea     eax, [r13 + 2]
    mov     [rsp + 4], eax
.next:
    add     r12, MOB_size
    inc     r13d
    cmp     r13d, MAX_MOBS
    jb      .loop
    mov     eax, [rsp + 4]
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_target_at(rdi mob, rsi out float[3]) -> eax 1 and out = the feet of the mob's target when
; that target still counts: the player while folk_wants_player says so, another mob while it is a
; folk of an enemy faction and no captive; and it stands within 24 blocks (horizontally). 0, out
; untouched, otherwise.
; rbx = the mob, r12 = out, r13 = the BODY looked at
folk_target_at:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     eax, [rbx + MOB.target]
    cmp     eax, 1
    je      .player
    sub     eax, 2
    cmp     eax, MAX_MOBS
    jae     .none                       ; no target (0 wraps round to a huge slot) or a bad one
    imul    eax, eax, MOB_size
    lea     r13, [mobs]
    add     r13, rax
    cmp     dword [r13 + MOB.type], MOB_FOLK
    jne     .none
    cmp     byte [r13 + MOB.role], ROLE_CAPTIVE
    je      .none
    movzx   edi, byte [rbx + MOB.faction]
    movzx   esi, byte [r13 + MOB.faction]
    call    faction_enemies
    test    eax, eax
    jz      .none
    jmp     .measure
.player:
    cmp     byte [net_role], NET_ROLE_OFF
    je      .player_local
    mov     rdi, rbx
    call    folk_player_body            ; online: the player it is after (or the nearest), while it still wants him
    mov     r13, rax
    mov     [mob_tgt_body], rax         ; a blow on him lands on this body and peer slot
    mov     [mob_tgt_slot], edx
    mov     rdi, rbx
    mov     esi, edx
    call    folk_wants_slot
    test    eax, eax
    jz      .none
    jmp     .measure
.player_local:
    mov     rdi, rbx
    call    folk_wants_player
    test    eax, eax
    jz      .none
    lea     r13, [player]
.measure:
    movss   xmm0, [r13 + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [r13 + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_lose2]
    jae     .none
    mov     eax, [r13 + BODY.x]
    mov     [r12], eax
    mov     eax, [r13 + BODY.y]
    mov     [r12 + 4], eax
    mov     eax, [r13 + BODY.z]
    mov     [r12 + 8], eax
    mov     eax, 1
    jmp     .ret
.none:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_greet(rdi mob): "<Member>: Well met, friend" (green). Frame: [rsp] the line (64 bytes + 8 padding).
folk_greet:
    push    rbp
    mov     rbp, rsp
    push    r12
    sub     rsp, 72
    movzx   eax, byte [rdi + MOB.faction]
    cmp     eax, NUM_FACTIONS
    jae     .ret
    lea     r12, [rsp]
    lea     rcx, [faction_members]
    mov     rsi, [rcx + rax*8]
    mov     rdi, r12
    call    str_append
    mov     r12, rax
    APPEND  s_well_met
    BANNER  COL_GREEN
.ret:
    add     rsp, 72
    pop     r12
    pop     rbp
    ret

; folk_idle(rdi mob) -> eax as folk_ai: a fighter with nothing to fight. A patrol walks its road: to
; dest, and within 6 blocks of it (or after 120 stuck steps in a row, counted in ai_timer: it ran into
; something, or mob_ai stopped it at the water and left its forward input 0) dest and home trade
; places and it walks back. A guard or champion walks home from beyond 6 blocks, turns to a player
; within 4 (a GUARD of a Friendly or Allied faction greets him, once in 1200 steps) and otherwise
; wanders.
; Frame: [rsp] dx, dz, distance^2
folk_idle:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 24
    mov     rbx, rdi
    cmp     byte [rbx + MOB.role], ROLE_PATROL
    jne     .guard
    cmp     dword [rbx + BODY.blocked], 0
    jne     .stuck
    cmp     dword [rbx + MOB.input + INPUT.fwd], 0
    jne     .free                       ; (it sets 1 every step it walks)
.stuck:
    inc     dword [rbx + MOB.ai_timer]
    cmp     dword [rbx + MOB.ai_timer], PATROL_STUCK
    jb      .steer
    call    folk_swap_ends
    jmp     .steer
.free:
    mov     dword [rbx + MOB.ai_timer], 0
.steer:
    movss   xmm0, [rbx + MOB.dest_x]
    subss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + MOB.dest_z]
    subss   xmm1, [rbx + BODY.z]
    movaps  xmm2, xmm0
    mulss   xmm2, xmm2
    movaps  xmm3, xmm1
    mulss   xmm3, xmm3
    addss   xmm2, xmm3
    comiss  xmm2, [c_home2]
    ja      .walk
    call    folk_swap_ends              ; at the end of its road: back the other way
    movss   xmm0, [rbx + MOB.dest_x]
    subss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + MOB.dest_z]
    subss   xmm1, [rbx + BODY.z]
.walk:
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    mov     eax, 1
    jmp     .ret
.guard:
    movss   xmm0, [rbx + MOB.home_x]
    subss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm1, [rbx + MOB.home_z]
    subss   xmm1, [rbx + BODY.z]
    movss   [rsp + 4], xmm1
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_home2]
    jbe     .at_home
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    mov     dword [rbx + MOB.ai_timer], 0
    mov     eax, 1
    jmp     .ret
.at_home:
    mov     rdi, rbx
    call    folk_player_body            ; the player it turns to: the nearest one online
    movss   xmm0, [rax + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm1, [rax + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    movss   [rsp + 4], xmm1
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_talk2]
    jae     .wander
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    mov     dword [rbx + MOB.ai_timer], 0
    cmp     byte [rbx + MOB.role], ROLE_GUARD
    jne     .faced
    cmp     dword [rbx + MOB.greet], 0
    jg      .faced
    movzx   edi, byte [rbx + MOB.faction]
    call    faction_tier
    cmp     eax, TIER_FRIENDLY
    jb      .faced
    mov     dword [rbx + MOB.greet], GREET_STEPS
    mov     rdi, rbx
    call    folk_greet
.faced:
    xor     eax, eax
    jmp     .ret
.wander:
    mov     eax, 2
.ret:
    add     rsp, 24
    pop     rbx
    pop     rbp
    ret

; folk_swap_ends(): a patrol (rbx) turns round: dest and home trade places, the blocked count restarts
folk_swap_ends:
    mov     eax, [rbx + MOB.dest_x]
    mov     ecx, [rbx + MOB.home_x]
    mov     [rbx + MOB.dest_x], ecx
    mov     [rbx + MOB.home_x], eax
    mov     eax, [rbx + MOB.dest_z]
    mov     ecx, [rbx + MOB.home_z]
    mov     [rbx + MOB.dest_z], ecx
    mov     [rbx + MOB.home_z], eax
    mov     dword [rbx + MOB.ai_timer], 0
    ret

; folk_shoot(rdi mob, rsi target float[3]) -> eax 1 when it shot: the fighter looses an arrow (an
; archer) or a magic bolt (an acolyte) from its eye, 0.6 blocks along the aim, unless a block stands
; between that eye and the aim point: the player's eye for an archer shooting at the player, else 1
; block above the target's feet. An arrow flies at 24 blocks/s lifted against gravity and scattered by the
; difficulty (at the player) or by 0.5 (at another folk); a bolt flies straight at 18. The damage is
; mob_blow of folk_base_d (at the player) or folk_base (at a folk), the flags carry the element of
; its affix, the owner is OWNER_FOLK + its faction. Then it reloads: an archer 50 + rng % 30 steps,
; an acolyte 60 + rng % 20.
; rbx = the mob, r12 = the target; frame: eye o[3] @0, aim p[3] @12, unit dir[3] @24, distance @36,
; RAYHIT scratch @40, damage @64, difficulty @68, velocity[3] @72, kind @84
folk_shoot:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 96
    mov     rbx, rdi
    mov     r12, rsi
    movss   xmm0, [rbx + BODY.x]
    movss   [rsp], xmm0
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [c_eye]
    movss   [rsp + 4], xmm0
    movss   xmm0, [rbx + BODY.z]
    movss   [rsp + 8], xmm0
    cmp     dword [rbx + MOB.target], 1
    jne     .centre
    cmp     byte [rbx + MOB.fclass], FCLASS_ARCHER
    jne     .centre
    mov     rdi, rbx
    call    folk_player_body            ; the eye of the player it shoots at: feet + 1.62 up
    mov     ecx, [rax + BODY.x]
    mov     [rsp + 12], ecx
    movss   xmm0, [rax + BODY.y]
    addss   xmm0, [c_eye]
    movss   [rsp + 16], xmm0
    mov     ecx, [rax + BODY.z]
    mov     [rsp + 20], ecx
    jmp     .aimed
.centre:
    movss   xmm0, [r12]
    movss   [rsp + 12], xmm0
    movss   xmm0, [r12 + 4]
    addss   xmm0, [c_aim_up]
    movss   [rsp + 16], xmm0
    movss   xmm0, [r12 + 8]
    movss   [rsp + 20], xmm0
.aimed:
    xor     ecx, ecx
.aim:
    movss   xmm0, [rsp + 12 + rcx*4]
    subss   xmm0, [rsp + rcx*4]
    movss   [rsp + 24 + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 3
    jb      .aim
    movss   xmm0, [rsp + 24]
    mulss   xmm0, xmm0
    movss   xmm1, [rsp + 28]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   xmm1, [rsp + 32]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    sqrtss  xmm0, xmm0
    comiss  xmm0, [c_tiny]
    jb      .no                         ; eye on the aim point: no direction to shoot along
    movss   [rsp + 36], xmm0
    xor     ecx, ecx
.unit:
    movss   xmm1, [rsp + 24 + rcx*4]
    divss   xmm1, xmm0
    movss   [rsp + 24 + rcx*4], xmm1
    inc     ecx
    cmp     ecx, 3
    jb      .unit
    lea     rdi, [rsp]                  ; line of sight: no block between the eye and the aim point
    lea     rsi, [rsp + 24]
    lea     rdx, [rsp + 40]
    movss   xmm0, [rsp + 36]
    call    raycast
    test    eax, eax
    jnz     .no
    mov     eax, [settings + SETTINGS.difficulty]
    mov     ecx, DIFF_HARD
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [rsp + 68], eax
    mov     rdi, rbx
    cmp     dword [rbx + MOB.target], 1
    jne     .folk_base
    call    folk_base_d                 ; against the player: the difficulty's share of it
    jmp     .base
.folk_base:
    call    folk_base
.base:
    mov     esi, eax
    mov     rdi, rbx
    xor     edx, edx
    call    mob_blow                    ; level, elite state and the affix parts
    mov     [rsp + 64], eax
    cmp     byte [rbx + MOB.fclass], FCLASS_ACOLYTE
    je      .bolt
    mov     dword [rsp + 84], PROJ_ARROW
    movss   xmm4, [c_folk_spread]       ; the aim error: (rng % 201 - 100) / 100 x the spread, per axis
    cmp     dword [rbx + MOB.target], 1
    jne     .spread
    mov     eax, [rsp + 68]
    movss   xmm4, [c_spread + rax*4]
.spread:
    movss   [rsp + 72], xmm4            ; (kept in the velocity slot while the rng runs)
    call    rng_next
    xor     edx, edx
    mov     ecx, 201
    div     ecx
    sub     edx, 100
    cvtsi2ss xmm0, edx
    mulss   xmm0, [c_cent]
    mulss   xmm0, [rsp + 72]
    movss   [rsp + 76], xmm0
    call    rng_next
    xor     edx, edx
    mov     ecx, 201
    div     ecx
    sub     edx, 100
    cvtsi2ss xmm0, edx
    mulss   xmm0, [c_cent]
    mulss   xmm0, [rsp + 72]
    movss   [rsp + 80], xmm0            ; z error, x error at [rsp + 76]
    movss   xmm0, [rsp + 36]            ; flight time dist / 24: lift 10 t against gravity
    divss   xmm0, [c_arrow_v]
    mulss   xmm0, [c_lift]
    movss   xmm1, [rsp + 28]
    mulss   xmm1, [c_arrow_v]
    addss   xmm1, xmm0                  ; vy
    movss   xmm2, [rsp + 24]
    mulss   xmm2, [c_arrow_v]
    addss   xmm2, [rsp + 76]            ; vx
    movss   xmm3, [rsp + 32]
    mulss   xmm3, [c_arrow_v]
    addss   xmm3, [rsp + 80]            ; vz
    movss   [rsp + 72], xmm2
    movss   [rsp + 76], xmm1
    movss   [rsp + 80], xmm3
    call    rng_next
    xor     edx, edx
    mov     ecx, 30
    div     ecx
    add     edx, 50
    jmp     .loose
.bolt:
    mov     dword [rsp + 84], PROJ_BOLT
    xor     ecx, ecx
.bolt_v:
    movss   xmm0, [rsp + 24 + rcx*4]
    mulss   xmm0, [c_bolt_v]
    movss   [rsp + 72 + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 3
    jb      .bolt_v
    call    rng_next
    xor     edx, edx
    mov     ecx, 20
    div     ecx
    add     edx, 60
.loose:
    mov     [rbx + MOB.cooldown], edx
    movss   xmm0, [rsp + 24]            ; starts 0.6 blocks along the aim
    mulss   xmm0, [c_muzzle]
    addss   xmm0, [rsp]
    movss   xmm1, [rsp + 28]
    mulss   xmm1, [c_muzzle]
    addss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 32]
    mulss   xmm2, [c_muzzle]
    addss   xmm2, [rsp + 8]
    movss   xmm3, [rsp + 72]
    movss   xmm4, [rsp + 76]
    movss   xmm5, [rsp + 80]
    mov     rdi, rbx
    call    mob_arrow_flags             ; touches only eax and ecx
    mov     r8d, eax
    movzx   edi, byte [rbx + MOB.faction]
    add     edi, OWNER_FOLK
    mov     esi, [rsp + 64]
    xor     edx, edx                    ; cannot be picked up
    mov     ecx, [rsp + 84]
    call    arrows_spawn
    mov     edi, SND_BOW
    cmp     dword [rsp + 84], PROJ_BOLT
    jne     .sound
    mov     edi, SND_SPELL
.sound:
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_vol]
    call    audio_play_at
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 96
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_fight(rdi mob) -> eax as folk_ai: a GUARD, CHAMPION or PATROL.
; A sleeping champion stands still, never targets and wakes when its faction's standing is Hated; a
; berserker below half its health rages (speed x 1.3, quicker blows). Every 20 steps (MOB.timer_b) it
; looks for the nearest enemy (folk_find_target); the target is dropped (and looked for again at
; once) when folk_target_at says it no longer counts. With a target it faces it and fights as its
; class: a brute or berserker walks up, raises its weapon for 28 (12) steps and hits a target still
; within 2.4 blocks and 1.5 up or down (the player through mob_melee_hit with knockback, a folk
; through folk_strike_mob), then rests for 70 (30) steps; an archer keeps 6..12 blocks and an acolyte
; 5..10, shooting through folk_shoot within 15. Without one it is folk_idle.
; rbx = the mob, r12d = a melee folk's wind-up; frame: FT_*
folk_fight:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, FT_FRAME
    mov     rbx, rdi
    test    byte [rbx + MOB.fflags], FF_ASLEEP
    jz      .awake
    movzx   edi, byte [rbx + MOB.faction]
    call    faction_tier
    cmp     eax, TIER_HATED
    jne     .sleep
    mov     rdi, rbx
    call    folk_wake
    jmp     .awake
.sleep:
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    mov     dword [rbx + MOB.target], 0
    mov     dword [rbx + MOB.windup], 0
    xor     eax, eax
    jmp     .ret
.awake:
    cmp     byte [rbx + MOB.fclass], FCLASS_BERSERKER
    jne     .look
    test    byte [rbx + MOB.fflags], FF_RAGE
    jnz     .look
    mov     eax, [rbx + MOB.health]
    add     eax, eax
    cmp     eax, [rbx + MOB.max_health]
    jge     .look
    or      byte [rbx + MOB.fflags], FF_RAGE    ; below half its health
    movss   xmm0, [rbx + BODY.speed]
    mulss   xmm0, [c_rage]
    movss   [rbx + BODY.speed], xmm0
.look:
    cmp     dword [rbx + MOB.timer_b], 0
    jg      .check
    mov     rdi, rbx
    call    folk_find_target
    test    eax, eax
    jz      .seen                       ; nobody within 16: the current target stays until it leaves 24
    cmp     eax, 1
    jne     .retarget
    cmp     byte [net_role], NET_ROLE_OFF
    je      .retarget
    mov     ecx, [mob_tgt_slot]         ; the nearest player: his slot is the folk's peer from now on
    mov     [rbx + MOB.peer], ecx
.retarget:
    cmp     eax, [rbx + MOB.target]
    je      .seen
    mov     [rbx + MOB.target], eax
    mov     dword [rbx + MOB.windup], 0
.seen:
    mov     dword [rbx + MOB.timer_b], SEE_STEPS
.check:
    mov     rdi, rbx
    lea     rsi, [rsp + FT_TX]
    call    folk_target_at
    test    eax, eax
    jnz     .engage
    cmp     dword [rbx + MOB.target], 0
    je      .alone
    mov     dword [rbx + MOB.target], 0         ; it died, got away or stopped being an enemy
    mov     dword [rbx + MOB.windup], 0
    mov     dword [rbx + MOB.timer_b], 0        ; look again at once
.alone:
    mov     rdi, rbx
    call    folk_idle
    jmp     .ret
.engage:
    movss   xmm0, [rsp + FT_TX]
    subss   xmm0, [rbx + BODY.x]
    movss   [rsp + FT_DX], xmm0
    movss   xmm1, [rsp + FT_TX + 8]
    subss   xmm1, [rbx + BODY.z]
    movss   [rsp + FT_DZ], xmm1
    movss   xmm2, [rsp + FT_TX + 4]
    subss   xmm2, [rbx + BODY.y]
    movss   [rsp + FT_DY], xmm2
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    movss   [rsp + FT_D2], xmm0
    movss   xmm0, [rsp + FT_DX]
    movss   xmm1, [rsp + FT_DZ]
    call    yaw_from
    movss   [rbx + BODY.yaw], xmm0
    movzx   eax, byte [rbx + MOB.fclass]
    cmp     eax, FCLASS_ARCHER
    je      .archer
    cmp     eax, FCLASS_ACOLYTE
    je      .acolyte
    cmp     eax, FCLASS_BRUTE
    je      .melee
    cmp     eax, FCLASS_BERSERKER
    je      .melee
    mov     dword [rbx + MOB.input + INPUT.fwd], 0  ; no class, no attack: it only faces its enemy
    jmp     .fighting
.archer:
    movss   xmm1, [c_arch_near2]
    movss   xmm2, [c_arch_far2]
    jmp     .ranged
.acolyte:
    movss   xmm1, [c_aco_near2]
    movss   xmm2, [c_aco_far2]
.ranged:
    movss   xmm0, [rsp + FT_D2]
    xor     eax, eax
    comiss  xmm0, xmm2
    ja      .close_in                   ; beyond its range: closes in
    comiss  xmm0, xmm1
    jae     .keep
    mov     eax, -1                     ; too close: backs off, still facing the target
    jmp     .keep
.close_in:
    mov     eax, 1
.keep:
    mov     [rbx + MOB.input + INPUT.fwd], eax
    cmp     dword [rbx + MOB.cooldown], 0
    jne     .fighting
    comiss  xmm0, [c_shoot2]
    jae     .fighting
    mov     rdi, rbx
    lea     rsi, [rsp + FT_TX]
    call    folk_shoot
    jmp     .fighting
.melee:
    movzx   ecx, byte [rbx + MOB.fclass]
    mov     r12d, [fc_windup + rcx*4]
    mov     eax, [fc_cool + rcx*4]
    test    byte [rbx + MOB.fflags], FF_RAGE
    jz      .m_go
    mov     r12d, RAGE_WINDUP
    mov     eax, RAGE_COOLDOWN
.m_go:
    mov     [rsp + FT_COOL], eax
    cmp     dword [rbx + MOB.windup], 0
    jg      .winding
    mov     dword [rbx + MOB.input + INPUT.fwd], 1
    movss   xmm0, [rsp + FT_D2]
    comiss  xmm0, [c_reach2]
    jae     .closing
    mov     dword [rbx + MOB.input + INPUT.fwd], 0  ; at arm's length it stops rather than walk into him
.closing:
    cmp     dword [rbx + MOB.cooldown], 0
    jne     .fighting
    comiss  xmm0, [c_reach2]
    jae     .fighting                   ; not in reach yet
    movss   xmm1, [rsp + FT_DY]
    mulss   xmm1, xmm1
    comiss  xmm1, [c_reach_y2]
    jae     .fighting                   ; above or below its reach
    mov     [rbx + MOB.windup], r12d    ; the weapon goes up, and the folk stands to swing
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    jmp     .fighting
.winding:
    mov     dword [rbx + MOB.input + INPUT.fwd], 0
    dec     dword [rbx + MOB.windup]
    jnz     .fighting                   ; the weapon is still up
    movss   xmm1, [rsp + FT_DY]         ; the blow lands only on a target still within reach
    mulss   xmm1, xmm1
    comiss  xmm1, [c_reach_y2]
    jae     .whiff
    addss   xmm1, [rsp + FT_D2]
    comiss  xmm1, [c_strike2]
    ja      .whiff
    cmp     dword [rbx + MOB.target], 1
    jne     .at_folk
    mov     rdi, rbx
    call    folk_base_d
    mov     esi, eax
    mov     rdi, rbx
    movzx   edx, byte [rbx + MOB.faction]
    add     edx, CAUSE_FOLK
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.z]
    movzx   ecx, byte [rbx + MOB.fclass]
    movss   xmm2, [c_kb]
    mulss   xmm2, [fc_kb + rcx*4]
    call    mob_melee_hit
    cmp     eax, HIT_PARRIED
    je      .parried
    cmp     eax, HIT_TAKEN
    jne     .blow_done                  ; blocked or dodged: no knockback
    movzx   ecx, byte [rbx + MOB.fclass]
    movss   xmm3, [c_kb]
    mulss   xmm3, [fc_kb + rcx*4]
    lea     rsi, [rsp + FT_DX]          ; knock the player back along folk -> player
    call    knock_player
    jmp     .blow_done
.parried:                               ; the riposte stuns it: it reels back and stands dazed
    test    byte [rbx + MOB.affix], AFX_JUGGERNAUT
    jnz     .blow_done                  ; a juggernaut shrugs the riposte off
    mov     dword [rbx + MOB.stun], STUN_PARRIED
    mov     rdi, rbx
    lea     rsi, [rsp + FT_DX]
    call    mob_reel
    mov     rdi, rbx
    call    mob_stunned_text
    jmp     .blow_done
.at_folk:
    mov     rdi, rbx
    call    folk_base
    mov     edx, eax
    mov     esi, [rbx + MOB.target]
    sub     esi, 2
    mov     rdi, rbx
    call    folk_strike_mob
.blow_done:
    mov     eax, [rsp + FT_COOL]
    mov     [rbx + MOB.cooldown], eax
    jmp     .fighting
.whiff:                                 ; the target got away: it recovers sooner
    mov     dword [rbx + MOB.cooldown], WHIFF_COOLDOWN
.fighting:
    mov     eax, 1
.ret:
    add     rsp, FT_FRAME
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- right-click ------------------------------------------------------------------------------

; folk_interact(edi slot) -> eax the ST_* screen a right-click on that folk opens, or 0 (and a banner
; saying why): a leader at standing 0 or better opens the elder's dialog (Villagers) or the leader
; screen (the others, screen_faction = its faction), else "<Faction> leader won't speak with you"; a
; trader at Friendly or better the trade screen (trade_open, screen_faction), a traveller at 0 or better,
; else "<Faction> won't trade with you yet"; a captive, unless an awake fighter of its captor stands
; within 12 blocks ("Its guards are watching"), is freed: +25 with its faction, its camp's record
; marked (structures_mark_freed), "Freed a <Member> captive (+25)", the folk leaves in a burst of
; magic. Anyone else, an empty slot or a bad one: 0.
; rbx = the folk, r12d = its faction; frame: [rsp] the banner line
folk_interact:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 64
    xor     eax, eax
    cmp     edi, MAX_MOBS
    jae     .ret
    imul    ecx, edi, MOB_size
    lea     rbx, [mobs]
    add     rbx, rcx
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .ret
    movzx   r12d, byte [rbx + MOB.faction]
    cmp     r12d, NUM_FACTIONS
    jae     .ret
    movzx   eax, byte [rbx + MOB.role]
    cmp     eax, ROLE_LEADER
    je      .leader
    cmp     eax, ROLE_TRADER
    je      .trader
    cmp     eax, ROLE_TRAVELLER
    je      .traveller
    cmp     eax, ROLE_CAPTIVE
    je      .captive
    xor     eax, eax
    jmp     .ret
.leader:
    mov     edi, r12d
    call    faction_standing
    test    eax, eax
    js      .leader_no
    test    r12d, r12d
    jnz     .leader_screen
    mov     eax, ST_DIALOG
    jmp     .ret
.leader_screen:
    mov     [screen_faction], r12d
    mov     eax, ST_LEADER
    jmp     .ret
.leader_no:
    lea     rdi, [rsp]
    lea     rcx, [faction_names]
    mov     rsi, [rcx + r12*8]
    call    str_append
    mov     r12, rax
    APPEND  s_no_speak
    BANNER  COL_RED
    xor     eax, eax
    jmp     .ret
.trader:
    mov     edi, r12d
    call    faction_tier
    cmp     eax, TIER_FRIENDLY
    jae     .shop
    jmp     .shop_no
.traveller:
    mov     edi, r12d
    call    faction_standing
    test    eax, eax
    js      .shop_no
.shop:
    mov     edi, r12d
    call    trade_open
    mov     [screen_faction], r12d
    mov     eax, ST_TRADE
    jmp     .ret
.shop_no:
    lea     rdi, [rsp]
    lea     rcx, [faction_names]
    mov     rsi, [rcx + r12*8]
    call    str_append
    mov     r12, rax
    APPEND  s_no_trade
    BANNER  COL_RED
    xor     eax, eax
    jmp     .ret
.captive:
    lea     rdx, [mobs]
    mov     ecx, MAX_MOBS
    movzx   r8d, byte [rbx + MOB.captor]
.watch:
    cmp     dword [rdx + MOB.type], MOB_FOLK
    jne     .w_next
    cmp     [rdx + MOB.faction], r8b
    jne     .w_next
    test    byte [rdx + MOB.fflags], FF_ASLEEP
    jnz     .w_next
    movzx   eax, byte [rdx + MOB.role]
    cmp     eax, ROLE_GUARD
    je      .w_fighter
    cmp     eax, ROLE_PATROL
    je      .w_fighter
    cmp     eax, ROLE_CHAMPION
    jne     .w_next
.w_fighter:
    movss   xmm0, [rdx + BODY.x]
    subss   xmm0, [rbx + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [rdx + BODY.z]
    subss   xmm1, [rbx + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_watch2]
    jb      .watched
.w_next:
    add     rdx, MOB_size
    dec     ecx
    jnz     .watch
    mov     rdi, rbx
    call    mob_index
    mov     edi, eax                    ; its slot
    cmp     byte [net_role], NET_ROLE_GUEST
    jne     .free_here
    mov     esi, IA_FREE_CAPTIVE        ; a guest asks the host to free it ...
    call    net_interact_out
    mov     dword [rbx + MOB.type], MOB_NONE    ; ... and sees it leave at once
    jmp     .freed
.free_here:
    call    folk_free_captive           ; +25 with its faction, its camp's record marked, the folk gone
.freed:
    movss   xmm0, [rbx + BODY.x]
    movss   xmm1, [rbx + BODY.y]
    addss   xmm1, [c_aim_up]
    movss   xmm2, [rbx + BODY.z]
    movss   xmm3, [c_one]
    mov     edi, FX_MAGIC
    mov     esi, 12
    call    fx_burst
    lea     r12, [rsp]
    APPEND  s_freed_a
    lea     rcx, [faction_members]
    movzx   eax, byte [rbx + MOB.faction]
    mov     rsi, [rcx + rax*8]
    mov     rdi, r12
    call    str_append
    mov     r12, rax
    APPEND  s_freed_b
    BANNER  COL_GREEN
    xor     eax, eax
    jmp     .ret
.watched:
    lea     r12, [rsp]
    APPEND  s_watching
    BANNER  COL_RED
    xor     eax, eax
.ret:
    add     rsp, 64
    pop     r12
    pop     rbx
    pop     rbp
    ret

; folk_free_captive(edi idx): the world half of freeing a captive: the folk in that slot (a captive, else
; nothing happens) is freed: +25 with its faction, its camp's record marked (structures_mark_freed) and the
; folk gone (MOB_NONE). A right-click on a captive does the rest at the player's end (the burst and the banner);
; a guest's asks the host for this (IA_FREE_CAPTIVE).
folk_free_captive:
    push    rbx
    sub     rsp, 16
    cmp     edi, MAX_MOBS
    jae     .ret
    imul    eax, edi, MOB_size
    lea     rbx, [mobs]
    add     rbx, rax
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .ret
    cmp     byte [rbx + MOB.role], ROLE_CAPTIVE
    jne     .ret
    movzx   edi, byte [rbx + MOB.faction]
    cmp     edi, NUM_FACTIONS
    jae     .ret
    mov     esi, 25
    call    faction_add
    movss   xmm0, [rbx + BODY.x]
    roundss xmm0, xmm0, 9
    cvttss2si edi, xmm0
    movss   xmm0, [rbx + BODY.z]
    roundss xmm0, xmm0, 9
    cvttss2si esi, xmm0
    call    structures_mark_freed
    mov     dword [rbx + MOB.type], MOB_NONE
.ret:
    add     rsp, 16
    pop     rbx
    ret

; ---- the travelling trader --------------------------------------------------------------------

; folk_travel_tick(): once per fixed step (mobs_step). On the step that opens every 3rd hour-block of
; 3600 steps (game_time % 3600 == 0 and game_time / 3600 % 3 == 0), by day, with no traveller alive: a
; travelling trader (ROLE_TRAVELLER) appears 24..40 blocks from the player (spawn_near_player, up to
; 8 spots tried) and stays for 18000 steps (MOB.timer_a; folk_npc sends it away after that, once the
; player is more than 24 blocks off). Its faction is that of the nearest camp in sites[] when it lies
; within 512 blocks and the player's standing with it is 0 or better, else Stonekin. No rng decides
; whether it comes.
; r12d = the faction, r13d = the slot, ebx = tries left
folk_travel_tick:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     eax, [game_time]
    xor     edx, edx
    mov     ecx, TRAVEL_PERIOD
    div     ecx
    test    edx, edx
    jnz     .ret
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    test    edx, edx
    jnz     .ret
    mov     edi, [game_time]
    call    sky_is_night
    test    eax, eax
    jnz     .ret
    lea     rax, [mobs]
    mov     ecx, MAX_MOBS
.live:
    cmp     dword [rax + MOB.type], MOB_FOLK
    jne     .live_next
    cmp     byte [rax + MOB.role], ROLE_TRAVELLER
    je      .ret                        ; one at a time
.live_next:
    add     rax, MOB_size
    dec     ecx
    jnz     .live
    mov     r12d, FAC_STONEKIN
    mov     edi, SITE_CAMP
    xor     esi, esi
    call    structures_nearest
    test    rax, rax
    jz      .spawn
    cvtsi2ss xmm0, dword [rax + SITE.x]
    subss   xmm0, [player + BODY.x]
    mulss   xmm0, xmm0
    cvtsi2ss xmm1, dword [rax + SITE.z]
    subss   xmm1, [player + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_512_2]
    ja      .spawn
    mov     r13d, [rax + SITE.index]
    cmp     r13d, NUM_FACTIONS
    jae     .spawn
    mov     edi, r13d
    call    faction_standing
    test    eax, eax
    js      .spawn
    mov     r12d, r13d
.spawn:
    mov     ebx, TRAVEL_TRIES
.try:
    mov     edi, MOB_FOLK
    mov     esi, 24
    mov     edx, 17
    mov     ecx, GROUND_HOSTILE
    call    spawn_near_player
    test    eax, eax
    jns     .made
    dec     ebx
    jnz     .try
    jmp     .ret
.made:
    mov     r13d, eax
    mov     edi, eax
    mov     esi, r12d
    mov     edx, ROLE_TRAVELLER
    xor     ecx, ecx
    call    folk_init
    imul    eax, r13d, MOB_size
    lea     rcx, [mobs]
    mov     dword [rcx + rax + MOB.timer_a], TRAVEL_LIFE
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
