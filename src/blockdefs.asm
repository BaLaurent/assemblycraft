; blockdefs.asm - per-block flags, atlas tiles, digging and harvest rules, shapes, light.
; Indexed by block id 0..136 (NUM_BLOCKS). Display names live in itemdefs.asm.
; Variant groups (stairs, doors, trapdoors, ladders, wall torches) take one id per
; orientation/state: param = id - block_base[id] (see common.inc).
;
; FLAG_SOLID is the coarse "full cell" answer of world_is_solid (drops, particles, blink,
; placement support); bodies collide with shapes.asm boxes. FLAG_OPAQUE is set only on
; full opaque cubes: it blocks light and culls faces.
%include "common.inc"
default rel

global block_flags, block_tiles, block_hardness, block_tool, block_harvest_level
global block_drop, block_dig_sound, block_step_sound, block_flammable
global block_shape, block_base, block_light

; SIZECHECK table, element size: every table holds exactly NUM_BLOCKS entries
%macro SIZECHECK 2
%if $ - %1 != NUM_BLOCKS * %2
%error %str(%1) has the wrong number of entries
%endif
%endmacro

; GROUP_IDS first, count: emit db first + i for i in 0..count-1
%macro GROUP_IDS 2
%assign gi 0
%rep %2
    db %1 + gi
%assign gi gi + 1
%endrep
%endmacro

section .rodata
;             AIR STONE GRASS DIRT COBBLE PLANKS LOG LEAVES SAND GLASS BRICK BEDROCK TABLE
block_flags: db 0,  3,    3,    3,   3,     3,     3,  1,     3,   5,    3,    3,      3
;               COAL IRON GOLD DIAMOND FURNACE LIT CHEST GRAVEL TNT FIRE SBRICK MOSSY
             db 3,   3,   3,   3,      3,      3,  3,    3,     3,  0,   3,     3
    times 10 db 3                       ; SANDSTONE .. COAL_BLOCK
    times 5 db 1                        ; slabs
    times 20 db 1                       ; stairs
    times 40 db 0                       ; doors, trapdoors
    times 4 db 0                        ; ladders
    times 5 db 0                        ; torches
    db 1, 1                             ; FENCE, GLASS_PANE
;      WATER ICE SNOWL SNOWB MUD GRASS CACTUS PLOG PLEAF BLOG BLEAF
    db 8,    9,  0,    3,    3,  0,    1,     3,   1,    3,   1
    times 8 db 1                        ; BED (foot 0..3, head 4..7)
    times 5 db 3                        ; SHRINE (one per faction)
    db 3, 8                             ; DRY_GRASS, LAVA
    SIZECHECK block_flags, 1

