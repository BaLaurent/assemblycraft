; structures.asm - villages, dungeons and the crypt: site planning from the world seed (pure),
; their blocks (stone-brick dungeons with chests and loot, the crypt, flattened villages), NPC
; spawns, the dungeon spawner, the boss trigger and the dungeon kill counters.
%include "common.inc"
default rel

global sites, site_count
global structures_plan, structures_generate, structures_spawn_npcs
global structures_reset, structures_step, structures_on_mob_killed, structures_nearest

extern hash32, worldgen_set_seed, worldgen_height
extern world_get, world_set, world_top_y, world_header
extern cont_create
extern mobs, mob_spawn, mob_spawn_elite, mob_spawn_npc, mob_count_type
extern rng_next, floor_i
extern game_mode, settings, player
extern rpg_state, rpg_add_xp, quests_on_dungeon_cleared
extern hud_banner, audio_play

%define OP_SHELL     255                ; box id: stone or mossy brick picked by the cell's hash
%define OP_IFAIR     1                  ; box flag: only replace AIR
%define OP_IFSOLID   2                  ; box flag: only replace what is not AIR
%define SPAWN_PERIOD 90                 ; steps between the spawn attempts of a dungeon
%define MAX_LIVE     3                  ; live mobs of one dungeon at a time
%define TUNNEL_STEPS 60                 ; columns a stair tunnel climbs at most
%define ORIGIN_CRYPT 99                 ; MOB.origin of the crypt boss
%define MAX_VILLAGES 2

; a box record: signed offsets from the origin (x, z) and y relative to the y origin, then the
; block id (0..254, or OP_SHELL) and the OP_IF* flags
%macro BOX 7-8 0                        ; dx0, y0, dz0, dx1, y1, dz1, id, flags
    db %1, %2, %3, %4, %5, %6, %7, %8
%endmacro

section .rodata
align 4
; trigger box of a site relative to its (x, y, z): lo dx, dy, dz, then hi dx, dy, dz, by kind - 1
site_box:
    dd -16, 0, -16,  16, 10, 16         ; village: x and z +-16, ground .. ground + 10
    dd  -5, -1, -5,  19,  5, 19         ; dungeon (y = 8): 7 .. 13 above its three rooms
    dd  -7, 0,  -7,   7,  7,  7         ; crypt (y = 6): 6 .. 13

v_tol:    dd 3, 6                       ; village flatness tolerance by pass
v_hmin:   dd 25, 23                     ; and its minimum ground height
c_range:  dd 3600, 12100, 1600, 16900   ; crypt distance^2 from the spawn by pass: 60..110, 40..130
c_pts:    dd 0, 0, -8, -8, 8, -8, -8, 8, 8, 8 ; crypt height samples: centre and the four corners

c_half:   dd 0.5
c_one:    dd 1.0
c_6_5:    dd 6.5
c_5_5:    dd 5.5
c_eps:    dd 0.01                       ; feet standing exactly on a block top still count
c_36:     dd 36.0                       ; dungeon mobs spawn at least 6 blocks from the player
c_big:    dd 1.0e30

s_awakens: db "The Fallen King awakens!", 0
s_cleared: db "Dungeon cleared!", 0

spawn_types: db MOB_ZOMBIE, MOB_SKELETON, MOB_SPIDER

