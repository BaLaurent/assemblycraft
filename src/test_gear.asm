; test_gear.asm - rolled gear: affix decode, names and tooltips; equipped stats and legendary
; powers; loot rolls, mob drops and chests; jewelry slots and the no-wear rule.
%include "common.inc"
default rel

global test_gear_decode_deterministic, test_gear_stats_and_powers
global test_gear_drops_and_chests, test_gear_jewelry_and_no_wear

extern rpg_spend, rpg_ext, rpg_recompute, rpg_archetype, rpg_reset
extern affix_tab, gear_affixes, gear_rarity, gear_rarity_color, gear_name
extern gear_add_stats, gear_powers, gear_has_power, gear_make, gear_roll
extern gear_tier_for_level, gear_pick_base, gear_drop_from_mob, gear_fill_chest
extern item_tooltip, gear_equipped_for
extern item_gear, item_durability
extern inv, inv_sel, inv_clear, inv_click, inv_damage_held, inv_container, craft_size, game_mode
extern rng_seed, world_clear, drops, drops_clear, mobs, mobs_clear, mob_spawn
extern rpg_stats, rpg_state, rpg_format_stat, str_eq

%define STK(id, n, dmg) ((id) | ((n) << 8) | ((dmg) << 16))
%define DMG(tier, rar, seed) (((rar) << GEAR_RARITY_SHIFT) | ((tier) << GEAR_TIER_SHIFT) | (seed))
%define D_SWORD       DMG(5, RAR_RARE, 77)
%define D_MAGIC_SWORD DMG(3, RAR_MAGIC, 5)
%define D_EPIC_RING   DMG(8, RAR_EPIC, 1000)
%define D_BLADE       DMG(13, RAR_RARE, 1)
%define D_CHESTPLATE  DMG(4, RAR_RARE, 300)
%define D_MAGIC_BOW   DMG(5, RAR_MAGIC, 9)
%define D_CELESTIAL   DMG(2, RAR_RARE, 5)
%define D_HELM        DMG(1, RAR_RARE, 11)
%define D_CHEST2      DMG(2, RAR_RARE, 22)
%define D_LEGS        DMG(3, RAR_RARE, 33)
%define D_BOOTS       DMG(4, RAR_RARE, 44)
%define D_RING1       DMG(5, RAR_MAGIC, 55)
%define D_RING2       DMG(6, RAR_RARE, 66)
%define D_AMULET      DMG(7, RAR_EPIC, 77)
%define CURSOR (inv + INVENTORY.cursor)

%define COL_WHITE RGBA(255, 255, 255, 255)
%define COL_GREY  RGBA(170, 170, 170, 255)
%define COL_AFFIX RGBA(150, 190, 255, 255)
%define COL_POWER RGBA(255, 150, 40, 255)
%define COL_HINT  RGBA(130, 130, 130, 255)
%define COL_RARE  RGBA(255, 230, 90, 255)
%define COL_LEGEND RGBA(255, 150, 40, 255)

section .rodata
align 4
; golden affixes, (stat, value) pairs, from an independent model of the decode
g_rare_sword:  dd 43, 6,  26, 6,  22, 12,  18, 5               ; IRON_SWORD rare tier 5 seed 77
g_magic_sword: dd 14, 2,  18, 6                                 ; IRON_SWORD magic tier 3 seed 5
g_epic_ring:   dd 6, 26,  4, 8,  18, 12,  40, 11,  22, 17      ; RING epic tier 8 seed 1000
g_blade:       dd 13, 1,  36, 14,  26, 14,  14, 1               ; KINGS_BLADE rare tier 13 seed 1
g_chestplate:  dd 27, 10,  35, 7,  10, 1,  28, 16               ; IRON_CHESTPLATE rare tier 4 seed 300

k_x: dd 5.5
k_y: dd 12.0
k_z: dd 5.5

n_iron_sword: db "Iron Sword", 0
n_sharp:      db "Sharp Iron Sword", 0
n_vampiric:   db "Vampiric Iron Sword", 0
n_wise_ring:  db "Wise Ring", 0
n_kings:      db "King's Blade", 0
n_pickaxe:    db "Stone Pickaxe", 0
n_unknown:    db "?", 0
l_rare_sword: db "Rare Weapon - Tier 5", 0
l_legendary:  db "Legendary Weapon - Tier 13", 0
l_common_wpn: db "Common Weapon", 0
l_common_chest: db "Common Chestplate", 0
l_attack7:    db "Attack 7", 0
l_attack11:   db "Attack 11", 0
l_attack9:    db "Attack 9", 0
l_armor6:     db "Armor 6", 0
l_hammer:     db "Hammer: stuns on hit", 0
l_king1:      db "+50% damage to elites and bosses;", 0
l_king2:      db "parries heal 10% health", 0
l_compare:    db "Shift: compare", 0
l_durability: db "Durability 124/131", 0
n_hammer:     db "Iron Warhammer", 0
n_chestplate: db "Iron Chestplate", 0
n_ring:       db "Ring", 0
n_celestial:  db "Celestial Bow", 0
n_archmage:   db "Archmage Staff", 0
l_attack13:   db "Attack 13", 0
l_attack4:    db "Attack 4", 0
l_celes1:     db "No arrows needed, x1.5 damage;", 0
l_celes2:     db "crits shock the target", 0
l_arch1:      db "Every 4th staff bolt is a fireball", 0
l_legend_staff: db "Legendary Staff", 0
l_common_ring: db "Common Ring", 0

t_legendary_by_class: db KINGS_BLADE, KINGS_BLADE, ARCHMAGE_STAFF, CELESTIAL_BOW, SHADOW_FANG

section .bss
alignb 16
t_aff:    resb 80                       ; two GEARAFFIX[5] sets
t_stats:  resd NUM_STATS
t_exp:    resd NUM_STATS                ; expected stats of the aggregate check
t_lines:  resq 12                       ; item_tooltip results
t_cols:   resd 12
jew_mode: resd 1                        ; game_mode to restore after the jewelry test
t_lines2: resq 12                       ; a copy of the first tooltip's pointers
t_text:   resb 64
t_stack:  resd 2
t_cont:   resb 2 * CONTAINER_size
t_rar:    resd 4                        ; roll_many: rolls per rarity
t_cnt:    resd 4                        ; scan_drops results
t_save:   resd 4                        ; saved globals: class, magic find

section .text
; take_path(edi arch 0..4): the character takes that archetype's path (0: none, a fresh character)
; at its current level, with the stats recomputed. Kits are poked given so the spend wears nothing;
; the spend refills mana and stamina. Clobbers the usual caller-saved registers.
take_path:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     ebx, edi
    movzx   r12d, byte [rpg_state + RPGSAVE.level]
    call    rpg_reset
    test    ebx, ebx
    jz      .done
    mov     byte [rpg_state + RPGSAVE.level], 50
    mov     byte [rpg_ext + RPGEXT.kits], 0xFF
    lea     edi, [rbx - 1]
    call    rpg_spend
    mov     byte [rpg_state + RPGSAVE.level], r12b
.done:
    mov     byte [rpg_state + RPGSAVE.level], r12b
    call    rpg_recompute
    add     rsp, 8
    pop     r12
    pop     rbx
    ret


; ---- helpers -----------------------------------------------------------------------------------

; row_of(edi stat) -> rax the affix_tab row of that stat, or 0
row_of:
    lea     rax, [affix_tab]
    xor     ecx, ecx
