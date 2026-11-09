; test_folk.asm - faction folk (0.10): who they are (class, health, speed, weapon, element, name),
; who they fight (the player by standing and provocation, rival factions on sight), what killing one
; costs and drops, the arrows and bolts they loose, the right-click gates and the travelling trader.
%include "common.inc"
default rel

global test_folk_spawn_and_weapons, test_folk_targets_and_standing, test_folk_rivals_fight
global test_folk_kill_reputation_and_drops, test_folk_projectiles, test_folk_interact_gates
global test_folk_travellers

extern mobs, mobs_clear, mobs_step, mob_is_hostile, mob_strike
extern folk_spawn, folk_make_champion, folk_interact, folk_name, folk_weapon_affix, folk_travel_tick
extern folk_hit_by, folk_strike_mob, mob_blow_raw
extern arrows, arrows_clear, arrows_step, explode_magic
extern drops, drops_clear
extern player, body_init, rng_seed, world_clear, world_set
extern game_mode, game_time, settings, surv, survival_reset, inv_clear, rpg_reset
extern combat_reset, combat_hit_mob, combat_hit_flags, combat_burn_t, combat_guard_t
extern world_header, banner_text, screen_faction, sites, site_count, rpg_stats
extern faction_reset
extern gear_make, gear_affixes, item_legendary

section .rodata
align 4
k_half_w: dd 0.3
k_height: dd 1.8
k_speed:  dd 4.317
k_3_5:    dd 3.5
k_60_5:   dd 60.5
k_30:     dd 30.0
k_20:     dd 20.0
k_10:     dd 10.0
k_529:    dd 529.0                      ; 23 blocks, squared
k_1:      dd 1.0
k_3:      dd 3.0
k_3_85:   dd 3.85
k_112:    dd 112.0
k_116_5:  dd 116.5
k_1764:   dd 1764.0                     ; 42 blocks, squared
start_standing: dw 200, -100, -100, 0, 0
n_elder:            db "Elder", 0
n_merchant:         db "Merchant", 0
n_cult_chief:       db "Cultist Chief", 0
n_bandit_trader:    db "Bandit Trader", 0
n_beast_worker:     db "Beastkin Worker", 0
n_captive_villager: db "Captive Villager", 0
n_travelling_stone: db "Travelling Stonekin", 0
n_bandit_archer:    db "Bandit Archer", 0
n_cult_acolyte:     db "Cultist Acolyte", 0
n_beast_berserker:  db "Beastkin Berserker", 0
n_thane:            db "Thane Durgar", 0
n_bandit_brute:     db "Bandit Brute", 0
s_not_trade:        db "Bandits won't trade with you yet", 0
s_stone_no:         db "Stonekin won't trade with you yet", 0
s_no_speak:         db "Ashen Cult leader won't speak with you", 0
s_watching:         db "Its guards are watching", 0
s_freed:            db "Freed a Villager captive (+25)", 0
s_fallen:           db "Morvael the Ashen has fallen!", 0
s_wakes:            db "Morvael the Ashen wakes!", 0
s_well_met:         db "Villager: Well met, friend", 0
; the spawn table: faction, role, class, health, speed, weapon, name
%macro ROW 7
    dd %1, %2, %3, %4, %5, %6
    dq %7
%endmacro
%define SPAWN_ROWS 12
align 8
spawn_rows:
    ROW FAC_VILLAGERS, ROLE_LEADER,    FCLASS_NONE,      20, 2.0, 0,              n_elder
    ROW FAC_VILLAGERS, ROLE_TRADER,    FCLASS_NONE,      20, 2.0, 0,              n_merchant
    ROW FAC_CULT,      ROLE_LEADER,    FCLASS_NONE,      20, 2.0, 0,              n_cult_chief
    ROW FAC_BANDITS,   ROLE_TRADER,    FCLASS_NONE,      20, 2.0, 0,              n_bandit_trader
    ROW FAC_BEASTFOLK, ROLE_WORKER,    FCLASS_NONE,      20, 2.0, 0,              n_beast_worker
    ROW FAC_VILLAGERS, ROLE_CAPTIVE,   FCLASS_NONE,      20, 0.0, 0,              n_captive_villager
    ROW FAC_STONEKIN,  ROLE_TRAVELLER, FCLASS_NONE,      20, 2.0, 0,              n_travelling_stone
    ROW FAC_BANDITS,   ROLE_GUARD,     FCLASS_ARCHER,    18, 2.6, BOW,            n_bandit_archer
    ROW FAC_CULT,      ROLE_GUARD,     FCLASS_ACOLYTE,   16, 2.4, STAFF,          n_cult_acolyte
    ROW FAC_BEASTFOLK, ROLE_PATROL,    FCLASS_BERSERKER, 24, 3.0, IRON_SWORD,     n_beast_berserker
    ROW FAC_STONEKIN,  ROLE_CHAMPION,  FCLASS_BRUTE,     32, 2.2, IRON_HAMMER,    n_thane
    ROW FAC_BANDITS,   ROLE_GUARD,     FCLASS_BRUTE,     32, 2.2, IRON_HAMMER,    n_bandit_brute

section .text

; SETF mem, float literal
%macro SETF 2
    mov     dword %1, __float32__(%2)
%endmacro

; FOLK faction, role, class, x, z: folk_spawn of that folk standing at (x, 11, z) -> eax slot or -1
%macro FOLK 5
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     eax, __float32__(%4)
    movd    xmm0, eax
    mov     eax, __float32__(11.0)
    movd    xmm1, eax
    mov     eax, __float32__(%5)
    movd    xmm2, eax
    call    folk_spawn
%endmacro

; fixture(): the state every folk test starts from (after world_clear): rng seed 1234, no mobs,
; arrows, drops or inventory, a level-1 character without a class, fresh survival and combat state,
; the starting standings (Villagers 200, Bandits -100, Cult -100, Beastfolk 0, Stonekin 0), Survival at
; Normal difficulty in the morning, no banner, no cached sites, a STONE floor at y = 10 for x, z in
; 56..144 and the player standing at (100.5, 11, 100.5)
fixture:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     edi, 1234
    call    rng_seed
    call    mobs_clear
    call    arrows_clear
    call    drops_clear
    call    inv_clear
    call    rpg_reset
    call    survival_reset
    call    combat_reset
    call    faction_reset
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [game_time], NEW_WORLD_TIME
    mov     byte [banner_text], 0
    mov     dword [site_count], 0
    mov     r12d, 56                    ; z
.z:
    mov     ebx, 56                     ; x
.x:
    mov     edi, ebx
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 144
    jbe     .x
    inc     r12d
    cmp     r12d, 144
    jbe     .z
    lea     rdi, [player]
    movss   xmm0, [k_half_w]
    movss   xmm1, [k_height]
    movss   xmm2, [k_speed]
    call    body_init
    SETF    [player + BODY.x], 100.5
    SETF    [player + BODY.y], 11.0
    SETF    [player + BODY.z], 100.5
    pop     r12
    pop     rbx
    pop     rbp
    ret

; cleanup(): leave no mobs, arrows, drops, banner, burning, cached sites or standings changed behind
cleanup:
    sub     rsp, 8
    call    mobs_clear
    call    arrows_clear
    call    drops_clear
    call    inv_clear
    call    combat_reset
    call    faction_reset
    mov     dword [game_mode], MODE_SURVIVAL
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    mov     dword [game_time], NEW_WORLD_TIME
    mov     byte [banner_text], 0
    mov     dword [site_count], 0
    add     rsp, 8
    ret