; ---- building blocks: boxes relative to a site origin -----------------------------------------
; dungeon, relative to (ox, oz) with absolute y: rooms R0 (0, 0), R1 (14, 0), R2 (14, 14) and the
; corridors A (R0 - R1) and B (R1 - R2): shells, then interiors, then the openings
dungeon_boxes:
    BOX  -5,  7,  -5,   5, 13,   5, OP_SHELL
    BOX   9,  7,  -5,  19, 13,   5, OP_SHELL
    BOX   9,  7,   9,  19, 13,  19, OP_SHELL
    BOX   5,  7,  -2,   9, 11,   2, OP_SHELL
    BOX  12,  7,   5,  16, 11,   9, OP_SHELL
    BOX  -4,  8,  -4,   4, 12,   4, AIR
    BOX  10,  8,  -4,  18, 12,   4, AIR
    BOX  10,  8,  10,  18, 12,  18, AIR
    BOX   6,  8,  -1,   8, 10,   1, AIR
    BOX  13,  8,   6,  15, 10,   8, AIR
    BOX   5,  8,  -1,   5, 10,   1, AIR
    BOX   9,  8,  -1,   9, 10,   1, AIR
    BOX  13,  8,   5,  15, 10,   5, AIR
    BOX  13,  8,   9,  15, 10,   9, AIR
    BOX  -5,  8,  -1,  -5, 10,   1, AIR
    BOX   0, 10,  -4,   0, 10,  -4, TORCH_WALL + DIR_N ; torches on the walls, lit rooms
    BOX  14, 10,  -4,  14, 10,  -4, TORCH_WALL + DIR_N
    BOX  14, 10,  18,  14, 10,  18, TORCH_WALL + DIR_S
%define DUNGEON_BOXES ((dungeon_boxes_end - dungeon_boxes) / 8)
dungeon_boxes_end:

; chests: dx, y, dz, loot table (0 dungeon, 1 crypt)
dungeon_chests:
    db   3, 8,   3, 0
    db  17, 8,  -3, 0
    db  11, 8,  17, 0
    db  17, 8,  17, 0
crypt_chests:
    db   6, 6,  -6, 1
    db   6, 6,   6, 1

; crypt, relative to (cx, cz) with absolute y
crypt_boxes:
    BOX  -8,  5,  -8,   8, 14,   8, OP_SHELL
    BOX  -7,  6,  -7,   7, 13,   7, AIR
    BOX  -4,  6,  -4,  -4, 13,  -4, STONE_BRICK
    BOX   4,  6,  -4,   4, 13,  -4, STONE_BRICK
    BOX  -4,  6,   4,  -4, 13,   4, STONE_BRICK
    BOX   4,  6,   4,   4, 13,   4, STONE_BRICK
    BOX   3,  9,  -4,   3,  9,  -4, TORCH_WALL + DIR_E ; torches on the pillars
    BOX   3,  9,   4,   3,  9,   4, TORCH_WALL + DIR_E
    BOX  -3,  9,  -4,  -3,  9,  -4, TORCH_WALL + DIR_W
    BOX  -3,  9,   4,  -3,  9,   4, TORCH_WALL + DIR_W
    BOX  -8,  6,  -1,  -8,  8,   1, AIR
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
build_fns:   dq build_village, build_dungeon, build_crypt ; by site kind - 1

section .bss
alignb 16
sites:      resb MAX_SITES * SITE_size
site_count: resd 1
st_kills:   resd NUM_DUNGEONS           ; deaths of dungeon mobs since the last reset
st_timer:   resd 1                      ; steps to the next dungeon spawn attempt
pcell:      resd 3                      ; the player's cell, set by structures_step

section .text

; ---- planning ---------------------------------------------------------------------------------

; min_dist2(edi kind, esi x, edx z) -> eax squared horizontal distance from (x, z) to the nearest
; planned site of that kind, 0x7FFFFFFF when there is none (leaf function)
min_dist2:
    mov     eax, 0x7FFFFFFF
    mov     r8d, [site_count]
    test    r8d, r8d
    jz      .ret
    lea     rcx, [sites]
.l:
    cmp     [rcx + SITE.kind], edi
    jne     .n
    mov     r9d, [rcx + SITE.x]
    sub     r9d, esi
    imul    r9d, r9d
    mov     r10d, [rcx + SITE.z]
    sub     r10d, edx
    imul    r10d, r10d
    add     r9d, r10d
    cmp     r9d, eax
    cmovb   eax, r9d
.n:
    add     rcx, SITE_size
    dec     r8d
    jnz     .l
.ret:
    ret

