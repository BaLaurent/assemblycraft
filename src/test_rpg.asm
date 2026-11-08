; test_rpg.asm - character progression, skill points, derived stats, quests and trades.
%include "common.inc"
default rel

global test_rpg_levels_and_points, test_rpg_skill_spend_rules, test_rpg_stats_from_class_and_ranks
global test_rpg_save_load_validates, test_quest_chain_progress_and_rewards
global test_trade_exchanges_items

extern world_clear, world_header, str_eq, fx_clear
extern inv, inv_clear, inv_add, inv_count
extern drops, drops_clear
extern surv, survival_reset, surv_max_health
extern combat_reset, combat_mana, combat_stamina
extern rpg_state, rpg_reset, rpg_set_class, rpg_class, rpg_level, rpg_points, rpg_xp_need
extern rpg_add_xp, rpg_can_spend, rpg_spend, rpg_rank, rpg_stat, rpg_recompute
extern rpg_ability_unlocked, rpg_class_info, rpg_node_info, rpg_ability_info, rpg_branch_name
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
%define R_RANKS   rpg_state + RPGSAVE.ranks
%define R_CLEARED rpg_state + RPGSAVE.cleared
%define R_FLAGS   rpg_state + RPGSAVE.flags
%define HDR       world_header + WORLDHDR.rpg

section .rodata
align 4
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
s_warrior:  db "Warrior", 0
s_mage:     db "Mage", 0
s_archer:   db "Archer", 0
s_rogue:    db "Rogue", 0
s_heavy:    db "Heavy armor", 0
s_deepmind: db "Deep Mind", 0
s_plus20:   db "+20 mana", 0
s_agility:  db "Agility", 0
s_empty:    db 0
s_title0:   db "Zombie Trouble", 0
s_fallen:   db "The Fallen King", 0

; the plan's skill trees: node = branch * 4 + tier; stat id (0x80 | slot for an ability), value
exp_nodes:
    ; Warrior
    db STAT_MELEE_DMG, 8, STAT_CRIT_CHANCE, 5, STAT_CRIT_DMG, 25, STAT_LIFESTEAL, 4
    db STAT_MAX_HEALTH, 2, 0x81, 0, STAT_ARMOR_BONUS, 2, 0x82, 0
    db STAT_MAX_STAMINA, 15, STAT_STAMINA_REGEN, 15, STAT_PARRY_WINDOW, 2, STAT_DODGE_COST, 15
    ; Mage
    db STAT_SPELL_DMG, 8, STAT_CRIT_CHANCE, 4, STAT_CRIT_DMG, 25, STAT_COOLDOWN_RED, 8
    db STAT_MAX_MANA, 20, 0x81, 0, STAT_MANA_REGEN, 2, 0x82, 0
    db STAT_MAX_HEALTH, 2, STAT_ARMOR_BONUS, 2, STAT_MOVE_SPEED, 5, STAT_LIFESTEAL, 3
    ; Archer
    db STAT_RANGED_DMG, 8, STAT_CRIT_CHANCE, 5, STAT_CRIT_DMG, 25, STAT_ARROW_SAVE, 15
    db STAT_MOVE_SPEED, 4, 0x81, 0, STAT_MAX_STAMINA, 15, 0x82, 0
    db STAT_MAX_HEALTH, 2, STAT_DODGE_COST, 15, STAT_STAMINA_REGEN, 15, STAT_COOLDOWN_RED, 8
    ; Rogue
    db STAT_BACKSTAB, 25, STAT_CRIT_CHANCE, 5, STAT_CRIT_DMG, 25, STAT_MELEE_DMG, 8
    db STAT_MOVE_SPEED, 5, 0x81, 0, STAT_DODGE_COST, 15, 0x82, 0
    db STAT_MAX_STAMINA, 15, STAT_STAMINA_REGEN, 15, STAT_LIFESTEAL, 4, STAT_COOLDOWN_RED, 8
