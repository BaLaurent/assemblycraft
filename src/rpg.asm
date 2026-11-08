; rpg.asm - the character: class, level, XP, skill ranks, attribute points and the stats derived
; from them. rpg_state is the live progression stored in WORLDHDR.rpg; rpg_ext is the 0.8 extension
; stored in WORLDHDR.rpgx (ranks of the 18 skill nodes, attribute points, a version byte).
; rpg_stats is rebuilt from both by rpg_recompute (class base, level, node ranks, attributes,
; keystones, equipped gear, then caps). Skill and attribute points are never stored: skill points =
; level - sum of ranks, attribute points = 3 * (level - 1) - sum of attributes. This file also owns
; the static class / skill node / ability / stat / attribute description tables the screens read
; (record layouts in common.inc).
%include "common.inc"
default rel

global rpg_state, rpg_ext, rpg_stats, rpg_keystones
global rpg_reset, rpg_set_class, rpg_class, rpg_level, rpg_points, rpg_xp_need, rpg_add_xp
global rpg_rank, rpg_can_spend, rpg_spend, rpg_stat, rpg_recompute, rpg_clamp_stats
global rpg_attr, rpg_attr_points, rpg_spend_attr, rpg_attr_info, rpg_attr_desc
global rpg_respec_cost, rpg_respec, rpg_keystone, rpg_ability_unlocked
global rpg_class_info, rpg_node_info, rpg_ability_info, rpg_ability_tile, rpg_stat_info, rpg_format_stat
global rpg_branch_name
global rpg_on_mob_killed, rpg_on_block_mined, rpg_on_death, rpg_load, rpg_save, rpg_give_item

extern surv, surv_max_health, combat_mana, combat_stamina, combat_refill, combat_heal
extern inv, inv_add, inv_count, inv_remove_one, drops_spawn, player
extern audio_play, hud_banner, fx_burst, quests_on_kill
extern str_append, i32_to_str
extern gear_add_stats

; strings of the tables below live in their own read-only section so the records stay contiguous
section .rodata.str progbits alloc noexec nowrite align=1

section .rodata
align 4
f_vol_click: dd 0.6
f_vol_coin:  dd 0.7
f_vol_full:  dd 1.0
f_chest:     dd 1.2                     ; chest height above the feet (effect origin)
f_burst:     dd 3.0                     ; level-up burst speed
f_drop_y:    dd 0.5                     ; overflow drops appear this far above the feet
s_level:     db "Level ", 0
s_empty:     db 0
s_respec:    db "Skills and attributes reset", 0
s_refund:    db "The skill trees changed: points refunded", 0

; base stats per class (0 = no class, 1..4), in stat-id order:
; HEALTH MELEE RANGED SPELL CRIT CRITDMG MANA MANAREGEN STAMINA STAMREGEN ARMOR SPEED
; BACKSTAB PARRY LIFESTEAL COOLDOWN ARROWSAVE DODGECOST, then stats 18..43 (all 0)
base_stats:
    dd 20,  0,  0,  0,  0, 0,   0, 0, 100, 0, 0, 0,   0, 0, 0, 0,  0, 0   ; none
    times NUM_STATS - 18 dd 0
    dd 24, 10,  0,  0,  5, 0,   0, 0, 120, 0, 0, 0,   0, 0, 0, 0,  0, 0   ; Warrior
    times NUM_STATS - 18 dd 0
    dd 18,  0,  0, 10,  5, 0, 100, 4,  80, 0, 0, 0,   0, 0, 0, 0,  0, 0   ; Mage
    times NUM_STATS - 18 dd 0
    dd 20,  0, 15,  0,  8, 0,   0, 0, 100, 0, 0, 5,   0, 0, 0, 0, 10, 0   ; Archer
    times NUM_STATS - 18 dd 0
    dd 20,  0,  0,  0, 10, 0,   0, 0, 110, 10, 0, 5, 100, 0, 0, 0,  0, 0  ; Rogue
    times NUM_STATS - 18 dd 0
%if $ - base_stats != (NUM_CLASSES + 1) * NUM_STATS * 4
%error "base_stats needs NUM_STATS dwords per class"
%endif

tier_level: db 1, 4, 9, 15, 22, 30      ; level needed by a node of tier 0..5 (node % 6)
abil_node:  db 7, 9, 15                 ; the node that unlocks ability slot 1, 2, 3 (slot 0: the class)

; stats are capped on both sides after every recompute: stat id, lowest value, highest value
; (the int limits stand for "no bound")
%define NOLO -2147483648
%define NOHI  2147483647
%macro CAPROW 3                         ; stat, lowest, highest
    dd %1, %2, %3
%endmacro
cap_tab:
    CAPROW STAT_CRIT_CHANCE,  NOLO,  75
    CAPROW STAT_COOLDOWN_RED, NOLO,  50
    CAPROW STAT_DODGE_COST,   NOLO,  75
    CAPROW STAT_ARROW_SAVE,   NOLO,  75
    CAPROW STAT_BLOCK_COST,   NOLO,  75
    CAPROW STAT_ATTACK_SPEED, NOLO, 100
    CAPROW STAT_AREA,         NOLO, 100
    CAPROW STAT_BLEED_CHANCE, NOLO, 100
    CAPROW STAT_MOVE_SPEED,    -50,  50
    CAPROW STAT_RES_FIRE,     -100,  75
    CAPROW STAT_RES_FROST,    -100,  75
    CAPROW STAT_RES_SHOCK,    -100,  75
    CAPROW STAT_RES_POISON,   -100,  75
    CAPROW STAT_CRIT_DMG,      -50, NOHI
    CAPROW STAT_FIRE_DMG,      -90, NOHI
    CAPROW STAT_FROST_DMG,     -90, NOHI
    CAPROW STAT_SHOCK_DMG,     -90, NOHI
    CAPROW STAT_POISON_DMG,    -90, NOHI
cap_tab_end:

; XP for a kill the player earned at level 1, by mob type 0..8 (the boss gives none here; folk
; 12)
kill_xp:    db 0, 10, 2, 15, 12, 10, 2, 0, 12
; XP for mining an ore: block id, XP; ended by a 0 id
ore_xp:     db COAL_ORE, 2, IRON_ORE, 5, GOLD_ORE, 8, DIAMOND_ORE, 20, 0, 0

; starting kits: (item id, count) pairs ended by a 0 id; every class then gets the common kit
kit_warrior: db IRON_SWORD, 1, 0
kit_mage:    db STAFF, 1, MANA_POTION, 2, 0
kit_archer:  db BOW, 1, ARROW, 32, 0
kit_rogue:   db IRON_DAGGER, 1, HEALTH_POTION, 2, 0
kit_common:  db COOKED_PORKCHOP, 4, 0
align 8
kit_tab:     dq kit_warrior, kit_mage, kit_archer, kit_rogue

; ---- description tables ---------------------------------------------------

; CLASSINFO record
%macro CINFO 4                          ; name, line1, line2, line3
section .rodata.str
%%n: db %1, 0
%%a: db %2, 0
%%b: db %3, 0
%%c: db %4, 0
section .rodata
    dq %%n, %%a, %%b, %%c
%endmacro