; mob_ptr(edi idx) -> rax the mob in that slot
mob_ptr:
    imul    eax, edi, MOB_size
    lea     rcx, [mobs]
    add     rax, rcx
    ret

; set_standing(edi faction, esi standing): the standing in the world header
set_standing:
    lea     rcx, [world_header + WORLDHDR.standing]
    mov     [rcx + rdi*2], si
    ret

; standing(edi faction) -> eax the standing in the world header
standing:
    lea     rcx, [world_header + WORLDHDR.standing]
    movsx   eax, word [rcx + rdi*2]
    ret

; standings_unchanged() -> eax 1 when every standing is still the starting one
standings_unchanged:
    lea     rcx, [world_header + WORLDHDR.standing]
    lea     rdx, [start_standing]
    xor     eax, eax
.l:
    mov     r8w, [rcx + rax*2]
    cmp     r8w, [rdx + rax*2]
    jne     .no
    inc     eax
    cmp     eax, NUM_FACTIONS
    jb      .l
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; hit_folk(edi slot) -> eax damage dealt: one melee hit of the player's, base 5, from the west
hit_folk:
    sub     rsp, 8
    mov     eax, __float32__(5.0)
    movd    xmm0, eax
    mov     eax, __float32__(1.0)
    movd    xmm1, eax
    xorps   xmm2, xmm2
    mov     esi, SRC_MELEE
    xor     edx, edx
    call    combat_hit_mob
    add     rsp, 8
    ret

; blast(edi slot): a magic blast (radius 3, 10 damage of fire from a spell) centred on that mob's middle
blast:
    push    rbx
    mov     ebx, edi
    call    mob_ptr
    movss   xmm0, [rax + BODY.x]
    movss   xmm1, [rax + BODY.y]
    addss   xmm1, [k_1]
    movss   xmm2, [rax + BODY.z]
    movss   xmm3, [k_3]
    mov     edi, 10
    mov     esi, SRC_SPELL
    mov     edx, ELEM_FIRE
    call    explode_magic
    pop     rbx
    ret

; kill_folk(edi slot) -> eax 1 when repeated hits killed it within 120 blows (the AI does not run)
kill_folk:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, 120
.hit:
    mov     edi, ebx
    call    hit_folk
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.type], MOB_NONE
    je      .dead
    dec     r12d
    jnz     .hit
    xor     eax, eax
    jmp     .ret
.dead:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; steps(edi n): n fixed steps of mobs and arrows
steps:
    push    rbx
    mov     ebx, edi
.l:
    call    mobs_step
    call    arrows_step
    dec     ebx
    jnz     .l
    pop     rbx
    ret

; streq(rdi a, rsi b) -> eax 1 when the two NUL-terminated strings are equal
streq:
.l:
    mov     al, [rdi]
    cmp     al, [rsi]
    jne     .no
    test    al, al
    jz      .yes
    inc     rdi
    inc     rsi
    jmp     .l
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; name_is(rdi mob, rsi expected) -> eax 1 when folk_name of that mob is exactly that string
; Frame: [rsp] the name
name_is:
    push    rbx
    sub     rsp, 80
    mov     rbx, rsi
    lea     rsi, [rsp]
    call    folk_name
    mov     byte [rax], 0
    lea     rdi, [rsp]
    mov     rsi, rbx
    call    streq
    add     rsp, 80
    pop     rbx
    ret

; banner_is(rdi expected) -> eax 1 when the HUD banner shows exactly that text
banner_is:
    sub     rsp, 8
    mov     rsi, rdi
    lea     rdi, [banner_text]
    call    streq
    add     rsp, 8
    ret

; has_drop(edi item id) -> eax 1 when some item entity on the ground is that item
has_drop:
    lea     rcx, [drops]
    mov     edx, MAX_DROPS
.l:
    cmp     [rcx + DROP.id], dil
    je      .yes
    add     rcx, DROP_size
    dec     edx
    jnz     .l
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; drop_count(edi item id) -> eax the items of that id lying on the ground, counting each stack's size
drop_count:
    lea     rcx, [drops]
    mov     edx, MAX_DROPS
    xor     eax, eax
.l:
    cmp     [rcx + DROP.id], dil
    jne     .next
    movzx   esi, byte [rcx + DROP.count]
    add     eax, esi
.next:
    add     rcx, DROP_size
    dec     edx
    jnz     .l
    ret

; has_legendary() -> eax 1 when some item entity on the ground is a legendary item
has_legendary:
    lea     rcx, [drops]
    lea     rsi, [item_legendary]
    mov     edx, MAX_DROPS
.l:
    movzx   eax, byte [rcx + DROP.id]
    test    eax, eax
    jz      .next
    cmp     byte [rsi + rax], 0
    jne     .yes
.next:
    add     rcx, DROP_size
    dec     edx
    jnz     .l
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; arrow_of(edi owner) -> eax 1 when a live projectile with that owner is in the air or stuck
arrow_of:
    lea     rcx, [arrows]
    mov     edx, MAX_ARROWS
.l:
    cmp     dword [rcx + ARROWENT.live], 0
    je      .next
    cmp     [rcx + ARROWENT.owner], edi
    je      .yes
.next:
    add     rcx, ARROWENT_size
    dec     edx
    jnz     .l
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; folk_at(edi faction, esi role, edx fclass, xmm0 x) -> eax slot: folk_spawn at (x, 11, 100.5)
folk_at:
    sub     rsp, 8
    mov     eax, __float32__(11.0)
    movd    xmm1, eax
    mov     eax, __float32__(100.5)
    movd    xmm2, eax
    call    folk_spawn
    add     rsp, 8
    ret

; ---- who they are --------------------------------------------------------------------------------

; Every role and class as a table row (level 1): the fields, the health and walking speed of the class
; (a non-fighter 20 and 2, a captive 0; archer 18 / 2.6, brute 32 / 2.2, acolyte 16 / 2.4, berserker
; 24 / 3.0), the weapon (BOW, IRON_HAMMER, STAFF, IRON_SWORD at tier 0) and the name plate text. A
; Bandits brute's weapon roll is a gear dmg word of tier 0. The element rule: for every seed of a
; rare IRON_SWORD, folk_weapon_affix gives the AFX bit of the first elemental affix (all four kinds
; come up), else nothing for a Bandits berserker and MOLTEN for an Ashen Cult acolyte (the weapon's
; own element wins there too); a common STAFF makes a Cult acolyte MOLTEN, a common BOW a Bandits
; archer nothing.
; rbx = the mob / the expected AFX bit, r12 = the row / the dmg word, r13d = the row index / the seed;
; frame: [rsp] GEARAFFIX[5], [rsp+40] the kinds of elements seen (bit 1 + STAT_ADD_* - STAT_ADD_FIRE)
test_folk_spawn_and_weapons:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 56
    call    world_clear
    call    fixture
    lea     r12, [spawn_rows]
    xor     r13d, r13d