; tiles per block: top, side, bottom
block_tiles:
    dw 0, 0, 0                          ; AIR
    dw 0, 0, 0                          ; STONE
    dw 1, 2, 3                          ; GRASS
    dw 3, 3, 3                          ; DIRT
    dw 4, 4, 4                          ; COBBLE
    dw 5, 5, 5                          ; PLANKS
    dw 7, 6, 7                          ; LOG
    dw 8, 8, 8                          ; LEAVES
    dw 9, 9, 9                          ; SAND
    dw 10, 10, 10                       ; GLASS
    dw 11, 11, 11                       ; BRICK
    dw 12, 12, 12                       ; BEDROCK
    dw TILE_TABLE_TOP, TILE_TABLE_SIDE, 5 ; CRAFTING_TABLE
    dw TILE_COAL_ORE, TILE_COAL_ORE, TILE_COAL_ORE
    dw TILE_IRON_ORE, TILE_IRON_ORE, TILE_IRON_ORE
    dw TILE_GOLD_ORE, TILE_GOLD_ORE, TILE_GOLD_ORE
    dw TILE_DIAMOND_ORE, TILE_DIAMOND_ORE, TILE_DIAMOND_ORE
    dw 0, TILE_FURNACE_FRONT, 0         ; FURNACE
    dw 0, TILE_FURNACE_LIT, 0           ; FURNACE_LIT
    dw TILE_CHEST_TOP, TILE_CHEST_SIDE, TILE_CHEST_TOP
    dw TILE_GRAVEL, TILE_GRAVEL, TILE_GRAVEL
    dw TILE_TNT_TOP, TILE_TNT_SIDE, TILE_TNT_TOP
    dw 0, 0, 0                          ; FIRE (drawn by fire.asm, skipped by the mesher)
    dw TILE_STONE_BRICK, TILE_STONE_BRICK, TILE_STONE_BRICK
    dw TILE_MOSSY_BRICK, TILE_MOSSY_BRICK, TILE_MOSSY_BRICK
    dw TILE_SANDSTONE_TOP, TILE_SANDSTONE_SIDE, TILE_SANDSTONE_BOTTOM
    times 3 dw TILE_SMOOTH_STONE
    times 3 dw TILE_MOSSY_COBBLE
    times 3 dw TILE_CRACKED_BRICK
    dw 5, TILE_BOOKSHELF, 5             ; BOOKSHELF
    times 3 dw TILE_WOOL
    times 3 dw TILE_IRON_BLOCK
    times 3 dw TILE_GOLD_BLOCK
    times 3 dw TILE_DIAMOND_BLOCK
    times 3 dw TILE_COAL_BLOCK
%define T_PLANKS 5, 5, 5
%define T_COBBLE 4, 4, 4
%define T_SBRICK TILE_STONE_BRICK, TILE_STONE_BRICK, TILE_STONE_BRICK
%define T_BRICK 11, 11, 11
%define T_SANDSTONE TILE_SANDSTONE_TOP, TILE_SANDSTONE_SIDE, TILE_SANDSTONE_BOTTOM
    dw T_PLANKS                         ; slabs
    dw T_COBBLE
    dw T_SBRICK
    dw T_BRICK
    dw T_SANDSTONE
%rep 4
    dw T_PLANKS                         ; PLANK_STAIRS
%endrep
%rep 4
    dw T_COBBLE
%endrep
%rep 4
    dw T_SBRICK
%endrep
%rep 4
    dw T_BRICK
%endrep
%rep 4
    dw T_SANDSTONE
%endrep
%rep 8                                  ; WOOD_DOOR: param bit 0 = upper half
    times 3 dw TILE_DOOR_WOOD_LOWER
    times 3 dw TILE_DOOR_WOOD_UPPER
%endrep
%rep 8                                  ; IRON_DOOR
    times 3 dw TILE_DOOR_IRON_LOWER
    times 3 dw TILE_DOOR_IRON_UPPER
%endrep
    times 8 * 3 dw TILE_TRAPDOOR
    times 4 * 3 dw TILE_LADDER
    times 5 * 3 dw TILE_TORCH
    dw T_PLANKS                         ; FENCE
    dw 10, 10, 10                       ; GLASS_PANE
    times 3 dw TILE_WATER
    times 3 dw TILE_ICE
    times 3 dw TILE_SNOW                ; SNOW_LAYER
    times 3 dw TILE_SNOW                ; SNOW_BLOCK
    times 3 dw TILE_MUD
    times 3 dw TILE_TALL_GRASS
    dw TILE_CACTUS_TOP, TILE_CACTUS_SIDE, TILE_CACTUS_TOP
    dw TILE_PINE_LOG_TOP, TILE_PINE_LOG, TILE_PINE_LOG_TOP
    times 3 dw TILE_PINE_LEAVES
    dw 7, TILE_BIRCH_LOG, 7             ; BIRCH_LOG: LOG's ring top
    times 3 dw TILE_BIRCH_LEAVES
%rep 4
    dw TILE_BED_FOOT_TOP, TILE_BED_FOOT_SIDE, 5
%endrep
%rep 4
    dw TILE_BED_HEAD_TOP, TILE_BED_HEAD_SIDE, 5
