; structures.asm - the sites of the world: villages, dungeons, crypts and faction camps.
; region_plan decides the sites of one 512 x 512 region from the seed alone (pure, reentrant,
; absolute coordinates). structures_stamp builds the part of every nearby site that falls in one
; generated column (generator thread; every write goes through gb_set / gb_get, clipped to the
; column). structures_fill_chest rolls the loot of a generated chest when its column is installed.
; At run time the sites around the player live in sites[] (local coordinates, rebuilt by
; structures_refresh), their persistent state (dungeon kills, cleared dungeons, the crypt boss) in
; WORLDHDR.sites (site_state), and structures_step re-creates the village NPCs, spawns the dungeon
; elites and wakes the crypt boss.
%include "common.inc"
default rel

global sites, site_count
global region_plan, structures_stamp, structures_fill_chest, structures_refresh
global structures_reset, structures_step, structures_nearest
global structures_on_mob_killed, structures_on_boss_killed, structures_shift, site_state

extern hash32, gen_height, gen_biome
extern world_header, world_get, world_column_ready, world_origin_x, world_origin_z
extern mobs, mob_spawn, mob_spawn_elite, folk_spawn, mob_count_type, mob_set_level
extern gear_fill_chest, gear_tier_for_level
extern rng_next, floor_i
extern game_mode, settings, player
extern rpg_state, rpg_level, rpg_add_xp, quests_on_dungeon_cleared
extern hud_banner, audio_play

%define OP_SHELL     255                ; box id: stone or mossy brick picked by the cell's hash
%define OP_IFAIR     1                  ; box flag: only replace AIR
%define OP_IFSOLID   2                  ; box flag: only replace what is not AIR
%define SPAWN_PERIOD 90                 ; steps between the spawn attempts of a dungeon
%define NPC_PERIOD   60                 ; steps between the checks for missing village NPCs
%define MAX_LIVE     3                  ; live mobs of one dungeon at a time
%define TUNNEL_STEPS 60                 ; columns a stair tunnel climbs at most
%define DUNGEON_TUNNEL 5                ; a dungeon's stair tunnel leaves its west wall at x - 5
%define CRYPT_TUNNEL 8                  ; a crypt's leaves its west wall at x - 8
%define PLAN_ENTRIES 16                 ; region plans a cache remembers

; a region plan remembered by plan_get; seed identifies the world seed (hash32(0, 0, 0))
struc PLANENT
    .valid: resd 1
    .seed:  resd 1
    .arx:   resd 1
    .arz:   resd 1
    .count: resd 1
    .age:   resd 1                      ; cache tick of the last use
    .pad:   resd 2
    .sites: resb MAX_REGION_SITES * SITE_size
endstruc

struc PLANCACHE
    .tick: resd 1
    .pad:  resd 3
    .ents: resb PLAN_ENTRIES * PLANENT_size
endstruc

; a box record: signed offsets from the origin (x, z) and y relative to the y origin, then the
; block id (0..254, or OP_SHELL) and the OP_IF* flags
%macro BOX 7-8 0                        ; dx0, y0, dz0, dx1, y1, dz1, id, flags
    db %1, %2, %3, %4, %5, %6, %7, %8
%endmacro

; CANDC key, salt, modulus: eax = hash32(candidate k in r15d, key, salt) % modulus
%macro CANDC 3
    mov     edi, r15d
    mov     esi, %1
    mov     edx, %2
    mov     ecx, %3
    call    cand_mod
%endmacro

section .rodata
align 4
; trigger box of a site relative to its (x, y, z): lo dx, dy, dz, then hi dx, dy, dz, by kind - 1
site_box:
    dd -16,  0, -16,  16, 10,  16       ; village: x and z +-16, ground .. ground + 10
    dd  -5, -1,  -5,  19,  5,  19       ; dungeon: floor - 1 .. floor + 5 over its three rooms
    dd  -7,  0,  -7,   7,  7,   7       ; crypt: floor .. floor + 7
    dd -10, -2, -10,  10,  8,  10       ; camp: ground - 2 .. ground + 8

; what a site's builder can touch relative to its (x, z): lo dx, lo dz, hi dx, hi dz, by kind - 1
foot_box:
    dd -16, -16, 16, 16                 ; village
    dd -66,  -6, 20, 20                 ; dungeon: the three rooms and the tunnel running west
    dd -69,  -9,  9,  9                 ; crypt: the hall and its tunnel
    dd -11, -11, 11, 11                 ; camp: the clearing

; the biomes a faction's camp may stand in, by faction: a bit per BIOME_*
camp_homes:
    dd (1 << BIOME_PLAINS) | (1 << BIOME_FOREST)        ; villagers
    dd (1 << BIOME_FOREST) | (1 << BIOME_MOUNTAINS)     ; bandits
    dd (1 << BIOME_SWAMP)                               ; cult
    dd (1 << BIOME_SNOW) | (1 << BIOME_MOUNTAINS)       ; beastfolk
    dd (1 << BIOME_MOUNTAINS)                           ; stonekin

c_pts:    dd -8, -8, 8, -8, -8, 8, 8, 8 ; crypt height samples: the four corners

c_half:   dd 0.5
c_one:    dd 1.0
c_eps:    dd 0.01                       ; feet standing exactly on a block top still count
c_36:     dd 36.0                       ; dungeon mobs spawn at least 6 blocks from the player
c_big:    dd 1.0e30
c_npc_r2: dd 9216.0
align 16
c_absmask: dd 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF, 0x7FFFFFFF

s_awakens: db "The Fallen King awakens!", 0
s_cleared: db "Dungeon cleared!", 0

spawn_types: db MOB_ZOMBIE, MOB_SKELETON, MOB_SPIDER

; ---- building blocks: boxes relative to a site origin -----------------------------------------
; dungeon, relative to (x, floor, z): rooms R0 (0, 0), R1 (14, 0), R2 (14, 14) and the corridors
; A (R0 - R1) and B (R1 - R2): shells, then interiors, then the openings. The floor is the cell a
; player's feet stand in, the shell's bottom is one below it.
dungeon_boxes:
    BOX  -5, -1,  -5,   5,  5,   5, OP_SHELL
    BOX   9, -1,  -5,  19,  5,   5, OP_SHELL
    BOX   9, -1,   9,  19,  5,  19, OP_SHELL
    BOX   5, -1,  -2,   9,  3,   2, OP_SHELL
    BOX  12, -1,   5,  16,  3,   9, OP_SHELL
    BOX  -4,  0,  -4,   4,  4,   4, AIR
    BOX  10,  0,  -4,  18,  4,   4, AIR
    BOX  10,  0,  10,  18,  4,  18, AIR
    BOX   6,  0,  -1,   8,  2,   1, AIR
    BOX  13,  0,   6,  15,  2,   8, AIR
    BOX   5,  0,  -1,   5,  2,   1, AIR
    BOX   9,  0,  -1,   9,  2,   1, AIR
    BOX  13,  0,   5,  15,  2,   5, AIR
    BOX  13,  0,   9,  15,  2,   9, AIR
    BOX  -5,  0,  -1,  -5,  2,   1, AIR
    BOX   0,  2,  -4,   0,  2,  -4, TORCH_WALL + DIR_N ; torches on the walls, lit rooms
    BOX  14,  2,  -4,  14,  2,  -4, TORCH_WALL + DIR_N
    BOX  14,  2,  18,  14,  2,  18, TORCH_WALL + DIR_S
%define DUNGEON_BOXES ((dungeon_boxes_end - dungeon_boxes) / 8)
dungeon_boxes_end:

; chests: dx, dy from the floor, dz, loot table (0 dungeon, 1 crypt)
dungeon_chests:
    db   3, 0,   3, 0
    db  17, 0,  -3, 0
    db  11, 0,  17, 0
    db  17, 0,  17, 0
crypt_chests:
    db   6, 0,  -6, 1
    db   6, 0,   6, 1

; crypt, relative to (x, floor, z)
crypt_boxes:
    BOX  -8, -1,  -8,   8,  8,   8, OP_SHELL
    BOX  -7,  0,  -7,   7,  7,   7, AIR
    BOX  -4,  0,  -4,  -4,  7,  -4, STONE_BRICK
    BOX   4,  0,  -4,   4,  7,  -4, STONE_BRICK
    BOX  -4,  0,   4,  -4,  7,   4, STONE_BRICK
    BOX   4,  0,   4,   4,  7,   4, STONE_BRICK
    BOX   3,  3,  -4,   3,  3,  -4, TORCH_WALL + DIR_E ; torches on the pillars
    BOX   3,  3,   4,   3,  3,   4, TORCH_WALL + DIR_E
    BOX  -3,  3,  -4,  -3,  3,  -4, TORCH_WALL + DIR_W
    BOX  -3,  3,   4,  -3,  3,   4, TORCH_WALL + DIR_W
    BOX  -8,  0,  -1,  -8,  2,   1, AIR
%define CRYPT_BOXES ((crypt_boxes_end - crypt_boxes) / 8)
crypt_boxes_end:

; one column of a stair tunnel, relative to (X, Yf, sz): the floor block, the 3 x 3 passage,
; then the walls and the ceiling wherever there is ground to line; the entrance frame closes the
; tunnel where it comes out
stair_step:
    BOX   0, 0, -1,  0, 0,  1, STONE_BRICK_STAIRS + DIR_W
    BOX   0, 1, -1,  0, 3,  1, AIR
    BOX   0, 0, -2,  0, 4, -2, OP_SHELL, OP_IFSOLID
    BOX   0, 0,  2,  0, 4,  2, OP_SHELL, OP_IFSOLID
    BOX   0, 4, -1,  0, 4,  1, OP_SHELL, OP_IFSOLID
%define STAIR_STEP ((stair_step_end - stair_step) / 8)
stair_step_end:
stair_exit:
    BOX   0, 0, -1,  0, 0,  1, STONE_BRICK_STAIRS + DIR_W, OP_IFSOLID
    BOX   0, 1, -2,  0, 3, -2, MOSSY_STONE_BRICK
    BOX   0, 1,  2,  0, 3,  2, MOSSY_STONE_BRICK
    BOX   0, 4, -2,  0, 4,  2, MOSSY_STONE_BRICK
%define STAIR_EXIT ((stair_exit_end - stair_exit) / 8)
stair_exit_end:

; village, relative to (vx, vy, vz): flattened ground, the well, the gravel paths
village_boxes:
    BOX -15,  1, -15,  15, 14,  15, AIR
    BOX -15,  0, -15,  15,  0,  15, GRASS
    BOX -15, -3, -15,  15, -1,  15, DIRT, OP_IFAIR
    BOX  -1,  1,  -1,   1,  1,   1, COBBLE
    BOX   0,  1,   0,   0,  1,   0, AIR
    BOX   0,  0,   0,   0,  0,   0, GLASS
    BOX  -1,  2,  -1,  -1,  3,  -1, LOG
    BOX   1,  2,  -1,   1,  3,  -1, LOG
    BOX  -1,  2,   1,  -1,  3,   1, LOG
    BOX   1,  2,   1,   1,  3,   1, LOG
    BOX  -1,  4,  -1,   1,  4,   1, PLANKS
    BOX   2,  0,   0,   6,  0,   0, GRAVEL
    BOX  -6,  0,   0,  -2,  0,   0, GRAVEL
    BOX   0,  0,   2,   0,  0,   6, GRAVEL
    BOX   0,  0,  -6,   0,  0,  -2, GRAVEL