.row:
    mov     edi, [r12]
    mov     esi, [r12 + 4]
    mov     edx, [r12 + 8]
    cvtsi2ss xmm0, r13d
    mulss   xmm0, [k_3_5]
    addss   xmm0, [k_60_5]              ; 3.5 blocks apart along x
    call    folk_at
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    mov     rbx, rax
    cmp     dword [rbx + MOB.type], MOB_FOLK
    jne     .fail
    mov     eax, [r12]
    cmp     [rbx + MOB.faction], al
    jne     .fail
    mov     eax, [r12 + 4]
    cmp     [rbx + MOB.role], al
    jne     .fail
    mov     eax, [r12 + 8]
    cmp     [rbx + MOB.fclass], al
    jne     .fail
    cmp     dword [rbx + MOB.level], 1
    jne     .fail
    mov     eax, [r12 + 12]
    cmp     [rbx + MOB.health], eax
    jne     .fail
    cmp     [rbx + MOB.max_health], eax
    jne     .fail
    mov     eax, [r12 + 16]
    cmp     [rbx + BODY.speed], eax
    jne     .fail
    mov     eax, [r12 + 20]
    cmp     [rbx + MOB.wid], al
    jne     .fail
    mov     rdi, rbx
    mov     rsi, [r12 + 24]
    call    name_is
    test    eax, eax
    jz      .fail
    add     r12, 32
    inc     r13d
    cmp     r13d, SPAWN_ROWS
    jb      .row
    movzx   eax, word [rbx + MOB.wdmg]  ; the last one, the Bandits brute: a tier-0 weapon roll
    shr     eax, GEAR_TIER_SHIFT
    and     eax, 15
    jnz     .fail
    mov     dword [rsp + 40], 0
    mov     r13d, 1                     ; seed
.seed:
    mov     edi, IRON_SWORD
    xor     esi, esi
    mov     edx, RAR_RARE
    mov     ecx, r13d
    call    gear_make
    mov     r12d, eax                   ; the dmg word
    mov     edi, IRON_SWORD
    mov     esi, r12d
    lea     rdx, [rsp]
    call    gear_affixes
    xor     ebx, ebx                    ; no elemental affix: no element...
    xor     ecx, ecx
.look:
    cmp     ecx, eax
    jae     .expect
    mov     edx, [rsp + rcx*8]
    sub     edx, STAT_ADD_FIRE
    cmp     edx, 3
    jbe     .elem
    inc     ecx
    jmp     .look
.elem:                                  ; the first elemental affix decides: FIRE, FROST, SHOCK, POISON
    lea     ecx, [rdx + 1]
    mov     eax, 1
    shl     eax, cl
    or      [rsp + 40], eax
    mov     ebx, AFX_MOLTEN
    mov     eax, AFX_FROZEN
    cmp     edx, 1
    cmove   ebx, eax
    mov     eax, AFX_STORM
    cmp     edx, 2
    cmove   ebx, eax
    mov     eax, AFX_VENOMOUS
    cmp     edx, 3
    cmove   ebx, eax
.expect:
    mov     edi, IRON_SWORD
    mov     esi, r12d
    mov     edx, FAC_BANDITS
    mov     ecx, FCLASS_BERSERKER
    call    folk_weapon_affix
    cmp     eax, ebx
    jne     .fail
    mov     edi, IRON_SWORD
    mov     esi, r12d
    mov     edx, FAC_CULT
    mov     ecx, FCLASS_ACOLYTE
    call    folk_weapon_affix           ; a Cult acolyte without one burns anyway
    mov     ecx, AFX_MOLTEN
    test    ebx, ebx
    cmovz   ebx, ecx
    cmp     eax, ebx
    jne     .fail
    inc     r13d
    cmp     r13d, 1023
    jbe     .seed
    cmp     dword [rsp + 40], 0x1E      ; fire, frost, shock and poison all came up
    jne     .fail
    mov     edi, STAFF                  ; a common staff (dmg 0): a Cult acolyte's flame
    xor     esi, esi
    mov     edx, FAC_CULT
    mov     ecx, FCLASS_ACOLYTE
    call    folk_weapon_affix
    cmp     eax, AFX_MOLTEN
    jne     .fail
    mov     edi, BOW                    ; a common bow: a Bandits archer has no element
    xor     esi, esi
    mov     edx, FAC_BANDITS
    mov     ecx, FCLASS_ARCHER
    call    folk_weapon_affix
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 56
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- who they fight ------------------------------------------------------------------------------