align 8
class_tab:                              ; indexed by class 0..4
    CINFO "None", "", "", ""
    CINFO "Warrior", "Heavy armor", "Charge and cleave", "Parry master"
    CINFO "Mage", "Fire and arcane", "Staff bolts", "Fragile, deadly"
    CINFO "Archer", "Bows and volleys", "Deadly at range", "Swift hunter"
    CINFO "Rogue", "Daggers, stealth", "Backstab x2", "Shadowstep"

; the three branch names of a class
%macro BRANCHES 3
section .rodata.str
%%a: db %1, 0
%%b: db %2, 0
%%c: db %3, 0
section .rodata
    dq %%a, %%b, %%c
%endmacro

branch_tab:                             ; (class - 1) * 3 + branch
    BRANCHES "Blademaster", "Bulwark", "Endurance"
    BRANCHES "Fire", "Arcane", "Warding"
    BRANCHES "Marksman", "Hunter", "Survival"
    BRANCHES "Assassin", "Shadow", "Agility"

; attribute name and the effect of one point, by attribute 0..3
%macro ATTR 2                           ; name, effects
section .rodata.str
%%n: db %1, 0
%%d: db %2, 0
section .rodata
    dq %%n, %%d
%endmacro

attr_tab:
    ATTR "Strength", "+1% melee damage, +1 max stamina"
    ATTR "Dexterity", "+1% ranged damage; per 3: +1% attack speed; per 5: +1% crit chance"
    ATTR "Intelligence", "+1% spell damage, +2 max mana; per 10: +1 mana per second"
    ATTR "Vitality", "+1 max health, +1% stamina regen"
%if $ - attr_tab != NUM_ATTRS * 16
%error "attr_tab needs one record per attribute"
%endif

; STATINFO record: label, the text that follows the value (it starts with a space unless it
; starts with '%'), display format and atlas tile
%macro STATI 4                          ; label, suffix, format, icon tile
section .rodata.str
%%l: db %1, 0
%%s: db %2, 0
section .rodata
    dq %%l, %%s
    db %3, %4
    times 6 db 0
%endmacro

align 8
stat_tab:                               ; by stat id
    STATI "Max health",       " max health",                FMT_FLAT,   TILE_STAT0 + STAT_MAX_HEALTH
    STATI "Melee damage",     "% melee damage",             FMT_PCT,    TILE_STAT0 + STAT_MELEE_DMG
    STATI "Ranged damage",    "% ranged damage",            FMT_PCT,    TILE_STAT0 + STAT_RANGED_DMG
    STATI "Spell damage",     "% spell damage",             FMT_PCT,    TILE_STAT0 + STAT_SPELL_DMG
    STATI "Crit chance",      "% critical chance",          FMT_PCT,    TILE_STAT0 + STAT_CRIT_CHANCE
    STATI "Crit damage",      "% critical damage",          FMT_PCT,    TILE_STAT0 + STAT_CRIT_DMG
    STATI "Max mana",         " max mana",                  FMT_FLAT,   TILE_STAT0 + STAT_MAX_MANA
    STATI "Mana regen",       " mana per second",           FMT_FLAT,   TILE_STAT0 + STAT_MANA_REGEN
    STATI "Max stamina",      " max stamina",               FMT_FLAT,   TILE_STAT0 + STAT_MAX_STAMINA
    STATI "Stamina regen",    "% stamina regen",            FMT_PCT,    TILE_STAT0 + STAT_STAMINA_REGEN
    STATI "Armor",            " armor",                     FMT_FLAT,   TILE_STAT0 + STAT_ARMOR_BONUS
    STATI "Move speed",       "% move speed",               FMT_PCT,    TILE_STAT0 + STAT_MOVE_SPEED
    STATI "Backstab",         "% backstab damage",          FMT_PCT,    TILE_STAT0 + STAT_BACKSTAB
    STATI "Parry window",     " steps parry window",        FMT_FLAT,   TILE_STAT0 + STAT_PARRY_WINDOW
    STATI "Lifesteal",        "% of damage healed",         FMT_PCT,    TILE_STAT0 + STAT_LIFESTEAL
    STATI "Cooldowns",        "% cooldowns",                FMT_NEGPCT, TILE_STAT0 + STAT_COOLDOWN_RED
    STATI "Arrow save",       "% arrows saved",             FMT_PCT,    TILE_STAT0 + STAT_ARROW_SAVE
    STATI "Dodge cost",       "% dodge cost",               FMT_NEGPCT, TILE_STAT0 + STAT_DODGE_COST
    STATI "Attack speed",     "% attack speed",             FMT_PCT,    TILE_STAT_ASPD
    STATI "Fire damage",      "% fire damage",              FMT_PCT,    TILE_ELEM_FIRE
    STATI "Frost damage",     "% frost damage",             FMT_PCT,    TILE_ELEM_FROST
    STATI "Shock damage",     "% shock damage",             FMT_PCT,    TILE_ELEM_SHOCK
    STATI "Poison damage",    "% poison damage",            FMT_PCT,    TILE_ELEM_POISON
    STATI "Added fire",       " fire damage to attacks",    FMT_FLAT,   TILE_ELEM_FIRE
    STATI "Added frost",      " frost damage to attacks",   FMT_FLAT,   TILE_ELEM_FROST
    STATI "Added shock",      " shock damage to attacks",   FMT_FLAT,   TILE_ELEM_SHOCK
    STATI "Added poison",     " poison damage to attacks",  FMT_FLAT,   TILE_ELEM_POISON
    STATI "Fire resist",      "% fire resistance",          FMT_PCT,    TILE_ELEM_FIRE
    STATI "Frost resist",     "% frost resistance",         FMT_PCT,    TILE_ELEM_FROST
    STATI "Shock resist",     "% shock resistance",         FMT_PCT,    TILE_ELEM_SHOCK
    STATI "Poison resist",    "% poison resistance",        FMT_PCT,    TILE_ELEM_POISON
    STATI "Bleed chance",     "% bleed chance",             FMT_PCT,    TILE_STAT_BLEED
    STATI "Damage over time", "% damage over time",         FMT_PCT,    TILE_STAT_BLEED
    STATI "Elite damage",     "% damage to elites",         FMT_PCT,    TILE_STAT_ELITE
    STATI "Area",             "% area of effect",           FMT_PCT,    TILE_STAT_AREA
    STATI "Life regen",       " health per second",         FMT_TENTH,  TILE_STAT0 + STAT_MAX_HEALTH
    STATI "Life on kill",     " health per kill",           FMT_FLAT,   TILE_STAT0 + STAT_LIFESTEAL
    STATI "Thorns",           " thorns damage",             FMT_FLAT,   TILE_STAT0 + STAT_ARMOR_BONUS
    STATI "Block cost",       "% block stamina cost",       FMT_NEGPCT, TILE_STAT0 + STAT_PARRY_WINDOW
    STATI "XP bonus",         "% experience",               FMT_PCT,    TILE_ITEM0 + GOLD_COIN - COAL
    STATI "Gold find",        "% gold found",               FMT_PCT,    TILE_ITEM0 + GOLD_COIN - COAL
    STATI "Magic find",       "% magic find",               FMT_PCT,    TILE_ITEM0 + GOLD_COIN - COAL
    STATI "All damage",       "% all damage",               FMT_PCT,    TILE_STAT0 + STAT_CRIT_DMG
    STATI "Weapon damage",    " weapon damage",             FMT_FLAT,   TILE_STAT0 + STAT_MELEE_DMG