; the plan's abilities: resource, cost, cooldown in seconds (slot 0..2 of each class)
exp_abil:
    db RES_STAMINA, 30, 6,  RES_STAMINA, 40, 20, RES_STAMINA, 60, 30   ; Warrior
    db RES_MANA, 25, 3,     RES_MANA, 20, 5,     RES_MANA, 70, 40      ; Mage
    db RES_STAMINA, 30, 6,  RES_STAMINA, 35, 10, RES_STAMINA, 60, 30   ; Archer
    db RES_STAMINA, 25, 8,  RES_STAMINA, 40, 20, RES_STAMINA, 60, 35   ; Rogue

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

; cleanup(): reset_all, and nothing left in the header's RPG record
cleanup:
    push    rbp
    mov     rbp, rsp
    call    reset_all
    lea     rdi, [HDR]
    mov     ecx, RPGSAVE_size
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
    ; the bar is 20 + 10 * level, none at the cap
    CALL1   rpg_xp_need, 1, 30
    CALL1   rpg_xp_need, 2, 40
    CALL1   rpg_xp_need, 29, 310
    CALL1   rpg_xp_need, 30, 0
    ; Warrior: chosen once, with the kit
    mov     dword [combat_stamina], __float32__(10.0)
    CALL1   rpg_set_class, CLASS_WARRIOR, 1
    CALL0   rpg_class, CLASS_WARRIOR
    CALL0   rpg_level, 1
    CALL0   rpg_points, 1
    HAVE    IRON_SWORD, 1
    HAVE    COOKED_PORKCHOP, 4
    HAVE    IRON_CHESTPLATE, 0              ; it is worn, not carried
    EXPECT_D inv + INVENTORY.armor + 4, IRON_CHESTPLATE | (1 << 8)
    EXPECT_D surv_max_health, 24
    EXPECT_D combat_stamina, __float32__(120.0) ; resources refilled to the Warrior's maximum
    CALL1   rpg_set_class, CLASS_MAGE, 0
    CALL0   rpg_class, CLASS_WARRIOR
    ; 30 XP is the first level: points follow, health and stamina are refilled
    mov     dword [surv + SURVIVAL.health], 3
    mov     dword [combat_stamina], __float32__(10.0)
    mov     edi, 30
    call    rpg_add_xp
    CALL0   rpg_level, 2
    EXPECT_D R_XP, 0
    CALL0   rpg_points, 2
    EXPECT_D surv + SURVIVAL.health, 24
    EXPECT_D combat_stamina, __float32__(120.0)
    ; left-over XP carries over: 40 for level 2, 49 given
    mov     edi, 49
    call    rpg_add_xp
    CALL0   rpg_level, 3
    EXPECT_D R_XP, 9
    CALL0   rpg_points, 3
    ; XP for kills (x3 for an elite) and for ore, at level 5 where no bar is crossed
    mov     byte [R_LEVEL], 5
    mov     r12d, 1
