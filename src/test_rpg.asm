; test_rpg.asm - character progression, skill points, attributes, derived stats, quests and trades.
%include "common.inc"
default rel

global test_rpg_levels_and_points, test_rpg_skill_spend_rules, test_rpg_stats_from_class_and_ranks
global test_rpg_save_load_validates, test_quest_chain_progress_and_rewards
global test_trade_exchanges_items
global test_rpg_attributes_and_respec, test_rpg_keystones_and_caps

extern world_clear, world_header, str_eq, fx_clear
extern inv, inv_clear, inv_add, inv_count
extern drops, drops_clear
extern surv, survival_reset, surv_max_health
extern combat_reset, combat_mana, combat_stamina
extern rpg_state, rpg_ext, rpg_stats, rpg_keystones, rpg_reset, rpg_set_class, rpg_class
extern rpg_level, rpg_points, rpg_xp_need, rpg_add_xp, rpg_can_spend, rpg_spend, rpg_rank
extern rpg_stat, rpg_recompute, rpg_clamp_stats, rpg_ability_unlocked, rpg_class_info, rpg_ability_tile
extern rpg_node_info, rpg_ability_info, rpg_branch_name, rpg_stat_info, rpg_format_stat
extern rpg_attr, rpg_attr_points, rpg_spend_attr, rpg_attr_info, rpg_attr_desc
extern rpg_respec_cost, rpg_respec, rpg_keystone
extern rpg_on_mob_killed, rpg_on_block_mined, rpg_on_death, rpg_load, rpg_save
extern quests_current, quests_progress, quests_accept, quests_can_complete, quests_complete
extern quests_on_kill, quests_on_dungeon_cleared, quests_on_boss_killed
extern trade_offer, trade_can, trade_execute

%define R_CLASS   rpg_state + RPGSAVE.class
%define R_LEVEL   rpg_state + RPGSAVE.level
%define R_QUEST   rpg_state + RPGSAVE.quest
%define R_QSTATE  rpg_state + RPGSAVE.quest_state
%define R_QPROG   rpg_state + RPGSAVE.quest_progress
%define R_XP      rpg_state + RPGSAVE.xp
%define R_RANKS   rpg_ext + RPGEXT.ranks
%define R_ATTR    rpg_ext + RPGEXT.attr
%define R_CLEARED rpg_state + RPGSAVE.cleared
%define R_FLAGS   rpg_state + RPGSAVE.flags
%define HDR       world_header + WORLDHDR.rpg
%define HDRX      world_header + WORLDHDR.rpgx
%define KS_NONE   0xFF
%define NOLO      -2147483648           ; no lowest / highest limit
%define NOHI      2147483647

; the plan's skill trees, one 24-byte record per node (node = branch * 6 + tier): name, text (0 for
; a stat node), code, value per rank, padding. The code is the stat id of a stat node, 0x80 | slot
; for an ability and 0xC0 | id for a keystone.
section .rodata.str progbits alloc noexec nowrite align=1

%macro EXPN 3                           ; name, stat id, value per rank
section .rodata.str
%%n: db %1, 0
section .rodata
    dq %%n, 0
    db %2, %3, 0, 0, 0, 0, 0, 0
%endmacro
%macro EXPA 2                           ; ability name, slot
section .rodata.str
%%n: db %1, 0
section .rodata
    dq %%n, 0
    db 0x80 | %2, 0, 0, 0, 0, 0, 0, 0
%endmacro
%macro EXPK 3                           ; name, keystone id, text
section .rodata.str
%%n: db %1, 0
%%d: db %3, 0
section .rodata
    dq %%n, %%d
    db 0xC0 | %2, 0, 0, 0, 0, 0, 0, 0
%endmacro
; a stat record: label, the text of the value 7, format, icon tile
%macro EXPS 4                           ; label, format, icon, text
section .rodata.str
%%l: db %1, 0
%%t: db %4, 0
section .rodata
    dq %%l, %%t
    db %2, %3, 0, 0, 0, 0, 0, 0
%endmacro

section .rodata
align 8
exp_nodes:
    ; Warrior
    EXPN "Weapon Mastery", STAT_MELEE_DMG, 6
    EXPN "Precision", STAT_CRIT_CHANCE, 3
    EXPN "Brutality", STAT_CRIT_DMG, 15
    EXPN "Bloodthirst", STAT_LIFESTEAL, 2
    EXPN "Swift Blade", STAT_ATTACK_SPEED, 5
    EXPK "Executioner", KS_EXECUTIONER, "Melee hits on foes under 30% health deal +60% damage"
    EXPN "Toughness", STAT_MAX_HEALTH, 4
    EXPA "War Cry", 1
    EXPN "Iron Skin", STAT_ARMOR_BONUS, 1
    EXPA "Whirlwind", 2
    EXPN "Shield Wall", STAT_BLOCK_COST, 10
    EXPK "Juggernaut", KS_JUGGERNAUT, "No knockback, +4 armor, -15% move speed"
    EXPN "Stamina", STAT_MAX_STAMINA, 12
    EXPN "Second Wind", STAT_STAMINA_REGEN, 10
    EXPN "Riposte", STAT_PARRY_WINDOW, 1
    EXPA "Ground Slam", 3
    EXPN "Spiked Mail", STAT_THORNS, 3
    EXPK "Bloodrage", KS_BLOODRAGE, "+1% damage per 2% missing health, -10% max health"
    ; Mage
    EXPN "Pyromancy", STAT_SPELL_DMG, 6
    EXPN "Kindling", STAT_FIRE_DMG, 8
    EXPN "Combustion", STAT_CRIT_DMG, 15
    EXPN "Fire Touch", STAT_ADD_FIRE, 1
    EXPN "Static", STAT_SHOCK_DMG, 8
    EXPK "Inferno", KS_INFERNO, "Spell hits ignite; burning foes take +25% spell damage; -50% frost damage"
    EXPN "Deep Mind", STAT_MAX_MANA, 15
    EXPA "Blink", 1
    EXPN "Flow", STAT_MANA_REGEN, 1
    EXPA "Meteor Storm", 2
    EXPN "Haste", STAT_COOLDOWN_RED, 4
    EXPK "Blood Magic", KS_BLOOD_MAGIC, "Mana costs are paid with health (1 per 5 mana); +30% spell damage"
    EXPN "Vitality", STAT_MAX_HEALTH, 3
    EXPN "Frost Weaving", STAT_FROST_DMG, 8
    EXPN "Arcane Reach", STAT_AREA, 8
    EXPA "Frost Nova", 3
    EXPN "Renewal", STAT_LIFE_REGEN, 5
    EXPK "Mana Shield", KS_MANA_SHIELD, "35% of damage taken drains mana instead (2 mana per point)"
    ; Archer
    EXPN "Steady Aim", STAT_RANGED_DMG, 6
    EXPN "Eagle Eye", STAT_CRIT_CHANCE, 3
    EXPN "Deadly Shot", STAT_CRIT_DMG, 15
    EXPN "Quick Draw", STAT_ATTACK_SPEED, 5
    EXPN "Big Game", STAT_ELITE_DMG, 6
    EXPK "Deadeye", KS_DEADEYE, "Fully drawn shots always crit; attack speed no longer speeds your draw"
    EXPN "Fleet Foot", STAT_MOVE_SPEED, 3
    EXPA "Explosive Arrow", 1
    EXPN "Quiver", STAT_ARROW_SAVE, 10
    EXPA "Arrow Rain", 2
    EXPN "Toxic Tips", STAT_ADD_POISON, 1
    EXPK "Barrage", KS_BARRAGE, "Bow shots fire 2 extra arrows (60% damage); Volley fires 7"
    EXPN "Vitality", STAT_MAX_HEALTH, 3
    EXPN "Evasion", STAT_DODGE_COST, 10
    EXPN "Second Wind", STAT_STAMINA_REGEN, 10
    EXPA "Hunter's Mark", 3
    EXPN "Readiness", STAT_COOLDOWN_RED, 4
    EXPK "Wind Runner", KS_WIND_RUNNER, "+20% move speed; dodges cost no stamina but recover twice as slowly"
    ; Rogue
    EXPN "Backstab", STAT_BACKSTAB, 20
    EXPN "Precision", STAT_CRIT_CHANCE, 3
    EXPN "Cruelty", STAT_CRIT_DMG, 15
    EXPN "Serrated", STAT_BLEED_CHANCE, 8
    EXPN "Blade Mastery", STAT_MELEE_DMG, 6
    EXPK "Assassinate", KS_ASSASSINATE, "Backstabs kill non-boss foes under 25% health; +50% backstab vs bosses"
    EXPN "Fleet Foot", STAT_MOVE_SPEED, 3
    EXPA "Smoke Bomb", 1
    EXPN "Evasion", STAT_DODGE_COST, 10
    EXPA "Blade Dance", 2
    EXPN "Venom", STAT_POISON_DMG, 10
    EXPK "Shadow Dance", KS_SHADOW_DANCE, "Smoke Bomb stealth lasts 30 s; the first hit from stealth deals double"
    EXPN "Endurance", STAT_MAX_STAMINA, 12
    EXPN "Second Wind", STAT_STAMINA_REGEN, 10
    EXPN "Leech", STAT_LIFESTEAL, 2
    EXPA "Fan of Knives", 3
    EXPN "Lethality", STAT_DOT_DMG, 10
    EXPK "Venom Blades", KS_VENOM_BLADES, "Melee hits add 2 poison stacks; +50% poison damage; -30% crit damage"
exp_nodes_end:
%if exp_nodes_end - exp_nodes != NUM_CLASSES * NUM_NODES * 24
%error "exp_nodes needs NUM_NODES records per class"
%endif

; the plan's stat table by stat id
exp_stats:
    EXPS "Max health", FMT_FLAT, 155, "+7 max health"
    EXPS "Melee damage", FMT_PCT, 156, "+7% melee damage"
    EXPS "Ranged damage", FMT_PCT, 157, "+7% ranged damage"
    EXPS "Spell damage", FMT_PCT, 158, "+7% spell damage"
    EXPS "Crit chance", FMT_PCT, 159, "+7% critical chance"
    EXPS "Crit damage", FMT_PCT, 160, "+7% critical damage"
    EXPS "Max mana", FMT_FLAT, 161, "+7 max mana"
    EXPS "Mana regen", FMT_FLAT, 162, "+7 mana per second"
    EXPS "Max stamina", FMT_FLAT, 163, "+7 max stamina"
    EXPS "Stamina regen", FMT_PCT, 164, "+7% stamina regen"
    EXPS "Armor", FMT_FLAT, 165, "+7 armor"
    EXPS "Move speed", FMT_PCT, 166, "+7% move speed"
    EXPS "Backstab", FMT_PCT, 167, "+7% backstab damage"
    EXPS "Parry window", FMT_FLAT, 168, "+7 steps parry window"
    EXPS "Lifesteal", FMT_PCT, 169, "+7% of damage healed"
    EXPS "Cooldowns", FMT_NEGPCT, 170, "-7% cooldowns"
    EXPS "Arrow save", FMT_PCT, 171, "+7% arrows saved"
    EXPS "Dodge cost", FMT_NEGPCT, 172, "-7% dodge cost"
    EXPS "Attack speed", FMT_PCT, 237, "+7% attack speed"
    EXPS "Fire damage", FMT_PCT, 233, "+7% fire damage"
    EXPS "Frost damage", FMT_PCT, 234, "+7% frost damage"
    EXPS "Shock damage", FMT_PCT, 235, "+7% shock damage"
    EXPS "Poison damage", FMT_PCT, 236, "+7% poison damage"
    EXPS "Added fire", FMT_FLAT, 233, "+7 fire damage to attacks"
    EXPS "Added frost", FMT_FLAT, 234, "+7 frost damage to attacks"
    EXPS "Added shock", FMT_FLAT, 235, "+7 shock damage to attacks"
    EXPS "Added poison", FMT_FLAT, 236, "+7 poison damage to attacks"
    EXPS "Fire resist", FMT_PCT, 233, "+7% fire resistance"
    EXPS "Frost resist", FMT_PCT, 234, "+7% frost resistance"
    EXPS "Shock resist", FMT_PCT, 235, "+7% shock resistance"
    EXPS "Poison resist", FMT_PCT, 236, "+7% poison resistance"
    EXPS "Bleed chance", FMT_PCT, 238, "+7% bleed chance"
    EXPS "Damage over time", FMT_PCT, 238, "+7% damage over time"
    EXPS "Elite damage", FMT_PCT, 254, "+7% damage to elites"
    EXPS "Area", FMT_PCT, 239, "+7% area of effect"
    EXPS "Life regen", FMT_TENTH, 155, "+0.7 health per second"
    EXPS "Life on kill", FMT_FLAT, 169, "+7 health per kill"
    EXPS "Thorns", FMT_FLAT, 165, "+7 thorns damage"
    EXPS "Block cost", FMT_NEGPCT, 168, "-7% block stamina cost"
    EXPS "XP bonus", FMT_PCT, 138, "+7% experience"
    EXPS "Gold find", FMT_PCT, 138, "+7% gold found"
    EXPS "Magic find", FMT_PCT, 138, "+7% magic find"
    EXPS "All damage", FMT_PCT, 160, "+7% all damage"
    EXPS "Weapon damage", FMT_FLAT, 156, "+7 weapon damage"