%if $ - stat_tab != NUM_STATS * STATINFO_size
%error "stat_tab needs one record per stat"
%endif

; ABILINFO record; the labels let the matching skill node share the name and text
%macro ABIL 6                           ; label, name, desc, resource, cost, cooldown_s
section .rodata.str
an_%1: db %2, 0
ad_%1: db %3, 0
section .rodata
    dq an_%1, ad_%1
    dd %4, %5, %6, 0
%endmacro

align 8
abil_tab:                               ; (class - 1) * 4 + slot
    ABIL charge,    "Charge",          "Rush forward, stunning foes",       RES_STAMINA, 30, 6
    ABIL warcry,    "War Cry",         "Stun foes, empower yourself",       RES_STAMINA, 40, 20
    ABIL whirl,     "Whirlwind",       "Spin and slash all around",         RES_STAMINA, 60, 30
    ABIL slam,      "Ground Slam",     "Smash the ground, stunning foes",   RES_STAMINA, 45, 12
    ABIL fireball,  "Fireball",        "Explosive fireball",                RES_MANA,    25, 3
    ABIL blink,     "Blink",           "Teleport a short way ahead",        RES_MANA,    20, 5
    ABIL meteor,    "Meteor Storm",    "Call down a meteor rain",           RES_MANA,    70, 40
    ABIL nova,      "Frost Nova",      "Freeze nearby foes",                RES_MANA,    35, 10
    ABIL volley,    "Volley",          "Fire a fan of five arrows",         RES_STAMINA, 30, 6
    ABIL explarrow, "Explosive Arrow", "Arrow that explodes on impact",     RES_STAMINA, 35, 10
    ABIL arrowrain, "Arrow Rain",      "Rain arrows on the target",         RES_STAMINA, 60, 30
    ABIL mark,      "Hunter's Mark",   "Marked foe takes 30% more damage",  RES_STAMINA, 20, 8
    ABIL shadowstp, "Shadowstep",      "Blink behind a foe, next hit crits", RES_STAMINA, 25, 8
    ABIL smoke,     "Smoke Bomb",      "Vanish, enemies lose track",        RES_STAMINA, 40, 20
    ABIL bladedance, "Blade Dance",    "Faster strikes that always crit",   RES_STAMINA, 60, 35
    ABIL knives,    "Fan of Knives",   "Throw bleeding knives all around",  RES_STAMINA, 35, 9
%if $ - abil_tab != NUM_CLASSES * NUM_ABILITY_SLOTS * ABILINFO_size
%error "abil_tab needs NUM_ABILITY_SLOTS records per class"
%endif

; NODEINFO records: a passive stat node (max rank 5) without a text of its own, since the text is
; always the stat's formatted value (rpg_format_stat) ...
%macro SNODE 3                          ; name, stat, value per rank
section .rodata.str
%%n: db %1, 0
section .rodata
    dq %%n, 0
    db NODE_STAT, %2, 5, 0
    dd %3
%endmacro
; ... an ability node (max rank 1): name and text come from the ability record ...
%macro ANODE 2                          ; ability label, ability slot
    dq an_%1, ad_%1
    db NODE_ABILITY, %2, 1, 0
    dd 0
%endmacro
; ... and a keystone (max rank 1) whose effect is coded where it applies
%macro KNODE 3                          ; name, keystone id, description
section .rodata.str
%%n: db %1, 0
%%d: db %3, 0
section .rodata
    dq %%n, %%d
    db NODE_KEYSTONE, %2, 1, 0
    dd 0
%endmacro

align 8
node_tab:                               ; (class - 1) * 18 + node, node = branch * 6 + tier
    ; Warrior
    SNODE "Weapon Mastery", STAT_MELEE_DMG,     6
    SNODE "Precision",      STAT_CRIT_CHANCE,   3
    SNODE "Brutality",      STAT_CRIT_DMG,     15
    SNODE "Bloodthirst",    STAT_LIFESTEAL,     2
    SNODE "Swift Blade",    STAT_ATTACK_SPEED,  5
    KNODE "Executioner",    KS_EXECUTIONER, "Melee hits on foes under 30% health deal +60% damage"
    SNODE "Toughness",      STAT_MAX_HEALTH,    4
    ANODE warcry, 1
    SNODE "Iron Skin",      STAT_ARMOR_BONUS,   1
    ANODE whirl, 2
    SNODE "Shield Wall",    STAT_BLOCK_COST,   10
    KNODE "Juggernaut",     KS_JUGGERNAUT, "No knockback, +4 armor, -15% move speed"
    SNODE "Stamina",        STAT_MAX_STAMINA,  12
    SNODE "Second Wind",    STAT_STAMINA_REGEN, 10
    SNODE "Riposte",        STAT_PARRY_WINDOW,  1
    ANODE slam, 3
    SNODE "Spiked Mail",    STAT_THORNS,        3
    KNODE "Bloodrage",      KS_BLOODRAGE, "+1% damage per 2% missing health, -10% max health"
    ; Mage
    SNODE "Pyromancy",      STAT_SPELL_DMG,     6
    SNODE "Kindling",       STAT_FIRE_DMG,      8
    SNODE "Combustion",     STAT_CRIT_DMG,     15
    SNODE "Fire Touch",     STAT_ADD_FIRE,      1
    SNODE "Static",         STAT_SHOCK_DMG,     8
    KNODE "Inferno",        KS_INFERNO, "Spell hits ignite; burning foes take +25% spell damage; -50% frost damage"
    SNODE "Deep Mind",      STAT_MAX_MANA,     15
    ANODE blink, 1
    SNODE "Flow",           STAT_MANA_REGEN,    1
    ANODE meteor, 2
    SNODE "Haste",          STAT_COOLDOWN_RED,  4
    KNODE "Blood Magic",    KS_BLOOD_MAGIC, "Mana costs are paid with health (1 per 5 mana); +30% spell damage"
    SNODE "Vitality",       STAT_MAX_HEALTH,    3
    SNODE "Frost Weaving",  STAT_FROST_DMG,     8
    SNODE "Arcane Reach",   STAT_AREA,          8
    ANODE nova, 3
    SNODE "Renewal",        STAT_LIFE_REGEN,    5
    KNODE "Mana Shield",    KS_MANA_SHIELD, "35% of damage taken drains mana instead (2 mana per point)"
    ; Archer
    SNODE "Steady Aim",     STAT_RANGED_DMG,    6
    SNODE "Eagle Eye",      STAT_CRIT_CHANCE,   3
    SNODE "Deadly Shot",    STAT_CRIT_DMG,     15
    SNODE "Quick Draw",     STAT_ATTACK_SPEED,  5
    SNODE "Big Game",       STAT_ELITE_DMG,     6
    KNODE "Deadeye",        KS_DEADEYE, "Fully drawn shots always crit; attack speed no longer speeds your draw"
    SNODE "Fleet Foot",     STAT_MOVE_SPEED,    3
    ANODE explarrow, 1
    SNODE "Quiver",         STAT_ARROW_SAVE,   10
    ANODE arrowrain, 2
    SNODE "Toxic Tips",     STAT_ADD_POISON,    1
    KNODE "Barrage",        KS_BARRAGE, "Bow shots fire 2 extra arrows (60% damage); Volley fires 7"
    SNODE "Vitality",       STAT_MAX_HEALTH,    3
    SNODE "Evasion",        STAT_DODGE_COST,   10
    SNODE "Second Wind",    STAT_STAMINA_REGEN, 10
    ANODE mark, 3
    SNODE "Readiness",      STAT_COOLDOWN_RED,  4
    KNODE "Wind Runner",    KS_WIND_RUNNER, "+20% move speed; dodges cost no stamina but recover twice as slowly"
    ; Rogue
    SNODE "Backstab",       STAT_BACKSTAB,     20
    SNODE "Precision",      STAT_CRIT_CHANCE,   3
    SNODE "Cruelty",        STAT_CRIT_DMG,     15
    SNODE "Serrated",       STAT_BLEED_CHANCE,  8
    SNODE "Blade Mastery",  STAT_MELEE_DMG,     6
    KNODE "Assassinate",    KS_ASSASSINATE, "Backstabs kill non-boss foes under 25% health; +50% backstab vs bosses"
    SNODE "Fleet Foot",     STAT_MOVE_SPEED,    3
    ANODE smoke, 1
    SNODE "Evasion",        STAT_DODGE_COST,   10
    ANODE bladedance, 2
    SNODE "Venom",          STAT_POISON_DMG,   10
    KNODE "Shadow Dance",   KS_SHADOW_DANCE, "Smoke Bomb stealth lasts 30 s; the first hit from stealth deals double"
    SNODE "Endurance",      STAT_MAX_STAMINA,  12
    SNODE "Second Wind",    STAT_STAMINA_REGEN, 10
    SNODE "Leech",          STAT_LIFESTEAL,     2
    ANODE knives, 3
    SNODE "Lethality",      STAT_DOT_DMG,      10
    KNODE "Venom Blades",   KS_VENOM_BLADES, "Melee hits add 2 poison stacks; +50% poison damage; -30% crit damage"