.l:
    cmp     [rax + AFFIXDEF.stat], dil
    je      .ret
    add     rax, AFFIXDEF_size
    inc     ecx
    cmp     ecx, 44
    jb      .l
    xor     eax, eax
.ret:
    ret

; affixes_ok(rdi GEARAFFIX*, esi count, edx tier, ecx gear kind) -> eax 1 when every affix names
; a distinct stat, belongs to a row whose kinds include the kind and has a value inside
; [lo + tier * tlo, hi + tier * thi]
affixes_ok:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    xor     r15d, r15d
.next:
    cmp     r15d, r12d
    jae     .yes
    mov     edi, [rbx + r15*8 + GEARAFFIX.stat]
    call    row_of
    test    rax, rax
    jz      .no
    movzx   ecx, word [rax + AFFIXDEF.kinds]
    bt      ecx, r14d
    jnc     .no
    movzx   edx, byte [rax + AFFIXDEF.tlo]
    imul    edx, r13d
    movzx   ecx, byte [rax + AFFIXDEF.lo]
    add     ecx, edx                    ; lo'
    movzx   edx, byte [rax + AFFIXDEF.thi]
    imul    edx, r13d
    movzx   esi, byte [rax + AFFIXDEF.hi]
    add     edx, esi                    ; hi'
    mov     esi, [rbx + r15*8 + GEARAFFIX.value]
    cmp     esi, ecx
    jl      .no
    cmp     esi, edx
    jg      .no
    mov     edi, [rbx + r15*8 + GEARAFFIX.stat]
    xor     ecx, ecx
.dup:
    cmp     ecx, r15d
    jae     .ok
    cmp     [rbx + rcx*8 + GEARAFFIX.stat], edi
    je      .no
    inc     ecx
    jmp     .dup
.ok:
    inc     r15d
    jmp     .next
.yes:
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; same(rdi a, rsi b, edx dwords) -> eax 1 when the two dword arrays are equal
same:
    mov     ecx, edx
    xor     eax, eax                    ; ZF = 1 for an empty compare
    repe cmpsd
    sete    al
    ret

; line_is(edi n, rsi expected zstr, edx expected colour) -> eax 1 when t_lines[n] is that text in
; that colour
line_is:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     r12d, edi
    mov     ebx, edx
    lea     rax, [t_lines]
    mov     rdi, [rax + r12*8]
    call    str_eq
    test    eax, eax
    jz      .ret
    lea     rax, [t_cols]
    xor     ecx, ecx
    cmp     [rax + r12*4], ebx
    sete    cl
    mov     eax, ecx
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; fmt_line_is(edi n, esi stat, edx value, ecx colour) -> eax: t_lines[n] is how rpg_format_stat
; writes that affix, in that colour
fmt_line_is:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     ebx, edi
    mov     r12d, ecx
    mov     edi, esi
    mov     esi, edx
    lea     rdx, [t_text]
    call    rpg_format_stat
    mov     edi, ebx
    lea     rsi, [t_text]
    mov     edx, r12d
    call    line_is
    pop     r12
    pop     rbx
    pop     rbp
    ret

; LINE n, text, colour: fails the test unless t_lines[n] is that text in that colour
%macro LINE 3
    mov     edi, %1
    lea     rsi, [%2]
    mov     edx, %3
    call    line_is
    test    eax, eax
    jz      .fail
%endmacro

; GOLDEN array, count: eax = 1 when t_aff holds those (stat, value) pairs
%macro GOLDEN 2
    lea     rdi, [t_aff]
    lea     rsi, [%1]
    mov     edx, (%2) * 2
    call    same
    test    eax, eax
    jz      .fail
%endmacro

; ASTACK id, dmg: t_stack = one gear stack
%macro ASTACK 2
    mov     dword [t_stack], STK(%1, 1, %2)
%endmacro

; TIP: item_tooltip(t_stack) -> eax lines
%macro TIP 0
    lea     rdi, [t_stack]
    lea     rsi, [t_lines]
    lea     rdx, [t_cols]
    call    item_tooltip
%endmacro

; NAME id, dmg, text: fails unless gear_name gives that text
%macro NAME 3
    mov     edi, %1
    mov     esi, %2
    lea     rdx, [t_text]
    call    gear_name
    lea     rdi, [t_text]
    lea     rsi, [%3]
    call    str_eq
    test    eax, eax
    jz      .fail
%endmacro

