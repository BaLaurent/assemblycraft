; common.inc - shared constants and struct layouts for every AssemblyCraft module.
; Every .asm file includes this first. It switches to .note.GNU-stack, so the
; including file MUST select its own section before emitting anything.

section .note.GNU-stack noalloc noexec nowrite progbits

; ---- world ----------------------------------------------------------------
%define WORLD_X        256
%define WORLD_Y        64
%define WORLD_Z        256
%define WORLD_VOLUME   4194304          ; index = (y<<16)|(z<<8)|x

; ---- chunks ---------------------------------------------------------------
%define CHUNK          16
%define CHUNKS_X       16
%define CHUNKS_Y       4
%define CHUNKS_Z       16
%define NUM_CHUNKS     1024             ; index = (cy*16 + cz)*16 + cx

; ---- block ids ------------------------------------------------------------
%define AIR            0
%define STONE          1
%define GRASS          2
%define DIRT           3
%define COBBLE         4
%define PLANKS         5
%define LOG            6
%define LEAVES         7
%define SAND           8
%define GLASS          9
%define BRICK          10
%define BEDROCK        11
%define NUM_BLOCKS     12

%define FLAG_SOLID     1
%define FLAG_OPAQUE    2
%define FLAG_CULL_SAME 4

; ---- mesh / texture -------------------------------------------------------
%define MAX_CHUNK_VERTS    98304        ; 4096 blocks * 6 faces * 4
%define VERTEX_SIZE        16
%define ATLAS_PX           256
%define TILE_PX            16
%define TEX_UNITS_PER_TILE 256          ; texcoords in 1/16 px; atlas = 4096 units

; ---- save file ------------------------------------------------------------
%define WORLD_HDR_SIZE  48
%define WORLD_FILE_SIZE 4194352
%define HOTBAR_SLOTS    9

; ---- syscalls -------------------------------------------------------------
%define SYS_READ    0
%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_CLOSE   3
%define SYS_RENAME  82
%define SYS_UNLINK  87
%define O_RDONLY    0
%define O_WCT       0x241               ; O_WRONLY|O_CREAT|O_TRUNC
%define MODE_644    420
%define ENOENT      2
%define EINTR       4
%define ENAMETOOLONG 36

; ---- structs --------------------------------------------------------------
struc INPUT
    .fwd:    resd 1                     ; W=+1 S=-1
    .strafe: resd 1                     ; D=+1 A=-1
    .jump:   resd 1
    .down:   resd 1
    .sprint: resd 1
endstruc

struc FRAMEINPUT
    .move:        resb INPUT_size
    .look_dx:     resd 1                ; float pixels
    .look_dy:     resd 1                ; float pixels
    .lmb_held:    resd 1
    .lmb_pressed: resd 1
    .rmb_held:    resd 1
    .rmb_pressed: resd 1
    .mmb_pressed: resd 1
    .slot:        resd 1                ; -1 or 0..8
    .scroll:      resd 1                ; +1 = wheel up
    .toggle_fly:  resd 1
    .save:        resd 1
    .captured:    resd 1
endstruc

struc PLAYER
    .x:         resd 1                  ; floats; .y = feet
    .y:         resd 1
    .z:         resd 1
    .vx:        resd 1
    .vy:        resd 1
    .vz:        resd 1
    .yaw:       resd 1
    .pitch:     resd 1
    .on_ground: resd 1                  ; int32
    .flying:    resd 1                  ; int32
endstruc

struc RAYHIT
    .bx: resd 1                         ; block hit
    .by: resd 1
    .bz: resd 1
    .px: resd 1                         ; cell entered just before it
    .py: resd 1
    .pz: resd 1
endstruc

struc WORLDHDR
    .magic:  resb 8                     ; "ACRAFT01"
    .seed:   resd 1
    .px:     resd 1
    .py:     resd 1
    .pz:     resd 1
    .yaw:    resd 1
    .pitch:  resd 1
    .flying: resb 1
    .sel:    resb 1
    .hotbar: resb 9
    .pad:    resb 5
endstruc

struc VERTEX
    .x:   resw 1
    .y:   resw 1
    .z:   resw 1
    .pad: resw 1
    .u:   resw 1
    .v:   resw 1
    .r:   resb 1
    .g:   resb 1
    .b:   resb 1
    .a:   resb 1
endstruc