exp_stats_end:
%if exp_stats_end - exp_stats != NUM_STATS * 24
%error "exp_stats needs one record per stat"
%endif

; the plan's abilities by (class - 1) * 4 + slot: resource, cost, cooldown in seconds
exp_abil:
    db RES_STAMINA, 30, 6,  RES_STAMINA, 40, 20, RES_STAMINA, 60, 30, RES_STAMINA, 45, 12   ; Warrior
    db RES_MANA, 25, 3,     RES_MANA, 20, 5,     RES_MANA, 70, 40,     RES_MANA, 35, 10       ; Mage
    db RES_STAMINA, 30, 6,  RES_STAMINA, 35, 10, RES_STAMINA, 60, 30, RES_STAMINA, 20, 8      ; Archer
    db RES_STAMINA, 25, 8,  RES_STAMINA, 40, 20, RES_STAMINA, 60, 35, RES_STAMINA, 35, 9      ; Rogue

; what each keystone alone does to a level 30 character of its class: two (stat, value) pairs
; (KS_NONE: nothing to check); the other effects live in the combat code
align 4
exp_ks:
    dd KS_NONE, 0, KS_NONE, 0                           ; Executioner
    dd STAT_ARMOR_BONUS, 4, STAT_MOVE_SPEED, -15        ; Juggernaut
    dd STAT_MAX_HEALTH, 73, KS_NONE, 0                  ; Bloodrage: (24 + 58) * 9 / 10
    dd STAT_FROST_DMG, -50, KS_NONE, 0                  ; Inferno
    dd STAT_SPELL_DMG, 40, KS_NONE, 0                   ; Blood Magic: 10 + 30
    dd KS_NONE, 0, KS_NONE, 0                           ; Mana Shield
    dd KS_NONE, 0, KS_NONE, 0                           ; Deadeye
    dd KS_NONE, 0, KS_NONE, 0                           ; Barrage
    dd STAT_MOVE_SPEED, 25, KS_NONE, 0                  ; Wind Runner: 5 + 20
    dd KS_NONE, 0, KS_NONE, 0                           ; Assassinate
    dd KS_NONE, 0, KS_NONE, 0                           ; Shadow Dance
    dd STAT_CRIT_DMG, -30, STAT_POISON_DMG, 50          ; Venom Blades

; the plan's stat limits: stat, lowest value, highest value
exp_caps:
    dd STAT_CRIT_CHANCE,  NOLO,  75
    dd STAT_COOLDOWN_RED, NOLO,  50
    dd STAT_DODGE_COST,   NOLO,  75
    dd STAT_ARROW_SAVE,   NOLO,  75
    dd STAT_BLOCK_COST,   NOLO,  75
    dd STAT_ATTACK_SPEED, NOLO, 100
    dd STAT_AREA,         NOLO, 100
    dd STAT_BLEED_CHANCE, NOLO, 100
    dd STAT_MOVE_SPEED,    -50,  50
    dd STAT_RES_FIRE,     -100,  75
    dd STAT_RES_FROST,    -100,  75
    dd STAT_RES_SHOCK,    -100,  75
    dd STAT_RES_POISON,   -100,  75
    dd STAT_CRIT_DMG,      -50, NOHI
    dd STAT_FIRE_DMG,      -90, NOHI
    dd STAT_FROST_DMG,     -90, NOHI
    dd STAT_SHOCK_DMG,     -90, NOHI
    dd STAT_POISON_DMG,    -90, NOHI
exp_caps_end:

kill_xp_tab:                            ; plain XP of a kill by mob type 1..9
    db 10, 2, 15, 12, 10, 2, 0, 0, 0
trade_tab:                              ; give, give_n, get, get_n
    dd GOLD_COIN, 6, HEALTH_POTION, 1
    dd GOLD_COIN, 6, MANA_POTION, 1
    dd GOLD_COIN, 4, ARROW, 16
    dd GOLD_COIN, 8, IRON_INGOT, 4
    dd GOLD_COIN, 25, DIAMOND, 1
    dd GOLD_COIN, 12, STAFF, 1
    dd ROTTEN_FLESH, 10, GOLD_COIN, 1
    dd DIAMOND, 1, GOLD_COIN, 15
    dd GOLD_COIN, 30, RING, 1
    dd GOLD_COIN, 30, AMULET, 1
s_warrior:  db "Warrior", 0
s_mage:     db "Mage", 0
s_archer:   db "Archer", 0
s_rogue:    db "Rogue", 0
s_heavy:    db "Heavy armor", 0
s_deepmind: db "Deep Mind", 0
s_agility:  db "Agility", 0
s_empty:    db 0
s_title0:   db "Zombie Trouble", 0
s_fallen:   db "The Fallen King", 0
s_strength: db "Strength", 0
s_dexterity: db "Dexterity", 0
s_intelligence: db "Intelligence", 0
s_vitality: db "Vitality", 0
s_str_fx:   db "+1% melee damage, +1 max stamina", 0
s_dex_fx:   db "+1% ranged damage; per 3: +1% attack speed; per 5: +1% crit chance", 0
s_int_fx:   db "+1% spell damage, +2 max mana; per 10: +1 mana per second", 0
s_vit_fx:   db "+1 max health, +1% stamina regen", 0
s_f_mana15: db "+15 max mana", 0
s_f_cd_neg: db "+3% cooldowns", 0
s_f_move_neg: db "-15% move speed", 0
s_f_regen_25: db "+2.5 health per second", 0
s_f_regen_neg: db "-0.5 health per second", 0
s_f_zero:   db "+0 max health", 0

section .bss
alignb 4
fmt_buf:    resb 48

section .text

; ---- harness -------------------------------------------------------------------

; save a result in rbx and keep rsp aligned; r12..r14 are free for the test body
%macro TEST_BEGIN 0
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
%endmacro
; success unless a check jumped to .fail; the world is left clean either way
%macro TEST_END 0
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    call    cleanup
    mov     eax, ebx
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
%endmacro

; fail unless the byte / dword at the operand equals the constant
%macro EXPECT_B 2
    cmp     byte [%1], %2
    jne     .fail
%endmacro
%macro EXPECT_D 2
    cmp     dword [%1], %2
    jne     .fail
%endmacro
; call %1 with edi = %2 and fail unless eax = %3
%macro CALL1 3
    mov     edi, %2
    call    %1
    cmp     eax, %3
    jne     .fail
%endmacro
; call %1 without arguments and fail unless eax = %2
%macro CALL0 2
    call    %1
    cmp     eax, %2
    jne     .fail
%endmacro
; inventory_add id, n
%macro ADD 2
    mov     edi, %1
    mov     esi, %2
    call    inv_add
%endmacro
; fail unless inv_count(id) = n
%macro HAVE 2
    mov     edi, %1
    call    inv_count
    cmp     eax, %2
    jne     .fail
%endmacro
; fail unless the zstr at rax equals the zstr %1
%macro STR_IS 1
    mov     rdi, rax
    lea     rsi, [%1]
    call    str_eq
    test    eax, eax
    jz      .fail
%endmacro
; fail unless rpg_format_stat(stat %1, value %2) is the zstr %3
%macro FMT_IS 3
    mov     edi, %1
    mov     esi, %2
    lea     rdx, [fmt_buf]
    call    rpg_format_stat
    lea     rcx, [fmt_buf]
    cmp     rax, rcx
    jne     .fail
    STR_IS  %3
%endmacro

; reset_all(): empty world, inventory, drops and particles, a class-less character at full health
reset_all:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    call    inv_clear
    call    drops_clear
    call    fx_clear
    call    rpg_reset
    call    survival_reset
    call    combat_reset
    pop     rbp
    ret

; cleanup(): reset_all, and nothing left in the header's RPG records
cleanup:
    push    rbp
    mov     rbp, rsp
    call    reset_all
    lea     rdi, [HDR]
    mov     ecx, RPGSAVE_size
    xor     eax, eax
    rep     stosb
    lea     rdi, [HDRX]
    mov     ecx, RPGEXT_size
    xor     eax, eax
    rep     stosb
    pop     rbp
    ret

; use_class(edi class, esi level): reset_all, then the class and level set directly (no kit)
use_class:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    call    reset_all
    mov     [R_CLASS], bl
    mov     [R_LEVEL], r12b
    call    rpg_recompute
    pop     r12
    pop     rbx
    pop     rbp
    ret

; spend_n(edi attribute, esi n) -> eax 0 when n attribute points went into the attribute
spend_n:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
.l:
    test    r12d, r12d
    jz      .ok
    mov     edi, ebx
    call    rpg_spend_attr
    test    eax, eax
    jz      .bad
    dec     r12d
    jmp     .l
.ok:
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; exp_node(edi class, esi node) -> rax the plan's record of that node in exp_nodes
exp_node:
    lea     eax, [rdi - 1]
    imul    eax, eax, NUM_NODES
    add     eax, esi
    imul    eax, eax, 24
    lea     rcx, [exp_nodes]
    add     rax, rcx
    ret

; ks_stats_ok(edi ks) -> eax 0 when the two (stat, value) pairs exp_ks lists for the keystone hold
ks_stats_ok:
    push    rbx
    push    r12
    push    r13
    shl     edi, 4
    lea     rbx, [exp_ks]
    add     rbx, rdi
    xor     r12d, r12d
.pair:
    mov     edi, [rbx + r12*8]
    cmp     edi, KS_NONE
    je      .next
    call    rpg_stat
    cmp     eax, [rbx + r12*8 + 4]
    jne     .bad
.next:
    inc     r12d
    cmp     r12d, 2
    jb      .pair
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; clamp_trial(edi stat, esi value) -> eax the stat after the value was put into rpg_stats and
; rpg_clamp_stats ran
clamp_trial:
    push    rbx
    mov     ebx, edi
    lea     rax, [rpg_stats]
    mov     [rax + rbx*4], esi
    call    rpg_clamp_stats
    lea     rax, [rpg_stats]
    mov     eax, [rax + rbx*4]
    pop     rbx
    ret

; cap_row_ok(rdi row) -> eax 0 when rpg_clamp_stats keeps the row's stat inside its limits: 0 and the
; limits themselves stay, a value 1000 beyond a limit comes back to it, and a missing limit (the
; int limits) lets any value through
cap_row_ok:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12d, [rbx]                     ; stat
    mov     r13d, [rbx + 4]                 ; lowest
    mov     edi, r12d
    xor     esi, esi
    call    clamp_trial
    test    eax, eax
    jnz     .bad
    mov     ecx, [rbx + 8]                  ; highest
    cmp     ecx, NOHI
    je      .no_hi
    mov     edi, r12d
    lea     esi, [rcx + 1000]
    call    clamp_trial
    cmp     eax, [rbx + 8]
    jne     .bad
    mov     edi, r12d
    mov     esi, [rbx + 8]
    call    clamp_trial
    cmp     eax, [rbx + 8]
    jne     .bad
    jmp     .lo
