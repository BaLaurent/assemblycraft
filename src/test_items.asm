; test_items.asm - inventory, crafting and tool-rule tests.
%include "common.inc"
%include "theme.inc"
default rel

global test_inv_add_merges, test_inv_right_click_split, test_craft_planks_from_log
global test_craft_tool_shapes, test_craft_shift_click_all, test_break_time_rules
global test_craft_advanced_recipes, test_break_tiers, test_inv_click_armor_containers
global test_recipe_fill_and_sets, test_recipe_fits_grid, test_furnace_book_fill
global test_new_blocks_tables, test_shrine_block_tables, test_terrain_blocks_tables
global test_grimoire_tiles, test_attach_craft

extern inv, inv_sel, craft_size, inv_container, game_mode
extern inv_count, inv_remove_one, armor_points, inv_damage_held
extern inv_clear, inv_add, inv_click, craft_update
extern recipes, recipes_end, recipe_sets, recipe_fits, recipe_fill
extern item_break_time, item_harvest_drop
extern world_clear, world_set, world_header, conts
extern cont_create, cont_fill_from_inv
extern block_flags, block_shape, block_tiles, block_hardness, block_tool, block_drop, block_base
extern block_harvest_level, block_dig_sound, block_step_sound, block_flammable
extern item_max_stack, item_icon, item_names, block_light, block_is_usable, texgen_build

section .rodata
align 16
abs_mask: dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF
tol:      dd 0.001
f_1e29:   dd 1.0e29
t_075:    dd 0.75
t_75:     dd 7.5
t_1125:   dd 1.125
t_0:      dd 0.0
t_01875:  dd 0.1875
t_028125: dd 0.28125
t_09:     dd 0.9
t_375:    dd 3.75

section .text

; stack constant for slot/grid/result/cursor comparisons
%define STK(id, n, dmg) ((id) | ((n) << 8) | ((dmg) << 16))
; slot ref: 0..35 slot, 36..44 grid cell, 45 result, 46 cursor
%define CELL(n) (SLOTREF_GRID + (n))
%define CURSOR  46

%macro TEST_INIT 0
    call    world_clear
    call    inv_clear
    mov     dword [inv_sel], 0
    mov     dword [craft_size], 2
%endmacro

; SET ref, id, n, dmg
%macro SET 4
    lea     rax, [inv]
    mov     dword [rax + (%1)*4], STK(%2, %3, %4)
%endmacro

; EXPECT ref, id, n, dmg  - fails the test when the stack differs
%macro EXPECT 4
    lea     rax, [inv]
    cmp     dword [rax + (%1)*4], STK(%2, %3, %4)
    jne     .fail
%endmacro

; CLICK ref, button, shift
%macro CLICK 3
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    call    inv_click
%endmacro

; ADD id, n
%macro ADD 2
    mov     edi, %1
    mov     esi, %2
    call    inv_add
%endmacro

; empties the whole 3x3 grid
%macro CLEAR_GRID 0
    lea     rax, [inv]
    %assign i 0
    %rep 9
        mov     dword [rax + CELL(i)*4], 0
        %assign i i+1
    %endrep
%endmacro

%macro RETURN_OK 0
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret
%endmacro

test_inv_add_merges:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    ADD     DIRT, 70
    test    eax, eax
    jnz     .fail
    EXPECT  0, DIRT, 64, 0
    EXPECT  1, DIRT, 6, 0
    ADD     WOOD_PICKAXE, 1
    ADD     WOOD_PICKAXE, 1
    EXPECT  2, WOOD_PICKAXE, 1, 0
    EXPECT  3, WOOD_PICKAXE, 1, 0
    ADD     COBBLE, 2304
    cmp     eax, 256
    jne     .fail
    RETURN_OK

test_inv_right_click_split:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    SET     5, DIRT, 5, 0
    CLICK   5, 1, 0
    EXPECT  CURSOR, DIRT, 3, 0
    EXPECT  5, DIRT, 2, 0
    CLICK   6, 1, 0
    EXPECT  6, DIRT, 1, 0
    EXPECT  CURSOR, DIRT, 2, 0
    CLICK   6, 0, 0
    EXPECT  6, DIRT, 3, 0
    EXPECT  CURSOR, 0, 0, 0
    RETURN_OK

test_craft_planks_from_log:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    SET     CELL(4), LOG, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, PLANKS, 4, 0
    CLICK   SLOTREF_RESULT, 0, 0
    EXPECT  CURSOR, PLANKS, 4, 0
    EXPECT  CELL(4), 0, 0, 0
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    RETURN_OK

test_craft_tool_shapes:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    mov     dword [craft_size], 3
    ; stone pickaxe: CCC / 0S0 / 0S0
    SET     CELL(0), COBBLE, 1, 0
    SET     CELL(1), COBBLE, 1, 0
    SET     CELL(2), COBBLE, 1, 0
    SET     CELL(4), STICK, 1, 0
    SET     CELL(7), STICK, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, STONE_PICKAXE, 1, 0
    ; wooden axe, mirrored: PP / SP / S0
    CLEAR_GRID
    SET     CELL(0), PLANKS, 1, 0
    SET     CELL(1), PLANKS, 1, 0
    SET     CELL(4), PLANKS, 1, 0
    SET     CELL(3), STICK, 1, 0
    SET     CELL(6), STICK, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, WOOD_AXE, 1, 0
    ; the same shape one column to the right
    CLEAR_GRID
    SET     CELL(1), PLANKS, 1, 0
    SET     CELL(2), PLANKS, 1, 0
    SET     CELL(5), PLANKS, 1, 0
    SET     CELL(4), STICK, 1, 0
    SET     CELL(7), STICK, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, WOOD_AXE, 1, 0
    ; two planks on a diagonal match nothing
    CLEAR_GRID
    SET     CELL(0), PLANKS, 1, 0
    SET     CELL(4), PLANKS, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    ; 2x2 grid of planks -> crafting table
    CLEAR_GRID
    mov     dword [craft_size], 2
    SET     CELL(0), PLANKS, 1, 0
    SET     CELL(1), PLANKS, 1, 0
    SET     CELL(3), PLANKS, 1, 0
    SET     CELL(4), PLANKS, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, CRAFTING_TABLE, 1, 0
    RETURN_OK

test_craft_shift_click_all:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    SET     CELL(0), LOG, 3, 0
    call    craft_update
    CLICK   SLOTREF_RESULT, 0, 1
    EXPECT  0, PLANKS, 12, 0
    EXPECT  CELL(0), 0, 0, 0
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    RETURN_OK

; CHECK_TIME block, held, expected-label: |item_break_time - expected| <= 0.001
%macro CHECK_TIME 3
    mov     edi, %1
    mov     esi, %2
    call    item_break_time
    subss   xmm0, [%3]
    andps   xmm0, [abs_mask]
    comiss  xmm0, [tol]
    ja      .fail
%endmacro

; CHECK_DROP block, held, expected
%macro CHECK_DROP 3
    mov     edi, %1
    mov     esi, %2
    call    item_harvest_drop
    cmp     eax, %3
    jne     .fail
%endmacro

test_break_time_rules:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    CHECK_TIME DIRT, 0, t_075
    CHECK_TIME STONE, 0, t_75
    CHECK_TIME STONE, WOOD_PICKAXE, t_1125
    CHECK_TIME LOG, STONE_AXE, t_075
    mov     edi, BEDROCK
    xor     esi, esi
    call    item_break_time
    comiss  xmm0, [f_1e29]
    jb      .fail
    CHECK_DROP STONE, 0, 0
    CHECK_DROP STONE, WOOD_PICKAXE, COBBLE
    CHECK_DROP GRASS, 0, DIRT
    CHECK_DROP GLASS, 0, 0
    RETURN_OK

test_break_tiers:
    push    rbp
    mov     rbp, rsp
    TEST_INIT
    CHECK_TIME IRON_ORE, WOOD_PICKAXE, t_75
    CHECK_DROP IRON_ORE, WOOD_PICKAXE, 0
    CHECK_TIME IRON_ORE, STONE_PICKAXE, t_1125
    CHECK_DROP IRON_ORE, STONE_PICKAXE, IRON_ORE
    CHECK_DROP IRON_ORE, GOLD_PICKAXE, 0
    CHECK_DROP DIAMOND_ORE, STONE_PICKAXE, 0
    CHECK_TIME DIAMOND_ORE, IRON_PICKAXE, t_075
    CHECK_DROP DIAMOND_ORE, IRON_PICKAXE, DIAMOND
    CHECK_DROP DIAMOND_ORE, DIAMOND_PICKAXE, DIAMOND
    CHECK_DROP DIAMOND_ORE, IRON_AXE, 0
    CHECK_DROP GOLD_ORE, IRON_PICKAXE, GOLD_ORE
    CHECK_DROP GOLD_ORE, GOLD_PICKAXE, 0
    CHECK_TIME STONE, GOLD_PICKAXE, t_01875
    CHECK_DROP STONE, GOLD_PICKAXE, COBBLE
    CHECK_TIME STONE, DIAMOND_PICKAXE, t_028125
    CHECK_DROP COAL_ORE, WOOD_PICKAXE, COAL
    CHECK_DROP COAL_ORE, GOLD_PICKAXE, COAL
    CHECK_TIME CHEST, 0, t_375
    CHECK_DROP CHEST, 0, CHEST
    CHECK_TIME GRAVEL, 0, t_09
    CHECK_DROP GRAVEL, 0, GRAVEL
    CHECK_TIME TNT, 0, t_0
    CHECK_DROP TNT, 0, TNT
    CHECK_DROP FURNACE, 0, 0
    CHECK_DROP FURNACE_LIT, STONE_PICKAXE, FURNACE
    RETURN_OK