; Survival, Normal, the player at (100.5, 11, 100.5).
; Hostility: a Bandits brute guard 8 blocks away at the starting -100 has the player for its target
; (1) after 40 steps and counts as hostile; at standing 0 it has none, is not hostile and a magic blast
; leaves it alone; a blow of the player's provokes it (provoked, target 1, hostile, a blast now hurts it)
; and a second Bandits guard 10 blocks away; a Villagers guard (200) never targets him; at Peaceful the
; Bandits at -100 leave him alone. The nearest enemy wins: a Villagers guard 4 blocks from the brute
; beats the player 8 off (target = 2 + its slot), the player beats one 12 off.
; Behaviour: a brute 1.5 blocks away takes health off the player; a Villagers guard (Friendly) greets
; him once ("Villager: Well met, friend"); a berserker below half its health rages (FF_RAGE, speed x 1.3);
; archers back off inside 6 blocks, hold at 8 and close in at 14, acolytes the same at 5 / 7 / 12; a
; brute's hammer stays up for 28 steps and a guard that comes up on the last one parries it (nothing
; taken, the brute stunned for 50 steps and reeling back).
; rbx = the first guard, r12d = the second, r13d scratch
test_folk_targets_and_standing:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    fixture
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 108.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 40
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.target], 1
    jne     .fail
    mov     edi, ebx
    call    mob_is_hostile
    cmp     eax, 1
    jne     .fail
    mov     edi, ebx                    ; 20 blocks off he stays its target (it keeps one to 24)...
    call    mob_ptr
    mov     r13, rax
    movss   xmm0, [r13 + BODY.x]
    addss   xmm0, [k_20]
    movss   [player + BODY.x], xmm0
    mov     eax, [r13 + BODY.z]
    mov     [player + BODY.z], eax
    mov     edi, 21
    call    steps
    cmp     dword [r13 + MOB.target], 1
    jne     .fail
    movss   xmm0, [r13 + BODY.x]        ; ...and 30 off he is not
    addss   xmm0, [k_30]
    movss   [player + BODY.x], xmm0
    mov     eax, [r13 + BODY.z]
    mov     [player + BODY.z], eax
    mov     edi, 2
    call    steps
    cmp     dword [r13 + MOB.target], 0
    jne     .fail
    SETF    [player + BODY.x], 100.5
    SETF    [player + BODY.z], 100.5
    call    mobs_clear
    mov     edi, FAC_BANDITS            ; at standing 0 the same guard ignores him
    xor     esi, esi
    call    set_standing
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 108.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 40
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.target], 0
    jne     .fail
    mov     edi, ebx
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail
    mov     edi, ebx                    ; a blast leaves the peaceful guard alone
    call    blast
    mov     edi, ebx
    call    mob_ptr
    mov     ecx, [rax + MOB.health]
    cmp     ecx, [rax + MOB.max_health]
    jne     .fail
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_ARCHER, 108.5, 110.5
    test    eax, eax
    js      .fail
    mov     r12d, eax
    mov     edi, ebx                    ; a blow provokes it...
    call    hit_folk
    test    eax, eax
    jz      .fail
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.provoked], 0
    jle     .fail
    cmp     dword [rax + MOB.target], 1
    jne     .fail
    mov     ecx, [rax + MOB.health]
    cmp     ecx, [rax + MOB.max_health]
    jge     .fail
    mov     edi, ebx
    call    mob_is_hostile
    cmp     eax, 1
    jne     .fail
    mov     edi, ebx
    call    mob_ptr
    mov     r13d, [rax + MOB.health]
    mov     edi, ebx                    ; hostile now: a blast reaches it
    call    blast
    mov     edi, ebx
    call    mob_ptr
    cmp     [rax + MOB.health], r13d
    jge     .fail
    mov     edi, r12d                   ; ...and the comrade 10 blocks off
    call    mob_ptr
    cmp     dword [rax + MOB.provoked], 0
    jle     .fail
    call    mobs_clear
    FOLK    FAC_VILLAGERS, ROLE_GUARD, FCLASS_ARCHER, 108.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 60
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.target], 0
    jne     .fail
    mov     edi, ebx
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail
    call    mobs_clear
    mov     edi, FAC_BANDITS
    mov     esi, -100
    call    set_standing
    mov     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 108.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 40
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.target], 0
    jne     .fail
    mov     edi, ebx
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail
    call    mobs_clear                  ; a brute 1.5 blocks away hits him: his health drops
    mov     dword [settings + SETTINGS.difficulty], DIFF_NORMAL
    call    survival_reset
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 102.0, 100.5
    test    eax, eax
    js      .fail
    mov     edi, 45
    call    steps
    cmp     dword [surv + SURVIVAL.health], 20
    jge     .fail
    call    mobs_clear                  ; a Villagers guard (Friendly) 3 blocks off greets him, once
    call    survival_reset
    FOLK    FAC_VILLAGERS, ROLE_GUARD, FCLASS_BRUTE, 103.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     byte [banner_text], 0
    mov     edi, 1
    call    steps
    lea     rdi, [s_well_met]
    call    banner_is
    test    eax, eax
    jz      .fail
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.greet], 0
    jle     .fail
    mov     byte [banner_text], 0
    mov     edi, 5
    call    steps
    cmp     byte [banner_text], 0
    jne     .fail
    call    mobs_clear                  ; a Neutral guard (Beastfolk, 0) 3 blocks off greets nobody
    mov     byte [banner_text], 0
    FOLK    FAC_BEASTFOLK, ROLE_GUARD, FCLASS_BERSERKER, 103.5, 100.5
    test    eax, eax
    js      .fail
    mov     edi, 5
    call    steps
    cmp     byte [banner_text], 0
    jne     .fail
    call    mobs_clear                  ; a provocation runs out: a Neutral guard the player struck hunts him...
    FOLK    FAC_BEASTFOLK, ROLE_GUARD, FCLASS_BRUTE, 108.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    call    hit_folk
    mov     edi, 2
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.target], 1
    jne     .fail
    mov     dword [rax + MOB.provoked], 3
    mov     edi, 8
    call    steps                       ; ...until it does: no target, not hostile again
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.provoked], 0
    jne     .fail
    cmp     dword [rax + MOB.target], 0
    jne     .fail
    mov     edi, ebx
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail
    call    mobs_clear                  ; a struck worker runs at 1.5 x its speed, and walks again once calm
    FOLK    FAC_VILLAGERS, ROLE_WORKER, FCLASS_NONE, 102.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    call    hit_folk
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.input + INPUT.fwd], 1
    jne     .fail
    cmp     dword [rax + BODY.speed], __float32__(3.0)
    jne     .fail
    mov     edi, 125
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.panic], 0
    jne     .fail
    cmp     dword [rax + BODY.speed], __float32__(2.0)
    jne     .fail
    call    mobs_clear                  ; the nearest enemy wins: a Villagers guard 4 blocks away beats the player
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 108.5, 100.5     ; 8 blocks away (target = 2 + its slot)...
    test    eax, eax
    js      .fail
    mov     ebx, eax
    FOLK    FAC_VILLAGERS, ROLE_GUARD, FCLASS_BRUTE, 112.5, 100.5
    test    eax, eax
    js      .fail
    mov     r12d, eax
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    lea     ecx, [r12 + 2]
    cmp     [rax + MOB.target], ecx
    jne     .fail
    call    mobs_clear                  ; ...and the player 8 blocks away beats one 12 blocks away
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 108.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    FOLK    FAC_VILLAGERS, ROLE_GUARD, FCLASS_BRUTE, 120.5, 100.5
    test    eax, eax
    js      .fail
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.target], 1
    jne     .fail
    call    mobs_clear                  ; a berserker below half its health rages: faster, and flagged
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BERSERKER, 108.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.health], 24
    jne     .fail
    test    byte [rax + MOB.fflags], FF_RAGE
    jnz     .fail
    mov     dword [rax + MOB.health], 11
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    test    byte [rax + MOB.fflags], FF_RAGE
    jz      .fail
    movss   xmm0, [rax + BODY.speed]
    comiss  xmm0, [k_3_85]              ; 3.0 x 1.3
    jb      .fail
    call    mobs_clear                  ; an archer 3 blocks off backs away, 8 off it holds, 14 off it closes in
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_ARCHER, 103.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.input + INPUT.fwd], -1
    jne     .fail
    call    mobs_clear
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_ARCHER, 108.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.input + INPUT.fwd], 0
    jne     .fail
    call    mobs_clear
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_ARCHER, 114.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.input + INPUT.fwd], 1
    jne     .fail
    call    mobs_clear                  ; an acolyte keeps 5..10: 4 off it backs away, 7 off it holds, 12 off it closes in
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_ACOLYTE, 104.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.input + INPUT.fwd], -1
    jne     .fail
    call    mobs_clear
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_ACOLYTE, 107.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.input + INPUT.fwd], 0
    jne     .fail
    call    mobs_clear
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_ACOLYTE, 112.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.input + INPUT.fwd], 1
    jne     .fail
    call    mobs_clear                  ; a brute raises its hammer for 28 steps; a guard that comes up on the last one
    call    arrows_clear                ; parries it: nothing taken, the brute dazed for 50 steps and reeling back
    call    combat_reset
    call    survival_reset
    SETF    [player + BODY.yaw], 90.0   ; facing +x, towards the brute
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 102.0, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, 1
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.windup], 28
    jne     .fail
    cmp     dword [rax + MOB.input + INPUT.fwd], 0
    jne     .fail
    mov     edi, 27
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.windup], 1
    jne     .fail
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail
    mov     dword [combat_guard_t], 0   ; the guard comes up on the very last step
    mov     edi, 1
    call    steps
    cmp     dword [surv + SURVIVAL.health], 20
    jne     .fail                       ; parried: nothing taken
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.stun], 50
    jne     .fail
    cmp     dword [rax + MOB.windup], 0
    jne     .fail
    movss   xmm0, [rax + BODY.kbx]      ; it stands at +x of the player: it reels back along +x
    comiss  xmm0, [k_1]
    jbe     .fail
    SETF    [player + BODY.yaw], 0.0
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; Creative, the player 60 blocks away. A Villagers brute and a Bandits brute 6 apart fight: one of them
; dies within 900 steps (a brute lands a 5-damage blow every ~100 steps on 32 health, so the first falls
; after ~650 steps; the spec's 600 is too tight) and every standing is still the starting one (no player
; kill). A Bandits brute and an Ashen Cult brute, no rivals, leave each other alone: both are alive with
; full health after 600 steps. Two Bandits patrols walk their roads: a brute's from x = 130.5 to 110.5
; turns within 6 blocks of the end and walks back; a berserker's from 140.5 to 60.5, cut by a wall at
; x = 110, turns round after 120 stuck steps.
; rbx, r12d = the two brutes / patrols, r13d = steps left
test_folk_rivals_fight:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     dword [game_mode], MODE_CREATIVE
    SETF    [player + BODY.x], 70.5
    FOLK    FAC_VILLAGERS, ROLE_GUARD, FCLASS_BRUTE, 110.5, 100.5   ; rivals 20 blocks apart do not notice
    test    eax, eax                                                ; each other (they see 16)
    js      .fail
    mov     ebx, eax
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 130.5, 100.5
    test    eax, eax
    js      .fail
    mov     r12d, eax
    mov     edi, 25
    call    steps
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.target], 0
    jne     .fail
    mov     edi, r12d
    call    mob_ptr
    cmp     dword [rax + MOB.target], 0
    jne     .fail
    call    mobs_clear
    FOLK    FAC_VILLAGERS, ROLE_GUARD, FCLASS_BRUTE, 130.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 136.5, 100.5
    test    eax, eax
    js      .fail
    mov     r12d, eax
    mov     r13d, 900