.no_hi:
    mov     edi, r12d
    mov     esi, 100000
    call    clamp_trial
    cmp     eax, 100000
    jne     .bad
.lo:
    cmp     r13d, NOLO
    je      .no_lo
    mov     edi, r12d
    lea     esi, [r13 - 1000]
    call    clamp_trial
    cmp     eax, r13d
    jne     .bad
    mov     edi, r12d
    mov     esi, r13d
    call    clamp_trial
    cmp     eax, r13d
    jne     .bad
    jmp     .ok
.no_lo:
    mov     edi, r12d
    mov     esi, -100000
    call    clamp_trial
    cmp     eax, -100000
    jne     .bad
.ok:
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

; a kill that only the quests see (no XP): kill(edi type, esi elite)
%define kill quests_on_kill

; ---- levels, XP, points ----------------------------------------------------------

test_rpg_levels_and_points:
    TEST_BEGIN
    call    reset_all
    ; no class: no XP, and only classes 1..4 can be chosen
    mov     edi, 100
    call    rpg_add_xp
    EXPECT_D R_XP, 0
    EXPECT_B R_LEVEL, 1
    CALL1   rpg_set_class, 0, 0
    CALL1   rpg_set_class, 5, 0
    CALL0   rpg_class, 0
    ; the bar is 20 + 10 * level + level squared, none at the cap
    CALL1   rpg_xp_need, 0, 0
    CALL1   rpg_xp_need, 1, 31
    CALL1   rpg_xp_need, 2, 44
    CALL1   rpg_xp_need, 29, 1151
    CALL1   rpg_xp_need, 49, 2911
    CALL1   rpg_xp_need, 50, 0
    ; Warrior: chosen once, with the kit
    mov     dword [combat_stamina], __float32__(10.0)
    mov     byte [R_RANKS + 3], 2           ; stale extension data: a new class starts from nothing
    mov     word [R_ATTR + ATTR_VIT*2], 5
    mov     byte [rpg_ext + RPGEXT.version], 0
    CALL1   rpg_set_class, CLASS_WARRIOR, 1
    CALL0   rpg_class, CLASS_WARRIOR
    CALL0   rpg_level, 1
    CALL0   rpg_points, 1
    CALL1   rpg_rank, 3, 0
    CALL1   rpg_attr, ATTR_VIT, 0
    EXPECT_B rpg_ext + RPGEXT.version, RPGX_VERSION
    HAVE    IRON_SWORD, 1
    HAVE    COOKED_PORKCHOP, 4
    HAVE    IRON_CHESTPLATE, 0              ; it is worn, not carried
    EXPECT_D inv + INVENTORY.armor + 4, IRON_CHESTPLATE | (1 << 8)
    EXPECT_D surv_max_health, 24
    EXPECT_D combat_stamina, __float32__(120.0) ; resources refilled to the Warrior's maximum
    CALL1   rpg_set_class, CLASS_MAGE, 0
    CALL0   rpg_class, CLASS_WARRIOR
    ; 31 XP is the first level: points follow, health (2 more per level) and stamina are refilled
    mov     dword [surv + SURVIVAL.health], 3
    mov     dword [combat_stamina], __float32__(10.0)
    mov     edi, 31
    call    rpg_add_xp
    CALL0   rpg_level, 2
    EXPECT_D R_XP, 0
    CALL0   rpg_points, 2
    EXPECT_D surv + SURVIVAL.health, 26
    EXPECT_D combat_stamina, __float32__(120.0)
    ; left-over XP carries over: 44 for level 2, 53 given
    mov     edi, 53
    call    rpg_add_xp
    CALL0   rpg_level, 3
    EXPECT_D R_XP, 9
    CALL0   rpg_points, 3
    ; XP for kills of level 1 (x3 for an elite) and for ore, at level 5 where no bar is crossed
    mov     byte [R_LEVEL], 5
    mov     r12d, 1
.kills:
    mov     dword [R_XP], 0
    mov     edi, r12d
    xor     esi, esi
    mov     edx, 1
    call    rpg_on_mob_killed
    lea     rax, [kill_xp_tab]
    movzx   eax, byte [rax + r12 - 1]
    cmp     [R_XP], eax
    jne     .fail
    mov     dword [R_XP], 0
    mov     edi, r12d
    mov     esi, 1
    mov     edx, 1
    call    rpg_on_mob_killed
    lea     rax, [kill_xp_tab]
    movzx   eax, byte [rax + r12 - 1]
    lea     eax, [rax + rax*2]
    cmp     [R_XP], eax
    jne     .fail
    inc     r12d
    cmp     r12d, NUM_MOB_TYPES
    jbe     .kills
    ; a kill is worth (9 + level) / 10 of its XP, rounded down before the elite factor
    mov     dword [R_XP], 0
    mov     edi, MOB_PIG
    xor     esi, esi
    mov     edx, 5
    call    rpg_on_mob_killed
    EXPECT_D R_XP, 2                        ; 2 * 14 / 10
    mov     edi, MOB_PIG
    mov     esi, 1
    mov     edx, 5
    call    rpg_on_mob_killed
    EXPECT_D R_XP, 8                        ; + 3 * 2
    mov     dword [R_XP], 0
    mov     edi, MOB_CREEPER
    xor     esi, esi
    mov     edx, 21
    call    rpg_on_mob_killed
    EXPECT_D R_XP, 45                       ; 15 * 30 / 10
    ; XP_BONUS percent more XP, rounded down: 7 * 150 / 100 = 10
    mov     dword [R_XP], 0
    mov     dword [rpg_stats + STAT_XP_BONUS*4], 50
    mov     edi, 7
    call    rpg_add_xp
    EXPECT_D R_XP, 10
    call    rpg_recompute                   ; the stat is rebuilt: no bonus any more
    mov     dword [R_XP], 0
    mov     edi, 7
    call    rpg_add_xp
    EXPECT_D R_XP, 7
    mov     dword [R_XP], 0
    mov     edi, STONE
    call    rpg_on_block_mined
    EXPECT_D R_XP, 0
    mov     edi, COAL_ORE
    call    rpg_on_block_mined
    EXPECT_D R_XP, 2
    mov     edi, IRON_ORE
    call    rpg_on_block_mined
    EXPECT_D R_XP, 7
    mov     edi, GOLD_ORE
    call    rpg_on_block_mined
    EXPECT_D R_XP, 15
    mov     edi, DIAMOND_ORE
    call    rpg_on_block_mined
    EXPECT_D R_XP, 35
    ; dying costs the bar, not the level
    call    rpg_on_death
    EXPECT_D R_XP, 0
    CALL0   rpg_level, 5
    ; plenty of XP: level 50, no bar left, nothing more is taken
    mov     edi, 100000
    call    rpg_add_xp
    CALL0   rpg_level, 50
    EXPECT_D R_XP, 0
    CALL0   rpg_points, 50
    mov     edi, 500
    call    rpg_add_xp
    CALL0   rpg_level, 50
    EXPECT_D R_XP, 0
    ; level 49 needs 2911: one short stays level 49, the last point makes level 50
    mov     byte [R_LEVEL], 49
    mov     dword [R_XP], 0
    mov     edi, 2910
    call    rpg_add_xp
    CALL0   rpg_level, 49
    EXPECT_D R_XP, 2910
    mov     edi, 1
    call    rpg_add_xp
    CALL0   rpg_level, 50
    EXPECT_D R_XP, 0
    ; rpg_reset starts from nothing as well
    mov     byte [R_RANKS + 3], 2
    mov     word [R_ATTR + ATTR_VIT*2], 5
    mov     byte [rpg_ext + RPGEXT.version], 0
    call    rpg_reset
    CALL1   rpg_rank, 3, 0
    CALL1   rpg_attr, ATTR_VIT, 0
    EXPECT_B rpg_ext + RPGEXT.version, RPGX_VERSION
    ; the other classes' kits, each with its own resources refilled
    call    reset_all
    CALL1   rpg_set_class, CLASS_MAGE, 1
    HAVE    STAFF, 1
    HAVE    MANA_POTION, 2
    HAVE    COOKED_PORKCHOP, 4
    HAVE    IRON_SWORD, 0
    EXPECT_D surv_max_health, 18
    EXPECT_D combat_mana, __float32__(100.0)
    EXPECT_D combat_stamina, __float32__(80.0)
    call    reset_all
    CALL1   rpg_set_class, CLASS_ARCHER, 1
    HAVE    BOW, 1
    HAVE    ARROW, 32
    HAVE    COOKED_PORKCHOP, 4
    call    reset_all
    CALL1   rpg_set_class, CLASS_ROGUE, 1
    HAVE    IRON_DAGGER, 1
    HAVE    HEALTH_POTION, 2
    HAVE    COOKED_PORKCHOP, 4
    EXPECT_D inv + INVENTORY.armor + 4, 0   ; only the Warrior wears a chestplate
    ; a taken chest slot keeps its piece: the new chestplate goes into the bag
    call    reset_all
    mov     dword [inv + INVENTORY.armor + 4], DIAMOND_CHESTPLATE | (1 << 8)
    CALL1   rpg_set_class, CLASS_WARRIOR, 1
    HAVE    IRON_CHESTPLATE, 1
    EXPECT_D inv + INVENTORY.armor + 4, DIAMOND_CHESTPLATE | (1 << 8)
    ; no room at all: the kit falls at the player's feet
    call    reset_all
    lea     rdi, [inv]
    mov     ecx, INV_SLOTS
    mov     eax, COBBLE | (64 << 8)
    rep     stosd
    CALL1   rpg_set_class, CLASS_ROGUE, 1
    HAVE    IRON_DAGGER, 0
    CALL1   find_drop, IRON_DAGGER, 1
    CALL1   find_drop, HEALTH_POTION, 2
    CALL1   find_drop, COOKED_PORKCHOP, 4
    TEST_END

; ---- skill points ------------------------------------------------------------------

