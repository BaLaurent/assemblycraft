; test_rpg.asm - character progression: levels and XP, the shared skill web, attributes and respec,
; archetype titles, derived stats, save/load validation, the quest chain and trades.
%include "common.inc"
default rel

global test_rpg_levels_and_points, test_rpg_skill_spend_rules, test_rpg_stats_from_paths_and_ranks
global test_rpg_save_load_validates, test_quest_chain_progress_and_rewards
global test_trade_exchanges_items
global test_rpg_attributes_and_respec, test_rpg_keystones_and_caps
global test_archetype_titles

extern world_clear, world_header, str_eq, fx_clear
extern inv, inv_clear, inv_add, inv_count
extern drops, drops_clear
extern surv, survival_reset, surv_max_health
extern combat_reset, combat_mana, combat_stamina
extern banner_text
extern rpg_state, rpg_ext, rpg_stats, rpg_keystones, rpg_reset, rpg_migrated, rpg_begin
extern rpg_level, rpg_points, rpg_xp_need, rpg_add_xp, rpg_can_spend, rpg_spend, rpg_rank
extern rpg_stat, rpg_recompute, rpg_clamp_stats, rpg_ability_tile
extern rpg_web_node, rpg_web_linked, web_edges, web_edge_count
extern rpg_ability_learned, rpg_ability_info, rpg_bar_ability
extern rpg_archetype, rpg_archetype_ranks, rpg_archetype_name, rpg_title
extern rpg_stat_info, rpg_format_stat
extern rpg_attr, rpg_attr_points, rpg_spend_attr, rpg_attr_info, rpg_attr_desc
extern rpg_respec_cost, rpg_respec, rpg_keystone
extern rpg_on_mob_killed, rpg_on_block_mined, rpg_on_death, rpg_load, rpg_save
extern quests_current, quests_progress, quests_accept, quests_can_complete, quests_complete
extern quests_on_kill, quests_on_dungeon_cleared, quests_on_boss_killed
extern trade_offer, trade_can, trade_execute, trade_open, trade_count

%define R_LEVEL   rpg_state + RPGSAVE.level
%define R_QUEST   rpg_state + RPGSAVE.quest
%define R_QSTATE  rpg_state + RPGSAVE.quest_state
%define R_QPROG   rpg_state + RPGSAVE.quest_progress
%define R_XP      rpg_state + RPGSAVE.xp
%define R_WEB     rpg_ext + RPGEXT.web
%define R_BAR     rpg_ext + RPGEXT.bar
%define R_KITS    rpg_ext + RPGEXT.kits
%define R_LEGACY  rpg_ext + RPGEXT.legacy
%define R_ATTR    rpg_ext + RPGEXT.attr
%define HDR       world_header + WORLDHDR.rpg
%define HDRX      world_header + WORLDHDR.rpgx
%define HWEB      HDRX + RPGEXT.web
%define KS_NONE   0xFF
%define NOLO      -2147483648           ; no lowest / highest limit
%define NOHI      2147483647
%define NUM_EDGES 104

; the node id of node n (= branch * 6 + tier, 0..17) of archetype a (1..4)
%define WEBN(a, n) (4 + ((a) - 1) * 18 + (n))

section .rodata.str progbits alloc noexec nowrite align=1
; a stat record: label, the text of the value 7, format, icon tile
%macro EXPS 4                           ; label, format, icon, text
section .rodata.str
%%l: db %1, 0
%%t: db %4, 0
section .rodata
    dq %%l, %%t
    db %2, %3, 0, 0, 0, 0, 0, 0
%endmacro

; a row of the plan's web, checked field by field through rpg_web_node: 24 bytes, the name, the node
; id, the value per rank, then kind, stat (stat id / ability id / keystone id / archetype), max
; rank, owner, cell x, cell y, level
%macro EXPW 10                          ; name, node, kind, stat, max, arch, value, x, y, level
section .rodata.str
%%n: db %1, 0
section .rodata
    dq %%n
    dd %2, %7
    db %3, %4, %5, %6, %8, %9, %10, 0
%endmacro

section .rodata
align 8
exp_web:
    EXPW "Path of the Warrior", 0,  NODE_PATH,     ARCH_WARRIOR,    1, ARCH_WARRIOR, 0,  0, -2, 1
    EXPW "Path of the Rogue",   3,  NODE_PATH,     ARCH_ROGUE,      1, ARCH_ROGUE,   0, -2,  0, 1
    EXPW "Weapon Mastery",      4,  NODE_STAT,     STAT_MELEE_DMG,  5, ARCH_WARRIOR, 6, -1, -3, 1
    EXPW "Blink",               29, NODE_ABILITY,  5,               1, ARCH_MAGE,    0,  4,  0, 4
    EXPW "Hunter's Mark",       55, NODE_ABILITY,  11,              1, ARCH_ARCHER,  0, -4,  6, 15
    EXPW "Assassinate",         63, NODE_KEYSTONE, KS_ASSASSINATE,  1, ARCH_ROGUE,   0, -8,  6, 30
    EXPW "Runed Steel",         76, NODE_STAT,     STAT_ADD_FIRE,   3, 0,            1,  3, -3, 4
    EXPW "Duelist",             87, NODE_STAT,     STAT_WEAPON_DMG, 3, 0,            5, -7, -7, 30
exp_web_end:

; the level a node of tier 0..5 asks for
tier_level: db 1, 4, 9, 15, 22, 30

; the stats of a path alone at level 1 (the former class rows), NUM_STATS dwords per archetype
align 4
exp_paths:
    dd 24, 10,  0,  0,  5, 0,   0, 0, 120, 0, 0, 0,   0, 0, 0, 0,  0, 0   ; Warrior
    times NUM_STATS - 18 dd 0
    dd 18,  0,  0, 10,  5, 0, 100, 4,  80, 0, 0, 0,   0, 0, 0, 0,  0, 0   ; Mage
    times NUM_STATS - 18 dd 0
    dd 20,  0, 15,  0,  8, 0,   0, 0, 100, 0, 0, 5,   0, 0, 0, 0, 10, 0   ; Archer
    times NUM_STATS - 18 dd 0
    dd 20,  0,  0,  0, 10, 0,   0, 0, 110, 10, 0, 5, 100, 0, 0, 0,  0, 0  ; Rogue
    times NUM_STATS - 18 dd 0

; the twelve bridges: node, stat, value per rank, level
exp_bridges:
    dd 76, STAT_ADD_FIRE,     1,  4    ; Runed Steel      (Warrior - Mage)
    dd 77, STAT_MAX_MANA,    10, 15    ; Warded Plate
    dd 78, STAT_ALL_DMG,      4, 30    ; Spellblade
    dd 79, STAT_ADD_SHOCK,    1,  4    ; Charged Tips     (Mage - Archer)
    dd 80, STAT_AREA,         6, 15    ; Far Sight
    dd 81, STAT_ALL_DMG,      4, 30    ; Starshot
    dd 82, STAT_BLEED_CHANCE, 6,  4    ; Barbed Shafts    (Archer - Rogue)
    dd 83, STAT_MOVE_SPEED,   3, 15    ; Light Step
    dd 84, STAT_ATTACK_SPEED, 4, 30    ; Skirmisher
    dd 85, STAT_CRIT_CHANCE,  2,  4    ; Riposte Edge     (Rogue - Warrior)
    dd 86, STAT_THORNS,       2, 15    ; Scarred Hide
    dd 87, STAT_WEAPON_DMG,   5, 30    ; Duelist
exp_bridges_end:

; the six pair titles: lower archetype, higher archetype, title
align 8
exp_pairs:
    dd 1, 2
    dq s_spellblade
    dd 2, 3
    dq s_arcane
    dd 3, 4
    dq s_skirmisher
    dd 1, 4
    dq s_duelist
    dd 1, 3
    dq s_warden
    dd 2, 4
    dq s_nightblade
exp_pairs_end:

section .rodata
align 8
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
    EXPS "Gun damage", FMT_PCT, TILE_STAT_GUN, "+7% gun damage"
    EXPS "Reload speed", FMT_PCT, TILE_STAT_RELOAD, "+7% reload speed"
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

align 4
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

kill_xp_tab:                            ; plain XP of a kill by mob type 1..8
    db 10, 2, 15, 12, 10, 2, 0, 12
t_trades:                              ; give, give_n, get, get_n
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
s_wanderer: db "Wanderer", 0
s_spellblade: db "Spellblade", 0
s_arcane:   db "Arcane Archer", 0
s_skirmisher: db "Skirmisher", 0
s_duelist:  db "Duelist", 0
s_warden:   db "Warden", 0
s_nightblade: db "Nightblade", 0
s_migrated: db "Classes became one grimoire: skill points refunded", 0
s_begin_a:  db "Open your grimoire (", 0
s_begin_b:  db ") to choose a path", 0
s_deepmind: db "Deep Mind", 0
s_blink:    db "Blink", 0

section .bss
alignb 4
fmt_buf:    resb 48

section .text

section .bss
alignb 4
web_seen:   resb WEB_MAX

section .text

; take the path of archetype %1 (0 = none) at level %2 on a fresh character, fail unless it worked
%macro USE_PATH 2
    mov     edi, %1
    mov     esi, %2
    call    use_path
    test    eax, eax
    jnz     .fail
%endmacro
; a zero web / bar / byte range
%macro EXPECT_ZERO_WEB 0
    lea     rdi, [R_WEB]
    mov     esi, WEB_MAX
    call    bytes_sum
    test    eax, eax
    jnz     .fail
%endmacro
; fail unless the banner is the zstr %1
%macro BANNER_IS 1
    lea     rdi, [banner_text]
    lea     rsi, [%1]
    call    str_eq
    test    eax, eax
    jz      .fail
%endmacro
; the header's web rank of node %1 = %2
%macro HW 2
    mov     byte [HWEB + %1], %2
%endmacro
; a version 2 header of level %1, nothing else
%macro HDR_NEW 1
    xor     edi, edi
    mov     esi, %1
    call    hdr_set