; ---- advanced recipes: one table row per case ------------------------------------------
; CASE result id, result count, then the 3x3 grid ids row by row (0 = empty cell)
%macro CASE 11
    db %1, %2, %3, %4, %5, %6, %7, %8, %9, %10, %11
%endmacro

section .rodata
craft_cases:
    CASE FURNACE, 1,    COBBLE, COBBLE, COBBLE,    COBBLE, 0, COBBLE,    COBBLE, COBBLE, COBBLE
    CASE CHEST, 1,      PLANKS, PLANKS, PLANKS,    PLANKS, 0, PLANKS,    PLANKS, PLANKS, PLANKS
    CASE BOW, 1,        0, STICK, STRING,          STICK, 0, STRING,     0, STICK, STRING
    CASE BOW, 1,        STRING, STICK, 0,          STRING, 0, STICK,     STRING, STICK, 0
    CASE ARROW, 4,      0, FLINT, 0,               0, STICK, 0,          0, FEATHER, 0
    CASE FLINT_AND_STEEL, 1,  IRON_INGOT, 0, 0,    0, FLINT, 0,          0, 0, 0
    CASE FLINT_AND_STEEL, 1,  0, IRON_INGOT, 0,    FLINT, 0, 0,          0, 0, 0
    CASE FLINT_AND_STEEL, 1,  IRON_INGOT, FLINT, 0, 0, 0, 0,             0, 0, 0
    CASE TNT, 1,        GUNPOWDER, SAND, GUNPOWDER,  SAND, GUNPOWDER, SAND,  GUNPOWDER, SAND, GUNPOWDER
    CASE IRON_PICKAXE, 1,     IRON_INGOT, IRON_INGOT, IRON_INGOT,  0, STICK, 0,  0, STICK, 0
    CASE GOLD_SWORD, 1,       0, GOLD_INGOT, 0,    0, GOLD_INGOT, 0,     0, STICK, 0
    CASE DIAMOND_HELMET, 1,   DIAMOND, DIAMOND, DIAMOND,  DIAMOND, 0, DIAMOND,  0, 0, 0
    CASE IRON_BOOTS, 1,       IRON_INGOT, 0, IRON_INGOT,  IRON_INGOT, 0, IRON_INGOT,  0, 0, 0
    CASE DIAMOND_CHESTPLATE, 1,  DIAMOND, 0, DIAMOND,  DIAMOND, DIAMOND, DIAMOND,  DIAMOND, DIAMOND, DIAMOND
    CASE GOLD_LEGGINGS, 1,    GOLD_INGOT, GOLD_INGOT, GOLD_INGOT,  GOLD_INGOT, 0, GOLD_INGOT,  GOLD_INGOT, 0, GOLD_INGOT
    ; firearms and their ammunition
    CASE PISTOL, 1,           IRON_INGOT, IRON_INGOT, 0,  0, PLANKS, 0,  0, 0, 0
    CASE MUSKET, 1,           0, 0, IRON_INGOT,  0, IRON_INGOT, FLINT_AND_STEEL,  LOG, 0, 0
    CASE SHOTGUN, 1,          0, 0, 0,  IRON_INGOT, IRON_INGOT, IRON_INGOT,  0, PLANKS, PLANKS
    CASE KALASHNIKOV, 1,      IRON_INGOT, IRON_INGOT, IRON_INGOT,  0, DIAMOND, IRON_INGOT,  0, PLANKS, IRON_INGOT
    CASE ROCKET_LAUNCHER, 1,  IRON_INGOT, IRON_INGOT, IRON_INGOT,  DIAMOND, 0, DIAMOND,  IRON_INGOT, IRON_INGOT, IRON_INGOT
    CASE PISTOL_ROUND, 8,     0, 0, IRON_INGOT,  0, 0, GUNPOWDER,  0, 0, 0
    CASE MUSKET_BALL, 4,      0, 0, 0,  0, 0, 0,  IRON_INGOT, GUNPOWDER, 0
    CASE SHOTGUN_SHELL, 4,    IRON_INGOT, 0, 0,  GUNPOWDER, 0, 0,  FEATHER, 0, 0
    CASE RIFLE_ROUND, 16,     0, IRON_INGOT, 0,  0, GUNPOWDER, 0,  0, GUNPOWDER, 0
    CASE ROCKET, 1,           0, IRON_INGOT, 0,  0, TNT, 0,  0, GUNPOWDER, 0
    ; 0.10.4: the revolver, the hunting rifle and the four attachments
    CASE REVOLVER, 1,         IRON_INGOT, IRON_INGOT, GOLD_INGOT,  0, PLANKS, 0,  0, 0, 0
    CASE HUNTING_RIFLE, 1,    IRON_INGOT, IRON_INGOT, IRON_INGOT,  PLANKS, PLANKS, GLASS_PANE,  0, 0, 0
    CASE SCOPE, 1,            IRON_INGOT, GLASS_PANE, IRON_INGOT,  0, 0, 0,  0, 0, 0
    CASE EXTENDED_MAG, 1,     0, IRON_INGOT, 0,  0, GOLD_INGOT, 0,  0, IRON_INGOT, 0
    CASE RIFLED_BARREL, 1,    0, 0, 0,  IRON_INGOT, IRON_INGOT, DIAMOND,  0, 0, 0
    CASE COMPENSATOR, 1,      0, 0, 0,  0, 0, 0,  FLINT, IRON_INGOT, FLINT
    ; 0.7: building blocks, storage blocks both ways, slabs, stairs (both mirrors), doors,
    ; trapdoor, ladder, torch, fence, glass pane
    CASE SANDSTONE, 1,        SAND, SAND, 0,  SAND, SAND, 0,  0, 0, 0
    CASE MOSSY_COBBLESTONE, 1, COBBLE, LEAVES, 0,  0, 0, 0,  0, 0, 0
    CASE MOSSY_STONE_BRICK, 1, 0, 0, 0,  0, STONE_BRICK, LEAVES,  0, 0, 0
    CASE BOOKSHELF, 1,        PLANKS, PLANKS, PLANKS,  STICK, STICK, STICK,  PLANKS, PLANKS, PLANKS
    CASE WOOL, 1,             0, STRING, STRING,  0, STRING, STRING,  0, 0, 0
    CASE IRON_BLOCK, 1,       IRON_INGOT, IRON_INGOT, IRON_INGOT,  IRON_INGOT, IRON_INGOT, IRON_INGOT,  IRON_INGOT, IRON_INGOT, IRON_INGOT
    CASE IRON_INGOT, 9,       0, 0, 0,  0, IRON_BLOCK, 0,  0, 0, 0
    CASE GOLD_BLOCK, 1,       GOLD_INGOT, GOLD_INGOT, GOLD_INGOT,  GOLD_INGOT, GOLD_INGOT, GOLD_INGOT,  GOLD_INGOT, GOLD_INGOT, GOLD_INGOT
    CASE GOLD_INGOT, 9,       0, 0, 0,  0, 0, 0,  0, 0, GOLD_BLOCK
    CASE DIAMOND_BLOCK, 1,    DIAMOND, DIAMOND, DIAMOND,  DIAMOND, DIAMOND, DIAMOND,  DIAMOND, DIAMOND, DIAMOND
    CASE DIAMOND, 9,          DIAMOND_BLOCK, 0, 0,  0, 0, 0,  0, 0, 0
    CASE COAL_BLOCK, 1,       COAL, COAL, COAL,  COAL, COAL, COAL,  COAL, COAL, COAL
    CASE COAL, 9,             0, 0, 0,  COAL_BLOCK, 0, 0,  0, 0, 0
    CASE PLANK_SLAB, 6,       PLANKS, PLANKS, PLANKS,  0, 0, 0,  0, 0, 0
    CASE COBBLE_SLAB, 6,      0, 0, 0,  COBBLE, COBBLE, COBBLE,  0, 0, 0
    CASE STONE_BRICK_SLAB, 6, 0, 0, 0,  0, 0, 0,  STONE_BRICK, STONE_BRICK, STONE_BRICK
    CASE BRICK_SLAB, 6,       BRICK, BRICK, BRICK,  0, 0, 0,  0, 0, 0
    CASE SANDSTONE_SLAB, 6,   0, 0, 0,  SANDSTONE, SANDSTONE, SANDSTONE,  0, 0, 0
    CASE PLANK_STAIRS, 4,     PLANKS, 0, 0,  PLANKS, PLANKS, 0,  PLANKS, PLANKS, PLANKS
    CASE PLANK_STAIRS, 4,     0, 0, PLANKS,  0, PLANKS, PLANKS,  PLANKS, PLANKS, PLANKS
    CASE COBBLE_STAIRS, 4,    COBBLE, 0, 0,  COBBLE, COBBLE, 0,  COBBLE, COBBLE, COBBLE
    CASE COBBLE_STAIRS, 4,    0, 0, COBBLE,  0, COBBLE, COBBLE,  COBBLE, COBBLE, COBBLE
    CASE STONE_BRICK_STAIRS, 4, STONE_BRICK, 0, 0,  STONE_BRICK, STONE_BRICK, 0,  STONE_BRICK, STONE_BRICK, STONE_BRICK
    CASE STONE_BRICK_STAIRS, 4, 0, 0, STONE_BRICK,  0, STONE_BRICK, STONE_BRICK,  STONE_BRICK, STONE_BRICK, STONE_BRICK
    CASE BRICK_STAIRS, 4,     BRICK, 0, 0,  BRICK, BRICK, 0,  BRICK, BRICK, BRICK
    CASE BRICK_STAIRS, 4,     0, 0, BRICK,  0, BRICK, BRICK,  BRICK, BRICK, BRICK
    CASE SANDSTONE_STAIRS, 4, SANDSTONE, 0, 0,  SANDSTONE, SANDSTONE, 0,  SANDSTONE, SANDSTONE, SANDSTONE
    CASE SANDSTONE_STAIRS, 4, 0, 0, SANDSTONE,  0, SANDSTONE, SANDSTONE,  SANDSTONE, SANDSTONE, SANDSTONE
    CASE WOOD_DOOR, 3,        PLANKS, PLANKS, 0,  PLANKS, PLANKS, 0,  PLANKS, PLANKS, 0
    CASE IRON_DOOR, 3,        0, IRON_INGOT, IRON_INGOT,  0, IRON_INGOT, IRON_INGOT,  0, IRON_INGOT, IRON_INGOT
    CASE TRAPDOOR, 2,         0, 0, 0,  PLANKS, PLANKS, PLANKS,  PLANKS, PLANKS, PLANKS
    CASE LADDER, 3,           STICK, 0, STICK,  STICK, STICK, STICK,  STICK, 0, STICK
    CASE TORCH, 4,            0, 0, 0,  0, COAL, 0,  0, STICK, 0
    CASE FENCE, 3,            PLANKS, STICK, PLANKS,  PLANKS, STICK, PLANKS,  0, 0, 0
    CASE GLASS_PANE, 16,      0, 0, 0,  GLASS, GLASS, GLASS,  GLASS, GLASS, GLASS
    ; 0.8: warhammers and spears
    CASE IRON_HAMMER, 1,      IRON_INGOT, IRON_INGOT, IRON_INGOT,  IRON_INGOT, STICK, IRON_INGOT,  0, STICK, 0
    CASE DIAMOND_HAMMER, 1,   DIAMOND, DIAMOND, DIAMOND,  DIAMOND, STICK, DIAMOND,  0, STICK, 0
    CASE IRON_SPEAR, 1,       0, 0, IRON_INGOT,  0, STICK, 0,  STICK, 0, 0
    CASE DIAMOND_SPEAR, 1,    0, 0, DIAMOND,  0, STICK, 0,  STICK, 0, 0
    ; 0.9: planks from the new logs, bed, boat
    CASE PLANKS, 4,           0, 0, 0,  0, PINE_LOG, 0,  0, 0, 0
    CASE PLANKS, 4,           0, 0, 0,  0, 0, 0,  BIRCH_LOG, 0, 0
    CASE BED, 1,              WOOL, WOOL, WOOL,  PLANKS, PLANKS, PLANKS,  0, 0, 0
    CASE BED, 1,              0, 0, 0,  WOOL, WOOL, WOOL,  PLANKS, PLANKS, PLANKS
    CASE BOAT, 1,             PLANKS, 0, PLANKS,  PLANKS, PLANKS, PLANKS,  0, 0, 0
    CASE BOAT, 1,             0, 0, 0,  PLANKS, 0, PLANKS,  PLANKS, PLANKS, PLANKS
    ; near misses craft nothing
    CASE 0, 0,          COBBLE, COBBLE, COBBLE,    COBBLE, COBBLE, COBBLE,  COBBLE, COBBLE, COBBLE
    CASE 0, 0,          0, IRON_INGOT, 0,          0, FLINT, 0,          0, 0, 0
    CASE 0, 0,          0, STICK, STRING,          STICK, 0, STRING,     STICK, 0, STRING
    CASE 0, 0,          0, 0, 0,  IRON_INGOT, IRON_INGOT, IRON_INGOT,  0, PLANKS, 0
    CASE 0, 0,          PLANKS, 0, PLANKS,  0, 0, 0,  0, 0, 0
    CASE 0, 0,          COBBLE, 0, 0,  COBBLE, COBBLE, 0,  COBBLE, COBBLE, 0
    CASE 0, 0,          STICK, 0, 0,  COAL, 0, 0,  0, 0, 0
    CASE 0, 0,          STICK, PLANKS, STICK,  STICK, PLANKS, STICK,  0, 0, 0
    CASE 0, 0,          STRING, STRING, 0,  STRING, 0, 0,  0, 0, 0
    CASE 0, 0,          IRON_INGOT, IRON_INGOT, 0,  IRON_INGOT, IRON_INGOT, 0,  0, 0, 0
    CASE 0, 0,          IRON_INGOT, IRON_INGOT, IRON_INGOT,  IRON_INGOT, STICK, IRON_INGOT,  0, 0, 0
    CASE 0, 0,          IRON_INGOT, 0, 0,  0, STICK, 0,  0, 0, STICK
    CASE 0, 0,          WOOL, WOOL, WOOL,  PLANKS, 0, PLANKS,  0, 0, 0
    CASE 0, 0,          PLANKS, 0, PLANKS,  PLANKS, 0, PLANKS,  0, 0, 0