; ---- test_gear_decode_deterministic -------------------------------------------------------------
test_gear_decode_deterministic:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    inv_clear
    mov     dword [inv_sel], 0

    ; gear_make packs rarity << 14 | tier << 10 | seed
    mov     edi, IRON_SWORD
    mov     esi, 5
    mov     edx, RAR_RARE
    mov     ecx, 77
    call    gear_make
    cmp     eax, 0x9400 | 77
    jne     .fail
    mov     edi, STONE_PICKAXE          ; not gear: nothing to roll
    mov     esi, 5
    mov     edx, RAR_RARE
    mov     ecx, 77
    call    gear_make
    test    eax, eax
    jnz     .fail

    ; RAR_LEGENDARY only displays: it makes RAR_RARE bits; tier and seed are masked to their fields
    mov     edi, IRON_SWORD
    mov     esi, 5
    mov     edx, RAR_LEGENDARY
    mov     ecx, 77
    call    gear_make
    cmp     eax, 0x9400 | 77
    jne     .fail
    mov     edi, IRON_SWORD
    mov     esi, 17
    mov     edx, RAR_EPIC
    mov     ecx, 2000
    call    gear_make
    cmp     eax, 0xC000 | (1 << 10) | (2000 & 1023)
    jne     .fail
    mov     edi, 99
    call    gear_rarity_color
    cmp     eax, RGBA(255, 255, 255, 255)
    jne     .fail

    ; a rare sword: 4 affixes, decoded identically twice, all distinct, of the melee pool and in
    ; range for tier 5
    lea     rdi, [t_aff]
    xor     eax, eax
    mov     ecx, 20
    rep     stosd
    mov     edi, IRON_SWORD
    mov     esi, D_SWORD
    lea     rdx, [t_aff]
    call    gear_affixes
    cmp     eax, 4
    jne     .fail
    mov     edi, IRON_SWORD
    mov     esi, D_SWORD
    lea     rdx, [t_aff + 40]
    call    gear_affixes
    cmp     eax, 4
    jne     .fail
    lea     rdi, [t_aff]
    lea     rsi, [t_aff + 40]
    mov     edx, 10
    call    same
    test    eax, eax
    jz      .fail
    lea     rdi, [t_aff]
    mov     esi, 4
    mov     edx, 5
    mov     ecx, GK_MELEE
    call    affixes_ok
    test    eax, eax
    jz      .fail
    GOLDEN  g_rare_sword, 4

    ; magic 2, epic 5, the legendary blade 4; dmg 0 and non-gear nothing
    lea     rdi, [t_aff]
    xor     eax, eax
    mov     ecx, 20
    rep     stosd
    mov     edi, IRON_SWORD
    mov     esi, D_MAGIC_SWORD
    lea     rdx, [t_aff]
    call    gear_affixes
    cmp     eax, 2
    jne     .fail
    GOLDEN  g_magic_sword, 2
    lea     rdi, [t_aff]
    xor     eax, eax
    mov     ecx, 20
    rep     stosd
    mov     edi, RING
    mov     esi, D_EPIC_RING
    lea     rdx, [t_aff]
    call    gear_affixes
    cmp     eax, 5
    jne     .fail
    GOLDEN  g_epic_ring, 5
    lea     rdi, [t_aff]
    xor     eax, eax
    mov     ecx, 20
    rep     stosd
    mov     edi, KINGS_BLADE
    mov     esi, D_BLADE
    lea     rdx, [t_aff]
    call    gear_affixes
    cmp     eax, 4
    jne     .fail
    GOLDEN  g_blade, 4
    mov     edi, IRON_SWORD
    xor     esi, esi
    lea     rdx, [t_aff]
    call    gear_affixes
    test    eax, eax
    jnz     .fail
    mov     edi, STONE_PICKAXE
    mov     esi, 7
    lea     rdx, [t_aff]
    call    gear_affixes
    test    eax, eax
    jnz     .fail
    mov     edi, STONE_PICKAXE
    mov     esi, D_SWORD                ; a pickaxe never decodes, whatever its dmg says
    lea     rdx, [t_aff]
    call    gear_affixes
    test    eax, eax
    jnz     .fail
    mov     edi, NUM_ITEMS
    mov     esi, D_SWORD
    lea     rdx, [t_aff]
    call    gear_affixes
    test    eax, eax
    jnz     .fail

    ; rarity: bits, legendary by id, non-gear common
    mov     edi, IRON_SWORD
    mov     esi, D_SWORD
    call    gear_rarity
    cmp     eax, RAR_RARE
    jne     .fail
    mov     edi, IRON_SWORD
    xor     esi, esi
    call    gear_rarity
    cmp     eax, RAR_COMMON
    jne     .fail
    mov     edi, KINGS_BLADE
    xor     esi, esi
    call    gear_rarity
    cmp     eax, RAR_LEGENDARY
    jne     .fail
    mov     edi, KINGS_BLADE
    mov     esi, D_BLADE
    call    gear_rarity
    cmp     eax, RAR_LEGENDARY
    jne     .fail
    mov     edi, STONE_PICKAXE
    mov     esi, 7
    call    gear_rarity
    cmp     eax, RAR_COMMON
    jne     .fail
    mov     edi, RAR_COMMON
    call    gear_rarity_color
    cmp     eax, RGBA(255, 255, 255, 255)
    jne     .fail
    mov     edi, RAR_MAGIC
    call    gear_rarity_color
    cmp     eax, RGBA(100, 150, 255, 255)
    jne     .fail
    mov     edi, RAR_RARE
    call    gear_rarity_color
    cmp     eax, RGBA(255, 230, 90, 255)
    jne     .fail
    mov     edi, RAR_EPIC
    call    gear_rarity_color
    cmp     eax, RGBA(190, 110, 255, 255)
    jne     .fail
    mov     edi, RAR_LEGENDARY
    call    gear_rarity_color
    cmp     eax, RGBA(255, 150, 40, 255)
    jne     .fail

    ; names: the plain item name, or "<word of the first affix> <name>"; legendaries keep theirs
    NAME    IRON_SWORD, 0, n_iron_sword
    NAME    IRON_SWORD, D_SWORD, n_sharp
    NAME    IRON_SWORD, D_MAGIC_SWORD, n_vampiric
    NAME    RING, D_EPIC_RING, n_wise_ring
    NAME    KINGS_BLADE, D_BLADE, n_kings
    NAME    STONE_PICKAXE, 7, n_pickaxe
    NAME    NUM_ITEMS, 0, n_unknown

    ; tooltip of a rare sword: name in the rarity colour, rarity and tier, attack, 4 affixes
    ASTACK  IRON_SWORD, D_SWORD
    TIP
    cmp     eax, 7
    jne     .fail
    LINE    0, n_sharp, COL_RARE
    LINE    1, l_rare_sword, COL_GREY
    LINE    2, l_attack7, COL_WHITE
    mov     edi, 3
    mov     esi, 43
    mov     edx, 6
    mov     ecx, COL_AFFIX
    call    fmt_line_is
    test    eax, eax
    jz      .fail
    mov     edi, 6
    mov     esi, 18
    mov     edx, 5
    mov     ecx, COL_AFFIX
    call    fmt_line_is
    test    eax, eax
    jz      .fail

    ; the lines of the call before stay valid after the next one (two alternating buffers)
    lea     rsi, [t_lines]
    lea     rdi, [t_lines2]
    mov     ecx, 12
    rep     movsq
    ASTACK  KINGS_BLADE, D_BLADE
    TIP
    cmp     eax, 9                      ; name, kind, attack, 4 affixes, 2 power lines
    jne     .fail
    LINE    0, n_kings, COL_LEGEND
    LINE    1, l_legendary, COL_GREY
    LINE    2, l_attack11, COL_WHITE
    LINE    7, l_king1, COL_POWER
    LINE    8, l_king2, COL_POWER
    mov     rdi, [t_lines2]
    lea     rsi, [n_sharp]
    call    str_eq                      ; the first tooltip's name is still there
    test    eax, eax
    jz      .fail
    mov     rax, [t_lines2]
    cmp     rax, [t_lines]
    je      .fail                       ; and lives in the other buffer

    ; a hammer, armor, a plain item
    ASTACK  IRON_HAMMER, 0
    TIP
    cmp     eax, 4
    jne     .fail
    LINE    0, n_hammer, COL_WHITE
    LINE    1, l_common_wpn, COL_GREY
    LINE    2, l_attack9, COL_WHITE
    LINE    3, l_hammer, COL_WHITE
    ASTACK  IRON_CHESTPLATE, 0
    TIP
    cmp     eax, 3
    jne     .fail
    LINE    0, n_chestplate, COL_WHITE
    LINE    1, l_common_chest, COL_GREY
    LINE    2, l_armor6, COL_WHITE
    ; bows and staves show the base damage of their attack; jewelry has no value line
    ASTACK  BOW, 0
    TIP
    cmp     eax, 3
    jne     .fail
    LINE    2, l_attack9, COL_WHITE
    ASTACK  STAFF, 0
    TIP
    cmp     eax, 3
    jne     .fail
    LINE    2, l_attack4, COL_WHITE
    ASTACK  CELESTIAL_BOW, D_CELESTIAL
    TIP
    cmp     eax, 9                      ; name, kind, attack, 4 affixes, 2 power lines
    jne     .fail
    LINE    0, n_celestial, COL_LEGEND
    LINE    2, l_attack13, COL_WHITE
    LINE    7, l_celes1, COL_POWER
    LINE    8, l_celes2, COL_POWER
    ASTACK  ARCHMAGE_STAFF, 0
    TIP
    cmp     eax, 4                      ; name, kind, attack, 1 power line
    jne     .fail
    LINE    0, n_archmage, COL_LEGEND
    LINE    1, l_legend_staff, COL_GREY
    LINE    2, l_attack7, COL_WHITE
    LINE    3, l_arch1, COL_POWER
    ASTACK  RING, 0
    TIP
    cmp     eax, 2
    jne     .fail
    LINE    0, n_ring, COL_WHITE
    LINE    1, l_common_ring, COL_GREY
    ASTACK  STONE_PICKAXE, 7
    TIP
    cmp     eax, 2
    jne     .fail
    LINE    0, n_pickaxe, COL_WHITE
    LINE    1, l_durability, COL_GREY
    mov     dword [t_stack], 0
    TIP
    test    eax, eax
    jnz     .fail                       ; an empty stack has no tooltip

    ; "Shift: compare" only when another stack of the kind is held (the held stack itself has none)
    mov     dword [inv], STK(IRON_SWORD, 1, 0)
    ASTACK  IRON_SWORD, D_SWORD
    TIP
    cmp     eax, 8
    jne     .fail
    LINE    7, l_compare, COL_HINT
    lea     rdi, [inv]
    lea     rsi, [t_lines]
    lea     rdx, [t_cols]
    call    item_tooltip
    cmp     eax, 3                      ; name, "Common Weapon", attack
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    inv_clear
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test_gear_stats_and_powers -----------------------------------------------------------------