%endrep
%rep 5                                  ; SHRINE
    dw TILE_SHRINE_TOP, TILE_SHRINE_SIDE, TILE_STONE_BRICK
%endrep
    dw TILE_DRY_GRASS_TOP, TILE_DRY_GRASS_SIDE, 3 ; DRY_GRASS (dirt below)
    dw TILE_LAVA, TILE_LAVA, TILE_LAVA  ; LAVA
    SIZECHECK block_tiles, 6

align 4
; seconds-scale hardness; negative = unbreakable
block_hardness:
    dd 0.0, 1.5, 0.6, 0.5, 2.0, 2.0, 2.0, 0.2, 0.5, 0.3, 2.0, -1.0, 2.5
    dd 3.0, 3.0, 3.0, 3.0, 3.5, 3.5, 2.5, 0.6, 0.0, 0.0, 1.5, 1.5
    ;  SAND  SMOOTH MOSSYC CRACK BOOKS WOOL IRON GOLD DIAM COAL
    dd 0.8, 2.0, 2.0, 1.5, 1.5, 0.8, 5.0, 3.0, 5.0, 5.0
    dd 2.0, 2.0, 1.5, 2.0, 0.8          ; slabs
    times 4 dd 2.0                      ; stairs
    times 4 dd 2.0
    times 4 dd 1.5
    times 4 dd 2.0
    times 4 dd 0.8
    times 16 dd 3.0                     ; WOOD_DOOR
    times 16 dd 5.0                     ; IRON_DOOR
    times 8 dd 3.0                      ; TRAPDOOR
    times 4 dd 0.4                      ; LADDER
    times 5 dd 0.0                      ; torches
    dd 2.0, 0.3                         ; FENCE, GLASS_PANE
    ;  WATER ICE  SNOWL SNOWB MUD  TGRASS CACTUS PLOG PLEAF BLOG BLEAF
    dd -1.0, 0.5, 0.1, 0.4, 0.6, 0.0, 0.4, 2.0, 0.2, 2.0, 0.2
    times 8 dd 0.2                      ; BED
    times 5 dd -1.0                     ; SHRINE
    dd 0.6, -1.0                        ; DRY_GRASS, LAVA
    SIZECHECK block_hardness, 4

%define M_TOOLS TOOL_AXE, TOOL_PICKAXE, TOOL_PICKAXE, TOOL_PICKAXE, TOOL_PICKAXE
;                  AIR STONE GRASS DIRT COBBLE PLANKS LOG LEAVES SAND GLASS BRICK BEDROCK TABLE
block_tool:       db 0, TOOL_PICKAXE, TOOL_SHOVEL, TOOL_SHOVEL, TOOL_PICKAXE, TOOL_AXE, TOOL_AXE, 0, TOOL_SHOVEL, 0, TOOL_PICKAXE, 0, TOOL_AXE
;                  COAL IRON GOLD DIAMOND FURNACE LIT CHEST GRAVEL TNT FIRE SBRICK MOSSY
                  db TOOL_PICKAXE, TOOL_PICKAXE, TOOL_PICKAXE, TOOL_PICKAXE, TOOL_PICKAXE, TOOL_PICKAXE, TOOL_AXE, TOOL_SHOVEL, 0, 0, TOOL_PICKAXE, TOOL_PICKAXE
                  times 4 db TOOL_PICKAXE ; SANDSTONE .. CRACKED_STONE_BRICK
                  db TOOL_AXE, 0         ; BOOKSHELF, WOOL
                  times 4 db TOOL_PICKAXE ; storage blocks
                  db M_TOOLS             ; slabs
                  times 4 db TOOL_AXE    ; stairs
                  times 16 db TOOL_PICKAXE
                  times 16 db TOOL_AXE   ; WOOD_DOOR
                  times 16 db TOOL_PICKAXE ; IRON_DOOR
                  times 8 db TOOL_AXE    ; TRAPDOOR
                  times 4 db TOOL_AXE    ; LADDER
                  times 5 db 0           ; torches
                  db TOOL_AXE, 0         ; FENCE, GLASS_PANE
                  db 0, TOOL_PICKAXE, 0, TOOL_SHOVEL, TOOL_SHOVEL, 0, 0 ; WATER .. CACTUS
                  db TOOL_AXE, 0, TOOL_AXE, 0 ; PINE_LOG .. BIRCH_LEAVES
                  times 8 db 0           ; BED
                  times 5 db 0           ; SHRINE
                  db TOOL_SHOVEL, 0      ; DRY_GRASS, LAVA
    SIZECHECK block_tool, 1

