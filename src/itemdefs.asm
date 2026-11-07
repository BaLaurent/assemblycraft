; itemdefs.asm - per-item data tables, indexed by item id 0..91 (NUM_ITEMS).
; Ids 0..21 are the blocks, 22..31 are unused, 32..91 are tools/materials/food/armor/firearms.
%include "common.inc"
default rel

global item_names, item_icon, item_max_stack, item_tool, item_tier
global item_durability, item_food, item_saturation, item_attack
global item_burn, item_smelt, item_armor_slot, item_armor_points

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
n_coalore:  db "Coal Ore", 0
n_ironore:  db "Iron Ore", 0
n_goldore:  db "Gold Ore", 0
n_diaore:   db "Diamond Ore", 0
n_furnace:  db "Furnace", 0
n_chest:    db "Chest", 0
n_gravel:   db "Gravel", 0
n_tnt:      db "TNT", 0
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
n_coal:     db "Coal", 0
n_iingot:   db "Iron Ingot", 0
n_gingot:   db "Gold Ingot", 0
n_diamond:  db "Diamond", 0
n_ipick:    db "Iron Pickaxe", 0
n_iaxe:     db "Iron Axe", 0
n_ishovel:  db "Iron Shovel", 0
n_isword:   db "Iron Sword", 0
n_gpick:    db "Golden Pickaxe", 0
n_gaxe:     db "Golden Axe", 0
n_gshovel:  db "Golden Shovel", 0
n_gsword:   db "Golden Sword", 0
n_dpick:    db "Diamond Pickaxe", 0
n_daxe:     db "Diamond Axe", 0
n_dshovel:  db "Diamond Shovel", 0
n_dsword:   db "Diamond Sword", 0
n_bow:      db "Bow", 0
n_arrow:    db "Arrow", 0
n_string:   db "String", 0
n_gunpow:   db "Gunpowder", 0
n_flint:    db "Flint", 0
n_fns:      db "Flint and Steel", 0
n_rotten:   db "Rotten Flesh", 0
n_cpork:    db "Cooked Porkchop", 0
n_feather:  db "Feather", 0
n_rchicken: db "Raw Chicken", 0
n_cchicken: db "Cooked Chicken", 0
n_ihelm:    db "Iron Helmet", 0
n_ichest:   db "Iron Chestplate", 0
n_ilegs:    db "Iron Leggings", 0
n_iboots:   db "Iron Boots", 0
n_ghelm:    db "Golden Helmet", 0
n_gchest:   db "Golden Chestplate", 0
n_glegs:    db "Golden Leggings", 0
n_gboots:   db "Golden Boots", 0
n_dhelm:    db "Diamond Helmet", 0
n_dchest:   db "Diamond Chestplate", 0
n_dlegs:    db "Diamond Leggings", 0
n_dboots:   db "Diamond Boots", 0
n_pistol:   db "Pistol", 0
n_musket:   db "Musket", 0
n_shotgun:  db "Shotgun", 0
n_ak:       db "Kalashnikov", 0
n_launcher: db "Rocket Launcher", 0
n_pround:   db "Pistol Round", 0
n_mball:    db "Musket Ball", 0
n_shell:    db "Shotgun Shell", 0
n_rround:   db "Rifle Round", 0
n_rocket:   db "Rocket", 0

align 8
item_names:
    dq n_air, n_stone, n_grass, n_dirt, n_cobble, n_planks, n_log, n_leaves
    dq n_sand, n_glass, n_brick, n_bedrock, n_table
    dq n_coalore, n_ironore, n_goldore, n_diaore, n_furnace, n_furnace, n_chest, n_gravel, n_tnt
    times 10 dq n_unused                ; 22..31
    dq n_stick, n_wpick, n_waxe, n_wshovel, n_wsword
    dq n_spick, n_saxe, n_sshovel, n_ssword, n_apple, n_pork
    dq n_coal, n_iingot, n_gingot, n_diamond
    dq n_ipick, n_iaxe, n_ishovel, n_isword
    dq n_gpick, n_gaxe, n_gshovel, n_gsword
    dq n_dpick, n_daxe, n_dshovel, n_dsword
    dq n_bow, n_arrow, n_string, n_gunpow, n_flint, n_fns
    dq n_rotten, n_cpork, n_feather, n_rchicken, n_cchicken
    dq n_ihelm, n_ichest, n_ilegs, n_iboots
    dq n_ghelm, n_gchest, n_glegs, n_gboots
    dq n_dhelm, n_dchest, n_dlegs, n_dboots
    dq n_pistol, n_musket, n_shotgun, n_ak, n_launcher
    dq n_pround, n_mball, n_shell, n_rround, n_rocket

; atlas tile of the inventory icon: block side tile, the item id (32..42), or
; TILE_ITEM0 + id - 43
item_icon:
    db 0, 0, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, TILE_TABLE_SIDE
    db 26, 27, 28, 29, 30, 31, 44, 45, 46
    times 10 db 0
    db 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42