%endmacro
; load the header and fail unless the whole web and the bar are gone and the refund banner is up
%macro LOAD_REFUNDS 0
    mov     byte [banner_text], 0
    call    hdr_load
    EXPECT_ZERO_WEB
    EXPECT_D R_BAR, 0
    BANNER_IS s_migrated
%endmacro
; load the header and fail unless it is accepted as it is: node %1 keeps rank %2, no banner
%macro LOAD_KEEPS 2
    mov     byte [banner_text], 0
    call    hdr_load
    EXPECT_B R_WEB + %1, %2
    EXPECT_B banner_text, 0
%endmacro

; use_path(edi archetype, esi level) -> eax 0 when it worked: a fresh character (reset_all) of that
; level with every starting kit already counted as given (so nothing is added to the inventory),
; whose point went into the path node of the archetype (0: no path, nothing spent)
use_path:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    call    reset_all
    mov     [R_LEVEL], r12b
    mov     byte [R_KITS], 0xFF
    call    rpg_recompute
    test    ebx, ebx
    jz      .ok
    lea     edi, [rbx - 1]
    call    rpg_spend
    cmp     eax, 1
    jne     .bad
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

; bytes_sum(rdi bytes, esi n) -> eax the sum of the n bytes
bytes_sum:
    xor     eax, eax
.l:
    test    esi, esi
    jz      .done
    movzx   ecx, byte [rdi]
    add     eax, ecx
    inc     rdi
    dec     esi
    jmp     .l
.done:
    ret

; banner_begin_ok() -> eax 0 when the banner reads "Open your grimoire (<a key name>) to choose a
; path"
banner_begin_ok:
    lea     rdi, [banner_text]
    lea     rsi, [s_begin_a]
.pre:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .pre_done
    cmp     al, [rdi]
    jne     .bad
    inc     rdi
    inc     rsi
    jmp     .pre
.pre_done:
    mov     r8, rdi                         ; the key name starts here
.scan:
    cmp     byte [rdi], 0
    je      .end
    inc     rdi
    jmp     .scan
.end:
    lea     rdi, [rdi - 18]                 ; the 18 characters of ") to choose a path"
    cmp     rdi, r8
    jbe     .bad                            ; no key name in between
    lea     rsi, [s_begin_b]
.suf:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .ok
    cmp     al, [rdi]
    jne     .bad
    inc     rdi
    inc     rsi
    jmp     .suf
.ok:
    xor     eax, eax
    ret
.bad:
    mov     eax, 1
    ret

; web_row_ok(rdi row of exp_web) -> eax 0 when rpg_web_node of the row's node has exactly the row's
; name, kind, stat, max rank, owner, value, cell and level
web_row_ok:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     rbx, rdi
    mov     edi, [rbx + 8]
    call    rpg_web_node
    test    rax, rax
    jz      .bad
    mov     r12, rax
    mov     rdi, [r12 + WEBNODE.name]
    mov     rsi, [rbx]
    call    str_eq
    test    eax, eax
    jz      .bad
    mov     eax, [rbx + 12]
    cmp     [r12 + WEBNODE.value], eax
    jne     .bad
    movzx   eax, byte [rbx + 16]
    cmp     [r12 + WEBNODE.kind], al
    jne     .bad
    movzx   eax, byte [rbx + 17]
    cmp     [r12 + WEBNODE.stat], al
    jne     .bad
    movzx   eax, byte [rbx + 18]
    cmp     [r12 + WEBNODE.max], al
    jne     .bad
    movzx   eax, byte [rbx + 19]
    cmp     [r12 + WEBNODE.arch], al
    jne     .bad
    movsx   eax, byte [rbx + 20]
    movsx   ecx, byte [r12 + WEBNODE.x]
    cmp     ecx, eax
    jne     .bad
    movsx   eax, byte [rbx + 21]
    movsx   ecx, byte [r12 + WEBNODE.y]
    cmp     ecx, eax
    jne     .bad
    movzx   eax, byte [rbx + 22]
    cmp     [r12 + WEBNODE.level], al
    jne     .bad
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; web_cells_ok() -> eax 0 when all NUM_WEB_NODES nodes exist, lie inside -8..8 on both axes and no
; two share a cell
web_cells_ok:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    xor     ebx, ebx                        ; i
.i:
    mov     edi, ebx
    call    rpg_web_node
    test    rax, rax
    jz      .bad
    movsx   r12d, byte [rax + WEBNODE.x]
    movsx   r13d, byte [rax + WEBNODE.y]
    lea     eax, [r12 + 8]
    cmp     eax, 16
    ja      .bad
    lea     eax, [r13 + 8]
    cmp     eax, 16
    ja      .bad
    lea     r14d, [rbx + 1]                 ; j
.j:
    cmp     r14d, NUM_WEB_NODES
    jae     .next_i
    mov     edi, r14d
    call    rpg_web_node
    movsx   ecx, byte [rax + WEBNODE.x]
    movsx   edx, byte [rax + WEBNODE.y]
    cmp     ecx, r12d
    jne     .next_j
    cmp     edx, r13d
    je      .bad
.next_j:
    inc     r14d
    jmp     .j
.next_i:
    inc     ebx
    cmp     ebx, NUM_WEB_NODES
    jb      .i
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; web_edges_ok() -> eax 0 when the web has NUM_EDGES edges, each joining two distinct valid nodes,
; none listed twice (either way round), and rpg_web_linked agrees with each of them both ways
web_edges_ok:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    cmp     dword [web_edge_count], NUM_EDGES
    jne     .bad
    lea     r15, [web_edges]
    xor     ebx, ebx                        ; k
.k:
    movzx   r12d, word [r15 + rbx*4]
    movzx   r13d, word [r15 + rbx*4 + 2]
    cmp     r12d, NUM_WEB_NODES
    jae     .bad
    cmp     r13d, NUM_WEB_NODES
    jae     .bad
    cmp     r12d, r13d
    je      .bad
    mov     edi, r12d
    mov     esi, r13d
    call    rpg_web_linked
    cmp     eax, 1
    jne     .bad
    mov     edi, r13d
    mov     esi, r12d
    call    rpg_web_linked
    cmp     eax, 1
    jne     .bad
    lea     r14d, [rbx + 1]                 ; the later edges
.dup:
    cmp     r14d, NUM_EDGES
    jae     .next_k
    movzx   eax, word [r15 + r14*4]
    movzx   ecx, word [r15 + r14*4 + 2]
    cmp     eax, r12d
    jne     .rev
    cmp     ecx, r13d
    je      .bad
.rev:
    cmp     eax, r13d
    jne     .next_d
    cmp     ecx, r12d
    je      .bad
.next_d:
    inc     r14d
    jmp     .dup
.next_k:
    inc     ebx
    cmp     ebx, NUM_EDGES
    jb      .k
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; web_connected_ok() -> eax 0 when every node is reached from the four paths along web_edges: a
; breadth-first fill, repeated over the edge list until nothing more joins (leaf)
web_connected_ok:
    lea     rdi, [web_seen]
    xor     eax, eax
    mov     ecx, WEB_MAX / 8
.clear:
    mov     [rdi + rcx*8 - 8], rax
    dec     ecx
    jnz     .clear
    mov     dword [web_seen], 0x01010101    ; the paths are the starting points
.pass:
    xor     r10d, r10d                      ; something joined in this pass
    lea     rsi, [web_edges]
    mov     r9d, NUM_EDGES
.edge:
    movzx   eax, word [rsi]
    movzx   edx, word [rsi + 2]
    mov     cl, [rdi + rax]
    cmp     cl, [rdi + rdx]
    je      .next
    mov     byte [rdi + rax], 1
    mov     byte [rdi + rdx], 1
    mov     r10d, 1
.next:
    add     rsi, 4
    dec     r9d
    jnz     .edge
    test    r10d, r10d
    jnz     .pass
    xor     ecx, ecx
.all:
    cmp     byte [rdi + rcx], 0
    je      .bad
    inc     ecx
    cmp     ecx, NUM_WEB_NODES
    jb      .all
    xor     eax, eax
    ret
.bad:
    mov     eax, 1
    ret

; web_nodes_ok() -> eax 0 when every node of the web is what its id says: the name, the owner (path
; a - 1 and the 18 nodes after it belong to archetype a; the bridges to none), the kind (a path, then
; per 18: stat nodes, abilities at 7 / 9 / 15, keystones at 5 / 11 / 17; the bridges are stat nodes),
; the max rank (1 for paths, abilities and keystones, 5 for the other former nodes, 3 for a
; bridge), the level of its tier (paths 1, bridges 4 / 15 / 30), the text (none for a stat node), and
; the ids a path (archetype), an ability ((a - 1) * 4 + slot) and a keystone ((a - 1) * 3 + branch)
; carry
; ebx = node id, r12 = WEBNODE*, r13d = a - 1, r14d = n or k
web_nodes_ok:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    xor     ebx, ebx
.n:
    mov     edi, ebx
    call    rpg_web_node
    test    rax, rax
    jz      .bad
    mov     r12, rax
    mov     rcx, [r12 + WEBNODE.name]
    test    rcx, rcx
    jz      .bad
    cmp     byte [rcx], 0
    je      .bad
    cmp     ebx, NUM_ARCHETYPES
    jb      .path
    cmp     ebx, 4 + NUM_ARCHETYPES * 18
    jae     .bridge
    lea     eax, [rbx - 4]
    xor     edx, edx
    mov     ecx, 18
    div     ecx
    mov     r13d, eax                       ; a - 1
    mov     r14d, edx                       ; n
    lea     eax, [r13 + 1]
    cmp     [r12 + WEBNODE.arch], al
    jne     .bad
    mov     eax, r14d
    xor     edx, edx
    mov     ecx, 6
    div     ecx                             ; eax = branch, edx = tier
    lea     rcx, [tier_level]
    movzx   ecx, byte [rcx + rdx]
    cmp     [r12 + WEBNODE.level], cl
    jne     .bad
    cmp     edx, 5
    je      .keystone
    mov     r15d, 1
    cmp     r14d, 7
    je      .ability
    inc     r15d
    cmp     r14d, 9
    je      .ability
    inc     r15d
    cmp     r14d, 15
    je      .ability
    cmp     byte [r12 + WEBNODE.kind], NODE_STAT
    jne     .bad
    cmp     byte [r12 + WEBNODE.max], 5
    jne     .bad
    cmp     qword [r12 + WEBNODE.desc], 0
    jne     .bad
    jmp     .next