.kills:
    mov     dword [R_XP], 0
    mov     edi, r12d
    xor     esi, esi
    call    rpg_on_mob_killed
    lea     rax, [kill_xp_tab]
    movzx   eax, byte [rax + r12 - 1]
    cmp     [R_XP], eax
    jne     .fail
    mov     dword [R_XP], 0
    mov     edi, r12d
    mov     esi, 1
    call    rpg_on_mob_killed
    lea     rax, [kill_xp_tab]
    movzx   eax, byte [rax + r12 - 1]
    lea     eax, [rax + rax*2]
    cmp     [R_XP], eax
    jne     .fail
    inc     r12d
    cmp     r12d, NUM_MOB_TYPES
    jbe     .kills
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
    ; plenty of XP: level 30, no bar left, nothing more is taken
    mov     edi, 10000
    call    rpg_add_xp
    CALL0   rpg_level, 30
    EXPECT_D R_XP, 0
    CALL0   rpg_points, 30
    mov     edi, 500
    call    rpg_add_xp
    CALL0   rpg_level, 30
    EXPECT_D R_XP, 0
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
    CALL1   rpg_can_spend, 4, 0             ; tier 0 is free
    mov     edi, NUM_NODES
    call    rpg_can_spend
    test    eax, eax
    jz      .fail                           ; no such node
    CALL1   rpg_spend, 0, 1
    CALL1   rpg_spend, 0, 1
    CALL1   rpg_spend, 0, 1
    CALL1   rpg_rank, 0, 3
    CALL0   rpg_points, 0
    CALL1   rpg_stat, STAT_MELEE_DMG, 34    ; 10 + 3 * 8
    CALL1   rpg_can_spend, 0, 1             ; no points: checked before the max rank
    CALL1   rpg_spend, 4, 0                 ; refused: nothing changes
    CALL1   rpg_rank, 4, 0
    mov     byte [R_LEVEL], 4               ; one point, tier 1 reachable, War Cry's parent unranked
    CALL1   rpg_can_spend, 1, 0
    CALL1   rpg_can_spend, 5, 4
    mov     byte [R_LEVEL], 5
    CALL1   rpg_can_spend, 0, 2             ; points left, but Weapon Mastery is maxed
    CALL1   rpg_spend, 1, 1
    CALL0   rpg_points, 1
    ; tier 2 needs level 9
    mov     byte [R_LEVEL], 8
    CALL1   rpg_can_spend, 2, 3
    mov     byte [R_LEVEL], 9
    CALL1   rpg_can_spend, 2, 0
    ; War Cry (node 5): an ability, one rank, unlocks slot 1
    CALL1   rpg_ability_unlocked, 0, 1
    CALL1   rpg_ability_unlocked, 1, 0
    CALL1   rpg_spend, 4, 1                 ; Toughness: +1 heart
    EXPECT_D surv_max_health, 26
    CALL1   rpg_stat, STAT_MAX_HEALTH, 26
    CALL1   rpg_can_spend, 5, 0
    CALL1   rpg_spend, 5, 1
    CALL1   rpg_can_spend, 5, 2
    CALL1   rpg_ability_unlocked, 1, 1
    CALL1   rpg_ability_unlocked, 2, 0
    CALL1   rpg_stat, STAT_MAX_HEALTH, 26   ; an ability adds no stat
    ; Whirlwind (node 7): level 15 and Iron Skin (node 6)
    mov     byte [R_LEVEL], 14
    CALL1   rpg_can_spend, 7, 3
    mov     byte [R_LEVEL], 15
    CALL1   rpg_can_spend, 7, 4
    CALL1   rpg_spend, 6, 1
    CALL1   rpg_stat, STAT_ARMOR_BONUS, 2
    CALL1   rpg_can_spend, 7, 0
    CALL1   rpg_spend, 7, 1
    CALL1   rpg_ability_unlocked, 2, 1
    CALL1   rpg_ability_unlocked, 3, 0
    ; points = level - ranks: 3 + 1 + 1 + 1 + 1 + 1 = 8 spent of 15
    CALL0   rpg_points, 7
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
    ; Rogue: Backstab 100, +25 per rank of node 0
    mov     edi, CLASS_ROGUE
    mov     esi, 5
    call    use_class
    CALL1   rpg_stat, STAT_BACKSTAB, 100
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 10
    CALL1   rpg_stat, STAT_MAX_STAMINA, 110
    CALL1   rpg_stat, STAT_STAMINA_REGEN, 10
    mov     byte [R_RANKS + 0], 2
    call    rpg_recompute
    CALL1   rpg_stat, STAT_BACKSTAB, 150
    CALL1   rpg_stat, STAT_MOVE_SPEED, 5
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 10
    EXPECT_D surv_max_health, 20
    ; the caps, reached with absurd ranks: crit 60, speed 40, dodge cost 60, cooldown 40
    mov     byte [R_RANKS + 1], 100
    mov     byte [R_RANKS + 4], 100
    mov     byte [R_RANKS + 6], 100
    mov     byte [R_RANKS + 11], 100
    call    rpg_recompute
    CALL1   rpg_stat, STAT_CRIT_CHANCE, 60
    CALL1   rpg_stat, STAT_MOVE_SPEED, 40
    CALL1   rpg_stat, STAT_DODGE_COST, 60
    CALL1   rpg_stat, STAT_COOLDOWN_RED, 40
    ; Mage: 100 mana, node 4 (Deep Mind) adds 20 per rank
    mov     edi, CLASS_MAGE
    mov     esi, 5
    call    use_class
    CALL1   rpg_stat, STAT_MAX_MANA, 100
    CALL1   rpg_stat, STAT_MANA_REGEN, 4
    CALL1   rpg_stat, STAT_SPELL_DMG, 10
    CALL1   rpg_stat, STAT_MAX_STAMINA, 80
    EXPECT_D surv_max_health, 18
    mov     byte [R_RANKS + 4], 3
    call    rpg_recompute
    CALL1   rpg_stat, STAT_MAX_MANA, 160
    mov     byte [R_RANKS + 5], 1           ; Blink: no stat of its own
    call    rpg_recompute
    CALL1   rpg_stat, STAT_MAX_MANA, 160
    CALL1   rpg_stat, STAT_MANA_REGEN, 4
    ; mana and stamina never stay above their maxima, but are not raised
    mov     dword [combat_mana], __float32__(500.0)
    mov     dword [combat_stamina], __float32__(500.0)
    call    rpg_recompute
    EXPECT_D combat_mana, __float32__(160.0)
    EXPECT_D combat_stamina, __float32__(80.0)
    mov     dword [combat_mana], __float32__(50.0)
    call    rpg_recompute
    EXPECT_D combat_mana, __float32__(50.0)
    ; Warrior: 24 health (published), clamped when it is higher; Toughness +2 per rank
    mov     edi, CLASS_WARRIOR
    mov     esi, 5
    call    use_class
    CALL1   rpg_stat, STAT_MELEE_DMG, 10
    CALL1   rpg_stat, STAT_MAX_STAMINA, 120
    EXPECT_D surv_max_health, 24
    mov     dword [surv + SURVIVAL.health], 30
    call    rpg_recompute
    EXPECT_D surv + SURVIVAL.health, 24
    mov     byte [R_RANKS + 4], 2
    call    rpg_recompute
    EXPECT_D surv_max_health, 28
    EXPECT_D surv + SURVIVAL.health, 24
    ; Archer: Quiver saves arrows, capped at 60
    mov     edi, CLASS_ARCHER
    mov     esi, 5
    call    use_class
    CALL1   rpg_stat, STAT_RANGED_DMG, 15
    CALL1   rpg_stat, STAT_ARROW_SAVE, 10
    mov     byte [R_RANKS + 3], 3
    call    rpg_recompute
    CALL1   rpg_stat, STAT_ARROW_SAVE, 55
    mov     byte [R_RANKS + 3], 100
    call    rpg_recompute
    CALL1   rpg_stat, STAT_ARROW_SAVE, 60
    ; ability slots: slot 0 needs a class; 1 and 2 need their node
    mov     edi, CLASS_NONE
    mov     esi, 5
    call    use_class
    CALL1   rpg_ability_unlocked, 0, 0
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
    mov     esi, 4
    call    rpg_node_info
    mov     r14, rax
    mov     rax, [r14 + NODEINFO.name]
    STR_IS  s_deepmind
    mov     rax, [r14 + NODEINFO.desc]
    STR_IS  s_plus20
    cmp     byte [r14 + NODEINFO.kind], 0
    jne     .fail
    cmp     byte [r14 + NODEINFO.stat], STAT_MAX_MANA
    jne     .fail
    cmp     byte [r14 + NODEINFO.max], 3
    jne     .fail
    cmp     dword [r14 + NODEINFO.value], 20
    jne     .fail
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
    ; every class: ability nodes are 5 and 7 and share the ability's texts; every other node
    ; is a stat node (max rank 3, a real stat, a value)
    mov     r12d, 1