%if $ - node_tab != NUM_CLASSES * NUM_NODES * NODEINFO_size
%error "node_tab needs NUM_NODES records per class"
%endif

; what the info getters return for no class / an index out of range
node_blank: dq s_empty, s_empty
            db 0, 0, 0, 0
            dd 0
align 8
abil_blank: dq s_empty, s_empty
            dd 0, 0, 0, 0
stat_blank: dq s_empty, s_empty
            db 0, 0, 0, 0, 0, 0, 0, 0

section .bss
alignb 4
rpg_state:  resb RPGSAVE_size
rpg_ext:    resb RPGEXT_size
rpg_stats:  resd NUM_STATS
rpg_keystones: resd 1                   ; bit ks (KS_*) set while that keystone is taken
banner:     resb 16                     ; "Level 50!"

section .text

; ---- plain getters ----------------------------------------------------------

; rpg_class() -> eax 0 (none) .. 4
rpg_class:
    movzx   eax, byte [rpg_state + RPGSAVE.class]
    ret

; rpg_level() -> eax 1..50
rpg_level:
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    ret

; rpg_points() -> eax unspent skill points = level - sum of the 18 ranks (never negative)
rpg_points:
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    lea     rsi, [rpg_ext + RPGEXT.ranks]
    xor     ecx, ecx
.l:
    movzx   edx, byte [rsi + rcx]
    sub     eax, edx
    inc     ecx
    cmp     ecx, NUM_NODES
    jb      .l
    xor     edx, edx
    test    eax, eax
    cmovs   eax, edx
    ret

; rpg_attr_points() -> eax unspent attribute points = 3 * (level - 1) - sum of the attributes
; (never negative)
rpg_attr_points:
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    dec     eax
    imul    eax, eax, ATTR_PER_LEVEL
    lea     rsi, [rpg_ext + RPGEXT.attr]
    xor     ecx, ecx
.l:
    movzx   edx, word [rsi + rcx*2]
    sub     eax, edx
    inc     ecx
    cmp     ecx, NUM_ATTRS
    jb      .l
    xor     edx, edx
    test    eax, eax
    cmovs   eax, edx
    ret

; rpg_xp_need(edi level) -> eax XP to leave that level: 20 + 10 * level + level^2 for 1..49,
; else 0
rpg_xp_need:
    lea     eax, [rdi - 1]
    cmp     eax, MAX_LEVEL - 1
    jae     .none
    imul    eax, edi, 10
    add     eax, 20
    mov     ecx, edi
    imul    ecx, edi
    add     eax, ecx
    ret
.none:
    xor     eax, eax
    ret

; rpg_rank(edi node) -> eax rank of node 0..17 (0 for anything else)
rpg_rank:
    xor     eax, eax
    cmp     edi, NUM_NODES
    jae     .ret
    mov     ecx, edi
    lea     rdx, [rpg_ext + RPGEXT.ranks]
    movzx   eax, byte [rdx + rcx]
.ret:
    ret

; rpg_attr(edi a) -> eax points spent in attribute 0..3 (0 for anything else)
rpg_attr:
    xor     eax, eax
    cmp     edi, NUM_ATTRS
    jae     .ret
    mov     ecx, edi
    lea     rdx, [rpg_ext + RPGEXT.attr]
    movzx   eax, word [rdx + rcx*2]
.ret:
    ret

; rpg_stat(edi stat) -> eax rpg_stats[stat] (0 for an unknown stat)
rpg_stat:
    xor     eax, eax
    cmp     edi, NUM_STATS
    jae     .ret
    mov     ecx, edi
    lea     rdx, [rpg_stats]
    mov     eax, [rdx + rcx*4]
.ret:
    ret

; rpg_keystone(edi ks) -> eax 1 when keystone 0..11 is taken (its node has a rank), else 0
rpg_keystone:
    xor     eax, eax
    cmp     edi, NUM_CLASSES * 3
    jae     .ret
    mov     ecx, edi
    mov     eax, [rpg_keystones]
    shr     eax, cl
    and     eax, 1
.ret:
    ret

; rpg_ability_unlocked(edi slot) -> eax 1 when the ability of slot 0..3 can be cast: slot 0 needs
; a class, slots 1, 2 and 3 rank >= 1 in nodes 7, 9 and 15
rpg_ability_unlocked:
    xor     eax, eax
    cmp     edi, NUM_ABILITY_SLOTS
    jae     .ret
    test    edi, edi
    jz      .slot0
    mov     ecx, edi
    lea     rdx, [abil_node - 1]
    movzx   ecx, byte [rdx + rcx]
    lea     rdx, [rpg_ext + RPGEXT.ranks]
    cmp     byte [rdx + rcx], 0
    seta    al
    ret
.slot0:
    cmp     byte [rpg_state + RPGSAVE.class], 0
    setne   al
.ret:
    ret

; ---- description tables ----------------------------------------------------

; rpg_class_info(edi class) -> rax CLASSINFO* {name, line1, line2, line3}; no class / unknown
; class -> the "None" record
rpg_class_info:
    cmp     edi, NUM_CLASSES
    jbe     .ok
    xor     edi, edi
.ok:
    mov     eax, edi
    imul    eax, eax, CLASSINFO_size
    lea     rcx, [class_tab]
    add     rax, rcx
    ret

