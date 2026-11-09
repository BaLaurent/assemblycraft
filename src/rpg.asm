; rpg.asm - the character: level, XP, the skill web, the ability bar, attribute points and the
; stats derived from them. rpg_state is the live progression stored in WORLDHDR.rpg; rpg_ext is the
; extension stored in WORLDHDR.rpgx: the rank of every node of the shared skill web (110 nodes: a
; path node per archetype, 90 archetype nodes, 15 bridges between neighbouring archetypes), the
; attribute points, the four-slot ability bar and the starting kits already given. rpg_stats is
; rebuilt from both by rpg_recompute (base row, level, path ranks, node ranks, attributes,
; keystones, equipped gear, then caps). Skill and attribute points are never stored: skill points
; = level - sum of ranks, attribute points = 3 * (level - 1) - sum of attributes. There are no
; classes: the archetype ("Warrior", "Spellblade", ...) is read off the ranks spent. This file also
; owns the static web / ability / stat / attribute description tables the screens read (record
; layouts in common.inc).
;
; The web: nodes are WEBNODE records generated below by macros from the layout of the design (the
; owner and level of a node follow from where its row stands, its cell is part of the row, the edges
; between neighbours come from a generator), so a new archetype or passive is a table row. A node
; can be ranked when it is reachable: a path node always is, any other node when a node linked to it
; has a rank (edges in web_edges).
%include "common.inc"
default rel

global rpg_state, rpg_ext, rpg_stats, rpg_keystones, rpg_migrated
global rpg_reset, rpg_level, rpg_points, rpg_xp_need, rpg_add_xp, rpg_begin
global rpg_rank, rpg_can_spend, rpg_spend, rpg_stat, rpg_recompute, rpg_clamp_stats
global rpg_attr, rpg_attr_points, rpg_spend_attr, rpg_attr_info, rpg_attr_desc
global rpg_respec_cost, rpg_respec, rpg_respec_free, rpg_keystone
global rpg_set_level, rpg_add_bonus_points, debug_stat_bonus
global rpg_web_node, rpg_web_linked, rpg_reachable, web_edges, web_edge_count
global rpg_ability_learned, rpg_ability_info, rpg_ability_tile, rpg_path_tile, rpg_bar_ability, rpg_bar_set
global rpg_archetype_ranks, rpg_archetype, rpg_archetype_name, rpg_title
global rpg_stat_info, rpg_format_stat
global rpg_on_mob_killed, rpg_on_block_mined, rpg_on_death, rpg_load, rpg_save, rpg_give_item

extern surv, surv_max_health, combat_mana, combat_stamina, combat_refill, combat_heal
extern inv, inv_add, inv_count, inv_remove_one, drops_spawn, player
extern audio_play, hud_banner, fx_burst, quests_on_kill
extern str_append, i32_to_str, key_name, settings
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
s_migrated:  db "Classes became one grimoire: skill points refunded", 0
s_migrated_mk: db "New Marksman path: skill points refunded", 0
s_begin_a:   db "Open your grimoire (", 0
s_begin_b:   db ") to choose a path", 0