; add_site(edi kind, esi index, edx x, ecx y, r8d z): appends a site, its trigger box taken from
; site_box (leaf function)
add_site:
    mov     eax, [site_count]
    cmp     eax, MAX_SITES
    jae     .ret
    inc     dword [site_count]
    imul    eax, eax, SITE_size
    lea     r9, [sites]
    add     r9, rax
    mov     [r9 + SITE.kind], edi
    mov     [r9 + SITE.index], esi
    mov     [r9 + SITE.x], edx
    mov     [r9 + SITE.y], ecx
    mov     [r9 + SITE.z], r8d
    lea     eax, [rdi - 1]
    imul    eax, eax, 24
    lea     r10, [site_box]
    add     r10, rax
    mov     eax, [r10]
    add     eax, edx
    mov     [r9 + SITE.lo_x], eax
    mov     eax, [r10 + 4]
    add     eax, ecx
    mov     [r9 + SITE.lo_y], eax
    mov     eax, [r10 + 8]
    add     eax, r8d
    mov     [r9 + SITE.lo_z], eax
    mov     eax, [r10 + 12]
    add     eax, edx
    mov     [r9 + SITE.hi_x], eax
    mov     eax, [r10 + 16]
    add     eax, ecx
    mov     [r9 + SITE.hi_y], eax
    mov     eax, [r10 + 20]
    add     eax, r8d
    mov     [r9 + SITE.hi_z], eax
.ret:
    ret

; CAND salt, base x, modulus x, base z, modulus z: candidate k (r12d) of a site search ->
; ebx = base x + hash32(k, 0, salt) % modulus x, r13d = base z + hash32(k, 1, salt) % modulus z
%macro CAND 5
    mov     edi, r12d
    xor     esi, esi
    mov     edx, %1
    call    hash32
    xor     edx, edx
    mov     ecx, %3
    div     ecx
    lea     ebx, [rdx + %2]
    mov     edi, r12d
    mov     esi, 1
    mov     edx, %1
    call    hash32
    xor     edx, edx
    mov     ecx, %5
    div     ecx
    lea     r13d, [rdx + %4]
%endmacro

; D2C: eax = squared distance of (ebx, r13d) from the middle of the world (128, 128)
%macro D2C 0
    mov     eax, ebx
    sub     eax, 128
    imul    eax, eax
    mov     ecx, r13d
    sub     ecx, 128
    imul    ecx, ecx
    add     eax, ecx
%endmacro

; structures_plan(edi seed): decides every site from the seed alone: up to two villages (index =
; order), up to six dungeons (index = bit of the cleared mask) and the crypt. No block is written,
; so a loaded world plans the sites it was built with. Heights come from worldgen_height.
; Frame: [rsp] dx, [rsp+4] dz, [rsp+8] flatness tolerance.
structures_plan:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    call    worldgen_set_seed
    mov     dword [site_count], 0
    lea     rdi, [sites]
    mov     ecx, MAX_SITES * SITE_size
    xor     eax, eax
    rep     stosb
    ; ---- villages: pass 0 wants flat ground (|dh| <= 3, h >= 25), pass 1 settles for less
    xor     r14d, r14d                  ; pass
.v_pass:
    xor     r12d, r12d                  ; candidate k
.v_cand:
    cmp     dword [site_count], MAX_VILLAGES
    jae     .v_done
    CAND    600, 24, 208, 24, 208
    D2C
    cmp     eax, 900                    ; 30..100 blocks from the middle
    jb      .v_next
    cmp     eax, 10000
    ja      .v_next
    mov     edi, SITE_VILLAGE
    mov     esi, ebx
    mov     edx, r13d
    call    min_dist2
    cmp     eax, 3600                   ; at least 60 from the other village
    jb      .v_next
    mov     edi, ebx
    mov     esi, r13d
    call    worldgen_height
    mov     r15d, eax                   ; ground height at the centre
    lea     rcx, [v_hmin]
    cmp     r15d, [rcx + r14*4]
    jl      .v_next
    lea     rcx, [v_tol]
    mov     eax, [rcx + r14*4]
    mov     [rsp + 8], eax
    mov     dword [rsp + 4], -15