; rpg_branch_name(edi class, esi branch) -> rax zstr of branch 0..2 of class 1..4, else ""
rpg_branch_name:
    lea     eax, [rdi - 1]
    cmp     eax, NUM_CLASSES
    jae     .blank
    cmp     esi, 3
    jae     .blank
    lea     eax, [rax + rax*2]
    add     eax, esi
    lea     rcx, [branch_tab]
    mov     rax, [rcx + rax*8]
    ret
.blank:
    lea     rax, [s_empty]
    ret

; rpg_node_info(edi class, esi node) -> rax NODEINFO* of node 0..17 of class 1..4 (stat nodes have
; no text: desc is 0; a keystone's stat field is its KS_* id); anything else -> an empty record
; (empty texts, kind 0, stat 0, max 0, value 0)
rpg_node_info:
    lea     eax, [rdi - 1]
    cmp     eax, NUM_CLASSES
    jae     .blank
    cmp     esi, NUM_NODES
    jae     .blank
    imul    eax, eax, NUM_NODES
    add     eax, esi
    imul    eax, eax, NODEINFO_size
    lea     rcx, [node_tab]
    add     rax, rcx
    ret
.blank:
    lea     rax, [node_blank]
    ret

; rpg_ability_info(edi class, esi slot) -> rax ABILINFO* of ability 0..3 of class 1..4;
; anything else -> an empty record
rpg_ability_info:
    lea     eax, [rdi - 1]
    cmp     eax, NUM_CLASSES
    jae     .blank
    cmp     esi, NUM_ABILITY_SLOTS
    jae     .blank
    lea     eax, [rsi + rax*4]
    imul    eax, eax, ABILINFO_size
    lea     rcx, [abil_tab]
    add     rax, rcx
    ret
.blank:
    lea     rax, [abil_blank]
    ret

; rpg_ability_tile(edi slot) -> eax atlas tile of the current class's ability icon:
; TILE_ABILITY0 + (class - 1) * 3 + slot for slots 0..2, TILE_ABILITY3_0 + class - 1 for slot 3;
; 0 without a class or for another slot. Leaf, clobbers ecx.
rpg_ability_tile:
    xor     eax, eax
    movzx   ecx, byte [rpg_state + RPGSAVE.class]
    dec     ecx
    cmp     ecx, NUM_CLASSES
    jae     .ret
    cmp     edi, NUM_ABILITY_SLOTS
    jae     .ret
    lea     eax, [rcx + TILE_ABILITY3_0]
    cmp     edi, 3
    je      .ret
    lea     ecx, [rcx + rcx*2]
    mov     eax, edi
    lea     eax, [rax + rcx + TILE_ABILITY0]
.ret:
    ret

; rpg_stat_info(edi stat) -> rax STATINFO* of stat 0..43; anything else -> an empty record
rpg_stat_info:
    cmp     edi, NUM_STATS
    jae     .blank
    imul    eax, edi, STATINFO_size
    lea     rcx, [stat_tab]
    add     rax, rcx
    ret
.blank:
    lea     rax, [stat_blank]
    ret

; rpg_attr_info(edi a) -> rax zstr name of attribute 0..3 ("" for anything else)
rpg_attr_info:
    lea     rax, [s_empty]
    cmp     edi, NUM_ATTRS
    jae     .ret
    mov     ecx, edi
    shl     ecx, 4
    lea     rdx, [attr_tab]
    mov     rax, [rdx + rcx]
.ret:
    ret

; rpg_attr_desc(edi a) -> rax zstr effects of one point of attribute 0..3 ("" for anything else)
rpg_attr_desc:
    lea     rax, [s_empty]
    cmp     edi, NUM_ATTRS
    jae     .ret
    mov     ecx, edi
    shl     ecx, 4
    lea     rdx, [attr_tab]
    mov     rax, [rdx + rcx + 8]
.ret:
    ret

; rpg_format_stat(edi stat, esi value, rdx out byte[48]) -> rax out: the stat's value as text,
; "+12% melee damage" style, NUL-terminated. FMT_PCT / FMT_FLAT: '+' or '-' by the value's sign,
; |value|, the suffix. FMT_NEGPCT (a reduction stored positive): '-' for a positive value, '+'
; for a negative one. FMT_TENTH: like FMT_PCT with |value| / 10 '.' |value| % 10.
rpg_format_stat:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12, rdx                    ; out
    mov     r13d, esi                   ; value, then |value|
    call    rpg_stat_info
    mov     rbx, rax
    xor     ecx, ecx                    ; 1 when the sign to print is '-'
    test    r13d, r13d
    jns     .abs
    neg     r13d
    mov     ecx, 1
.abs:
    cmp     byte [rbx + STATINFO.fmt], FMT_NEGPCT
    jne     .sign
    xor     ecx, 1
.sign:
    mov     eax, '+'
    mov     edx, '-'
    test    ecx, ecx
    cmovnz  eax, edx
    mov     [r12], al
    lea     r14, [r12 + 1]
    cmp     byte [rbx + STATINFO.fmt], FMT_TENTH
    je      .tenth
    mov     edi, r13d
    mov     rsi, r14
    call    i32_to_str
    mov     r14, rax
    jmp     .suffix
.tenth:
    mov     eax, r13d
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    mov     r13d, edx                   ; the tenth
    mov     edi, eax
    mov     rsi, r14
    call    i32_to_str
    mov     byte [rax], '.'
    add     r13d, '0'
    mov     [rax + 1], r13b
    lea     r14, [rax + 2]
.suffix:
    mov     rdi, r14
    mov     rsi, [rbx + STATINFO.suffix]
    call    str_append
    mov     byte [rax], 0
    mov     rax, r12
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- stats -------------------------------------------------------------------

; rpg_clamp_stats(): every stat of cap_tab into its [lowest, highest] range: the percentage caps
; (crit chance 75, cooldowns 50, dodge and block cost 75, arrow save 75, attack speed 100, area 100,
; bleed chance 100), move speed [-50, 50], resistances [-100, 75], crit damage >= -50 and the
; element damage percentages >= -90. Leaf.
rpg_clamp_stats:
    lea     rsi, [cap_tab]
    lea     rdx, [rpg_stats]
    mov     ecx, (cap_tab_end - cap_tab) / 12
.l:
    mov     eax, [rsi]                  ; stat
    mov     r8d, [rdx + rax*4]
    cmp     r8d, [rsi + 4]
    cmovl   r8d, [rsi + 4]
    cmp     r8d, [rsi + 8]
    cmovg   r8d, [rsi + 8]
    mov     [rdx + rax*4], r8d
    add     rsi, 12
    dec     ecx
    jnz     .l
    ret

; add (r8d / %1) to the stat %2 (clobbers eax, ecx, edx)
%macro ADD_DIV 2
    mov     eax, r8d
    xor     edx, edx
    mov     ecx, %1
    div     ecx
    add     [rpg_stats + (%2) * 4], eax
%endmacro

; add %3 to the stat %2 while the keystone %1 is taken
%macro KS_STAT 3
    bt      dword [rpg_keystones], %1
    jnc     %%off
    add     dword [rpg_stats + (%2) * 4], %3
%%off:
%endmacro

; rpg_recompute(): rebuilds rpg_stats in this order: the class's base row, +2 health per level
; above the first, the stat nodes (rank * value; the ranked keystone nodes set their rpg_keystones
; bit), the attributes, the keystones' stat changes, the equipped gear (gear_add_stats), the caps
; and floors, Bloodrage's -10% health. Then publishes surv_max_health and keeps health, mana and
; stamina at or below their maxima.
rpg_recompute:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    movzx   ebx, byte [rpg_state + RPGSAVE.class]
    cmp     ebx, NUM_CLASSES
    jbe     .base
    xor     ebx, ebx                    ; a corrupt class counts as none
.base:
    imul    eax, ebx, NUM_STATS * 4
    lea     rsi, [base_stats]
    add     rsi, rax
    lea     rdi, [rpg_stats]
    mov     ecx, NUM_STATS
    rep     movsd
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    dec     eax
    jns     .level
    xor     eax, eax
.level:
    add     eax, eax                    ; 2 health per level above the first
    add     [rpg_stats + STAT_MAX_HEALTH*4], eax
    xor     r11d, r11d                  ; keystones taken
    test    ebx, ebx
    jz      .keystones
    lea     r8, [rpg_ext + RPGEXT.ranks]
    lea     r9, [node_tab]
    lea     eax, [rbx - 1]
    imul    eax, eax, NUM_NODES * NODEINFO_size
    add     r9, rax                     ; the class's first node
    lea     r10, [rpg_stats]
    xor     ecx, ecx
.node:
    movzx   eax, byte [r8 + rcx]
    test    eax, eax
    jz      .next
    movzx   edx, byte [r9 + NODEINFO.stat]
    cmp     byte [r9 + NODEINFO.kind], NODE_STAT
    je      .stat
    cmp     byte [r9 + NODEINFO.kind], NODE_KEYSTONE
    jne     .next                       ; an ability node adds no stat
    bts     r11d, edx
    jmp     .next
.stat:
    imul    eax, [r9 + NODEINFO.value]
    add     [r10 + rdx*4], eax
.next:
    add     r9, NODEINFO_size
    inc     ecx
    cmp     ecx, NUM_NODES
    jb      .node
.keystones:
    mov     [rpg_keystones], r11d
    movzx   eax, word [rpg_ext + RPGEXT.attr + ATTR_STR*2]
    add     [rpg_stats + STAT_MELEE_DMG*4], eax
    add     [rpg_stats + STAT_MAX_STAMINA*4], eax
    movzx   r8d, word [rpg_ext + RPGEXT.attr + ATTR_DEX*2]
    add     [rpg_stats + STAT_RANGED_DMG*4], r8d
    ADD_DIV 3, STAT_ATTACK_SPEED
    ADD_DIV 5, STAT_CRIT_CHANCE
    movzx   r8d, word [rpg_ext + RPGEXT.attr + ATTR_INT*2]
    add     [rpg_stats + STAT_SPELL_DMG*4], r8d
    lea     eax, [r8 + r8]
    add     [rpg_stats + STAT_MAX_MANA*4], eax
    ADD_DIV 10, STAT_MANA_REGEN
    movzx   eax, word [rpg_ext + RPGEXT.attr + ATTR_VIT*2]
    add     [rpg_stats + STAT_MAX_HEALTH*4], eax
    add     [rpg_stats + STAT_STAMINA_REGEN*4], eax
    KS_STAT KS_JUGGERNAUT, STAT_ARMOR_BONUS, 4
    KS_STAT KS_JUGGERNAUT, STAT_MOVE_SPEED, -15
    KS_STAT KS_INFERNO, STAT_FROST_DMG, -50
    KS_STAT KS_BLOOD_MAGIC, STAT_SPELL_DMG, 30
    KS_STAT KS_WIND_RUNNER, STAT_MOVE_SPEED, 20
    KS_STAT KS_VENOM_BLADES, STAT_CRIT_DMG, -30
    KS_STAT KS_VENOM_BLADES, STAT_POISON_DMG, 50
    lea     rdi, [rpg_stats]
    call    gear_add_stats
    call    rpg_clamp_stats
    bt      dword [rpg_keystones], KS_BLOODRAGE
    jnc     .publish
    mov     eax, [rpg_stats + STAT_MAX_HEALTH*4]
    imul    eax, eax, 9
    xor     edx, edx
    mov     ecx, 10
    div     ecx                         ; 90% of the health, rounded down, at least 2
    mov     ecx, 2
    cmp     eax, ecx
    cmovl   eax, ecx
    mov     [rpg_stats + STAT_MAX_HEALTH*4], eax
.publish:
    mov     eax, [rpg_stats + STAT_MAX_HEALTH*4]
    mov     [surv_max_health], eax
    cmp     [surv + SURVIVAL.health], eax
    jle     .hp_ok
    mov     [surv + SURVIVAL.health], eax
.hp_ok:
    cvtsi2ss xmm0, dword [rpg_stats + STAT_MAX_MANA*4]
    movss   xmm1, [combat_mana]
    minss   xmm1, xmm0
    movss   [combat_mana], xmm1
    cvtsi2ss xmm0, dword [rpg_stats + STAT_MAX_STAMINA*4]
    movss   xmm1, [combat_stamina]
    minss   xmm1, xmm0
    movss   [combat_stamina], xmm1
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- lifecycle ---------------------------------------------------------------

; ext_reset(): no ranks, no attribute points, the current version. Leaf.
ext_reset:
    lea     rdi, [rpg_ext]
    mov     ecx, RPGEXT_size
    xor     eax, eax
    rep     stosb
    mov     byte [rpg_ext + RPGEXT.version], RPGX_VERSION
    ret

; rpg_reset(): a character without a class: level 1, nothing else, stats recomputed
rpg_reset:
    push    rbp
    mov     rbp, rsp
    lea     rdi, [rpg_state]
    mov     ecx, RPGSAVE_size
    xor     eax, eax
    rep     stosb
    mov     byte [rpg_state + RPGSAVE.level], 1
    call    ext_reset
    call    rpg_recompute
    pop     rbp
    ret

; rpg_give_item(edi id, esi count): into the inventory, what does not fit is dropped at the
; player's feet
rpg_give_item:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    inv_add
    test    eax, eax
    jz      .done
    mov     esi, eax
    mov     edi, ebx
    xor     edx, edx
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.y]
    addss   xmm1, [f_drop_y]
    movss   xmm2, [player + BODY.z]
    call    drops_spawn