; zero_stats(): t_stats = 0
zero_stats:
    lea     rdi, [t_stats]
    mov     ecx, NUM_STATS
    xor     eax, eax
    rep     stosd
    ret

; stats_are(rdi pairs (stat, value), esi n) -> eax 1 when t_stats holds exactly those values and
; nothing else (the sum over every stat matches too)
stats_are:
    lea     r8, [t_stats]
    xor     eax, eax
    xor     ecx, ecx
.pair:
    cmp     ecx, esi
    jae     .total
    mov     edx, [rdi + rcx*8]
    mov     r9d, [rdi + rcx*8 + 4]
    add     eax, r9d
    cmp     [r8 + rdx*4], r9d
    jne     .no
    inc     ecx
    jmp     .pair
.total:
    xor     edx, edx
    xor     ecx, ecx
.sum:
    add     edx, [r8 + rcx*4]
    inc     ecx
    cmp     ecx, NUM_STATS
    jb      .sum
    cmp     edx, eax
    jne     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; acc_affixes(edi id, esi dmg): t_exp += the affixes of that stack
acc_affixes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     rdx, [t_aff]
    call    gear_affixes
    mov     ebx, eax
    xor     r12d, r12d
.add:
    cmp     r12d, ebx
    jae     .ret
    lea     rdx, [t_aff]
    mov     eax, [rdx + r12*8 + GEARAFFIX.stat]
    mov     esi, [rdx + r12*8 + GEARAFFIX.value]
    lea     rdi, [t_exp]
    add     [rdi + rax*4], esi
    inc     r12d
    jmp     .add
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ACC id, dmg: t_exp += the affixes of that stack
%macro ACC 2
    mov     edi, %1
    mov     esi, %2
    call    acc_affixes
%endmacro

; ADD_STATS: t_stats = zero, then gear_add_stats(t_stats)
%macro ADD_STATS 0
    call    zero_stats
    lea     rdi, [t_stats]
    call    gear_add_stats
%endmacro

; EXPECT_STATS golden, n: fails unless t_stats holds exactly those pairs
%macro EXPECT_STATS 2
    lea     rdi, [%1]
    mov     esi, %2
    call    stats_are
    test    eax, eax
    jz      .fail
%endmacro

; NO_STATS: fails unless t_stats is all zero
%macro NO_STATS 0
    xor     esi, esi
    call    stats_are
    test    eax, eax
    jz      .fail
%endmacro

; POWER lp, want: fails unless gear_has_power(lp) == want
%macro POWER 2
    mov     edi, %1
    call    gear_has_power
    cmp     eax, %2
    jne     .fail
%endmacro

section .rodata
align 4
g_ember:  dd STAT_FIRE_DMG, 20
g_blade0: dd STAT_ELITE_DMG, 50
g_viper:  dd STAT_POISON_DMG, 25
g_both:   dd STAT_ELITE_DMG, 50,  STAT_FIRE_DMG, 20

section .text
test_gear_stats_and_powers:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    inv_clear
    mov     dword [inv_sel], 0

    ; the held rare sword adds exactly its 4 affixes; in an unselected slot nothing
    mov     dword [inv], STK(IRON_SWORD, 1, DMG(5, RAR_RARE, 77))
    ADD_STATS
    EXPECT_STATS g_rare_sword, 4
    POWER   LP_KINGSLAYER, 0
    mov     dword [inv], 0
    mov     dword [inv + 3*4], STK(IRON_SWORD, 1, DMG(5, RAR_RARE, 77))
    ADD_STATS
    NO_STATS
    mov     dword [inv + 3*4], 0
    ; an empty held stack (count 0) with a stale id counts for nothing
    mov     dword [inv], STK(IRON_SWORD, 0, DMG(5, RAR_RARE, 77))
    ADD_STATS
    NO_STATS
    mov     dword [inv], 0

    ; a worn chestplate adds its affixes; the same piece selected in the hotbar adds nothing
    mov     dword [inv + INVENTORY.armor + 4], STK(IRON_CHESTPLATE, 1, DMG(4, RAR_RARE, 300))
    ADD_STATS
    EXPECT_STATS g_chestplate, 4
    mov     dword [inv + INVENTORY.armor + 4], 0
    mov     dword [inv], STK(IRON_CHESTPLATE, 1, DMG(4, RAR_RARE, 300))
    ADD_STATS
    NO_STATS
    mov     dword [inv], 0

    ; a ring in a jewelry cell adds its affixes (an epic: 5)
    mov     dword [inv + INVENTORY.jewelry], STK(RING, 1, DMG(8, RAR_EPIC, 1000))
    ADD_STATS
    EXPECT_STATS g_epic_ring, 5
    mov     dword [inv + INVENTORY.jewelry], 0
    ; ...and one in the hotbar does nothing
    mov     dword [inv], STK(RING, 1, DMG(8, RAR_EPIC, 1000))
    ADD_STATS
    NO_STATS
    mov     dword [inv], 0

    ; legendary implicits and powers: Ember Amulet +20 fire damage; King's Blade +50 elite
    ; damage; Viper Amulet +25 poison damage; the powers are rebuilt on every call
    mov     dword [inv + INVENTORY.jewelry + 8], STK(EMBER_AMULET, 1, 0)
    ADD_STATS
    EXPECT_STATS g_ember, 1
    POWER   LP_EMBERS, 1
    POWER   LP_VIPER, 0
    POWER   LP_KINGSLAYER, 0
    mov     dword [inv], STK(KINGS_BLADE, 1, 0)
    ADD_STATS
    EXPECT_STATS g_both, 2
    POWER   LP_EMBERS, 1
    POWER   LP_KINGSLAYER, 1
    mov     dword [inv + INVENTORY.jewelry + 8], 0
    ADD_STATS
    EXPECT_STATS g_blade0, 1
    POWER   LP_EMBERS, 0
    POWER   LP_KINGSLAYER, 1
    mov     dword [inv], 0
    mov     dword [inv + INVENTORY.jewelry + 8], STK(VIPER_AMULET, 1, 0)
    ADD_STATS
    EXPECT_STATS g_viper, 1
    POWER   LP_VIPER, 1
    mov     dword [inv + INVENTORY.jewelry + 8], 0
    ADD_STATS
    NO_STATS
    POWER   LP_VIPER, 0
    mov     eax, [gear_powers]
    test    eax, eax
    jnz     .fail

    ; every equipped cell counts, once: a sword in hand, four armor pieces, two rings, an amulet
    mov     dword [inv], STK(IRON_SWORD, 1, D_SWORD)
    mov     dword [inv + INVENTORY.armor], STK(IRON_HELMET, 1, D_HELM)
    mov     dword [inv + INVENTORY.armor + 4], STK(IRON_CHESTPLATE, 1, D_CHEST2)
    mov     dword [inv + INVENTORY.armor + 8], STK(IRON_LEGGINGS, 1, D_LEGS)
    mov     dword [inv + INVENTORY.armor + 12], STK(IRON_BOOTS, 1, D_BOOTS)
    mov     dword [inv + INVENTORY.jewelry], STK(RING, 1, D_RING1)
    mov     dword [inv + INVENTORY.jewelry + 4], STK(RING, 1, D_RING2)
    mov     dword [inv + INVENTORY.jewelry + 8], STK(AMULET, 1, D_AMULET)
    ADD_STATS
    lea     rdi, [t_exp]
    xor     eax, eax
    mov     ecx, NUM_STATS
    rep     stosd
    ACC     IRON_SWORD, D_SWORD
    ACC     IRON_HELMET, D_HELM
    ACC     IRON_CHESTPLATE, D_CHEST2
    ACC     IRON_LEGGINGS, D_LEGS
    ACC     IRON_BOOTS, D_BOOTS
    ACC     RING, D_RING1
    ACC     RING, D_RING2
    ACC     AMULET, D_AMULET
    lea     rdi, [t_stats]
    lea     rsi, [t_exp]
    mov     edx, NUM_STATS
    call    same
    test    eax, eax
    jz      .fail
    mov     dword [inv], 0
    mov     dword [inv + INVENTORY.armor], 0
    mov     dword [inv + INVENTORY.armor + 4], 0
    mov     dword [inv + INVENTORY.armor + 8], 0
    mov     dword [inv + INVENTORY.armor + 12], 0
    mov     dword [inv + INVENTORY.jewelry], 0
    mov     dword [inv + INVENTORY.jewelry + 4], 0
    mov     dword [inv + INVENTORY.jewelry + 8], 0

    ; a held bow is a weapon too
    mov     dword [inv], STK(BOW, 1, D_MAGIC_BOW)
    ADD_STATS
    mov     edi, BOW
    mov     esi, D_MAGIC_BOW
    lea     rdx, [t_aff]
    call    gear_affixes
    cmp     eax, 2
    jne     .fail
    mov     eax, [t_aff + GEARAFFIX.stat]
    mov     ecx, [t_aff + GEARAFFIX.value]
    cmp     [t_stats + rax*4], ecx
    jne     .fail
    mov     eax, [t_aff + 8 + GEARAFFIX.stat]
    mov     ecx, [t_aff + 8 + GEARAFFIX.value]
    cmp     [t_stats + rax*4], ecx
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    inv_clear
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test_gear_drops_and_chests -----------------------------------------------------------------