; minimum pickaxe level to harvest (0 = anything; 1 wood, 2 stone, 3 iron/diamond)
block_harvest_level: db 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0
                  db 1, 2, 3, 3, 1, 1, 0, 0, 0, 0, 1, 1
                  db 1, 1, 1, 1, 0, 0, 2, 3, 3, 1 ; SANDSTONE .. COAL_BLOCK
                  db 0, 1, 1, 1, 1       ; slabs
                  times 4 db 0           ; stairs
                  times 16 db 1
                  times 16 db 0          ; WOOD_DOOR
                  times 16 db 1          ; IRON_DOOR
                  times 8 + 4 + 5 + 2 db 0
                  times 11 + 8 + 5 db 0  ; WATER .. BED, SHRINE
                  times 2 db 0           ; DRY_GRASS, LAVA
    SIZECHECK block_harvest_level, 1

; harvested item (LEAVES: 0, the apple chance is rolled by the game)
block_drop:       db 0, COBBLE, DIRT, DIRT, COBBLE, PLANKS, LOG, 0, SAND, 0, BRICK, 0, CRAFTING_TABLE
                  db COAL, IRON_ORE, GOLD_ORE, DIAMOND, FURNACE, FURNACE, CHEST, GRAVEL, TNT, 0, STONE_BRICK, MOSSY_STONE_BRICK
                  GROUP_IDS SANDSTONE, 15 ; SANDSTONE .. SANDSTONE_SLAB drop themselves
                  times 4 db PLANK_STAIRS
                  times 4 db COBBLE_STAIRS
                  times 4 db STONE_BRICK_STAIRS
                  times 4 db BRICK_STAIRS
                  times 4 db SANDSTONE_STAIRS
                  times 16 db WOOD_DOOR
                  times 16 db IRON_DOOR
                  times 8 db TRAPDOOR
                  times 4 db LADDER
                  times 5 db TORCH
                  db FENCE, 0            ; GLASS_PANE drops nothing, like glass
                  db 0, 0, 0, SNOW_BLOCK, MUD, 0, CACTUS ; WATER .. CACTUS
                  db PINE_LOG, 0, BIRCH_LOG, 0 ; leaves: the game rolls their drops
                  times 8 db BED         ; either half drops the one bed
                  times 5 db 0           ; SHRINE
                  db DIRT, 0             ; DRY_GRASS digs to dirt, LAVA nothing
    SIZECHECK block_drop, 1