craft_cases_end:

section .text

test_craft_advanced_recipes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    TEST_INIT
    mov     dword [craft_size], 3
    lea     rbx, [craft_cases]
    lea     r12, [craft_cases_end]
.case:
    lea     rdi, [inv + INVENTORY.grid]
    xor     ecx, ecx
.cell:
    movzx   eax, byte [rbx + 2 + rcx]
    test    eax, eax
    jz      .put
    or      eax, 0x100                  ; one item
.put:
    mov     [rdi + rcx*4], eax
    inc     ecx
    cmp     ecx, 9
    jb      .cell
    call    craft_update
    movzx   eax, byte [rbx + 1]
    shl     eax, 8
    movzx   ecx, byte [rbx]
    or      eax, ecx
    cmp     [inv + INVENTORY.result], eax
    jne     .fail
    add     rbx, 11
    cmp     rbx, r12
    jb      .case
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    inv_clear
    mov     dword [craft_size], 2
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- armor and container cells of inv_click --------------------------------------------
%define ARMOR_REF(n) (SLOTREF_ARMOR + (n))
%define CREF(n)      (SLOTREF_CONTAINER + (n))

; CSET k, id, n, dmg / CEXPECT k, id, n, dmg: cell k of the open container
%macro CSET 4
    mov     rax, [inv_container]
    mov     dword [rax + CONTAINER.slots + (%1)*4], STK(%2, %3, %4)
%endmacro
%macro CEXPECT 4
    mov     rax, [inv_container]
    cmp     dword [rax + CONTAINER.slots + (%1)*4], STK(%2, %3, %4)
    jne     .fail
%endmacro

; CLICKR ref, button, shift, expected return value
%macro CLICKR 4
    CLICK   %1, %2, %3
    cmp     eax, %4
    jne     .fail
%endmacro

; MAKE_CONT x, y, z, block, kind: sets the block and creates its record -> rax
%macro MAKE_CONT 5
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %5
    call    cont_create
%endmacro

; zero_conts() - empties the runtime container table
zero_conts:
    lea     rdi, [conts]
    mov     ecx, MAX_CONTAINERS * CONTAINER_size
    xor     eax, eax
    rep     stosb
    ret

