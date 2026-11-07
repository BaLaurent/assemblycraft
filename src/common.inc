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
%define CRAFTING_TABLE 12
%define NUM_BLOCKS     13

; ---- item ids (13..31 unused) ---------------------------------------------
%define STICK          32
%define WOOD_PICKAXE   33
%define WOOD_AXE       34
%define WOOD_SHOVEL    35
%define WOOD_SWORD     36
%define STONE_PICKAXE  37
%define STONE_AXE      38
%define STONE_SHOVEL   39
%define STONE_SWORD    40
%define APPLE          41
%define PORKCHOP       42
%define NUM_ITEMS      43

; ---- tools ----------------------------------------------------------------
%define TOOL_NONE      0
%define TOOL_PICKAXE   1
%define TOOL_AXE       2
%define TOOL_SHOVEL    3
%define TOOL_SWORD     4
%define TIER_WOOD      1
%define TIER_STONE     2

%define FLAG_SOLID     1
%define FLAG_OPAQUE    2
%define FLAG_CULL_SAME 4

; ---- mesh / texture -------------------------------------------------------
%define MAX_CHUNK_VERTS    98304        ; 4096 blocks * 6 faces * 4
%define VERTEX_SIZE        16
%define ATLAS_PX           256
%define TILE_PX            16
%define TEX_UNITS_PER_TILE 256          ; texcoords in 1/16 px; atlas = 4096 units

; atlas tiles beyond the 0.1 block tiles 0..12
%define TILE_TABLE_TOP     13
%define TILE_TABLE_SIDE    14
%define TILE_CRACK0        16           ; crack stages 16..25
%define TILE_HEART_FULL    48
%define TILE_HEART_HALF    49
%define TILE_HEART_EMPTY   50
%define TILE_FOOD_FULL     51
%define TILE_FOOD_HALF     52
%define TILE_FOOD_EMPTY    53
%define TILE_ZOMBIE_SKIN   64
%define TILE_ZOMBIE_FACE   65
%define TILE_ZOMBIE_SHIRT  66
%define TILE_ZOMBIE_PANTS  67
%define TILE_PIG_SKIN      68
%define TILE_PIG_FACE      69
%define TILE_PLAYER_SKIN   70
%define FONT_Y             192          ; glyph rows at atlas y 192..239, x 0..127

; ---- save file ------------------------------------------------------------
%define WORLD_HDR_SIZE  1024
%define WORLD_FILE_SIZE 4195328          ; 1024 + 4194304
%define WORLD_V1_SIZE   4194352          ; 0.1 file: 48-byte header + blocks
%define WORLD_V1_HDR    48
%define HOTBAR_SLOTS    9

; ---- game -----------------------------------------------------------------
%define MODE_SURVIVAL   0
%define MODE_CREATIVE   1
%define DAY_LENGTH      72000           ; fixed 1/60 s steps (20 minutes)
%define NEW_WORLD_TIME  6000
%define PANORAMA_SEED   20261107

%define DIFF_PEACEFUL   0
%define DIFF_EASY       1
%define DIFF_NORMAL     2
%define DIFF_HARD       3

%define CAUSE_FALL      1
%define CAUSE_ZOMBIE    2
%define CAUSE_STARVE    3
%define CAUSE_SUFFOCATE 4

%define MOB_NONE        0
%define MOB_ZOMBIE      1
%define MOB_PIG         2
%define MAX_MOBS        32
%define MAX_DROPS       64              ; item entities lying in the world

%define INV_SLOTS       36              ; 0..8 hotbar, 9..35 main
%define SLOTREF_GRID    36              ; grid cell c = 36 + c (c 0..8, 3 wide)
%define SLOTREF_RESULT  45

; ---- app states -----------------------------------------------------------
%define ST_TITLE        0
%define ST_WORLDS       1
%define ST_CREATE       2
%define ST_RENAME       3
%define ST_DELETE       4
%define ST_SETTINGS     5
%define ST_CONTROLS     6
%define ST_PLAYING      7
%define ST_PAUSED       8
%define ST_INVENTORY    9
%define ST_CRAFTING     10
%define ST_DEATH        11
%define ST_QUIT         12

