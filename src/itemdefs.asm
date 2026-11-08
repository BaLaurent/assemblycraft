; itemdefs.asm - per-item data tables, indexed by item id 0..224 (NUM_ITEMS).
; Ids 0..129 are the blocks (variant ids: the item form is block_base), 130..143 are unused,
; 144..224 (FIRST_ITEM..) are tools/materials/food/armor/firearms/RPG gear/jewelry/boat.
; Every table lists entries in ascending id order; PAD_TO fills the gaps.
%include "common.inc"
default rel

global item_names, item_icon, item_max_stack, item_tool, item_tier
global item_durability, item_food, item_saturation, item_attack
global item_burn, item_smelt, item_armor_slot, item_armor_points
global item_gear, item_legendary

; PAD_TO table, id, elemsize, default: emit `default` up to (not including) entry `id`
%macro PAD_TO 4
%if %3 == 1
    times (%2) - ($ - %1) db %4
%elif %3 == 2
    times (%2) - ($ - %1) / 2 dw %4
%elif %3 == 4
    times (%2) - ($ - %1) / 4 dd %4
%else
    times (%2) - ($ - %1) / 8 dq %4
%endif
%endmacro

; END_TABLE table, elemsize: pad to NUM_ITEMS and check the size
%macro END_TABLE 3                      ; table, elemsize, default
    PAD_TO %1, NUM_ITEMS, %2, %3
%if $ - %1 != NUM_ITEMS * %2
%error %str(%1) has the wrong number of entries
%endif
%endmacro

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
n_fire:     db "Fire", 0
n_sbrick:   db "Stone Bricks", 0
n_mossy:    db "Mossy Stone Bricks", 0
n_sandstone: db "Sandstone", 0
n_smooth:   db "Smooth Stone", 0
n_mcobble:  db "Mossy Cobblestone", 0
n_cracked:  db "Cracked Stone Bricks", 0
n_books:    db "Bookshelf", 0
n_wool:     db "Wool", 0
n_ironblk:  db "Block of Iron", 0
n_goldblk:  db "Block of Gold", 0
n_diablk:   db "Block of Diamond", 0
n_coalblk:  db "Block of Coal", 0
n_pslab:    db "Wooden Slab", 0
n_cslab:    db "Cobblestone Slab", 0
n_sbslab:   db "Stone Brick Slab", 0
n_bslab:    db "Brick Slab", 0
n_ssslab:   db "Sandstone Slab", 0
n_pstairs:  db "Wooden Stairs", 0
n_cstairs:  db "Cobblestone Stairs", 0
n_sbstairs: db "Stone Brick Stairs", 0
n_bstairs:  db "Brick Stairs", 0
n_ssstairs: db "Sandstone Stairs", 0
n_wdoor:    db "Wooden Door", 0
n_idoor:    db "Iron Door", 0
n_trapdoor: db "Trapdoor", 0
n_ladder:   db "Ladder", 0
n_torch:    db "Torch", 0
n_fence:    db "Fence", 0
n_pane:     db "Glass Pane", 0
n_water:    db "Water", 0
n_ice:      db "Ice", 0
n_snow:     db "Snow", 0
n_snowblk:  db "Snow Block", 0
n_mud:      db "Mud", 0
n_tgrass:   db "Tall Grass", 0
n_cactus:   db "Cactus", 0
n_plog:     db "Pine Log", 0
n_pleaves:  db "Pine Leaves", 0
n_blog:     db "Birch Log", 0
n_bleaves:  db "Birch Leaves", 0
n_bed:      db "Bed", 0
n_boat:     db "Boat", 0
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
n_staff:    db "Staff", 0
n_astaff:   db "Archmage Staff", 0
n_idagger:  db "Iron Dagger", 0
n_ddagger:  db "Diamond Dagger", 0
n_fang:     db "Shadow Fang", 0
n_kblade:   db "King's Blade", 0
n_cbow:     db "Celestial Bow", 0
n_hpotion:  db "Health Potion", 0
n_mpotion:  db "Mana Potion", 0
n_coin:     db "Gold Coin", 0
n_ring:     db "Ring", 0
n_amulet:   db "Amulet", 0
n_phoenix:  db "Phoenix Ring", 0
n_storm:    db "Band of Storms", 0
n_ember:    db "Ember Amulet", 0
n_viper:    db "Viper Amulet", 0
n_ihammer:  db "Iron Warhammer", 0
n_dhammer:  db "Diamond Warhammer", 0
n_ispear:   db "Iron Spear", 0
n_dspear:   db "Diamond Spear", 0