.v_fz:
    mov     dword [rsp], -15
.v_fx:
    mov     edi, ebx
    add     edi, [rsp]
    mov     esi, r13d
    add     esi, [rsp + 4]
    call    worldgen_height
    sub     eax, r15d
    cdq
    xor     eax, edx
    sub     eax, edx                    ; |dh|
    cmp     eax, [rsp + 8]
    jg      .v_next
    add     dword [rsp], 5
    cmp     dword [rsp], 15
    jle     .v_fx
    add     dword [rsp + 4], 5
    cmp     dword [rsp + 4], 15
    jle     .v_fz
    mov     edi, SITE_VILLAGE
    mov     esi, [site_count]
    mov     edx, ebx
    mov     ecx, r15d
    mov     r8d, r13d
    call    add_site
.v_next:
    inc     r12d
    cmp     r12d, 96
    jb      .v_cand
    inc     r14d
    cmp     r14d, 2
    jb      .v_pass
.v_done:
    ; ---- dungeons: ground >= 16 at three corners of the footprint, 30 from the middle of the
    ; world, 40 from each other, 32 from the villages
    xor     r14d, r14d                  ; dungeons found
    xor     r12d, r12d
.d_cand:
    cmp     r14d, NUM_DUNGEONS
    jae     .d_done
    CAND    610, 60, 170, 8, 226
    D2C
    cmp     eax, 900
    jb      .d_next
    mov     edi, SITE_DUNGEON
    mov     esi, ebx
    mov     edx, r13d
    call    min_dist2
    cmp     eax, 1600
    jb      .d_next
    mov     edi, SITE_VILLAGE
    mov     esi, ebx
    mov     edx, r13d
    call    min_dist2
    cmp     eax, 1024
    jb      .d_next
    mov     edi, ebx
    mov     esi, r13d
    call    worldgen_height
    cmp     eax, 16
    jl      .d_next
    lea     edi, [rbx + 14]
    mov     esi, r13d
    call    worldgen_height
    cmp     eax, 16
    jl      .d_next
    lea     edi, [rbx + 14]
    lea     esi, [r13 + 14]
    call    worldgen_height
    cmp     eax, 16
    jl      .d_next
    mov     edi, SITE_DUNGEON
    mov     esi, r14d
    mov     edx, ebx
    mov     ecx, 8
    mov     r8d, r13d
    call    add_site
    inc     r14d
.d_next:
    inc     r12d
    cmp     r12d, 192
    jb      .d_cand
.d_done:
    ; ---- crypt: pass 0 wants it 60..110 blocks from the spawn, pass 1 40..130; ground >= 18 at
    ; its middle and corners, 40 from the dungeons and the villages
    xor     r14d, r14d                  ; pass
.c_pass:
    xor     r12d, r12d
.c_cand:
    CAND    620, 66, 160, 10, 236
    D2C
    lea     rcx, [c_range]
    cmp     eax, [rcx + r14*8]
    jb      .c_next
    cmp     eax, [rcx + r14*8 + 4]
    ja      .c_next
    mov     edi, SITE_DUNGEON
    mov     esi, ebx
    mov     edx, r13d
    call    min_dist2
    cmp     eax, 1600
    jb      .c_next
    mov     edi, SITE_VILLAGE
    mov     esi, ebx
    mov     edx, r13d
    call    min_dist2
    cmp     eax, 1600
    jb      .c_next
    xor     r15d, r15d
.c_h:
    lea     rcx, [c_pts]
    mov     edi, ebx
    add     edi, [rcx + r15*8]
    mov     esi, r13d
    add     esi, [rcx + r15*8 + 4]
    call    worldgen_height
    cmp     eax, 18
    jl      .c_next
    inc     r15d
    cmp     r15d, 5
    jb      .c_h
    mov     edi, SITE_CRYPT
    xor     esi, esi
    mov     edx, ebx
    mov     ecx, 6
    mov     r8d, r13d
    call    add_site
    jmp     .done