; ---- key bindings (index into SETTINGS.keys) -----------------------------
%define BIND_FORWARD    0
%define BIND_BACK       1
%define BIND_LEFT       2
%define BIND_RIGHT      3
%define BIND_JUMP       4
%define BIND_SNEAK      5
%define BIND_SPRINT     6
%define BIND_INVENTORY  7
%define BIND_FLY        8
%define NUM_BINDINGS    9

; ---- sounds ---------------------------------------------------------------
%define SND_CLICK       0
%define SND_DIG_STONE   1
%define SND_DIG_WOOD    2
%define SND_DIG_SOFT    3
%define SND_DIG_GLASS   4
%define SND_STEP_STONE  5
%define SND_STEP_WOOD   6
%define SND_STEP_SOFT   7
%define SND_HURT        8
%define SND_EAT         9
%define SND_BURP        10
%define SND_ZOMBIE_SAY  11
%define SND_ZOMBIE_HURT 12
%define SND_PIG_SAY     13
%define SND_PIG_HURT    14
%define SND_TOOL_BREAK  15
%define SND_POP         16
%define NUM_SOUNDS      17

; ---- colours: packed for glColor4ub as four bytes r,g,b,a -----------------
%define RGBA(r,g,b,a) ((r)|((g)<<8)|((b)<<16)|((a)<<24))

; ---- syscalls -------------------------------------------------------------
%define SYS_READ    0
%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_CLOSE   3
%define SYS_STAT    4
%define SYS_LSEEK   8
%define SYS_PWRITE64 18
%define SYS_RENAME  82
%define SYS_MKDIR   83
%define SYS_UNLINK  87
%define SYS_TIME    201
%define SYS_GETDENTS64 217
%define O_RDONLY    0
%define O_WRONLY    1
%define O_WCT       0x241               ; O_WRONLY|O_CREAT|O_TRUNC
%define O_DIRECTORY 0x10000
%define MODE_644    420
%define ENOENT      2
%define EINTR       4
%define EEXIST      17
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
    .inventory:   resd 1                ; edge of the inventory binding
    .debug:       resd 1                ; F3 edge
    .fullscreen:  resd 1                ; F11 edge
endstruc

struc UIINPUT
    .mouse_px:     resd 1               ; int framebuffer pixels
    .mouse_py:     resd 1
    .lmb_pressed:  resd 1
    .lmb_held:     resd 1
    .rmb_pressed:  resd 1
    .shift:        resd 1
    .scroll:       resd 1
    .double_click: resd 1
    .enter:        resd 1
    .escape:       resd 1
    .backspace:    resd 1               ; presses + repeats this frame
    .key_pressed:  resd 1               ; last key code pressed this frame, or -1
    .typed_len:    resd 1
    .typed:        resb 32
endstruc

struc BODY
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
    .half_w:    resd 1                  ; float box half width
    .height:    resd 1                  ; float box height
    .speed:     resd 1                  ; float walk speed
    .kbx:       resd 1                  ; float knockback velocity (decays)
    .kbz:       resd 1
    .fall:      resd 1                  ; float distance fallen since last on ground
    .blocked:   resd 1                  ; int32: 1 if an X or Z collision happened this step
endstruc                                ; 68 bytes

struc RAYHIT
    .bx: resd 1                         ; block hit
    .by: resd 1
    .bz: resd 1
    .px: resd 1                         ; cell entered just before it
    .py: resd 1
    .pz: resd 1
endstruc

struc ITEMSTACK
    .id:    resb 1
    .count: resb 1
    .dmg:   resw 1                      ; tool damage taken
endstruc

struc INVENTORY
    .slots:  resb INV_SLOTS * 4
    .grid:   resb 9 * 4
    .result: resb 4
    .cursor: resb 4
endstruc

struc SURVIVAL
    .health:          resd 1
    .food:            resd 1
    .saturation:      resd 1            ; float
    .exhaustion:      resd 1            ; float
    .regen_timer:     resd 1
    .starve_timer:    resd 1
    .invuln:          resd 1
    .hurt_flash:      resd 1
    .suffocate_timer: resd 1
    .eat_timer:       resd 1
    .eat_sound:       resd 1
    .dead:            resd 1
    .death_cause:     resd 1
endstruc