.fight:
    call    mobs_step
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.type], MOB_NONE
    je      .over
    mov     edi, r12d
    call    mob_ptr
    cmp     dword [rax + MOB.type], MOB_NONE
    je      .over
    dec     r13d
    jnz     .fight
    jmp     .fail                       ; nobody fell
.over:
    call    standings_unchanged
    test    eax, eax
    jz      .fail
    call    mobs_clear
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 130.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    FOLK    FAC_CULT, ROLE_GUARD, FCLASS_BRUTE, 136.5, 100.5
    test    eax, eax
    js      .fail
    mov     r12d, eax
    mov     r13d, 600
.peace:
    call    mobs_step
    dec     r13d
    jnz     .peace
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.type], MOB_FOLK
    jne     .fail
    mov     ecx, [rax + MOB.health]
    cmp     ecx, [rax + MOB.max_health]
    jne     .fail
    mov     edi, r12d
    call    mob_ptr
    cmp     dword [rax + MOB.type], MOB_FOLK
    jne     .fail
    mov     ecx, [rax + MOB.health]
    cmp     ecx, [rax + MOB.max_health]
    jne     .fail
    call    mobs_clear                  ; ---- patrols: a Bandits brute walks its road from 130.5 to 110.5, turns
    mov     r13d, 90                    ; within 6 blocks of the end and walks back; a berserker's road from 140.5
.wall_z:                                ; to 60.5 is cut by a wall (x = 110, z 90..97, y 11..13): after 120 stuck
    mov     ebx, 11                     ; steps it turns round too
.wall_y:
    mov     edi, 110
    mov     esi, ebx
    mov     edx, r13d
    mov     ecx, STONE
    call    world_set
    inc     ebx
    cmp     ebx, 13
    jbe     .wall_y
    inc     r13d
    cmp     r13d, 97
    jbe     .wall_z
    FOLK    FAC_BANDITS, ROLE_PATROL, FCLASS_BRUTE, 130.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    call    mob_ptr
    SETF    [rax + MOB.dest_x], 110.5
    SETF    [rax + MOB.dest_z], 100.5
    FOLK    FAC_BANDITS, ROLE_PATROL, FCLASS_BERSERKER, 140.5, 94.5
    test    eax, eax
    js      .fail
    mov     r12d, eax
    mov     edi, r12d
    call    mob_ptr
    SETF    [rax + MOB.dest_x], 60.5
    SETF    [rax + MOB.dest_z], 94.5
    mov     r13d, 450
.walk1:
    call    mobs_step
    dec     r13d
    jnz     .walk1
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.dest_x], __float32__(130.5)
    jne     .fail                       ; it turned at the end of its road: dest and home traded places
    cmp     dword [rax + MOB.home_x], __float32__(110.5)
    jne     .fail
    movss   xmm0, [rax + BODY.x]
    comiss  xmm0, [k_116_5]
    jbe     .fail                       ; and walks back east
    mov     r13d, 350
.walk2:
    call    mobs_step
    dec     r13d
    jnz     .walk2
    mov     edi, r12d
    call    mob_ptr
    cmp     dword [rax + MOB.dest_x], __float32__(140.5)
    jne     .fail                       ; the wall stopped it, and 120 stuck steps turned it round
    movss   xmm0, [rax + BODY.x]
    comiss  xmm0, [k_112]
    jbe     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- what killing one costs and drops -----------------------------------------------------------

; Reputation: the player kills a Bandits guard with melee hits: Bandits -110, Villagers 205, Stonekin 5
; (the rivals of the Bandits), Cult and Beastfolk unchanged, one gold coin lies there (1 + level / 10).
; A Villagers leader costs -50 and gives its rivals +5 (Villagers 150, Bandits and Cult -95) and drops
; 5 coins; a trader 3, a worker none.
; Champion: a Cult champion (folk_make_champion: elite, level 6, health 70, or 105 with Juggernaut, asleep)
; stands still with no target for 100 steps next to the player at standing -100; one hit wakes it; its
; death by the player sets bit 2 of WORLDHDR.champions, shows "Morvael the Ashen has fallen!" and drops
; its staff, 26 coins (20 + level) and a legendary item.
; rbx = the folk, r12 = its mob, r13d = steps left
test_folk_kill_reputation_and_drops:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     dword [rpg_stats + STAT_XP_BONUS * 4], -100     ; kills give no XP: no level-up banner over the champion's
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 104.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    call    kill_folk
    test    eax, eax
    jz      .fail
    mov     edi, FAC_BANDITS
    call    standing
    cmp     eax, -110
    jne     .fail
    mov     edi, FAC_VILLAGERS
    call    standing
    cmp     eax, 205
    jne     .fail
    mov     edi, FAC_STONEKIN
    call    standing
    cmp     eax, 5
    jne     .fail
    mov     edi, FAC_CULT
    call    standing
    cmp     eax, -100
    jne     .fail
    mov     edi, FAC_BEASTFOLK
    call    standing
    test    eax, eax
    jnz     .fail
    mov     edi, GOLD_COIN              ; 1 + level / 10 coins
    call    drop_count
    cmp     eax, 1
    jne     .fail
    call    mobs_clear                  ; a Villagers leader: -50 for them, +5 for their rivals, 5 + level / 5 coins;
    call    drops_clear                 ; a trader 3 coins; a worker nothing
    call    faction_reset
    FOLK    FAC_VILLAGERS, ROLE_LEADER, FCLASS_NONE, 104.5, 100.5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    kill_folk
    test    eax, eax
    jz      .fail
    mov     edi, FAC_VILLAGERS
    call    standing
    cmp     eax, 150
    jne     .fail
    mov     edi, FAC_BANDITS
    call    standing
    cmp     eax, -95
    jne     .fail
    mov     edi, FAC_CULT
    call    standing
    cmp     eax, -95
    jne     .fail
    mov     edi, GOLD_COIN
    call    drop_count
    cmp     eax, 5
    jne     .fail
    call    mobs_clear
    call    drops_clear
    FOLK    FAC_VILLAGERS, ROLE_TRADER, FCLASS_NONE, 104.5, 100.5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    kill_folk
    test    eax, eax
    jz      .fail
    mov     edi, GOLD_COIN
    call    drop_count
    cmp     eax, 3
    jne     .fail
    call    mobs_clear
    call    drops_clear
    FOLK    FAC_VILLAGERS, ROLE_WORKER, FCLASS_NONE, 104.5, 100.5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    kill_folk
    test    eax, eax
    jz      .fail
    mov     edi, GOLD_COIN
    call    drop_count
    test    eax, eax
    jnz     .fail
    call    faction_reset               ; back to the starting standings
    call    mobs_clear
    call    drops_clear
    FOLK    FAC_CULT, ROLE_CHAMPION, FCLASS_ACOLYTE, 104.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    call    folk_make_champion
    mov     edi, ebx
    call    mob_ptr
    mov     r12, rax
    cmp     dword [r12 + MOB.elite], 1
    jne     .fail
    cmp     dword [r12 + MOB.level], 6
    jne     .fail
    test    byte [r12 + MOB.fflags], FF_ASLEEP
    jz      .fail
    mov     eax, [r12 + MOB.max_health]
    cmp     eax, 70                     ; round(16 * 1.75 * 2.5)
    je      .health_ok
    cmp     eax, 105                    ; ...a Juggernaut's 1.5 x more
    jne     .fail