%define DS_STONE SND_DIG_STONE
%define DS_WOOD SND_DIG_WOOD
block_dig_sound:
    db 0, SND_DIG_STONE, SND_DIG_SOFT, SND_DIG_SOFT, SND_DIG_STONE, SND_DIG_WOOD, SND_DIG_WOOD
    db SND_DIG_SOFT, SND_DIG_SOFT, SND_DIG_GLASS, SND_DIG_STONE, SND_DIG_STONE, SND_DIG_WOOD
    db SND_DIG_STONE, SND_DIG_STONE, SND_DIG_STONE, SND_DIG_STONE, SND_DIG_STONE, SND_DIG_STONE
    db SND_DIG_WOOD, SND_DIG_SOFT, SND_DIG_SOFT, SND_DIG_SOFT, SND_DIG_STONE, SND_DIG_STONE
    times 4 db DS_STONE                 ; SANDSTONE .. CRACKED_STONE_BRICK
    db DS_WOOD, SND_DIG_SOFT            ; BOOKSHELF, WOOL
    times 4 db DS_STONE                 ; storage blocks
    db DS_WOOD, DS_STONE, DS_STONE, DS_STONE, DS_STONE ; slabs
    times 4 db DS_WOOD                  ; stairs
    times 16 db DS_STONE
    times 16 db DS_WOOD                 ; WOOD_DOOR
    times 16 db DS_STONE                ; IRON_DOOR
    times 8 + 4 + 5 db DS_WOOD          ; trapdoors, ladders, torches
    db DS_WOOD, SND_DIG_GLASS           ; FENCE, GLASS_PANE
    db 0, DS_STONE, SND_DIG_SOFT, DS_STONE, SND_DIG_SOFT, SND_DIG_SOFT, SND_DIG_SOFT ; WATER .. CACTUS
    db DS_WOOD, SND_DIG_SOFT, DS_WOOD, SND_DIG_SOFT ; pine, birch
    times 8 db DS_WOOD                  ; BED
    times 5 db DS_STONE                 ; SHRINE
    db SND_DIG_SOFT, 0                  ; DRY_GRASS, LAVA
    SIZECHECK block_dig_sound, 1

%define SS_STONE SND_STEP_STONE
%define SS_WOOD SND_STEP_WOOD
block_step_sound:
    db 0, SND_STEP_STONE, SND_STEP_SOFT, SND_STEP_SOFT, SND_STEP_STONE, SND_STEP_WOOD, SND_STEP_WOOD
    db SND_STEP_SOFT, SND_STEP_SOFT, SND_STEP_STONE, SND_STEP_STONE, SND_STEP_STONE, SND_STEP_WOOD
    db SND_STEP_STONE, SND_STEP_STONE, SND_STEP_STONE, SND_STEP_STONE, SND_STEP_STONE, SND_STEP_STONE
    db SND_STEP_WOOD, SND_STEP_SOFT, SND_STEP_SOFT, SND_STEP_SOFT, SND_STEP_STONE, SND_STEP_STONE
    times 4 db SS_STONE
    db SS_WOOD, SND_STEP_SOFT           ; BOOKSHELF, WOOL
    times 4 db SS_STONE
    db SS_WOOD, SS_STONE, SS_STONE, SS_STONE, SS_STONE ; slabs
    times 4 db SS_WOOD                  ; stairs
    times 16 db SS_STONE
    times 16 db SS_WOOD                 ; WOOD_DOOR
    times 16 db SS_STONE                ; IRON_DOOR
    times 8 + 4 + 5 db SS_WOOD
    db SS_WOOD, SS_STONE                ; FENCE, GLASS_PANE
    db 0, SS_STONE, SND_STEP_SOFT, SS_STONE, SND_STEP_SOFT, SND_STEP_SOFT, SND_STEP_SOFT ; WATER .. CACTUS
    db SS_WOOD, SND_STEP_SOFT, SS_WOOD, SND_STEP_SOFT ; pine, birch
    times 8 db SS_WOOD                  ; BED
    times 5 db SS_STONE                 ; SHRINE
    db SND_STEP_SOFT, 0                 ; DRY_GRASS, LAVA
    SIZECHECK block_step_sound, 1

; chance in % per fire tick that a neighbouring fire burns the block (TNT: ignites)
;                AIR STONE GRASS DIRT COBBLE PLANKS LOG LEAVES SAND GLASS BRICK BEDROCK TABLE
block_flammable: db 0, 0,    0,    0,   0,     20,    5,  30,    0,   0,    0,    0,      20
;                COAL IRON GOLD DIAMOND FURNACE LIT CHEST GRAVEL TNT FIRE SBRICK MOSSY
                 db 0,   0,   0,   0,      0,      0,  20,   0,     100, 0,   0,     0
                 db 0, 0, 0, 0, 30, 30, 0, 0, 0, 5 ; SANDSTONE .. COAL_BLOCK
                 db 20, 0, 0, 0, 0       ; slabs
                 times 4 db 20           ; PLANK_STAIRS
                 times 16 db 0
                 times 16 db 20          ; WOOD_DOOR
                 times 16 db 0           ; IRON_DOOR
                 times 8 + 4 db 20       ; trapdoors, ladders
                 times 5 db 0            ; torches
                 db 20, 0                ; FENCE, GLASS_PANE
                 times 7 db 0            ; WATER .. CACTUS
                 db 5, 30, 5, 30         ; PINE_LOG, PINE_LEAVES, BIRCH_LOG, BIRCH_LEAVES
                 times 8 db 20           ; BED
                 times 5 db 0            ; SHRINE
                 times 2 db 0            ; DRY_GRASS, LAVA
    SIZECHECK block_flammable, 1

