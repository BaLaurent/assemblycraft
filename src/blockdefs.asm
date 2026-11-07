; blockdefs.asm - per-block flags, atlas tiles, digging and harvest rules.
; Indexed by block id 0..24 (NUM_BLOCKS). Display names live in itemdefs.asm.
%include "common.inc"
default rel

global block_flags, block_tiles, block_hardness, block_tool, block_harvest_level
global block_drop, block_dig_sound, block_step_sound, block_flammable

section .rodata
;             AIR STONE GRASS DIRT COBBLE PLANKS LOG LEAVES SAND GLASS BRICK BEDROCK TABLE
block_flags: db 0,  3,    3,    3,   3,     3,     3,  1,     3,   5,    3,    3,      3
;               COAL IRON GOLD DIAMOND FURNACE LIT CHEST GRAVEL TNT FIRE SBRICK MOSSY
             db 3,   3,   3,   3,      3,      3,  3,    3,     3,  0,   3,     3

; tiles per block: top, side, bottom
block_tiles:
    db 0, 0, 0                          ; AIR
    db 0, 0, 0                          ; STONE
    db 1, 2, 3                          ; GRASS
    db 3, 3, 3                          ; DIRT
    db 4, 4, 4                          ; COBBLE
    db 5, 5, 5                          ; PLANKS
    db 7, 6, 7                          ; LOG
    db 8, 8, 8                          ; LEAVES
    db 9, 9, 9                          ; SAND
    db 10, 10, 10                       ; GLASS
    db 11, 11, 11                       ; BRICK
    db 12, 12, 12                       ; BEDROCK
    db TILE_TABLE_TOP, TILE_TABLE_SIDE, 5 ; CRAFTING_TABLE
    db TILE_COAL_ORE, TILE_COAL_ORE, TILE_COAL_ORE
    db TILE_IRON_ORE, TILE_IRON_ORE, TILE_IRON_ORE
    db TILE_GOLD_ORE, TILE_GOLD_ORE, TILE_GOLD_ORE
    db TILE_DIAMOND_ORE, TILE_DIAMOND_ORE, TILE_DIAMOND_ORE
    db 0, TILE_FURNACE_FRONT, 0         ; FURNACE
    db 0, TILE_FURNACE_LIT, 0           ; FURNACE_LIT
    db TILE_CHEST_TOP, TILE_CHEST_SIDE, TILE_CHEST_TOP
    db TILE_GRAVEL, TILE_GRAVEL, TILE_GRAVEL
    db TILE_TNT_TOP, TILE_TNT_SIDE, TILE_TNT_TOP
    db 0, 0, 0                          ; FIRE (drawn by fire.asm, skipped by the mesher)
    db TILE_STONE_BRICK, TILE_STONE_BRICK, TILE_STONE_BRICK
    db TILE_MOSSY_BRICK, TILE_MOSSY_BRICK, TILE_MOSSY_BRICK

align 4
; seconds-scale hardness; negative = unbreakable
block_hardness:
    dd 0.0, 1.5, 0.6, 0.5, 2.0, 2.0, 2.0, 0.2, 0.5, 0.3, 2.0, -1.0, 2.5
    dd 3.0, 3.0, 3.0, 3.0, 3.5, 3.5, 2.5, 0.6, 0.0, 0.0, 1.5, 1.5

;                  AIR STONE GRASS DIRT COBBLE PLANKS LOG LEAVES SAND GLASS BRICK BEDROCK TABLE
block_tool:       db 0, TOOL_PICKAXE, TOOL_SHOVEL, TOOL_SHOVEL, TOOL_PICKAXE, TOOL_AXE, TOOL_AXE, 0, TOOL_SHOVEL, 0, TOOL_PICKAXE, 0, TOOL_AXE
;                  COAL IRON GOLD DIAMOND FURNACE LIT CHEST GRAVEL TNT FIRE SBRICK MOSSY
                  db TOOL_PICKAXE, TOOL_PICKAXE, TOOL_PICKAXE, TOOL_PICKAXE, TOOL_PICKAXE, TOOL_PICKAXE, TOOL_AXE, TOOL_SHOVEL, 0, 0, TOOL_PICKAXE, TOOL_PICKAXE
; minimum pickaxe level to harvest (0 = anything; 1 wood, 2 stone, 3 iron/diamond)
block_harvest_level: db 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0
                  db 1, 2, 3, 3, 1, 1, 0, 0, 0, 0, 1, 1
; harvested item (LEAVES: 0, the apple chance is rolled by the game)
block_drop:       db 0, COBBLE, DIRT, DIRT, COBBLE, PLANKS, LOG, 0, SAND, 0, BRICK, 0, CRAFTING_TABLE
                  db COAL, IRON_ORE, GOLD_ORE, DIAMOND, FURNACE, FURNACE, CHEST, GRAVEL, TNT, 0, STONE_BRICK, MOSSY_STONE_BRICK
block_dig_sound:
    db 0, SND_DIG_STONE, SND_DIG_SOFT, SND_DIG_SOFT, SND_DIG_STONE, SND_DIG_WOOD, SND_DIG_WOOD
    db SND_DIG_SOFT, SND_DIG_SOFT, SND_DIG_GLASS, SND_DIG_STONE, SND_DIG_STONE, SND_DIG_WOOD
    db SND_DIG_STONE, SND_DIG_STONE, SND_DIG_STONE, SND_DIG_STONE, SND_DIG_STONE, SND_DIG_STONE
    db SND_DIG_WOOD, SND_DIG_SOFT, SND_DIG_SOFT, SND_DIG_SOFT, SND_DIG_STONE, SND_DIG_STONE
block_step_sound:
    db 0, SND_STEP_STONE, SND_STEP_SOFT, SND_STEP_SOFT, SND_STEP_STONE, SND_STEP_WOOD, SND_STEP_WOOD
    db SND_STEP_SOFT, SND_STEP_SOFT, SND_STEP_STONE, SND_STEP_STONE, SND_STEP_STONE, SND_STEP_WOOD
    db SND_STEP_STONE, SND_STEP_STONE, SND_STEP_STONE, SND_STEP_STONE, SND_STEP_STONE, SND_STEP_STONE
    db SND_STEP_WOOD, SND_STEP_SOFT, SND_STEP_SOFT, SND_STEP_SOFT, SND_STEP_STONE, SND_STEP_STONE
; chance in % per fire tick that a neighbouring fire burns the block (TNT: ignites)
;                AIR STONE GRASS DIRT COBBLE PLANKS LOG LEAVES SAND GLASS BRICK BEDROCK TABLE
block_flammable: db 0, 0,    0,    0,   0,     20,    5,  30,    0,   0,    0,    0,      20
;                COAL IRON GOLD DIAMOND FURNACE LIT CHEST GRAVEL TNT FIRE SBRICK MOSSY
                 db 0,   0,   0,   0,      0,      0,  20,   0,     100, 0,   0,     0