test_inv_click_armor_containers:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    TEST_INIT
    mov     r12d, [game_mode]           ; the screen rules below are survival's
    mov     dword [game_mode], MODE_SURVIVAL
    call    zero_conts
    mov     qword [inv_container], 0

    ; the crafting table and the creative palette draw no armor or jewelry cells: shift-click
    ; keeps the piece in the inventory (hotbar -> main) instead of hiding it in a worn cell
    mov     dword [craft_size], 3
    SET     0, IRON_HELMET, 1, 0
    CLICKR  0, 0, 1, 1
    EXPECT  ARMOR_REF(0), 0, 0, 0
    EXPECT  9, IRON_HELMET, 1, 0
    SET     1, RING, 1, 0
    CLICKR  1, 0, 1, 1
    cmp     dword [inv + INVENTORY.jewelry], 0
    jne     .fail
    EXPECT  10, RING, 1, 0
    mov     dword [craft_size], 2
    mov     dword [game_mode], MODE_CREATIVE
    SET     2, AMULET, 1, 0
    CLICKR  2, 0, 1, 1
    cmp     dword [inv + INVENTORY.jewelry + 8], 0
    jne     .fail
    EXPECT  11, AMULET, 1, 0
    SET     3, IRON_HELMET, 1, 0
    CLICKR  3, 0, 1, 1
    EXPECT  ARMOR_REF(0), 0, 0, 0
    EXPECT  12, IRON_HELMET, 1, 0
    mov     dword [game_mode], MODE_SURVIVAL
    call    inv_clear

    ; shift-click sends a helmet to the empty head cell
    SET     0, IRON_HELMET, 1, 0
    SET     1, DIRT, 5, 0
    CLICKR  0, 0, 1, 1
    EXPECT  ARMOR_REF(0), IRON_HELMET, 1, 0
    EXPECT  0, 0, 0, 0
    ; dirt is no chestplate: the click is refused and the cursor keeps the dirt
    CLICKR  1, 0, 0, 1
    EXPECT  CURSOR, DIRT, 5, 0
    CLICKR  ARMOR_REF(1), 0, 0, 0
    EXPECT  ARMOR_REF(1), 0, 0, 0
    EXPECT  CURSOR, DIRT, 5, 0
    CLICKR  1, 0, 0, 1
    EXPECT  1, DIRT, 5, 0
    EXPECT  CURSOR, 0, 0, 0

    ; with the head cell taken, a second helmet only moves between hotbar and main
    SET     2, GOLD_HELMET, 1, 7
    CLICKR  2, 0, 1, 1
    EXPECT  ARMOR_REF(0), IRON_HELMET, 1, 0
    EXPECT  2, 0, 0, 0
    EXPECT  9, GOLD_HELMET, 1, 7
    ; either button swaps the cursor with the head cell; a helmet fits no other cell
    CLICKR  9, 0, 0, 1
    EXPECT  CURSOR, GOLD_HELMET, 1, 7
    CLICKR  ARMOR_REF(1), 0, 0, 0
    CLICKR  ARMOR_REF(0), 1, 0, 1
    EXPECT  ARMOR_REF(0), GOLD_HELMET, 1, 7
    EXPECT  CURSOR, IRON_HELMET, 1, 0
    CLICKR  ARMOR_REF(0), 0, 0, 1
    EXPECT  ARMOR_REF(0), IRON_HELMET, 1, 0
    EXPECT  CURSOR, GOLD_HELMET, 1, 7
    CLICKR  9, 0, 0, 1
    EXPECT  9, GOLD_HELMET, 1, 7
    EXPECT  CURSOR, 0, 0, 0
    ; an empty cursor takes the worn piece; an empty cell has nothing to take
    CLICKR  ARMOR_REF(0), 0, 0, 1
    EXPECT  CURSOR, IRON_HELMET, 1, 0
    EXPECT  ARMOR_REF(0), 0, 0, 0
    CLICKR  ARMOR_REF(0), 0, 0, 1
    EXPECT  ARMOR_REF(0), IRON_HELMET, 1, 0
    EXPECT  CURSOR, 0, 0, 0
    CLICKR  ARMOR_REF(3), 0, 0, 0
    ; shift-click on a worn piece sends it to the inventory, and back
    CLICKR  ARMOR_REF(0), 0, 1, 1
    EXPECT  ARMOR_REF(0), 0, 0, 0
    EXPECT  0, IRON_HELMET, 1, 0
    CLICKR  0, 0, 1, 1
    EXPECT  ARMOR_REF(0), IRON_HELMET, 1, 0
    EXPECT  0, 0, 0, 0

    ; a chest: shift-click moves stacks into it and back out
    MAKE_CONT 5, 11, 5, CHEST, CONT_CHEST
    test    rax, rax
    jz      .fail
    mov     [inv_container], rax
    CLICKR  1, 0, 1, 1
    CEXPECT 0, DIRT, 5, 0
    EXPECT  1, 0, 0, 0
    CLICKR  CREF(0), 0, 1, 1
    EXPECT  0, DIRT, 5, 0
    CEXPECT 0, 0, 0, 0
    CSET    26, STICK, 3, 0             ; the last cell is a real cell
    CLICKR  CREF(26), 0, 1, 1
    EXPECT  1, STICK, 3, 0
    CEXPECT 26, 0, 0, 0
    SET     1, 0, 0, 0

    ; a furnace: ore goes to the input, fuel to the fuel cell
    MAKE_CONT 6, 11, 5, FURNACE, CONT_FURNACE
    test    rax, rax
    jz      .fail
    mov     [inv_container], rax
    SET     2, IRON_ORE, 3, 0
    SET     3, COAL, 2, 0
    SET     4, DIRT, 1, 0
    CLICKR  2, 0, 1, 1
    CEXPECT 0, IRON_ORE, 3, 0
    EXPECT  2, 0, 0, 0
    CLICKR  3, 0, 1, 1
    CEXPECT 1, COAL, 2, 0
    EXPECT  3, 0, 0, 0
    ; the output cell is take-only: the whole stack goes to the cursor, once
    CSET    2, IRON_INGOT, 4, 0
    CLICKR  CREF(2), 0, 0, 1
    EXPECT  CURSOR, IRON_INGOT, 4, 0
    CEXPECT 2, 0, 0, 0
    CLICKR  CREF(2), 0, 0, 0
    CLICKR  2, 0, 0, 1
    EXPECT  2, IRON_INGOT, 4, 0
    ; the fuel cell refuses what does not burn
    CLICKR  4, 0, 0, 1
    EXPECT  CURSOR, DIRT, 1, 0
    CLICKR  CREF(1), 0, 0, 0
    CEXPECT 1, COAL, 2, 0
    CLICKR  4, 0, 0, 1
    ; the cursor adds to the output when it holds the same item and the total fits
    CLICKR  2, 0, 0, 1
    CSET    2, IRON_INGOT, 3, 0
    CLICKR  CREF(2), 0, 0, 1
    EXPECT  CURSOR, IRON_INGOT, 7, 0
    CEXPECT 2, 0, 0, 0
    SET     CURSOR, IRON_INGOT, 62, 0   ; 62 + 3 > 64
    CSET    2, IRON_INGOT, 3, 0
    CLICKR  CREF(2), 0, 0, 0
    CEXPECT 2, IRON_INGOT, 3, 0
    EXPECT  CURSOR, IRON_INGOT, 62, 0
    SET     CURSOR, STONE, 1, 0         ; another item
    CLICKR  CREF(2), 0, 0, 0
    CEXPECT 2, IRON_INGOT, 3, 0
    EXPECT  CURSOR, STONE, 1, 0
    SET     CURSOR, 0, 0, 0             ; right click takes the whole stack too
    CLICKR  CREF(2), 1, 0, 1
    EXPECT  CURSOR, IRON_INGOT, 3, 0
    CEXPECT 2, 0, 0, 0
    ; a furnace has three cells
    CSET    3, STICK, 1, 0
    CLICKR  CREF(3), 0, 0, 0
    CEXPECT 3, STICK, 1, 0
    EXPECT  CURSOR, IRON_INGOT, 3, 0
    ; coal tops up the fuel; the input cell takes any item
    SET     CURSOR, COAL, 1, 0
    CLICKR  CREF(1), 0, 0, 1
    CEXPECT 1, COAL, 3, 0
    EXPECT  CURSOR, 0, 0, 0
    SET     CURSOR, DIRT, 1, 0
    CLICKR  CREF(0), 0, 0, 1
    CEXPECT 0, DIRT, 1, 0
    EXPECT  CURSOR, IRON_ORE, 3, 0
    CLICKR  CREF(0), 0, 0, 1
    CEXPECT 0, IRON_ORE, 3, 0
    EXPECT  CURSOR, DIRT, 1, 0
    SET     CURSOR, 0, 0, 0
    ; shift-click: what is neither ore nor fuel moves on within the inventory, smeltable
    ; and fuel stacks merge into their cell, and a taken input cell leaves the stack alone
    CLICKR  4, 0, 1, 1
    EXPECT  4, 0, 0, 0
    EXPECT  10, DIRT, 1, 0
    SET     5, SAND, 3, 0
    CLICKR  5, 0, 1, 0
    EXPECT  5, SAND, 3, 0
    CSET    0, SAND, 10, 0
    CLICKR  5, 0, 1, 1
    CEXPECT 0, SAND, 13, 0
    EXPECT  5, 0, 0, 0
    SET     6, COAL, 5, 0
    CLICKR  6, 0, 1, 1
    CEXPECT 1, COAL, 8, 0
    EXPECT  6, 0, 0, 0
    ; no container open: the container refs do nothing
    mov     qword [inv_container], 0
    CLICKR  CREF(0), 0, 0, 0
    CLICKR  CREF(2), 0, 1, 0

    ; no container: hotbar <-> main in both directions
    call    inv_clear
    SET     3, DIRT, 5, 0
    CLICKR  3, 0, 1, 1
    EXPECT  3, 0, 0, 0
    EXPECT  9, DIRT, 5, 0
    CLICKR  9, 0, 1, 1
    EXPECT  9, 0, 0, 0
    EXPECT  0, DIRT, 5, 0

    ; inv_count sees the 36 slots only; inv_remove_one takes from the first stack holding it
    call    inv_clear
    SET     0, ARROW, 1, 0
    SET     5, ARROW, 2, 0
    SET     35, ARROW, 4, 0
    SET     CELL(0), ARROW, 9, 0        ; neither the grid nor the cursor counts
    SET     CURSOR, ARROW, 9, 0
    mov     edi, ARROW
    call    inv_count
    cmp     eax, 7
    jne     .fail
    mov     edi, STRING
    call    inv_count
    test    eax, eax
    jnz     .fail
    mov     edi, ARROW
    call    inv_remove_one
    cmp     eax, 1
    jne     .fail
    EXPECT  0, 0, 0, 0                  ; the single arrow of slot 0 is gone
    EXPECT  5, ARROW, 2, 0
    mov     edi, ARROW
    call    inv_remove_one
    EXPECT  5, ARROW, 1, 0
    mov     edi, ARROW
    call    inv_remove_one
    EXPECT  5, 0, 0, 0
    mov     edi, ARROW
    call    inv_remove_one
    EXPECT  35, ARROW, 3, 0
    mov     edi, ARROW
    call    inv_remove_one
    mov     edi, ARROW
    call    inv_remove_one
    mov     edi, ARROW
    call    inv_remove_one
    EXPECT  35, 0, 0, 0
    mov     edi, ARROW
    call    inv_remove_one              ; only the grid and the cursor still hold arrows
    test    eax, eax
    jnz     .fail
    EXPECT  CELL(0), ARROW, 9, 0
    EXPECT  CURSOR, ARROW, 9, 0

    ; armor_points adds the worn pieces; inv_clear wipes the armor and jewelry rows with the rest
    SET     ARMOR_REF(2), IRON_LEGGINGS, 1, 0
    mov     dword [inv + INVENTORY.jewelry + 8], STK(AMULET, 1, 0)
    call    inv_clear
    EXPECT  ARMOR_REF(2), 0, 0, 0
    cmp     dword [inv + INVENTORY.jewelry + 8], 0
    jne     .fail
    SET     ARMOR_REF(0), IRON_HELMET, 1, 0
    SET     ARMOR_REF(1), GOLD_CHESTPLATE, 1, 111
    SET     ARMOR_REF(3), DIAMOND_BOOTS, 1, 5
    call    armor_points
    cmp     eax, 10                     ; 2 + 5 + 3
    jne     .fail

    ; only what has a durability wears: a pickaxe and flint and steel do; gear (the bow) and the
    ; rest do not
    call    inv_clear
    mov     dword [inv_sel], 0
    SET     0, STONE_PICKAXE, 1, 0
    mov     edi, 1
    call    inv_damage_held
    test    eax, eax
    jnz     .fail
    EXPECT  0, STONE_PICKAXE, 1, 1
    SET     0, BOW, 1, 0
    mov     edi, 1
    call    inv_damage_held
    test    eax, eax
    jnz     .fail
    EXPECT  0, BOW, 1, 0
    SET     0, FLINT_AND_STEEL, 1, 63   ; durability 64
    mov     edi, 1
    call    inv_damage_held
    cmp     eax, 1
    jne     .fail
    EXPECT  0, 0, 0, 0
    SET     0, DIRT, 5, 0
    mov     edi, 1
    call    inv_damage_held
    test    eax, eax
    jnz     .fail
    EXPECT  0, DIRT, 5, 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    mov     [game_mode], r12d
    call    inv_clear
    mov     qword [inv_container], 0
    call    zero_conts
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- recipe book support: recipe_sets / recipe_fits / recipe_fill, cont_fill_from_inv -----

