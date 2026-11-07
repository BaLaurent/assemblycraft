; blockdefs.asm - per-block flags, atlas tiles and display names.
%include "common.inc"
default rel

global block_flags, block_tiles, block_names

section .rodata
;             AIR STONE GRASS DIRT COBBLE PLANKS LOG LEAVES SAND GLASS BRICK BEDROCK
block_flags: db 0,  3,    3,    3,   3,     3,     3,  1,     3,   5,    3,    3

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

name_air:     db "Air", 0
name_stone:   db "Stone", 0
name_grass:   db "Grass", 0
name_dirt:    db "Dirt", 0
name_cobble:  db "Cobblestone", 0
name_planks:  db "Planks", 0
name_log:     db "Log", 0
name_leaves:  db "Leaves", 0
name_sand:    db "Sand", 0
name_glass:   db "Glass", 0
name_brick:   db "Bricks", 0
name_bedrock: db "Bedrock", 0

align 8
block_names:
    dq name_air, name_stone, name_grass, name_dirt, name_cobble, name_planks
    dq name_log, name_leaves, name_sand, name_glass, name_brick, name_bedrock