.ability:                                   ; r15d = the slot
    cmp     byte [r12 + WEBNODE.kind], NODE_ABILITY
    jne     .bad
    cmp     byte [r12 + WEBNODE.max], 1
    jne     .bad
    lea     eax, [r15 + r13*4]
    cmp     [r12 + WEBNODE.stat], al
    jne     .bad
    jmp     .text
.keystone:                                  ; eax = the branch
    cmp     byte [r12 + WEBNODE.kind], NODE_KEYSTONE
    jne     .bad
    cmp     byte [r12 + WEBNODE.max], 1
    jne     .bad
    lea     ecx, [r13 + r13*2]
    add     eax, ecx
    cmp     [r12 + WEBNODE.stat], al
    jne     .bad
.text:
    mov     rcx, [r12 + WEBNODE.desc]
    test    rcx, rcx
    jz      .bad
    cmp     byte [rcx], 0
    je      .bad
    jmp     .next
.path:
    cmp     byte [r12 + WEBNODE.kind], NODE_PATH
    jne     .bad
    cmp     byte [r12 + WEBNODE.max], 1
    jne     .bad
    cmp     byte [r12 + WEBNODE.level], 1
    jne     .bad
    lea     eax, [rbx + 1]
    cmp     [r12 + WEBNODE.stat], al
    jne     .bad
    cmp     [r12 + WEBNODE.arch], al
    jne     .bad
    jmp     .text
.bridge:
    cmp     byte [r12 + WEBNODE.kind], NODE_STAT
    jne     .bad
    cmp     byte [r12 + WEBNODE.max], 3
    jne     .bad
    cmp     byte [r12 + WEBNODE.arch], 0
    jne     .bad
    lea     eax, [rbx - (4 + NUM_ARCHETYPES * 18)]
    xor     edx, edx
    mov     ecx, 3
    div     ecx                             ; edx = k
    lea     rcx, [tier_level]
    movzx   ecx, byte [rcx + rdx*2 + 1]     ; the levels of tiers 1, 3, 5
    cmp     [r12 + WEBNODE.level], cl
    jne     .bad
.next:
    inc     ebx
    cmp     ebx, NUM_WEB_NODES
    jb      .n
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

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

; cleanup(): reset_all, no refund pending, and nothing left in the header's RPG records
cleanup:
    push    rbp
    mov     rbp, rsp
    call    reset_all
    mov     byte [rpg_migrated], 0
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
    ; XP counts without a path
    mov     edi, 10
    call    rpg_add_xp
    EXPECT_D R_XP, 10
    EXPECT_B R_LEVEL, 1
    CALL0   rpg_points, 1
    mov     dword [R_XP], 0
    ; the bar is 20 + 10 * level + level squared, none at the cap
    CALL1   rpg_xp_need, 0, 0
    CALL1   rpg_xp_need, 1, 31
    CALL1   rpg_xp_need, 2, 44
    CALL1   rpg_xp_need, 29, 1151
    CALL1   rpg_xp_need, 49, 2911
    CALL1   rpg_xp_need, 50, 0
    ; Warrior: the first rank of the path gives the kit and wears the chestplate
    mov     dword [combat_stamina], __float32__(10.0)
    CALL1   rpg_spend, 0, 1
    CALL0   rpg_level, 1
    CALL0   rpg_points, 0
    CALL1   rpg_rank, 0, 1
    HAVE    IRON_SWORD, 1
    HAVE    COOKED_PORKCHOP, 0              ; the common kit comes with rpg_begin
    HAVE    IRON_CHESTPLATE, 0              ; it is worn, not carried
    EXPECT_D inv + INVENTORY.armor + 4, IRON_CHESTPLATE | (1 << 8)
    EXPECT_D surv_max_health, 24
    EXPECT_D combat_stamina, __float32__(120.0) ; resources refilled to the Warrior's maximum
    ; 31 XP is the first level: points follow, health (2 more per level) and stamina are refilled
    mov     dword [surv + SURVIVAL.health], 3
    mov     dword [combat_stamina], __float32__(10.0)
    mov     edi, 31
    call    rpg_add_xp
    CALL0   rpg_level, 2
    EXPECT_D R_XP, 0
    CALL0   rpg_points, 1
    EXPECT_D surv + SURVIVAL.health, 26
    EXPECT_D combat_stamina, __float32__(120.0)
    ; left-over XP carries over: 44 for level 2, 53 given
    mov     edi, 53
    call    rpg_add_xp
    CALL0   rpg_level, 3
    EXPECT_D R_XP, 9
    CALL0   rpg_points, 2
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
    CALL0   rpg_points, 49                  ; 50 levels, the path took one
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
    mov     byte [R_WEB + 3], 2
    mov     byte [R_BAR], 5
    mov     byte [R_KITS], 0x0F
    mov     word [R_ATTR + ATTR_VIT*2], 5
    mov     byte [rpg_ext + RPGEXT.version], 0
    call    rpg_reset
    CALL1   rpg_rank, 3, 0
    EXPECT_D R_BAR, 0
    EXPECT_B R_KITS, 0
    CALL1   rpg_attr, ATTR_VIT, 0
    EXPECT_B rpg_ext + RPGEXT.version, RPGX_VERSION
    CALL0   rpg_level, 1
    ; the other paths' kits, each with its own resources refilled
    call    reset_all
    CALL1   rpg_spend, 1, 1
    CALL1   rpg_bar_ability, 0, 4           ; Fireball in the first bar slot
    HAVE    STAFF, 1
    HAVE    MANA_POTION, 2
    HAVE    COOKED_PORKCHOP, 0
    HAVE    IRON_SWORD, 0
    EXPECT_D surv_max_health, 18
    EXPECT_D combat_mana, __float32__(100.0)
    EXPECT_D combat_stamina, __float32__(80.0)
    call    reset_all
    CALL1   rpg_spend, 2, 1
    CALL1   rpg_bar_ability, 0, 8
    HAVE    BOW, 1
    HAVE    ARROW, 32
    call    reset_all
    CALL1   rpg_spend, 3, 1
    CALL1   rpg_bar_ability, 0, 12
    HAVE    IRON_DAGGER, 1
    HAVE    HEALTH_POTION, 2
    EXPECT_D inv + INVENTORY.armor + 4, 0   ; only the Warrior wears a chestplate
    ; a taken chest slot keeps its piece: the new chestplate goes into the bag
    call    reset_all
    mov     dword [inv + INVENTORY.armor + 4], DIAMOND_CHESTPLATE | (1 << 8)
    CALL1   rpg_spend, 0, 1
    HAVE    IRON_CHESTPLATE, 1
    EXPECT_D inv + INVENTORY.armor + 4, DIAMOND_CHESTPLATE | (1 << 8)
    ; no room at all: the kit falls at the player's feet
    call    reset_all
    lea     rdi, [inv]
    mov     ecx, INV_SLOTS
    mov     eax, COBBLE | (64 << 8)
    rep     stosd
    CALL1   rpg_spend, 3, 1
    HAVE    IRON_DAGGER, 0
    CALL1   find_drop, IRON_DAGGER, 1
    CALL1   find_drop, HEALTH_POTION, 2
    TEST_END

; ---- skill points: the web and its rules ----------------------------------------------

; CALL2 fn, a, b, n: call fn with edi = a, esi = b and fail unless eax = n
%macro CALL2 4
    mov     edi, %2
    mov     esi, %3
    call    %1
    cmp     eax, %4
    jne     .fail
%endmacro

test_rpg_skill_spend_rules:
    TEST_BEGIN
    ; --- the shape of the web: the plan's rows field by field, then what every id has to be
    xor     r12d, r12d