; roll_many(edi id, esi tier, edx table, ecx n) -> eax 1 when every roll carries the tier and a
; seed 1..1023; t_rar[0..3] = how many rolls came out common, magic, rare, epic
roll_many:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, 1
    mov     qword [t_rar], 0
    mov     qword [t_rar + 8], 0
.roll:
    test    r14d, r14d
    jz      .out
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    call    gear_roll
    mov     ecx, eax
    shr     ecx, GEAR_RARITY_SHIFT
    lea     rdx, [t_rar]
    inc     dword [rdx + rcx*4]
    mov     ecx, eax
    shr     ecx, GEAR_TIER_SHIFT
    and     ecx, 15
    cmp     ecx, r12d
    je      .tier
    xor     r15d, r15d
.tier:
    and     eax, GEAR_SEED_MASK
    jnz     .next
    xor     r15d, r15d
.next:
    dec     r14d
    jmp     .roll
.out:
    mov     eax, r15d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; material_ok(edi id, esi tier) -> eax 1 when gear_pick_base may give that item at that tier:
; swords are wood at 0, stone at 1, iron 2..5, diamond from 6 (golden always allowed); iron
; daggers, hammers, spears and armor only below tier 6, diamond ones only from tier 6
material_ok:
    mov     edx, WOOD_SWORD
    test    esi, esi
    jz      .have
    mov     edx, STONE_SWORD
    cmp     esi, 1
    je      .have
    mov     edx, IRON_SWORD
    cmp     esi, 6
    jb      .have
    mov     edx, DIAMOND_SWORD
.have:
    cmp     edi, WOOD_SWORD
    je      .sword
    cmp     edi, STONE_SWORD
    je      .sword
    cmp     edi, IRON_SWORD
    je      .sword
    cmp     edi, DIAMOND_SWORD
    je      .sword
    cmp     esi, 6
    jb      .low
    cmp     edi, IRON_DAGGER
    je      .bad
    cmp     edi, IRON_HAMMER
    je      .bad
    cmp     edi, IRON_SPEAR
    je      .bad
    lea     ecx, [rdi - IRON_HELMET]
    cmp     ecx, 3
    jbe     .bad
    jmp     .good
.low:
    cmp     edi, DIAMOND_DAGGER
    je      .bad
    cmp     edi, DIAMOND_HAMMER
    je      .bad
    cmp     edi, DIAMOND_SPEAR
    je      .bad
    lea     ecx, [rdi - DIAMOND_HELMET]
    cmp     ecx, 3
    jbe     .bad
.good:
    mov     eax, 1
    ret
.sword:
    xor     eax, eax
    cmp     edi, edx
    sete    al
    ret
.bad:
    xor     eax, eax
    ret

; pick_many(edi tier, esi class, edx n) -> eax 1 when every pick is a gear item the tier allows;
; t_cnt[0] = how many picks were bows
pick_many:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r15d, 1
    mov     dword [t_cnt], 0
.pick:
    test    r13d, r13d
    jz      .out
    mov     edi, ebx
    mov     esi, r12d
    call    gear_pick_base
    mov     r14d, eax
    cmp     eax, NUM_ITEMS
    jae     .bad
    lea     rcx, [item_gear]
    cmp     byte [rcx + rax], 0
    je      .bad
    cmp     r14d, BOW
    jne     .material
    inc     dword [t_cnt]
.material:
    mov     edi, r14d
    mov     esi, ebx
    call    material_ok
    test    eax, eax
    jnz     .next
.bad:
    xor     r15d, r15d
.next:
    dec     r13d
    jmp     .pick
.out:
    mov     eax, r15d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; scan_drops(edi tier) -> eax gear drop entities in the world; t_cnt[0] = how many carry that
; tier, t_cnt[1] = how many are rare or better, t_cnt[2] = drops that are not gear
scan_drops:
    push    rbx
    xor     eax, eax
    mov     dword [t_cnt], 0
    mov     dword [t_cnt + 4], 0
    mov     dword [t_cnt + 8], 0
    lea     rsi, [drops]
    xor     ecx, ecx
.l:
    movzx   edx, byte [rsi + DROP.id]
    test    edx, edx
    jz      .next
    lea     r8, [item_gear]
    cmp     byte [r8 + rdx], 0
    jne     .gear
    inc     dword [t_cnt + 8]
    jmp     .next
.gear:
    inc     eax
    movzx   edx, word [rsi + DROP.dmg]
    mov     ebx, edx
    shr     ebx, GEAR_TIER_SHIFT
    and     ebx, 15
    cmp     ebx, edi
    jne     .rar
    inc     dword [t_cnt]
.rar:
    shr     edx, GEAR_RARITY_SHIFT
    cmp     edx, RAR_RARE
    jb      .next
    inc     dword [t_cnt + 4]
.next:
    add     rsi, DROP_size
    inc     ecx
    cmp     ecx, MAX_DROPS
    jb      .l
    pop     rbx
    ret

; drops_have(edi id) -> eax 1 when a drop entity holds that item
drops_have:
    lea     rsi, [drops]
    xor     ecx, ecx