.done:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; give_kit(rdi pairs): rpg_give_item for each (id, count) pair, ended by a 0 id
give_kit:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
.l:
    movzx   edi, byte [rbx]
    test    edi, edi
    jz      .done
    movzx   esi, byte [rbx + 1]
    call    rpg_give_item
    add     rbx, 2
    jmp     .l
.done:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; rpg_set_class(edi class) -> eax 1 when the class was set (only while the character has none,
; class 1..4): level 1, no XP, no ranks or attribute points, the starting kit, stats recomputed,
; resources refilled. 0 otherwise.
rpg_set_class:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    xor     eax, eax
    cmp     byte [rpg_state + RPGSAVE.class], 0
    jne     .ret
    lea     ecx, [rdi - 1]
    cmp     ecx, NUM_CLASSES
    jae     .ret
    mov     ebx, edi
    mov     [rpg_state + RPGSAVE.class], bl
    mov     byte [rpg_state + RPGSAVE.level], 1
    mov     dword [rpg_state + RPGSAVE.xp], 0
    call    ext_reset
    call    rpg_recompute
    lea     rax, [kit_tab]
    mov     rdi, [rax + rbx*8 - 8]
    call    give_kit
    lea     rdi, [kit_common]
    call    give_kit
    cmp     ebx, CLASS_WARRIOR
    jne     .refill
    lea     rax, [inv + INVENTORY.armor + 4]    ; the chest slot, worn when it is free
    cmp     byte [rax + 1], 0
    jne     .bag
    mov     dword [rax], IRON_CHESTPLATE | (1 << 8)
    jmp     .refill