; base stats (row 0: the classless character; rows 1..5: what the path node of that archetype
; stands for, rpg_recompute adds row a minus row 0 for a ranked path), in stat-id order:
; HEALTH MELEE RANGED SPELL CRIT CRITDMG MANA MANAREGEN STAMINA STAMREGEN ARMOR SPEED
; BACKSTAB PARRY LIFESTEAL COOLDOWN ARROWSAVE DODGECOST, then stats 18..43 (all 0), then GUNDMG
; RELOADSPEED (the Marksman's only)
base_stats:
    dd 20,  0,  0,  0,  0, 0,   0, 0, 100, 0, 0, 0,   0, 0, 0, 0,  0, 0   ; none
    times NUM_STATS - 18 dd 0
    dd 28, 10,  0,  0,  5, 0,   0, 0, 120, 0, 2, 0,   0, 0, 0, 0,  0, 0   ; Warrior
    times NUM_STATS - 18 dd 0
    dd 18,  0,  0, 10,  5, 0, 100, 4,  80, 0, 0, 0,   0, 0, 0, 0,  0, 0   ; Mage
    times NUM_STATS - 18 dd 0
    dd 20,  0, 20,  0,  8, 0,   0, 0, 100, 0, 0, 5,   0, 0, 0, 0, 10, 0   ; Archer
    times NUM_STATS - 18 dd 0
    dd 24,  0,  0,  0, 10, 0,   0, 0, 110, 10, 0, 5, 100, 0, 0, 0,  0, 0  ; Rogue
    times NUM_STATS - 18 dd 0
    dd 20,  0,  0,  0,  8, 10,  0, 0, 100, 0, 0, 0,   0, 0, 0, 0, 10, 0   ; Marksman
    times STAT_GUN_DMG - 18 dd 0
    dd 15, 15                           ; gun damage, reload speed
%if $ - base_stats != (NUM_ARCHETYPES + 1) * NUM_STATS * 4
%error "base_stats needs NUM_STATS dwords per archetype row"
%endif

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

; starting kits: (item id, count) pairs ended by a 0 id. Taking the path of an archetype for the first
; time gives its kit once (RPGEXT.kits); every character gets the common kit once (rpg_begin)
kit_warrior: db IRON_SWORD, 1, 0
kit_mage:    db STAFF, 1, MANA_POTION, 2, 0
kit_archer:  db BOW, 1, ARROW, 32, 0
kit_rogue:   db IRON_DAGGER, 1, HEALTH_POTION, 2, 0
kit_marksman: db PISTOL, 1, PISTOL_ROUND, 32, 0     ; the pistol arrives unloaded: R reloads it
kit_common:  db COOKED_PORKCHOP, 4, 0
align 8
kit_tab:     dq kit_warrior, kit_mage, kit_archer, kit_rogue, kit_marksman

; ---- description tables ----------------------------------------------------

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
    STATI "Arrow save",       "% ammo saved",               FMT_PCT,    TILE_STAT0 + STAT_ARROW_SAVE
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
    STATI "Gun damage",       "% gun damage",               FMT_PCT,    TILE_STAT_GUN
    STATI "Reload speed",     "% reload speed",             FMT_PCT,    TILE_STAT_RELOAD
%if $ - stat_tab != NUM_STATS * STATINFO_size
%error "stat_tab needs one record per stat"
%endif

; ABILINFO record; the labels let the matching skill node share the name and text, and the
; aname_ constant lets the path node of an archetype name the ability it teaches
%macro ABIL 6                           ; label, name, desc, resource, cost, cooldown_s
%define aname_%1 %2
section .rodata.str
an_%1: db %2, 0
ad_%1: db %3, 0
section .rodata
    dq an_%1, ad_%1
    dd %4, %5, %6, 0
%endmacro

align 8
abil_tab:                               ; by ability id = (archetype - 1) * 4 + slot
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
    ABIL grenade,   "Powder Grenade",  "Lob a grenade that bursts into flame", RES_STAMINA, 30, 8
    ABIL bullseye,  "Bullseye",        "Shots fly true and crit more",      RES_STAMINA, 20, 15
    ABIL fanhammer, "Fan the Hammer",  "Fire twice as fast, rounds are free", RES_STAMINA, 50, 30
    ABIL flashbang, "Flashbang",       "Throw a flash that stuns foes",     RES_STAMINA, 35, 12
%if $ - abil_tab != NUM_ABILITIES * ABILINFO_size
%error "abil_tab needs one record per ability"
%endif

; ---- the skill web -------------------------------------------------------------------------
; Node ids: the path of archetype a is a - 1 (0..4); node n (= branch * 6 + tier, 0..17) of
; archetype a is 5 + (a - 1) * 18 + n (5..94); bridge k (0..2) owned by archetype a, which joins it
; to the next archetype clockwise, is 95 + (a - 1) * 3 + k (95..109). The ids are not places: the
; archetypes sit on a ring, clockwise Warrior, Mage, Marksman, Rogue, Archer (the sector of ring
; position p = 0..4 is centred 72 * p degrees clockwise of north). Each row of the table carries
; the cell of its node: x, y in 1/8 cell (WEB_SUB), screen axes (y down), all within +-WEB_EXTENT.
; They follow the layout of the design: the path at radius 2 cells on its sector axis, tier t of a
; branch at radius 3.4 + 1.1 t, branch b at (b - 1) * 20 degrees off the axis (branch 0 leans
; towards the previous archetype of the ring, branch 2 towards the next), bridge k at the radius of
; tier 2k + 1 on the boundary 36 degrees clockwise of the axis; x = round(8 r sin(theta)),
; y = round(-8 r cos(theta)). The rows say what a node is and where it lies; the macros work out its
; owner and level from where it stands in the table (wb_arch, wb_n, wb_k count as the assembler goes).
%assign wb_arch 0                       ; archetype whose rows are being emitted (1..5)
%assign wb_n    0                       ; index of the next archetype node (branch * 6 + tier)
%assign wb_k    0                       ; index of the next bridge after wb_arch

; TLEVEL tier: wt_level = the level a node of that tier asks for
%macro TLEVEL 1
  %if %1 == 0
    %assign wt_level 1
  %elif %1 == 1
    %assign wt_level 4
  %elif %1 == 2
    %assign wt_level 9
  %elif %1 == 3
    %assign wt_level 15
  %elif %1 == 4
    %assign wt_level 22
  %else
    %assign wt_level 30
  %endif
%endmacro

; WREC name, desc, kind, stat, max, owner, value, x, y, level: one WEBNODE; the cell x, y is in 1/8 cell
%macro WREC 10
    dq %1, %2
    db %3, %4, %5, %6
    dd %7
    db %8, %9, %10
    times 5 db 0
%endmacro

; FORMER name, desc, kind, stat, max, value, x, y: the next archetype node of wb_arch (a node of the
; 0.10.1 class trees)
%macro FORMER 8
    %assign wf_b wb_n / 6
    %assign wf_t wb_n - wf_b * 6
    TLEVEL wf_t
    WREC %1, %2, %3, %4, %5, wb_arch, %6, %7, %8, wt_level
    %assign wb_n wb_n + 1
%endmacro

; a passive stat node (max rank 5) without a text of its own, since the text is always the stat's
; formatted value (rpg_format_stat) ...
%macro SNODE 5                          ; name, stat, value per rank, x, y
section .rodata.str
%%n: db %1, 0
section .rodata
    FORMER %%n, 0, NODE_STAT, %2, 5, %3, %4, %5
%endmacro
; ... an ability node (max rank 1): name and text come from the ability record; its stat is the
; ability id ...
%macro ANODE 4                          ; ability label, ability slot, x, y
    FORMER an_%1, ad_%1, NODE_ABILITY, (wb_arch - 1) * 4 + %2, 1, 0, %3, %4
%endmacro
; ... and a keystone (max rank 1) whose effect is coded where it applies
%macro KNODE 5                          ; name, keystone id, description, x, y
section .rodata.str
%%n: db %1, 0
%%d: db %3, 0
section .rodata
    FORMER %%n, %%d, NODE_KEYSTONE, %2, 1, 0, %4, %5
%endmacro

; the path node of the next archetype: its text is the three lines of the former class card plus
; the ability it teaches; its stat is the archetype
%macro PATHNODE 7                       ; name, line1, line2, line3, ability label (slot 0), x, y
section .rodata.str
%%n: db %1, 0
%%d: db %2, ". ", %3, ". ", %4, ". Learns ", aname_%5, ".", 0
section .rodata
    %assign wb_arch wb_arch + 1
    WREC %%n, %%d, NODE_PATH, wb_arch, 1, wb_arch, 0, %6, %7, 1
%endmacro

; the rows of archetype %1 follow
%macro ARCHETYPE 1
    %assign wb_arch %1
    %assign wb_n 0
%endmacro

; the bridges after archetype %1 follow
%macro BRIDGES 1
    %assign wb_arch %1
    %assign wb_k 0
%endmacro
; a bridge (max rank 3, owned by nobody): name, stat, value per rank, x, y
%macro BRIDGE 5
section .rodata.str
%%n: db %1, 0
section .rodata
    %assign wb_t 2 * wb_k + 1
    TLEVEL wb_t
    WREC %%n, 0, NODE_STAT, %2, 3, 0, %3, %4, %5, wt_level
    %assign wb_k wb_k + 1
%endmacro

align 8
web_tab:                                ; by node id
    PATHNODE "Path of the Warrior", "Heavy armor", "Charge and cleave", "Parry master", charge, 0, -16
    PATHNODE "Path of the Mage", "Fire and arcane", "Staff bolts", "Fragile, deadly", fireball, 15, -5
    PATHNODE "Path of the Archer", "Bows and volleys", "Deadly at range", "Swift hunter", volley, -15, -5
    PATHNODE "Path of the Rogue", "Daggers, stealth", "Backstab x2", "Shadowstep", shadowstp, -9, 13
    PATHNODE "Path of the Marksman", "Guns and powder", "Dexterity raises gun damage", "Crit-hungry, fragile", grenade, 9, 13
    ARCHETYPE 1                         ; Warrior: Blademaster, Bulwark, Endurance
    SNODE "Weapon Mastery", STAT_MELEE_DMG,     6, -9, -26
    SNODE "Precision",      STAT_CRIT_CHANCE,   3, -12, -34
    SNODE "Brutality",      STAT_CRIT_DMG,     15, -15, -42
    SNODE "Bloodthirst",    STAT_LIFESTEAL,     2, -18, -50
    SNODE "Swift Blade",    STAT_ATTACK_SPEED,  5, -21, -59
    KNODE "Executioner",    KS_EXECUTIONER, "Melee hits on foes under 30% health deal +60% damage", -24, -67
    SNODE "Toughness",      STAT_MAX_HEALTH,    4, 0, -27
    ANODE warcry, 1, 0, -36
    SNODE "Iron Skin",      STAT_ARMOR_BONUS,   2, 0, -45
    ANODE whirl, 2, 0, -54
    SNODE "Shield Wall",    STAT_BLOCK_COST,   10, 0, -62
    KNODE "Juggernaut",     KS_JUGGERNAUT, "No knockback, +4 armor, -15% move speed", 0, -71
    SNODE "Stamina",        STAT_MAX_STAMINA,  12, 9, -26
    SNODE "Second Wind",    STAT_STAMINA_REGEN, 10, 12, -34
    SNODE "Riposte",        STAT_PARRY_WINDOW,  1, 15, -42
    ANODE slam, 3, 18, -50
    SNODE "Spiked Mail",    STAT_THORNS,        3, 21, -59
    KNODE "Bloodrage",      KS_BLOODRAGE, "+1% damage per 2% missing health, -10% max health", 24, -67
    ARCHETYPE 2                         ; Mage: Fire, Arcane, Warding
    SNODE "Pyromancy",      STAT_SPELL_DMG,     6, 21, -17
    SNODE "Kindling",       STAT_FIRE_DMG,      8, 28, -22
    SNODE "Combustion",     STAT_CRIT_DMG,     15, 35, -28
    SNODE "Fire Touch",     STAT_ADD_FIRE,      1, 42, -33
    SNODE "Static",         STAT_SHOCK_DMG,     8, 49, -38
    KNODE "Inferno",        KS_INFERNO, "Spell hits ignite; burning foes take +25% spell damage; -50% frost damage", 56, -44
    SNODE "Deep Mind",      STAT_MAX_MANA,     15, 26, -8
    ANODE blink, 1, 34, -11
    SNODE "Flow",           STAT_MANA_REGEN,    1, 43, -14
    ANODE meteor, 2, 51, -17
    SNODE "Haste",          STAT_COOLDOWN_RED,  4, 59, -19
    KNODE "Blood Magic",    KS_BLOOD_MAGIC, "Mana costs are paid with health (1 per 5 mana); +30% spell damage", 68, -22
    SNODE "Vitality",       STAT_MAX_HEALTH,    3, 27, 1
    SNODE "Frost Weaving",  STAT_FROST_DMG,     8, 36, 1
    SNODE "Arcane Reach",   STAT_AREA,          8, 45, 2
    ANODE nova, 3, 54, 2
    SNODE "Renewal",        STAT_LIFE_REGEN,    5, 62, 2
    KNODE "Mana Shield",    KS_MANA_SHIELD, "35% of damage taken drains mana instead (2 mana per point)", 71, 2
    ARCHETYPE 3                         ; Archer: Aim, Hunter, Survival
    SNODE "Steady Aim",     STAT_RANGED_DMG,    8, -27, 1
    SNODE "Eagle Eye",      STAT_CRIT_CHANCE,   3, -36, 1
    SNODE "Deadly Shot",    STAT_CRIT_DMG,     15, -45, 2
    SNODE "Quick Draw",     STAT_ATTACK_SPEED,  5, -54, 2
    SNODE "Big Game",       STAT_ELITE_DMG,     6, -62, 2
    KNODE "Deadeye",        KS_DEADEYE, "Fully drawn shots always crit; attack speed no longer speeds your draw", -71, 2
    SNODE "Fleet Foot",     STAT_MOVE_SPEED,    3, -26, -8
    ANODE explarrow, 1, -34, -11
    SNODE "Quiver",         STAT_ARROW_SAVE,   10, -43, -14
    ANODE arrowrain, 2, -51, -17
    SNODE "Toxic Tips",     STAT_ADD_POISON,    1, -59, -19
    KNODE "Barrage",        KS_BARRAGE, "Bow shots fire 2 extra arrows (60% damage); Volley fires 7", -68, -22
    SNODE "Vitality",       STAT_MAX_HEALTH,    3, -21, -17
    SNODE "Evasion",        STAT_DODGE_COST,   10, -28, -22
    SNODE "Second Wind",    STAT_STAMINA_REGEN, 10, -35, -28
    ANODE mark, 3, -42, -33
    SNODE "Readiness",      STAT_COOLDOWN_RED,  4, -49, -38
    KNODE "Wind Runner",    KS_WIND_RUNNER, "+20% move speed; dodges cost no stamina but recover twice as slowly", -56, -44
    ARCHETYPE 4                         ; Rogue: Assassin, Shadow, Agility
    SNODE "Backstab",       STAT_BACKSTAB,     20, -7, 26
    SNODE "Precision",      STAT_CRIT_CHANCE,   3, -10, 35
    SNODE "Cruelty",        STAT_CRIT_DMG,     15, -12, 43
    SNODE "Serrated",       STAT_BLEED_CHANCE,  8, -15, 52
    SNODE "Blade Mastery",  STAT_MELEE_DMG,     8, -17, 60
    KNODE "Assassinate",    KS_ASSASSINATE, "Backstabs kill non-boss foes under 25% health; +50% backstab vs bosses", -20, 68
    SNODE "Fleet Foot",     STAT_MOVE_SPEED,    3, -16, 22
    ANODE smoke, 1, -21, 29
    SNODE "Evasion",        STAT_DODGE_COST,   10, -26, 36
    ANODE bladedance, 2, -32, 43
    SNODE "Venom",          STAT_POISON_DMG,   10, -37, 50
    KNODE "Shadow Dance",   KS_SHADOW_DANCE, "Smoke Bomb stealth lasts 30 s; the first hit from stealth deals double", -42, 58
    SNODE "Endurance",      STAT_MAX_STAMINA,  12, -23, 15
    SNODE "Second Wind",    STAT_STAMINA_REGEN, 10, -30, 20
    SNODE "Leech",          STAT_LIFESTEAL,     2, -37, 25
    ANODE knives, 3, -44, 30
    SNODE "Lethality",      STAT_DOT_DMG,      10, -52, 35
    KNODE "Venom Blades",   KS_VENOM_BLADES, "Melee hits add 2 poison stacks; +50% poison damage; -30% crit damage", -59, 40
    ARCHETYPE 5                         ; Marksman: Gunslinger, Quartermaster, Demolitions
    SNODE "Steady Hands",   STAT_GUN_DMG,       6, 23, 15
    SNODE "Trigger Discipline", STAT_CRIT_CHANCE, 3, 30, 20
    SNODE "Hollow Points",  STAT_CRIT_DMG,     15, 37, 25
    SNODE "Bounty Hunter",  STAT_ELITE_DMG,     6, 44, 30
    SNODE "Fast Hands",     STAT_RELOAD_SPEED,  8, 52, 35
    KNODE "Deadshot",       KS_DEADSHOT, "Aimed shots always crit. Shots from the hip never crit.", 59, 40
    SNODE "Bandolier",      STAT_ARROW_SAVE,    8, 16, 22
    ANODE bullseye, 1, 21, 29
    SNODE "Speed Loader",   STAT_RELOAD_SPEED,  8, 26, 36
    ANODE fanhammer, 2, 32, 43
    SNODE "Tinkerer",       STAT_COOLDOWN_RED,  4, 37, 50
    KNODE "Quartermaster",  KS_QUARTERMASTER, "Your magazines hold 50% more rounds.", 42, 58
    SNODE "Vitality",       STAT_MAX_HEALTH,    3, 7, 26
    SNODE "Powder Burns",   STAT_FIRE_DMG,      8, 10, 35
    SNODE "Blast Radius",   STAT_AREA,          8, 12, 43
    ANODE flashbang, 3, 15, 52
    SNODE "Leather Coat",   STAT_ARMOR_BONUS,   1, 17, 60
    KNODE "Powder Keg",     KS_POWDER_KEG, "Grenade, flashbang and rocket blasts are 50% wider.", 20, 68
    BRIDGES 1                           ; Warrior - Mage
    BRIDGE "Runed Steel",   STAT_ADD_FIRE,       1, 21, -29
    BRIDGE "Warded Plate",  STAT_MAX_MANA,       10, 32, -43
    BRIDGE "Spellblade",    STAT_ALL_DMG,        4, 42, -58
    BRIDGES 2                           ; Mage - Marksman
    BRIDGE "Alchemist's Powder", STAT_FIRE_DMG,  6, 34, 11
    BRIDGE "Far Sight",     STAT_AREA,           6, 51, 17
    BRIDGE "Spellslinger",  STAT_ALL_DMG,        4, 68, 22
    BRIDGES 3                           ; Archer - Warrior
    BRIDGE "Riposte Edge",  STAT_CRIT_CHANCE,    2, -21, -29
    BRIDGE "Scarred Hide",  STAT_THORNS,         2, -32, -43
    BRIDGE "Warden",        STAT_WEAPON_DMG,     5, -42, -58
    BRIDGES 4                           ; Rogue - Archer
    BRIDGE "Barbed Shafts", STAT_BLEED_CHANCE,   6, -34, 11
    BRIDGE "Light Step",    STAT_MOVE_SPEED,     3, -51, 17
    BRIDGE "Skirmisher",    STAT_ATTACK_SPEED,   4, -68, 22
    BRIDGES 5                           ; Marksman - Rogue
    BRIDGE "Cold Read",     STAT_CRIT_CHANCE,    2, 0, 36
    BRIDGE "Light Fingers", STAT_DODGE_COST,     8, 0, 54
    BRIDGE "Gunslinger",    STAT_CRIT_DMG,       10, 0, 71
%if $ - web_tab != NUM_WEB_NODES * WEBNODE_size
%error "web_tab needs NUM_WEB_NODES records"
%endif

; the edges of the web, pairs of node ids (each joins its two nodes both ways):
;   path(a) - (a, b, 0) for each branch b;  (a, b, t) - (a, b, t + 1);
;   bridge(a, k) - (a, 2, 2k + 1) and (next(a), 0, 2k + 1);  bridge(a, k) - bridge(a, k + 1)
; where next(a) is the archetype after a on the ring: Warrior, Mage, Marksman, Rogue, Archer, Warrior
align 2
web_edges:
%assign wx_a 1
%rep NUM_ARCHETYPES
  %assign wx_path wx_a - 1
  %assign wx_base NUM_ARCHETYPES + (wx_a - 1) * 18
  %if wx_a == ARCH_WARRIOR
    %assign wx_next ARCH_MAGE
  %elif wx_a == ARCH_MAGE
    %assign wx_next ARCH_MARKSMAN
  %elif wx_a == ARCH_MARKSMAN
    %assign wx_next ARCH_ROGUE
  %elif wx_a == ARCH_ROGUE
    %assign wx_next ARCH_ARCHER
  %else
    %assign wx_next ARCH_WARRIOR
  %endif
  %assign wx_nbase NUM_ARCHETYPES + (wx_next - 1) * 18  ; the node base of next(a)
  %assign wx_bridge NUM_ARCHETYPES + NUM_ARCHETYPES * 18 + (wx_a - 1) * 3
  %assign wx_b 0
  %rep 3
    dw wx_path, wx_base + wx_b * 6
    %assign wx_t 0
    %rep 5
      dw wx_base + wx_b * 6 + wx_t, wx_base + wx_b * 6 + wx_t + 1
      %assign wx_t wx_t + 1
    %endrep
    %assign wx_b wx_b + 1
  %endrep
  %assign wx_k 0
  %rep 3
    dw wx_bridge + wx_k, wx_base + 2 * 6 + 2 * wx_k + 1
    dw wx_bridge + wx_k, wx_nbase + 2 * wx_k + 1
    %if wx_k < 2
      dw wx_bridge + wx_k, wx_bridge + wx_k + 1
    %endif
    %assign wx_k wx_k + 1
  %endrep
  %assign wx_a wx_a + 1
%endrep
web_edges_end:
%if (web_edges_end - web_edges) != 130 * 4
%error "the web has 130 edges"
%endif
align 4
web_edge_count: dd (web_edges_end - web_edges) / 4

; the archetype names and the titles of the pairs of archetypes (rpg_title); a pair is looked up
; by (lower - 1) * 5 + (higher - 1)
%macro PSTR 1                           ; a string in .rodata.str and its pointer in .rodata
section .rodata.str
%%s: db %1, 0
section .rodata
    dq %%s
%endmacro
align 8
arch_names:                             ; by archetype 0..5
    PSTR "Wanderer"
    PSTR "Warrior"
    PSTR "Mage"
    PSTR "Archer"
    PSTR "Rogue"
    PSTR "Marksman"
pair_titles:
    dq 0                                ; (1, 1)
    PSTR "Spellblade"                   ; (1, 2)
    PSTR "Warden"                       ; (1, 3)
    PSTR "Duelist"                      ; (1, 4)
    PSTR "Grenadier"                    ; (1, 5)
    times 2 dq 0                        ; (2, 1) (2, 2)
    PSTR "Arcane Archer"                ; (2, 3)
    PSTR "Nightblade"                   ; (2, 4)
    PSTR "Spellslinger"                 ; (2, 5)
    times 3 dq 0                        ; (3, 1) (3, 2) (3, 3)
    PSTR "Skirmisher"                   ; (3, 4)
    PSTR "Sharpshooter"                 ; (3, 5)
    times 4 dq 0                        ; (4, 1) .. (4, 4)
    PSTR "Gunslinger"                   ; (4, 5)
    times 5 dq 0                        ; (5, 1) .. (5, 5)
%if $ - pair_titles != 25 * 8
%error "pair_titles has 25 entries"
%endif

; what the info getters return for an index out of range
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
web_scratch: resb WEB_MAX               ; web_valid: 1 per ranked node joined to a ranked path
rpg_migrated: resb 1                    ; rpg_load refunded the web this session (rpg_begin keeps the banner)
alignb 2
debug_stat_bonus: resw NUM_STATS        ; the debug menu's flat bonus per stat (int16), added before the caps; saved in WORLDHDR.debug_stats

section .text

; ---- plain getters ----------------------------------------------------------

; rpg_level() -> eax 1..50
rpg_level:
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    ret

; web_ranks_total() -> eax the sum of the ranks of the NUM_WEB_NODES (110) web nodes (leaf; clobbers ecx, edx, rsi)
web_ranks_total:
    lea     rsi, [rpg_ext + RPGEXT.web]
    xor     eax, eax
    xor     ecx, ecx
.l:
    movzx   edx, byte [rsi + rcx]
    add     eax, edx
    inc     ecx
    cmp     ecx, NUM_WEB_NODES
    jb      .l
    ret

; rpg_points() -> eax unspent skill points = level + the debug menu's bonus points - sum of the web ranks
; (never negative)
rpg_points:
    sub     rsp, 8
    call    web_ranks_total
    movzx   ecx, byte [rpg_state + RPGSAVE.level]
    movzx   edx, word [rpg_ext + RPGEXT.bonus_sp]
    add     ecx, edx
    sub     ecx, eax
    xor     eax, eax
    test    ecx, ecx
    cmovns  eax, ecx
    add     rsp, 8
    ret

; rpg_attr_points() -> eax unspent attribute points = 3 * (level - 1) + the debug menu's bonus points - sum
; of the attributes (never negative)
rpg_attr_points:
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    dec     eax
    imul    eax, eax, ATTR_PER_LEVEL
    movzx   ecx, word [rpg_ext + RPGEXT.bonus_ap]
    add     eax, ecx
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

; rpg_rank(edi node) -> eax rank of web node 0..109 (0 for anything else)
rpg_rank:
    xor     eax, eax
    cmp     edi, NUM_WEB_NODES
    jae     .ret
    mov     ecx, edi
    lea     rdx, [rpg_ext + RPGEXT.web]
    movzx   eax, byte [rdx + rcx]
.ret:
    ret

; rpg_web_node(edi node) -> rax WEBNODE* of node 0..109, 0 for anything else (leaf)
rpg_web_node:
    xor     eax, eax
    cmp     edi, NUM_WEB_NODES
    jae     .ret
    mov     eax, edi
    shl     eax, 5                      ; WEBNODE_size
    lea     rcx, [web_tab]
    add     rax, rcx
.ret:
    ret
%if WEBNODE_size != 32
%error "rpg_web_node shifts by 5"
%endif

; rpg_web_linked(edi a, esi b) -> eax 1 when the web has an edge between nodes a and b (either
; way round), else 0 (leaf)
rpg_web_linked:
    lea     rdx, [web_edges]
    mov     ecx, [web_edge_count]
.l:
    movzx   eax, word [rdx]
    movzx   r8d, word [rdx + 2]
    cmp     eax, edi
    jne     .rev
    cmp     r8d, esi
    je      .yes
.rev:
    cmp     eax, esi
    jne     .next
    cmp     r8d, edi
    je      .yes
.next:
    add     rdx, 4
    dec     ecx
    jnz     .l
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; rpg_reachable(edi node) -> eax 1 when a point could go into the node as far as the web goes (no
; level or points asked): a path node always, any other node when a node linked to it has a rank;
; 0 for no such node (leaf)
rpg_reachable:
    xor     eax, eax
    cmp     edi, NUM_WEB_NODES
    jae     .ret
    mov     eax, 1
    cmp     edi, NUM_ARCHETYPES
    jb      .ret                        ; the paths are the way in
    lea     rdx, [web_edges]
    mov     ecx, [web_edge_count]
    lea     r9, [rpg_ext + RPGEXT.web]
.l:
    movzx   eax, word [rdx]
    movzx   r8d, word [rdx + 2]
    cmp     eax, edi
    jne     .other
    cmp     byte [r9 + r8], 0           ; (a, b) with a the node: b is its neighbour
    jne     .yes
    jmp     .next
.other:
    cmp     r8d, edi
    jne     .next
    cmp     byte [r9 + rax], 0          ; (a, b) with b the node
    jne     .yes
.next:
    add     rdx, 4
    dec     ecx
    jnz     .l
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
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

; rpg_keystone(edi ks) -> eax 1 when keystone 0..14 is taken (its node has a rank), else 0
rpg_keystone:
    xor     eax, eax
    cmp     edi, NUM_KEYSTONES
    jae     .ret
    mov     ecx, edi
    mov     eax, [rpg_keystones]
    shr     eax, cl
    and     eax, 1
.ret:
    ret

; ---- ability bar ------------------------------------------------------------

; rpg_ability_learned(edi ability) -> eax 1 when the ability 0..19 is taught by a ranked node: the
; path node of its archetype (slot 0) or the ability node whose stat is its id (slots 1..3); else 0
; (leaf)
rpg_ability_learned:
    xor     eax, eax
    cmp     edi, NUM_ABILITIES
    jae     .ret
    lea     rsi, [web_tab]
    lea     r8, [rpg_ext + RPGEXT.web]
    xor     ecx, ecx
.l:
    cmp     byte [r8 + rcx], 0
    je      .next
    movzx   edx, byte [rsi + WEBNODE.stat]
    cmp     byte [rsi + WEBNODE.kind], NODE_ABILITY
    je      .cmp
    cmp     byte [rsi + WEBNODE.kind], NODE_PATH
    jne     .next
    dec     edx                         ; a path node teaches ability (archetype - 1) * 4
    shl     edx, 2
.cmp:
    cmp     edx, edi
    je      .yes
.next:
    add     rsi, WEBNODE_size
    inc     ecx
    cmp     ecx, NUM_WEB_NODES
    jb      .l
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
.ret:
    ret

; rpg_bar_ability(edi slot) -> eax the ability id bound to bar slot 0..3, -1 for an empty slot or
; no such slot (leaf)
rpg_bar_ability:
    mov     eax, -1
    cmp     edi, NUM_ABILITY_SLOTS
    jae     .ret
    mov     ecx, edi
    lea     rdx, [rpg_ext + RPGEXT.bar]
    movzx   eax, byte [rdx + rcx]
    dec     eax                         ; stored as id + 1: an empty slot becomes -1
.ret:
    ret

; rpg_bar_set(edi slot, esi ability) -> eax 1 when bar slot 0..3 now holds the ability, or is empty
; for ability -1; 0 (nothing changed) for another slot or an ability that is not learned. An ability
; that was bound to another slot swaps places with what this slot held.
; ebx = slot, r12d = ability
rpg_bar_set:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    xor     eax, eax
    cmp     edi, NUM_ABILITY_SLOTS
    jae     .ret
    mov     ebx, edi
    mov     r12d, esi
    cmp     r12d, -1
    je      .clear
    mov     edi, r12d
    call    rpg_ability_learned
    test    eax, eax
    jz      .ret
    lea     rdx, [rpg_ext + RPGEXT.bar]
    lea     ecx, [r12 + 1]              ; the stored value
    xor     esi, esi
.find:
    cmp     [rdx + rsi], cl
    jne     .next
    cmp     esi, ebx
    je      .next                       ; already in this very slot
    mov     al, [rdx + rbx]             ; bound elsewhere: that slot takes what this one held
    mov     [rdx + rsi], al
    jmp     .set
.next:
    inc     esi
    cmp     esi, NUM_ABILITY_SLOTS
    jb      .find
.set:
    mov     [rdx + rbx], cl
    mov     eax, 1
    jmp     .ret
.clear:
    lea     rdx, [rpg_ext + RPGEXT.bar]
    mov     byte [rdx + rbx], 0
    mov     eax, 1
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; bar_put_first_empty(edi ability): the ability goes into the first empty bar slot, if there is one
; (leaf)
bar_put_first_empty:
    lea     rdx, [rpg_ext + RPGEXT.bar]
    xor     ecx, ecx
.l:
    cmp     byte [rdx + rcx], 0
    je      .set
    inc     ecx
    cmp     ecx, NUM_ABILITY_SLOTS
    jb      .l
    ret
.set:
    lea     eax, [rdi + 1]
    mov     [rdx + rcx], al
    ret

; ---- archetype and title ----------------------------------------------------

; arch_sums(rdi out dword[6]): the sum of the ranks of the nodes of owner 0 (the bridges), 1..5
; (leaf; clobbers eax, ecx, edx, rsi, r8)
arch_sums:
    xor     eax, eax
    mov     [rdi], rax
    mov     [rdi + 8], rax
    mov     [rdi + 16], rax
    lea     rsi, [web_tab]
    lea     r8, [rpg_ext + RPGEXT.web]
    xor     ecx, ecx
.l:
    movzx   eax, byte [rsi + WEBNODE.arch]
    movzx   edx, byte [r8 + rcx]
    add     [rdi + rax*4], edx
    add     rsi, WEBNODE_size
    inc     ecx
    cmp     ecx, NUM_WEB_NODES
    jb      .l
    ret

; rpg_archetype_ranks(edi arch) -> eax the sum of the ranks of the nodes owned by archetype 1..5
; (0 would be the bridges); 0 for another value. Keeps its argument in r9d across arch_sums, which
; leaves r9 alone.
rpg_archetype_ranks:
    sub     rsp, 24
    mov     r9d, edi
    mov     rdi, rsp
    call    arch_sums
    xor     eax, eax
    cmp     r9d, NUM_ARCHETYPES
    ja      .ret
    mov     eax, [rsp + r9*4]
.ret:
    add     rsp, 24
    ret

; rpg_archetype() -> eax the archetype 1..5 with the most ranks spent in its own nodes (ties go to
; the lower number), 0 while nothing is spent
rpg_archetype:
    sub     rsp, 24
    mov     rdi, rsp
    call    arch_sums
    xor     eax, eax                    ; best archetype
    xor     edx, edx                    ; its sum
    mov     ecx, 1
.l:
    mov     esi, [rsp + rcx*4]
    cmp     esi, edx
    jbe     .next
    mov     edx, esi
    mov     eax, ecx
.next:
    inc     ecx
    cmp     ecx, NUM_ARCHETYPES
    jbe     .l
    add     rsp, 24
    ret

; rpg_archetype_name(edi a) -> rax zstr "Wanderer" (0), "Warrior", "Mage", "Archer", "Rogue",
; "Marksman"; "" for another value (leaf)
rpg_archetype_name:
    lea     rax, [s_empty]
    cmp     edi, NUM_ARCHETYPES
    ja      .ret
    mov     ecx, edi
    lea     rdx, [arch_names]
    mov     rax, [rdx + rcx*8]
.ret:
    ret

; rpg_title() -> rax zstr the title the ranks earn. s1 >= s2 are the two largest archetype sums
; (a1, a2; ties to the lower number): nothing spent is "Wanderer"; s2 > 0 and 2 * s2 >= s1 is the
; title of the pair (Spellblade, Warden, Duelist, Grenadier, Arcane Archer, Nightblade, Spellslinger,
; Skirmisher, Sharpshooter, Gunslinger); else the name of a1.
; ebx = a1, r12d = a2; frame: the six sums
rpg_title:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    sub     rsp, 32
    mov     rdi, rsp
    call    arch_sums
    xor     ebx, ebx                    ; a1
    xor     edx, edx                    ; s1
    mov     ecx, 1
.first:
    mov     esi, [rsp + rcx*4]
    cmp     esi, edx
    jbe     .first_next
    mov     edx, esi
    mov     ebx, ecx
.first_next:
    inc     ecx
    cmp     ecx, NUM_ARCHETYPES
    jbe     .first
    lea     rax, [arch_names]
    mov     rax, [rax]                  ; "Wanderer"
    test    ebx, ebx
    jz      .ret                        ; nothing spent
    xor     r12d, r12d                  ; a2
    xor     r8d, r8d                    ; s2
    mov     ecx, 1
.second:
    cmp     ecx, ebx
    je      .second_next
    mov     esi, [rsp + rcx*4]
    cmp     esi, r8d
    jbe     .second_next
    mov     r8d, esi
    mov     r12d, ecx
.second_next:
    inc     ecx
    cmp     ecx, NUM_ARCHETYPES
    jbe     .second
    lea     rax, [arch_names]
    mov     rax, [rax + rbx*8]          ; the single archetype, unless the second one is close
    test    r8d, r8d
    jz      .ret
    lea     ecx, [r8 + r8]
    cmp     ecx, edx
    jb      .ret                        ; 2 * s2 < s1
    mov     eax, ebx                    ; the pair (lower, higher)
    mov     ecx, r12d
    cmp     eax, ecx
    jbe     .ordered
    xchg    eax, ecx
.ordered:
    dec     eax
    lea     eax, [rax + rax*4]
    lea     eax, [rax + rcx - 1]        ; (lower - 1) * 5 + (higher - 1)
    lea     rdx, [pair_titles]
    mov     rax, [rdx + rax*8]
.ret:
    add     rsp, 32
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- description getters ---------------------------------------------------

; rpg_ability_info(edi ability) -> rax ABILINFO* of ability 0..19; anything else -> an empty record
; (leaf)
rpg_ability_info:
    cmp     edi, NUM_ABILITIES
    jae     .blank
    mov     eax, edi
    shl     eax, 5                      ; ABILINFO_size
    lea     rcx, [abil_tab]
    add     rax, rcx
    ret
.blank:
    lea     rax, [abil_blank]
    ret
%if ABILINFO_size != 32
%error "rpg_ability_info shifts by 5"
%endif

; rpg_ability_tile(edi ability) -> eax atlas tile of the ability's icon: with s = ability mod 4 and
; c = ability / 4, TILE_ABILITY0 + 3c + s for slots 0..2 and TILE_ABILITY3_0 + c for slot 3 of the
; archetypes 1..4 (c = 0..3), TILE_MK_ABIL0 + s for the Marksman's four (c = 4); 0 for another
; ability. Leaf, clobbers ecx.
rpg_ability_tile:
    xor     eax, eax
    cmp     edi, NUM_ABILITIES
    jae     .ret
    mov     ecx, edi
    shr     ecx, 2                      ; c
    mov     eax, edi
    and     eax, 3                      ; s
    cmp     ecx, ARCH_MARKSMAN - 1
    je      .marksman
    cmp     eax, 3
    je      .slot3
    lea     ecx, [rcx + rcx*2]
    lea     eax, [rax + rcx + TILE_ABILITY0]
    ret
.slot3:
    lea     eax, [rcx + TILE_ABILITY3_0]
    ret
.marksman:
    add     eax, TILE_MK_ABIL0          ; its four icons are one run of tiles
.ret:
    ret

; rpg_path_tile(edi archetype) -> eax atlas tile of the emblem on the path node of archetype 1..5:
; TILE_CLASS0 + a - 1 for 1..4, TILE_CLASS_MARKSMAN for 5; 0 for another value. Leaf, clobbers ecx.
rpg_path_tile:
    lea     ecx, [rdi - 1]
    xor     eax, eax
    cmp     ecx, NUM_ARCHETYPES
    jae     .ret                        ; 0 (0 - 1 wraps) and everything above 5
    lea     eax, [rdi + TILE_CLASS0 - 1]
    mov     ecx, TILE_CLASS_MARKSMAN
    cmp     edi, ARCH_MARKSMAN
    cmove   eax, ecx
.ret:
    ret

; rpg_stat_info(edi stat) -> rax STATINFO* of stat 0..45; anything else -> an empty record
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


; rpg_recompute(): rebuilds rpg_stats in this order: the classless base row, +2 health per level
; above the first, the difference between the row of each ranked path node and the classless row,
; the stat nodes (rank * value; the ranked keystone nodes set their rpg_keystones bit), the
; attributes (with the Marksman's path ranked, each Dexterity point is also +1 gun damage), the
; keystones' stat changes, the equipped gear (gear_add_stats), the caps and floors, Bloodrage's -10%
; health, and last the debug menu's flat bonus per stat (debug_stat_bonus: before the caps; max health
; stays at least 2). Then publishes surv_max_health and keeps health, mana and stamina at or below their
; maxima.
rpg_recompute:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     rsi, [base_stats]
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
    lea     r8, [rpg_ext + RPGEXT.web]
    lea     r9, [base_stats]
    lea     r10, [rpg_stats]
    xor     ebx, ebx                    ; archetype - 1
.path:
    movzx   eax, byte [r8 + rbx]        ; the path nodes are web nodes 0..NUM_ARCHETYPES-1
    test    eax, eax
    jz      .path_next
    lea     eax, [rbx + 1]
    imul    eax, eax, NUM_STATS * 4
    lea     rsi, [r9 + rax]             ; the archetype's row ...
    xor     ecx, ecx
.delta:
    mov     eax, [rsi + rcx*4]
    sub     eax, [r9 + rcx*4]           ; ... minus the classless row
    add     [r10 + rcx*4], eax
    inc     ecx
    cmp     ecx, NUM_STATS
    jb      .delta
.path_next:
    inc     ebx
    cmp     ebx, NUM_ARCHETYPES
    jb      .path
    xor     r11d, r11d                  ; keystones taken
    lea     r9, [web_tab + NUM_ARCHETYPES * WEBNODE_size]   ; the first node that is not a path
    mov     ecx, NUM_ARCHETYPES
.node:
    movzx   eax, byte [r8 + rcx]
    test    eax, eax
    jz      .next
    movzx   edx, byte [r9 + WEBNODE.stat]
    cmp     byte [r9 + WEBNODE.kind], NODE_STAT
    je      .stat
    cmp     byte [r9 + WEBNODE.kind], NODE_KEYSTONE
    jne     .next                       ; an ability node adds no stat
    bts     r11d, edx
    jmp     .next
.stat:
    imul    eax, [r9 + WEBNODE.value]
    add     [r10 + rdx*4], eax
.next:
    add     r9, WEBNODE_size
    inc     ecx
    cmp     ecx, NUM_WEB_NODES
    jb      .node
.keystones:
    mov     [rpg_keystones], r11d
    movzx   eax, word [rpg_ext + RPGEXT.attr + ATTR_STR*2]
    add     [rpg_stats + STAT_MELEE_DMG*4], eax
    add     [rpg_stats + STAT_MAX_STAMINA*4], eax
    movzx   r8d, word [rpg_ext + RPGEXT.attr + ATTR_DEX*2]
    add     [rpg_stats + STAT_RANGED_DMG*4], r8d
    cmp     byte [rpg_ext + RPGEXT.web + ARCH_MARKSMAN - 1], 0  ; only the Marksman path turns Dexterity into gun damage
    je      .no_gun_dex
    add     [rpg_stats + STAT_GUN_DMG*4], r8d
.no_gun_dex:
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
    lea     rsi, [debug_stat_bonus]     ; the debug menu's flat bonus, before the caps so every invariant holds
    lea     rdi, [rpg_stats]
    xor     ecx, ecx
.bonus:
    movsx   eax, word [rsi + rcx*2]
    add     [rdi + rcx*4], eax
    inc     ecx
    cmp     ecx, NUM_STATS
    jb      .bonus
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
    mov     ecx, 2
    cmp     eax, ecx
    cmovl   eax, ecx
    mov     [rpg_stats + STAT_MAX_HEALTH*4], eax
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

; ext_reset(): no ranks, no attribute points, no bar, no kits given, the current version. Leaf.
ext_reset:
    lea     rdi, [rpg_ext]
    mov     ecx, RPGEXT_size
    xor     eax, eax
    rep     stosb
    mov     byte [rpg_ext + RPGEXT.version], RPGX_VERSION
    ret

; rpg_reset(): a new character: level 1, nothing else (no debug bonus either), stats recomputed
rpg_reset:
    push    rbp
    mov     rbp, rsp
    lea     rdi, [rpg_state]
    mov     ecx, RPGSAVE_size
    xor     eax, eax
    rep     stosb
    lea     rdi, [debug_stat_bonus]
    mov     ecx, NUM_STATS * 2
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

; rpg_begin(): a character enters the world (app enter_world). The common starting kit is given once
; (KIT_COMMON_BIT of RPGEXT.kits). While no skill point is spent a banner points at the grimoire,
; "Open your grimoire (<key>) to choose a path"; a world rpg_load just refunded keeps its refund
; banner instead (rpg_migrated is cleared here).
; frame: [rsp] the banner text (80)
rpg_begin:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 88
    test    byte [rpg_ext + RPGEXT.kits], KIT_COMMON_BIT
    jnz     .kit_done
    or      byte [rpg_ext + RPGEXT.kits], KIT_COMMON_BIT
    lea     rdi, [kit_common]
    call    give_kit
.kit_done:
    cmp     byte [rpg_migrated], 0
    jne     .migrated
    call    web_ranks_total
    test    eax, eax
    jnz     .ret
    mov     rdi, rsp
    lea     rsi, [s_begin_a]
    call    str_append
    mov     edi, [settings + SETTINGS.keys + 4*BIND_SKILLS]
    mov     rsi, rax
    call    key_name
    mov     rdi, rax
    lea     rsi, [s_begin_b]
    call    str_append
    mov     byte [rax], 0
    mov     rdi, rsp
    mov     esi, RGBA(255, 215, 60, 255)
    call    hud_banner
    jmp     .ret
.migrated:
    mov     byte [rpg_migrated], 0
.ret:
    add     rsp, 88
    pop     rbx
    pop     rbp
    ret

; rpg_add_xp(edi amount): the amount, raised by XP_BONUS percent (integer), goes into the current
; level; every full bar is a level (up to 50, where the XP stays 0). Does nothing at level 50.
; Gaining one or more levels refills health, mana and stamina, plays the level-up sound and shows
; one banner and one burst for the final level.
rpg_add_xp:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
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
    call    level_up_fx
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; level_up_fx(): the character has just gained one or more levels: the stats are recomputed (that
; publishes surv_max_health), health, mana and stamina are full, the level-up sound plays, and one
; "Level N!" banner and one burst at the chest announce the final level
level_up_fx:
    push    rbp
    mov     rbp, rsp
    call    rpg_recompute
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
    pop     rbp
    jmp     fx_burst

; ---- skill and attribute points ---------------------------------------------------

; rpg_can_spend(edi node) -> eax 0 when a point can go into web node 0..109, else why not (checked in
; this order): 2 no such node or already at its maximum rank, 3 the character's level is below the
; node's, 4 the node is not reachable (rpg_reachable), 1 no skill points left
; ebx = node, r12 = WEBNODE*
rpg_can_spend:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     eax, 2
    cmp     ebx, NUM_WEB_NODES
    jae     .ret
    mov     edi, ebx
    call    rpg_web_node
    mov     r12, rax
    lea     rdx, [rpg_ext + RPGEXT.web]
    movzx   edx, byte [rdx + rbx]
    mov     eax, 2
    cmp     dl, [r12 + WEBNODE.max]
    jae     .ret
    mov     eax, 3
    movzx   ecx, byte [r12 + WEBNODE.level]
    cmp     byte [rpg_state + RPGSAVE.level], cl
    jb      .ret
    mov     edi, ebx
    call    rpg_reachable
    test    eax, eax
    mov     eax, 4
    jz      .ret
    call    rpg_points
    mov     ecx, eax
    mov     eax, 1
    test    ecx, ecx
    jz      .ret
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; rpg_spend(edi node) -> eax 1 when a point was spent (rank + 1, stats recomputed, click), else 0.
; A node that goes from rank 0 to 1 also: puts the ability it teaches (an ability node's, or the
; slot-0 ability of a path) into the first empty bar slot; for a path whose archetype kit was not
; given yet, gives that kit (the Warrior also wears the iron chestplate when the chest slot is
; free); and refills mana and stamina.
; ebx = node, r12 = WEBNODE*, r13d = the ability it teaches or -1; frame: [rsp] archetype - 1
rpg_spend:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    call    rpg_can_spend
    test    eax, eax
    jnz     .no
    lea     rdx, [rpg_ext + RPGEXT.web]
    inc     byte [rdx + rbx]
    cmp     byte [rdx + rbx], 1
    jne     .again                      ; a further rank: only the stats change
    mov     edi, ebx
    call    rpg_web_node
    mov     r12, rax
    mov     r13d, -1
    movzx   eax, byte [r12 + WEBNODE.kind]
    cmp     eax, NODE_ABILITY
    jne     .not_ability
    movzx   r13d, byte [r12 + WEBNODE.stat]
    jmp     .taught
.not_ability:
    cmp     eax, NODE_PATH
    jne     .taught
    movzx   ecx, byte [r12 + WEBNODE.stat]
    dec     ecx                         ; archetype - 1
    lea     r13d, [rcx*4]               ; the ability of its slot 0
    movzx   eax, byte [rpg_ext + RPGEXT.kits]
    bt      eax, ecx
    jc      .taught                     ; its kit was given before
    bts     eax, ecx
    mov     [rpg_ext + RPGEXT.kits], al
    mov     [rsp], ecx
    lea     rax, [kit_tab]
    mov     rdi, [rax + rcx*8]
    call    give_kit
    cmp     dword [rsp], ARCH_WARRIOR - 1
    jne     .taught
    lea     rax, [inv + INVENTORY.armor + 4]    ; the chest slot, worn when it is free
    cmp     byte [rax + 1], 0
    jne     .bag
    mov     dword [rax], IRON_CHESTPLATE | (1 << 8)
    jmp     .taught
.bag:
    mov     edi, IRON_CHESTPLATE
    mov     esi, 1
    call    rpg_give_item
.taught:
    test    r13d, r13d
    js      .first
    mov     edi, r13d
    call    bar_put_first_empty
.first:
    call    rpg_recompute
    call    combat_refill
    jmp     .click
.again:
    call    rpg_recompute
.click:
    mov     edi, SND_CLICK
    movss   xmm0, [f_vol_click]
    call    audio_play
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
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

; rpg_respec_cost() -> eax coins a respec costs: 10 per level
rpg_respec_cost:
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    imul    eax, eax, 10
    ret

; web_clear(): no web ranks and an empty ability bar (leaf)
web_clear:
    lea     rdi, [rpg_ext + RPGEXT.web]
    mov     ecx, WEB_MAX
    xor     eax, eax
    rep     stosb
    mov     dword [rpg_ext + RPGEXT.bar], 0
    ret

; rpg_respec_free(): every web rank, attribute point and bar slot is handed back, for no coins (the
; starting kits stay given; the debug menu's bonus points stay too); stats recomputed, banner
rpg_respec_free:
    push    rbp
    mov     rbp, rsp
    call    web_clear
    mov     qword [rpg_ext + RPGEXT.attr], 0
    call    rpg_recompute
    lea     rdi, [s_respec]
    mov     esi, RGBA(255, 215, 60, 255)
    call    hud_banner
    pop     rbp
    ret

; rpg_respec() -> eax 1 when the character paid rpg_respec_cost() coins out of the inventory and
; every web rank, attribute point and bar slot was handed back (the starting kits stay given;
; stats recomputed, coin sound, banner); 0, with nothing changed, without enough coins
rpg_respec:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
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
    mov     edi, SND_COIN
    movss   xmm0, [f_vol_coin]
    call    audio_play
    call    rpg_respec_free
    mov     eax, 1
    jmp     .ret
.poor:
    xor     eax, eax
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; fix_points(): after the level or the bonus points changed: a web that web_valid refuses is handed back
; with the bar, and attribute points above 3 per level above the first (plus the bonus points) are all
; handed back (leaf: clobbers the caller-saved registers)
fix_points:
    sub     rsp, 8
    call    web_valid
    test    eax, eax
    jnz     .web_ok
    call    web_clear
.web_ok:
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    dec     eax
    imul    eax, eax, ATTR_PER_LEVEL
    movzx   ecx, word [rpg_ext + RPGEXT.bonus_ap]
    add     eax, ecx
    movzx   edx, word [rpg_ext + RPGEXT.attr + 0]
    movzx   ecx, word [rpg_ext + RPGEXT.attr + 2]
    add     edx, ecx
    movzx   ecx, word [rpg_ext + RPGEXT.attr + 4]
    add     edx, ecx
    movzx   ecx, word [rpg_ext + RPGEXT.attr + 6]
    add     edx, ecx
    cmp     edx, eax
    jbe     .attr_ok
    mov     qword [rpg_ext + RPGEXT.attr], 0
.attr_ok:
    add     rsp, 8
    ret

; rpg_set_level(edi level) -> eax the new level: the debug menu's setter. The level is clamped to
; 1..MAX_LEVEL and the XP bar empties. A higher level pays out like a level-up (level_up_fx: health,
; mana and stamina full, sound, banner, burst); a lower one hands back what it cannot hold (fix_points).
; The stats are recomputed either way.
; ebx = the new level; frame: [rsp] the old level
rpg_set_level:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     ebx, edi
    mov     eax, 1
    cmp     ebx, eax
    cmovl   ebx, eax
    mov     eax, MAX_LEVEL
    cmp     ebx, eax
    cmovg   ebx, eax
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    mov     [rsp], eax
    mov     [rpg_state + RPGSAVE.level], bl
    mov     dword [rpg_state + RPGSAVE.xp], 0
    call    fix_points
    cmp     ebx, [rsp]
    jbe     .plain
    call    level_up_fx
    jmp     .done
.plain:
    call    rpg_recompute
.done:
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; rpg_add_bonus_points(edi skill, esi attr): the debug menu's points on top of the level's: the signed
; amounts are added to the skill and attribute bonus (each kept within 0..9999); a bonus that shrinks
; under what is already spent hands the spent points back (fix_points). Stats recomputed.
rpg_add_bonus_points:
    push    rbp
    mov     rbp, rsp
    movzx   eax, word [rpg_ext + RPGEXT.bonus_sp]
    add     eax, edi
    xor     edx, edx
    test    eax, eax
    cmovs   eax, edx
    mov     ecx, 9999
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [rpg_ext + RPGEXT.bonus_sp], ax
    movzx   eax, word [rpg_ext + RPGEXT.bonus_ap]
    add     eax, esi
    test    eax, eax
    cmovs   eax, edx
    cmp     eax, ecx
    cmova   eax, ecx
    mov     [rpg_ext + RPGEXT.bonus_ap], ax
    call    fix_points
    call    rpg_recompute
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

; rpg_save(rdi header): rpg_state -> WORLDHDR.rpg, rpg_ext -> WORLDHDR.rpgx, debug_stat_bonus ->
; WORLDHDR.debug_stats
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
    lea     rsi, [debug_stat_bonus]
    lea     rdi, [rdx + WORLDHDR.debug_stats]
    mov     ecx, NUM_STATS * 2
    rep     movsb
    ret

; web_valid() -> eax 1 when the ranks of RPGEXT.web are a state the rules can reach, else 0: no rank
; above the maximum of its node (nothing in the slots past the last node), the ranks add up to at most
; the level plus the debug menu's skill points (RPGEXT.bonus_sp), no ranked node asks for a level above
; the character's, and every ranked node is joined
; to a ranked path node through ranked nodes (web_scratch grows from the ranked paths along the
; edges). Leaf: clobbers every caller-saved register.
web_valid:
    lea     r8, [rpg_ext + RPGEXT.web]
    lea     rsi, [web_tab]
    movzx   r9d, byte [rpg_state + RPGSAVE.level]
    xor     ecx, ecx                    ; node
    xor     edx, edx                    ; sum of the ranks
.check:
    movzx   eax, byte [r8 + rcx]
    test    eax, eax
    jz      .check_next
    cmp     al, [rsi + WEBNODE.max]
    ja      .bad
    cmp     r9b, [rsi + WEBNODE.level]
    jb      .bad
    add     edx, eax
.check_next:
    add     rsi, WEBNODE_size
    inc     ecx
    cmp     ecx, NUM_WEB_NODES
    jb      .check
.beyond:
    cmp     byte [r8 + rcx], 0          ; the slots past the last node hold nothing
    jne     .bad
    inc     ecx
    cmp     ecx, WEB_MAX
    jb      .beyond
    movzx   eax, word [rpg_ext + RPGEXT.bonus_sp]
    add     eax, r9d
    cmp     edx, eax
    ja      .bad                        ; more ranks than levels (and debug menu points)
    lea     rdi, [web_scratch]
    xor     eax, eax
    mov     ecx, WEB_MAX / 8
    rep     stosq
    lea     rdi, [web_scratch]
    xor     ecx, ecx
.paths:
    cmp     byte [r8 + rcx], 0
    setne   al
    mov     [rdi + rcx], al             ; the ranked paths are joined to themselves
    inc     ecx
    cmp     ecx, NUM_ARCHETYPES
    jb      .paths
.grow:
    lea     rsi, [web_edges]
    mov     r9d, [web_edge_count]
    xor     r10d, r10d                  ; set when a node joined in this pass
.edge:
    movzx   eax, word [rsi]
    movzx   edx, word [rsi + 2]
    mov     cl, [rdi + rax]
    cmp     cl, [rdi + rdx]
    je      .edge_next
    test    cl, cl
    jnz     .join                       ; a is joined, b is not: b may join
    xchg    eax, edx                    ; b is joined, a is not: a may join
.join:
    cmp     byte [r8 + rdx], 0
    je      .edge_next                  ; an unranked node carries the way no further
    mov     byte [rdi + rdx], 1
    mov     r10d, 1
.edge_next:
    add     rsi, 4
    dec     r9d
    jnz     .edge
    test    r10d, r10d
    jnz     .grow
    xor     ecx, ecx
.every:
    cmp     byte [r8 + rcx], 0
    je      .every_next
    cmp     byte [rdi + rcx], 0
    je      .bad                        ; ranked, but not joined to a ranked path
.every_next:
    inc     ecx
    cmp     ecx, NUM_WEB_NODES
    jb      .every
    mov     eax, 1
    ret
.bad:
    xor     eax, eax
    ret

%define LEGACY_CLASSES 4                ; the classes of a 0.10.1 save (RPGSAVE.legacy_class 1..4); not the paths of the web

; refund_banner(rdi text): the web was handed back by rpg_load: say so with the zstr, and keep
; rpg_begin from replacing the banner
refund_banner:
    sub     rsp, 8
    mov     byte [rpg_migrated], 1
    mov     esi, RGBA(255, 215, 60, 255)
    call    hud_banner
    add     rsp, 8
    ret

; rpg_load(rdi header): WORLDHDR.rpg -> rpg_state and WORLDHDR.rpgx -> rpg_ext, made consistent,
; then the stats. A level outside 1..50 rebuilds the character from scratch. A record of version 0
; or 1 (a save from before the grimoire, with classes) is migrated: its web and bar are zeroed (so
; every skill point is refunded; version 0 also loses its attribute points), the kits it counts as
; given are the common one and the one of its old class (RPGSAVE.legacy_class, 1..LEGACY_CLASSES),
; so no kit is given twice, and a banner says the points were refunded. A version 2 record (0.10.2
; and 0.10.3: four paths, every node id has moved since) keeps its kits and attribute points but its
; web and bar are zeroed too, with a banner of their own. A version 3 record whose web the rules
; cannot reach (web_valid) is refunded like a version 1 one. A bar slot holding an ability that is
; not learned is emptied. Attribute points adding up to more than 3 per level above the first (plus the
; debug menu's RPGEXT.bonus_ap) are dropped; the debug menu's stat bonuses (WORLDHDR.debug_stats) go to
; debug_stat_bonus, each cut to +-DEBUG_BONUS_MAX; xp is kept below the bar; quest and quest_state are
; masked to their ranges. The old
; cleared and flags bytes of the record are not read any more (0.9: the dungeons and the crypt keep
; their state in WORLDHDR.sites).
; ebx = level, r12 = the bar, r13d = the slot being checked
rpg_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
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
    xor     ecx, ecx                    ; the debug menu's stat bonuses, each kept within +-DEBUG_BONUS_MAX
    lea     rsi, [debug_stat_bonus]
.dbonus:
    movsx   eax, word [rdx + WORLDHDR.debug_stats + rcx*2]
    mov     edi, DEBUG_BONUS_MAX
    cmp     eax, edi
    cmovg   eax, edi
    neg     edi
    cmp     eax, edi
    cmovl   eax, edi
    mov     [rsi + rcx*2], ax
    inc     ecx
    cmp     ecx, NUM_STATS
    jb      .dbonus
    movzx   ebx, byte [rpg_state + RPGSAVE.level]
    lea     eax, [rbx - 1]
    cmp     eax, MAX_LEVEL
    jae     .reset
    cmp     byte [rpg_ext + RPGEXT.version], RPGX_VERSION
    jae     .current
    cmp     byte [rpg_ext + RPGEXT.version], 2
    je      .fifth_path
    movzx   ecx, byte [rpg_state + RPGSAVE.legacy_class]
    dec     ecx
    mov     edx, KIT_COMMON_BIT
    cmp     ecx, LEGACY_CLASSES
    jae     .kits                       ; no class: only the common kit counts as given
    bts     edx, ecx
.kits:
    mov     [rpg_ext + RPGEXT.kits], dl
    cmp     byte [rpg_ext + RPGEXT.version], 0
    jne     .legacy
    mov     qword [rpg_ext + RPGEXT.attr], 0    ; version 0: the attribute points go too
.legacy:
    lea     rdi, [rpg_ext + RPGEXT.legacy]
    mov     ecx, 32
    xor     eax, eax
    rep     stosb
    mov     byte [rpg_state + RPGSAVE.legacy_class], 0
    call    web_clear
    lea     rdi, [s_migrated]
    call    refund_banner
    jmp     .bars
.fifth_path:                            ; version 2: the node ids moved; kits and attribute points stay
    mov     byte [rpg_state + RPGSAVE.legacy_class], 0
    call    web_clear
    lea     rdi, [s_migrated_mk]
    call    refund_banner
    jmp     .bars
.current:
    mov     byte [rpg_state + RPGSAVE.legacy_class], 0
    call    web_valid
    test    eax, eax
    jnz     .bars
    call    web_clear
    lea     rdi, [s_migrated]
    call    refund_banner
.bars:
    lea     r12, [rpg_ext + RPGEXT.bar]
    xor     r13d, r13d
.bar:
    movzx   edi, byte [r12 + r13]
    test    edi, edi
    jz      .bar_next
    dec     edi
    call    rpg_ability_learned
    test    eax, eax
    jnz     .bar_next
    mov     byte [r12 + r13], 0         ; an ability the web does not teach
.bar_next:
    inc     r13d
    cmp     r13d, NUM_ABILITY_SLOTS
    jb      .bar
    lea     eax, [rbx - 1]
    imul    eax, eax, ATTR_PER_LEVEL    ; attribute points the level has paid
    movzx   ecx, word [rpg_ext + RPGEXT.bonus_ap]
    add     eax, ecx
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
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