.l:
    cmp     [rsi + DROP.id], dil
    je      .yes
    add     rsi, DROP_size
    inc     ecx
    cmp     ecx, MAX_DROPS
    jb      .l
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; spawn_mob(edi type, esi level, edx elite) -> rax MOB* (or 0)
spawn_mob:
    push    rbx
    push    r12
    push    r13
    mov     r12d, esi
    mov     r13d, edx
    movss   xmm0, [k_x]
    movss   xmm1, [k_y]
    movss   xmm2, [k_z]
    call    mob_spawn
    xor     ebx, ebx
    test    eax, eax
    js      .ret
    imul    eax, eax, MOB_size
    lea     rbx, [mobs]
    add     rbx, rax
    mov     [rbx + MOB.level], r12d
    mov     [rbx + MOB.elite], r13d
.ret:
    mov     rax, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret

test_gear_drops_and_chests:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    call    world_clear
    call    drops_clear
    call    mobs_clear
    call    inv_clear
    mov     eax, [rpg_stats + STAT_MAGIC_FIND*4]
    mov     [t_save + 4], eax
    call    rpg_archetype
    movzx   eax, al
    mov     [t_save], eax
    mov     dword [rpg_stats + STAT_MAGIC_FIND*4], 0

    ; boss and shop rolls never come out common; the boss table gives epics
    mov     edi, 1234
    call    rng_seed
    mov     edi, RING
    mov     esi, 4
    mov     edx, LOOT_BOSS
    mov     ecx, 1000
    call    roll_many
    test    eax, eax
    jz      .fail
    cmp     dword [t_rar], 0
    jne     .fail
    cmp     dword [t_rar + 4], 0
    jne     .fail
    cmp     dword [t_rar + 12], 1
    jb      .fail
    mov     edi, RING
    mov     esi, 4
    mov     edx, LOOT_SHOP
    mov     ecx, 1000
    call    roll_many
    test    eax, eax
    jz      .fail
    cmp     dword [t_rar], 0
    jne     .fail
    mov     edi, RING
    mov     esi, 4
    mov     edx, LOOT_MOB
    mov     ecx, 1000
    call    roll_many
    cmp     dword [t_rar], 450          ; ~60 % common
    jb      .fail
    cmp     dword [t_rar], 750
    ja      .fail
    ; magic find shifts the weights: +900 % makes a plain mob roll mostly non-common
    mov     dword [rpg_stats + STAT_MAGIC_FIND*4], 900
    mov     edi, RING
    mov     esi, 4
    mov     edx, LOOT_MOB
    mov     ecx, 1000
    call    roll_many
    cmp     dword [t_rar], 250          ; ~130 of 1000 instead of ~600
    ja      .fail
    mov     dword [rpg_stats + STAT_MAGIC_FIND*4], 0

    ; tier for a level
    mov     edi, 1
    call    gear_tier_for_level
    test    eax, eax
    jnz     .fail
    mov     edi, 4
    call    gear_tier_for_level
    cmp     eax, 1
    jne     .fail
    mov     edi, 7
    call    gear_tier_for_level
    cmp     eax, 2
    jne     .fail
    mov     edi, 50
    call    gear_tier_for_level
    cmp     eax, 15
    jne     .fail
    mov     edi, 0
    call    gear_tier_for_level
    test    eax, eax
    jnz     .fail

    ; base items: always gear, an archer finds bows, the tier decides the material
    mov     edi, 5
    mov     esi, ARCH_ARCHER
    mov     edx, 200
    call    pick_many
    test    eax, eax
    jz      .fail
    cmp     dword [t_cnt], 1
    jb      .fail
%assign tier_n 0
%rep 16
    mov     edi, tier_n
    mov     esi, ARCH_WARRIOR
    mov     edx, 120
    call    pick_many
    test    eax, eax
    jz      .fail
    mov     edi, tier_n
    xor     esi, esi
    mov     edx, 120
    call    pick_many
    test    eax, eax
    jz      .fail
%assign tier_n tier_n + 1
%endrep

    ; a boss chest: exactly 2 stacks, in the lowest cells, rare or epic gear; the same seed gives
    ; the same chest whatever rng_next and magic find are doing; another seed another chest
    lea     rdi, [t_cont]
    xor     eax, eax
    mov     ecx, CONTAINER_size * 2 / 4
    rep     stosd
    lea     rdi, [t_cont]
    mov     esi, LOOT_BOSS
    mov     edx, 13
    mov     ecx, 2
    mov     r8d, 9
    call    gear_fill_chest
    xor     ebx, ebx                    ; occupied cells
    xor     r12d, r12d
.cells:
    lea     rax, [t_cont + CONTAINER.slots + r12*4]
    cmp     byte [rax + ITEMSTACK.count], 0
    je      .cell_next
    inc     ebx
    cmp     r12d, 2
    jae     .fail                       ; only cells 0 and 1 may be filled
    cmp     byte [rax + ITEMSTACK.count], 1
    jne     .fail
    movzx   ecx, byte [rax + ITEMSTACK.id]
    lea     rdx, [item_gear]
    cmp     byte [rdx + rcx], 0
    je      .fail
    movzx   ecx, word [rax + ITEMSTACK.dmg]
    shr     ecx, GEAR_RARITY_SHIFT
    cmp     ecx, RAR_RARE
    jb      .fail
    movzx   ecx, word [rax + ITEMSTACK.dmg]
    shr     ecx, GEAR_TIER_SHIFT
    and     ecx, 15
    cmp     ecx, 13
    jne     .fail