; find_recipe(edi out id) -> rax the first record of the recipe table that makes that item, or 0
find_recipe:
    lea     rax, [recipes]
    lea     rdx, [recipes_end]
.l:
    cmp     rax, rdx
    jae     .none
    cmp     [rax + 2], dil
    je      .ret
    add     rax, RECIPE_SIZE
    jmp     .l
.none:
    xor     eax, eax
.ret:
    ret

%macro FIND 1                           ; the record that makes item %1 -> rbx
    mov     edi, %1
    call    find_recipe
    mov     rbx, rax
    test    rax, rax
    jz      .fail
%endmacro
%macro SETS_EQ 1                        ; recipe_sets(rbx) == %1
    mov     rdi, rbx
    call    recipe_sets
    cmp     eax, %1
    jne     .fail
%endmacro
%macro FILL_EQ 2                        ; recipe_fill(rbx, %1) == %2
    mov     rdi, rbx
    mov     esi, %1
    call    recipe_fill
    cmp     eax, %2
    jne     .fail
%endmacro
%macro FITS_EQ 1                        ; recipe_fits(rbx) == %1
    mov     rdi, rbx
    call    recipe_fits
    cmp     eax, %1
    jne     .fail
%endmacro
%macro CFILL 3                          ; cont_fill_from_inv(cell %1, item %2) == %3
    mov     edi, %1
    mov     esi, %2
    call    cont_fill_from_inv
    cmp     eax, %3
    jne     .fail
%endmacro

test_recipe_fill_and_sets:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    TEST_INIT
    mov     dword [craft_size], 3
    ; 4 ingots and 3 sticks make the iron pickaxe once
    SET     0, IRON_INGOT, 4, 0
    SET     1, STICK, 3, 0
    FIND    IRON_PICKAXE
    SETS_EQ 1
    FILL_EQ 1, 1
    EXPECT  CELL(0), IRON_INGOT, 1, 0
    EXPECT  CELL(1), IRON_INGOT, 1, 0
    EXPECT  CELL(2), IRON_INGOT, 1, 0
    EXPECT  CELL(3), 0, 0, 0
    EXPECT  CELL(4), STICK, 1, 0
    EXPECT  CELL(5), 0, 0, 0
    EXPECT  CELL(6), 0, 0, 0
    EXPECT  CELL(7), STICK, 1, 0
    EXPECT  CELL(8), 0, 0, 0
    EXPECT  SLOTREF_RESULT, IRON_PICKAXE, 1, 0
    EXPECT  0, IRON_INGOT, 1, 0
    EXPECT  1, STICK, 1, 0
    SETS_EQ 1                           ; the grid counts as stock: 1 + 3 ingots, 1 + 2 sticks
    FILL_EQ 1, 1                        ; filling again returns the grid and lays it out anew
    EXPECT  CELL(0), IRON_INGOT, 1, 0
    EXPECT  CELL(7), STICK, 1, 0
    EXPECT  SLOTREF_RESULT, IRON_PICKAXE, 1, 0
    EXPECT  0, IRON_INGOT, 1, 0
    EXPECT  1, STICK, 1, 0
    ; too little of one ingredient: no sets, and a refused fill moves nothing
    call    inv_clear
    SET     0, IRON_INGOT, 2, 0
    SET     1, STICK, 5, 0
    SETS_EQ 0
    FILL_EQ 1, 0
    EXPECT  0, IRON_INGOT, 2, 0
    EXPECT  1, STICK, 5, 0
    EXPECT  CELL(0), 0, 0, 0
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    ; 7 ingots (2 sets) and 9 sticks (4 sets): max_sets 64 gives the 2 the ingots allow
    call    inv_clear
    SET     0, IRON_INGOT, 7, 0
    SET     1, STICK, 9, 0
    SETS_EQ 2
    FILL_EQ 64, 2
    EXPECT  CELL(0), IRON_INGOT, 2, 0
    EXPECT  CELL(4), STICK, 2, 0
    EXPECT  SLOTREF_RESULT, IRON_PICKAXE, 1, 0
    EXPECT  0, IRON_INGOT, 1, 0
    EXPECT  1, STICK, 5, 0
    ; the pistol uses 2 ingots and a plank: 5 ingots and 1 plank are 1 set, with 4 planks 2
    call    inv_clear
    SET     0, IRON_INGOT, 5, 0
    SET     1, PLANKS, 1, 0
    FIND    PISTOL
    SETS_EQ 1
    SET     1, PLANKS, 4, 0
    SETS_EQ 2
    ; 10 logs: every log goes into the one cell, the result is the single craft's planks
    call    inv_clear
    SET     0, LOG, 10, 0
    FIND    PLANKS
    SETS_EQ 10
    FILL_EQ 64, 10
    EXPECT  CELL(0), LOG, 10, 0
    EXPECT  SLOTREF_RESULT, PLANKS, 4, 0
    EXPECT  0, 0, 0, 0
    ; a cell holds one stack: 150 logs are capped at 64 sets
    call    inv_clear
    SET     0, LOG, 64, 0
    SET     1, LOG, 64, 0
    SET     2, LOG, 22, 0
    SETS_EQ 64
    FILL_EQ 64, 64
    EXPECT  CELL(0), LOG, 64, 0
    EXPECT  0, 0, 0, 0
    EXPECT  1, LOG, 64, 0
    EXPECT  2, LOG, 22, 0
    ; a stray stack in the grid goes back to the inventory; grid items count as stock
    call    inv_clear
    SET     0, LOG, 3, 0
    SET     CELL(4), DIRT, 5, 0
    FILL_EQ 1, 1
    EXPECT  CELL(0), LOG, 1, 0
    EXPECT  CELL(4), 0, 0, 0
    mov     edi, DIRT
    call    inv_count
    cmp     eax, 5
    jne     .fail
    call    inv_clear
    SET     CELL(0), LOG, 3, 0
    SETS_EQ 3
    FILL_EQ 64, 3
    EXPECT  CELL(0), LOG, 3, 0
    ; an ingredient that does not stack keeps its wear, and caps the sets at 1
    call    inv_clear
    SET     0, IRON_INGOT, 5, 0
    SET     1, FLINT_AND_STEEL, 1, 7
    SET     2, LOG, 3, 0
    SET     3, FLINT_AND_STEEL, 1, 40
    FIND    MUSKET
    SETS_EQ 1
    FILL_EQ 64, 1
    EXPECT  CELL(2), IRON_INGOT, 1, 0
    EXPECT  CELL(4), IRON_INGOT, 1, 0
    EXPECT  CELL(5), FLINT_AND_STEEL, 1, 7
    EXPECT  CELL(6), LOG, 1, 0
    EXPECT  SLOTREF_RESULT, MUSKET, 1, 0
    EXPECT  0, IRON_INGOT, 3, 0
    EXPECT  1, 0, 0, 0
    EXPECT  2, LOG, 2, 0
    EXPECT  3, FLINT_AND_STEEL, 1, 40
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    inv_clear
    mov     dword [craft_size], 2
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

test_recipe_fits_grid:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    TEST_INIT                           ; the 2x2 inventory grid
    FIND    CRAFTING_TABLE
    FITS_EQ 1
    FIND    IRON_PICKAXE
    FITS_EQ 0
    FIND    PLANK_SLAB                  ; 3 wide
    FITS_EQ 0
    FIND    TORCH                       ; 1x2
    FITS_EQ 1
    ; the pickaxe does not fit: fill is refused and the grid is left alone
    SET     0, IRON_INGOT, 3, 0
    SET     1, STICK, 2, 0
    SET     CELL(0), DIRT, 2, 0
    FIND    IRON_PICKAXE
    FILL_EQ 1, 0
    EXPECT  CELL(0), DIRT, 2, 0
    EXPECT  0, IRON_INGOT, 3, 0
    EXPECT  1, STICK, 2, 0
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    ; a 2x2 recipe is laid out on the 2x2 cells (0, 1, 3, 4)
    call    inv_clear
    SET     0, STONE, 9, 0
    FIND    STONE_BRICK
    FITS_EQ 1
    FILL_EQ 64, 2
    EXPECT  CELL(0), STONE, 2, 0
    EXPECT  CELL(1), STONE, 2, 0
    EXPECT  CELL(2), 0, 0, 0
    EXPECT  CELL(3), STONE, 2, 0
    EXPECT  CELL(4), STONE, 2, 0
    EXPECT  SLOTREF_RESULT, STONE_BRICK, 4, 0
    EXPECT  0, STONE, 1, 0
    ; at the crafting table the pickaxe fits and the same fill works
    call    inv_clear
    mov     dword [craft_size], 3
    SET     0, IRON_INGOT, 3, 0
    SET     1, STICK, 2, 0
    FIND    IRON_PICKAXE
    FITS_EQ 1
    FILL_EQ 1, 1
    EXPECT  SLOTREF_RESULT, IRON_PICKAXE, 1, 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    inv_clear
    mov     dword [craft_size], 2
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