%define VILLAGE_BOXES ((village_boxes_end - village_boxes) / 8)
village_boxes_end:

; a house, relative to its centre (hx, hz): cobble floor, plank walls with log corners, a window
; in the middle of every wall, a stepped plank and brick roof
house_boxes:
    BOX  -2, 0, -2,  2, 0,  2, COBBLE
    BOX  -2, 1, -2,  2, 3,  2, PLANKS
    BOX  -1, 1, -1,  1, 3,  1, AIR
    BOX  -2, 1, -2, -2, 3, -2, LOG
    BOX   2, 1, -2,  2, 3, -2, LOG
    BOX  -2, 1,  2, -2, 3,  2, LOG
    BOX   2, 1,  2,  2, 3,  2, LOG
    BOX   2, 2,  0,  2, 2,  0, GLASS
    BOX  -2, 2,  0, -2, 2,  0, GLASS
    BOX   0, 2,  2,  0, 2,  2, GLASS
    BOX   0, 2, -2,  0, 2, -2, GLASS
    BOX  -3, 4, -3,  3, 4,  3, PLANKS
    BOX  -2, 5, -2,  2, 5,  2, BRICK
    BOX  -1, 6, -1,  1, 6,  1, BRICK
%define HOUSE_BOXES ((house_boxes_end - house_boxes) / 8)
house_boxes_end:
; per house, 8 bytes: centre dx, dz from the village centre; the door cell's dx, dz from the house
; centre (the middle of the wall that faces the well); the door's facing (the direction of that
; offset from the centre); the wall torch's dx, dz from the centre (interior cell next to the
; window, against the wall opposite the door) and its id TORCH_WALL + opposite(facing)
house_tab:
    db   9,  0, -2,  0, DIR_W,  1,  1, TORCH_WALL + DIR_E
    db  -9,  0,  2,  0, DIR_E, -1,  1, TORCH_WALL + DIR_W
    db   0,  9,  0, -2, DIR_N,  1,  1, TORCH_WALL + DIR_S
    db   0, -9,  0,  2, DIR_S,  1, -1, TORCH_WALL + DIR_N

; loot tables, one entry per 4 bytes: weight, item, min count, max count
loot_dungeon:
    db 30, GOLD_COIN,       3,  8
    db 15, IRON_INGOT,      2,  5
    db 10, GOLD_INGOT,      1,  3
    db  5, DIAMOND,         1,  2
    db 12, HEALTH_POTION,   1,  2
    db  8, MANA_POTION,     1,  2
    db 10, ARROW,           8, 16
    db  5, PISTOL_ROUND,    8, 16
    db  5, COOKED_PORKCHOP, 2,  4
loot_crypt:
    db 30, GOLD_COIN,      10, 20
    db 15, DIAMOND,         2,  4
    db 20, HEALTH_POTION,   2,  3
    db 15, MANA_POTION,     2,  3
    db 20, GOLD_INGOT,      3,  6
loot_end:
align 8
loot_tabs:   dq loot_dungeon, loot_crypt
loot_counts: db (loot_crypt - loot_dungeon) / 4, (loot_end - loot_crypt) / 4
align 8
build_fns:   dq build_village, build_dungeon, build_crypt, build_camp ; by site kind - 1

section .bss
alignb 16
sites:      resb MAX_SITES * SITE_size  ; the sites around the player, local coordinates
site_count: resd 1
st_timer:   resd 1                      ; steps to the next dungeon spawn attempt
st_npc:     resd 1                      ; steps to the next check for missing village NPCs
pcell:      resd 3                      ; the player's cell, set by structures_step
gb_buf:     resq 1                      ; the GENBUF being stamped (generator thread only)
gb_x0:      resd 1                      ; its first absolute x and z
gb_z0:      resd 1
alignb 16
plan_gen:   resb PLANCACHE_size         ; region plans of the generator thread (structures_stamp)
plan_main:  resb PLANCACHE_size         ; region plans of the main thread (structures_refresh)

section .text

; ---- planning (pure, reentrant: stack only, read-only seed) -----------------------------------

; cand_mod(edi k, esi key, edx salt, ecx modulus) -> eax hash32(k, key, salt) % modulus
cand_mod:
    push    rbx
    mov     ebx, ecx
    call    hash32
    xor     edx, edx
    div     ebx
    mov     eax, edx
    pop     rbx
    ret

; floor_div3(eax n) -> eax floor(n / 3) (leaf; clobbers ecx, edx)
floor_div3:
    cdq
    mov     ecx, 3
    idiv    ecx
    test    edx, edx
    jns     .ret
    dec     eax
.ret:
    ret

; site_add(rdi SITE* dst, esi kind, edx index, ecx x, r8d y, r9d z): kind, index, position and the
; trigger box (site_box by kind); rx, rz and slot are set by tag_sites (leaf)
site_add:
    mov     [rdi + SITE.kind], esi
    mov     [rdi + SITE.index], edx
    mov     [rdi + SITE.x], ecx
    mov     [rdi + SITE.y], r8d
    mov     [rdi + SITE.z], r9d
    lea     eax, [rsi - 1]
    imul    eax, eax, 24
    lea     r10, [site_box]
    add     r10, rax
    mov     eax, [r10]
    add     eax, ecx
    mov     [rdi + SITE.lo_x], eax
    mov     eax, [r10 + 4]
    add     eax, r8d
    mov     [rdi + SITE.lo_y], eax
    mov     eax, [r10 + 8]
    add     eax, r9d
    mov     [rdi + SITE.lo_z], eax
    mov     eax, [r10 + 12]
    add     eax, ecx
    mov     [rdi + SITE.hi_x], eax
    mov     eax, [r10 + 16]
    add     eax, r8d
    mov     [rdi + SITE.hi_y], eax
    mov     eax, [r10 + 20]
    add     eax, r9d
    mov     [rdi + SITE.hi_z], eax
    ret

; tag_sites(rdi SITE* base, esi count, edx arx, ecx arz): rx, rz and the slot (index) of each (leaf)
tag_sites:
    xor     eax, eax
.l:
    cmp     eax, esi
    jae     .ret
    mov     [rdi + SITE.rx], edx
    mov     [rdi + SITE.rz], ecx
    mov     [rdi + SITE.slot], eax
    add     rdi, SITE_size
    inc     eax
    jmp     .l
.ret:
    ret

; far_from(rdi SITE* base, esi count, edx x, ecx z, r8d min_d2) -> eax 1 when every site of
; base[0..count) is at least sqrt(min_d2) blocks from (x, z) horizontally (leaf)
far_from:
    mov     eax, 1
.l:
    test    esi, esi
    jz      .ret
    mov     r9d, [rdi + SITE.x]
    sub     r9d, edx
    imul    r9d, r9d
    mov     r10d, [rdi + SITE.z]
    sub     r10d, ecx
    imul    r10d, r10d
    add     r9d, r10d
    cmp     r9d, r8d
    jb      .near
    add     rdi, SITE_size
    dec     esi
    jmp     .l
.near:
    xor     eax, eax
.ret:
    ret

; village_find(edi arx, esi arz, rdx out3) -> eax 1 when the region has a village: out3 = x,
; ground y, z. 70 % of the regions try; of 16 candidates (x, z 48 .. 463 into the region) the first
; in a PLAINS or FOREST biome (DESERT or SNOW for half of the candidates) whose ground is at least
; 98 high at the centre and within 4 of it at 25 samples (5 apart, +-10) is the village.
; Frame: [rsp] z, [rsp+4] centre height, [rsp+8] key, [rsp+12] sample dx, [rsp+16] sample dz.
village_find:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     r12d, edi
    mov     r13d, esi
    mov     r14, rdx
    mov     eax, esi
    shl     eax, 16
    xor     eax, edi
    mov     [rsp + 8], eax              ; key = arx ^ (arz << 16)
    mov     edx, 700
    call    hash32                      ; (edi, esi still arx, arz)
    xor     edx, edx
    mov     ecx, 100
    div     ecx
    cmp     edx, 70
    jae     .none
    xor     r15d, r15d
.cand:
    CANDC   [rsp + 8], 701, 416
    mov     ebx, r12d
    shl     ebx, 9
    lea     ebx, [rbx + rax + 48]       ; x
    CANDC   [rsp + 8], 702, 416
    mov     ecx, r13d
    shl     ecx, 9
    lea     ecx, [rcx + rax + 48]
    mov     [rsp], ecx                  ; z
    mov     edi, ebx
    mov     esi, ecx
    call    gen_biome
    cmp     eax, BIOME_PLAINS
    je      .biome_ok
    cmp     eax, BIOME_FOREST
    je      .biome_ok
    cmp     eax, BIOME_DESERT
    je      .alt
    cmp     eax, BIOME_SNOW
    jne     .next
.alt:
    mov     edi, r15d                   ; DESERT and SNOW villages for half of the candidates
    mov     esi, r13d
    mov     edx, 703
    call    hash32
    test    al, 1
    jz      .next
.biome_ok:
    mov     edi, ebx
    mov     esi, [rsp]
    call    gen_height
    mov     [rsp + 4], eax
    cmp     eax, 98
    jl      .next
    mov     dword [rsp + 16], -10
.gz:
    mov     dword [rsp + 12], -10
.gx:
    mov     edi, ebx
    add     edi, [rsp + 12]
    mov     esi, [rsp]
    add     esi, [rsp + 16]
    call    gen_height
    sub     eax, [rsp + 4]
    cdq
    xor     eax, edx
    sub     eax, edx                    ; |dh|
    cmp     eax, 4
    jg      .next
    add     dword [rsp + 12], 5
    cmp     dword [rsp + 12], 10
    jle     .gx
    add     dword [rsp + 16], 5
    cmp     dword [rsp + 16], 10
    jle     .gz
    mov     [r14], ebx                  ; flat enough: this is the village
    mov     eax, [rsp + 4]
    mov     [r14 + 4], eax
    mov     eax, [rsp]
    mov     [r14 + 8], eax
    mov     eax, 1
    jmp     .ret
.next:
    inc     r15d
    cmp     r15d, 16
    jb      .cand