.health_ok:
    cmp     [r12 + MOB.health], eax
    jne     .fail
    mov     r13d, 100
.sleep:
    call    mobs_step
    cmp     dword [r12 + MOB.input + INPUT.fwd], 0
    jne     .fail
    cmp     dword [r12 + MOB.target], 0
    jne     .fail
    dec     r13d
    jnz     .sleep
    mov     edi, ebx
    call    mob_is_hostile
    test    eax, eax
    jnz     .fail                       ; asleep: no health bar, no ability target
    mov     edi, ebx
    call    hit_folk
    test    byte [r12 + MOB.fflags], FF_ASLEEP
    jnz     .fail                       ; one hit wakes it
    mov     edi, ebx
    call    mob_is_hostile
    cmp     eax, 1
    jne     .fail
    mov     edi, ebx
    call    kill_folk
    test    eax, eax
    jz      .fail
    movzx   eax, byte [world_header + WORLDHDR.champions]
    test    eax, 1 << FAC_CULT
    jz      .fail
    call    has_legendary
    test    eax, eax
    jz      .fail
    mov     edi, STAFF
    call    has_drop
    test    eax, eax
    jz      .fail
    mov     edi, GOLD_COIN              ; 20 + level coins
    call    drop_count
    cmp     eax, 26
    jne     .fail
    lea     rdi, [s_fallen]
    call    banner_is
    test    eax, eax
    jz      .fail
    call    mobs_clear                  ; at Hated (-201) a sleeping champion wakes by itself and says so; at
    mov     byte [banner_text], 0       ; Hostile (-200) it sleeps on
    mov     edi, FAC_CULT
    mov     esi, -200
    call    set_standing
    FOLK    FAC_CULT, ROLE_CHAMPION, FCLASS_ACOLYTE, 104.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    call    folk_make_champion
    mov     edi, 5
    call    steps
    mov     edi, ebx
    call    mob_ptr
    mov     r12, rax
    test    byte [r12 + MOB.fflags], FF_ASLEEP
    jz      .fail
    cmp     byte [banner_text], 0
    jne     .fail
    mov     edi, FAC_CULT
    mov     esi, -201
    call    set_standing
    mov     edi, 1
    call    steps
    test    byte [r12 + MOB.fflags], FF_ASLEEP
    jnz     .fail
    lea     rdi, [s_wakes]
    call    banner_is
    test    eax, eax
    jz      .fail
    mov     edi, 25
    call    steps
    cmp     dword [r12 + MOB.target], 1
    jne     .fail
    call    mobs_clear                  ; a champion the player did not slay (TNT, a rival) is not defeated:
    call    drops_clear                 ; no legendary, no hoard of coins, its bit stays clear
    mov     byte [world_header + WORLDHDR.champions], 0
    FOLK    FAC_CULT, ROLE_CHAMPION, FCLASS_ACOLYTE, 104.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    call    folk_make_champion
    mov     byte [combat_hit_flags], 0
    mov     edi, ebx
    mov     esi, 100000
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    call    mob_strike
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.type], MOB_NONE
    jne     .fail                       ; it died
    call    has_legendary
    test    eax, eax
    jnz     .fail
    mov     edi, GOLD_COIN
    call    drop_count
    cmp     eax, 20
    jae     .fail
    cmp     byte [world_header + WORLDHDR.champions], 0
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- arrows and bolts ---------------------------------------------------------------------------

; Creative, the player far away: a Bandits archer and a Villagers brute 10 apart in the open. Within
; 300 steps an arrow of OWNER_FOLK + FAC_BANDITS has been in the air and the brute has lost health.
; Survival: the Ashen Cult at -100: a Cult acolyte (MOLTEN) 8 blocks from the player looses a fire bolt
; and within 400 steps the player is burning (combat_burn_t > 0); a Bandits archer's arrows take health
; off him. Folk against folk: a fire arrow (folk_hit_by) burns a Villagers worker (health, burn, the
; folk's-burn flag, no tag, scared, no target) and the burn that kills it moves no standing, while a
; burn of the player's costs Villagers 10; a molten brute's blow (folk_strike_mob) hurts, burns and
; makes a guard hit back and scares a worker; mob_blow_raw scales with level and the elite factor; a
; rival's blow or shot wakes a sleeping champion without a banner.
; rbx, r12d, r13d = the folk in play, r14d = steps left
test_folk_projectiles:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    call    world_clear
    call    fixture
    mov     dword [game_mode], MODE_CREATIVE
    SETF    [player + BODY.x], 70.5
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_ARCHER, 120.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    FOLK    FAC_VILLAGERS, ROLE_GUARD, FCLASS_BRUTE, 130.5, 100.5
    test    eax, eax
    js      .fail
    mov     r12d, eax
    xor     r13d, r13d
    mov     r14d, 300
.fly:
    call    mobs_step
    call    arrows_step
    mov     edi, OWNER_FOLK + FAC_BANDITS
    call    arrow_of
    or      r13d, eax
    dec     r14d
    jnz     .fly
    test    r13d, r13d
    jz      .fail
    mov     edi, r12d
    call    mob_ptr
    mov     ecx, [rax + MOB.health]
    cmp     ecx, [rax + MOB.max_health]
    jge     .fail
    call    mobs_clear
    call    arrows_clear
    call    combat_reset
    mov     dword [game_mode], MODE_SURVIVAL
    SETF    [player + BODY.x], 100.5
    FOLK    FAC_CULT, ROLE_GUARD, FCLASS_ACOLYTE, 108.5, 100.5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    mob_ptr
    or      dword [rax + MOB.affix], AFX_MOLTEN
    mov     r14d, 400
.bolt:
    call    mobs_step
    call    arrows_step
    cmp     dword [combat_burn_t], 0
    jg      .burning
    dec     r14d
    jnz     .bolt
    jmp     .fail
.burning:
    call    mobs_clear                  ; an archer's arrows reach the player too: his health drops
    call    arrows_clear
    call    combat_reset
    call    survival_reset
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_ARCHER, 108.5, 100.5
    test    eax, eax
    js      .fail
    mov     r14d, 300
.shot:
    call    mobs_step
    call    arrows_step
    cmp     dword [surv + SURVIVAL.health], 20
    jl      .hurt
    dec     r14d
    jnz     .shot
    jmp     .fail
.hurt:
    call    mobs_clear                  ; folk against folk: a fire arrow burns a worker and scares it, and a burn
    call    arrows_clear                ; that takes it is nobody's kill
    FOLK    FAC_VILLAGERS, ROLE_WORKER, FCLASS_NONE, 120.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    mov     esi, 3
    mov     edx, ELEM_FIRE
    movss   xmm0, [k_1]
    xorps   xmm1, xmm1
    call    folk_hit_by
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.health], 17
    jne     .fail
    cmp     dword [rax + MOB.burn_t], 0
    jle     .fail
    test    byte [rax + MOB.fflags], FF_FOLKDOT
    jz      .fail
    cmp     dword [rax + MOB.tagged], 0
    jne     .fail
    cmp     dword [rax + MOB.panic], 0
    jle     .fail
    cmp     dword [rax + MOB.target], 0
    jne     .fail
    mov     byte [combat_hit_flags], HF_PLAYER | HF_DOT     ; the burn finishes it
    mov     edi, ebx
    mov     esi, 40
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    call    mob_strike
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.type], MOB_NONE
    jne     .fail
    call    standings_unchanged
    test    eax, eax
    jz      .fail                       ; nobody's kill: no standing moved
    FOLK    FAC_VILLAGERS, ROLE_WORKER, FCLASS_NONE, 120.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     byte [combat_hit_flags], HF_PLAYER | HF_DOT     ; a burn of the player's is
    mov     edi, ebx
    mov     esi, 40
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    call    mob_strike
    mov     edi, FAC_VILLAGERS
    call    standing
    cmp     eax, 190
    jne     .fail
    call    mobs_clear                  ; a molten brute's blow on a Villagers guard: the hit, the burn, a target
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 120.5, 94.5
    test    eax, eax
    js      .fail
    mov     r12d, eax
    mov     edi, r12d
    call    mob_ptr
    or      dword [rax + MOB.affix], AFX_MOLTEN
    mov     rbx, rax
    FOLK    FAC_VILLAGERS, ROLE_GUARD, FCLASS_BRUTE, 120.5, 96.5
    test    eax, eax
    js      .fail
    mov     r13d, eax
    mov     rdi, rbx
    mov     esi, r13d
    mov     edx, 5
    call    folk_strike_mob
    mov     edi, r13d
    call    mob_ptr
    cmp     dword [rax + MOB.health], 27
    jne     .fail
    cmp     dword [rax + MOB.burn_t], 0
    jle     .fail
    test    byte [rax + MOB.fflags], FF_FOLKDOT
    jz      .fail
    lea     ecx, [r12 + 2]
    cmp     [rax + MOB.target], ecx
    jne     .fail                       ; it fights back at whoever hit it
    FOLK    FAC_VILLAGERS, ROLE_WORKER, FCLASS_NONE, 120.5, 98.5    ; a worker struck by the same brute runs
    test    eax, eax
    js      .fail
    mov     r13d, eax
    mov     rdi, rbx
    mov     esi, r13d
    mov     edx, 5
    call    folk_strike_mob
    mov     edi, r13d
    call    mob_ptr
    cmp     dword [rax + MOB.health], 15
    jne     .fail
    cmp     dword [rax + MOB.panic], 0
    jle     .fail
    mov     rdi, rbx                    ; the blow: base 5 at level 1; level 11 doubles it; an elite's 1.5 x first, rounded
    mov     esi, 5
    call    mob_blow_raw
    cmp     eax, 5
    jne     .fail
    mov     dword [rbx + MOB.level], 11
    mov     rdi, rbx
    mov     esi, 5
    call    mob_blow_raw
    cmp     eax, 10
    jne     .fail
    mov     dword [rbx + MOB.elite], 1
    mov     rdi, rbx
    mov     esi, 5
    call    mob_blow_raw
    cmp     eax, 16
    jne     .fail
    call    mobs_clear                  ; a rival's blow wakes a sleeping champion without a banner, and it hits back;
    mov     byte [banner_text], 0       ; so does a rival's shot
    FOLK    FAC_CULT, ROLE_CHAMPION, FCLASS_BRUTE, 120.5, 98.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    call    folk_make_champion
    FOLK    FAC_VILLAGERS, ROLE_GUARD, FCLASS_BRUTE, 120.5, 96.5
    test    eax, eax
    js      .fail
    mov     r12d, eax
    mov     edi, ebx
    call    mob_ptr
    mov     r13, rax
    test    byte [r13 + MOB.fflags], FF_ASLEEP
    jz      .fail
    mov     edi, r12d
    call    mob_ptr
    mov     rdi, rax
    mov     esi, ebx
    mov     edx, 5
    call    folk_strike_mob
    test    byte [r13 + MOB.fflags], FF_ASLEEP
    jnz     .fail
    lea     ecx, [r12 + 2]
    cmp     [r13 + MOB.target], ecx
    jne     .fail
    cmp     byte [banner_text], 0
    jne     .fail
    or      byte [r13 + MOB.fflags], FF_ASLEEP
    mov     dword [r13 + MOB.hurt], 0
    mov     edi, ebx
    mov     esi, 3
    xor     edx, edx
    movss   xmm0, [k_1]
    xorps   xmm1, xmm1
    call    folk_hit_by
    test    byte [r13 + MOB.fflags], FF_ASLEEP
    jnz     .fail
    cmp     byte [banner_text], 0
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- right-click --------------------------------------------------------------------------------