test_furnace_book_fill:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    TEST_INIT
    call    zero_conts
    mov     qword [inv_container], 0
    ; no container open: nothing moves
    SET     0, IRON_ORE, 5, 0
    CFILL   0, IRON_ORE, 0
    EXPECT  0, IRON_ORE, 5, 0
    MAKE_CONT 6, 11, 5, FURNACE, CONT_FURNACE
    test    rax, rax
    jz      .fail
    mov     [inv_container], rax
    ; 70 ore: a full stack goes into the input cell, 6 stay
    SET     0, IRON_ORE, 64, 0
    SET     1, IRON_ORE, 6, 0
    CFILL   0, IRON_ORE, 64
    CEXPECT 0, IRON_ORE, 64, 0
    EXPECT  0, 0, 0, 0
    EXPECT  1, IRON_ORE, 6, 0
    CFILL   0, IRON_ORE, 0              ; the cell is full
    CFILL   0, COAL, 0                  ; and holds another item
    EXPECT  1, IRON_ORE, 6, 0
    ; fuel: the fuel cell takes the coal
    SET     2, COAL, 5, 0
    CFILL   1, COAL, 5
    CEXPECT 1, COAL, 5, 0
    EXPECT  2, 0, 0, 0
    ; topping up moves only what the stack has room for
    SET     3, COAL, 64, 0
    SET     4, COAL, 10, 0
    CFILL   1, COAL, 59
    CEXPECT 1, COAL, 64, 0
    EXPECT  3, COAL, 5, 0
    EXPECT  4, COAL, 10, 0
    ; nothing of the item in the inventory, and a furnace has three cells
    CFILL   2, GOLD_ORE, 0
    CEXPECT 2, 0, 0, 0
    CFILL   3, COAL, 0
    ; a cell holding another item is left alone even when it has room
    CSET    2, IRON_INGOT, 3, 0
    SET     8, COAL, 4, 0
    CFILL   2, COAL, 0
    CEXPECT 2, IRON_INGOT, 3, 0
    EXPECT  8, COAL, 4, 0
    CSET    2, 0, 0, 0
    SET     8, 0, 0, 0
    ; a wooden tool burns as fuel and moves with its wear; a second one finds the cell taken
    CSET    1, 0, 0, 0
    SET     5, WOOD_PICKAXE, 1, 20
    SET     6, WOOD_PICKAXE, 1, 3
    CFILL   1, WOOD_PICKAXE, 1
    CEXPECT 1, WOOD_PICKAXE, 1, 20
    EXPECT  5, 0, 0, 0
    CFILL   1, WOOD_PICKAXE, 0
    EXPECT  6, WOOD_PICKAXE, 1, 3
    ; a chest has 27 cells and no input rule
    MAKE_CONT 5, 11, 5, CHEST, CONT_CHEST
    test    rax, rax
    jz      .fail
    mov     [inv_container], rax
    SET     7, DIRT, 3, 0
    CFILL   27, DIRT, 0
    CFILL   26, DIRT, 3
    CEXPECT 26, DIRT, 3, 0
    EXPECT  7, 0, 0, 0
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    mov     ebx, eax
    call    inv_clear
    mov     qword [inv_container], 0
    call    zero_conts
    mov     eax, ebx
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- 0.9 block and item tables ---------------------------------------------------------
; BROW id, flags, shape, top, side, bottom, tool, drop, max stack, hardness
%macro BROW 10
    db %1, %2, %3, %4, %5, %6, %7, %8, %9
    dd %10
%endmacro
%define BROW_SIZE 13

section .rodata
new_block_rows:
    BROW WATER,        FLAG_TRANSLUCENT, SHAPE_LIQUID, TILE_WATER, TILE_WATER, TILE_WATER, 0, 0, 0, -1.0
    BROW ICE,          FLAG_SOLID | FLAG_TRANSLUCENT, SHAPE_CUBE, TILE_ICE, TILE_ICE, TILE_ICE, TOOL_PICKAXE, 0, 64, 0.5
    BROW SNOW_LAYER,   0, SHAPE_SNOW, TILE_SNOW, TILE_SNOW, TILE_SNOW, 0, 0, 0, 0.1
    BROW SNOW_BLOCK,   FLAG_SOLID | FLAG_OPAQUE, SHAPE_CUBE, TILE_SNOW, TILE_SNOW, TILE_SNOW, TOOL_SHOVEL, SNOW_BLOCK, 64, 0.4
    BROW MUD,          FLAG_SOLID | FLAG_OPAQUE, SHAPE_CUBE, TILE_MUD, TILE_MUD, TILE_MUD, TOOL_SHOVEL, MUD, 64, 0.6
    BROW TALL_GRASS,   0, SHAPE_CROSS, TILE_TALL_GRASS, TILE_TALL_GRASS, TILE_TALL_GRASS, 0, 0, 0, 0.0
    BROW CACTUS,       FLAG_SOLID, SHAPE_CACTUS, TILE_CACTUS_TOP, TILE_CACTUS_SIDE, TILE_CACTUS_TOP, 0, CACTUS, 64, 0.4
    BROW PINE_LOG,     FLAG_SOLID | FLAG_OPAQUE, SHAPE_CUBE, TILE_PINE_LOG_TOP, TILE_PINE_LOG, TILE_PINE_LOG_TOP, TOOL_AXE, PINE_LOG, 64, 2.0
    BROW PINE_LEAVES,  FLAG_SOLID, SHAPE_CUBE, TILE_PINE_LEAVES, TILE_PINE_LEAVES, TILE_PINE_LEAVES, 0, 0, 64, 0.2
    BROW BIRCH_LOG,    FLAG_SOLID | FLAG_OPAQUE, SHAPE_CUBE, 7, TILE_BIRCH_LOG, 7, TOOL_AXE, BIRCH_LOG, 64, 2.0
    BROW BIRCH_LEAVES, FLAG_SOLID, SHAPE_CUBE, TILE_BIRCH_LEAVES, TILE_BIRCH_LEAVES, TILE_BIRCH_LEAVES, 0, 0, 64, 0.2
    BROW BED + 0,      FLAG_SOLID, SHAPE_BED, TILE_BED_FOOT_TOP, TILE_BED_FOOT_SIDE, 5, 0, BED, 1, 0.2
    BROW BED + 1,      FLAG_SOLID, SHAPE_BED, TILE_BED_FOOT_TOP, TILE_BED_FOOT_SIDE, 5, 0, BED, 0, 0.2
    BROW BED + 2,      FLAG_SOLID, SHAPE_BED, TILE_BED_FOOT_TOP, TILE_BED_FOOT_SIDE, 5, 0, BED, 0, 0.2
    BROW BED + 3,      FLAG_SOLID, SHAPE_BED, TILE_BED_FOOT_TOP, TILE_BED_FOOT_SIDE, 5, 0, BED, 0, 0.2
    BROW BED + 4,      FLAG_SOLID, SHAPE_BED, TILE_BED_HEAD_TOP, TILE_BED_HEAD_SIDE, 5, 0, BED, 0, 0.2
    BROW BED + 5,      FLAG_SOLID, SHAPE_BED, TILE_BED_HEAD_TOP, TILE_BED_HEAD_SIDE, 5, 0, BED, 0, 0.2
    BROW BED + 6,      FLAG_SOLID, SHAPE_BED, TILE_BED_HEAD_TOP, TILE_BED_HEAD_SIDE, 5, 0, BED, 0, 0.2
    BROW BED + 7,      FLAG_SOLID, SHAPE_BED, TILE_BED_HEAD_TOP, TILE_BED_HEAD_SIDE, 5, 0, BED, 0, 0.2
new_block_rows_end:

nm_bed:     db "Bed", 0
nm_boat:    db "Boat", 0
nm_plog:    db "Pine Log", 0
nm_blog:    db "Birch Log", 0
nm_snowblk: db "Snow Block", 0
nm_mud:     db "Mud", 0
nm_cactus:  db "Cactus", 0
nm_ice:     db "Ice", 0
; id byte, then the name pointer table index
name_rows:
    db BED
    dq nm_bed
    db BOAT
    dq nm_boat
    db PINE_LOG
    dq nm_plog
    db BIRCH_LOG
    dq nm_blog
    db SNOW_BLOCK
    dq nm_snowblk
    db MUD
    dq nm_mud
    db CACTUS
    dq nm_cactus
    db ICE
    dq nm_ice
name_rows_end:

section .text

; nb_streq(rdi a, rsi b) -> eax 1 when the C strings are equal
nb_streq:
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

; test_new_blocks_tables() -> eax 0 pass
;   every 0.9 block row (ids 111..129) matches the plan's table: flags, shape, tiles, tool,
;   drop, item max stack and hardness; the new item names, icons and BOAT's stack size
test_new_blocks_tables:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    TEST_INIT
    lea     rbx, [new_block_rows]