.cell_next:
    inc     r12d
    cmp     r12d, 27
    jb      .cells
    cmp     ebx, 2
    jne     .fail
    mov     edi, 777
    call    rng_seed
    mov     dword [rpg_stats + STAT_MAGIC_FIND*4], 500
    lea     rdi, [t_cont + CONTAINER_size]
    mov     esi, LOOT_BOSS
    mov     edx, 13
    mov     ecx, 2
    mov     r8d, 9
    call    gear_fill_chest
    mov     dword [rpg_stats + STAT_MAGIC_FIND*4], 0
    lea     rdi, [t_cont + CONTAINER.slots]
    lea     rsi, [t_cont + CONTAINER_size + CONTAINER.slots]
    mov     edx, 27
    call    same
    test    eax, eax
    jz      .fail
    lea     rdi, [t_cont + CONTAINER_size]
    xor     eax, eax
    mov     ecx, CONTAINER_size / 4
    rep     stosd
    lea     rdi, [t_cont + CONTAINER_size]
    mov     esi, LOOT_BOSS
    mov     edx, 13
    mov     ecx, 2
    mov     r8d, 10
    call    gear_fill_chest
    lea     rdi, [t_cont + CONTAINER.slots]
    lea     rsi, [t_cont + CONTAINER_size + CONTAINER.slots]
    mov     edx, 27
    call    same
    test    eax, eax
    jnz     .fail                       ; another seed fills another chest
    ; a 20-stack chest from the mixed chest table depends neither on magic find nor on rng_next
    lea     rdi, [t_cont]
    xor     eax, eax
    mov     ecx, CONTAINER_size * 2 / 4
    rep     stosd
    mov     edi, 31
    call    rng_seed
    lea     rdi, [t_cont]
    mov     esi, LOOT_CHEST
    mov     edx, 5
    mov     ecx, 20
    mov     r8d, 31
    call    gear_fill_chest
    mov     edi, 4242
    call    rng_seed
    mov     dword [rpg_stats + STAT_MAGIC_FIND*4], 900
    lea     rdi, [t_cont + CONTAINER_size]
    mov     esi, LOOT_CHEST
    mov     edx, 5
    mov     ecx, 20
    mov     r8d, 31
    call    gear_fill_chest
    mov     dword [rpg_stats + STAT_MAGIC_FIND*4], 0
    lea     rdi, [t_cont + CONTAINER.slots]
    lea     rsi, [t_cont + CONTAINER_size + CONTAINER.slots]
    mov     edx, 27
    call    same
    test    eax, eax
    jz      .fail
    cmp     byte [t_cont + CONTAINER.slots + 19*4 + ITEMSTACK.count], 1
    jne     .fail
    cmp     byte [t_cont + CONTAINER.slots + 20*4 + ITEMSTACK.count], 0
    jne     .fail
    ; a chest with a taken cell: the stacks go to the lowest free ones; a full chest takes none
    lea     rdi, [t_cont]
    xor     eax, eax
    mov     ecx, CONTAINER_size / 4
    rep     stosd
    mov     dword [t_cont + CONTAINER.slots], STK(COAL, 5, 0)
    lea     rdi, [t_cont]
    mov     esi, LOOT_CHEST
    mov     edx, 2
    mov     ecx, 1
    mov     r8d, 5
    call    gear_fill_chest
    cmp     dword [t_cont + CONTAINER.slots], STK(COAL, 5, 0)
    jne     .fail
    cmp     byte [t_cont + CONTAINER.slots + 4 + ITEMSTACK.count], 1
    jne     .fail
    cmp     byte [t_cont + CONTAINER.slots + 8 + ITEMSTACK.count], 0
    jne     .fail
    lea     rdi, [t_cont]
    mov     esi, LOOT_CHEST
    mov     edx, 2
    mov     ecx, 40
    mov     r8d, 6
    call    gear_fill_chest             ; more stacks than cells: stops at the last cell
    cmp     byte [t_cont + CONTAINER.slots + 26*4 + ITEMSTACK.count], 1
    jne     .fail
    cmp     dword [t_cont + CONTAINER.slots], STK(COAL, 5, 0)
    jne     .fail

    ; an elite zombie of level 10 drops at least one gear item, tier 3, rare or not
    call    drops_clear
    mov     edi, 99
    call    rng_seed
    mov     edi, MOB_ZOMBIE
    mov     esi, 10
    mov     edx, 1
    call    spawn_mob
    test    rax, rax
    jz      .fail
    mov     rdi, rax
    call    gear_drop_from_mob
    mov     edi, 3
    call    scan_drops
    cmp     eax, 1
    jb      .fail
    cmp     eax, 2
    ja      .fail                       ; one, and a second 30 % of the time
    cmp     [t_cnt], eax
    jne     .fail                       ; every one of them tier 3
    cmp     dword [t_cnt + 8], 0
    jne     .fail                       ; nothing but gear
    movss   xmm0, [drops + DROP.x]      ; popped out where the zombie stands
    comiss  xmm0, [k_x]
    jne     .fail
    ; plain hostile mobs: 6 % of 1000 deaths
    call    mobs_clear
    mov     edi, MOB_ZOMBIE
    mov     esi, 1
    xor     edx, edx
    call    spawn_mob
    mov     r13, rax
    xor     r12d, r12d                  ; kills
    xor     r14d, r14d                  ; gear dropped
.kill:
    call    drops_clear
    mov     rdi, r13
    call    gear_drop_from_mob
    xor     edi, edi
    call    scan_drops
    add     r14d, eax
    inc     r12d
    cmp     r12d, 1000
    jb      .kill
    cmp     r14d, 30
    jb      .fail
    cmp     r14d, 100
    ja      .fail

    ; the Fallen King: his class's legendary, 3 boss rolls (rare or better), tier of level 20
    xor     r15d, r15d                  ; class
.boss:
    call    mobs_clear
    call    drops_clear
    mov     edi, r15d
    call    take_path
    mov     edi, MOB_BOSS
    mov     esi, 20
    xor     edx, edx
    call    spawn_mob
    test    rax, rax
    jz      .fail
    mov     rdi, rax
    call    gear_drop_from_mob
    mov     edi, 6
    call    scan_drops
    cmp     eax, 4
    jb      .fail
    cmp     eax, 5
    ja      .fail                       ; legendary, 3 rolls, maybe a jewel
    cmp     [t_cnt], eax
    jne     .fail                       ; tier (20 - 1) / 3 = 6
    cmp     [t_cnt + 4], eax
    jne     .fail                       ; all of them rare or better
    lea     rcx, [t_legendary_by_class]
    movzx   edi, byte [rcx + r15]
    call    drops_have
    test    eax, eax
    jz      .fail
    inc     r15d
    cmp     r15d, NUM_ARCHETYPES
    jbe     .boss
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     eax, [t_save + 4]
    mov     [rpg_stats + STAT_MAGIC_FIND*4], eax
    mov     eax, [t_save]
    mov     edi, eax
    call    take_path
    call    drops_clear
    call    mobs_clear
    call    inv_clear
    mov     eax, ebx
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- test_gear_jewelry_and_no_wear --------------------------------------------------------------

%define RING_A   STK(RING, 1, DMG(2, RAR_RARE, 100))
%define RING_B   STK(RING, 1, DMG(3, RAR_MAGIC, 200))
%define RING_C   STK(RING, 1, 0)
%define AMULET_A STK(AMULET, 1, DMG(4, RAR_EPIC, 300))
%define AMULET_B STK(AMULET, 1, DMG(1, RAR_MAGIC, 400))
%define JEWEL(n) (inv + INVENTORY.jewelry + (n)*4)
%define SWORD_STACK STK(IRON_SWORD, 1, D_SWORD)
%define PICK_WORN   STK(STONE_PICKAXE, 1, 1)

; CLICKR ref, button, shift, want: inv_click returns want
%macro CLICKR 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    inv_click
    cmp     eax, %4
    jne     .fail
%endmacro

; IS cell, stack: fails unless the dword at cell is that stack
%macro IS 2
    cmp     dword [%1], %2
    jne     .fail
%endmacro