%assign i 43
%rep NUM_ITEMS - 43
    db TILE_ITEM0 + i - 43
%assign i i + 1
%endrep

item_max_stack:
    db 0
    times 17 db 64                      ; blocks 1..17
    db 0                                ; FURNACE_LIT
    times 3 db 64                       ; chest, gravel, tnt
    times 10 db 0
    db 64                               ; stick
    times 8 db 1                        ; tools
    db 64, 64                           ; apple, porkchop
    times 4 db 64                       ; coal, ingots, diamond
    times 12 db 1                       ; iron/gold/diamond tools
    db 1                                ; bow
    times 4 db 64                       ; arrow, string, gunpowder, flint
    db 1                                ; flint and steel
    times 5 db 64                       ; foods, feather
    times 12 db 1                       ; armor
    times 5 db 1                        ; firearms (dmg holds the rounds loaded)
    times 5 db 64                       ; ammunition

%define TOOLS4 TOOL_PICKAXE, TOOL_AXE, TOOL_SHOVEL, TOOL_SWORD
item_tool:
    times 33 db 0
    db TOOLS4, TOOLS4                   ; wood, stone
    times 6 db 0                        ; apple .. diamond
    db TOOLS4, TOOLS4, TOOLS4           ; iron, gold, diamond
    times NUM_ITEMS - 59 db 0

item_tier:
    times 33 db 0
    times 4 db TIER_WOOD
    times 4 db TIER_STONE
    times 6 db 0
    times 4 db TIER_IRON
    times 4 db TIER_GOLD
    times 4 db TIER_DIAMOND
    times NUM_ITEMS - 59 db 0

item_food:
    times 41 db 0
    db 4, 3                             ; apple, porkchop
    times 22 db 0                       ; 43..64
    db 4, 8, 0, 2, 6                    ; rotten flesh, cooked pork, feather, raw/cooked chicken
    times 12 db 0
    times 10 db 0                       ; firearms, ammunition

item_attack:
    times 33 db 1
    db 3, 4, 2, 5                       ; wood pickaxe, axe, shovel, sword
    db 4, 5, 3, 6                       ; stone pickaxe, axe, shovel, sword
    times 6 db 1
    db 5, 6, 4, 7                       ; iron
    db 3, 4, 2, 5                       ; gold
    db 6, 7, 5, 8                       ; diamond
    times NUM_ITEMS - 59 db 1

; smelting result of an input item, or 0 (entries in ascending id order)
%macro SMELT 2                          ; input id, result id
    times (%1) - ($ - item_smelt) db 0
    db %2
%endmacro
item_smelt:
    SMELT COBBLE, STONE
    SMELT LOG, COAL
    SMELT SAND, GLASS
    SMELT IRON_ORE, IRON_INGOT
    SMELT GOLD_ORE, GOLD_INGOT
    SMELT PORKCHOP, COOKED_PORKCHOP
    SMELT RAW_CHICKEN, COOKED_CHICKEN
    times NUM_ITEMS - ($ - item_smelt) db 0

; armor slot (ARMOR_HEAD..ARMOR_FEET) of an item, or 0
item_armor_slot:
    times 70 db 0
    db 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4
    times 10 db 0

; armor points of a worn piece
item_armor_points:
    times 70 db 0
    db 2, 6, 5, 2                       ; iron
    db 2, 5, 3, 1                       ; gold
    db 3, 8, 6, 3                       ; diamond
    times 10 db 0

align 2
item_durability:
    times 33 dw 0
    times 4 dw 59
    times 4 dw 131
    times 6 dw 0
    times 4 dw 250                      ; iron tools
    times 4 dw 32                       ; gold tools
    times 4 dw 1561                     ; diamond tools
    dw 384                              ; bow
    times 4 dw 0
    dw 64                               ; flint and steel
    times 5 dw 0
    dw 165, 240, 225, 195               ; iron armor
    dw 77, 112, 105, 91                 ; gold armor
    dw 363, 528, 495, 429               ; diamond armor
    times 10 dw 0                       ; firearms never wear, ammunition

; fuel value in furnace steps, or 0 (entries in ascending id order)
%macro BURN 2                           ; item id, steps
    times (%1) - ($ - item_burn) / 2 dw 0
    dw %2
%endmacro
item_burn:
    BURN PLANKS, 300
    BURN LOG, 300
    BURN CRAFTING_TABLE, 300
    BURN CHEST, 300
    BURN STICK, 100
    BURN WOOD_PICKAXE, 200
    BURN WOOD_AXE, 200
    BURN WOOD_SHOVEL, 200
    BURN WOOD_SWORD, 200
    BURN COAL, 1600
    BURN BOW, 300
    times NUM_ITEMS - ($ - item_burn) / 2 dw 0

align 4
item_saturation:
    times 41 dd 0.0
    dd 2.4, 1.8
    times 22 dd 0.0
    dd 0.8, 12.8, 0.0, 1.2, 7.2
    times 12 dd 0.0
    times 10 dd 0.0