.row:
    movzx   ecx, byte [rbx]
    lea     rdx, [block_flags]
    mov     al, [rdx + rcx]
    cmp     al, [rbx + 1]
    jne     .fail
    lea     rdx, [block_shape]
    mov     al, [rdx + rcx]
    cmp     al, [rbx + 2]
    jne     .fail
    lea     rdx, [block_tiles]
    lea     rsi, [rcx + rcx*2]
    movzx   eax, word [rdx + rsi*2]
    movzx   r8d, byte [rbx + 3]
    cmp     eax, r8d
    jne     .fail
    movzx   eax, word [rdx + rsi*2 + 2]
    movzx   r8d, byte [rbx + 4]
    cmp     eax, r8d
    jne     .fail
    movzx   eax, word [rdx + rsi*2 + 4]
    movzx   r8d, byte [rbx + 5]
    cmp     eax, r8d
    jne     .fail
    lea     rdx, [block_tool]
    mov     al, [rdx + rcx]
    cmp     al, [rbx + 6]
    jne     .fail
    lea     rdx, [block_drop]
    mov     al, [rdx + rcx]
    cmp     al, [rbx + 7]
    jne     .fail
    lea     rdx, [item_max_stack]
    mov     al, [rdx + rcx]
    cmp     al, [rbx + 8]
    jne     .fail
    lea     rdx, [block_hardness]
    movss   xmm0, [rdx + rcx*4]
    ucomiss xmm0, [rbx + 9]
    jne     .fail
    jp      .fail
    add     rbx, BROW_SIZE
    lea     rax, [new_block_rows_end]
    cmp     rbx, rax
    jb      .row
    ; variant bases: the bed is one group, ICE/SNOW_BLOCK/MUD/CACTUS/logs/leaves are own items
    movzx   eax, byte [block_base + BED + 6]
    cmp     eax, BED
    jne     .fail
    movzx   eax, byte [block_base + BED]
    cmp     eax, BED
    jne     .fail
    movzx   eax, byte [block_base + BIRCH_LEAVES]
    cmp     eax, BIRCH_LEAVES
    jne     .fail
    ; items: BOAT stacks to 1, icons, names
    movzx   eax, byte [item_max_stack + BOAT]
    cmp     eax, 1
    jne     .fail
    movzx   eax, word [item_icon + BED*2]
    cmp     eax, TILE_ICON_BED
    jne     .fail
    movzx   eax, word [item_icon + BOAT*2]
    cmp     eax, TILE_ICON_BOAT
    jne     .fail
    lea     rbx, [name_rows]
.name:
    movzx   ecx, byte [rbx]
    lea     rdx, [item_names]
    mov     rdi, [rdx + rcx*8]
    mov     rsi, [rbx + 1]
    call    nb_streq
    test    eax, eax
    jz      .fail
    add     rbx, 9
    lea     rax, [name_rows_end]
    cmp     rbx, rax
    jb      .name
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r12
    pop     rbx
    pop     rbp
    ret

section .rodata
; the 22 tiles 0.10 draws: shrine top and side, then the faction skins 304..323
art_tiles:
    dw TILE_SHRINE_TOP, TILE_SHRINE_SIDE
%assign art_i 0
%rep 20
    dw TILE_FOLK0 + art_i
%assign art_i art_i + 1
%endrep
art_tiles_end:
nm_shrine:  db "Shrine", 0
t_minus_one: dd -1.0

section .bss
align 16
art_atlas: resb ATLAS_W * ATLAS_H * 4

section .text

; test_shrine_block_tables() -> eax 0 pass
;   SHRINE .. SHRINE + 4: flags solid + opaque, tiles (TILE_SHRINE_TOP, TILE_SHRINE_SIDE,
;   TILE_STONE_BRICK), hardness -1, no drop, variant base SHRINE, light 10, no item form (stack 0,
;   icon 0), the name "Shrine", right-clickable; SHRINE + 5 is not a block. The atlas draws the 22
;   0.10 tiles (228, 229, 304..323) fully opaque with no black pixel (a bitmap char missing from
;   its palette would leave a transparent or black one).
test_shrine_block_tables:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    TEST_INIT
    mov     ebx, SHRINE
.block:
    lea     rdx, [block_flags]
    movzx   eax, byte [rdx + rbx]
    cmp     eax, FLAG_SOLID | FLAG_OPAQUE
    jne     .fail
    lea     rdx, [block_tiles]
    lea     rsi, [rbx + rbx*2]
    movzx   eax, word [rdx + rsi*2]
    cmp     eax, TILE_SHRINE_TOP
    jne     .fail
    movzx   eax, word [rdx + rsi*2 + 2]
    cmp     eax, TILE_SHRINE_SIDE
    jne     .fail
    movzx   eax, word [rdx + rsi*2 + 4]
    cmp     eax, TILE_STONE_BRICK
    jne     .fail
    lea     rdx, [block_hardness]
    movss   xmm0, [rdx + rbx*4]
    ucomiss xmm0, [t_minus_one]
    jne     .fail
    jp      .fail
    cmp     byte [block_drop + rbx], 0
    jne     .fail
    movzx   eax, byte [block_base + rbx]
    cmp     eax, SHRINE
    jne     .fail
    cmp     byte [block_light + rbx], 10
    jne     .fail
    cmp     byte [item_max_stack + rbx], 0
    jne     .fail
    cmp     word [item_icon + rbx*2], 0
    jne     .fail
    lea     rdx, [item_names]
    mov     rdi, [rdx + rbx*8]
    lea     rsi, [nm_shrine]
    call    nb_streq
    test    eax, eax
    jz      .fail
    mov     edi, ebx
    call    block_is_usable
    cmp     eax, 1
    jne     .fail
    inc     ebx
    cmp     ebx, SHRINE + 5
    jb      .block
    mov     edi, NUM_BLOCKS                 ; past the group: not a block, not usable
    call    block_is_usable
    test    eax, eax
    jnz     .fail
    ; the atlas: every pixel of the new tiles is opaque and not black
    lea     rdi, [art_atlas]
    call    texgen_build
    lea     rbx, [art_tiles]
.tile:
    movzx   eax, word [rbx]
    mov     ecx, eax
    shr     ecx, 4
    shl     ecx, 12                         ; row * 16 px * 256 px per row
    and     eax, 15
    shl     eax, 4
    add     eax, ecx                        ; the tile's first pixel
    lea     r12, [art_atlas]
    lea     r12, [r12 + rax*4]
    xor     ecx, ecx                        ; py
.py:
    xor     edx, edx                        ; px
.px:
    mov     eax, ecx
    shl     eax, 8
    add     eax, edx
    mov     eax, [r12 + rax*4]
    cmp     eax, 0xFF000000
    jbe     .fail                           ; alpha < 255 or rgb == 0
    inc     edx
    cmp     edx, 16
    jb      .px
    inc     ecx
    cmp     ecx, 16
    jb      .py
    add     rbx, 2
    lea     rax, [art_tiles_end]
    cmp     rbx, rax
    jb      .tile
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r12
    pop     rbx
    pop     rbp
    ret

section .rodata
; the Contracts rows of DRY_GRASS and LAVA (0.10.1 terrain), 40 bytes each:
;   +0 name ptr, +8 id, +12 hardness, +16 tiles top/side/bottom (words), +24 flags, tool, harvest
;   level, drop, dig sound, step sound, flammable, shape, block_base, light, item_icon,
;   item_max_stack (12 bytes)
%define TB_ROW 40
tb_rows:
    dq tb_nm_dry
    dd DRY_GRASS
    dd 0.6
    dw TILE_DRY_GRASS_TOP, TILE_DRY_GRASS_SIDE, 3, 0
    db FLAG_SOLID | FLAG_OPAQUE, TOOL_SHOVEL, 0, DIRT, SND_DIG_SOFT, SND_STEP_SOFT, 0, SHAPE_CUBE
    db 0, 0, 0, 0
    times 4 db 0
    dq tb_nm_lava
    dd LAVA
    dd -1.0
    dw TILE_LAVA, TILE_LAVA, TILE_LAVA, 0
    db FLAG_TRANSLUCENT, 0, 0, 0, 0, 0, 0, SHAPE_LIQUID
    db 0, 15, 0, 0
    times 4 db 0
tb_rows_end:
tb_nm_dry:  db "Dry Grass", 0
tb_nm_lava: db "Lava", 0
; the 3 tiles 0.10.1 draws
tb_tiles:
    dw TILE_DRY_GRASS_TOP, TILE_DRY_GRASS_SIDE, TILE_LAVA
tb_tiles_end:

section .text

; test_terrain_blocks_tables() -> eax 0 pass
;   DRY_GRASS (135) and LAVA (136) match the Contracts rows field by field: flags, tile words,
;   hardness, tool, harvest level, drop, dig/step sound, flammable, shape, block_base, light (LAVA
;   15), item name, item icon and max stack (no item form). The atlas draws tiles 324..326 fully
;   opaque with no black pixel.
test_terrain_blocks_tables:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    lea     r12, [tb_rows]
.row:
    mov     ebx, [r12 + 8]
    movzx   eax, byte [block_flags + rbx]
    cmp     al, [r12 + 24]
    jne     .fail
    movzx   eax, byte [block_tool + rbx]
    cmp     al, [r12 + 25]
    jne     .fail
    movzx   eax, byte [block_harvest_level + rbx]
    cmp     al, [r12 + 26]
    jne     .fail
    movzx   eax, byte [block_drop + rbx]
    cmp     al, [r12 + 27]
    jne     .fail
    movzx   eax, byte [block_dig_sound + rbx]
    cmp     al, [r12 + 28]
    jne     .fail
    movzx   eax, byte [block_step_sound + rbx]
    cmp     al, [r12 + 29]
    jne     .fail
    movzx   eax, byte [block_flammable + rbx]
    cmp     al, [r12 + 30]
    jne     .fail
    movzx   eax, byte [block_shape + rbx]
    cmp     al, [r12 + 31]
    jne     .fail
    movzx   eax, byte [block_base + rbx]
    cmp     al, [r12 + 32]
    jne     .fail
    movzx   eax, byte [block_light + rbx]
    cmp     al, [r12 + 33]
    jne     .fail
    movzx   eax, word [item_icon + rbx*2]
    movzx   ecx, byte [r12 + 34]
    cmp     eax, ecx
    jne     .fail
    movzx   eax, byte [item_max_stack + rbx]
    cmp     al, [r12 + 35]
    jne     .fail
    movss   xmm0, [block_hardness + rbx*4]
    ucomiss xmm0, [r12 + 12]
    jne     .fail
    jp      .fail
    lea     rsi, [rbx + rbx*2]
    movzx   eax, word [block_tiles + rsi*2]
    cmp     ax, [r12 + 16]
    jne     .fail
    movzx   eax, word [block_tiles + rsi*2 + 2]
    cmp     ax, [r12 + 18]
    jne     .fail
    movzx   eax, word [block_tiles + rsi*2 + 4]
    cmp     ax, [r12 + 20]
    jne     .fail
    lea     rdx, [item_names]
    mov     rdi, [rdx + rbx*8]
    mov     rsi, [r12]
    call    nb_streq
    test    eax, eax
    jz      .fail
    add     r12, TB_ROW
    lea     rax, [tb_rows_end]
    cmp     r12, rax
    jb      .row
    ; the atlas: every pixel of tiles 324..326 is opaque and not black
    lea     rdi, [art_atlas]
    call    texgen_build
    lea     rbx, [tb_tiles]
