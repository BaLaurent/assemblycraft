; rpg.asm - the character: class, level, XP, skill ranks and the stats derived from them.
; rpg_state is the live progression stored in WORLDHDR.rpg; rpg_stats is rebuilt from it by
; rpg_recompute (class base + sum of rank * node value, then caps). Skill points are never
; stored: points = level - sum of ranks. This file also owns the static class / skill node /
; ability description tables the screens read (record layouts below).
%include "common.inc"
default rel

global rpg_state, rpg_stats
global rpg_reset, rpg_set_class, rpg_class, rpg_level, rpg_points, rpg_xp_need, rpg_add_xp
global rpg_rank, rpg_can_spend, rpg_spend, rpg_stat, rpg_recompute, rpg_ability_unlocked
global rpg_class_info, rpg_node_info, rpg_ability_info, rpg_branch_name
global rpg_on_mob_killed, rpg_on_block_mined, rpg_on_death, rpg_load, rpg_save, rpg_give_item

extern surv, surv_max_health, combat_mana, combat_stamina, combat_refill
extern inv, inv_add, drops_spawn, player
extern audio_play, hud_banner, fx_burst, quests_on_kill
extern str_append, i32_to_str

; strings of the tables below live in their own read-only section so the records stay contiguous
section .rodata.str progbits alloc noexec nowrite align=1

section .rodata
align 4
f_vol_click: dd 0.6
f_vol_full:  dd 1.0
f_chest:     dd 1.2                     ; chest height above the feet (effect origin)
f_burst:     dd 3.0                     ; level-up burst speed
f_drop_y:    dd 0.5                     ; overflow drops appear this far above the feet
s_level:     db "Level ", 0
s_empty:     db 0

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

tier_level: db 1, 4, 9, 15              ; level needed by a node of tier 0..3

; XP for a kill the player earned, by mob type 0..9 (merchant, elder and boss give none here)
kill_xp:    db 0, 10, 2, 15, 12, 10, 2, 0, 0, 0
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
abil_tab:                               ; (class - 1) * 3 + slot
    ABIL charge,    "Charge",          "Rush forward, stunning foes",       RES_STAMINA, 30, 6
    ABIL warcry,    "War Cry",         "Stun foes, empower yourself",       RES_STAMINA, 40, 20
    ABIL whirl,     "Whirlwind",       "Spin and slash all around",         RES_STAMINA, 60, 30
    ABIL fireball,  "Fireball",        "Explosive fireball",                RES_MANA,    25, 3
    ABIL blink,     "Blink",           "Teleport a short way ahead",        RES_MANA,    20, 5
    ABIL meteor,    "Meteor Storm",    "Call down a meteor rain",           RES_MANA,    70, 40
    ABIL volley,    "Volley",          "Fire a fan of five arrows",         RES_STAMINA, 30, 6
    ABIL explarrow, "Explosive Arrow", "Arrow that explodes on impact",     RES_STAMINA, 35, 10
    ABIL arrowrain, "Arrow Rain",      "Rain arrows on the target",         RES_STAMINA, 60, 30
    ABIL shadowstp, "Shadowstep",      "Blink behind a foe, next hit crits", RES_STAMINA, 25, 8
    ABIL smoke,     "Smoke Bomb",      "Vanish, enemies lose track",        RES_STAMINA, 40, 20
    ABIL bladedance, "Blade Dance",    "Faster strikes that always crit",   RES_STAMINA, 60, 35

; NODEINFO records: a passive stat node (max rank 3) with a literal text ...
%macro SNODE 4                          ; name, stat, value, desc
section .rodata.str
%%n: db %1, 0
%%d: db %4, 0
section .rodata
    dq %%n, %%d
    db 0, %2, 3, 0
    dd %3
%endmacro
; ... one whose text is sign + value + suffix, so the text always follows the value
%macro PNODE 5                          ; name, stat, value, sign, suffix
%strcat %%txt, %4, %str(%3), %5
    SNODE %1, %2, %3, %%txt
%endmacro
; ... and an ability node (max rank 1): name and text come from the ability record
%macro ANODE 2                          ; ability label, ability slot
    dq an_%1, ad_%1
    db 1, %2, 1, 0
    dd 0