.bag:
    mov     edi, IRON_CHESTPLATE
    mov     esi, 1
    call    rpg_give_item
.refill:
    call    combat_refill
    mov     eax, 1
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; rpg_add_xp(edi amount): the amount, raised by XP_BONUS percent (integer), goes into the current
; level; every full bar is a level (up to 50, where the XP stays 0). Does nothing without a class
; or at level 50. Gaining one or more levels refills health, mana and stamina, plays the level-up
; sound and shows one banner and one burst for the final level.
rpg_add_xp:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    cmp     byte [rpg_state + RPGSAVE.class], 0
    je      .ret
    cmp     byte [rpg_state + RPGSAVE.level], MAX_LEVEL
    jae     .ret
    mov     ecx, [rpg_stats + STAT_XP_BONUS*4]
    add     ecx, 100
    jns     .scale
    xor     ecx, ecx
.scale:
    mov     eax, edi
    imul    rax, rcx                    ; amount * (100 + bonus) / 100 in 64 bits, saturated
    xor     edx, edx
    mov     ecx, 100
    div     rcx
    mov     edx, -1
    cmp     rax, rdx
    cmova   rax, rdx
    mov     ebx, [rpg_state + RPGSAVE.xp]
    add     ebx, eax
    jnc     .sum
    mov     ebx, -1                     ; saturate instead of wrapping
.sum:
    xor     r12d, r12d                  ; levels gained
.loop:
    movzx   edi, byte [rpg_state + RPGSAVE.level]
    call    rpg_xp_need
    test    eax, eax
    jz      .capped                     ; level 50: the bar is gone
    cmp     ebx, eax
    jb      .store
    sub     ebx, eax
    inc     byte [rpg_state + RPGSAVE.level]
    inc     r12d
    jmp     .loop
.capped:
    xor     ebx, ebx
.store:
    mov     [rpg_state + RPGSAVE.xp], ebx
    test    r12d, r12d
    jz      .ret
    call    rpg_recompute               ; publishes surv_max_health
    mov     eax, [surv_max_health]
    mov     [surv + SURVIVAL.health], eax
    call    combat_refill
    mov     edi, SND_LEVELUP
    movss   xmm0, [f_vol_full]
    call    audio_play
    lea     rdi, [banner]               ; "Level N!"
    lea     rsi, [s_level]
    call    str_append
    movzx   edi, byte [rpg_state + RPGSAVE.level]
    mov     rsi, rax
    call    i32_to_str
    mov     byte [rax], '!'
    mov     byte [rax + 1], 0
    lea     rdi, [banner]
    mov     esi, RGBA(255, 215, 60, 255)
    call    hud_banner
    movss   xmm0, [player + BODY.x]
    movss   xmm1, [player + BODY.y]
    addss   xmm1, [f_chest]
    movss   xmm2, [player + BODY.z]
    movss   xmm3, [f_burst]
    mov     edi, FX_GOLD
    mov     esi, 30
    call    fx_burst
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- skill and attribute points ---------------------------------------------------

; rpg_can_spend(edi node) -> eax 0 when a point can go into the node, else why not (the first
; failing check wins): 5 no class, 1 no points, 2 node at its max rank (or no such node),
; 3 level below the tier's requirement, 4 the previous node of the branch has rank 0
rpg_can_spend:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi                    ; node
    mov     eax, 5
    cmp     byte [rpg_state + RPGSAVE.class], 0
    je      .ret
    call    rpg_points
    mov     ecx, eax
    mov     eax, 1
    test    ecx, ecx
    jz      .ret
    mov     eax, 2
    cmp     ebx, NUM_NODES
    jae     .ret
    movzx   edi, byte [rpg_state + RPGSAVE.class]
    mov     esi, ebx
    call    rpg_node_info
    movzx   ecx, byte [rax + NODEINFO.max]
    lea     rdx, [rpg_ext + RPGEXT.ranks]
    movzx   edx, byte [rdx + rbx]
    mov     eax, 2
    cmp     edx, ecx
    jae     .ret
    mov     eax, ebx
    xor     edx, edx
    mov     ecx, NODES_PER_BRANCH
    div     ecx
    mov     ecx, edx                    ; tier
    lea     rdx, [tier_level]
    movzx   edx, byte [rdx + rcx]
    mov     eax, 3
    cmp     byte [rpg_state + RPGSAVE.level], dl
    jb      .ret
    mov     eax, 4
    test    ecx, ecx
    jz      .ok                         ; tier 0 has no prerequisite
    lea     rdx, [rpg_ext + RPGEXT.ranks]
    cmp     byte [rdx + rbx - 1], 0
    je      .ret
.ok:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; rpg_spend(edi node) -> eax 1 when a point was spent (rank + 1, stats recomputed, click)
rpg_spend:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    call    rpg_can_spend
    test    eax, eax
    jnz     .no
    lea     rdx, [rpg_ext + RPGEXT.ranks]
    inc     byte [rdx + rbx]
    call    rpg_recompute
    mov     edi, SND_CLICK
    movss   xmm0, [f_vol_click]
    call    audio_play
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; rpg_spend_attr(edi a) -> eax 1 when an attribute point was spent in attribute 0..3 (points
; left, stats recomputed, click), else 0
rpg_spend_attr:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    cmp     edi, NUM_ATTRS
    jae     .no
    mov     ebx, edi
    call    rpg_attr_points
    test    eax, eax
    jz      .no
    lea     rdx, [rpg_ext + RPGEXT.attr]
    inc     word [rdx + rbx*2]
    call    rpg_recompute
    mov     edi, SND_CLICK
    movss   xmm0, [f_vol_click]
    call    audio_play
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; rpg_respec_cost() -> eax coins a respec costs: 5 per level
rpg_respec_cost:
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    imul    eax, eax, 5
    ret

; rpg_respec() -> eax 1 when the character paid rpg_respec_cost() coins out of the inventory and
; every skill rank and attribute point was handed back (stats recomputed, coin sound, banner); 0,
; with nothing changed, without a class or without enough coins
rpg_respec:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    xor     eax, eax
    cmp     byte [rpg_state + RPGSAVE.class], 0
    je      .ret
    call    rpg_respec_cost
    mov     ebx, eax
    mov     edi, GOLD_COIN
    call    inv_count
    cmp     eax, ebx
    jb      .poor
    mov     r12d, ebx
.take:
    mov     edi, GOLD_COIN
    call    inv_remove_one
    dec     r12d
    jnz     .take
    lea     rdi, [rpg_ext]
    mov     ecx, RPGEXT.version         ; the ranks and the attribute points
    xor     eax, eax
    rep     stosb
    call    rpg_recompute
    mov     edi, SND_COIN
    movss   xmm0, [f_vol_coin]
    call    audio_play
    lea     rdi, [s_respec]
    mov     esi, RGBA(255, 215, 60, 255)
    call    hud_banner
    mov     eax, 1
    jmp     .ret