.rows:
    imul    eax, r12d, 24
    lea     rdi, [exp_web]
    add     rdi, rax
    call    web_row_ok
    test    eax, eax
    jnz     .fail
    inc     r12d
    cmp     r12d, (exp_web_end - exp_web) / 24
    jb      .rows
    CALL1   rpg_web_node, NUM_WEB_NODES, 0
    CALL1   rpg_web_node, 255, 0
    call    web_nodes_ok
    test    eax, eax
    jnz     .fail
    call    web_cells_ok
    test    eax, eax
    jnz     .fail
    call    web_edges_ok
    test    eax, eax
    jnz     .fail
    ; a few pairs that are no edge, in both directions
    CALL2   rpg_web_linked, 0, 1, 0                         ; two paths
    CALL2   rpg_web_linked, 0, 0, 0                         ; a node and itself
    CALL2   rpg_web_linked, 0, WEBN(1,1), 0                 ; the path and a tier 1 node
    CALL2   rpg_web_linked, WEBN(1,0), WEBN(1,6), 0         ; first nodes of two branches
    CALL2   rpg_web_linked, 76, 87, 0                       ; two bridges that are no neighbours
    CALL2   rpg_web_linked, 77, 76, 1                       ; neighbouring bridges
    CALL2   rpg_web_linked, 0, NUM_WEB_NODES, 0
    CALL2   rpg_web_linked, 1000, 0, 0
    call    web_connected_ok
    test    eax, eax
    jnz     .fail

    ; --- the reasons a point cannot be spent, in their order: 2, 3, 4, 1
    USE_PATH ARCH_WARRIOR, 1                ; level 1: the path took the only point
    CALL0   rpg_points, 0
    CALL1   rpg_can_spend, 0, 2             ; maxed (one rank): before anything else
    CALL1   rpg_can_spend, NUM_WEB_NODES, 2 ; no such node
    CALL1   rpg_can_spend, 255, 2
    CALL1   rpg_can_spend, WEBN(1,1), 3     ; level 4: before the missing neighbour and the points
    CALL1   rpg_can_spend, WEBN(2,0), 4     ; level fine, no ranked neighbour: before the points
    CALL1   rpg_can_spend, WEBN(1,0), 1     ; all well but no point
    CALL1   rpg_can_spend, 1, 1             ; a path is always reachable
    CALL1   rpg_spend, WEBN(1,0), 0         ; refused: nothing changes
    CALL1   rpg_rank, WEBN(1,0), 0
    mov     byte [R_LEVEL], 2               ; one point
    CALL0   rpg_points, 1
    CALL1   rpg_can_spend, WEBN(1,0), 0
    CALL1   rpg_can_spend, WEBN(2,0), 4     ; still not joined to a ranked node
    CALL1   rpg_can_spend, 1, 0             ; another path costs a point and nothing else
    CALL1   rpg_can_spend, WEBN(1,1), 3
    CALL1   rpg_spend, WEBN(1,0), 1
    CALL1   rpg_can_spend, WEBN(1,1), 3     ; level 2 is below 4
    ; Weapon Mastery goes to rank 5, then no further
    mov     byte [R_LEVEL], 6
    CALL1   rpg_spend, WEBN(1,0), 1
    CALL1   rpg_spend, WEBN(1,0), 1
    CALL1   rpg_spend, WEBN(1,0), 1
    CALL1   rpg_spend, WEBN(1,0), 1
    CALL1   rpg_rank, WEBN(1,0), 5
    CALL0   rpg_points, 0
    CALL1   rpg_can_spend, WEBN(1,0), 2     ; maxed, and no points either
    mov     byte [R_LEVEL], 7               ; a point is left but the node is maxed
    CALL1   rpg_can_spend, WEBN(1,0), 2
    CALL1   rpg_spend, WEBN(1,0), 0
    CALL1   rpg_rank, WEBN(1,0), 5
    CALL1   rpg_stat, STAT_MELEE_DMG, 40    ; 10 + 5 * 6
    CALL1   rpg_can_spend, WEBN(1,1), 0     ; level 4 reached, the node before it ranked
    CALL1   rpg_spend, WEBN(1,1), 1         ; Precision
    CALL0   rpg_points, 0
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 8   ; 5 + 3
    ; War Cry (ability node, branch 1 tier 1) follows the first node of its branch
    mov     byte [R_LEVEL], 8
    CALL1   rpg_can_spend, WEBN(1,7), 4
    CALL1   rpg_spend, WEBN(1,6), 1         ; Toughness: +4 health per rank
    CALL1   rpg_stat, STAT_MAX_HEALTH, 42   ; 20 + 4 (the path) + 14 (level 8) + 4
    CALL1   rpg_rank, WEBN(1,6), 1
    CALL0   rpg_points, 0
    mov     byte [R_LEVEL], 9
    CALL1   rpg_can_spend, WEBN(1,7), 0
    CALL1   rpg_ability_learned, 1, 0
    CALL1   rpg_bar_ability, 1, -1
    CALL1   rpg_spend, WEBN(1,7), 1         ; the ability goes into the first empty bar slot
    CALL1   rpg_can_spend, WEBN(1,7), 2     ; one rank only
    CALL1   rpg_ability_learned, 1, 1
    CALL1   rpg_ability_learned, 2, 0
    CALL1   rpg_bar_ability, 0, 0           ; Charge, from the path
    CALL1   rpg_bar_ability, 1, 1
    CALL1   rpg_bar_ability, 2, -1
    CALL1   rpg_stat, STAT_MAX_HEALTH, 44   ; an ability adds no stat: 20 + 4 + 16 + 4
    ; Whirlwind (tier 3, level 15) follows Iron Skin
    mov     byte [R_LEVEL], 14
    CALL1   rpg_spend, WEBN(1,8), 1
    CALL1   rpg_stat, STAT_ARMOR_BONUS, 1
    CALL1   rpg_can_spend, WEBN(1,9), 3     ; level 14, the neighbour is ranked
    mov     byte [R_LEVEL], 15
    CALL1   rpg_can_spend, WEBN(1,9), 0
    CALL1   rpg_spend, WEBN(1,9), 1
    CALL1   rpg_ability_learned, 2, 1
    CALL1   rpg_ability_learned, 3, 0
    CALL1   rpg_bar_ability, 2, 2
    CALL1   rpg_bar_ability, 3, -1
    CALL0   rpg_points, 4                   ; 15 - (1 + 5 + 1 + 1 + 1 + 1 + 1)
    CALL1   rpg_can_spend, WEBN(1,5), 3     ; a keystone asks for level 30, unreached or not
    ; Ground Slam (branch 2, tier 3) follows three nodes of its branch
    mov     byte [R_LEVEL], 22
    CALL1   rpg_can_spend, WEBN(1,15), 4
    CALL1   rpg_spend, WEBN(1,12), 1
    CALL1   rpg_spend, WEBN(1,13), 1
    CALL1   rpg_spend, WEBN(1,14), 1
    CALL1   rpg_can_spend, WEBN(1,15), 0
    CALL1   rpg_spend, WEBN(1,15), 1
    CALL1   rpg_ability_learned, 3, 1
    CALL1   rpg_ability_learned, 4, 0       ; Mage abilities belong to the Mage's nodes
    CALL1   rpg_ability_learned, NUM_ABILITIES, 0
    CALL1   rpg_bar_ability, 3, 3
    CALL0   rpg_points, 7                   ; 22 - 15

    ; --- a bridge leads into the next archetype: level 15 from an empty web
    USE_PATH 0, 15
    CALL0   rpg_points, 15
    CALL1   rpg_spend, 0, 1                 ; Path of the Warrior
    CALL1   rpg_spend, WEBN(1,12), 1        ; the first node of its third branch
    CALL1   rpg_can_spend, 76, 4            ; Runed Steel hangs on the node after it
    CALL1   rpg_spend, 76, 0
    CALL1   rpg_spend, WEBN(1,13), 1
    CALL1   rpg_can_spend, 76, 0
    CALL1   rpg_spend, 76, 1
    CALL1   rpg_stat, STAT_ADD_FIRE, 1
    CALL1   rpg_rank, 1, 0                  ; the Mage's path was never taken ...
    CALL1   rpg_can_spend, WEBN(2,1), 0     ; ... yet its first fire node, beside the bridge, is open
    CALL1   rpg_can_spend, WEBN(2,7), 4     ; Blink is not (nothing ranked next to it)
    CALL1   rpg_spend, WEBN(2,1), 1
    CALL1   rpg_can_spend, WEBN(2,2), 0     ; the Mage's own branch goes on from it
    CALL1   rpg_can_spend, WEBN(2,0), 0     ; and back towards its path
    CALL1   rpg_can_spend, WEBN(2,7), 4     ; Blink, on another branch, is still closed
    CALL1   rpg_rank, 1, 0

    ; --- the first rank of a path: its ability on the bar, its kit once, the Warrior's chestplate
    call    reset_all
    mov     byte [R_LEVEL], 3
    CALL1   rpg_spend, 1, 1                 ; Path of the Mage
    CALL1   rpg_bar_ability, 0, 4           ; Fireball
    CALL1   rpg_bar_ability, 1, -1
    HAVE    STAFF, 1
    HAVE    MANA_POTION, 2
    EXPECT_B R_KITS, 2
    ADD     GOLD_COIN, 30                   ; a respec at level 3
    CALL0   rpg_respec, 1
    CALL1   rpg_bar_ability, 0, -1
    EXPECT_B R_KITS, 2                      ; the kit stays given ...
    CALL1   rpg_spend, 1, 1
    HAVE    STAFF, 1                        ; ... and does not come twice
    HAVE    MANA_POTION, 2
    CALL1   rpg_bar_ability, 0, 4
    HAVE    IRON_SWORD, 0
    CALL1   rpg_spend, 0, 1                 ; Path of the Warrior as well
    HAVE    IRON_SWORD, 1
    HAVE    IRON_CHESTPLATE, 0
    EXPECT_D inv + INVENTORY.armor + 4, IRON_CHESTPLATE | (1 << 8)
    CALL1   rpg_bar_ability, 1, 0           ; Charge into the next empty slot
    EXPECT_B R_KITS, 3
    CALL1   rpg_spend, 2, 1                 ; the third path: all of it for 3 points
    CALL0   rpg_points, 0
    HAVE    BOW, 1
    CALL1   rpg_bar_ability, 2, 8
    TEST_END

; ---- derived stats and the description tables --------------------------------------

; path_row_ok(edi archetype) -> eax 0 when a level 1 character of that path has exactly the stats of
; its row of exp_paths (all NUM_STATS of them)
path_row_ok:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     ebx, edi
    mov     esi, 1
    call    use_path
    test    eax, eax
    jnz     .bad
    lea     eax, [rbx - 1]
    imul    eax, eax, NUM_STATS * 4
    lea     r12, [exp_paths]
    add     r12, rax
    xor     ebx, ebx
.stat:
    mov     edi, ebx
    call    rpg_stat
    cmp     eax, [r12 + rbx*4]
    jne     .bad
    inc     ebx
    cmp     ebx, NUM_STATS
    jb      .stat
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; abil_node_ok(edi ability 1..3 mod 4) -> eax 0 when the web's node of that ability (node 7, 9 or 15
; of its archetype) is an ability node of the ability's id, one rank, owned by its archetype, and
; shares the ability's name and text
abil_node_ok:
    push    rbx
    push    r12
    push    r13
    mov     ebx, edi
    call    rpg_ability_info
    mov     r12, rax
    mov     eax, ebx
    shr     eax, 2
    imul    eax, eax, 18
    mov     ecx, ebx
    and     ecx, 3
    lea     rdx, [abil_node_n]
    movzx   ecx, byte [rdx + rcx]
    lea     edi, [rax + rcx + 4]
    call    rpg_web_node
    test    rax, rax
    jz      .bad
    mov     r13, rax
    cmp     byte [r13 + WEBNODE.kind], NODE_ABILITY
    jne     .bad
    cmp     [r13 + WEBNODE.stat], bl
    jne     .bad
    cmp     byte [r13 + WEBNODE.max], 1
    jne     .bad
    cmp     dword [r13 + WEBNODE.value], 0
    jne     .bad
    mov     eax, ebx
    shr     eax, 2
    inc     eax
    cmp     [r13 + WEBNODE.arch], al
    jne     .bad
    mov     rdi, [r13 + WEBNODE.name]
    mov     rsi, [r12 + ABILINFO.name]
    call    str_eq
    test    eax, eax
    jz      .bad
    mov     rdi, [r13 + WEBNODE.desc]
    mov     rsi, [r12 + ABILINFO.desc]
    call    str_eq
    test    eax, eax
    jz      .bad
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     r13
    pop     r12
    pop     rbx
    ret