%endmacro

align 8
node_tab:                               ; (class - 1) * 12 + node, node = branch * 4 + tier
    ; Warrior
    PNODE "Weapon Mastery", STAT_MELEE_DMG,     8, "+", "% melee damage"
    PNODE "Precision",      STAT_CRIT_CHANCE,   5, "+", "% critical chance"
    PNODE "Brutality",      STAT_CRIT_DMG,     25, "+", "% critical damage"
    PNODE "Bloodthirst",    STAT_LIFESTEAL,     4, "+", "% of damage healed"
    SNODE "Toughness",      STAT_MAX_HEALTH,    2, "+1 heart"
    ANODE warcry, 1
    PNODE "Iron Skin",      STAT_ARMOR_BONUS,   2, "+", " armor"
    ANODE whirl, 2
    PNODE "Stamina",        STAT_MAX_STAMINA,  15, "+", " stamina"
    PNODE "Second Wind",    STAT_STAMINA_REGEN, 15, "+", "% stamina regen"
    PNODE "Riposte",        STAT_PARRY_WINDOW,  2, "+", " steps parry window"
    PNODE "Light Feet",     STAT_DODGE_COST,   15, "-", "% dodge cost"
    ; Mage
    PNODE "Pyromancy",      STAT_SPELL_DMG,     8, "+", "% spell damage"
    PNODE "Focus",          STAT_CRIT_CHANCE,   4, "+", "% critical chance"
    PNODE "Combustion",     STAT_CRIT_DMG,     25, "+", "% critical damage"
    PNODE "Haste",          STAT_COOLDOWN_RED,  8, "-", "% cooldowns"
    PNODE "Deep Mind",      STAT_MAX_MANA,     20, "+", " mana"
    ANODE blink, 1
    PNODE "Flow",           STAT_MANA_REGEN,    2, "+", " mana per second"
    ANODE meteor, 2
    SNODE "Vitality",       STAT_MAX_HEALTH,    2, "+1 heart"
    PNODE "Mage Armor",     STAT_ARMOR_BONUS,   2, "+", " armor"
    PNODE "Swiftness",      STAT_MOVE_SPEED,    5, "+", "% move speed"
    PNODE "Siphon",         STAT_LIFESTEAL,     3, "+", "% of damage healed"
    ; Archer
    PNODE "Steady Aim",     STAT_RANGED_DMG,    8, "+", "% bow damage"
    PNODE "Eagle Eye",      STAT_CRIT_CHANCE,   5, "+", "% critical chance"
    PNODE "Deadly Shot",    STAT_CRIT_DMG,     25, "+", "% critical damage"
    PNODE "Quiver",         STAT_ARROW_SAVE,   15, "+", "% arrows saved"
    PNODE "Fleet Foot",     STAT_MOVE_SPEED,    4, "+", "% move speed"
    ANODE explarrow, 1
    PNODE "Endurance",      STAT_MAX_STAMINA,  15, "+", " stamina"
    ANODE arrowrain, 2
    SNODE "Vitality",       STAT_MAX_HEALTH,    2, "+1 heart"
    PNODE "Evasion",        STAT_DODGE_COST,   15, "-", "% dodge cost"
    PNODE "Second Wind",    STAT_STAMINA_REGEN, 15, "+", "% stamina regen"
    PNODE "Readiness",      STAT_COOLDOWN_RED,  8, "-", "% cooldowns"
    ; Rogue
    PNODE "Backstab",       STAT_BACKSTAB,     25, "+", "% backstab damage"
    PNODE "Precision",      STAT_CRIT_CHANCE,   5, "+", "% critical chance"
    PNODE "Cruelty",        STAT_CRIT_DMG,     25, "+", "% critical damage"
    PNODE "Blade Mastery",  STAT_MELEE_DMG,     8, "+", "% melee damage"
    PNODE "Fleet Foot",     STAT_MOVE_SPEED,    5, "+", "% move speed"
    ANODE smoke, 1
    PNODE "Evasion",        STAT_DODGE_COST,   15, "-", "% dodge cost"
    ANODE bladedance, 2
    PNODE "Endurance",      STAT_MAX_STAMINA,  15, "+", " stamina"
    PNODE "Second Wind",    STAT_STAMINA_REGEN, 15, "+", "% stamina regen"
    PNODE "Leech",          STAT_LIFESTEAL,     4, "+", "% of damage healed"
    PNODE "Readiness",      STAT_COOLDOWN_RED,  8, "-", "% cooldowns"