; A Bandits trader at -100 (and at 199) opens nothing and the banner says "Bandits won't trade with
; you yet"; at 200 it opens ST_TRADE with screen_faction 1. The Villagers' leader opens ST_DIALOG. An
; Ashen Cult leader at -1 opens nothing ("Ashen Cult leader won't speak with you"), at 0 ST_LEADER with
; screen_faction 2. A Stonekin traveller trades at 0 (ST_TRADE, screen_faction 4) and not at -1. A guard,
; a worker, an empty slot and a bad one open nothing and show no banner. A Villagers captive held by
; Bandits with an awake Bandits guard 6 blocks away opens nothing ("Its guards are watching"); with the
; guard gone it is freed: Villagers +25, the folk gone, "Freed a Villager captive (+25)".
; rbx = the folk being clicked, r12d = the guard
test_folk_interact_gates:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    fixture
    FOLK    FAC_BANDITS, ROLE_TRADER, FCLASS_NONE, 104.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    call    folk_interact
    test    eax, eax
    jnz     .fail
    lea     rdi, [s_not_trade]
    call    banner_is
    test    eax, eax
    jz      .fail
    mov     edi, FAC_BANDITS            ; 199 is still short of Friendly
    mov     esi, 199
    call    set_standing
    mov     edi, ebx
    call    folk_interact
    test    eax, eax
    jnz     .fail
    mov     edi, FAC_BANDITS
    mov     esi, 200
    call    set_standing
    mov     dword [screen_faction], 0
    mov     edi, ebx
    call    folk_interact
    cmp     eax, ST_TRADE
    jne     .fail
    cmp     dword [screen_faction], FAC_BANDITS
    jne     .fail
    FOLK    FAC_VILLAGERS, ROLE_LEADER, FCLASS_NONE, 96.5, 100.5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    folk_interact
    cmp     eax, ST_DIALOG
    jne     .fail
    FOLK    FAC_CULT, ROLE_LEADER, FCLASS_NONE, 100.5, 104.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     byte [banner_text], 0
    mov     edi, ebx
    call    folk_interact
    test    eax, eax
    jnz     .fail
    lea     rdi, [s_no_speak]
    call    banner_is
    test    eax, eax
    jz      .fail
    mov     edi, FAC_CULT               ; one short of Neutral
    mov     esi, -1
    call    set_standing
    mov     edi, ebx
    call    folk_interact
    test    eax, eax
    jnz     .fail
    mov     edi, FAC_CULT
    xor     esi, esi
    call    set_standing
    mov     dword [screen_faction], 0
    mov     edi, ebx
    call    folk_interact
    cmp     eax, ST_LEADER
    jne     .fail
    cmp     dword [screen_faction], FAC_CULT
    jne     .fail
    call    mobs_clear                  ; a Stonekin traveller trades at standing 0, not at -1
    FOLK    FAC_STONEKIN, ROLE_TRAVELLER, FCLASS_NONE, 100.5, 104.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     dword [screen_faction], 0
    mov     edi, ebx
    call    folk_interact
    cmp     eax, ST_TRADE
    jne     .fail
    cmp     dword [screen_faction], FAC_STONEKIN
    jne     .fail
    mov     edi, FAC_STONEKIN
    mov     esi, -1
    call    set_standing
    mov     edi, ebx
    call    folk_interact
    test    eax, eax
    jnz     .fail
    lea     rdi, [s_stone_no]
    call    banner_is
    test    eax, eax
    jz      .fail
    mov     byte [banner_text], 0       ; nothing else opens anything: a guard, a worker, an empty slot
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 104.5, 104.5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    folk_interact
    test    eax, eax
    jnz     .fail
    FOLK    FAC_BANDITS, ROLE_WORKER, FCLASS_NONE, 106.5, 104.5
    test    eax, eax
    js      .fail
    mov     edi, eax
    call    folk_interact
    test    eax, eax
    jnz     .fail
    mov     edi, MAX_MOBS - 1
    call    folk_interact
    test    eax, eax
    jnz     .fail
    mov     edi, MAX_MOBS
    call    folk_interact
    test    eax, eax
    jnz     .fail
    cmp     byte [banner_text], 0
    jne     .fail
    call    mobs_clear
    FOLK    FAC_VILLAGERS, ROLE_CAPTIVE, FCLASS_NONE, 120.5, 100.5
    test    eax, eax
    js      .fail
    mov     ebx, eax
    mov     edi, ebx
    call    mob_ptr
    mov     byte [rax + MOB.captor], FAC_BANDITS
    FOLK    FAC_BANDITS, ROLE_GUARD, FCLASS_BRUTE, 120.5, 106.5
    test    eax, eax
    js      .fail
    mov     r12d, eax
    mov     byte [banner_text], 0
    mov     edi, ebx
    call    folk_interact
    test    eax, eax
    jnz     .fail
    lea     rdi, [s_watching]
    call    banner_is
    test    eax, eax
    jz      .fail
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.type], MOB_FOLK
    jne     .fail                       ; still held
    mov     edi, r12d
    call    mob_ptr
    mov     dword [rax + MOB.type], MOB_NONE    ; the guard is gone
    mov     edi, ebx
    call    folk_interact
    test    eax, eax
    jnz     .fail
    mov     edi, FAC_VILLAGERS
    call    standing
    cmp     eax, 225
    jne     .fail
    mov     edi, ebx
    call    mob_ptr
    cmp     dword [rax + MOB.type], MOB_NONE
    jne     .fail
    lea     rdi, [s_freed]
    call    banner_is
    test    eax, eax
    jz      .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- the travelling trader ----------------------------------------------------------------------