align 8
; display name; every variant id points at its base's name
item_names:
    dq n_air, n_stone, n_grass, n_dirt, n_cobble, n_planks, n_log, n_leaves
    dq n_sand, n_glass, n_brick, n_bedrock, n_table
    dq n_coalore, n_ironore, n_goldore, n_diaore, n_furnace, n_furnace, n_chest, n_gravel, n_tnt
    dq n_fire, n_sbrick, n_mossy
    dq n_sandstone, n_smooth, n_mcobble, n_cracked, n_books, n_wool
    dq n_ironblk, n_goldblk, n_diablk, n_coalblk
    dq n_pslab, n_cslab, n_sbslab, n_bslab, n_ssslab
    times 4 dq n_pstairs
    times 4 dq n_cstairs
    times 4 dq n_sbstairs
    times 4 dq n_bstairs
    times 4 dq n_ssstairs
    times 16 dq n_wdoor
    times 16 dq n_idoor
    times 8 dq n_trapdoor
    times 4 dq n_ladder
    times 5 dq n_torch
    dq n_fence, n_pane
    dq n_water, n_ice, n_snow, n_snowblk, n_mud, n_tgrass, n_cactus
    dq n_plog, n_pleaves, n_blog, n_bleaves
    times 8 dq n_bed
    PAD_TO item_names, STICK, 8, n_unused
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
    dq n_staff, n_astaff, n_idagger, n_ddagger, n_fang, n_kblade, n_cbow
    dq n_hpotion, n_mpotion, n_coin
    dq n_ring, n_amulet, n_phoenix, n_storm, n_ember, n_viper
    dq n_ihammer, n_dhammer, n_ispear, n_dspear
    dq n_boat
    END_TABLE item_names, 8, n_unused

; atlas tile of the inventory icon: a block's side tile or icon tile (0 for non-base
; variants), tiles 32.. for STICK..PORKCHOP, TILE_ITEM0 + id - COAL from COAL to GOLD_COIN,
; then the 0.8 jewelry and weapon tiles
item_icon:
    db 0, 0, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, TILE_TABLE_SIDE
    db 26, 27, 28, 29, 30, 31, 44, 45, 46
    db 0, TILE_STONE_BRICK, TILE_MOSSY_BRICK ; FIRE, stone bricks, mossy
    db TILE_SANDSTONE_SIDE, TILE_SMOOTH_STONE, TILE_MOSSY_COBBLE, TILE_CRACKED_BRICK
    db TILE_BOOKSHELF, TILE_WOOL, TILE_IRON_BLOCK, TILE_GOLD_BLOCK, TILE_DIAMOND_BLOCK
    db TILE_COAL_BLOCK
%assign i 0
%rep 5
    db TILE_ICON_SLAB0 + i
%assign i i + 1
%endrep
%assign i 0
%rep 5
    db TILE_ICON_STAIRS0 + i, 0, 0, 0