.c_next:
    inc     r12d
    cmp     r12d, 192
    jb      .c_cand
    inc     r14d
    cmp     r14d, 2
    jb      .c_pass
.done:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- building ---------------------------------------------------------------------------------

; box_fill(edi x0, esi y0, edx z0, ecx x1, r8d y1, r9d z1, eax op): applies op to every cell of the
; inclusive box (world_set skips cells outside the world). op = id | flags << 8: the block id,
; or OP_SHELL for a stone brick (mossy with 3 in 10) chosen by hash of the cell; flag OP_IFAIR
; places only where the cell is AIR, OP_IFSOLID only where it is not.
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
    call    world_get
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
    call    world_set
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
; climbs west one block per column (floor y0 + i at x = sx - i) until the ground of the column
; and of the next one west is at or below the floor, so the exit is walkable without a jump;
; then an entrance frame closes it. The ground test reads world_top_y before the column is touched.
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
    mov     r14d, 1                     ; i
.step:
    mov     edi, ebx
    sub     edi, r14d
    mov     esi, r12d
    call    world_top_y
    lea     ecx, [r13 + r14 + 1]        ; Yf + 1: where the player's feet would stand
    cmp     eax, ecx
    jge     .dig                        ; the ground is above the floor: keep digging
    lea     edi, [rbx - 1]
    sub     edi, r14d                   ; the next column west, where the player walks out
    mov     esi, r12d
    call    world_top_y
    lea     ecx, [r13 + r14 + 1]
    cmp     eax, ecx
    jl      .exit                       ; both at or below the floor: we are out
.dig:
    lea     rdi, [stair_step]
    mov     esi, STAIR_STEP
    mov     edx, ebx
    sub     edx, r14d
    lea     ecx, [r13 + r14]
    mov     r8d, r12d
    call    run_boxes
    inc     r14d
    cmp     r14d, TUNNEL_STEPS
    jbe     .step
    jmp     .ret
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

; place_chest(edi x, esi y, edx z, ecx table): a CHEST block with its container and 4..6 loot
; rolls from the loot table (0 dungeon, 1 crypt). Roll r: h = hash32(x*31 + r, z*17 + y, 640);
; the entry is the weighted pick h % total, count = min + (h >> 16) % (max - min + 1), cell =
; (h >> 8) % 27 or the next free cell.
; Frame: [rsp] r, [rsp+4] rolls, [rsp+8] h.
place_chest:
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
    mov     r14d, edx
    mov     r15d, ecx
    mov     ecx, CHEST
    call    world_set
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, CONT_CHEST
    call    cont_create
    test    rax, rax
    jz      .ret                        ; every container record is in use
    mov     rbx, rax
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
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; place_chests(rdi table, esi count, edx ox, ecx oz): a chest per 4-byte record (dx, y, dz, loot table)
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
.chest:
    movsx   edi, byte [rbx]
    add     edi, r13d
    movzx   esi, byte [rbx + 1]
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
; room has two)
build_dungeon:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, [rdi + SITE.x]        ; ox
    mov     r13d, [rdi + SITE.z]        ; oz
    lea     rdi, [dungeon_boxes]
    mov     esi, DUNGEON_BOXES
    mov     edx, r12d
    xor     ecx, ecx
    mov     r8d, r13d
    call    run_boxes
    lea     edi, [r12 - 5]
    mov     esi, r13d
    mov     edx, 7
    call    stair_tunnel
    lea     rdi, [dungeon_chests]
    mov     esi, 4
    mov     edx, r12d
    mov     ecx, r13d
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
    mov     r12d, [rdi + SITE.x]        ; cx
    mov     r13d, [rdi + SITE.z]        ; cz
    lea     rdi, [crypt_boxes]
    mov     esi, CRYPT_BOXES
    mov     edx, r12d
    xor     ecx, ecx
    mov     r8d, r13d
    call    run_boxes
    lea     edi, [r12 - 8]
    mov     esi, r13d
    mov     edx, 5
    call    stair_tunnel
    lea     rdi, [crypt_chests]
    mov     esi, 2
    mov     edx, r12d
    mov     ecx, r13d
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