.none:
    xor     eax, eax
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; tunnel_exit(edi sx, esi sz, edx y0) -> eax the column i (1 .. TUNNEL_STEPS) where the stair tunnel
; of stair_tunnel(sx, sz, y0) comes out, 0 when it is still under the ground after TUNNEL_STEPS
; columns. The tunnel climbs west one block per column (floor y0 + i at x = sx - i) and comes out at
; the first column where the terrain (gen_height) of the column and of the next one west is at or
; below the floor, so the exit is walkable without a jump. The one walk of the planner (tunnel_ok)
; and of the builder (stair_tunnel). Pure and reentrant: stack only, the seed is read-only.
tunnel_exit:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, 1                     ; i
.step:
    mov     edi, ebx
    sub     edi, r14d
    mov     esi, r12d
    call    gen_height
    lea     ecx, [r13 + r14 + 1]        ; Yf + 1: where the player's feet would stand
    cmp     eax, ecx
    jge     .next                       ; the ground is above the floor: keep digging
    lea     edi, [rbx - 1]
    sub     edi, r14d                   ; the next column west, where the player walks out
    mov     esi, r12d
    call    gen_height
    lea     ecx, [r13 + r14 + 1]
    cmp     eax, ecx
    jl      .found                      ; both at or below the floor: we are out
.next:
    inc     r14d
    cmp     r14d, TUNNEL_STEPS
    jbe     .step
    xor     r14d, r14d                  ; still under the ground: no way out
.found:
    mov     eax, r14d
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; tunnel_ok(edi sx, esi sz, edx floor) -> eax 1 when the stair tunnel that leaves a site with the
; floor y `floor` at x = sx (y0 = floor - 1, as the builders call stair_tunnel) comes out within
; TUNNEL_STEPS columns and the feet of the exit (floor + i) are higher than SEA_LEVEL: the way out
; is neither sealed in the rock nor flooded by a sea, a lake or a river. Pure.
tunnel_ok:
    push    rbx
    mov     ebx, edx
    dec     edx
    call    tunnel_exit
    test    eax, eax
    jz      .ret                        ; no way out
    add     eax, ebx                    ; the feet of the exit: y0 + i + 1
    cmp     eax, SEA_LEVEL
    setg    al
    movzx   eax, al
.ret:
    pop     rbx
    ret

; dungeon_try(edi arx, esi arz, edx k, rcx out3) -> eax 1 when candidate k (x, z 80 .. 431 into the
; region) lies in a land biome (not OCEAN or RIVER), the ground at (0, 0), (14, 0) and (14, 14)
; reaches 12 above the floor y = clamp(ground - 24, 20, 80) and its stair tunnel comes out above the
; sea (tunnel_ok); out3 = x, floor y, z.
; Frame: [rsp] z, [rsp+4] floor, [rsp+8] key, [rsp+12] the height the corners must reach.
dungeon_try:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     r12d, edi
    mov     r13d, esi
    mov     r15d, edx
    mov     r14, rcx
    mov     eax, esi
    shl     eax, 16
    xor     eax, edi
    mov     [rsp + 8], eax
    CANDC   [rsp + 8], 711, 352
    mov     ebx, r12d
    shl     ebx, 9
    lea     ebx, [rbx + rax + 80]       ; x
    CANDC   [rsp + 8], 712, 352
    mov     ecx, r13d
    shl     ecx, 9
    lea     ecx, [rcx + rax + 80]
    mov     [rsp], ecx                  ; z
    mov     edi, ebx
    mov     esi, ecx
    call    gen_biome
    cmp     eax, BIOME_OCEAN
    je      .no
    cmp     eax, BIOME_RIVER
    je      .no
    mov     edi, ebx
    mov     esi, [rsp]
    call    gen_height
    lea     ecx, [rax - 24]
    mov     edx, 20
    cmp     ecx, edx
    cmovl   ecx, edx
    mov     edx, 80
    cmp     ecx, edx
    cmovg   ecx, edx
    mov     [rsp + 4], ecx              ; floor y
    add     ecx, 12
    mov     [rsp + 12], ecx
    cmp     eax, ecx
    jl      .no
    lea     edi, [rbx + 14]
    mov     esi, [rsp]
    call    gen_height
    cmp     eax, [rsp + 12]
    jl      .no
    lea     edi, [rbx + 14]
    mov     esi, [rsp]
    add     esi, 14
    call    gen_height
    cmp     eax, [rsp + 12]
    jl      .no
    lea     edi, [rbx - DUNGEON_TUNNEL] ; the way out must exist and stay dry
    mov     esi, [rsp]
    mov     edx, [rsp + 4]
    call    tunnel_ok
    test    eax, eax
    jz      .no
    mov     [r14], ebx
    mov     eax, [rsp + 4]
    mov     [r14 + 4], eax
    mov     eax, [rsp]
    mov     [r14 + 8], eax
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; crypt_try(edi arx, esi arz, edx k, rcx out3) -> eax 1 when candidate k (x, z 80 .. 431 into the
; region) lies in a land biome (not OCEAN or RIVER), has ground reaching 14 above the floor y =
; clamp(ground - 30, 15, 70) at its centre and at (+-8, +-8) and its stair tunnel comes out above
; the sea (tunnel_ok); out3 = x, floor y, z.
; Frame: [rsp] z, [rsp+4] floor, [rsp+8] key, [rsp+12] the height the ground must reach.
crypt_try:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     r12d, edi
    mov     r13d, esi
    mov     r15d, edx
    mov     r14, rcx
    mov     eax, esi
    shl     eax, 16
    xor     eax, edi
    mov     [rsp + 8], eax
    CANDC   [rsp + 8], 721, 352
    mov     ebx, r12d
    shl     ebx, 9
    lea     ebx, [rbx + rax + 80]       ; x
    CANDC   [rsp + 8], 722, 352
    mov     ecx, r13d
    shl     ecx, 9
    lea     ecx, [rcx + rax + 80]
    mov     [rsp], ecx                  ; z
    mov     edi, ebx
    mov     esi, ecx
    call    gen_biome
    cmp     eax, BIOME_OCEAN
    je      .no
    cmp     eax, BIOME_RIVER
    je      .no
    mov     edi, ebx
    mov     esi, [rsp]
    call    gen_height
    lea     ecx, [rax - 30]
    mov     edx, 15
    cmp     ecx, edx
    cmovl   ecx, edx
    mov     edx, 70
    cmp     ecx, edx
    cmovg   ecx, edx
    mov     [rsp + 4], ecx              ; floor y
    add     ecx, 14
    mov     [rsp + 12], ecx
    cmp     eax, ecx
    jl      .no
    xor     r12d, r12d                  ; corner
.corner:
    lea     rcx, [c_pts]
    mov     edi, ebx
    add     edi, [rcx + r12*8]
    mov     esi, [rsp]
    add     esi, [rcx + r12*8 + 4]
    call    gen_height
    cmp     eax, [rsp + 12]
    jl      .no
    inc     r12d
    cmp     r12d, 4
    jb      .corner
    lea     edi, [rbx - CRYPT_TUNNEL]   ; the way out must exist and stay dry
    mov     esi, [rsp]
    mov     edx, [rsp + 4]
    call    tunnel_ok
    test    eax, eax
    jz      .no
    mov     [r14], ebx
    mov     eax, [rsp + 4]
    mov     [r14 + 4], eax
    mov     eax, [rsp]
    mov     [r14 + 8], eax
    mov     eax, 1
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; camp_plan(edi sx, esi sz, rdx out) -> eax camps placed in the 1536 x 1536 super-region (sx, sz):
; SITE records at out (5 at most, in faction order; rx, rz and slot unset). For each faction 24
; candidates (x, z 64 .. 1471 into the super-region) are tried in order; the first that stands in
; one of its home biomes, at least 128 from the camps already placed, on ground within 5 of its
; centre at the 8 samples around it (+-10) and at least 96 from the village of the region it
; falls in is the faction's camp. A faction without one has no camp here.
; Frame: [rsp] x, [rsp+4] z, [rsp+8] ground, [rsp+12] key, [rsp+16] faction, [rsp+20] unused,
; [rsp+24] village out3, [rsp+40] sample dz, [rsp+44] sample dx.
camp_plan:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56
    mov     r12d, edi
    mov     r13d, esi
    mov     r14, rdx
    xor     ebx, ebx                    ; camps so far
    mov     eax, esi
    shl     eax, 16
    xor     eax, edi
    mov     [rsp + 12], eax             ; key = sx ^ (sz << 16)
    mov     dword [rsp + 16], 0
.faction:
    xor     r15d, r15d
.cand:
    mov     edi, r15d
    mov     esi, [rsp + 12]
    mov     edx, [rsp + 16]
    add     edx, 800
    mov     ecx, 1408
    call    cand_mod
    imul    ecx, r12d, 1536
    lea     ecx, [rcx + rax + 64]
    mov     [rsp], ecx                  ; x
    mov     edi, r15d
    mov     esi, [rsp + 12]
    mov     edx, [rsp + 16]
    add     edx, 810
    mov     ecx, 1408
    call    cand_mod
    imul    ecx, r13d, 1536
    lea     ecx, [rcx + rax + 64]
    mov     [rsp + 4], ecx              ; z
    mov     edi, [rsp]
    mov     esi, ecx
    call    gen_biome
    mov     ecx, [rsp + 16]
    lea     rdx, [camp_homes]
    mov     edx, [rdx + rcx*4]
    bt      edx, eax
    jnc     .next
    mov     rdi, r14                    ; at least 128 from the camps placed before
    mov     esi, ebx
    mov     edx, [rsp]
    mov     ecx, [rsp + 4]
    mov     r8d, 128 * 128
    call    far_from
    test    eax, eax
    jz      .next
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    call    gen_height
    mov     [rsp + 8], eax
    mov     dword [rsp + 40], -10
.gz:
    mov     dword [rsp + 44], -10
.gx:
    mov     edi, [rsp]
    add     edi, [rsp + 44]
    mov     esi, [rsp + 4]
    add     esi, [rsp + 40]
    call    gen_height
    sub     eax, [rsp + 8]
    cdq
    xor     eax, edx
    sub     eax, edx
    cmp     eax, 5
    jg      .next
    add     dword [rsp + 44], 10
    cmp     dword [rsp + 44], 10
    jle     .gx
    add     dword [rsp + 40], 10
    cmp     dword [rsp + 40], 10
    jle     .gz
    mov     edi, [rsp]                  ; at least 96 from the village of its region
    sar     edi, 9
    mov     esi, [rsp + 4]
    sar     esi, 9
    lea     rdx, [rsp + 24]
    call    village_find
    test    eax, eax
    jz      .accept
    mov     eax, [rsp + 24]
    sub     eax, [rsp]
    imul    eax, eax
    mov     ecx, [rsp + 32]
    sub     ecx, [rsp + 4]
    imul    ecx, ecx
    add     eax, ecx
    cmp     eax, 96 * 96
    jb      .next
.accept:
    imul    eax, ebx, SITE_size
    lea     rdi, [r14 + rax]
    mov     esi, SITE_CAMP
    mov     edx, [rsp + 16]
    mov     ecx, [rsp]
    mov     r8d, [rsp + 8]
    mov     r9d, [rsp + 4]
    call    site_add
    inc     ebx
    jmp     .done_faction
.next:
    inc     r15d
    cmp     r15d, 24
    jb      .cand