.tile:
    movzx   eax, word [rbx]
    mov     ecx, eax
    shr     ecx, 4
    shl     ecx, 12                         ; row * 16 px * 256 px per row
    and     eax, 15
    shl     eax, 4
    add     eax, ecx                        ; the tile's first pixel
    lea     r12, [art_atlas]
    lea     r12, [r12 + rax*4]
    xor     ecx, ecx                        ; py
.py:
    xor     edx, edx                        ; px
.px:
    mov     eax, ecx
    shl     eax, 8
    add     eax, edx
    mov     eax, [r12 + rax*4]
    cmp     eax, 0xFF000000
    jbe     .fail                           ; alpha < 255 or rgb == 0
    inc     edx
    cmp     edx, 16
    jb      .px
    inc     ecx
    cmp     ecx, 16
    jb      .py
    add     rbx, 2
    lea     rax, [tb_tiles_end]
    cmp     rbx, rax
    jb      .tile
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gt_pixel(eax tile, ecx x, edx y) -> eax the RGBA dword of texel (x, y) of that tile in art_atlas.
; Clobbers ecx, edx, esi.
gt_pixel:
    mov     esi, eax
    shr     eax, 4
    shl     eax, 4
    add     eax, edx                    ; atlas row = (tile >> 4) * 16 + y
    shl     eax, 8                      ; * ATLAS_W
    and     esi, 15
    shl     esi, 4
    add     eax, esi
    add     eax, ecx                    ; + atlas column = (tile & 15) * 16 + x
    lea     rsi, [art_atlas]
    mov     eax, [rsi + rax*4]
    ret

; test_grimoire_tiles() -> eax 0 pass
;   The 0.10.2 art in the atlas texgen_build draws: each of the 16 9-slice tiles TILE_NINE0 + 0..15
;   (NINE_PAGE .. NINE_NODE_PATH) has an opaque rim pixel at texel (0, 7) (the left edge, half way
;   down), except NINE_RIBBON, whose left end is a swallowtail notch: there (0, 7) is transparent and
;   the opaque rim pixel is (7, 0) on the top edge instead. The silhouette block TILE_SIL0 has a
;   C_INK pixel at local (24, 3), the top of the head outline: sub-tile row 0, column 1, texel (8, 3).
test_grimoire_tiles:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    lea     rdi, [art_atlas]
    call    texgen_build
    xor     ebx, ebx                    ; NINE_* kind
.kind:
    lea     eax, [rbx + TILE_NINE0]
    xor     ecx, ecx                    ; texel (0, 7)
    mov     edx, 7
    cmp     ebx, NINE_RIBBON
    jne     .have_xy
    mov     ecx, 7                      ; the ribbon: texel (7, 0)
    xor     edx, edx
.have_xy:
    call    gt_pixel
    shr     eax, 24                     ; alpha
    cmp     eax, 255
    jne     .fail
    inc     ebx
    cmp     ebx, 16
    jb      .kind
    mov     eax, TILE_NINE0 + NINE_RIBBON ; the swallowtail notch: transparent at (0, 7)
    xor     ecx, ecx
    mov     edx, 7
    call    gt_pixel
    test    eax, 0xFF000000
    jnz     .fail
    mov     eax, TILE_SIL0 + 1          ; the head outline: local (24, 3) = sub-tile column 1, texel (8, 3)
    mov     ecx, 8
    mov     edx, 3
    call    gt_pixel
    cmp     eax, C_INK
    jne     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- fitting an attachment onto a firearm ------------------------------------------------------

; FITS gun id, gun dmg, attachment id, grid cell of the gun, grid cell of the attachment, expected
; result dmg (-1: no result): the two stacks alone in the grid, craft_update
%macro FITS 6
    CLEAR_GRID
    SET     CELL(%4), %1, 1, %2
    SET     CELL(%5), %3, 1, 0
    call    craft_update
%if (%6) < 0
    EXPECT  SLOTREF_RESULT, 0, 0, 0
%else
    EXPECT  SLOTREF_RESULT, %1, 1, %6
%endif
%endmacro

; An attachment fits onto a firearm when the grid holds exactly those two stacks (any cells of the
; active grid, either order) and the firearm does not carry it yet: the result is the firearm with
; its dmg word | the attachment's bit (the rounds loaded stay), taking it (click or shift-click)
; consumes both. Nothing fits otherwise; a stack outside the active 2x2 grid is not seen.
test_attach_craft:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    TEST_INIT
    ; the 2x2 grid: the pistol with 5 rounds and a scope, either way round
    FITS    PISTOL, 5, SCOPE, 0, 1, ATT_SCOPE | 5
    FITS    PISTOL, 5, SCOPE, 4, 3, ATT_SCOPE | 5
    FITS    PISTOL, 5, EXTENDED_MAG, 0, 3, ATT_EXTMAG | 5
    FITS    PISTOL, 5, RIFLED_BARREL, 1, 4, ATT_RIFLED | 5
    FITS    PISTOL, 5, COMPENSATOR, 3, 0, ATT_COMP | 5
    ; any other firearm: the bits are kept apart
    FITS    KALASHNIKOV, ATT_COMP | 30, SCOPE, 0, 1, ATT_COMP | ATT_SCOPE | 30
    FITS    HUNTING_RIFLE, ATT_EXTMAG | ATT_SCOPE | ATT_RIFLED, COMPENSATOR, 0, 1, ATT_EXTMAG | ATT_SCOPE | ATT_RIFLED | ATT_COMP
    ; the 3x3 grid, cells far apart
    mov     dword [craft_size], 3
    FITS    ROCKET_LAUNCHER, 1, SCOPE, 0, 8, ATT_SCOPE | 1
    FITS    REVOLVER, 0, COMPENSATOR, 8, 2, ATT_COMP
    ; nothing fits: the attachment is on the firearm already, a third stack, two attachments, two
    ; firearms, a firearm or an attachment alone, something else beside a firearm
    FITS    PISTOL, ATT_SCOPE | 5, SCOPE, 0, 1, -1
    FITS    PISTOL, ATT_COMP | ATT_SCOPE | 5, COMPENSATOR, 0, 1, -1
    FITS    SCOPE, 0, COMPENSATOR, 0, 1, -1
    FITS    PISTOL, 5, MUSKET, 0, 1, -1
    FITS    PISTOL, 5, STICK, 0, 1, -1
    FITS    STICK, 0, SCOPE, 0, 1, -1
    FITS    PISTOL, 5, PISTOL_ROUND, 0, 1, -1
    CLEAR_GRID
    SET     CELL(0), PISTOL, 1, 5
    call    craft_update
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    SET     CELL(1), SCOPE, 1, 0
    SET     CELL(4), STICK, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, 0, 0, 0         ; a third stack spoils it, wherever it is
    CLEAR_GRID
    SET     CELL(0), PISTOL, 1, 5
    SET     CELL(1), STICK, 1, 0
    SET     CELL(4), SCOPE, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    CLEAR_GRID
    SET     CELL(0), STICK, 1, 0
    SET     CELL(1), PISTOL, 1, 5
    SET     CELL(4), SCOPE, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    CLEAR_GRID
    SET     CELL(0), SCOPE, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    ; a stack outside the active 2x2 grid is not seen: the scope is alone in it
    mov     dword [craft_size], 2
    FITS    PISTOL, 5, SCOPE, 2, 0, -1
    FITS    PISTOL, 5, SCOPE, 6, 0, -1
    ; taking the result with a click: the cursor holds the fitted pistol, both stacks are used up
    FITS    PISTOL, 5, SCOPE, 0, 1, ATT_SCOPE | 5
    CLICK   SLOTREF_RESULT, 0, 0
    EXPECT  CURSOR, PISTOL, 1, ATT_SCOPE | 5
    EXPECT  CELL(0), 0, 0, 0
    EXPECT  CELL(1), 0, 0, 0
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    ; shift-click: it goes straight into the inventory with its word, and a stack of three scopes
    ; keeps two
    mov     dword [inv + INVENTORY.cursor], 0
    CLEAR_GRID
    SET     CELL(0), PISTOL, 1, 7
    SET     CELL(1), SCOPE, 3, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, PISTOL, 1, ATT_SCOPE | 7
    CLICK   SLOTREF_RESULT, 0, 1
    EXPECT  0, PISTOL, 1, ATT_SCOPE | 7
    EXPECT  CELL(0), 0, 0, 0
    EXPECT  CELL(1), SCOPE, 2, 0
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    ; with one stack of each the shift-click leaves the grid empty (the next free slot takes the gun)
    CLEAR_GRID
    SET     CELL(3), PISTOL, 1, 9
    SET     CELL(4), COMPENSATOR, 1, 0
    call    craft_update
    EXPECT  SLOTREF_RESULT, PISTOL, 1, ATT_COMP | 9
    CLICK   SLOTREF_RESULT, 0, 1
    EXPECT  1, PISTOL, 1, ATT_COMP | 9
    EXPECT  CELL(3), 0, 0, 0
    EXPECT  CELL(4), 0, 0, 0
    EXPECT  SLOTREF_RESULT, 0, 0, 0
    xor     ebx, ebx
    jmp     .out
.fail:
    mov     ebx, 1
.out:
    call    inv_clear
    mov     dword [craft_size], 2
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