.cls:
    xor     r13d, r13d
.node:
    mov     edi, r12d
    mov     esi, r13d
    call    rpg_node_info
    mov     r14, rax
    ; the plan's skill table: stat (0x80 | slot for an ability) and value of every node
    lea     eax, [r12 - 1]
    imul    eax, eax, NUM_NODES
    add     eax, r13d
    lea     rcx, [exp_nodes]
    lea     rcx, [rcx + rax*2]
    movzx   edx, byte [rcx]
    movzx   eax, byte [rcx + 1]
    test    dl, 0x80
    jnz     .exp_ability
    cmp     byte [r14 + NODEINFO.kind], 0
    jne     .fail
    cmp     [r14 + NODEINFO.stat], dl
    jne     .fail
    cmp     [r14 + NODEINFO.value], eax
    jne     .fail
    jmp     .exp_done
.exp_ability:
    and     edx, 0x7F
    cmp     byte [r14 + NODEINFO.kind], 1
    jne     .fail
    cmp     [r14 + NODEINFO.stat], dl
    jne     .fail
    cmp     dword [r14 + NODEINFO.value], 0
    jne     .fail
.exp_done:
    mov     rax, [r14 + NODEINFO.name]
    cmp     byte [rax], 0
    je      .fail                           ; a skill without a name
    mov     rax, [r14 + NODEINFO.desc]
    cmp     byte [rax], 0
    je      .fail
    cmp     r13d, 5
    je      .ability
    cmp     r13d, 7
    je      .ability
    cmp     byte [r14 + NODEINFO.kind], 0
    jne     .fail
    cmp     byte [r14 + NODEINFO.max], 3
    jne     .fail
    cmp     byte [r14 + NODEINFO.stat], NUM_STATS
    jae     .fail
    cmp     dword [r14 + NODEINFO.value], 0
    je      .fail
    jmp     .next_node