section .rodata
abil_node_n: db 0, 7, 9, 15            ; the node (of the archetype's 18) teaching slot 0..3
section .text

test_rpg_stats_from_paths_and_ranks:
    TEST_BEGIN
    call    reset_all
    ; no path: the base character
    CALL1   rpg_stat, STAT_MAX_HEALTH, 20
    CALL1   rpg_stat, STAT_MAX_STAMINA, 100
    CALL1   rpg_stat, STAT_MAX_MANA, 0
    CALL1   rpg_stat, NUM_STATS, 0          ; unknown stat
    EXPECT_D surv_max_health, 20
    ; each path alone is the row of its former class
    mov     edi, ARCH_WARRIOR
    call    path_row_ok
    test    eax, eax
    jnz     .fail
    mov     edi, ARCH_MAGE
    call    path_row_ok
    test    eax, eax
    jnz     .fail
    mov     edi, ARCH_ARCHER
    call    path_row_ok
    test    eax, eax
    jnz     .fail
    mov     edi, ARCH_ROGUE
    call    path_row_ok
    test    eax, eax
    jnz     .fail
    ; two paths add both differences from the base: Warrior and Mage at level 5
    USE_PATH ARCH_WARRIOR, 5
    CALL1   rpg_spend, 1, 1
    CALL1   rpg_stat, STAT_MAX_HEALTH, 30   ; 20 + 4 - 2 + 8
    CALL1   rpg_stat, STAT_MELEE_DMG, 10
    CALL1   rpg_stat, STAT_SPELL_DMG, 10
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 10  ; 5 + 5
    CALL1   rpg_stat, STAT_MAX_MANA, 100
    CALL1   rpg_stat, STAT_MANA_REGEN, 4
    CALL1   rpg_stat, STAT_MAX_STAMINA, 100 ; 100 + 20 - 20
    EXPECT_D surv_max_health, 30
    ; Rogue of level 5: Backstab 100, +20 per rank of its first node, 2 health per level above the first
    USE_PATH ARCH_ROGUE, 5
    CALL1   rpg_stat, STAT_BACKSTAB, 100
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 10
    CALL1   rpg_stat, STAT_MAX_STAMINA, 110
    CALL1   rpg_stat, STAT_STAMINA_REGEN, 10
    CALL1   rpg_stat, STAT_MAX_HEALTH, 28
    EXPECT_D surv_max_health, 28
    mov     byte [R_WEB + WEBN(4,0)], 2
    call    rpg_recompute
    CALL1   rpg_stat, STAT_BACKSTAB, 140
    CALL1   rpg_stat, STAT_MOVE_SPEED, 5
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 10
    EXPECT_D surv_max_health, 28
    ; the caps, reached with absurd ranks: crit chance 75, bleed chance 100, move speed 50 and
    ; dodge cost 75
    mov     byte [R_WEB + WEBN(4,1)], 100   ; Precision, +3 crit chance
    mov     byte [R_WEB + WEBN(4,3)], 100   ; Serrated, +8 bleed chance
    mov     byte [R_WEB + WEBN(4,6)], 100   ; Fleet Foot, +3 move speed
    mov     byte [R_WEB + WEBN(4,8)], 100   ; Evasion, +10 dodge cost
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
    ; Mage: 100 mana, Deep Mind (n = 6) adds 15 per rank
    USE_PATH ARCH_MAGE, 5
    CALL1   rpg_stat, STAT_MAX_MANA, 100
    CALL1   rpg_stat, STAT_MANA_REGEN, 4
    CALL1   rpg_stat, STAT_SPELL_DMG, 10
    CALL1   rpg_stat, STAT_MAX_STAMINA, 80
    EXPECT_D surv_max_health, 26
    mov     byte [R_WEB + WEBN(2,6)], 3
    call    rpg_recompute
    CALL1   rpg_stat, STAT_MAX_MANA, 145
    mov     byte [R_WEB + WEBN(2,7)], 1     ; Blink: no stat of its own
    call    rpg_recompute
    CALL1   rpg_stat, STAT_MAX_MANA, 145
    CALL1   rpg_stat, STAT_MANA_REGEN, 4
    mov     byte [R_WEB + WEBN(2,10)], 100  ; Haste: cooldowns capped at 50
    mov     byte [R_WEB + WEBN(2,14)], 100  ; Arcane Reach: area capped at 100
    call    rpg_recompute
    CALL1   rpg_stat, STAT_COOLDOWN_RED, 50
    CALL1   rpg_stat, STAT_AREA, 100
    mov     byte [R_WEB + WEBN(2,10)], 0
    mov     byte [R_WEB + WEBN(2,14)], 0
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
    USE_PATH ARCH_WARRIOR, 5
    CALL1   rpg_stat, STAT_MELEE_DMG, 10
    CALL1   rpg_stat, STAT_MAX_STAMINA, 120
    EXPECT_D surv_max_health, 32
    mov     dword [surv + SURVIVAL.health], 40
    call    rpg_recompute
    EXPECT_D surv + SURVIVAL.health, 32
    mov     byte [R_WEB + WEBN(1,6)], 2
    call    rpg_recompute
    EXPECT_D surv_max_health, 40
    EXPECT_D surv + SURVIVAL.health, 32
    mov     byte [R_WEB + WEBN(1,10)], 3    ; Shield Wall: block cost, capped at 75
    call    rpg_recompute
    CALL1   rpg_stat, STAT_BLOCK_COST, 30
    mov     byte [R_WEB + WEBN(1,10)], 100
    call    rpg_recompute
    CALL1   rpg_stat, STAT_BLOCK_COST, 75
    ; a stat node bought through the web: three ranks of Weapon Mastery
    USE_PATH ARCH_WARRIOR, 5
    CALL1   rpg_spend, WEBN(1,0), 1
    CALL1   rpg_spend, WEBN(1,0), 1
    CALL1   rpg_spend, WEBN(1,0), 1
    CALL1   rpg_stat, STAT_MELEE_DMG, 28    ; 10 + 3 * 6
    ; Archer: Quiver (n = 8) saves arrows, capped at 75
    USE_PATH ARCH_ARCHER, 5
    CALL1   rpg_stat, STAT_RANGED_DMG, 15
    CALL1   rpg_stat, STAT_ARROW_SAVE, 10
    mov     byte [R_WEB + WEBN(3,8)], 3
    call    rpg_recompute
    CALL1   rpg_stat, STAT_ARROW_SAVE, 40
    mov     byte [R_WEB + WEBN(3,8)], 100
    call    rpg_recompute
    CALL1   rpg_stat, STAT_ARROW_SAVE, 75
    ; the bridges: each alone, two ranks of its stat, and what the node says about itself
    xor     r12d, r12d
.bridge:
    call    reset_all
    imul    eax, r12d, 16
    lea     r13, [exp_bridges]
    add     r13, rax
    mov     edi, [r13]
    call    rpg_web_node
    mov     r14, rax
    cmp     byte [r14 + WEBNODE.kind], NODE_STAT
    jne     .fail
    mov     eax, [r13 + 4]
    cmp     [r14 + WEBNODE.stat], al
    jne     .fail
    cmp     byte [r14 + WEBNODE.max], 3
    jne     .fail
    cmp     byte [r14 + WEBNODE.arch], 0
    jne     .fail
    mov     eax, [r13 + 8]
    cmp     [r14 + WEBNODE.value], eax
    jne     .fail
    mov     eax, [r13 + 12]
    cmp     [r14 + WEBNODE.level], al
    jne     .fail
    mov     edi, [r13]
    lea     rax, [R_WEB]
    mov     byte [rax + rdi], 2
    call    rpg_recompute
    mov     edi, [r13 + 4]
    call    rpg_stat
    mov     ecx, [r13 + 8]
    add     ecx, ecx
    cmp     eax, ecx
    jne     .fail
    inc     r12d
    cmp     r12d, (exp_bridges_end - exp_bridges) / 16
    jb      .bridge
    ; ability slots: the path teaches slot 0, an ability node its own slot; nothing else does
    USE_PATH 0, 5
    mov     r12d, 0
.none:
    mov     edi, r12d
    call    rpg_ability_learned
    test    eax, eax
    jnz     .fail
    inc     r12d
    cmp     r12d, NUM_ABILITIES
    jb      .none
    mov     byte [R_WEB + 1], 1             ; Path of the Mage
    CALL1   rpg_ability_learned, 4, 1
    CALL1   rpg_ability_learned, 5, 0
    CALL1   rpg_ability_learned, 6, 0
    CALL1   rpg_ability_learned, 7, 0
    mov     byte [R_WEB + WEBN(2,9)], 1
    CALL1   rpg_ability_learned, 6, 1
    CALL1   rpg_ability_learned, 5, 0
    CALL1   rpg_ability_learned, 7, 0
    mov     byte [R_WEB + WEBN(2,15)], 1
    CALL1   rpg_ability_learned, 7, 1
    mov     byte [R_WEB + WEBN(2,7)], 1
    CALL1   rpg_ability_learned, 5, 1
    CALL1   rpg_ability_learned, 3, 0
    CALL1   rpg_ability_learned, 8, 0
    CALL1   rpg_ability_learned, NUM_ABILITIES, 0
    ; the description tables: a node's name and text, abilities
    mov     edi, WEBN(2,6)
    call    rpg_web_node
    mov     r14, rax
    mov     rax, [r14 + WEBNODE.name]
    STR_IS  s_deepmind
    cmp     qword [r14 + WEBNODE.desc], 0   ; a stat node's text is its formatted value
    jne     .fail
    cmp     byte [r14 + WEBNODE.kind], NODE_STAT
    jne     .fail
    cmp     byte [r14 + WEBNODE.stat], STAT_MAX_MANA
    jne     .fail
    cmp     byte [r14 + WEBNODE.max], 5
    jne     .fail
    cmp     dword [r14 + WEBNODE.value], 15
    jne     .fail
    FMT_IS  STAT_MAX_MANA, 15, s_f_mana15
    ; an ability node shares the name and the text of its ability
    xor     r12d, r12d
.anode:
    test    r12b, 3
    jz      .anode_next                     ; slot 0 is taught by the path
    mov     edi, r12d
    call    abil_node_ok
    test    eax, eax
    jnz     .fail
.anode_next:
    inc     r12d
    cmp     r12d, NUM_ABILITIES
    jb      .anode
    mov     edi, WEBN(2,7)
    call    rpg_web_node
    mov     rax, [rax + WEBNODE.name]
    STR_IS  s_blink
    ; the plan's ability table: resource, cost and cooldown of every ability, by ability id
    xor     r12d, r12d
.abil:
    mov     edi, r12d
    call    rpg_ability_info
    mov     r14, rax
    lea     eax, [r12 + r12*2]              ; 3 bytes per entry
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
    inc     r12d
    cmp     r12d, NUM_ABILITIES
    jb      .abil
    ; out of range: an empty record, never a null pointer
    mov     edi, NUM_ABILITIES
    call    rpg_ability_info
    test    rax, rax
    jz      .fail
    mov     rax, [rax + ABILINFO.name]
    STR_IS  s_empty
    ; the HUD and web icon of an ability follows its id: three tiles per archetype, then slot 3's
    CALL1   rpg_ability_tile, 0, TILE_ABILITY0
    CALL1   rpg_ability_tile, 8, TILE_ABILITY0 + 6
    CALL1   rpg_ability_tile, 10, TILE_ABILITY0 + 8
    CALL1   rpg_ability_tile, 11, TILE_ABILITY3_0 + 2
    CALL1   rpg_ability_tile, 3, TILE_ABILITY3_0
    CALL1   rpg_ability_tile, NUM_ABILITIES, 0
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
    USE_PATH ARCH_WARRIOR, 1                ; level 1: no attribute points yet
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
    CALL1   rpg_spend, WEBN(1,0), 1
    CALL1   rpg_spend, WEBN(1,0), 1
    CALL1   rpg_stat, STAT_MELEE_DMG, 25            ; 10 + 3 + 2 * 6
    CALL1   rpg_bar_ability, 0, 0                   ; Charge from the path
    ; the respec costs 10 coins per level
    CALL0   rpg_respec_cost, 100
    mov     byte [R_LEVEL], 1
    CALL0   rpg_respec_cost, 10
    mov     byte [R_LEVEL], 50
    CALL0   rpg_respec_cost, 500
    mov     byte [R_LEVEL], 10
    ; 99 coins are one short: nothing happens
    ADD     GOLD_COIN, 99
    CALL0   rpg_respec, 0
    HAVE    GOLD_COIN, 99
    CALL1   rpg_rank, WEBN(1,0), 2
    CALL1   rpg_rank, 0, 1
    CALL1   rpg_attr, ATTR_DEX, 12
    CALL1   rpg_bar_ability, 0, 0
    CALL1   rpg_stat, STAT_MELEE_DMG, 25
    ADD     GOLD_COIN, 11
    CALL0   rpg_respec, 1
    HAVE    GOLD_COIN, 10
    CALL1   rpg_rank, WEBN(1,0), 0
    CALL1   rpg_rank, 0, 0                          ; the path goes back too
    CALL1   rpg_bar_ability, 0, -1
    EXPECT_D R_BAR, 0
    EXPECT_B R_KITS, 0xFF                           ; a given kit stays given
    CALL1   rpg_attr, ATTR_STR, 0
    CALL1   rpg_attr, ATTR_DEX, 0
    CALL1   rpg_attr, ATTR_INT, 0
    CALL1   rpg_attr, ATTR_VIT, 0
    CALL0   rpg_points, 10
    CALL0   rpg_attr_points, 27
    CALL1   rpg_stat, STAT_MELEE_DMG, 0             ; no path: the base character
    CALL1   rpg_stat, STAT_MAX_HEALTH, 38           ; 20 + 18
    EXPECT_D surv_max_health, 38
    ; the kit of a path taken for real stays given through a respec: nothing is taken back
    call    reset_all
    mov     byte [R_LEVEL], 4
    CALL1   rpg_spend, 2, 1                         ; Path of the Archer: bow and arrows
    EXPECT_B R_KITS, 4
    CALL1   rpg_spend, WEBN(3,0), 1
    ADD     GOLD_COIN, 40
    CALL0   rpg_respec, 1
    HAVE    GOLD_COIN, 0
    EXPECT_B R_KITS, 4
    HAVE    BOW, 1
    HAVE    ARROW, 32
    CALL1   rpg_bar_ability, 0, -1
    CALL1   rpg_rank, 2, 0
    CALL0   rpg_points, 4
    ; the attribute points survive the header ...
    USE_PATH ARCH_WARRIOR, 10
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
    CALL1   rpg_rank, 0, 1
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
    ; Warrior of level 30: the first branch (nodes n = 0..4), then its keystone (n = 5)
    USE_PATH ARCH_WARRIOR, 30
    mov     r12d, WEBN(1,0)
.b0:
    mov     edi, r12d
    call    rpg_spend
    cmp     eax, 1
    jne     .fail
    inc     r12d
    cmp     r12d, WEBN(1,5)
    jb      .b0
    CALL1   rpg_keystone, KS_EXECUTIONER, 0
    CALL1   rpg_can_spend, WEBN(1,5), 0
    CALL1   rpg_spend, WEBN(1,5), 1
    CALL1   rpg_keystone, KS_EXECUTIONER, 1
    CALL1   rpg_keystone, KS_JUGGERNAUT, 0
    CALL1   rpg_keystone, NUM_KEYSTONES, 0          ; there are 12 keystones
    CALL1   rpg_can_spend, WEBN(1,5), 2             ; one rank only
    EXPECT_D rpg_keystones, 1 << KS_EXECUTIONER
    ; the Juggernaut branch (n = 6..10, then 11): the keystone asks for level 30
    mov     byte [R_LEVEL], 29
    mov     r12d, WEBN(1,6)
.b1:
    mov     edi, r12d
    call    rpg_spend
    cmp     eax, 1
    jne     .fail
    inc     r12d
    cmp     r12d, WEBN(1,11)
    jb      .b1
    CALL1   rpg_can_spend, WEBN(1,11), 3
    mov     byte [R_LEVEL], 30
    CALL1   rpg_can_spend, WEBN(1,11), 0
    CALL1   rpg_spend, WEBN(1,11), 1
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
    mov     r12d, 1                                 ; archetype
.arch:
    xor     r13d, r13d                              ; branch
.branch:
    mov     edi, r12d
    mov     esi, 30
    call    use_path
    test    eax, eax
    jnz     .fail
    lea     eax, [r13 + r13*2]                      ; 6 nodes per branch
    add     eax, eax
    lea     ecx, [r12 - 1]
    imul    ecx, ecx, 18
    lea     eax, [rax + rcx + 4 + 5]                ; the keystone is its sixth node
    lea     rdx, [R_WEB]
    mov     byte [rdx + rax], 1
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
    cmp     r12d, NUM_ARCHETYPES
    jbe     .arch
    ; the bar of the levels and the XP of a level 11 kill: 10 * (9 + 11) / 10 = 20, an elite 60
    CALL1   rpg_xp_need, 1, 31
    CALL1   rpg_xp_need, 2, 44
    CALL1   rpg_xp_need, 49, 2911
    CALL1   rpg_xp_need, 50, 0
    USE_PATH ARCH_WARRIOR, 5
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

; ---- archetype titles ----------------------------------------------------------------

; the web rank of node %1 = %2, poked (no spending, no recompute)
%macro WEB 2
    mov     byte [R_WEB + %1], %2
%endmacro
; fail unless rpg_title() is the zstr %1 and rpg_archetype() is %2
%macro TITLE 2
    call    rpg_title
    STR_IS  %1
    call    rpg_archetype
    cmp     eax, %2
    jne     .fail
%endmacro

; clear_web(): no ranks at all
clear_web:
    lea     rdi, [R_WEB]
    mov     ecx, WEB_MAX
    xor     eax, eax
    rep     stosb
    ret

; pair_title_ok(rdi row of exp_pairs) -> eax 0 when the pair (lo, hi) with equal sums 2 / 2 is titled
; by the row's title and led by lo (a tie goes to the lower id), and with hi ahead 3 / 2 is led by
; hi and keeps the title
pair_title_ok:
    push    rbx
    mov     rbx, rdi
    call    clear_web
    mov     eax, [rbx]                      ; lo
    lea     rcx, [R_WEB]
    mov     byte [rcx + rax - 1], 1         ; its path
    lea     edx, [rax - 1]
    imul    edx, edx, 18
    mov     byte [rcx + rdx + 4], 1         ; and its first node: a sum of 2
    mov     eax, [rbx + 4]                  ; hi
    mov     byte [rcx + rax - 1], 1
    lea     edx, [rax - 1]
    imul    edx, edx, 18
    mov     byte [rcx + rdx + 4], 1
    call    rpg_title
    mov     rdi, rax
    mov     rsi, [rbx + 8]
    call    str_eq
    test    eax, eax
    jz      .bad
    call    rpg_archetype
    cmp     eax, [rbx]
    jne     .bad
    mov     eax, [rbx + 4]
    lea     rcx, [R_WEB]
    lea     edx, [rax - 1]
    imul    edx, edx, 18
    mov     byte [rcx + rdx + 4], 2         ; hi: 3 against lo's 2
    call    rpg_title
    mov     rdi, rax
    mov     rsi, [rbx + 8]
    call    str_eq
    test    eax, eax
    jz      .bad
    call    rpg_archetype
    cmp     eax, [rbx + 4]
    jne     .bad
    xor     eax, eax
    jmp     .ret
.bad:
    mov     eax, 1
.ret:
    pop     rbx
    ret

test_archetype_titles:
    TEST_BEGIN
    call    reset_all
    ; a fresh character
    TITLE   s_wanderer, 0
    CALL1   rpg_archetype_ranks, 1, 0
    CALL1   rpg_archetype_ranks, 4, 0
    ; the names of the archetypes
    xor     edi, edi
    call    rpg_archetype_name
    STR_IS  s_wanderer
    mov     edi, ARCH_WARRIOR
    call    rpg_archetype_name
    STR_IS  s_warrior
    mov     edi, ARCH_MAGE
    call    rpg_archetype_name
    STR_IS  s_mage
    mov     edi, ARCH_ARCHER
    call    rpg_archetype_name
    STR_IS  s_archer
    mov     edi, ARCH_ROGUE
    call    rpg_archetype_name
    STR_IS  s_rogue
    mov     edi, NUM_ARCHETYPES + 1
    call    rpg_archetype_name
    STR_IS  s_empty
    CALL1   rpg_archetype_ranks, NUM_ARCHETYPES + 1, 0
    ; one path alone is its archetype
    WEB     0, 1
    TITLE   s_warrior, ARCH_WARRIOR
    CALL1   rpg_archetype_ranks, 1, 1
    call    clear_web
    WEB     1, 1
    TITLE   s_mage, ARCH_MAGE
    call    clear_web
    WEB     2, 1
    TITLE   s_archer, ARCH_ARCHER
    call    clear_web
    WEB     3, 1
    TITLE   s_rogue, ARCH_ROGUE
    ; Warrior 4 (the path and three ranks of Weapon Mastery), Mage 2: a Spellblade
    call    clear_web
    WEB     0, 1
    WEB     WEBN(1,0), 3
    WEB     1, 1
    WEB     WEBN(2,0), 1
    TITLE   s_spellblade, ARCH_WARRIOR
    CALL1   rpg_archetype_ranks, 1, 4
    CALL1   rpg_archetype_ranks, 2, 2
    CALL1   rpg_archetype_ranks, 3, 0
    ; Warrior 5 against Mage 2: twice the second is below the first, a plain Warrior
    WEB     WEBN(1,0), 4
    TITLE   s_warrior, ARCH_WARRIOR
    CALL1   rpg_archetype_ranks, 1, 5
    ; the bridges belong to neither: a lot of them changes nothing
    WEB     76, 3
    WEB     87, 3
    TITLE   s_warrior, ARCH_WARRIOR
    CALL1   rpg_archetype_ranks, 1, 5
    CALL1   rpg_archetype_ranks, 2, 2
    CALL1   rpg_archetype_ranks, 4, 0
    ; Warrior and Archer of close sums: a Warden, led by the lower id on a tie
    call    clear_web
    WEB     0, 1
    WEB     WEBN(1,0), 2
    WEB     2, 1
    WEB     WEBN(3,0), 2
    TITLE   s_warden, ARCH_WARRIOR
    CALL1   rpg_archetype_ranks, 3, 3
    ; the Mage ahead of the Warrior by one: the Mage leads, the pair stays a Spellblade
    call    clear_web
    WEB     0, 1
    WEB     WEBN(1,0), 2                    ; Warrior 3
    WEB     1, 1
    WEB     WEBN(2,0), 3                    ; Mage 4
    TITLE   s_spellblade, ARCH_MAGE
    ; the second place is the second largest sum, not the next id: Warrior 4, Mage 1, Archer 3
    call    clear_web
    WEB     0, 1
    WEB     WEBN(1,0), 3
    WEB     1, 1
    WEB     2, 1
    WEB     WEBN(3,0), 2
    TITLE   s_warden, ARCH_WARRIOR
    ; Archer 7 against Rogue 3: more than twice, a plain Archer; Archer 6, a Skirmisher
    call    clear_web
    WEB     2, 1
    WEB     WEBN(3,0), 6
    WEB     3, 1
    WEB     WEBN(4,0), 2
    TITLE   s_archer, ARCH_ARCHER
    WEB     WEBN(3,0), 5
    TITLE   s_skirmisher, ARCH_ARCHER
    ; the six pairs, each reachable and in the right place
    xor     r12d, r12d
.pairs:
    imul    eax, r12d, 16
    lea     rdi, [exp_pairs]
    add     rdi, rax
    call    pair_title_ok
    test    eax, eax
    jnz     .fail
    inc     r12d
    cmp     r12d, (exp_pairs_end - exp_pairs) / 16
    jb      .pairs
    TEST_END

; ---- save and load -----------------------------------------------------------------

; hdr_set(edi legacy_class, esi level): the header's RPG records are all zero but the legacy class,
; the level and the extension's version (the current one)
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
    mov     [HDR + RPGSAVE.legacy_class], bl
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
    USE_PATH ARCH_ARCHER, 7
    mov     dword [R_XP], 55
    mov     byte [R_WEB + WEBN(3,0)], 2     ; Steady Aim
    mov     byte [R_WEB + WEBN(3,1)], 1     ; Eagle Eye, which needs it
    mov     byte [R_WEB + WEBN(3,6)], 1     ; Fleet Foot
    mov     byte [R_QUEST], 3
    mov     byte [R_QSTATE], 1
    mov     word [R_QPROG], 2
    lea     rdi, [world_header]
    call    rpg_save
    EXPECT_B HDR + RPGSAVE.legacy_class, 0
    EXPECT_B HDR + RPGSAVE.level, 7
    EXPECT_D HDR + RPGSAVE.xp, 55
    EXPECT_B HWEB + 2, 1                    ; the path of the Archer
    EXPECT_B HWEB + WEBN(3,1), 1
    EXPECT_B HDRX + RPGEXT.version, RPGX_VERSION
    EXPECT_B HDRX + RPGEXT.bar, 9           ; ability 8 + 1
    EXPECT_B HDRX + RPGEXT.kits, 0xFF
    call    rpg_reset
    CALL1   rpg_rank, 2, 0
    CALL1   rpg_bar_ability, 0, -1
    mov     byte [banner_text], 0
    call    hdr_load
    CALL0   rpg_level, 7
    EXPECT_D R_XP, 55
    CALL1   rpg_rank, 2, 1
    CALL1   rpg_rank, WEBN(3,0), 2
    CALL1   rpg_rank, WEBN(3,1), 1
    CALL1   rpg_rank, WEBN(3,6), 1
    CALL1   rpg_rank, WEBN(3,2), 0
    CALL1   rpg_bar_ability, 0, 8           ; the bar comes back with the web
    EXPECT_B banner_text, 0                 ; nothing was refunded
    EXPECT_B R_QUEST, 3
    EXPECT_B R_QSTATE, 1
    cmp     word [R_QPROG], 2
    jne     .fail
    CALL1   rpg_stat, STAT_RANGED_DMG, 27   ; stats are recomputed: 15 + 2 * 6
    CALL1   rpg_stat, STAT_MOVE_SPEED, 8    ; Fleet Foot rank 1: 5 + 3
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 11  ; 8 + 3
    ; a legacy class byte of a current header means nothing and is written back as 0
    HDR_NEW 5
    mov     byte [HDR + RPGSAVE.legacy_class], 9
    call    hdr_load
    CALL0   rpg_level, 5
    EXPECT_B rpg_state + RPGSAVE.legacy_class, 0
    ; zeros are a path-less character; the level byte stays
    HDR_NEW 10
    call    hdr_load
    CALL0   rpg_level, 10
    CALL0   rpg_points, 10
    EXPECT_ZERO_WEB
    ; a level outside 1..50 rebuilds the character
    HDR_NEW 0
    HW      0, 1
    mov     byte [HDRX + RPGEXT.kits], 0x0F
    call    hdr_load
    CALL0   rpg_level, 1
    CALL1   rpg_rank, 0, 0
    EXPECT_B R_KITS, 0
    HDR_NEW 51
    HW      0, 1
    call    hdr_load
    CALL0   rpg_level, 1
    CALL1   rpg_rank, 0, 0
    HDR_NEW 50
    HW      0, 1
    call    hdr_load
    CALL0   rpg_level, 50
    CALL1   rpg_rank, 0, 1
    ; ranks of 3 everywhere at level 5: more than the level, and past a node's max
    HDR_NEW 5
    lea     rdi, [HWEB]
    mov     ecx, NUM_WEB_NODES
    mov     al, 3
    rep     stosb
    LOAD_REFUNDS
    CALL0   rpg_level, 5
    CALL1   rpg_stat, STAT_RANGED_DMG, 0
    ; a rank past its node's maximum (5 for a stat node, 1 for a path, an ability, a keystone, 3 for a
    ; bridge) zeroes every rank and the bar
    HDR_NEW 10
    HW      0, 1
    HW      4, 6
    mov     byte [HDRX + RPGEXT.bar], 1
    LOAD_REFUNDS
    CALL0   rpg_level, 10
    HDR_NEW 10
    HW      0, 2
    LOAD_REFUNDS
    HDR_NEW 20
    HW      0, 1
    HW      WEBN(1,6), 1
    HW      WEBN(1,7), 2
    LOAD_REFUNDS
    HDR_NEW 30
    HW      3, 1
    HW      WEBN(4,0), 1
    HW      WEBN(4,1), 1
    HW      WEBN(4,2), 1
    HW      WEBN(4,3), 1
    HW      WEBN(4,4), 1
    HW      WEBN(4,5), 2                    ; the Assassinate keystone
    LOAD_REFUNDS
    HDR_NEW 30
    HW      0, 1
    HW      WEBN(1,13), 1
    HW      WEBN(1,12), 1
    HW      76, 4                           ; a bridge goes to 3
    LOAD_REFUNDS
    HDR_NEW 30
    HW      0, 1
    HW      WEBN(1,13), 1
    HW      WEBN(1,12), 1
    HW      76, 3                           ; and 3 is fine
    LOAD_KEEPS 76, 3
    ; a slot past the last node holds nothing
    HDR_NEW 5
    HW      0, 1
    HW      100, 1
    LOAD_REFUNDS
    ; the ranks adding up to the level are fine, one more is not
    HDR_NEW 6
    HW      0, 1
    HW      WEBN(1,0), 5
    LOAD_KEEPS WEBN(1,0), 5
    HDR_NEW 5
    HW      0, 1
    HW      WEBN(1,0), 5
    LOAD_REFUNDS
    ; a ranked node under its level (tier 1 asks for 4)
    HDR_NEW 4
    HW      0, 1
    HW      WEBN(1,0), 1
    HW      WEBN(1,1), 1
    LOAD_KEEPS WEBN(1,1), 1
    HDR_NEW 3
    HW      0, 1
    HW      WEBN(1,0), 1
    HW      WEBN(1,1), 1
    LOAD_REFUNDS
    ; a ranked node has to be joined to a ranked path through ranked nodes
    HDR_NEW 10
    HW      WEBN(1,0), 1
    LOAD_REFUNDS
    HDR_NEW 10
    HW      0, 1
    HW      WEBN(1,1), 1                    ; the node before it is not ranked
    LOAD_REFUNDS
    HDR_NEW 10
    HW      0, 1
    HW      WEBN(1,0), 1
    HW      WEBN(1,1), 1
    LOAD_KEEPS WEBN(1,1), 1
    ; a branch's first node needs only the path, and so does the first node of the next branch
    HDR_NEW 10
    HW      0, 1
    HW      WEBN(1,6), 1
    HW      WEBN(1,12), 1
    LOAD_KEEPS WEBN(1,12), 1
    ; across a bridge: Runed Steel joins Warrior branch 2 to the Mage's first fire node
    HDR_NEW 15
    HW      0, 1
    HW      WEBN(1,12), 1
    HW      WEBN(1,13), 1
    HW      76, 1
    HW      WEBN(2,1), 1
    LOAD_KEEPS WEBN(2,1), 1
    EXPECT_B R_WEB + 76, 1
    HDR_NEW 15
    HW      0, 1
    HW      WEBN(1,12), 1
    HW      76, 1                           ; the bridge hangs on a node that is not ranked ...
    HW      WEBN(2,1), 1
    LOAD_REFUNDS
    HDR_NEW 15
    HW      0, 1
    HW      WEBN(1,12), 1
    HW      WEBN(1,13), 1
    HW      WEBN(2,1), 1                    ; ... and the Mage's node on a bridge that is not ranked
    LOAD_REFUNDS
    ; a bar slot whose ability the web does not teach is emptied, the others stay
    HDR_NEW 10
    HW      0, 1
    mov     byte [HDRX + RPGEXT.bar + 0], 1     ; ability 0: Charge, taught by the path
    mov     byte [HDRX + RPGEXT.bar + 1], 6     ; ability 5: Blink, not learned
    mov     byte [HDRX + RPGEXT.bar + 2], 200   ; no such ability
    mov     byte [HDRX + RPGEXT.bar + 3], 16    ; ability 15: Fan of Knives, not learned
    call    hdr_load
    CALL1   rpg_rank, 0, 1
    CALL1   rpg_bar_ability, 0, 0
    CALL1   rpg_bar_ability, 1, -1
    CALL1   rpg_bar_ability, 2, -1
    CALL1   rpg_bar_ability, 3, -1
    ; XP stays below the bar (59 at level 3); none at level 50
    HDR_NEW 3
    mov     dword [HDR + RPGSAVE.xp], 58
    call    hdr_load
    EXPECT_D R_XP, 58
    mov     dword [HDR + RPGSAVE.xp], 59
    call    hdr_load
    EXPECT_D R_XP, 58
    mov     dword [HDR + RPGSAVE.xp], 0xFFFFFFFF
    call    hdr_load
    EXPECT_D R_XP, 58
    HDR_NEW 50
    mov     dword [HDR + RPGSAVE.xp], 5
    call    hdr_load
    CALL0   rpg_level, 50
    EXPECT_D R_XP, 0
    ; quest 0..8, quest state 0/1
    HDR_NEW 4
    mov     byte [HDR + RPGSAVE.quest], 8
    mov     byte [HDR + RPGSAVE.quest_state], 1
    call    hdr_load
    EXPECT_B R_QUEST, 8
    EXPECT_B R_QSTATE, 1
    mov     byte [HDR + RPGSAVE.quest], 9
    mov     byte [HDR + RPGSAVE.quest_state], 2
    call    hdr_load
    EXPECT_B R_QUEST, 0
    EXPECT_B R_QSTATE, 0
    mov     byte [HDR + RPGSAVE.quest], 0xFF
    call    hdr_load
    EXPECT_B R_QUEST, 0

    ; --- a header of version 1 (a save with classes): Mage, with ranks, attribute points, XP
    mov     edi, 2                          ; legacy class: Mage
    mov     esi, 12
    call    hdr_set
    mov     byte [HDRX + RPGEXT.version], 1
    mov     byte [HDRX + RPGEXT.legacy + 0], 3
    mov     byte [HDRX + RPGEXT.legacy + 6], 1
    mov     byte [HDRX + RPGEXT.legacy + 31], 1
    mov     word [HDRX + RPGEXT.attr + ATTR_INT*2], 5
    mov     dword [HDR + RPGSAVE.xp], 7
    mov     byte [HDRX + RPGEXT.kits], 0x55         ; whatever the old record held
    mov     byte [HDRX + RPGEXT.bar], 6
    HW      4, 1
    mov     byte [rpg_migrated], 0
    mov     byte [banner_text], 0
    call    hdr_load
    CALL0   rpg_level, 12
    EXPECT_D R_XP, 7
    EXPECT_ZERO_WEB
    EXPECT_D R_BAR, 0
    lea     rdi, [R_LEGACY]
    mov     esi, 32
    call    bytes_sum
    test    eax, eax
    jnz     .fail
    CALL1   rpg_attr, ATTR_INT, 5                   ; the attribute points stay
    EXPECT_B R_KITS, KIT_COMMON_BIT | 2             ; the common kit and the Mage's
    EXPECT_B rpg_state + RPGSAVE.legacy_class, 0
    EXPECT_B rpg_ext + RPGEXT.version, RPGX_VERSION
    CALL0   rpg_points, 12
    CALL1   rpg_stat, STAT_MAX_MANA, 10             ; no path, 5 Intelligence: the stats were rebuilt
    cmp     byte [rpg_migrated], 0
    je      .fail
    BANNER_IS s_migrated
    ; rpg_begin keeps the refund banner and clears the flag; the kits counted as given are not given
    call    rpg_begin
    BANNER_IS s_migrated
    EXPECT_B rpg_migrated, 0
    HAVE    COOKED_PORKCHOP, 0
    HAVE    STAFF, 0
    ; it is saved as the current version, and a second load keeps it without a word
    lea     rdi, [world_header]
    call    rpg_save
    EXPECT_B HDRX + RPGEXT.version, RPGX_VERSION
    mov     byte [banner_text], 0
    call    hdr_load
    CALL1   rpg_attr, ATTR_INT, 5
    EXPECT_B banner_text, 0
    EXPECT_B rpg_migrated, 0
    ; version 0 as well, and it loses its attribute points
    mov     edi, 4                          ; legacy class: Rogue
    mov     esi, 12
    call    hdr_set
    mov     byte [HDRX + RPGEXT.version], 0
    mov     word [HDRX + RPGEXT.attr + ATTR_INT*2], 5
    mov     dword [HDR + RPGSAVE.xp], 7
    mov     byte [banner_text], 0
    call    hdr_load
    CALL0   rpg_level, 12
    EXPECT_D R_XP, 7
    EXPECT_ZERO_WEB
    CALL1   rpg_attr, ATTR_INT, 0
    EXPECT_B R_KITS, KIT_COMMON_BIT | 8
    CALL0   rpg_attr_points, 33
    BANNER_IS s_migrated
    ; no class (or an unknown one) counts only the common kit
    mov     edi, 0
    mov     esi, 5
    call    hdr_set
    mov     byte [HDRX + RPGEXT.version], 1
    call    hdr_load
    EXPECT_B R_KITS, KIT_COMMON_BIT
    mov     edi, 5
    mov     esi, 5
    call    hdr_set
    mov     byte [HDRX + RPGEXT.version], 0
    call    hdr_load
    EXPECT_B R_KITS, KIT_COMMON_BIT
    mov     edi, 1
    mov     esi, 5
    call    hdr_set
    mov     byte [HDRX + RPGEXT.version], 1
    call    hdr_load
    EXPECT_B R_KITS, KIT_COMMON_BIT | 1

    ; --- rpg_begin: the common kit once, the grimoire hint while no point is spent
    call    reset_all
    mov     byte [rpg_migrated], 0
    mov     byte [banner_text], 0
    call    rpg_begin
    HAVE    COOKED_PORKCHOP, 4
    EXPECT_B R_KITS, KIT_COMMON_BIT
    call    banner_begin_ok
    test    eax, eax
    jnz     .fail
    mov     byte [banner_text], 0
    call    rpg_begin
    HAVE    COOKED_PORKCHOP, 4                      ; given once
    call    banner_begin_ok                         ; and the hint comes again
    test    eax, eax
    jnz     .fail
    mov     byte [R_WEB], 1                         ; a path taken: no hint
    mov     byte [banner_text], 0
    call    rpg_begin
    EXPECT_B banner_text, 0
    HAVE    COOKED_PORKCHOP, 4
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
    USE_PATH ARCH_WARRIOR, 5
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
    mov     edi, FAC_VILLAGERS              ; the Merchant's table, whatever an earlier test opened
    call    trade_open
    ; the offer table
    xor     r12d, r12d
.offers:
    mov     edi, r12d
    call    trade_offer
    test    rax, rax
    jz      .fail
    mov     rcx, r12
    shl     rcx, 4
    lea     rdx, [t_trades]
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
    cmp     r12d, [trade_count]
    jb      .offers
    mov     edi, [trade_count]              ; one past the last row
    call    trade_offer
    test    rax, rax
    jnz     .fail
    mov     edi, [trade_count]
    call    trade_can
    test    eax, eax
    jnz     .fail
    mov     edi, [trade_count]
    call    trade_execute
    test    eax, eax
    jnz     .fail
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
    USE_PATH ARCH_WARRIOR, 10
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
    USE_PATH ARCH_WARRIOR, 50
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
    USE_PATH ARCH_WARRIOR, 10
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