; what the info getters return for no class / an index out of range
node_blank: dq s_empty, s_empty
            db 0, 0, 0, 0
            dd 0
align 8
abil_blank: dq s_empty, s_empty
            dd 0, 0, 0, 0

section .bss
alignb 4
rpg_state:  resb RPGSAVE_size
rpg_stats:  resd NUM_STATS
banner:     resb 16                     ; "Level 30!"

section .text

; ---- plain getters ----------------------------------------------------------

; rpg_class() -> eax 0 (none) .. 4
rpg_class:
    movzx   eax, byte [rpg_state + RPGSAVE.class]
    ret

; rpg_level() -> eax 1..30
rpg_level:
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    ret

; rpg_points() -> eax unspent skill points = level - sum of ranks (never negative)
rpg_points:
    movzx   eax, byte [rpg_state + RPGSAVE.level]
    lea     rsi, [rpg_state + RPGSAVE.ranks_v4]
    xor     ecx, ecx
.l:
    movzx   edx, byte [rsi + rcx]
    sub     eax, edx
    inc     ecx
    cmp     ecx, V4_NODES
    jb      .l
    xor     edx, edx
    test    eax, eax
    cmovs   eax, edx
    ret

; rpg_xp_need(edi level) -> eax XP to leave that level: 20 + 10 * level for 1..29, else 0
rpg_xp_need:
    lea     eax, [rdi - 1]
    cmp     eax, V4_MAX_LEVEL - 1
    jae     .none
    imul    eax, edi, 10
    add     eax, 20
    ret
.none:
    xor     eax, eax
    ret

; rpg_rank(edi node) -> eax rank of node 0..11 (0 for anything else)
rpg_rank:
    xor     eax, eax
    cmp     edi, V4_NODES
    jae     .ret
    mov     ecx, edi
    lea     rdx, [rpg_state + RPGSAVE.ranks_v4]
    movzx   eax, byte [rdx + rcx]
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

; rpg_ability_unlocked(edi slot) -> eax 1 when the ability of that slot can be cast: slot 0
; needs a class, slot 1 rank >= 1 in node 5, slot 2 rank >= 1 in node 7
rpg_ability_unlocked:
    xor     eax, eax
    cmp     edi, 2
    ja      .ret
    je      .slot2
    test    edi, edi
    jz      .slot0
    cmp     byte [rpg_state + RPGSAVE.ranks_v4 + 5], 0
    seta    al
    ret
.slot2:
    cmp     byte [rpg_state + RPGSAVE.ranks_v4 + 7], 0
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

; rpg_node_info(edi class, esi node) -> rax NODEINFO* of node 0..11 of class 1..4; anything
; else -> an empty record (empty texts, kind 0, stat 0, max 0, value 0)
rpg_node_info:
    lea     eax, [rdi - 1]
    cmp     eax, NUM_CLASSES
    jae     .blank
    cmp     esi, V4_NODES
    jae     .blank
    imul    eax, eax, V4_NODES
    add     eax, esi
    imul    eax, eax, NODEINFO_size
    lea     rcx, [node_tab]
    add     rax, rcx
    ret
.blank:
    lea     rax, [node_blank]
    ret

; rpg_ability_info(edi class, esi slot) -> rax ABILINFO* of ability 0..2 of class 1..4;
; anything else -> an empty record
rpg_ability_info:
    lea     eax, [rdi - 1]
    cmp     eax, NUM_CLASSES
    jae     .blank
    cmp     esi, 3
    jae     .blank
    lea     eax, [rax + rax*2]
    add     eax, esi
    imul    eax, eax, ABILINFO_size
    lea     rcx, [abil_tab]
    add     rax, rcx
    ret
.blank:
    lea     rax, [abil_blank]
    ret

; ---- stats -------------------------------------------------------------------