%assign i i + 1
%endrep
    db TILE_ICON_WOOD_DOOR
    times 15 db 0
    db TILE_ICON_IRON_DOOR
    times 15 db 0
    db TILE_TRAPDOOR
    times 7 db 0
    db TILE_LADDER, 0, 0, 0
    db TILE_TORCH, 0, 0, 0, 0
    db TILE_ICON_FENCE, TILE_ICON_GLASS_PANE
    db 0, TILE_ICE, 0, TILE_SNOW, TILE_MUD, 0, TILE_CACTUS_SIDE ; WATER .. CACTUS
    db TILE_PINE_LOG, TILE_PINE_LEAVES, TILE_BIRCH_LOG, TILE_BIRCH_LEAVES
    db TILE_ICON_BED
    times 7 db 0
    PAD_TO item_icon, STICK, 1, 0
%assign i 0
%rep COAL - STICK
    db 32 + i
%assign i i + 1
%endrep
%assign i 0
%rep RING - COAL
    db TILE_ITEM0 + i
%assign i i + 1
%endrep
    db TILE_RING, TILE_AMULET, TILE_RING, TILE_RING ; ring, amulet, Phoenix Ring, Band of Storms
    db TILE_AMULET, TILE_AMULET         ; Ember, Viper amulets
    db TILE_IRON_HAMMER, TILE_DIAMOND_HAMMER, TILE_IRON_SPEAR, TILE_DIAMOND_SPEAR
    db TILE_ICON_BOAT
    END_TABLE item_icon, 1, 0

; 0 = not an item (air, fire, the lit furnace, non-base variants, unused ids)
item_max_stack:
    db 0
    times 17 db 64                      ; blocks 1..17
    db 0                                ; FURNACE_LIT
    times 3 db 64                       ; chest, gravel, tnt
    db 0                                ; FIRE
    db 64, 64                           ; stone bricks, mossy
    times 10 db 64                      ; SANDSTONE .. COAL_BLOCK
    times 5 db 64                       ; slabs
%rep 5
    db 64, 0, 0, 0                      ; stairs
%endrep
    db 64                               ; WOOD_DOOR
    times 15 db 0
    db 64                               ; IRON_DOOR
    times 15 db 0
    db 64                               ; TRAPDOOR
    times 7 db 0
    db 64, 0, 0, 0                      ; LADDER
    db 64, 0, 0, 0, 0                   ; TORCH, TORCH_WALL
    db 64, 64                           ; FENCE, GLASS_PANE
    db 0, 64, 0, 64, 64, 0, 64          ; WATER .. CACTUS (water, snow layer, grass: no item)
    times 4 db 64                       ; pine, birch
    db 1                                ; BED
    times 7 db 0
    PAD_TO item_max_stack, STICK, 1, 0
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
    times 7 db 1                        ; staves, daggers, legendaries
    db 16, 16                           ; potions
    db 64                               ; gold coin
    times 10 db 1                       ; jewelry, hammers, spears
    db 1                                ; boat
    END_TABLE item_max_stack, 1, 0

%define TOOLS4 TOOL_PICKAXE, TOOL_AXE, TOOL_SHOVEL, TOOL_SWORD
item_tool:
    PAD_TO item_tool, WOOD_PICKAXE, 1, 0
    db TOOLS4, TOOLS4                   ; wood, stone
    PAD_TO item_tool, IRON_PICKAXE, 1, 0
    db TOOLS4, TOOLS4, TOOLS4           ; iron, gold, diamond
    PAD_TO item_tool, IRON_DAGGER, 1, 0
    db TOOL_DAGGER, TOOL_DAGGER, TOOL_DAGGER, TOOL_SWORD ; daggers, King's Blade
    PAD_TO item_tool, IRON_HAMMER, 1, 0
    db TOOL_HAMMER, TOOL_HAMMER, TOOL_SPEAR, TOOL_SPEAR
    END_TABLE item_tool, 1, 0