.ability:
    cmp     byte [r14 + NODEINFO.kind], 1
    jne     .fail
    cmp     byte [r14 + NODEINFO.max], 1
    jne     .fail
    mov     esi, 1                          ; node 5 is slot 1, node 7 slot 2
    cmp     r13d, 5
    je      .slot
    mov     esi, 2
.slot:
    movzx   eax, byte [r14 + NODEINFO.stat]
    cmp     eax, esi
    jne     .fail
    mov     edi, r12d
    call    rpg_ability_info
    mov     rcx, [rax + ABILINFO.name]
    cmp     rcx, [r14 + NODEINFO.name]
    jne     .fail
    mov     rcx, [rax + ABILINFO.desc]
    cmp     rcx, [r14 + NODEINFO.desc]
    jne     .fail
    cmp     dword [rax + ABILINFO.cost], 0
    je      .fail
    cmp     dword [rax + ABILINFO.cooldown], 0
    je      .fail
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
    lea     eax, [rax + rax*2]
    add     eax, r13d
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
    cmp     r13d, 3
    jb      .aslot
    inc     r12d
    cmp     r12d, NUM_CLASSES
    jbe     .acls
    TEST_END

; ---- save and load -----------------------------------------------------------------

; hdr_set(edi class, esi level): the header's RPG record is all zero but class and level
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
    mov     [HDR + RPGSAVE.class], bl
    mov     [HDR + RPGSAVE.level], r12b
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
    mov     byte [R_RANKS + 0], 2
    mov     byte [R_RANKS + 4], 1
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
    EXPECT_B HDR + RPGSAVE.ranks + 4, 1
    EXPECT_B HDR + RPGSAVE.cleared, 5
    call    rpg_reset
    CALL0   rpg_class, CLASS_NONE
    call    hdr_load
    CALL0   rpg_class, CLASS_ARCHER
    CALL0   rpg_level, 7
    EXPECT_D R_XP, 55
    EXPECT_B R_RANKS + 0, 2
    EXPECT_B R_RANKS + 4, 1
    EXPECT_B R_RANKS + 1, 0
    EXPECT_B R_QUEST, 3
    EXPECT_B R_QSTATE, 1
    cmp     word [R_QPROG], 2
    jne     .fail
    EXPECT_B R_CLEARED, 5
    EXPECT_B R_FLAGS, 1
    CALL1   rpg_stat, STAT_RANGED_DMG, 31   ; stats are recomputed: 15 + 2 * 8
    CALL1   rpg_stat, STAT_MOVE_SPEED, 9    ; Fleet Foot rank 1: 5 + 4
    ; ranks of 3 everywhere at level 5: more than the level, and past an ability's max
    mov     edi, CLASS_ARCHER
    mov     esi, 5
    call    hdr_set
    lea     rdi, [HDR + RPGSAVE.ranks]
    mov     ecx, NUM_NODES
    mov     al, 3
    rep     stosb
    call    hdr_load
    CALL0   rpg_class, CLASS_ARCHER
    CALL0   rpg_level, 5
    cmp     qword [R_RANKS], 0
    jne     .fail
    cmp     dword [R_RANKS + 8], 0
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
    ; a level outside 1..30 rebuilds the character
    mov     edi, CLASS_ROGUE
    xor     esi, esi
    call    hdr_set
    call    hdr_load
    CALL0   rpg_class, CLASS_NONE
    CALL0   rpg_level, 1
    mov     edi, CLASS_ROGUE
    mov     esi, 31
    call    hdr_set
    call    hdr_load
    CALL0   rpg_class, CLASS_NONE
    ; a rank past its node's maximum (3, or 1 for an ability) zeroes every rank
    mov     edi, CLASS_ROGUE
    mov     esi, 10
    call    hdr_set
    mov     byte [HDR + RPGSAVE.ranks + 0], 4
    call    hdr_load
    CALL0   rpg_class, CLASS_ROGUE
    EXPECT_B R_RANKS + 0, 0
    mov     edi, CLASS_ROGUE
    mov     esi, 10
    call    hdr_set
    mov     byte [HDR + RPGSAVE.ranks + 5], 2
    call    hdr_load
    EXPECT_B R_RANKS + 5, 0
    ; ranks adding up to the level are fine, one more is not
    mov     edi, CLASS_ROGUE
    mov     esi, 9
    call    hdr_set
    mov     byte [HDR + RPGSAVE.ranks + 0], 3
    mov     byte [HDR + RPGSAVE.ranks + 1], 3
    mov     byte [HDR + RPGSAVE.ranks + 4], 3
    call    hdr_load
    EXPECT_B R_RANKS + 4, 3
    mov     edi, CLASS_ROGUE
    mov     esi, 8
    call    hdr_set
    mov     byte [HDR + RPGSAVE.ranks + 0], 3
    mov     byte [HDR + RPGSAVE.ranks + 1], 3
    mov     byte [HDR + RPGSAVE.ranks + 4], 3
    call    hdr_load
    EXPECT_B R_RANKS + 4, 0
    EXPECT_B R_RANKS + 0, 0
    ; XP stays below the bar (50 at level 3); none at level 30
    mov     edi, CLASS_MAGE
    mov     esi, 3
    call    hdr_set
    mov     dword [HDR + RPGSAVE.xp], 49
    call    hdr_load
    EXPECT_D R_XP, 49
    mov     dword [HDR + RPGSAVE.xp], 50
    call    hdr_load
    EXPECT_D R_XP, 49
    mov     dword [HDR + RPGSAVE.xp], 0xFFFFFFFF
    call    hdr_load
    EXPECT_D R_XP, 49
    mov     edi, CLASS_MAGE
    mov     esi, 30
    call    hdr_set
    mov     dword [HDR + RPGSAVE.xp], 5
    call    hdr_load
    CALL0   rpg_level, 30
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
    mov     esi, 5                          ; the bar is 70, rewards stay readable
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
    CALL0   rpg_level, 6                    ; 40 + 50 XP: one level of 70 and 20 over
    EXPECT_D R_XP, 20
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
    CALL0   rpg_level, 7
    EXPECT_D R_XP, 0
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
    CALL0   rpg_level, 7
    EXPECT_D R_XP, 70
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
    CALL0   rpg_level, 9
    EXPECT_D R_XP, 30
    HAVE    GOLD_COIN, 54
    HAVE    HEALTH_POTION, 3
    ; quest 5: 3 diamonds
    CALL0   quests_accept, 1
    ADD     DIAMOND, 4
    CALL0   quests_complete, 1
    HAVE    DIAMOND, 1
    EXPECT_B R_QUEST, 6
    CALL0   rpg_level, 10
    EXPECT_D R_XP, 40
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
    CALL0   rpg_level, 11
    EXPECT_D R_XP, 120
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
    CALL0   rpg_level, 15
    EXPECT_D R_XP, 40
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
    TEST_END