; clamp the stat %1 to at most %2
%macro CAP 2
    mov     eax, [rpg_stats + (%1)*4]
    mov     ecx, %2
    cmp     eax, ecx
    cmovg   eax, ecx
    mov     [rpg_stats + (%1)*4], eax
%endmacro

; rpg_recompute(): rpg_stats = class base + sum of rank * value over the stat nodes, then the
; caps. Publishes surv_max_health, keeps health, mana and stamina at or below their maxima.
rpg_recompute:
    movzx   edx, byte [rpg_state + RPGSAVE.class]
    cmp     edx, NUM_CLASSES
    jbe     .base
    xor     edx, edx                    ; a corrupt class counts as none
.base:
    imul    eax, edx, NUM_STATS * 4
    lea     rsi, [base_stats]
    add     rsi, rax
    lea     rdi, [rpg_stats]
    mov     ecx, NUM_STATS
    rep     movsd
    test    edx, edx
    jz      .caps
    lea     r8, [rpg_state + RPGSAVE.ranks_v4]
    lea     r9, [node_tab]
    lea     eax, [rdx - 1]
    imul    eax, eax, V4_NODES * NODEINFO_size
    add     r9, rax                     ; the class's first node
    lea     r10, [rpg_stats]
    xor     ecx, ecx
.node:
    movzx   eax, byte [r8 + rcx]
    test    eax, eax
    jz      .next
    cmp     byte [r9 + NODEINFO.kind], 0
    jne     .next                       ; an ability node adds no stat
    movzx   edx, byte [r9 + NODEINFO.stat]
    imul    eax, [r9 + NODEINFO.value]
    add     [r10 + rdx*4], eax
.next:
    add     r9, NODEINFO_size
    inc     ecx
    cmp     ecx, V4_NODES
    jb      .node
.caps:
    CAP     STAT_CRIT_CHANCE, 60
    CAP     STAT_COOLDOWN_RED, 40
    CAP     STAT_DODGE_COST, 60
    CAP     STAT_ARROW_SAVE, 60
    CAP     STAT_MOVE_SPEED, 40
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
    ret

; ---- lifecycle ---------------------------------------------------------------

; rpg_reset(): a character without a class: level 1, nothing else, stats recomputed
rpg_reset:
    push    rbp
    mov     rbp, rsp
    lea     rdi, [rpg_state]
    mov     ecx, RPGSAVE_size
    xor     eax, eax
    rep     stosb
    mov     byte [rpg_state + RPGSAVE.level], 1
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
; class 1..4): level 1, no XP, no ranks, the starting kit, stats recomputed, resources refilled.
; 0 otherwise.
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
    lea     rdi, [rpg_state + RPGSAVE.ranks_v4]
    mov     ecx, V4_NODES
    xor     eax, eax
    rep     stosb
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

; rpg_add_xp(edi amount): XP into the current level; every full bar is a level (up to 30,
; where the XP stays 0). Does nothing without a class or at level 30. Gaining one or more
; levels refills health, mana and stamina, plays the level-up sound and shows one banner and
; one burst for the final level.
rpg_add_xp:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    cmp     byte [rpg_state + RPGSAVE.class], 0
    je      .ret
    cmp     byte [rpg_state + RPGSAVE.level], V4_MAX_LEVEL
    jae     .ret
    mov     ebx, [rpg_state + RPGSAVE.xp]
    add     ebx, edi
    jnc     .sum
    mov     ebx, -1                     ; saturate instead of wrapping
.sum:
    xor     r12d, r12d                  ; levels gained
.loop:
    movzx   edi, byte [rpg_state + RPGSAVE.level]
    call    rpg_xp_need
    test    eax, eax
    jz      .capped                     ; level 30: the bar is gone
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

