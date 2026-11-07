; itemdefs.asm - per-item data tables, indexed by item id 0..42 (NUM_ITEMS).
; Ids 0..12 are the blocks, 13..31 are unused, 32..42 are tools/materials/food.
%include "common.inc"
default rel

global item_names, item_icon, item_max_stack, item_tool, item_tier
global item_durability, item_food, item_saturation, item_attack

section .rodata
n_air:      db "Air", 0
n_stone:    db "Stone", 0
n_grass:    db "Grass", 0
n_dirt:     db "Dirt", 0
n_cobble:   db "Cobblestone", 0
n_planks:   db "Planks", 0
n_log:      db "Log", 0
n_leaves:   db "Leaves", 0
n_sand:     db "Sand", 0
n_glass:    db "Glass", 0
n_brick:    db "Bricks", 0
n_bedrock:  db "Bedrock", 0
n_table:    db "Crafting Table", 0
n_unused:   db "?", 0
n_stick:    db "Stick", 0
n_wpick:    db "Wooden Pickaxe", 0
n_waxe:     db "Wooden Axe", 0
n_wshovel:  db "Wooden Shovel", 0
n_wsword:   db "Wooden Sword", 0
n_spick:    db "Stone Pickaxe", 0
n_saxe:     db "Stone Axe", 0
n_sshovel:  db "Stone Shovel", 0
n_ssword:   db "Stone Sword", 0
n_apple:    db "Apple", 0
n_pork:     db "Raw Porkchop", 0

align 8
item_names:
    dq n_air, n_stone, n_grass, n_dirt, n_cobble, n_planks, n_log, n_leaves
    dq n_sand, n_glass, n_brick, n_bedrock, n_table
    times 19 dq n_unused                ; 13..31
    dq n_stick, n_wpick, n_waxe, n_wshovel, n_wsword
    dq n_spick, n_saxe, n_sshovel, n_ssword, n_apple, n_pork

; atlas tile of the inventory icon: block side tile, or the item id itself
item_icon:
    db 0, 0, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, TILE_TABLE_SIDE
    times 19 db 0
    db 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42

item_max_stack:
    db 0
    times 12 db 64
    times 19 db 0
    db 64                               ; stick
    times 8 db 1                        ; tools
    db 64, 64                           ; apple, porkchop

item_tool:
    times 33 db 0
    db TOOL_PICKAXE, TOOL_AXE, TOOL_SHOVEL, TOOL_SWORD
    db TOOL_PICKAXE, TOOL_AXE, TOOL_SHOVEL, TOOL_SWORD
    db 0, 0

item_tier:
    times 33 db 0
    times 4 db TIER_WOOD
    times 4 db TIER_STONE
    db 0, 0

item_food:
    times 41 db 0
    db 4, 3                             ; apple, porkchop

item_attack:
    times 33 db 1
    db 3, 4, 2, 5                       ; wood pickaxe, axe, shovel, sword
    db 4, 5, 3, 6                       ; stone pickaxe, axe, shovel, sword
    db 1, 1

align 2
item_durability:
    times 33 dw 0
    times 4 dw 59
    times 4 dw 131
    dw 0, 0

align 4
item_saturation:
    times 41 dd 0.0
    dd 2.4, 1.8