; SHAPE_* of each block (shapes.asm turns it into boxes)
block_shape:
    db SHAPE_NONE
    times FIRE - 1 db SHAPE_CUBE        ; STONE .. TNT
    db SHAPE_NONE                       ; FIRE
    times PLANK_SLAB - STONE_BRICK db SHAPE_CUBE ; STONE_BRICK .. COAL_BLOCK
    times 5 db SHAPE_SLAB
    times 20 db SHAPE_STAIRS
    times 32 db SHAPE_DOOR
    times 8 db SHAPE_TRAPDOOR
    times 4 db SHAPE_LADDER
    times 5 db SHAPE_TORCH
    db SHAPE_FENCE, SHAPE_PANE
    db SHAPE_LIQUID, SHAPE_CUBE, SHAPE_SNOW, SHAPE_CUBE, SHAPE_CUBE, SHAPE_CROSS, SHAPE_CACTUS
    times 4 db SHAPE_CUBE               ; pine, birch
    times 8 db SHAPE_BED
    times 5 db SHAPE_CUBE               ; SHRINE
    db SHAPE_CUBE, SHAPE_LIQUID         ; DRY_GRASS, LAVA
    SIZECHECK block_shape, 1

; the base id of a variant group (param = id - base); the item form of a block, 0 = none
block_base:
    db 0                                ; AIR
    GROUP_IDS STONE, FURNACE_LIT - STONE ; STONE .. FURNACE
    db FURNACE                          ; FURNACE_LIT
    GROUP_IDS CHEST, FIRE - CHEST       ; CHEST .. TNT
    db 0                                ; FIRE
    GROUP_IDS STONE_BRICK, PLANK_STAIRS - STONE_BRICK ; .. SANDSTONE_SLAB
    times 4 db PLANK_STAIRS
    times 4 db COBBLE_STAIRS
    times 4 db STONE_BRICK_STAIRS
    times 4 db BRICK_STAIRS
    times 4 db SANDSTONE_STAIRS
    times 16 db WOOD_DOOR
    times 16 db IRON_DOOR
    times 8 db TRAPDOOR
    times 4 db LADDER
    times 5 db TORCH                    ; TORCH, TORCH_WALL variants: param = 1 + support side
    db FENCE, GLASS_PANE
    db 0, ICE, 0, SNOW_BLOCK, MUD, 0    ; WATER .. TALL_GRASS (water, snow layer, grass: no item)
    GROUP_IDS CACTUS, BED - CACTUS      ; CACTUS .. BIRCH_LEAVES
    times 8 db BED
    times 5 db SHRINE
    db 0, 0                             ; DRY_GRASS, LAVA: no item form
    SIZECHECK block_base, 1

; block light emitted (0..15)
block_light:
    times FURNACE_LIT db 0
    db 13                               ; FURNACE_LIT
    times FIRE - CHEST db 0
    db 15                               ; FIRE
    times TORCH - STONE_BRICK db 0
    times 5 db 14                       ; TORCH, TORCH_WALL variants
    db 0, 0                             ; FENCE, GLASS_PANE
    times 11 + 8 db 0                   ; WATER .. BED
    times 5 db 10                       ; SHRINE
    db 0, 15                            ; DRY_GRASS, LAVA
    SIZECHECK block_light, 1