.done_faction:
    inc     dword [rsp + 16]
    cmp     dword [rsp + 16], NUM_FACTIONS
    jb      .faction
    mov     eax, ebx
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; region_plan(edi arx, esi arz, rdx SITE* out) -> eax count: the sites of region (arx, arz), blocks
; arx * 512 .. arx * 512 + 511, in absolute coordinates, at most MAX_REGION_SITES, in this order:
; the village (0 or 1), the dungeons (1 or 2: the first valid dungeon_try of 32 candidates, then a
; second one in half of the regions, both at least 48 from the other sites), the crypt (only in
; regions with even arx and arz: the first valid crypt_try of 32 candidates at least 48 from the
; other sites) and the camps whose centre lies in the region (SITE_CAMP, index = faction, in
; faction order). A dungeon or crypt is valid only when its stair tunnel comes out above the sea.
; Every record carries its region and its slot (its index in the output). Pure: it reads the world
; seed through hash32, gen_height and gen_biome and writes only out.
; Frame: [rsp] pos3 (x, y, z), [rsp+16] camps in the super-region, [rsp+20] want a second dungeon,
; [rsp+24] dungeons found, [rsp+32] the super-region's camps (5 SITE records).
region_plan:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 312
    mov     r12d, edi
    mov     r13d, esi
    mov     r14, rdx
    xor     r15d, r15d                  ; sites written
    mov     edi, r12d                   ; ---- the village
    mov     esi, r13d
    lea     rdx, [rsp]
    call    village_find
    test    eax, eax
    jz      .dungeons
    mov     rdi, r14
    mov     esi, SITE_VILLAGE
    xor     edx, edx
    mov     ecx, [rsp]
    mov     r8d, [rsp + 4]
    mov     r9d, [rsp + 8]
    call    site_add
    inc     r15d
.dungeons:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, 713
    call    hash32
    and     eax, 1
    mov     [rsp + 20], eax             ; a second dungeon in half of the regions
    mov     dword [rsp + 24], 0
    xor     ebx, ebx                    ; candidate k
.d_cand:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, ebx
    lea     rcx, [rsp]
    call    dungeon_try
    test    eax, eax
    jz      .d_next
    mov     rdi, r14                    ; at least 48 from the village and the other dungeon
    mov     esi, r15d
    mov     edx, [rsp]
    mov     ecx, [rsp + 8]
    mov     r8d, 48 * 48
    call    far_from
    test    eax, eax
    jz      .d_next
    imul    eax, r15d, SITE_size
    lea     rdi, [r14 + rax]
    mov     esi, SITE_DUNGEON
    mov     edx, [rsp + 24]             ; index: the dungeon's order in the region
    mov     ecx, [rsp]
    mov     r8d, [rsp + 4]
    mov     r9d, [rsp + 8]
    call    site_add
    inc     r15d
    inc     dword [rsp + 24]
    cmp     dword [rsp + 24], 2
    jae     .crypt
    cmp     dword [rsp + 20], 0
    je      .crypt
.d_next:
    inc     ebx
    cmp     ebx, 32
    jb      .d_cand
.crypt:
    test    r12d, 1                     ; one crypt per 2 x 2 regions: even arx and arz only
    jnz     .camps
    test    r13d, 1
    jnz     .camps
    xor     ebx, ebx
.c_cand:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, ebx
    lea     rcx, [rsp]
    call    crypt_try
    test    eax, eax
    jz      .c_next
    mov     rdi, r14
    mov     esi, r15d
    mov     edx, [rsp]
    mov     ecx, [rsp + 8]
    mov     r8d, 48 * 48
    call    far_from
    test    eax, eax
    jz      .c_next
    imul    eax, r15d, SITE_size
    lea     rdi, [r14 + rax]
    mov     esi, SITE_CRYPT
    xor     edx, edx
    mov     ecx, [rsp]
    mov     r8d, [rsp + 4]
    mov     r9d, [rsp + 8]
    call    site_add
    inc     r15d
    jmp     .camps
.c_next:
    inc     ebx
    cmp     ebx, 32
    jb      .c_cand
.camps:
    mov     eax, r12d                   ; the super-region of 3 x 3 regions
    call    floor_div3
    mov     edi, eax
    mov     eax, r13d
    call    floor_div3
    mov     esi, eax
    lea     rdx, [rsp + 32]
    call    camp_plan
    mov     [rsp + 16], eax
    xor     ebx, ebx
.camp:
    cmp     ebx, [rsp + 16]
    jae     .tag
    imul    eax, ebx, SITE_size
    lea     rsi, [rsp + 32]
    add     rsi, rax
    mov     eax, [rsi + SITE.x]
    sar     eax, 9
    cmp     eax, r12d
    jne     .camp_next
    mov     eax, [rsi + SITE.z]
    sar     eax, 9
    cmp     eax, r13d
    jne     .camp_next
    imul    eax, r15d, SITE_size
    lea     rdi, [r14 + rax]
    mov     ecx, SITE_size / 8
    rep     movsq
    inc     r15d
.camp_next:
    inc     ebx
    jmp     .camp
.tag:
    mov     rdi, r14
    mov     esi, r15d
    mov     edx, r12d
    mov     ecx, r13d
    call    tag_sites
    mov     eax, r15d
    add     rsp, 312
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; plan_get(rdi PLANCACHE* cache, esi arx, edx arz) -> rax the PLANENT of that region for the current
; world seed. A miss plans the region (region_plan) into the least recently used entry.
plan_get:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    hash32
    mov     r14d, eax                   ; fingerprint of the seed
    inc     dword [rbx + PLANCACHE.tick]
    mov     r15d, [rbx + PLANCACHE.tick]
    lea     rax, [rbx + PLANCACHE.ents]
    mov     ecx, PLAN_ENTRIES
.hit:
    cmp     dword [rax + PLANENT.valid], 0
    je      .hit_next
    cmp     [rax + PLANENT.seed], r14d
    jne     .hit_next
    cmp     [rax + PLANENT.arx], r12d
    jne     .hit_next
    cmp     [rax + PLANENT.arz], r13d
    jne     .hit_next
    mov     [rax + PLANENT.age], r15d
    jmp     .ret
.hit_next:
    add     rax, PLANENT_size
    dec     ecx
    jnz     .hit
    lea     rax, [rbx + PLANCACHE.ents]
    mov     rdx, rax                    ; victim: an empty entry, else the least recently used
    mov     esi, -1
    mov     ecx, PLAN_ENTRIES
.victim:
    cmp     dword [rax + PLANENT.valid], 0
    je      .empty
    mov     edi, [rax + PLANENT.age]
    cmp     edi, esi
    jae     .victim_next
    mov     esi, edi
    mov     rdx, rax
.victim_next:
    add     rax, PLANENT_size
    dec     ecx
    jnz     .victim
    jmp     .plan
.empty:
    mov     rdx, rax
.plan:
    mov     rbx, rdx
    mov     dword [rbx + PLANENT.valid], 0
    mov     [rbx + PLANENT.seed], r14d
    mov     [rbx + PLANENT.arx], r12d
    mov     [rbx + PLANENT.arz], r13d
    mov     [rbx + PLANENT.age], r15d
    mov     edi, r12d
    mov     esi, r13d
    lea     rdx, [rbx + PLANENT.sites]
    call    region_plan
    mov     [rbx + PLANENT.count], eax
    mov     dword [rbx + PLANENT.valid], 1
    mov     rax, rbx
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- stamping (generator thread, or the main thread in selftests: file statics are safe) ------

; gb_set(edi x, esi y, edx z, ecx id): the cell (absolute x, z) of the column being stamped;
; anything outside it, or outside y 0..255, is dropped (leaf)
gb_set:
    sub     edi, [gb_x0]
    cmp     edi, 15
    ja      .ret
    sub     edx, [gb_z0]
    cmp     edx, 15
    ja      .ret
    cmp     esi, 255
    ja      .ret
    shl     esi, 8
    shl     edx, 4
    or      esi, edx
    or      esi, edi
    mov     rax, [gb_buf]
    mov     [rax + rsi + GENBUF.blocks], cl
.ret:
    ret

; gb_get(edi x, esi y, edx z) -> eax the block there, AIR outside the column being stamped (leaf)
gb_get:
    xor     eax, eax
    sub     edi, [gb_x0]
    cmp     edi, 15
    ja      .ret
    sub     edx, [gb_z0]
    cmp     edx, 15
    ja      .ret
    cmp     esi, 255
    ja      .ret
    shl     esi, 8
    shl     edx, 4
    or      esi, edx
    or      esi, edi
    mov     rax, [gb_buf]
    movzx   eax, byte [rax + rsi + GENBUF.blocks]
.ret:
    ret

; box_fill(edi x0, esi y0, edx z0, ecx x1, r8d y1, r9d z1, eax op): applies op to every cell of the
; inclusive box that lies in the column being stamped (gb_get / gb_set drop the rest, and the
; loops are clipped to it). op = id | flags << 8: the block id, or OP_SHELL for a stone brick
; (mossy with 3 in 10) chosen by hash of the cell; flag OP_IFAIR places only where the cell is
; AIR, OP_IFSOLID only where it is not.
; Frame: [rsp] x1, [rsp+4] y1, [rsp+8] z1, [rsp+12] op, [rsp+16] x0, [rsp+20] z0.
box_fill:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     r10d, [gb_x0]               ; clip to the column and to y 0..255
    cmp     edi, r10d
    cmovl   edi, r10d
    add     r10d, 15
    cmp     ecx, r10d
    cmovg   ecx, r10d
    cmp     edi, ecx
    jg      .done
    mov     r10d, [gb_z0]
    cmp     edx, r10d
    cmovl   edx, r10d
    add     r10d, 15
    cmp     r9d, r10d
    cmovg   r9d, r10d
    cmp     edx, r9d
    jg      .done
    xor     r10d, r10d
    cmp     esi, r10d
    cmovl   esi, r10d
    mov     r10d, 255
    cmp     r8d, r10d
    cmovg   r8d, r10d
    cmp     esi, r8d
    jg      .done
    mov     [rsp], ecx
    mov     [rsp + 4], r8d
    mov     [rsp + 8], r9d
    mov     [rsp + 12], eax
    mov     [rsp + 16], edi
    mov     [rsp + 20], edx
    mov     r13d, esi                   ; y
.y:
    mov     r14d, [rsp + 20]            ; z
.z:
    mov     r12d, [rsp + 16]            ; x
.x:
    mov     r15d, [rsp + 12]
    mov     ebx, r15d
    and     ebx, 255                    ; block id, or OP_SHELL
    test    r15d, (OP_IFAIR | OP_IFSOLID) << 8
    jz      .place
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    call    gb_get
    test    r15d, OP_IFAIR << 8
    jz      .need_solid
    test    eax, eax
    jnz     .next                       ; something is there already
    jmp     .place
.need_solid:
    test    eax, eax
    jz      .next                       ; nothing there to line