.poor:
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- events ------------------------------------------------------------------------

; rpg_on_mob_killed(edi type, esi elite, edx level): XP for a kill the player earned:
; kill_xp[type] * (9 + level) / 10, x3 for an elite; then LIFE_ON_KILL health; then the quests
rpg_on_mob_killed:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    xor     eax, eax
    cmp     ebx, NUM_MOB_TYPES
    ja      .xp
    lea     rcx, [kill_xp]
    movzx   eax, byte [rcx + rbx]
    lea     ecx, [r13 + 9]
    imul    eax, ecx
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    test    r12d, r12d
    jz      .xp
    lea     eax, [rax + rax*2]
.xp:
    test    eax, eax
    jz      .heal
    mov     edi, eax
    call    rpg_add_xp
.heal:
    mov     edi, [rpg_stats + STAT_LIFE_ON_KILL*4]
    test    edi, edi
    jle     .quest
    call    combat_heal
.quest:
    mov     edi, ebx
    mov     esi, r12d
    call    quests_on_kill
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; rpg_on_block_mined(edi block): XP for mining coal 2, iron 5, gold 8 or diamond 20
rpg_on_block_mined:
    lea     rcx, [ore_xp]
.l:
    movzx   eax, byte [rcx]
    test    eax, eax
    jz      .none
    cmp     eax, edi
    je      .hit
    add     rcx, 2
    jmp     .l
.hit:
    movzx   edi, byte [rcx + 1]
    jmp     rpg_add_xp
.none:
    ret

; rpg_on_death(): the bar is lost; level, ranks and attribute points stay
rpg_on_death:
    mov     dword [rpg_state + RPGSAVE.xp], 0
    ret

; ---- save file -------------------------------------------------------------------------

; rpg_save(rdi header): rpg_state -> WORLDHDR.rpg, rpg_ext -> WORLDHDR.rpgx
rpg_save:
    mov     rdx, rdi
    lea     rsi, [rpg_state]
    lea     rdi, [rdx + WORLDHDR.rpg]
    mov     ecx, RPGSAVE_size
    rep     movsb
    lea     rsi, [rpg_ext]
    lea     rdi, [rdx + WORLDHDR.rpgx]
    mov     ecx, RPGEXT_size
    rep     movsb
    ret

; rpg_load(rdi header): WORLDHDR.rpg -> rpg_state and WORLDHDR.rpgx -> rpg_ext, made consistent,
; then the stats. A class outside 1..4 (zeros in an old save are "no class") or a level outside
; 1..50 rebuilds the character from scratch. A record of version 0 (a save from before the 0.8
; trees) loses its ranks and attribute points with a banner: everything is refunded. Ranks above
; a node's maximum, adding up to more than the level, or in a node whose predecessor in its branch
; has none are dropped; attribute points adding up to more than 3 per level above the first are
; dropped; xp is kept below the bar; quest and quest_state are masked to their ranges. The old
; cleared and flags bytes of the record are not read any more (0.9: the dungeons and the crypt keep
; their state in WORLDHDR.sites).
rpg_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rdx, rdi
    lea     rsi, [rdx + WORLDHDR.rpg]
    lea     rdi, [rpg_state]
    mov     ecx, RPGSAVE_size
    rep     movsb
    lea     rsi, [rdx + WORLDHDR.rpgx]
    lea     rdi, [rpg_ext]
    mov     ecx, RPGEXT_size
    rep     movsb
    movzx   eax, byte [rpg_state + RPGSAVE.class]
    dec     eax
    cmp     eax, NUM_CLASSES
    jae     .reset
    movzx   ebx, byte [rpg_state + RPGSAVE.level]
    lea     eax, [rbx - 1]
    cmp     eax, MAX_LEVEL
    jae     .reset
    cmp     byte [rpg_ext + RPGEXT.version], 0
    jne     .ranks
    lea     rdi, [rpg_ext]              ; the old trees: all points are refunded
    mov     ecx, RPGEXT.version
    xor     eax, eax
    rep     stosb
    lea     rdi, [s_refund]
    mov     esi, RGBA(255, 215, 60, 255)
    call    hud_banner
.ranks:
    lea     r8, [rpg_ext + RPGEXT.ranks]
    lea     r9, [node_tab]
    movzx   eax, byte [rpg_state + RPGSAVE.class]
    dec     eax
    imul    eax, eax, NUM_NODES * NODEINFO_size
    add     r9, rax                     ; the class's first node
    xor     ecx, ecx                    ; node
    xor     edx, edx                    ; sum of ranks
.branch:
    xor     r10d, r10d                  ; tier
.rank:
    movzx   eax, byte [r8 + rcx]
    cmp     al, [r9 + NODEINFO.max]
    ja      .bad_ranks
    add     edx, eax
    test    eax, eax
    jz      .rank_next
    test    r10d, r10d
    jz      .rank_next                  ; tier 0 needs no predecessor
    cmp     byte [r8 + rcx - 1], 0
    je      .bad_ranks
.rank_next:
    add     r9, NODEINFO_size
    inc     ecx
    inc     r10d
    cmp     r10d, NODES_PER_BRANCH
    jb      .rank
    cmp     ecx, NUM_NODES
    jb      .branch
    cmp     edx, ebx
    jbe     .ranks_ok
.bad_ranks:
    lea     rdi, [rpg_ext + RPGEXT.ranks]
    mov     ecx, RPGEXT.attr - RPGEXT.ranks
    xor     eax, eax
    rep     stosb
.ranks_ok:
    lea     eax, [rbx - 1]
    imul    eax, eax, ATTR_PER_LEVEL    ; attribute points the level has paid
    movzx   edx, word [rpg_ext + RPGEXT.attr + 0]
    movzx   ecx, word [rpg_ext + RPGEXT.attr + 2]
    add     edx, ecx
    movzx   ecx, word [rpg_ext + RPGEXT.attr + 4]
    add     edx, ecx
    movzx   ecx, word [rpg_ext + RPGEXT.attr + 6]
    add     edx, ecx
    cmp     edx, eax
    jbe     .attrs_ok
    mov     qword [rpg_ext + RPGEXT.attr], 0
.attrs_ok:
    mov     byte [rpg_ext + RPGEXT.version], RPGX_VERSION
    mov     edi, ebx
    call    rpg_xp_need
    test    eax, eax
    jnz     .xp
    mov     dword [rpg_state + RPGSAVE.xp], 0   ; level 50 has no bar
    jmp     .fields
.xp:
    cmp     [rpg_state + RPGSAVE.xp], eax
    jb      .fields
    dec     eax
    mov     [rpg_state + RPGSAVE.xp], eax       ; just below the bar
.fields:
    cmp     byte [rpg_state + RPGSAVE.quest], NUM_QUESTS
    jbe     .quest_ok
    mov     byte [rpg_state + RPGSAVE.quest], 0
.quest_ok:
    cmp     byte [rpg_state + RPGSAVE.quest_state], 1
    jbe     .state_ok
    mov     byte [rpg_state + RPGSAVE.quest_state], 0
.state_ok:
    call    rpg_recompute
    jmp     .ret
.reset:
    call    rpg_reset
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