; ---- skill points ----------------------------------------------------------------

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
    cmp     ebx, V4_NODES
    jae     .ret
    movzx   edi, byte [rpg_state + RPGSAVE.class]
    mov     esi, ebx
    call    rpg_node_info
    movzx   ecx, byte [rax + NODEINFO.max]
    lea     rdx, [rpg_state + RPGSAVE.ranks_v4]
    movzx   edx, byte [rdx + rbx]
    mov     eax, 2
    cmp     edx, ecx
    jae     .ret
    mov     ecx, ebx
    and     ecx, 3                      ; tier
    lea     rdx, [tier_level]
    movzx   edx, byte [rdx + rcx]
    mov     eax, 3
    cmp     byte [rpg_state + RPGSAVE.level], dl
    jb      .ret
    mov     eax, 4
    test    ecx, ecx
    jz      .ok                         ; tier 0 has no prerequisite
    lea     rdx, [rpg_state + RPGSAVE.ranks_v4]
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
    lea     rdx, [rpg_state + RPGSAVE.ranks_v4]
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

; ---- events ------------------------------------------------------------------------

; rpg_on_mob_killed(edi type, esi elite): XP for a kill the player earned (x3 for an elite),
; then the quests
rpg_on_mob_killed:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, esi
    xor     eax, eax
    cmp     ebx, NUM_MOB_TYPES
    ja      .xp
    lea     rcx, [kill_xp]
    movzx   eax, byte [rcx + rbx]
    test    r12d, r12d
    jz      .xp
    lea     eax, [rax + rax*2]
.xp:
    test    eax, eax
    jz      .quest
    mov     edi, eax
    call    rpg_add_xp
.quest:
    mov     edi, ebx
    mov     esi, r12d
    call    quests_on_kill
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

; rpg_on_death(): the bar is lost; level and ranks stay
rpg_on_death:
    mov     dword [rpg_state + RPGSAVE.xp], 0
    ret

; ---- save file -------------------------------------------------------------------------

; rpg_save(rdi header): rpg_state -> WORLDHDR.rpg
rpg_save:
    lea     rsi, [rpg_state]
    lea     rdi, [rdi + WORLDHDR.rpg]
    mov     ecx, RPGSAVE_size
    rep     movsb
    ret

; rpg_load(rdi header): WORLDHDR.rpg -> rpg_state, made consistent, then the stats. A class
; outside 1..4 (zeros in an old save are "no class") or a level outside 1..30 rebuilds the
; character from scratch; ranks above a node's maximum or adding up to more than the level are
; dropped; xp is kept below the bar; quest, quest_state, cleared and flags are masked to
; their ranges.
rpg_load:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     rsi, [rdi + WORLDHDR.rpg]
    lea     rdi, [rpg_state]
    mov     ecx, RPGSAVE_size
    rep     movsb
    movzx   eax, byte [rpg_state + RPGSAVE.class]
    dec     eax
    cmp     eax, NUM_CLASSES
    jae     .reset
    movzx   ebx, byte [rpg_state + RPGSAVE.level]
    lea     eax, [rbx - 1]
    cmp     eax, V4_MAX_LEVEL
    jae     .reset
    lea     r8, [rpg_state + RPGSAVE.ranks_v4]
    lea     r9, [node_tab]
    movzx   eax, byte [rpg_state + RPGSAVE.class]
    dec     eax
    imul    eax, eax, V4_NODES * NODEINFO_size
    add     r9, rax                     ; the class's first node
    xor     ecx, ecx                    ; node
    xor     edx, edx                    ; sum of ranks
.rank:
    movzx   eax, byte [r8 + rcx]
    cmp     al, [r9 + NODEINFO.max]
    ja      .bad_ranks
    add     edx, eax
    add     r9, NODEINFO_size
    inc     ecx
    cmp     ecx, V4_NODES
    jb      .rank
    cmp     edx, ebx
    jbe     .ranks_ok
.bad_ranks:
    lea     rdi, [rpg_state + RPGSAVE.ranks_v4]
    mov     ecx, V4_NODES
    xor     eax, eax
    rep     stosb
.ranks_ok:
    mov     edi, ebx
    call    rpg_xp_need
    test    eax, eax
    jnz     .xp
    mov     dword [rpg_state + RPGSAVE.xp], 0   ; level 30 has no bar
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
    and     byte [rpg_state + RPGSAVE.cleared], 0x3F
    and     byte [rpg_state + RPGSAVE.flags], 1
    call    rpg_recompute
    jmp     .ret
.reset:
    call    rpg_reset
.ret:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