.place:
    cmp     ebx, OP_SHELL
    jne     .set
    imul    edi, r12d, 7
    add     edi, r13d
    mov     esi, r14d
    mov     edx, 630
    call    hash32
    xor     edx, edx
    mov     ecx, 10
    div     ecx
    mov     ebx, STONE_BRICK
    mov     eax, MOSSY_STONE_BRICK
    cmp     edx, 3
    cmovb   ebx, eax
.set:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, ebx
    call    gb_set
.next:
    inc     r12d
    cmp     r12d, [rsp]
    jle     .x
    inc     r14d
    cmp     r14d, [rsp + 8]
    jle     .z
    inc     r13d
    cmp     r13d, [rsp + 4]
    jle     .y
.done:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; run_boxes(rdi table, esi count, edx ox, ecx oy, r8d oz): box_fill for each 8-byte record of the
; table (signed offsets from the origin, then the id and the flags)
run_boxes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, r8d
.rec:
    movsx   edi, byte [rbx]
    add     edi, r13d
    movsx   esi, byte [rbx + 1]
    add     esi, r14d
    movsx   edx, byte [rbx + 2]
    add     edx, r15d
    movsx   ecx, byte [rbx + 3]
    add     ecx, r13d
    movsx   r8d, byte [rbx + 4]
    add     r8d, r14d
    movsx   r9d, byte [rbx + 5]
    add     r9d, r15d
    movzx   eax, word [rbx + 6]         ; id | flags << 8
    call    box_fill
    add     rbx, 8
    dec     r12d
    jnz     .rec
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; stair_tunnel(edi sx, esi sz, edx y0): from an opening in the wall at x = sx a 3 x 3 passage
; climbs west one block per column (floor y0 + i at x = sx - i) up to the column tunnel_exit finds,
; where an entrance frame closes it. The way out depends on the seed alone, so every column of the
; site's footprint reaches the same tunnel. The planner only accepts sites whose tunnel comes out
; (tunnel_ok), so a call without a way out (tunnel_exit 0) builds nothing.
stair_tunnel:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    call    tunnel_exit                 ; edi, esi and edx are still the arguments
    mov     r15d, eax                   ; the exit column
    test    eax, eax
    jz      .ret
    mov     r14d, 1                     ; i
.dig:
    cmp     r14d, r15d
    jae     .exit
    lea     rdi, [stair_step]
    mov     esi, STAIR_STEP
    mov     edx, ebx
    sub     edx, r14d
    lea     ecx, [r13 + r14]
    mov     r8d, r12d
    call    run_boxes
    inc     r14d
    jmp     .dig
.exit:
    lea     rdi, [stair_exit]
    mov     esi, STAIR_EXIT
    mov     edx, ebx
    sub     edx, r14d
    lea     ecx, [r13 + r14]
    mov     r8d, r12d
    call    run_boxes
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; place_chest(edi x, esi y, edx z, ecx table): a CHEST block (absolute cell) and, when the cell is
; in the column being stamped, its GENCHEST record; the loot is rolled when the column is installed
; (structures_fill_chest). table: 0 dungeon, 1 crypt.
place_chest:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12d, edi
    mov     r13d, esi
    mov     r14d, edx
    mov     ebx, ecx
    mov     ecx, CHEST
    call    gb_set
    mov     eax, r12d
    sub     eax, [gb_x0]
    cmp     eax, 15
    ja      .ret
    mov     eax, r14d
    sub     eax, [gb_z0]
    cmp     eax, 15
    ja      .ret
    cmp     r13d, 255
    ja      .ret
    mov     rax, [gb_buf]
    mov     ecx, [rax + GENBUF.nchests]
    cmp     ecx, MAX_GEN_CHESTS
    jae     .ret
    inc     dword [rax + GENBUF.nchests]
    shl     ecx, 4
    lea     rdx, [rax + rcx + GENBUF.chests]
    mov     [rdx + GENCHEST.x], r12d
    mov     [rdx + GENCHEST.y], r13d
    mov     [rdx + GENCHEST.z], r14d
    mov     [rdx + GENCHEST.table], ebx
.ret:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; place_chests(rdi table, esi count, edx ox, ecx oz, r8d oy): a chest per 4-byte record (dx, dy, dz,
; loot table), relative to (ox, oy, oz)
place_chests:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, r8d
.chest:
    movsx   edi, byte [rbx]
    add     edi, r13d
    movsx   esi, byte [rbx + 1]
    add     esi, r15d
    movsx   edx, byte [rbx + 2]
    add     edx, r14d
    movzx   ecx, byte [rbx + 3]
    call    place_chest
    add     rbx, 4
    dec     r12d
    jnz     .chest
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; build_dungeon(rdi SITE*): three stone-brick rooms joined by corridors, a stair tunnel climbing
; to the surface from the west wall of the first room, and a chest in each room (the third
; room has two); clipped to the column being stamped
build_dungeon:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, [rdi + SITE.x]
    mov     r13d, [rdi + SITE.z]
    mov     r14d, [rdi + SITE.y]        ; floor
    lea     rdi, [dungeon_boxes]
    mov     esi, DUNGEON_BOXES
    mov     edx, r12d
    mov     ecx, r14d
    mov     r8d, r13d
    call    run_boxes
    lea     edi, [r12 - DUNGEON_TUNNEL]
    mov     esi, r13d
    lea     edx, [r14 - 1]
    call    stair_tunnel
    lea     rdi, [dungeon_chests]
    mov     esi, 4
    mov     edx, r12d
    mov     ecx, r13d
    mov     r8d, r14d
    call    place_chests
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; build_crypt(rdi SITE*): one big pillared hall, a stair tunnel from its west wall, two chests
build_crypt:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, [rdi + SITE.x]
    mov     r13d, [rdi + SITE.z]
    mov     r14d, [rdi + SITE.y]        ; floor
    lea     rdi, [crypt_boxes]
    mov     esi, CRYPT_BOXES
    mov     edx, r12d
    mov     ecx, r14d
    mov     r8d, r13d
    call    run_boxes
    lea     edi, [r12 - CRYPT_TUNNEL]
    mov     esi, r13d
    lea     edx, [r14 - 1]
    call    stair_tunnel
    lea     rdi, [crypt_chests]
    mov     esi, 2
    mov     edx, r12d
    mov     ecx, r13d
    mov     r8d, r14d
    call    place_chests
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; build_village(rdi SITE*): the ground flattened to the village's height over x, z +-15 (trees
; cut away), a well in the middle, gravel paths along both axes and four houses whose closed
; wooden doors face the well, each with a wall torch inside
; Frame: [rsp] house x, [rsp+4] house z.
build_village:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, [rdi + SITE.x]        ; vx
    mov     r13d, [rdi + SITE.y]        ; vy
    mov     r14d, [rdi + SITE.z]        ; vz
    lea     rdi, [village_boxes]
    mov     esi, VILLAGE_BOXES
    mov     edx, r12d
    mov     ecx, r13d
    mov     r8d, r14d
    call    run_boxes
    lea     rbx, [house_tab]
    mov     r15d, 4
.house:
    movsx   edx, byte [rbx]
    add     edx, r12d
    movsx   r8d, byte [rbx + 1]
    add     r8d, r14d
    mov     [rsp], edx
    mov     [rsp + 4], r8d
    lea     rdi, [house_boxes]
    mov     esi, HOUSE_BOXES
    mov     ecx, r13d
    call    run_boxes
    movsx   edi, byte [rbx + 2]         ; the door: a closed wooden door in the wall facing the
    add     edi, [rsp]                  ; well, lower half then upper half (param bit 0)
    movsx   edx, byte [rbx + 3]
    add     edx, [rsp + 4]
    lea     esi, [r13 + 1]
    mov     ecx, edi
    lea     r8d, [r13 + 1]
    mov     r9d, edx
    movzx   eax, byte [rbx + 4]
    lea     eax, [WOOD_DOOR + rax*4]
    call    box_fill
    movsx   edi, byte [rbx + 2]
    add     edi, [rsp]
    movsx   edx, byte [rbx + 3]
    add     edx, [rsp + 4]
    lea     esi, [r13 + 2]
    mov     ecx, edi
    mov     r8d, esi
    mov     r9d, edx
    movzx   eax, byte [rbx + 4]
    lea     eax, [WOOD_DOOR + 1 + rax*4]
    call    box_fill
    movsx   edi, byte [rbx + 5]         ; the wall torch inside, against the opposite plank wall
    add     edi, [rsp]
    movsx   edx, byte [rbx + 6]
    add     edx, [rsp + 4]
    lea     esi, [r13 + 2]
    mov     ecx, edi
    mov     r8d, esi
    mov     r9d, edx
    movzx   eax, byte [rbx + 7]
    call    box_fill
    add     rbx, 8
    dec     r15d
    jnz     .house
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; camp_ground(edi biome, esi ground y) -> eax top block, edx filler block of a camp's clearing
; (the generator's materials: grass over dirt; sand in a desert; on a mountain stone from 150 and a
; snow block top from 195) (leaf)
camp_ground:
    mov     eax, GRASS
    mov     edx, DIRT
    cmp     edi, BIOME_DESERT
    jne     .not_desert
    mov     eax, SAND
    mov     edx, SAND
    ret
.not_desert:
    cmp     edi, BIOME_MOUNTAINS
    jne     .ret
    cmp     esi, 150
    jl      .ret
    mov     eax, STONE
    mov     edx, STONE
    cmp     esi, 195
    jl      .ret
    mov     eax, SNOW_BLOCK
.ret:
    ret