; travellers() -> eax the live travelling traders (leaf; ecx, edx, rsi)
travellers:
    xor     eax, eax
    lea     rsi, [mobs]
    mov     edx, MAX_MOBS
.l:
    cmp     dword [rsi + MOB.type], MOB_FOLK
    jne     .next
    cmp     byte [rsi + MOB.role], ROLE_TRAVELLER
    jne     .next
    inc     eax
.next:
    add     rsi, MOB_size
    dec     edx
    jnz     .l
    ret

; traveller() -> rax the first travelling trader (0 for none)
traveller:
    lea     rax, [mobs]
    mov     edx, MAX_MOBS
.l:
    cmp     dword [rax + MOB.type], MOB_FOLK
    jne     .next
    cmp     byte [rax + MOB.role], ROLE_TRAVELLER
    je      .ret
.next:
    add     rax, MOB_size
    dec     edx
    jnz     .l
    xor     eax, eax
.ret:
    ret

; With no camps cached, at game_time 10800 (a day step on the cadence: a multiple of 3600 whose
; quotient is a multiple of 3) one folk_travel_tick brings exactly one Stonekin TRAVELLER 24..41 blocks
; from the player (a second tick adds none). At 54000 (also on the cadence, but night) and at 14400
; (day, off the cadence: 14400 / 3600 = 4) none comes. A traveller whose timer_a ran out leaves once
; the player stands 30 blocks away (a step with the clock off the cadence) and stays while he is
; within 24. The nearest cached camp within 512 blocks sends its own faction (a Beastfolk camp 50 blocks
; away at standing 0) unless its standing is below 0 or it lies beyond 512 blocks: then Stonekin come.
; rbx = the traveller
test_folk_travellers:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    call    fixture
    mov     dword [game_time], 10800
    call    folk_travel_tick
    call    travellers
    cmp     eax, 1
    jne     .fail
    call    traveller
    mov     rbx, rax
    cmp     byte [rbx + MOB.faction], FAC_STONEKIN
    jne     .fail
    cmp     dword [rbx + MOB.timer_a], 18000
    jne     .fail
    movss   xmm0, [rbx + BODY.x]
    subss   xmm0, [player + BODY.x]
    mulss   xmm0, xmm0
    movss   xmm1, [rbx + BODY.z]
    subss   xmm1, [player + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [k_529]
    jb      .fail
    comiss  xmm0, [k_1764]
    ja      .fail
    call    folk_travel_tick            ; one at a time
    call    travellers
    cmp     eax, 1
    jne     .fail
    call    mobs_clear
    mov     dword [game_time], 54000
    call    folk_travel_tick
    call    travellers
    test    eax, eax
    jnz     .fail
    mov     dword [game_time], 14400
    call    folk_travel_tick
    call    travellers
    test    eax, eax
    jnz     .fail
    mov     dword [game_time], 10800
    call    folk_travel_tick
    call    traveller
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    mov     dword [rbx + MOB.timer_a], 1
    mov     dword [game_time], 10801    ; off the cadence: no second one comes
    movss   xmm0, [rbx + BODY.x]
    addss   xmm0, [k_30]
    movss   [player + BODY.x], xmm0
    movss   xmm0, [rbx + BODY.z]
    movss   [player + BODY.z], xmm0
    call    mobs_step
    call    travellers
    test    eax, eax
    jnz     .fail                       ; time was up and nobody watched: it left
    mov     dword [game_time], 10800
    call    folk_travel_tick
    call    traveller
    test    rax, rax
    jz      .fail
    mov     rbx, rax
    mov     dword [rbx + MOB.timer_a], 0
    mov     dword [game_time], 10801
    movss   xmm0, [rbx + BODY.x]
    addss   xmm0, [k_10]
    movss   [player + BODY.x], xmm0     ; the player 10 blocks off: he is watching
    movss   xmm0, [rbx + BODY.z]
    movss   [player + BODY.z], xmm0
    mov     edi, 3
    call    steps
    call    travellers
    cmp     eax, 1
    jne     .fail                       ; time was up, but within 24 blocks it stays
    call    mobs_clear                  ; the nearest cached camp decides its faction: a Beastfolk camp 50 blocks
    mov     dword [site_count], 1       ; off at standing 0...
    mov     dword [sites + SITE.kind], SITE_CAMP
    mov     dword [sites + SITE.index], FAC_BEASTFOLK
    mov     dword [sites + SITE.x], 150
    mov     dword [sites + SITE.z], 100
    mov     dword [game_time], 10800
    call    folk_travel_tick
    call    traveller
    test    rax, rax
    jz      .fail
    cmp     byte [rax + MOB.faction], FAC_BEASTFOLK
    jne     .fail
    call    mobs_clear                  ; ...a standing below 0 sends a Stonekin instead...
    mov     edi, FAC_BEASTFOLK
    mov     esi, -1
    call    set_standing
    call    folk_travel_tick
    call    traveller
    test    rax, rax
    jz      .fail
    cmp     byte [rax + MOB.faction], FAC_STONEKIN
    jne     .fail
    call    mobs_clear                  ; ...and so does a camp more than 512 blocks away
    mov     edi, FAC_BEASTFOLK
    xor     esi, esi
    call    set_standing
    mov     dword [sites + SITE.x], 700
    call    folk_travel_tick
    call    traveller
    test    rax, rax
    jz      .fail
    cmp     byte [rax + MOB.faction], FAC_STONEKIN
    jne     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    mov     ebx, eax
    call    cleanup
    mov     eax, ebx
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