item_tier:
    PAD_TO item_tier, WOOD_PICKAXE, 1, 0
    times 4 db TIER_WOOD
    times 4 db TIER_STONE
    PAD_TO item_tier, IRON_PICKAXE, 1, 0
    times 4 db TIER_IRON
    times 4 db TIER_GOLD
    times 4 db TIER_DIAMOND
    PAD_TO item_tier, KINGS_BLADE, 1, 0
    db TIER_DIAMOND                     ; King's Blade
    PAD_TO item_tier, IRON_HAMMER, 1, 0
    db TIER_IRON, TIER_DIAMOND, TIER_IRON, TIER_DIAMOND ; hammers, spears
    END_TABLE item_tier, 1, 0

item_food:
    PAD_TO item_food, APPLE, 1, 0
    db 4, 3                             ; apple, porkchop
    PAD_TO item_food, ROTTEN_FLESH, 1, 0
    db 4, 8, 0, 2, 6                    ; rotten flesh, cooked pork, feather, raw/cooked chicken
    END_TABLE item_food, 1, 0

item_attack:
    PAD_TO item_attack, WOOD_PICKAXE, 1, 1
    db 3, 4, 2, 5                       ; wood pickaxe, axe, shovel, sword
    db 4, 5, 3, 6                       ; stone pickaxe, axe, shovel, sword
    PAD_TO item_attack, IRON_PICKAXE, 1, 1
    db 5, 6, 4, 7                       ; iron
    db 3, 4, 2, 5                       ; gold
    db 6, 7, 5, 8                       ; diamond
    PAD_TO item_attack, STAFF, 1, 1
    db 2, 3, 5, 7, 9, 11                ; staff, archmage staff, daggers, Shadow Fang, King's Blade
    PAD_TO item_attack, IRON_HAMMER, 1, 1
    db 9, 12, 6, 8                      ; iron/diamond warhammer, iron/diamond spear
    END_TABLE item_attack, 1, 1

; smelting result of an input item, or 0
item_smelt:
    PAD_TO item_smelt, STONE, 1, 0
    db SMOOTH_STONE
    PAD_TO item_smelt, COBBLE, 1, 0
    db STONE
    PAD_TO item_smelt, LOG, 1, 0
    db COAL
    PAD_TO item_smelt, SAND, 1, 0
    db GLASS
    PAD_TO item_smelt, IRON_ORE, 1, 0
    db IRON_INGOT
    PAD_TO item_smelt, GOLD_ORE, 1, 0
    db GOLD_INGOT
    PAD_TO item_smelt, STONE_BRICK, 1, 0
    db CRACKED_STONE_BRICK
    PAD_TO item_smelt, PORKCHOP, 1, 0
    db COOKED_PORKCHOP
    PAD_TO item_smelt, RAW_CHICKEN, 1, 0
    db COOKED_CHICKEN
    END_TABLE item_smelt, 1, 0

; armor slot (ARMOR_HEAD..ARMOR_FEET) of an item, or 0
item_armor_slot:
    PAD_TO item_armor_slot, IRON_HELMET, 1, 0
    db 1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4
    END_TABLE item_armor_slot, 1, 0

; armor points of a worn piece
item_armor_points:
    PAD_TO item_armor_points, IRON_HELMET, 1, 0
    db 2, 6, 5, 2                       ; iron
    db 2, 5, 3, 1                       ; gold
    db 3, 8, 6, 3                       ; diamond
    END_TABLE item_armor_points, 1, 0

; AT table, id, value: one byte entry at `id` (ascending ids), zero before it
%macro AT 3
    PAD_TO %1, %2, 1, 0
    db %3
%endmacro

; gear kind (GK_*) of an item: rolled gear with affixes, or GK_NONE
item_gear:
    AT item_gear, WOOD_SWORD, GK_MELEE
    AT item_gear, STONE_SWORD, GK_MELEE
    AT item_gear, IRON_SWORD, GK_MELEE
    AT item_gear, GOLD_SWORD, GK_MELEE
    AT item_gear, DIAMOND_SWORD, GK_MELEE
    AT item_gear, BOW, GK_BOW
    PAD_TO item_gear, IRON_HELMET, 1, 0