; structures_generate(): builds every planned site (structures_plan ran first) with an empty
; container table: villages, then dungeons, then the crypt, so a stair tunnel that crosses a
; village still cuts through it instead of being flattened away
structures_generate:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    lea     rdi, [world_header + WORLDHDR.containers]
    mov     ecx, MAX_CONTAINERS * CONTAINER_size
    xor     eax, eax
    rep     stosb
    xor     r13d, r13d                  ; kind - 1
.kind:
    lea     r14, [sites]
    mov     r12d, [site_count]
.site:
    test    r12d, r12d
    jz      .next_kind
    lea     eax, [r13 + 1]
    cmp     [r14 + SITE.kind], eax
    jne     .skip
    mov     rdi, r14
    lea     rax, [build_fns]
    call    qword [rax + r13*8]
.skip:
    add     r14, SITE_size
    dec     r12d
    jmp     .site
.next_kind:
    inc     r13d
    cmp     r13d, 3
    jb      .kind
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- NPCs, spawners, counters, queries ----------------------------------------------------------

; structures_spawn_npcs(): in every village, the merchant at (vx + 6.5, vz + 0.5) and the elder at
; (vx - 5.5, vz + 0.5), feet on the flattened ground (vy + 1): both homes sit under a house's eave,
; so the top block there is the roof
structures_spawn_npcs:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    lea     rbx, [sites]
    mov     r12d, [site_count]
.site:
    test    r12d, r12d
    jz      .ret
    cmp     dword [rbx + SITE.kind], SITE_VILLAGE
    jne     .next
    mov     eax, [rbx + SITE.y]
    inc     eax
    cvtsi2ss xmm1, eax
    cvtsi2ss xmm0, dword [rbx + SITE.x]
    addss   xmm0, [c_6_5]
    cvtsi2ss xmm2, dword [rbx + SITE.z]
    addss   xmm2, [c_half]
    mov     edi, MOB_MERCHANT
    call    mob_spawn_npc
    mov     eax, [rbx + SITE.y]
    inc     eax
    cvtsi2ss xmm1, eax
    cvtsi2ss xmm0, dword [rbx + SITE.x]
    subss   xmm0, [c_5_5]
    cvtsi2ss xmm2, dword [rbx + SITE.z]
    addss   xmm2, [c_half]
    mov     edi, MOB_ELDER
    call    mob_spawn_npc
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

; structures_reset(): forget the dungeon kill counts and the spawn timer
structures_reset:
    lea     rdi, [st_kills]
    mov     ecx, NUM_DUNGEONS + 1
    xor     eax, eax
    rep     stosd
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

; dungeon_spawn(rdi SITE*): one attempt of a dungeon's spawner. A dungeon holds at most 3 live
; mobs and needs 8 kills to clear, so it spawns while live + kills < 8 (a mob that vanished
; unkilled is replaced). The mob is a random elite zombie, skeleton or spider at a random cell
; within 3 of a random room's middle, at floor level, at least 6 blocks from the player.
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
    mov     r12d, [rbx + SITE.index]
    lea     r13d, [r12 + 1]             ; MOB.origin of this dungeon's mobs
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
    lea     rcx, [st_kills]
    mov     eax, [rcx + r12*4]
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
    imul    eax, eax, MOB_size
    lea     rcx, [mobs]
    mov     [rcx + rax + MOB.origin], r13d
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; structures_step(): once per fixed step, Survival above Peaceful only. Every 90 steps the
; dungeon the player is in (box grown by 2, not cleared yet) tries to spawn an elite; the crypt
; wakes the boss when the player is inside, it is not defeated and none is alive.
structures_step:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
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
    test    byte [rpg_state + RPGSAVE.flags], 1
    jnz     .next                       ; the Fallen King is dead
    mov     rdi, rbx
    xor     esi, esi
    call    in_box
    test    eax, eax
    jz      .next
    mov     edi, MOB_BOSS
    call    mob_count_type
    test    eax, eax
    jnz     .next
    mov     edi, MOB_BOSS
    cvtsi2ss xmm0, dword [rbx + SITE.x]
    addss   xmm0, [c_half]
    cvtsi2ss xmm1, dword [rbx + SITE.y]
    cvtsi2ss xmm2, dword [rbx + SITE.z]
    addss   xmm2, [c_half]
    call    mob_spawn
    test    eax, eax
    js      .next                       ; no free slot: try again next step
    imul    eax, eax, MOB_size
    lea     rcx, [mobs]
    mov     dword [rcx + rax + MOB.origin], ORIGIN_CRYPT
    mov     edi, SND_BOSS_ROAR
    movss   xmm0, [c_one]
    call    audio_play
    lea     rdi, [s_awakens]
    mov     esi, RGBA(255, 80, 60, 255)
    call    hud_banner
    jmp     .next