test_rpg_skill_spend_rules:
    TEST_BEGIN
    ; without a class nothing can be bought
    xor     edi, edi
    mov     esi, 5
    call    use_class
    CALL1   rpg_can_spend, 0, 5
    CALL1   rpg_spend, 0, 0
    CALL1   rpg_rank, 0, 0
    ; Warrior at level 3: 3 points
    mov     edi, CLASS_WARRIOR
    mov     esi, 3
    call    use_class
    CALL0   rpg_points, 3
    CALL1   rpg_can_spend, 1, 3             ; tier 1 needs level 4
    CALL1   rpg_can_spend, 4, 3             ; tier 4 needs level 22: checked before the previous node
    CALL1   rpg_can_spend, 0, 0             ; tier 0 is free
    CALL1   rpg_can_spend, 6, 0             ; and so is the first node of the next branch
    CALL1   rpg_can_spend, NUM_NODES, 2     ; no such node
    CALL1   rpg_can_spend, 255, 2
    CALL1   rpg_spend, 0, 1
    CALL1   rpg_spend, 0, 1
    CALL1   rpg_spend, 0, 1
    CALL1   rpg_rank, 0, 3
    CALL1   rpg_rank, NUM_NODES, 0
    CALL0   rpg_points, 0
    CALL1   rpg_stat, STAT_MELEE_DMG, 28    ; 10 + 3 * 6
    CALL1   rpg_can_spend, 0, 1             ; no points: checked before everything else
    CALL1   rpg_spend, 6, 0                 ; refused: nothing changes
    CALL1   rpg_rank, 6, 0
    mov     byte [R_LEVEL], 4               ; one point, tier 1 reachable, War Cry's parent unranked
    CALL1   rpg_can_spend, 1, 0
    CALL1   rpg_can_spend, 7, 4
    mov     byte [R_LEVEL], 5               ; two points, Weapon Mastery is at rank 3 of 5
    CALL1   rpg_can_spend, 0, 0
    CALL1   rpg_spend, 0, 1
    CALL1   rpg_spend, 0, 1
    CALL1   rpg_rank, 0, 5
    mov     byte [R_LEVEL], 6               ; a point is left but the node is maxed
    CALL1   rpg_can_spend, 0, 2
    CALL1   rpg_spend, 0, 0
    CALL1   rpg_spend, 1, 1                 ; Precision
    CALL0   rpg_points, 0
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 8   ; 5 + 3
    ; tier 2 needs level 9
    mov     byte [R_LEVEL], 8
    CALL1   rpg_can_spend, 2, 3
    mov     byte [R_LEVEL], 9
    CALL1   rpg_can_spend, 2, 0
    CALL1   rpg_spend, 6, 1                 ; Toughness: +4 health per rank
    EXPECT_D surv_max_health, 44            ; 24 + 2 * 8 + 4
    CALL1   rpg_stat, STAT_MAX_HEALTH, 44
    ; War Cry (node 7): an ability, one rank, unlocks slot 1
    CALL1   rpg_ability_unlocked, 0, 1
    CALL1   rpg_ability_unlocked, 1, 0
    CALL1   rpg_can_spend, 7, 0
    CALL1   rpg_spend, 7, 1
    CALL1   rpg_can_spend, 7, 2
    CALL1   rpg_ability_unlocked, 1, 1
    CALL1   rpg_ability_unlocked, 2, 0
    CALL1   rpg_stat, STAT_MAX_HEALTH, 44   ; an ability adds no stat
    ; Whirlwind (node 9): level 15 and Iron Skin (node 8)
    mov     byte [R_LEVEL], 14
    CALL1   rpg_can_spend, 9, 3
    mov     byte [R_LEVEL], 15
    CALL1   rpg_can_spend, 9, 4
    CALL1   rpg_spend, 8, 1
    CALL1   rpg_stat, STAT_ARMOR_BONUS, 1
    CALL1   rpg_can_spend, 9, 0
    CALL1   rpg_spend, 9, 1
    CALL1   rpg_ability_unlocked, 2, 1
    CALL1   rpg_ability_unlocked, 3, 0
    ; Ground Slam (node 15, slot 3) follows Stamina, Second Wind and Riposte of the third branch
    CALL1   rpg_can_spend, 15, 4
    CALL1   rpg_spend, 12, 1
    CALL1   rpg_spend, 13, 1
    CALL1   rpg_spend, 14, 1
    CALL1   rpg_stat, STAT_PARRY_WINDOW, 1
    CALL1   rpg_can_spend, 15, 0
    CALL1   rpg_spend, 15, 1
    CALL1   rpg_ability_unlocked, 3, 1
    CALL1   rpg_ability_unlocked, 4, 0      ; there is no fifth slot
    ; points = level - ranks: 15 - (5 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1) = 1
    CALL0   rpg_points, 1
    CALL1   rpg_can_spend, 5, 3             ; a keystone asks for level 30
    mov     byte [R_LEVEL], 21              ; Shield Wall (node 10, tier 4) asks for level 22
    CALL1   rpg_can_spend, 10, 3
    mov     byte [R_LEVEL], 22
    CALL1   rpg_can_spend, 10, 0
    TEST_END

; ---- derived stats and the description tables --------------------------------------

test_rpg_stats_from_class_and_ranks:
    TEST_BEGIN
    call    reset_all
    ; no class: the base character
    CALL1   rpg_stat, STAT_MAX_HEALTH, 20
    CALL1   rpg_stat, STAT_MAX_STAMINA, 100
    CALL1   rpg_stat, STAT_MAX_MANA, 0
    CALL1   rpg_stat, NUM_STATS, 0          ; unknown stat
    EXPECT_D surv_max_health, 20
    ; Rogue of level 5: Backstab 100, +20 per rank of node 0, 2 health per level above the first
    mov     edi, CLASS_ROGUE
    mov     esi, 5
    call    use_class
    CALL1   rpg_stat, STAT_BACKSTAB, 100
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 10
    CALL1   rpg_stat, STAT_MAX_STAMINA, 110
    CALL1   rpg_stat, STAT_STAMINA_REGEN, 10
    CALL1   rpg_stat, STAT_MAX_HEALTH, 28
    EXPECT_D surv_max_health, 28
    mov     byte [R_RANKS + 0], 2
    call    rpg_recompute
    CALL1   rpg_stat, STAT_BACKSTAB, 140
    CALL1   rpg_stat, STAT_MOVE_SPEED, 5
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 10
    EXPECT_D surv_max_health, 28
    ; the caps, reached with absurd ranks: crit chance 75, bleed chance 100, move speed 50 and
    ; dodge cost 75
    mov     byte [R_RANKS + 1], 100         ; Precision, +3 crit chance
    mov     byte [R_RANKS + 3], 100         ; Serrated, +8 bleed chance
    mov     byte [R_RANKS + 6], 100         ; Fleet Foot, +3 move speed
    mov     byte [R_RANKS + 8], 100         ; Evasion, +10 dodge cost
    call    rpg_recompute
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 75
    CALL1   rpg_stat, STAT_BLEED_CHANCE, 100
    CALL1   rpg_stat, STAT_MOVE_SPEED, 50
    CALL1   rpg_stat, STAT_DODGE_COST, 75
    ; every row of the plan's limits (the percentage caps, move speed, the resistances, the crit
    ; damage and element damage floors), both sides, and a stat without limits
    xor     r12d, r12d
.cap:
    imul    eax, r12d, 12
    lea     rdi, [exp_caps]
    add     rdi, rax
    call    cap_row_ok
    test    eax, eax
    jnz     .fail
    inc     r12d
    cmp     r12d, (exp_caps_end - exp_caps) / 12
    jb      .cap
    mov     edi, STAT_MELEE_DMG
    mov     esi, 100000
    call    clamp_trial
    cmp     eax, 100000
    jne     .fail
    mov     edi, STAT_ADD_FIRE
    mov     esi, -5
    call    clamp_trial
    cmp     eax, -5
    jne     .fail
    ; Mage: 100 mana, node 6 (Deep Mind) adds 15 per rank
    mov     edi, CLASS_MAGE
    mov     esi, 5
    call    use_class
    CALL1   rpg_stat, STAT_MAX_MANA, 100
    CALL1   rpg_stat, STAT_MANA_REGEN, 4
    CALL1   rpg_stat, STAT_SPELL_DMG, 10
    CALL1   rpg_stat, STAT_MAX_STAMINA, 80
    EXPECT_D surv_max_health, 26
    mov     byte [R_RANKS + 6], 3
    call    rpg_recompute
    CALL1   rpg_stat, STAT_MAX_MANA, 145
    mov     byte [R_RANKS + 7], 1           ; Blink: no stat of its own
    call    rpg_recompute
    CALL1   rpg_stat, STAT_MAX_MANA, 145
    CALL1   rpg_stat, STAT_MANA_REGEN, 4
    mov     byte [R_RANKS + 10], 100        ; Haste: cooldowns capped at 50
    mov     byte [R_RANKS + 14], 100        ; Arcane Reach: area capped at 100
    call    rpg_recompute
    CALL1   rpg_stat, STAT_COOLDOWN_RED, 50
    CALL1   rpg_stat, STAT_AREA, 100
    mov     byte [R_RANKS + 10], 0
    mov     byte [R_RANKS + 14], 0
    call    rpg_recompute
    ; mana and stamina never stay above their maxima, but are not raised
    mov     dword [combat_mana], __float32__(500.0)
    mov     dword [combat_stamina], __float32__(500.0)
    call    rpg_recompute
    EXPECT_D combat_mana, __float32__(145.0)
    EXPECT_D combat_stamina, __float32__(80.0)
    mov     dword [combat_mana], __float32__(50.0)
    call    rpg_recompute
    EXPECT_D combat_mana, __float32__(50.0)
    ; Warrior of level 5: 24 + 8 health (published), clamped when it is higher; Toughness +4 per rank
    mov     edi, CLASS_WARRIOR
    mov     esi, 5
    call    use_class
    CALL1   rpg_stat, STAT_MELEE_DMG, 10
    CALL1   rpg_stat, STAT_MAX_STAMINA, 120
    EXPECT_D surv_max_health, 32
    mov     dword [surv + SURVIVAL.health], 40
    call    rpg_recompute
    EXPECT_D surv + SURVIVAL.health, 32
    mov     byte [R_RANKS + 6], 2
    call    rpg_recompute
    EXPECT_D surv_max_health, 40
    EXPECT_D surv + SURVIVAL.health, 32
    mov     byte [R_RANKS + 10], 3          ; Shield Wall: block cost, capped at 75
    call    rpg_recompute
    CALL1   rpg_stat, STAT_BLOCK_COST, 30
    mov     byte [R_RANKS + 10], 100
    call    rpg_recompute
    CALL1   rpg_stat, STAT_BLOCK_COST, 75
    ; Archer: Quiver (node 8) saves arrows, capped at 75
    mov     edi, CLASS_ARCHER
    mov     esi, 5
    call    use_class
    CALL1   rpg_stat, STAT_RANGED_DMG, 15
    CALL1   rpg_stat, STAT_ARROW_SAVE, 10
    mov     byte [R_RANKS + 8], 3
    call    rpg_recompute
    CALL1   rpg_stat, STAT_ARROW_SAVE, 40
    mov     byte [R_RANKS + 8], 100
    call    rpg_recompute
    CALL1   rpg_stat, STAT_ARROW_SAVE, 75
    ; ability slots: slot 0 needs a class, slots 1..3 their node (7, 9, 15), there is no slot 4
    mov     edi, CLASS_NONE
    mov     esi, 5
    call    use_class
    CALL1   rpg_ability_unlocked, 0, 0
    mov     edi, CLASS_MAGE
    mov     esi, 5
    call    use_class
    CALL1   rpg_ability_unlocked, 0, 1
    CALL1   rpg_ability_unlocked, 1, 0
    CALL1   rpg_ability_unlocked, 2, 0
    CALL1   rpg_ability_unlocked, 3, 0
    mov     byte [R_RANKS + 9], 1
    CALL1   rpg_ability_unlocked, 2, 1
    CALL1   rpg_ability_unlocked, 1, 0
    CALL1   rpg_ability_unlocked, 3, 0
    mov     byte [R_RANKS + 15], 1
    CALL1   rpg_ability_unlocked, 3, 1
    mov     byte [R_RANKS + 7], 1
    CALL1   rpg_ability_unlocked, 1, 1
    CALL1   rpg_ability_unlocked, 4, 0
    ; the description tables: names, a skill's text, abilities, branches
    mov     edi, CLASS_WARRIOR
    call    rpg_class_info
    mov     rdi, [rax + 0]
    lea     rsi, [s_warrior]
    call    str_eq
    test    eax, eax
    jz      .fail
    mov     edi, CLASS_WARRIOR
    call    rpg_class_info
    mov     rax, [rax + 8]                  ; line 1
    STR_IS  s_heavy
    mov     edi, CLASS_MAGE
    call    rpg_class_info
    mov     rax, [rax]
    STR_IS  s_mage
    mov     edi, CLASS_ARCHER
    call    rpg_class_info
    mov     rax, [rax]
    STR_IS  s_archer
    mov     edi, CLASS_ROGUE
    call    rpg_class_info
    mov     rax, [rax]
    STR_IS  s_rogue
    mov     edi, CLASS_ROGUE
    mov     esi, 2
    call    rpg_branch_name
    STR_IS  s_agility
    mov     edi, CLASS_MAGE
    mov     esi, 6
    call    rpg_node_info
    mov     r14, rax
    mov     rax, [r14 + NODEINFO.name]
    STR_IS  s_deepmind
    cmp     qword [r14 + NODEINFO.desc], 0  ; a stat node's text is its formatted value
    jne     .fail
    cmp     byte [r14 + NODEINFO.kind], NODE_STAT
    jne     .fail
    cmp     byte [r14 + NODEINFO.stat], STAT_MAX_MANA
    jne     .fail
    cmp     byte [r14 + NODEINFO.max], 5
    jne     .fail
    cmp     dword [r14 + NODEINFO.value], 15
    jne     .fail
    FMT_IS  STAT_MAX_MANA, 15, s_f_mana15
    mov     edi, CLASS_MAGE
    mov     esi, 2
    call    rpg_ability_info
    cmp     dword [rax + ABILINFO.resource], RES_MANA
    jne     .fail
    cmp     dword [rax + ABILINFO.cost], 70
    jne     .fail
    cmp     dword [rax + ABILINFO.cooldown], 40
    jne     .fail
    mov     edi, CLASS_ROGUE
    xor     esi, esi
    call    rpg_ability_info
    cmp     dword [rax + ABILINFO.resource], RES_STAMINA
    jne     .fail
    cmp     dword [rax + ABILINFO.cost], 25
    jne     .fail
    cmp     dword [rax + ABILINFO.cooldown], 8
    jne     .fail
    ; no class / out of range: an empty record, never a null pointer
    xor     edi, edi
    xor     esi, esi
    call    rpg_node_info
    test    rax, rax
    jz      .fail
    mov     rax, [rax + NODEINFO.name]
    STR_IS  s_empty
    mov     edi, CLASS_WARRIOR
    mov     esi, NUM_NODES
    call    rpg_node_info
    mov     rax, [rax + NODEINFO.desc]
    STR_IS  s_empty
    mov     edi, CLASS_WARRIOR
    mov     esi, NUM_ABILITY_SLOTS
    call    rpg_ability_info
    test    rax, rax
    jz      .fail
    mov     rax, [rax + ABILINFO.name]
    STR_IS  s_empty
    ; the HUD and skill-screen icon of each ability slot follows the current class
    mov     edi, CLASS_ARCHER
    mov     esi, 1
    call    use_class
    CALL1   rpg_ability_tile, 0, TILE_ABILITY0 + 6
    CALL1   rpg_ability_tile, 2, TILE_ABILITY0 + 8
    CALL1   rpg_ability_tile, 3, TILE_ABILITY3_0 + 2
    CALL1   rpg_ability_tile, NUM_ABILITY_SLOTS, 0
    call    reset_all
    CALL1   rpg_ability_tile, 0, 0              ; no class, no icon
    ; every class, node by node, as the plan lists them: name, kind, stat / slot / keystone id,
    ; max rank (5, or 1 for abilities and keystones), value, and the text: none for a stat node, the
    ; ability's own for an ability, the keystone's description for a keystone
    mov     r12d, 1
