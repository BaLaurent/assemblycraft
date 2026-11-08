; test_items.asm - inventory, crafting and tool-rule tests.
%include "common.inc"
default rel

global test_inv_add_merges, test_inv_right_click_split, test_craft_planks_from_log
global test_craft_tool_shapes, test_craft_shift_click_all, test_break_time_rules
global test_craft_advanced_recipes, test_break_tiers, test_inv_click_armor_containers
global test_recipe_fill_and_sets, test_recipe_fits_grid, test_furnace_book_fill

extern inv, inv_sel, craft_size, inv_container, game_mode
extern inv_count, inv_remove_one, armor_points, inv_damage_held
extern inv_clear, inv_add, inv_click, craft_update
extern recipes, recipes_end, recipe_sets, recipe_fits, recipe_fill
extern item_break_time, item_harvest_drop
extern world_clear, world_set, world_header
extern cont_create, cont_fill_from_inv

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

; zero_conts() - empties the container table in the world header
zero_conts:
    lea     rdi, [world_header + WORLDHDR.containers_v5]
    mov     ecx, MAX_CONTAINERS_V5 * CONTAINER_size
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