%rep 3
    db GK_HEAD, GK_CHEST, GK_LEGS, GK_FEET ; iron, gold, diamond armor
%endrep
    PAD_TO item_gear, STAFF, 1, 0
    db GK_STAFF, GK_STAFF               ; staff, archmage staff
    db GK_MELEE, GK_MELEE, GK_MELEE, GK_MELEE ; daggers, Shadow Fang, King's Blade
    db GK_BOW                           ; Celestial Bow
    PAD_TO item_gear, RING, 1, 0
    db GK_RING, GK_AMULET, GK_RING, GK_RING, GK_AMULET, GK_AMULET
    db GK_MELEE, GK_MELEE, GK_MELEE, GK_MELEE ; hammers, spears
    END_TABLE item_gear, 1, 0

; legendary power (LP_*) of an item, or LP_NONE
item_legendary:
    AT item_legendary, ARCHMAGE_STAFF, LP_ARCHMAGE
    AT item_legendary, SHADOW_FANG, LP_SHADOW_FANG
    AT item_legendary, KINGS_BLADE, LP_KINGSLAYER
    AT item_legendary, CELESTIAL_BOW, LP_CELESTIAL
    AT item_legendary, PHOENIX_RING, LP_PHOENIX
    AT item_legendary, STORM_BAND, LP_STORMS
    AT item_legendary, EMBER_AMULET, LP_EMBERS
    AT item_legendary, VIPER_AMULET, LP_VIPER
    END_TABLE item_legendary, 1, 0

align 2
; wear in uses. Only pickaxes, axes, shovels and flint and steel wear; gear (swords, daggers,
; hammers, spears, bows, staves, armor, jewelry) never does: its dmg word holds its rarity, tier
; and seed instead.
item_durability:
    PAD_TO item_durability, WOOD_PICKAXE, 2, 0
    dw 59, 59, 59, 0                    ; wood pickaxe, axe, shovel, sword
    dw 131, 131, 131, 0                 ; stone
    PAD_TO item_durability, IRON_PICKAXE, 2, 0
    dw 250, 250, 250, 0                 ; iron
    dw 32, 32, 32, 0                    ; gold
    dw 1561, 1561, 1561, 0              ; diamond
    PAD_TO item_durability, FLINT_AND_STEEL, 2, 0
    dw 64                               ; flint and steel
    END_TABLE item_durability, 2, 0     ; every other item never wears

; fuel value in furnace steps, or 0
%macro BURN 2                           ; item id, steps
    PAD_TO item_burn, %1, 2, 0
    dw %2
%endmacro
item_burn:
    BURN PLANKS, 300
    BURN LOG, 300
    BURN CRAFTING_TABLE, 300
    BURN CHEST, 300
    BURN BOOKSHELF, 300
    BURN WOOL, 100
    BURN COAL_BLOCK, 16000
    BURN PLANK_SLAB, 150
    BURN PLANK_STAIRS, 300
    BURN WOOD_DOOR, 200
    BURN TRAPDOOR, 300
    BURN LADDER, 300
    BURN FENCE, 300
    BURN PINE_LOG, 300
    BURN BIRCH_LOG, 300
    BURN STICK, 100
    BURN WOOD_PICKAXE, 200
    BURN WOOD_AXE, 200
    BURN WOOD_SHOVEL, 200
    BURN WOOD_SWORD, 200
    BURN COAL, 1600
    BURN BOW, 300
    END_TABLE item_burn, 2, 0

align 4
item_saturation:
    PAD_TO item_saturation, APPLE, 4, 0.0
    dd 2.4, 1.8
    PAD_TO item_saturation, ROTTEN_FLESH, 4, 0.0
    dd 0.8, 12.8, 0.0, 1.2, 7.2
    END_TABLE item_saturation, 4, 0.0