struc MOB
    .body:     resb BODY_size
    .type:     resd 1
    .health:   resd 1
    .hurt:     resd 1                   ; steps
    .cooldown: resd 1                   ; steps
    .ai_timer: resd 1                   ; steps
    .panic:    resd 1                   ; steps
    .walk:     resd 1                   ; float, degrees of walk-cycle phase
    .input:    resb INPUT_size
endstruc

struc MOBSAVE
    .type:   resd 1
    .health: resd 1
    .x:      resd 1                     ; floats
    .y:      resd 1
    .z:      resd 1
endstruc

; v2 world file header; offsets are load-bearing (save files, verification patches)
struc WORLDHDR
    .magic:      resb 8                 ; "ACRAFT02"
    .seed:       resd 1
    .mode:       resd 1
    .time:       resd 1
    .name:       resb 33                ; NUL-terminated, <= 32 chars
    .pad0:       resb 3
    .spawn_x:    resd 1
    .spawn_y:    resd 1
    .spawn_z:    resd 1
    .player:     resb BODY_size         ; @68
    .health:     resd 1                 ; @136
    .food:       resd 1
    .saturation: resd 1                 ; float
    .exhaustion: resd 1                 ; float
    .sel:        resd 1                 ; @152
    .inventory:  resb INV_SLOTS * 4     ; @156
    .mob_count:  resd 1                 ; @300
    .mobs:       resb MAX_MOBS * MOBSAVE_size ; @304
    .pad:        resb 80                ; @944
endstruc

; 0.1 header (48 bytes, magic "ACRAFT01")
%define V1_SEED    8
%define V1_PX      12
%define V1_PY      16
%define V1_PZ      20
%define V1_YAW     24
%define V1_PITCH   28
%define V1_FLYING  32
%define V1_SEL     33
%define V1_HOTBAR  34

struc SETTINGS
    .fov:          resd 1               ; 50..110, default 70
    .sensitivity:  resd 1               ; 10..300 %, 100
    .render_dist:  resd 1               ; 2..16 chunks, 8
    .volume:       resd 1               ; 0..100, 100
    .difficulty:   resd 1               ; 0..3, 2
    .invert_mouse: resd 1               ; 0/1, 0
    .vsync:        resd 1               ; 0/1, 1
    .fullscreen:   resd 1               ; 0/1, 0
    .gui_scale:    resd 1               ; 0 = auto, 1..4
    .keys:         resd NUM_BINDINGS    ; GLFW key codes, 32..348
endstruc

struc TEXTFIELD
    .buf: resb 33
    .pad: resb 3
    .len: resd 1
    .max: resd 1
endstruc

struc SLIDERDEF
    .value:  resq 1                     ; int32*
    .prefix: resq 1                     ; zstr
    .suffix: resq 1                     ; zstr
    .min:    resd 1
    .max:    resd 1
endstruc

struc WORLDENTRY
    .file:  resb 64                     ; file name only
    .name:  resb 33
    .pad:   resb 7
    .mtime: resq 1
    .mode:  resd 1                      ; 0, 1, or 2 = legacy v1
    .seed:  resd 1
    .valid: resd 1
    .pad2:  resd 1
endstruc                                ; 128 bytes

struc SFXLAYER
    .sound:  resd 1
    .wave:   resd 1                     ; 0 noise, 1 square, 2 saw
    .f0:     resd 1                     ; floats
    .f1:     resd 1
    .lp:     resd 1
    .hp:     resd 1                     ; int32
    .env:    resd 1                     ; int32: 0 exp, 1 linear
    .half:   resd 1                     ; floats
    .attack: resd 1
    .start:  resd 1
    .dur:    resd 1
    .amp:    resd 1
    .vdepth: resd 1
    .vrate:  resd 1
endstruc

; an item entity lying in the world (not saved with the world)
struc DROP
    .x:     resd 1                      ; floats, .y = bottom
    .y:     resd 1
    .z:     resd 1
    .vx:    resd 1
    .vy:    resd 1
    .vz:    resd 1
    .age:   resd 1                      ; steps since spawn
    .delay: resd 1                      ; steps before it can be picked up
    .id:    resb 1                      ; 0 = free slot
    .count: resb 1
    .dmg:   resw 1
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