.cls:
    xor     r13d, r13d
.node:
    mov     edi, r12d
    mov     esi, r13d
    call    rpg_node_info
    mov     r14, rax
    mov     edi, r12d
    mov     esi, r13d
    call    exp_node
    mov     rdi, [r14 + NODEINFO.name]
    mov     rsi, [rax]
    call    str_eq
    test    eax, eax
    jz      .fail
    mov     edi, r12d
    mov     esi, r13d
    call    exp_node
    movzx   edx, byte [rax + 16]            ; code
    movzx   ecx, byte [rax + 17]            ; value
    mov     rax, [rax + 8]                  ; text: 0 unless a keystone
    cmp     edx, 0xC0
    jae     .exp_keystone
    cmp     edx, 0x80
    jae     .exp_ability
    cmp     byte [r14 + NODEINFO.kind], NODE_STAT
    jne     .fail
    cmp     [r14 + NODEINFO.stat], dl
    jne     .fail
    cmp     [r14 + NODEINFO.value], ecx
    jne     .fail
    cmp     byte [r14 + NODEINFO.max], 5
    jne     .fail
    cmp     qword [r14 + NODEINFO.desc], 0
    jne     .fail
    jmp     .next_node
.exp_ability:
    and     edx, 3                          ; slot
    cmp     byte [r14 + NODEINFO.kind], NODE_ABILITY
    jne     .fail
    cmp     [r14 + NODEINFO.stat], dl
    jne     .fail
    cmp     byte [r14 + NODEINFO.max], 1
    jne     .fail
    cmp     dword [r14 + NODEINFO.value], 0
    jne     .fail
    mov     edi, r12d
    mov     esi, edx
    call    rpg_ability_info                ; the node shares the ability's name and text
    mov     rcx, [rax + ABILINFO.name]
    cmp     rcx, [r14 + NODEINFO.name]
    jne     .fail
    mov     rcx, [rax + ABILINFO.desc]
    cmp     rcx, [r14 + NODEINFO.desc]
    jne     .fail
    jmp     .next_node
.exp_keystone:
    and     edx, 0x3F                       ; keystone id
    cmp     byte [r14 + NODEINFO.kind], NODE_KEYSTONE
    jne     .fail
    cmp     [r14 + NODEINFO.stat], dl
    jne     .fail
    cmp     byte [r14 + NODEINFO.max], 1
    jne     .fail
    cmp     dword [r14 + NODEINFO.value], 0
    jne     .fail
    mov     rdi, [r14 + NODEINFO.desc]
    mov     rsi, rax
    call    str_eq
    test    eax, eax
    jz      .fail
.next_node:
    inc     r13d
    cmp     r13d, NUM_NODES
    jb      .node
    inc     r12d
    cmp     r12d, NUM_CLASSES
    jbe     .cls
    ; the plan's ability table: resource, cost and cooldown of every ability
    mov     r12d, 1
.acls:
    xor     r13d, r13d
.aslot:
    mov     edi, r12d
    mov     esi, r13d
    call    rpg_ability_info
    mov     r14, rax
    lea     eax, [r12 - 1]
    lea     eax, [r13 + rax*4]
    lea     rax, [rax + rax*2]              ; 3 bytes per entry
    lea     rcx, [exp_abil]
    add     rcx, rax
    movzx   eax, byte [rcx]
    cmp     [r14 + ABILINFO.resource], eax
    jne     .fail
    movzx   eax, byte [rcx + 1]
    cmp     [r14 + ABILINFO.cost], eax
    jne     .fail
    movzx   eax, byte [rcx + 2]
    cmp     [r14 + ABILINFO.cooldown], eax
    jne     .fail
    mov     rax, [r14 + ABILINFO.name]
    cmp     byte [rax], 0
    je      .fail
    mov     rax, [r14 + ABILINFO.desc]
    cmp     byte [rax], 0
    je      .fail
    inc     r13d
    cmp     r13d, NUM_ABILITY_SLOTS
    jb      .aslot
    inc     r12d
    cmp     r12d, NUM_CLASSES
    jbe     .acls
    ; the plan's stat table: label, format, icon and the text of a value
    xor     r12d, r12d
.stat:
    mov     edi, r12d
    call    rpg_stat_info
    mov     r14, rax
    imul    eax, r12d, 24
    lea     r13, [exp_stats]
    add     r13, rax
    mov     rdi, [r14 + STATINFO.label]
    mov     rsi, [r13]
    call    str_eq
    test    eax, eax
    jz      .fail
    movzx   eax, byte [r13 + 16]
    cmp     [r14 + STATINFO.fmt], al
    jne     .fail
    movzx   eax, byte [r13 + 17]
    cmp     [r14 + STATINFO.icon], al
    jne     .fail
    mov     edi, r12d
    mov     esi, 7
    lea     rdx, [fmt_buf]
    call    rpg_format_stat
    lea     rcx, [fmt_buf]
    cmp     rax, rcx
    jne     .fail
    mov     rdi, rax
    mov     rsi, [r13 + 8]
    call    str_eq
    test    eax, eax
    jz      .fail
    inc     r12d
    cmp     r12d, NUM_STATS
    jb      .stat
    mov     edi, NUM_STATS                  ; out of range: an empty record, never null
    call    rpg_stat_info
    test    rax, rax
    jz      .fail
    mov     rax, [rax + STATINFO.label]
    STR_IS  s_empty
    ; signs, reductions stored positive, tenths
    FMT_IS  STAT_COOLDOWN_RED, -3, s_f_cd_neg
    FMT_IS  STAT_MOVE_SPEED, -15, s_f_move_neg
    FMT_IS  STAT_LIFE_REGEN, 25, s_f_regen_25
    FMT_IS  STAT_LIFE_REGEN, -5, s_f_regen_neg
    FMT_IS  STAT_MAX_HEALTH, 0, s_f_zero
    ; the attribute texts
    xor     edi, edi
    call    rpg_attr_info
    STR_IS  s_strength
    mov     edi, ATTR_DEX
    call    rpg_attr_info
    STR_IS  s_dexterity
    mov     edi, ATTR_INT
    call    rpg_attr_info
    STR_IS  s_intelligence
    mov     edi, ATTR_VIT
    call    rpg_attr_info
    STR_IS  s_vitality
    mov     edi, NUM_ATTRS
    call    rpg_attr_info
    STR_IS  s_empty
    xor     edi, edi
    call    rpg_attr_desc
    STR_IS  s_str_fx
    mov     edi, ATTR_DEX
    call    rpg_attr_desc
    STR_IS  s_dex_fx
    mov     edi, ATTR_INT
    call    rpg_attr_desc
    STR_IS  s_int_fx
    mov     edi, ATTR_VIT
    call    rpg_attr_desc
    STR_IS  s_vit_fx
    mov     edi, NUM_ATTRS
    call    rpg_attr_desc
    STR_IS  s_empty
    TEST_END

; ---- attributes and respec ----------------------------------------------------------