test_gear_jewelry_and_no_wear:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    call    world_clear
    call    inv_clear
    mov     dword [inv_sel], 0
    mov     qword [inv_container], 0
    mov     dword [craft_size], 2       ; the survival inventory screen: shift-click fills worn cells
    mov     eax, [game_mode]
    mov     [jew_mode], eax
    mov     dword [game_mode], MODE_SURVIVAL

    ; a ring goes into a ring cell; an amulet is refused there and fits the amulet cell
    mov     dword [CURSOR], RING_A
    CLICKR  78, 0, 0, 1
    IS      JEWEL(0), RING_A
    IS      CURSOR, 0
    mov     dword [CURSOR], AMULET_A
    CLICKR  78, 0, 0, 0                 ; refused: the ring stays, the amulet stays in hand
    CLICKR  79, 1, 0, 0
    IS      JEWEL(0), RING_A
    IS      CURSOR, AMULET_A
    CLICKR  80, 0, 0, 1
    IS      JEWEL(2), AMULET_A
    IS      CURSOR, 0
    ; a ring is refused by the amulet cell, a right click fills the second ring cell
    mov     dword [CURSOR], RING_B
    CLICKR  80, 0, 0, 0
    CLICKR  80, 1, 0, 0
    IS      JEWEL(2), AMULET_A
    IS      CURSOR, RING_B
    CLICKR  79, 1, 0, 1
    IS      JEWEL(1), RING_B
    IS      CURSOR, 0
    ; no sword, no block fits any jewelry cell
    mov     dword [CURSOR], STK(IRON_SWORD, 1, 0)
    CLICKR  78, 0, 0, 0
    CLICKR  79, 0, 0, 0
    CLICKR  80, 0, 0, 0
    mov     dword [CURSOR], STK(DIRT, 5, 0)
    CLICKR  78, 0, 0, 0
    mov     dword [CURSOR], 0
    ; a cursor ring swaps with the ring in the cell; an empty cursor takes it; refs past the
    ; amulet cell are nothing
    mov     dword [CURSOR], RING_C
    CLICKR  78, 0, 0, 1
    IS      JEWEL(0), RING_C
    IS      CURSOR, RING_A
    CLICKR  78, 0, 0, 1
    IS      JEWEL(0), RING_A
    IS      CURSOR, RING_C
    mov     dword [CURSOR], 0
    CLICKR  79, 0, 0, 1                 ; an empty cursor takes the ring
    IS      CURSOR, RING_B
    IS      JEWEL(1), 0
    CLICKR  79, 0, 0, 1                 ; the ring in hand goes back into the empty cell
    IS      JEWEL(1), RING_B
    IS      CURSOR, 0
    mov     dword [JEWEL(1)], 0
    CLICKR  79, 0, 0, 0                 ; an empty cell and an empty cursor: nothing
    mov     dword [JEWEL(1)], RING_B
    CLICKR  81, 0, 0, 0

    ; shift-click: a worn ring goes to the inventory and back to the first free ring cell
    CLICKR  78, 0, 1, 1
    IS      JEWEL(0), 0
    IS      inv, RING_A
    CLICKR  0, 0, 1, 1
    IS      JEWEL(0), RING_A
    IS      inv, 0
    ; a second ring takes the second cell; the amulet cell takes only amulets
    mov     dword [JEWEL(1)], 0
    mov     dword [inv + 5*4], RING_B
    CLICKR  5, 0, 1, 1
    IS      JEWEL(1), RING_B
    IS      inv + 5*4, 0
    ; a third ring has no cell: it only moves from the hotbar to the main inventory
    mov     dword [inv + 6*4], RING_C
    CLICKR  6, 0, 1, 1
    IS      inv + 6*4, 0
    IS      inv + 9*4, RING_C
    IS      JEWEL(0), RING_A
    IS      JEWEL(1), RING_B
    ; an amulet with the amulet cell taken stays in the inventory; with it free it goes there
    mov     dword [inv + 7*4], AMULET_B
    CLICKR  7, 0, 1, 1
    IS      inv + 7*4, 0
    IS      JEWEL(2), AMULET_A
    IS      inv + 10*4, AMULET_B
    mov     dword [JEWEL(2)], 0
    mov     dword [inv + 10*4], 0
    mov     dword [inv + 7*4], AMULET_B
    CLICKR  7, 0, 1, 1
    IS      JEWEL(2), AMULET_B
    IS      inv + 7*4, 0

    ; "Shift: compare": a worn ring is its own comparison in either ring cell (gear_equipped_for
    ; only ever returns the first occupied one); the same ring lying in the inventory is compared
    lea     rdi, [JEWEL(1)]
    lea     rsi, [t_lines]
    lea     rdx, [t_cols]
    call    item_tooltip
    mov     r12d, eax
    lea     rdi, [JEWEL(0)]
    lea     rsi, [t_lines]
    lea     rdx, [t_cols]
    call    item_tooltip
    mov     ebx, eax
    mov     dword [inv + 12*4], RING_B
    lea     rdi, [inv + 12*4]
    lea     rsi, [t_lines]
    lea     rdx, [t_cols]
    call    item_tooltip
    mov     dword [inv + 12*4], 0
    dec     eax
    cmp     eax, r12d                   ; the inventory copy has the extra "Shift: compare"
    jne     .fail
    mov     dword [inv + 12*4], RING_A
    lea     rdi, [inv + 12*4]
    lea     rsi, [t_lines]
    lea     rdx, [t_cols]
    call    item_tooltip
    mov     dword [inv + 12*4], 0
    dec     eax
    cmp     eax, ebx
    jne     .fail

    ; gear_equipped_for: the ring cells in order, the amulet cell, the worn piece, the held weapon
    mov     edi, RING
    call    gear_equipped_for
    lea     rcx, [JEWEL(0)]
    cmp     rax, rcx
    jne     .fail
    mov     dword [JEWEL(0)], 0
    mov     edi, RING
    call    gear_equipped_for
    lea     rcx, [JEWEL(1)]
    cmp     rax, rcx
    jne     .fail
    mov     dword [JEWEL(1)], 0
    mov     edi, PHOENIX_RING
    call    gear_equipped_for
    test    rax, rax
    jnz     .fail
    mov     edi, AMULET
    call    gear_equipped_for
    lea     rcx, [JEWEL(2)]
    cmp     rax, rcx
    jne     .fail
    mov     edi, IRON_HELMET
    call    gear_equipped_for
    test    rax, rax
    jnz     .fail
    mov     dword [inv + INVENTORY.armor], STK(GOLD_HELMET, 1, 0)
    mov     edi, IRON_HELMET
    call    gear_equipped_for
    lea     rcx, [inv + INVENTORY.armor]
    cmp     rax, rcx
    jne     .fail
    mov     edi, IRON_BOOTS
    call    gear_equipped_for
    test    rax, rax
    jnz     .fail
    mov     dword [inv + 2*4], STK(IRON_SWORD, 1, 0)
    mov     dword [inv_sel], 2
    mov     edi, DIAMOND_HAMMER
    call    gear_equipped_for
    lea     rcx, [inv + 2*4]
    cmp     rax, rcx
    jne     .fail
    mov     edi, BOW
    call    gear_equipped_for
    test    rax, rax
    jnz     .fail
    mov     edi, DIRT
    call    gear_equipped_for
    test    rax, rax
    jnz     .fail

    ; gear never wears: a held sword keeps its dmg word and never breaks; a pickaxe still wears
    mov     dword [inv_sel], 0
    mov     dword [inv], SWORD_STACK
    mov     edi, 1
    call    inv_damage_held
    test    eax, eax
    jnz     .fail
    IS      inv, SWORD_STACK
    mov     dword [inv], STK(STONE_PICKAXE, 1, 0)
    mov     edi, 1
    call    inv_damage_held
    test    eax, eax
    jnz     .fail
    IS      inv, PICK_WORN
    ; no gear item has a durability; tools and flint and steel still have one
    xor     ebx, ebx
.dur:
    lea     rax, [item_gear]
    cmp     byte [rax + rbx], 0
    je      .dur_next
    lea     rax, [item_durability]
    cmp     word [rax + rbx*2], 0
    jne     .fail
.dur_next:
    inc     ebx
    cmp     ebx, NUM_ITEMS
    jb      .dur
    lea     rax, [item_durability]
    cmp     word [rax + WOOD_PICKAXE*2], 0
    je      .fail
    cmp     word [rax + DIAMOND_SHOVEL*2], 0
    je      .fail
    cmp     word [rax + FLINT_AND_STEEL*2], 0
    je      .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    inv_clear
    mov     dword [inv_sel], 0
    mov     eax, [jew_mode]
    mov     [game_mode], eax
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret
