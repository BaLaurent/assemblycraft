; blockdefs.asm - per-block flags, atlas tiles, digging and harvest rules.
; Indexed by block id 0..12 (NUM_BLOCKS). Display names live in itemdefs.asm.
%include "common.inc"
default rel

global block_flags, block_tiles, block_hardness, block_tool, block_needs_tool
global block_drop, block_dig_sound, block_step_sound

section .rodata
;             AIR STONE GRASS DIRT COBBLE PLANKS LOG LEAVES SAND GLASS BRICK BEDROCK TABLE
block_flags: db 0,  3,    3,    3,   3,     3,     3,  1,     3,   5,    3,    3,      3

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

align 4
; seconds-scale hardness; negative = unbreakable
block_hardness:
    dd 0.0, 1.5, 0.6, 0.5, 2.0, 2.0, 2.0, 0.2, 0.5, 0.3, 2.0, -1.0, 2.5

;                  AIR STONE GRASS DIRT COBBLE PLANKS LOG LEAVES SAND GLASS BRICK BEDROCK TABLE
block_tool:       db 0, TOOL_PICKAXE, TOOL_SHOVEL, TOOL_SHOVEL, TOOL_PICKAXE, TOOL_AXE, TOOL_AXE, 0, TOOL_SHOVEL, 0, TOOL_PICKAXE, 0, TOOL_AXE
block_needs_tool: db 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0
; harvested item (LEAVES: 0, the apple chance is rolled by the game)
block_drop:       db 0, COBBLE, DIRT, DIRT, COBBLE, PLANKS, LOG, 0, SAND, 0, BRICK, 0, CRAFTING_TABLE
block_dig_sound:
    db 0, SND_DIG_STONE, SND_DIG_SOFT, SND_DIG_SOFT, SND_DIG_STONE, SND_DIG_WOOD, SND_DIG_WOOD
    db SND_DIG_SOFT, SND_DIG_SOFT, SND_DIG_GLASS, SND_DIG_STONE, SND_DIG_STONE, SND_DIG_WOOD
block_step_sound:
    db 0, SND_STEP_STONE, SND_STEP_SOFT, SND_STEP_SOFT, SND_STEP_STONE, SND_STEP_WOOD, SND_STEP_WOOD
    db SND_STEP_SOFT, SND_STEP_SOFT, SND_STEP_STONE, SND_STEP_STONE, SND_STEP_STONE, SND_STEP_WOOD