test_rpg_attributes_and_respec:
    TEST_BEGIN
    mov     edi, CLASS_WARRIOR
    mov     esi, 1
    call    use_class                       ; level 1: no attribute points yet
    CALL0   rpg_attr_points, 0
    CALL1   rpg_spend_attr, ATTR_STR, 0
    CALL1   rpg_attr, ATTR_STR, 0
    ; level 2 (31 XP) pays 3 points; 3 Strength: +3 melee damage and stamina
    mov     edi, 31
    call    rpg_add_xp
    CALL0   rpg_level, 2
    CALL0   rpg_attr_points, 3
    CALL1   rpg_spend_attr, NUM_ATTRS, 0    ; no such attribute: nothing is spent
    CALL0   rpg_attr_points, 3
    mov     edi, ATTR_STR
    mov     esi, 3
    call    spend_n
    test    eax, eax
    jnz     .fail
    CALL1   rpg_attr, ATTR_STR, 3
    CALL1   rpg_attr, NUM_ATTRS, 0
    CALL0   rpg_attr_points, 0
    CALL1   rpg_spend_attr, ATTR_STR, 0     ; nothing left
    CALL1   rpg_attr, ATTR_STR, 3
    CALL1   rpg_stat, STAT_MELEE_DMG, 13
    CALL1   rpg_stat, STAT_MAX_STAMINA, 123
    CALL1   rpg_stat, STAT_MAX_HEALTH, 26   ; 24 + 2 for the level, Strength adds none
    EXPECT_D surv_max_health, 26
    ; level 10 has paid 27 points, 3 are spent: 12 Dexterity, 10 Intelligence and 2 Vitality use
    ; the other 24
    mov     byte [R_LEVEL], 10
    call    rpg_recompute
    CALL0   rpg_attr_points, 24
    mov     edi, ATTR_DEX
    mov     esi, 12
    call    spend_n
    test    eax, eax
    jnz     .fail
    mov     edi, ATTR_INT
    mov     esi, 10
    call    spend_n
    test    eax, eax
    jnz     .fail
    mov     edi, ATTR_VIT
    mov     esi, 2
    call    spend_n
    test    eax, eax
    jnz     .fail
    CALL0   rpg_attr_points, 0
    CALL1   rpg_stat, STAT_RANGED_DMG, 12
    CALL1   rpg_stat, STAT_ATTACK_SPEED, 4          ; 12 / 3
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 7           ; 5 + 12 / 5
    CALL1   rpg_stat, STAT_SPELL_DMG, 10
    CALL1   rpg_stat, STAT_MAX_MANA, 20
    CALL1   rpg_stat, STAT_MANA_REGEN, 1            ; 10 / 10
    CALL1   rpg_stat, STAT_MAX_HEALTH, 44           ; 24 + 18 + 2
    CALL1   rpg_stat, STAT_STAMINA_REGEN, 2
    CALL1   rpg_stat, STAT_MELEE_DMG, 13
    ; the divisions round down
    mov     word [R_ATTR + ATTR_DEX*2], 14
    mov     word [R_ATTR + ATTR_INT*2], 9
    call    rpg_recompute
    CALL1   rpg_stat, STAT_ATTACK_SPEED, 4          ; 14 / 3
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 7           ; 5 + 14 / 5
    CALL1   rpg_stat, STAT_MANA_REGEN, 0            ; 9 / 10
    mov     word [R_ATTR + ATTR_DEX*2], 15
    mov     word [R_ATTR + ATTR_INT*2], 10
    call    rpg_recompute
    CALL1   rpg_stat, STAT_ATTACK_SPEED, 5
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 8
    CALL1   rpg_stat, STAT_MANA_REGEN, 1
    mov     word [R_ATTR + ATTR_DEX*2], 12
    call    rpg_recompute
    ; two ranks of Weapon Mastery to hand back as well
    CALL1   rpg_spend, 0, 1
    CALL1   rpg_spend, 0, 1
    CALL1   rpg_stat, STAT_MELEE_DMG, 25            ; 10 + 3 + 2 * 6
    CALL0   rpg_respec_cost, 50
    ; 49 coins are one short: nothing happens
    ADD     GOLD_COIN, 49
    CALL0   rpg_respec, 0
    HAVE    GOLD_COIN, 49
    CALL1   rpg_rank, 0, 2
    CALL1   rpg_attr, ATTR_DEX, 12
    ADD     GOLD_COIN, 11
    CALL0   rpg_respec, 1
    HAVE    GOLD_COIN, 10
    CALL1   rpg_rank, 0, 0
    CALL1   rpg_attr, ATTR_STR, 0
    CALL1   rpg_attr, ATTR_DEX, 0
    CALL1   rpg_attr, ATTR_INT, 0
    CALL1   rpg_attr, ATTR_VIT, 0
    CALL0   rpg_points, 10
    CALL0   rpg_attr_points, 27
    CALL1   rpg_stat, STAT_MELEE_DMG, 10
    CALL1   rpg_stat, STAT_MAX_HEALTH, 42
    EXPECT_D surv_max_health, 42
    ; without a class there is nothing to hand back, and the coins stay
    xor     edi, edi
    mov     esi, 10
    call    use_class
    ADD     GOLD_COIN, 100
    CALL0   rpg_respec, 0
    HAVE    GOLD_COIN, 100
    ; the attribute points survive the header ...
    mov     edi, CLASS_WARRIOR
    mov     esi, 10
    call    use_class
    mov     edi, ATTR_STR
    mov     esi, 4
    call    spend_n
    test    eax, eax
    jnz     .fail
    mov     edi, ATTR_VIT
    mov     esi, 6
    call    spend_n
    test    eax, eax
    jnz     .fail
    lea     rdi, [world_header]
    call    rpg_save
    cmp     word [HDRX + RPGEXT.attr + ATTR_STR*2], 4
    jne     .fail
    cmp     word [HDRX + RPGEXT.attr + ATTR_VIT*2], 6
    jne     .fail
    EXPECT_B HDRX + RPGEXT.version, RPGX_VERSION
    call    rpg_reset
    CALL1   rpg_attr, ATTR_STR, 0
    call    hdr_load
    CALL0   rpg_class, CLASS_WARRIOR
    CALL1   rpg_attr, ATTR_STR, 4
    CALL1   rpg_attr, ATTR_VIT, 6
    CALL1   rpg_attr, ATTR_DEX, 0
    CALL0   rpg_attr_points, 17
    CALL1   rpg_stat, STAT_MELEE_DMG, 14            ; 10 + 4
    CALL1   rpg_stat, STAT_MAX_HEALTH, 48           ; 24 + 18 + 6
    ; ... and a header that spent more than the 27 the level paid loses them all
    mov     word [HDRX + RPGEXT.attr + ATTR_DEX*2], 18
    call    hdr_load
    CALL1   rpg_attr, ATTR_STR, 0
    CALL1   rpg_attr, ATTR_DEX, 0
    CALL1   rpg_attr, ATTR_VIT, 0
    CALL0   rpg_attr_points, 27
    mov     word [HDRX + RPGEXT.attr + ATTR_DEX*2], 17      ; exactly 27 is fine
    call    hdr_load
    CALL1   rpg_attr, ATTR_STR, 4
    CALL1   rpg_attr, ATTR_DEX, 17
    CALL1   rpg_attr, ATTR_VIT, 6
    CALL0   rpg_attr_points, 0
    TEST_END

; ---- keystones and caps ---------------------------------------------------------------

test_rpg_keystones_and_caps:
    TEST_BEGIN
    ; Warrior of level 30: ranks 0..4 of the first branch, then its keystone
    mov     edi, CLASS_WARRIOR
    mov     esi, 30
    call    use_class
    xor     r12d, r12d
.b0:
    mov     edi, r12d
    call    rpg_spend
    cmp     eax, 1
    jne     .fail
    inc     r12d
    cmp     r12d, 5
    jb      .b0
    CALL1   rpg_keystone, KS_EXECUTIONER, 0
    CALL1   rpg_can_spend, 5, 0
    CALL1   rpg_spend, 5, 1
    CALL1   rpg_keystone, KS_EXECUTIONER, 1
    CALL1   rpg_keystone, KS_JUGGERNAUT, 0
    CALL1   rpg_keystone, 12, 0                     ; there are 12 keystones
    CALL1   rpg_can_spend, 5, 2                     ; one rank only
    EXPECT_D rpg_keystones, 1 << KS_EXECUTIONER
    ; the Juggernaut path (nodes 6..11): the keystone asks for level 30
    mov     byte [R_LEVEL], 29
    mov     r12d, 6
.b1:
    mov     edi, r12d
    call    rpg_spend
    cmp     eax, 1
    jne     .fail
    inc     r12d
    cmp     r12d, 11
    jb      .b1
    CALL1   rpg_can_spend, 11, 3
    mov     byte [R_LEVEL], 30
    CALL1   rpg_can_spend, 11, 0
    CALL1   rpg_spend, 11, 1
    CALL1   rpg_keystone, KS_JUGGERNAUT, 1
    EXPECT_D rpg_keystones, (1 << KS_EXECUTIONER) | (1 << KS_JUGGERNAUT)
    CALL1   rpg_stat, STAT_ARMOR_BONUS, 5           ; Iron Skin 1 + 4
    CALL1   rpg_stat, STAT_MOVE_SPEED, -15
    ; 400 Dexterity: crit chance and attack speed are capped
    mov     word [R_ATTR + ATTR_DEX*2], 400
    call    rpg_recompute
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 75
    CALL1   rpg_stat, STAT_ATTACK_SPEED, 100
    ; every keystone on its own: its bit and no other, and its stat changes
    mov     r12d, 1                                 ; class
.class:
    xor     r13d, r13d                              ; branch
.branch:
    mov     edi, r12d
    mov     esi, 30
    call    use_class
    imul    eax, r13d, NODES_PER_BRANCH
    lea     rdx, [R_RANKS]
    mov     byte [rdx + rax + NODES_PER_BRANCH - 1], 1
    call    rpg_recompute
    lea     eax, [r12 - 1]
    lea     r14d, [rax + rax*2]
    add     r14d, r13d                              ; keystone id
    mov     eax, 1
    mov     ecx, r14d
    shl     eax, cl
    cmp     [rpg_keystones], eax
    jne     .fail
    mov     edi, r14d
    call    rpg_keystone
    cmp     eax, 1
    jne     .fail
    mov     edi, r14d
    call    ks_stats_ok
    test    eax, eax
    jnz     .fail
    inc     r13d
    cmp     r13d, 3
    jb      .branch
    inc     r12d
    cmp     r12d, NUM_CLASSES
    jbe     .class
    ; a header of version 0 (a save from before the trees changed) with a class: ranks and
    ; attribute points are refunded, the version is set
    mov     edi, CLASS_MAGE
    mov     esi, 12
    call    hdr_set
    mov     byte [HDRX + RPGEXT.version], 0
    mov     byte [HDRX + RPGEXT.ranks + 0], 3
    mov     byte [HDRX + RPGEXT.ranks + 6], 1
    mov     word [HDRX + RPGEXT.attr + ATTR_INT*2], 5
    call    hdr_load
    CALL0   rpg_class, CLASS_MAGE
    EXPECT_B R_RANKS + 0, 0
    EXPECT_B R_RANKS + 6, 0
    CALL1   rpg_attr, ATTR_INT, 0
    EXPECT_B rpg_ext + RPGEXT.version, RPGX_VERSION
    CALL0   rpg_points, 12
    CALL0   rpg_attr_points, 33
    mov     byte [HDRX + RPGEXT.version], RPGX_VERSION      ; the same header at version 1 keeps them
    call    hdr_load
    EXPECT_B R_RANKS + 0, 3
    EXPECT_B R_RANKS + 6, 1
    CALL1   rpg_attr, ATTR_INT, 5
    ; no class and version 0 is simply a new character
    xor     edi, edi
    mov     esi, 12
    call    hdr_set
    mov     byte [HDRX + RPGEXT.version], 0
    call    hdr_load
    CALL0   rpg_class, CLASS_NONE
    CALL0   rpg_level, 1
    EXPECT_B rpg_ext + RPGEXT.version, RPGX_VERSION
    ; the bar of the levels and the XP of a level 11 kill: 10 * (9 + 11) / 10 = 20, an elite 60
    CALL1   rpg_xp_need, 1, 31
    CALL1   rpg_xp_need, 2, 44
    CALL1   rpg_xp_need, 49, 2911
    CALL1   rpg_xp_need, 50, 0
    mov     edi, CLASS_WARRIOR
    mov     esi, 5
    call    use_class
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    mov     edx, 11
    call    rpg_on_mob_killed
    EXPECT_D R_XP, 20
    mov     dword [R_XP], 0
    mov     edi, MOB_ZOMBIE
    mov     esi, 1
    mov     edx, 11
    call    rpg_on_mob_killed
    EXPECT_D R_XP, 60
    ; LIFE_ON_KILL heals the killer
    mov     dword [rpg_stats + STAT_LIFE_ON_KILL*4], 3
    mov     dword [surv + SURVIVAL.health], 5
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    mov     edx, 1
    call    rpg_on_mob_killed
    EXPECT_D surv + SURVIVAL.health, 8
    TEST_END

; ---- save and load -----------------------------------------------------------------

; hdr_set(edi class, esi level): the header's RPG records are all zero but class, level and the
; extension's version
hdr_set:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    lea     rdi, [HDR]
    mov     ecx, RPGSAVE_size
    xor     eax, eax
    rep     stosb
    lea     rdi, [HDRX]
    mov     ecx, RPGEXT_size
    xor     eax, eax
    rep     stosb
    mov     [HDR + RPGSAVE.class], bl
    mov     [HDR + RPGSAVE.level], r12b
    mov     byte [HDRX + RPGEXT.version], RPGX_VERSION
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hdr_load(): rpg_load(&world_header)
hdr_load:
    push    rbp
    mov     rbp, rsp
    lea     rdi, [world_header]
    call    rpg_load
    pop     rbp
    ret