; build_camp(rdi SITE*): the clearing of a faction camp: x, z +-10 flattened to the ground height
; h of its centre (the biome's top block at h, its filler under it down to h - 3 where there is air,
; air from h + 1 to h + 12), a fence post with a torch on it in the middle. The camp's buildings
; are not built yet.
build_camp:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, [rdi + SITE.x]
    mov     r13d, [rdi + SITE.y]        ; h
    mov     r14d, [rdi + SITE.z]
    mov     edi, r12d
    mov     esi, r14d
    call    gen_biome
    mov     edi, eax
    mov     esi, r13d
    call    camp_ground
    mov     ebx, eax                    ; top block
    mov     r15d, edx                   ; filler
    lea     edi, [r12 - 10]             ; the air above
    lea     esi, [r13 + 1]
    lea     edx, [r14 - 10]
    lea     ecx, [r12 + 10]
    lea     r8d, [r13 + 12]
    lea     r9d, [r14 + 10]
    xor     eax, eax
    call    box_fill
    lea     edi, [r12 - 10]             ; the filler below, where the ground was lower
    lea     esi, [r13 - 3]
    lea     edx, [r14 - 10]
    lea     ecx, [r12 + 10]
    lea     r8d, [r13 - 1]
    lea     r9d, [r14 + 10]
    lea     eax, [r15 + (OP_IFAIR << 8)]
    call    box_fill
    lea     edi, [r12 - 10]             ; the top
    mov     esi, r13d
    lea     edx, [r14 - 10]
    lea     ecx, [r12 + 10]
    mov     r8d, r13d
    lea     r9d, [r14 + 10]
    mov     eax, ebx
    call    box_fill
    mov     edi, r12d                   ; the post
    lea     esi, [r13 + 1]
    mov     edx, r14d
    mov     ecx, edi
    mov     r8d, esi
    mov     r9d, edx
    mov     eax, FENCE
    call    box_fill
    mov     edi, r12d
    lea     esi, [r13 + 2]
    mov     edx, r14d
    mov     ecx, edi
    mov     r8d, esi
    mov     r9d, edx
    mov     eax, TORCH
    call    box_fill
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; structures_stamp(rdi GENBUF*): builds the part of every site that falls in the column (GENBUF.cx,
; .cz): the plans of the column's region and the eight around it (plan_get, 16-entry cache private to
; the generator thread) in the order village, dungeon, crypt, camp, so a stair tunnel that crosses
; a village still cuts through it; each site whose footprint (foot_box) meets the column is built
; by its builder, clipped to the column. Resets GENBUF.nchests; chests are appended by place_chest.
; Generator thread only (or the main thread while no generator runs).
; Frame: [rsp + i*8] the plan of region (rx + i % 3 - 1, rz + i / 3 - 1).
structures_stamp:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 72
    mov     [gb_buf], rdi
    mov     eax, [rdi + GENBUF.cx]
    mov     r12d, eax
    shl     eax, 4
    mov     [gb_x0], eax
    mov     eax, [rdi + GENBUF.cz]
    mov     r13d, eax
    shl     eax, 4
    mov     [gb_z0], eax
    mov     dword [rdi + GENBUF.nchests], 0
    sar     r12d, 5                     ; the column's region
    sar     r13d, 5
    xor     r14d, r14d
.fetch:
    mov     eax, r14d
    xor     edx, edx
    mov     ecx, 3
    div     ecx                         ; eax = row, edx = column of the 3 x 3 block
    lea     esi, [r12 + rdx - 1]
    lea     edx, [r13 + rax - 1]
    lea     rdi, [plan_gen]
    call    plan_get
    mov     [rsp + r14*8], rax
    inc     r14d
    cmp     r14d, 9
    jb      .fetch
    mov     r15d, 1                     ; site kind
.kind:
    xor     r14d, r14d                  ; plan
.plan:
    mov     rbx, [rsp + r14*8]
    xor     r12d, r12d                  ; site
.site:
    cmp     r12d, [rbx + PLANENT.count]
    jae     .next_plan
    imul    eax, r12d, SITE_size
    lea     r13, [rbx + PLANENT.sites]
    add     r13, rax
    cmp     [r13 + SITE.kind], r15d
    jne     .next_site
    lea     eax, [r15 - 1]
    shl     eax, 4
    lea     rcx, [foot_box]
    add     rcx, rax
    mov     eax, [r13 + SITE.x]
    add     eax, [rcx + 8]
    cmp     eax, [gb_x0]
    jl      .next_site                  ; the footprint ends west of the column
    mov     eax, [r13 + SITE.x]
    add     eax, [rcx]
    mov     edx, [gb_x0]
    add     edx, 15
    cmp     eax, edx
    jg      .next_site                  ; or starts east of it
    mov     eax, [r13 + SITE.z]
    add     eax, [rcx + 12]
    cmp     eax, [gb_z0]
    jl      .next_site
    mov     eax, [r13 + SITE.z]
    add     eax, [rcx + 4]
    mov     edx, [gb_z0]
    add     edx, 15
    cmp     eax, edx
    jg      .next_site
    mov     rdi, r13
    lea     rax, [build_fns]
    mov     ecx, r15d
    call    [rax + rcx*8 - 8]
.next_site:
    inc     r12d
    jmp     .site
.next_plan:
    inc     r14d
    cmp     r14d, 9
    jb      .plan
    inc     r15d
    cmp     r15d, SITE_CAMP
    jbe     .kind
    add     rsp, 72
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; structures_fill_chest(rdi CONTAINER*, rsi GENCHEST*): makes the record the generated chest's
; container (its cell and kind CONT_CHEST are set, the cells cleared) and rolls its loot, a pure
; function of the chest (cell, table) and the world seed. 4..6 rolls from the loot table (0 dungeon,
; 1 crypt): roll r: h = hash32(x*31 + r, z*17 + y, 640); the entry is the weighted pick h % total,
; count = min + (h >> 16) % (max - min + 1), cell = (h >> 8) % 27 or the next free cell. Then
; rolled gear (gear_fill_chest, seed hash32(x, z, 650)): a dungeon's chest gets one LOOT_CHEST piece
; of tier max(2, gear_tier_for_level(rpg_level)), the crypt's two LOOT_BOSS pieces of tier 13.
; Frame: [rsp] r, [rsp+4] rolls, [rsp+8] h.
structures_fill_chest:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     rbx, rdi
    mov     r15d, [rsi + GENCHEST.table]
    mov     r12d, [rsi + GENCHEST.x]
    mov     r13d, [rsi + GENCHEST.y]
    mov     r14d, [rsi + GENCHEST.z]
    mov     [rbx + CONTAINER.x], r12d
    mov     [rbx + CONTAINER.y], r13d
    mov     [rbx + CONTAINER.z], r14d
    mov     byte [rbx + CONTAINER.kind], CONT_CHEST
    lea     rdi, [rbx + CONTAINER.slots]
    mov     ecx, (CONTAINER_size - CONTAINER.slots) / 4
    xor     eax, eax
    rep     stosd
    mov     edi, r12d
    mov     esi, r14d
    mov     edx, 641
    call    hash32
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    add     edx, 4
    mov     [rsp + 4], edx              ; rolls
    mov     dword [rsp], 0
.roll:
    imul    edi, r12d, 31
    add     edi, [rsp]
    imul    esi, r14d, 17
    add     esi, r13d
    mov     edx, 640
    call    hash32
    mov     [rsp + 8], eax
    lea     rax, [loot_tabs]
    mov     rsi, [rax + r15*8]          ; first entry
    lea     rax, [loot_counts]
    movzx   ecx, byte [rax + r15]       ; entries
    mov     r8, rsi
    xor     edx, edx                    ; total weight
.sum:
    movzx   eax, byte [r8]
    add     edx, eax
    add     r8, 4
    dec     ecx
    jnz     .sum
    mov     ecx, edx
    mov     eax, [rsp + 8]
    xor     edx, edx
    div     ecx                         ; edx = h % total
.find:
    movzx   eax, byte [rsi]
    cmp     edx, eax
    jb      .found
    sub     edx, eax
    add     rsi, 4
    jmp     .find
.found:
    movzx   r9d, byte [rsi + 1]         ; item
    movzx   ecx, byte [rsi + 3]
    movzx   r8d, byte [rsi + 2]
    sub     ecx, r8d
    inc     ecx                         ; max - min + 1
    mov     eax, [rsp + 8]
    shr     eax, 16
    xor     edx, edx
    div     ecx
    add     r8d, edx                    ; count
    mov     eax, [rsp + 8]
    shr     eax, 8
    xor     edx, edx
    mov     ecx, 27
    div     ecx                         ; edx = first cell to try
.cell:
    cmp     byte [rbx + CONTAINER.slots + rdx*4 + ITEMSTACK.id], 0
    je      .free
    inc     edx
    cmp     edx, 27
    jb      .cell
    xor     edx, edx
    jmp     .cell