.dungeon:
    test    r15d, r15d
    jz      .next
    mov     ecx, [rbx + SITE.index]
    movzx   eax, byte [rpg_state + RPGSAVE.cleared]
    bt      eax, ecx
    jc      .next
    mov     rdi, rbx
    mov     esi, 2
    call    in_box
    test    eax, eax
    jz      .next
    mov     rdi, rbx
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

; structures_on_mob_killed(edi origin): a mob of dungeon origin - 1 died (origin 1..6; anything
; else is ignored). The 8th death clears the dungeon: its bit in the cleared mask, 150 XP, a
; banner, the quest hook.
structures_on_mob_killed:
    lea     eax, [rdi - 1]
    cmp     eax, NUM_DUNGEONS - 1
    ja      .none
    push    rbx
    mov     ebx, eax                    ; dungeon index
    lea     rcx, [st_kills]
    inc     dword [rcx + rbx*4]
    cmp     dword [rcx + rbx*4], DUNGEON_KILLS
    jb      .done
    movzx   eax, byte [rpg_state + RPGSAVE.cleared]
    bt      eax, ebx
    jc      .done
    bts     eax, ebx
    mov     [rpg_state + RPGSAVE.cleared], al
    mov     edi, 150
    call    rpg_add_xp
    lea     rdi, [s_cleared]
    mov     esi, RGBA(120, 255, 120, 255)
    call    hud_banner
    mov     edi, SND_QUEST
    movss   xmm0, [c_one]
    call    audio_play
    call    quests_on_dungeon_cleared
.done:
    pop     rbx
.none:
    ret

; structures_nearest(edi kind, esi uncleared_only) -> rax SITE* of that kind nearest to the
; player by horizontal distance, or 0. uncleared_only skips cleared dungeons and the crypt once
; the boss is defeated.
structures_nearest:
    xor     eax, eax
    movss   xmm3, [c_big]
    mov     r8d, [site_count]
    test    r8d, r8d
    jz      .ret
    lea     rcx, [sites]
.l:
    cmp     [rcx + SITE.kind], edi
    jne     .n
    test    esi, esi
    jz      .measure
    cmp     edi, SITE_DUNGEON
    jne     .not_dungeon
    mov     edx, [rcx + SITE.index]
    movzx   r9d, byte [rpg_state + RPGSAVE.cleared]
    bt      r9d, edx
    jc      .n
    jmp     .measure
.not_dungeon:
    cmp     edi, SITE_CRYPT
    jne     .measure
    test    byte [rpg_state + RPGSAVE.flags], 1
    jnz     .n
.measure:
    cvtsi2ss xmm0, dword [rcx + SITE.x]
    subss   xmm0, [player + BODY.x]
    mulss   xmm0, xmm0
    cvtsi2ss xmm1, dword [rcx + SITE.z]
    subss   xmm1, [player + BODY.z]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, xmm3
    jae     .n
    movaps  xmm3, xmm0
    mov     rax, rcx
.n:
    add     rcx, SITE_size
    dec     r8d
    jnz     .l
.ret:
    ret