test_rpg_save_load_validates:
    TEST_BEGIN
    ; a full round trip through the header
    mov     edi, CLASS_ARCHER
    mov     esi, 7
    call    use_class
    mov     dword [R_XP], 55
    mov     byte [R_RANKS + 0], 2           ; Steady Aim
    mov     byte [R_RANKS + 1], 1           ; Eagle Eye, which needs it
    mov     byte [R_RANKS + 6], 1           ; Fleet Foot
    mov     byte [R_QUEST], 3
    mov     byte [R_QSTATE], 1
    mov     word [R_QPROG], 2
    mov     byte [R_CLEARED], 5
    mov     byte [R_FLAGS], 1
    lea     rdi, [world_header]
    call    rpg_save
    EXPECT_B HDR + RPGSAVE.class, CLASS_ARCHER
    EXPECT_B HDR + RPGSAVE.level, 7
    EXPECT_D HDR + RPGSAVE.xp, 55
    EXPECT_B HDRX + RPGEXT.ranks + 1, 1
    EXPECT_B HDRX + RPGEXT.version, RPGX_VERSION
    EXPECT_B HDR + RPGSAVE.cleared, 5
    call    rpg_reset
    CALL0   rpg_class, CLASS_NONE
    call    hdr_load
    CALL0   rpg_class, CLASS_ARCHER
    CALL0   rpg_level, 7
    EXPECT_D R_XP, 55
    EXPECT_B R_RANKS + 0, 2
    EXPECT_B R_RANKS + 1, 1
    EXPECT_B R_RANKS + 6, 1
    EXPECT_B R_RANKS + 2, 0
    EXPECT_B R_QUEST, 3
    EXPECT_B R_QSTATE, 1
    cmp     word [R_QPROG], 2
    jne     .fail
    EXPECT_B R_CLEARED, 5
    EXPECT_B R_FLAGS, 1
    CALL1   rpg_stat, STAT_RANGED_DMG, 27   ; stats are recomputed: 15 + 2 * 6
    CALL1   rpg_stat, STAT_MOVE_SPEED, 8    ; Fleet Foot rank 1: 5 + 3
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 11  ; 8 + 3
    ; ranks of 3 everywhere at level 5: more than the level, and past an ability's max
    mov     edi, CLASS_ARCHER
    mov     esi, 5
    call    hdr_set
    lea     rdi, [HDRX + RPGEXT.ranks]
    mov     ecx, NUM_NODES
    mov     al, 3
    rep     stosb
    call    hdr_load
    CALL0   rpg_class, CLASS_ARCHER
    CALL0   rpg_level, 5
    cmp     qword [R_RANKS], 0
    jne     .fail
    cmp     qword [R_RANKS + 8], 0
    jne     .fail
    cmp     word [R_RANKS + 16], 0
    jne     .fail
    CALL1   rpg_stat, STAT_RANGED_DMG, 15
    ; an unknown class means no class at all
    mov     edi, 9
    mov     esi, 5
    call    hdr_set
    call    hdr_load
    CALL0   rpg_class, CLASS_NONE
    CALL0   rpg_level, 1
    ; zeros (an old save) are a class-less level 1 even when the level byte says otherwise
    xor     edi, edi
    mov     esi, 10
    call    hdr_set
    call    hdr_load
    CALL0   rpg_class, CLASS_NONE
    CALL0   rpg_level, 1
    ; a level outside 1..50 rebuilds the character
    mov     edi, CLASS_ROGUE
    xor     esi, esi
    call    hdr_set
    call    hdr_load
    CALL0   rpg_class, CLASS_NONE
    CALL0   rpg_level, 1
    mov     edi, CLASS_ROGUE
    mov     esi, 51
    call    hdr_set
    call    hdr_load
    CALL0   rpg_class, CLASS_NONE
    mov     edi, CLASS_ROGUE
    mov     esi, 50
    call    hdr_set
    call    hdr_load
    CALL0   rpg_class, CLASS_ROGUE
    CALL0   rpg_level, 50
    ; a rank past its node's maximum (5, or 1 for an ability) zeroes every rank
    mov     edi, CLASS_ROGUE
    mov     esi, 10
    call    hdr_set
    mov     byte [HDRX + RPGEXT.ranks + 0], 6
    call    hdr_load
    CALL0   rpg_class, CLASS_ROGUE
    EXPECT_B R_RANKS + 0, 0
    mov     edi, CLASS_ROGUE
    mov     esi, 10
    call    hdr_set
    mov     byte [HDRX + RPGEXT.ranks + 6], 1
    mov     byte [HDRX + RPGEXT.ranks + 7], 2
    call    hdr_load
    EXPECT_B R_RANKS + 7, 0
    EXPECT_B R_RANKS + 6, 0
    ; a ranked node needs the node before it in its branch
    mov     edi, CLASS_ROGUE
    mov     esi, 10
    call    hdr_set
    mov     byte [HDRX + RPGEXT.ranks + 0], 1
    mov     byte [HDRX + RPGEXT.ranks + 2], 1
    call    hdr_load
    EXPECT_B R_RANKS + 2, 0
    EXPECT_B R_RANKS + 0, 0
    mov     edi, CLASS_ROGUE
    mov     esi, 10
    call    hdr_set
    mov     byte [HDRX + RPGEXT.ranks + 0], 1
    mov     byte [HDRX + RPGEXT.ranks + 1], 1
    mov     byte [HDRX + RPGEXT.ranks + 2], 1
    call    hdr_load
    EXPECT_B R_RANKS + 2, 1
    ; a branch's first node needs nothing, the next branch starts over at tier 0
    mov     edi, CLASS_ROGUE
    mov     esi, 10
    call    hdr_set
    mov     byte [HDRX + RPGEXT.ranks + 6], 1
    mov     byte [HDRX + RPGEXT.ranks + 12], 1
    call    hdr_load
    EXPECT_B R_RANKS + 12, 1
    EXPECT_B R_RANKS + 6, 1
    ; ranks adding up to the level are fine, one more is not
    mov     edi, CLASS_ROGUE
    mov     esi, 9
    call    hdr_set
    mov     byte [HDRX + RPGEXT.ranks + 0], 5
    mov     byte [HDRX + RPGEXT.ranks + 1], 4
    call    hdr_load
    EXPECT_B R_RANKS + 1, 4
    mov     edi, CLASS_ROGUE
    mov     esi, 8
    call    hdr_set
    mov     byte [HDRX + RPGEXT.ranks + 0], 5
    mov     byte [HDRX + RPGEXT.ranks + 1], 4
    call    hdr_load
    EXPECT_B R_RANKS + 1, 0
    EXPECT_B R_RANKS + 0, 0
    ; XP stays below the bar (59 at level 3); none at level 50
    mov     edi, CLASS_MAGE
    mov     esi, 3
    call    hdr_set
    mov     dword [HDR + RPGSAVE.xp], 58
    call    hdr_load
    EXPECT_D R_XP, 58
    mov     dword [HDR + RPGSAVE.xp], 59
    call    hdr_load
    EXPECT_D R_XP, 58
    mov     dword [HDR + RPGSAVE.xp], 0xFFFFFFFF
    call    hdr_load
    EXPECT_D R_XP, 58
    mov     edi, CLASS_MAGE
    mov     esi, 50
    call    hdr_set
    mov     dword [HDR + RPGSAVE.xp], 5
    call    hdr_load
    CALL0   rpg_level, 50
    EXPECT_D R_XP, 0
    ; quest 0..8, quest state 0/1, cleared bits 0..5, flag bit 0
    mov     edi, CLASS_WARRIOR
    mov     esi, 4
    call    hdr_set
    mov     byte [HDR + RPGSAVE.quest], 8
    mov     byte [HDR + RPGSAVE.quest_state], 1
    mov     byte [HDR + RPGSAVE.cleared], 0x3F
    mov     byte [HDR + RPGSAVE.flags], 1
    call    hdr_load
    EXPECT_B R_QUEST, 8
    EXPECT_B R_QSTATE, 1
    EXPECT_B R_CLEARED, 0x3F
    EXPECT_B R_FLAGS, 1
    mov     byte [HDR + RPGSAVE.quest], 9
    mov     byte [HDR + RPGSAVE.quest_state], 2
    mov     byte [HDR + RPGSAVE.cleared], 0xFF
    mov     byte [HDR + RPGSAVE.flags], 0xFE
    call    hdr_load
    EXPECT_B R_QUEST, 0
    EXPECT_B R_QSTATE, 0
    EXPECT_B R_CLEARED, 0x3F
    EXPECT_B R_FLAGS, 0
    mov     byte [HDR + RPGSAVE.quest], 0xFF
    mov     byte [HDR + RPGSAVE.flags], 0xFF
    call    hdr_load
    EXPECT_B R_QUEST, 0
    EXPECT_B R_FLAGS, 1
    TEST_END

; ---- quests ----------------------------------------------------------------------------

; kills_to_goal(edi type, esi elite, edx n) -> eax 0 when n - 1 kills of that kind leave the
; quest not completable and the n-th makes it completable, 1 otherwise
kills_to_goal:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
.l:
    mov     edi, ebx
    mov     esi, r12d
    call    quests_on_kill
    dec     r13d
    jz      .last
    call    quests_can_complete
    test    eax, eax
    jnz     .bad                            ; completable too early
    jmp     .l
.last:
    call    quests_can_complete
    cmp     eax, 1
    jne     .bad
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

test_quest_chain_progress_and_rewards:
    TEST_BEGIN
    mov     edi, CLASS_WARRIOR
    mov     esi, 5                          ; the bar is 95, rewards stay readable
    call    use_class
    ; quest 0 is on offer
    call    quests_current
    test    rax, rax
    jz      .fail
    mov     r14, rax
    cmp     dword [r14 + QUESTINFO.type], Q_KILL
    jne     .fail
    cmp     dword [r14 + QUESTINFO.target], MOB_ZOMBIE
    jne     .fail
    cmp     dword [r14 + QUESTINFO.count], 6
    jne     .fail
    cmp     dword [r14 + QUESTINFO.xp], 40
    jne     .fail
    cmp     dword [r14 + QUESTINFO.coins], 6
    jne     .fail
    cmp     dword [r14 + QUESTINFO.item], 0
    jne     .fail
    mov     rax, [r14 + QUESTINFO.title]
    STR_IS  s_title0
    ; nothing counts before the quest is accepted, and it cannot be handed in
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    call    kill
    CALL0   quests_progress, 0
    CALL0   quests_can_complete, 0
    CALL0   quests_complete, 0
    EXPECT_B R_QUEST, 0
    mov     word [R_QPROG], 3               ; a stale counter must not survive the accept
    CALL0   quests_accept, 1
    CALL0   quests_progress, 0
    CALL0   quests_accept, 0                ; already accepted
    EXPECT_B R_QSTATE, 1
    ; other mobs do not count; five zombies (the last one elite) are not enough
    mov     edi, MOB_SKELETON
    xor     esi, esi
    call    kill
    mov     edi, MOB_PIG
    mov     esi, 1
    call    kill
    CALL0   quests_progress, 0
    mov     r12d, 5