.free:
    mov     [rbx + CONTAINER.slots + rdx*4 + ITEMSTACK.id], r9b
    mov     [rbx + CONTAINER.slots + rdx*4 + ITEMSTACK.count], r8b
    inc     dword [rsp]
    mov     eax, [rsp]
    cmp     eax, [rsp + 4]
    jb      .roll
    mov     edi, r12d                   ; the gear: seed hash32(x, z, 650)
    mov     esi, r14d
    mov     edx, 650
    call    hash32
    mov     r14d, eax
    test    r15d, r15d
    jnz     .crypt
    call    rpg_level
    mov     edi, eax
    call    gear_tier_for_level
    mov     edx, 2
    cmp     eax, edx
    cmovl   eax, edx
    mov     edx, eax                    ; tier max(2, tier for the player's level)
    mov     esi, LOOT_CHEST
    mov     ecx, 1
    jmp     .gear
.crypt:
    mov     esi, LOOT_BOSS              ; the crypt: two pieces of tier 13
    mov     edx, 13
    mov     ecx, 2
.gear:
    mov     rdi, rbx
    mov     r8d, r14d
    call    gear_fill_chest
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- the sites around the player (local coordinates) -------------------------------------------

; player_region() -> eax rx, edx rz: the region ((floor(player) + origin) sar 9) the player is in
player_region:
    push    rbx
    movss   xmm0, [player + BODY.x]
    call    floor_i
    add     eax, [world_origin_x]
    sar     eax, 9
    mov     ebx, eax
    movss   xmm0, [player + BODY.z]
    call    floor_i
    add     eax, [world_origin_z]
    sar     eax, 9
    mov     edx, eax
    mov     eax, ebx
    pop     rbx
    ret

; structures_refresh(): rebuilds sites[] from the plans of the 3 x 3 regions around the player's
; region (main-thread plan cache), x and z fields minus the world origin. Call it when the
; player's region changes, after a rebase and once after a world is loaded.
structures_refresh:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    call    player_region
    mov     r12d, eax
    mov     r13d, edx
    xor     r15d, r15d                  ; sites cached
    mov     r14d, -1                    ; dz
.row:
    mov     ebx, -1                     ; dx
.col:
    lea     rdi, [plan_main]
    lea     esi, [r12 + rbx]
    lea     edx, [r13 + r14]
    call    plan_get
    mov     ecx, [rax + PLANENT.count]
    lea     rsi, [rax + PLANENT.sites]
.copy:
    test    ecx, ecx
    jz      .next_col
    cmp     r15d, MAX_SITES
    jae     .next_col
    imul    edx, r15d, SITE_size
    lea     rdi, [sites]
    add     rdi, rdx
    mov     r8d, ecx
    mov     ecx, SITE_size / 4
    rep     movsd
    sub     rdi, SITE_size
    mov     eax, [world_origin_x]
    sub     [rdi + SITE.x], eax
    sub     [rdi + SITE.lo_x], eax
    sub     [rdi + SITE.hi_x], eax
    mov     eax, [world_origin_z]
    sub     [rdi + SITE.z], eax
    sub     [rdi + SITE.lo_z], eax
    sub     [rdi + SITE.hi_z], eax
    inc     r15d
    lea     ecx, [r8 - 1]
    jmp     .copy
.next_col:
    inc     ebx
    cmp     ebx, 1
    jle     .col
    inc     r14d
    cmp     r14d, 1
    jle     .row
    mov     [site_count], r15d
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; structures_shift(edi dx, esi dz): the world origin moved by (dx, dz) (world_rebase ran already):
; the cached sites are rebuilt against the new origin
structures_shift:
    jmp     structures_refresh

; structures_reset(): forget the cached sites and the spawn timers (the per-site state belongs to
; the world: WORLDHDR.sites)
structures_reset:
    mov     dword [site_count], 0
    mov     dword [st_timer], 0
    mov     dword [st_npc], 0
    ret

; ---- per-site state, WORLDHDR.sites --------------------------------------------------------------

; site_find(rdi SITE*) -> rax the SITESTATE of that site (rx, rz, slot), or 0 (leaf)
site_find:
    mov     ecx, [world_header + WORLDHDR.site_count]
    mov     eax, MAX_SITESTATES
    cmp     ecx, eax
    cmova   ecx, eax
    lea     rax, [world_header + WORLDHDR.sites]
    mov     edx, [rdi + SITE.rx]
    mov     esi, [rdi + SITE.rz]
    mov     r8d, [rdi + SITE.slot]
.l:
    test    ecx, ecx
    jz      .none
    cmp     [rax + SITESTATE.rx], edx
    jne     .n
    cmp     [rax + SITESTATE.rz], esi
    jne     .n
    cmp     [rax + SITESTATE.slot], r8b
    je      .ret
.n:
    add     rax, SITESTATE_size
    dec     ecx
    jmp     .l
.none:
    xor     eax, eax
.ret:
    ret

; ss_by_origin(edi origin) -> rax the SITESTATE a MOB.origin (record index + 1) names, or 0 (leaf)
ss_by_origin:
    lea     eax, [rdi - 1]
    mov     ecx, [world_header + WORLDHDR.site_count]
    mov     edx, MAX_SITESTATES
    cmp     ecx, edx
    cmova   ecx, edx
    cmp     eax, ecx
    jae     .none
    imul    eax, eax, SITESTATE_size
    lea     rcx, [world_header + WORLDHDR.sites]
    add     rax, rcx
    ret
.none:
    xor     eax, eax
    ret

; ss_origin(rdi SITESTATE*) -> eax the MOB.origin of the site's mobs (record index + 1) (leaf)
ss_origin:
    lea     rax, [world_header + WORLDHDR.sites]
    sub     rdi, rax
    mov     eax, edi
    xor     edx, edx
    mov     ecx, SITESTATE_size
    div     ecx
    inc     eax
    ret

; site_state(rdi SITE*) -> rax the persistent state of the site, keyed by (rx, rz, slot): the
; existing record, else a new one (kind, no kills, not cleared). When WORLDHDR.sites is full the
; record whose region lies farthest (Chebyshev) from the player's, and that no live mob's origin
; points at, is replaced; 0 when none can be.
; Frame: [rsp .. +1024) one byte per record: a live mob's origin points at it; [rsp+1024] the
; farthest distance so far, [rsp+1032] its record.
site_state:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 1048
    mov     rbx, rdi
    call    site_find
    test    rax, rax
    jnz     .ret
    mov     ecx, [world_header + WORLDHDR.site_count]
    cmp     ecx, MAX_SITESTATES
    jae     .full
    imul    edx, ecx, SITESTATE_size    ; room left: append
    lea     rax, [world_header + WORLDHDR.sites]
    add     rax, rdx
    inc     ecx
    mov     [world_header + WORLDHDR.site_count], ecx
    jmp     .fill
.full:
    lea     rdi, [rsp]
    mov     ecx, MAX_SITESTATES / 8
    xor     eax, eax
    rep     stosq
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
.mob:
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .mob_next
    mov     eax, [rcx + MOB.origin]
    dec     eax
    cmp     eax, MAX_SITESTATES
    jae     .mob_next
    mov     byte [rsp + rax], 1
.mob_next:
    add     rcx, MOB_size
    dec     edx
    jnz     .mob
    call    player_region
    mov     r12d, eax
    mov     r13d, edx
    lea     r14, [world_header + WORLDHDR.sites]
    xor     r15d, r15d
    mov     dword [rsp + 1024], -1
    mov     qword [rsp + 1032], 0
.rec:
    cmp     r15d, MAX_SITESTATES
    jae     .pick
    cmp     byte [rsp + r15], 0
    jne     .rec_next
    mov     eax, [r14 + SITESTATE.rx]
    sub     eax, r12d
    cdq
    xor     eax, edx
    sub     eax, edx                    ; |drx|
    mov     ecx, [r14 + SITESTATE.rz]
    sub     ecx, r13d
    mov     edx, ecx
    sar     edx, 31
    xor     ecx, edx
    sub     ecx, edx                    ; |drz|
    cmp     eax, ecx
    cmovl   eax, ecx                    ; the Chebyshev distance
    cmp     eax, [rsp + 1024]
    jle     .rec_next
    mov     [rsp + 1024], eax
    mov     [rsp + 1032], r14
.rec_next:
    add     r14, SITESTATE_size
    inc     r15d
    jmp     .rec
.pick:
    mov     rax, [rsp + 1032]
    test    rax, rax
    jz      .ret                        ; every record is in use by a live mob
.fill:
    mov     ecx, [rbx + SITE.rx]
    mov     [rax + SITESTATE.rx], ecx
    mov     ecx, [rbx + SITE.rz]
    mov     [rax + SITESTATE.rz], ecx
    mov     ecx, [rbx + SITE.slot]
    mov     [rax + SITESTATE.slot], cl
    mov     ecx, [rbx + SITE.kind]
    mov     [rax + SITESTATE.kind], cl
    mov     byte [rax + SITESTATE.kills], 0
    mov     byte [rax + SITESTATE.flags], 0
.ret:
    add     rsp, 1048
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- NPCs, spawners, counters, queries ----------------------------------------------------------

; ensure_folk(edi faction, esi role, edx fclass, ecx dx, r8d dz, r9 SITE* site): the folk of that
; faction and role with its home in the cell (site x + dx, site z + dz), at the site's ground level
; + 1, is spawned (folk_spawn) unless a live one of that faction and role already has that home
; (within 0.01) or its column is not loaded
; Frame: [rsp] home x, [rsp+4] y, [rsp+8] home z, [rsp+12] fclass.
ensure_folk:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 16
    mov     r12d, edi
    mov     r14d, esi
    mov     [rsp + 12], edx
    mov     r13d, [r9 + SITE.x]
    add     r13d, ecx                   ; the folk's cell
    mov     ebx, [r9 + SITE.z]
    add     ebx, r8d
    mov     eax, [r9 + SITE.y]
    inc     eax
    cvtsi2ss xmm1, eax
    movss   [rsp + 4], xmm1
    cvtsi2ss xmm0, r13d
    addss   xmm0, [c_half]
    movss   [rsp], xmm0
    cvtsi2ss xmm2, ebx
    addss   xmm2, [c_half]
    movss   [rsp + 8], xmm2
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
.find:
    cmp     dword [rcx + MOB.type], MOB_FOLK
    jne     .next
    movzx   eax, byte [rcx + MOB.faction]
    cmp     eax, r12d
    jne     .next
    movzx   eax, byte [rcx + MOB.role]
    cmp     eax, r14d
    jne     .next
    movss   xmm3, [rcx + MOB.home_x]
    subss   xmm3, xmm0
    andps   xmm3, [c_absmask]
    comiss  xmm3, [c_eps]
    jae     .next
    movss   xmm3, [rcx + MOB.home_z]
    subss   xmm3, xmm2
    andps   xmm3, [c_absmask]
    comiss  xmm3, [c_eps]
    jb      .ret                        ; it is there already
.next:
    add     rcx, MOB_size
    dec     edx
    jnz     .find
    mov     edi, r13d
    mov     esi, ebx
    call    world_column_ready
    test    eax, eax
    jz      .ret
    mov     edi, r12d
    mov     esi, r14d
    mov     edx, [rsp + 12]
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    call    folk_spawn
.ret:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; village_npcs(): every cached village within 96 blocks of the player whose centre column is
; loaded gets its Villagers trader (cell x + 6) and leader (cell x - 6) at (x + 0.5, y + 1, z + 0.5)
; again when no live one has that home: folk are not saved
village_npcs:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    lea     rbx, [sites]
    mov     r12d, [site_count]
.site:
    test    r12d, r12d
    jz      .ret
    cmp     dword [rbx + SITE.kind], SITE_VILLAGE
    jne     .next
    cvtsi2ss xmm0, dword [rbx + SITE.x]
    addss   xmm0, [c_half]
    subss   xmm0, [player + BODY.x]
    mulss   xmm0, xmm0
    cvtsi2ss xmm1, dword [rbx + SITE.z]
    addss   xmm1, [c_half]
    subss   xmm1, [player + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_npc_r2]
    ja      .next
    mov     edi, [rbx + SITE.x]
    mov     esi, [rbx + SITE.z]
    call    world_column_ready
    test    eax, eax
    jz      .next
    mov     edi, FAC_VILLAGERS
    mov     esi, ROLE_TRADER
    xor     edx, edx
    mov     ecx, 6
    xor     r8d, r8d
    mov     r9, rbx
    call    ensure_folk
    mov     edi, FAC_VILLAGERS
    mov     esi, ROLE_LEADER
    xor     edx, edx
    mov     ecx, -6
    xor     r8d, r8d
    mov     r9, rbx
    call    ensure_folk
.next:
    add     rbx, SITE_size
    dec     r12d
    jmp     .site
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; in_box(rdi SITE*, esi grow) -> eax 1 when the player's cell (pcell) lies inside the site's
; trigger box grown by `grow` blocks on every side (leaf function)
in_box:
    mov     eax, [pcell]
    mov     ecx, [rdi + SITE.lo_x]
    sub     ecx, esi
    cmp     eax, ecx
    jl      .no
    mov     ecx, [rdi + SITE.hi_x]
    add     ecx, esi
    cmp     eax, ecx
    jg      .no
    mov     eax, [pcell + 4]
    mov     ecx, [rdi + SITE.lo_y]
    sub     ecx, esi
    cmp     eax, ecx
    jl      .no
    mov     ecx, [rdi + SITE.hi_y]
    add     ecx, esi
    cmp     eax, ecx
    jg      .no
    mov     eax, [pcell + 8]
    mov     ecx, [rdi + SITE.lo_z]
    sub     ecx, esi
    cmp     eax, ecx
    jl      .no
    mov     ecx, [rdi + SITE.hi_z]
    add     ecx, esi
    cmp     eax, ecx
    jg      .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; boss_level() -> eax the level the Fallen King wakes at: the player's + 3, at least 20
; elite_level() -> eax the level of a dungeon elite: the player's + 2 (a blank character is level 1)
boss_level:
    sub     rsp, 8
    call    rpg_level
    add     rsp, 8
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx
    add     eax, 3
    mov     ecx, 20
    cmp     eax, ecx
    cmovl   eax, ecx
    ret
elite_level:
    sub     rsp, 8
    call    rpg_level
    add     rsp, 8
    mov     ecx, 1
    cmp     eax, ecx
    cmovl   eax, ecx
    add     eax, 2
    ret

; dungeon_spawn(rdi SITE*, rsi SITESTATE*): one attempt of a dungeon's spawner. A dungeon holds at
; most 3 live mobs and needs 8 kills to clear, so it spawns while live + kills < 8 (a mob that
; vanished unkilled is replaced). The mob is a random elite zombie, skeleton or spider at a random
; cell within 3 of a random room's middle, at floor level, in a loaded column, at least 6 blocks
; from the player; its MOB.origin is the site's record index + 1 and its level the player's + 2.
; Frame: [rsp] dx, [rsp+4] dz, [rsp+8] x, [rsp+12] z.
dungeon_spawn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     rbx, rdi
    mov     r12, rsi
    mov     rdi, rsi
    call    ss_origin
    mov     r13d, eax                   ; MOB.origin of this dungeon's mobs
    xor     r14d, r14d                  ; live
    lea     rcx, [mobs]
    mov     edx, MAX_MOBS
.count:
    cmp     dword [rcx + MOB.type], MOB_NONE
    je      .cnext
    cmp     [rcx + MOB.origin], r13d
    jne     .cnext
    inc     r14d
.cnext:
    add     rcx, MOB_size
    dec     edx
    jnz     .count
    cmp     r14d, MAX_LIVE
    jae     .ret
    movzx   eax, byte [r12 + SITESTATE.kills]
    add     eax, r14d
    cmp     eax, DUNGEON_KILLS
    jae     .ret
    call    rng_next
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    mov     r14d, edx                   ; room
    call    rng_next
    xor     edx, edx
    mov     ecx, 7
    div     ecx
    sub     edx, 3
    mov     [rsp], edx
    call    rng_next
    xor     edx, edx
    mov     ecx, 7
    div     ecx
    sub     edx, 3
    mov     [rsp + 4], edx
    call    rng_next
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    mov     r15d, edx                   ; type
    mov     eax, [rbx + SITE.x]
    mov     ecx, [rbx + SITE.z]
    test    r14d, r14d
    jz      .have
    add     eax, 14                     ; rooms 1 and 2 stand 14 east of room 0
    cmp     r14d, 2
    jb      .have
    add     ecx, 14                     ; room 2 also 14 south
.have:
    add     eax, [rsp]
    add     ecx, [rsp + 4]
    mov     [rsp + 8], eax
    mov     [rsp + 12], ecx
    cvtsi2ss xmm0, eax
    addss   xmm0, [c_half]
    subss   xmm0, [player + BODY.x]
    mulss   xmm0, xmm0
    cvtsi2ss xmm1, dword [rbx + SITE.y]
    subss   xmm1, [player + BODY.y]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    cvtsi2ss xmm1, ecx
    addss   xmm1, [c_half]
    subss   xmm1, [player + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [c_36]
    jb      .ret                        ; too close to the player
    mov     edi, [rsp + 8]
    mov     esi, [rsp + 12]
    call    world_column_ready
    test    eax, eax
    jz      .ret
    mov     edi, [rsp + 8]
    mov     esi, [rbx + SITE.y]
    mov     edx, [rsp + 12]
    call    world_get
    test    eax, eax
    jnz     .ret
    mov     edi, [rsp + 8]
    mov     esi, [rbx + SITE.y]
    inc     esi
    mov     edx, [rsp + 12]
    call    world_get
    test    eax, eax
    jnz     .ret
    lea     rcx, [spawn_types]
    movzx   edi, byte [rcx + r15]
    cvtsi2ss xmm0, dword [rsp + 8]
    addss   xmm0, [c_half]
    cvtsi2ss xmm1, dword [rbx + SITE.y]
    cvtsi2ss xmm2, dword [rsp + 12]
    addss   xmm2, [c_half]
    call    mob_spawn_elite
    test    eax, eax
    js      .ret
    mov     r14d, eax                   ; slot index
    imul    eax, eax, MOB_size
    lea     rcx, [mobs]
    mov     [rcx + rax + MOB.origin], r13d
    call    elite_level
    mov     edi, r14d
    mov     esi, eax
    call    mob_set_level
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; wake_boss(rdi SITE*, rsi SITESTATE*): the Fallen King wakes in the crypt: a boss at the middle
; of the hall with MOB.origin = the crypt's record index + 1, at least level 20, a roar and a banner
wake_boss:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     rdi, rsi
    call    ss_origin
    mov     r12d, eax
    mov     edi, MOB_BOSS
    cvtsi2ss xmm0, dword [rbx + SITE.x]
    addss   xmm0, [c_half]
    cvtsi2ss xmm1, dword [rbx + SITE.y]
    cvtsi2ss xmm2, dword [rbx + SITE.z]
    addss   xmm2, [c_half]
    call    mob_spawn
    test    eax, eax
    js      .ret                        ; no free slot: try again next step
    mov     r13d, eax                   ; slot index
    imul    eax, eax, MOB_size
    lea     rcx, [mobs]
    mov     [rcx + rax + MOB.origin], r12d
    call    boss_level
    mov     edi, r13d
    mov     esi, eax
    call    mob_set_level
    mov     edi, SND_BOSS_ROAR
    movss   xmm0, [c_one]
    call    audio_play
    lea     rdi, [s_awakens]
    mov     esi, RGBA(255, 80, 60, 255)
    call    hud_banner
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; structures_step(): once per fixed step. Every 60 steps the village NPCs are checked, in every
; mode. In Survival above Peaceful, every 90 steps the dungeon the player is in (box grown by 2,
; not cleared yet) tries to spawn an elite, and the crypt wakes the boss when the player is inside,
; it is not defeated and none is alive. Persistent state is created only for the sites the player
; is inside.
structures_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     eax, [st_npc]
    dec     eax
    jg      .npc_wait
    mov     eax, NPC_PERIOD
    mov     [st_npc], eax
    call    village_npcs
    jmp     .gate
.npc_wait:
    mov     [st_npc], eax
.gate:
    cmp     dword [game_mode], MODE_SURVIVAL
    jne     .ret
    cmp     dword [settings + SETTINGS.difficulty], DIFF_PEACEFUL
    je      .ret
    movss   xmm0, [player + BODY.x]
    call    floor_i
    mov     [pcell], eax
    movss   xmm0, [player + BODY.y]
    addss   xmm0, [c_eps]
    call    floor_i
    mov     [pcell + 4], eax
    movss   xmm0, [player + BODY.z]
    call    floor_i
    mov     [pcell + 8], eax
    xor     r15d, r15d                  ; 1 on the step of a spawn attempt
    mov     eax, [st_timer]
    dec     eax
    jg      .tick
    mov     eax, SPAWN_PERIOD
    mov     r15d, 1
.tick:
    mov     [st_timer], eax
    lea     rbx, [sites]
    mov     r12d, [site_count]
.site:
    test    r12d, r12d
    jz      .ret
    mov     eax, [rbx + SITE.kind]
    cmp     eax, SITE_DUNGEON
    je      .dungeon
    cmp     eax, SITE_CRYPT
    jne     .next
    mov     rdi, rbx
    xor     esi, esi
    call    in_box
    test    eax, eax
    jz      .next
    mov     edi, MOB_BOSS
    call    mob_count_type
    test    eax, eax
    jnz     .next
    mov     rdi, rbx
    call    site_state
    test    rax, rax
    jz      .next
    test    byte [rax + SITESTATE.flags], SS_CLEARED
    jnz     .next                       ; the Fallen King is dead
    mov     rdi, rbx
    mov     rsi, rax
    call    wake_boss
    jmp     .next
.dungeon:
    test    r15d, r15d
    jz      .next
    mov     rdi, rbx
    mov     esi, 2
    call    in_box
    test    eax, eax
    jz      .next
    mov     rdi, rbx
    call    site_state
    test    rax, rax
    jz      .next
    test    byte [rax + SITESTATE.flags], SS_CLEARED
    jnz     .next
    mov     rdi, rbx
    mov     rsi, rax
    call    dungeon_spawn
.next:
    add     rbx, SITE_size
    dec     r12d
    jmp     .site
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; structures_on_mob_killed(edi origin): a mob born in the dungeon with that record index + 1 died
; (any other origin, including 0 and the crypt's, is ignored). The 8th death clears the dungeon:
; SS_CLEARED, 150 + 15 per level XP, a banner, the quest hook.
structures_on_mob_killed:
    sub     rsp, 8
    call    ss_by_origin
    test    rax, rax
    jz      .done
    cmp     byte [rax + SITESTATE.kind], SITE_DUNGEON
    jne     .done
    test    byte [rax + SITESTATE.flags], SS_CLEARED
    jnz     .done
    movzx   ecx, byte [rax + SITESTATE.kills]
    inc     ecx
    mov     [rax + SITESTATE.kills], cl
    cmp     ecx, DUNGEON_KILLS
    jb      .done
    or      byte [rax + SITESTATE.flags], SS_CLEARED
    movzx   edi, byte [rpg_state + RPGSAVE.level]
    imul    edi, edi, 15
    add     edi, 150
    call    rpg_add_xp
    lea     rdi, [s_cleared]
    mov     esi, RGBA(120, 255, 120, 255)
    call    hud_banner
    mov     edi, SND_QUEST
    movss   xmm0, [c_one]
    call    audio_play
    call    quests_on_dungeon_cleared
.done:
    add     rsp, 8
    ret

; structures_on_boss_killed(edi origin): the Fallen King of the crypt with that record index + 1
; fell: the record is SS_CLEARED (any other origin is ignored)
structures_on_boss_killed:
    sub     rsp, 8
    call    ss_by_origin
    add     rsp, 8
    test    rax, rax
    jz      .ret
    cmp     byte [rax + SITESTATE.kind], SITE_CRYPT
    jne     .ret
    or      byte [rax + SITESTATE.flags], SS_CLEARED
.ret:
    ret

; structures_nearest(edi kind, esi uncleared_only) -> rax SITE* of that kind in sites[] nearest to
; the player by horizontal distance, or 0. uncleared_only skips dungeons and crypts whose state
; says SS_CLEARED (records are read, never created).
structures_nearest:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r13d, edi
    mov     r14d, esi
    xor     r15d, r15d
    movss   xmm3, [c_big]
    lea     rbx, [sites]
    mov     r12d, [site_count]
.l:
    test    r12d, r12d
    jz      .ret
    cmp     [rbx + SITE.kind], r13d
    jne     .n
    test    r14d, r14d
    jz      .measure
    cmp     r13d, SITE_DUNGEON
    je      .state
    cmp     r13d, SITE_CRYPT
    jne     .measure
.state:
    mov     rdi, rbx
    call    site_find
    test    rax, rax
    jz      .measure
    test    byte [rax + SITESTATE.flags], SS_CLEARED
    jnz     .n
.measure:
    cvtsi2ss xmm0, dword [rbx + SITE.x]
    subss   xmm0, [player + BODY.x]
    mulss   xmm0, xmm0
    cvtsi2ss xmm1, dword [rbx + SITE.z]
    subss   xmm1, [player + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, xmm3
    jae     .n
    movaps  xmm3, xmm0
    mov     r15, rbx
.n:
    add     rbx, SITE_size
    dec     r12d
    jmp     .l
.ret:
    mov     rax, r15
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