.zombies:
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    cmp     r12d, 1
    sete    sil
    call    kill
    dec     r12d
    jnz     .zombies
    CALL0   quests_progress, 5
    CALL0   quests_can_complete, 0
    CALL0   quests_complete, 0
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    call    kill                            ; the sixth
    CALL0   quests_progress, 6
    CALL0   quests_can_complete, 1
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    call    kill
    CALL0   quests_progress, 6              ; never past the count
    CALL0   quests_complete, 1
    EXPECT_B R_QUEST, 1
    EXPECT_B R_QSTATE, 0
    cmp     word [R_QPROG], 0
    jne     .fail
    CALL0   rpg_level, 5
    EXPECT_D R_XP, 40
    HAVE    GOLD_COIN, 6
    CALL0   quests_complete, 0              ; the next quest is not even accepted
    ; quest 1: bring 8 iron ingots, the inventory counts
    CALL0   quests_accept, 1
    CALL0   quests_can_complete, 0
    ADD     IRON_INGOT, 7
    CALL0   quests_progress, 7
    CALL0   quests_can_complete, 0
    ADD     IRON_INGOT, 6
    CALL0   quests_progress, 8              ; 13 carried, 8 count
    CALL0   quests_can_complete, 1
    CALL0   quests_complete, 1
    HAVE    IRON_INGOT, 5                   ; the 8 asked for were taken
    EXPECT_B R_QUEST, 2
    CALL0   rpg_level, 5                    ; 40 + 50 XP stay below the bar of 95
    EXPECT_D R_XP, 90
    HAVE    GOLD_COIN, 16
    ; quest 2: 5 skeletons, a health potion as well
    CALL0   quests_accept, 1
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    call    kill                            ; a zombie does not count here
    CALL0   quests_progress, 0
    mov     edi, MOB_SKELETON
    xor     esi, esi
    mov     edx, 5
    call    kills_to_goal
    test    eax, eax
    jnz     .fail
    CALL0   quests_complete, 1
    EXPECT_B R_QUEST, 3
    CALL0   rpg_level, 6                    ; 90 + 60 XP: one level of 95 and 55 over
    EXPECT_D R_XP, 55
    HAVE    GOLD_COIN, 24
    HAVE    HEALTH_POTION, 1
    ; quest 3: 3 creepers
    CALL0   quests_accept, 1
    mov     edi, MOB_CREEPER
    xor     esi, esi
    mov     edx, 3
    call    kills_to_goal
    test    eax, eax
    jnz     .fail
    CALL0   quests_complete, 1
    EXPECT_B R_QUEST, 4
    CALL0   rpg_level, 7                    ; 55 + 70 XP: the bar of 116 and 9 over
    EXPECT_D R_XP, 9
    HAVE    GOLD_COIN, 34
    ; quest 4: clear a dungeon; kills and the boss do not count
    CALL0   quests_accept, 1
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    call    kill
    call    quests_on_boss_killed
    CALL0   quests_progress, 0
    CALL0   quests_can_complete, 0
    call    quests_on_dungeon_cleared
    CALL0   quests_progress, 1
    CALL0   quests_complete, 1
    EXPECT_B R_QUEST, 5
    CALL0   rpg_level, 8                    ; 9 + 150 XP: the bar of 139 and 20 over
    EXPECT_D R_XP, 20
    HAVE    GOLD_COIN, 54
    HAVE    HEALTH_POTION, 3
    ; quest 5: 3 diamonds
    CALL0   quests_accept, 1
    ADD     DIAMOND, 4
    CALL0   quests_complete, 1
    HAVE    DIAMOND, 1
    EXPECT_B R_QUEST, 6
    CALL0   rpg_level, 8                    ; 20 + 120 XP stay below the bar of 164
    EXPECT_D R_XP, 140
    HAVE    GOLD_COIN, 79
    ; quest 6: five elites of any kind; a plain mob does not count
    CALL0   quests_accept, 1
    mov     edi, MOB_ZOMBIE
    xor     esi, esi
    call    kill
    CALL0   quests_progress, 0
    mov     edi, MOB_SPIDER
    mov     esi, 1
    mov     edx, 5
    call    kills_to_goal                   ; four elites leave it open, the fifth completes it
    test    eax, eax
    jnz     .fail
    CALL0   quests_complete, 1
    EXPECT_B R_QUEST, 7
    CALL0   rpg_level, 9                    ; 140 + 200 XP: the bar of 164 and 176 over
    EXPECT_D R_XP, 176
    HAVE    GOLD_COIN, 109
    ; quest 7: the boss
    call    quests_current
    test    rax, rax
    jz      .fail
    mov     r14, rax
    mov     rax, [r14 + QUESTINFO.title]
    STR_IS  s_fallen
    CALL0   quests_accept, 1
    call    quests_on_dungeon_cleared       ; not this one
    CALL0   quests_can_complete, 0
    call    quests_on_boss_killed
    CALL0   quests_complete, 1
    EXPECT_B R_QUEST, 8
    CALL0   rpg_level, 12                   ; 176 + 500 XP: three levels (191, 220, 251) and 14 over
    EXPECT_D R_XP, 14
    HAVE    GOLD_COIN, 169
    ; the chain is over
    CALL0   quests_current, 0
    CALL0   quests_accept, 0
    CALL0   quests_progress, 0
    CALL0   quests_can_complete, 0
    CALL0   quests_complete, 0
    TEST_END

; ---- trades ----------------------------------------------------------------------------

; find_drop(edi id) -> eax total count of that item lying in the world
find_drop:
    lea     rsi, [drops]
    xor     eax, eax
    mov     ecx, MAX_DROPS
.l:
    cmp     byte [rsi + DROP.id], dil
    jne     .n
    movzx   edx, byte [rsi + DROP.count]
    add     eax, edx
.n:
    add     rsi, DROP_size
    dec     ecx
    jnz     .l
    ret

; drop_dmg(edi id) -> eax the dmg word of the first drop of that item (-1 when none)
drop_dmg:
    lea     rsi, [drops]
    mov     ecx, MAX_DROPS
.l:
    cmp     byte [rsi + DROP.id], dil
    jne     .n
    movzx   eax, word [rsi + DROP.dmg]
    ret
.n:
    add     rsi, DROP_size
    dec     ecx
    jnz     .l
    mov     eax, -1
    ret

; stack_dmg(edi id) -> eax the dmg word of the first inventory stack of that item (-1 when none)
stack_dmg:
    lea     rsi, [inv]
    mov     ecx, INV_SLOTS
.l:
    cmp     byte [rsi + ITEMSTACK.id], dil
    jne     .n
    cmp     byte [rsi + ITEMSTACK.count], 0
    jne     .found
.n:
    add     rsi, 4
    dec     ecx
    jnz     .l
    mov     eax, -1
    ret
.found:
    movzx   eax, word [rsi + ITEMSTACK.dmg]
    ret

; rolled_ok(edi dmg, esi tier) -> eax 0 when the dmg word is a rolled piece of that tier: a rarity
; above common, the tier in bits 10..13 and a seed
rolled_ok:
    mov     eax, edi
    shr     eax, GEAR_RARITY_SHIFT
    jz      .bad
    mov     eax, edi
    shr     eax, GEAR_TIER_SHIFT
    and     eax, 15
    cmp     eax, esi
    jne     .bad
    test    edi, GEAR_SEED_MASK
    jz      .bad
    xor     eax, eax
    ret
.bad:
    mov     eax, 1
    ret

test_trade_exchanges_items:
    TEST_BEGIN
    call    reset_all
    ; the offer table
    xor     r12d, r12d
.offers:
    mov     edi, r12d
    call    trade_offer
    test    rax, rax
    jz      .fail
    mov     rcx, r12
    shl     rcx, 4
    lea     rdx, [trade_tab]
    add     rdx, rcx
    mov     ecx, [rdx]
    cmp     [rax], ecx
    jne     .fail
    mov     ecx, [rdx + 4]
    cmp     [rax + 4], ecx
    jne     .fail
    mov     ecx, [rdx + 8]
    cmp     [rax + 8], ecx
    jne     .fail
    mov     ecx, [rdx + 12]
    cmp     [rax + 12], ecx
    jne     .fail
    inc     r12d
    cmp     r12d, NUM_TRADES
    jb      .offers
    CALL1   trade_offer, NUM_TRADES, 0
    CALL1   trade_can, NUM_TRADES, 0
    CALL1   trade_execute, NUM_TRADES, 0
    ; 5 coins are one short of a potion
    ADD     GOLD_COIN, 5
    CALL1   trade_can, 0, 0
    CALL1   trade_execute, 0, 0
    HAVE    GOLD_COIN, 5
    HAVE    HEALTH_POTION, 0
    ; 6 coins: the potion, and the coins are gone
    ADD     GOLD_COIN, 1
    CALL1   trade_can, 0, 1
    CALL1   trade_execute, 0, 1
    HAVE    GOLD_COIN, 0
    HAVE    HEALTH_POTION, 1
    CALL1   trade_can, 0, 0
    CALL1   trade_execute, 0, 0
    HAVE    HEALTH_POTION, 1
    ; the other purchases
    ADD     GOLD_COIN, 40
    CALL1   trade_execute, 1, 1
    HAVE    MANA_POTION, 1
    CALL1   trade_execute, 2, 1
    HAVE    ARROW, 16
    CALL1   trade_execute, 3, 1
    HAVE    IRON_INGOT, 4
    HAVE    GOLD_COIN, 22                   ; 40 - 6 - 4 - 8
    CALL1   trade_can, 4, 0                 ; a diamond costs 25
    CALL1   trade_execute, 5, 1
    HAVE    STAFF, 1
    HAVE    GOLD_COIN, 10
    ; selling: 10 rotten flesh for a coin, a diamond for 15
    ADD     ROTTEN_FLESH, 23
    CALL1   trade_execute, 6, 1
    HAVE    ROTTEN_FLESH, 13
    HAVE    GOLD_COIN, 11
    CALL1   trade_execute, 6, 1
    HAVE    ROTTEN_FLESH, 3
    CALL1   trade_can, 6, 0
    CALL1   trade_can, 7, 0
    ADD     DIAMOND, 1
    CALL1   trade_execute, 7, 1
    HAVE    DIAMOND, 0
    HAVE    GOLD_COIN, 27                   ; 11 + 1 + 15
    CALL1   trade_execute, 4, 1             ; 25 coins buy a diamond
    HAVE    DIAMOND, 1
    HAVE    GOLD_COIN, 2
    ; a full inventory: the coins left in it keep their slot, so the goods fall to the ground
    call    inv_clear
    lea     rdi, [inv]
    mov     ecx, INV_SLOTS
    mov     eax, COBBLE | (64 << 8)
    rep     stosd
    mov     dword [inv], GOLD_COIN | (7 << 8)
    CALL1   trade_execute, 0, 1
    HAVE    GOLD_COIN, 1
    HAVE    HEALTH_POTION, 0
    CALL1   find_drop, HEALTH_POTION, 1
    ; the jewelry rows roll their piece: a level 10 Warrior (tier 3) pays 30 coins for a ring and
    ; for an amulet that are rolled above common, of tier 3, with a seed
    mov     edi, CLASS_WARRIOR
    mov     esi, 10
    call    use_class
    ADD     GOLD_COIN, 70
    CALL1   trade_execute, 8, 1
    HAVE    GOLD_COIN, 40
    HAVE    RING, 1
    mov     edi, RING
    call    stack_dmg
    mov     edi, eax
    mov     esi, 3
    call    rolled_ok
    test    eax, eax
    jnz     .fail
    CALL1   trade_execute, 9, 1
    HAVE    GOLD_COIN, 10
    HAVE    AMULET, 1
    mov     edi, AMULET
    call    stack_dmg
    mov     edi, eax
    mov     esi, 3
    call    rolled_ok
    test    eax, eax
    jnz     .fail
    CALL1   trade_can, 8, 0
    ; a level 50 Warrior's ring is of tier 15
    mov     edi, CLASS_WARRIOR
    mov     esi, 50
    call    use_class
    ADD     GOLD_COIN, 30
    CALL1   trade_execute, 8, 1
    mov     edi, RING
    call    stack_dmg
    mov     edi, eax
    mov     esi, 15
    call    rolled_ok
    test    eax, eax
    jnz     .fail
    ; no room: the ring falls at the player's feet with its roll
    mov     edi, CLASS_WARRIOR
    mov     esi, 10
    call    use_class
    lea     rdi, [inv]
    mov     ecx, INV_SLOTS
    mov     eax, COBBLE | (64 << 8)
    rep     stosd
    mov     dword [inv], GOLD_COIN | (31 << 8)
    CALL1   trade_execute, 8, 1
    HAVE    GOLD_COIN, 1
    HAVE    RING, 0
    CALL1   find_drop, RING, 1
    mov     edi, RING
    call    drop_dmg
    mov     edi, eax
    mov     esi, 3
    call    rolled_ok
    test    eax, eax
    jnz     .fail
    TEST_END
