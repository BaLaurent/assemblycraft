; worldgen.asm - the infinite terrain generator: biomes, heights, caves, ores, trees.
;
; gen_column() fills one 16 x 256 x 16 column of a GENBUF from the seed alone; the same column
; always comes out the same, whatever was generated before (no state survives a call), so columns
; can be built in any order on the generator thread. gen_height, gen_biome, gen_carved and
; gen_find_spawn are pure functions of the absolute cell and of gen_seed and are reentrant (stack
; and registers only); the main thread calls them while the worker runs gen_column. The statics
; below belong to gen_column alone: exactly one thread runs it at a time (the worker during a
; session, the main thread in the selftests).
;
; Coordinates in this file are absolute (the generator never sees the floating origin); a column's
; own cells are local lx, lz in 0..15 and ax = acx * 16 + lx. The block layout is the world's own:
; blocks[(y << 8) | (lz << 4) | lx]. Nothing here calls world_*.
%include "common.inc"
default rel

global worldgen_set_seed, gen_column, gen_height, gen_biome, gen_carved, gen_find_spawn

extern hash32, noise2, noise3, fbm2, gen_seed
extern structures_stamp, roads_prepare, road_mask

; the terrain of one block column (terrain_cell's output)
struc TCELL
    .h:      resd 1                     ; surface height in 8..240
    .biome:  resd 1                     ; BIOME_*
    .top:    resd 1                     ; block at y = h
    .f1:     resd 1                     ; blocks at h - 1, h - 2, h - 3 (the filler)
    .f2:     resd 1
    .f3:     resd 1
    .deep:   resd 1                     ; blocks at h - 4 .. h - 6 (STONE, or SANDSTONE in deserts)
    .cover:  resd 1                     ; block placed at h + 1 when the column is above water (0 = none)
    .cold:   resd 1                     ; 1 when the temperature is below the snow line (water freezes)
endstruc

%define SALT_C      1001                ; continentalness salt (the plan's 1000 gives seed 42 a 53 % ocean)

; float slots of terrain_cell's frame
%define TF_C        0
%define TF_T        4
%define TF_M        8
%define TF_RG       12
%define TF_D        16
%define TF_RV       20
%define TF_MTN      24
%define TF_SW       28
%define TF_HPRE     32
%define TF_SIZE     40                  ; keeps rsp 16-aligned after the five pushes

; terrain cells around the column (the column plus a 3 cell margin for trees that cross its border)
%define TC_W        22
%define TC_CELLS    484

; cave lattice: 4 block spacing, levels j (y = 4 j) 0..21 of the three fields, 5 x 5 points per level
%define LAT_I       4                   ; bytes per x step
%define LAT_K       32                  ; per z step (5 floats, padded to 8)
%define LAT_J       160                 ; per level
%define LAT_F       3520                ; per field (22 levels)
%define LAT_JLO     3
%define LAT_JHI     21

section .rodata
align 4
k_zero:     dd 0.0
k_one:      dd 1.0
k_two:      dd 2.0
k_three:    dd 3.0
k_four:     dd 4.0
k_quarter:  dd 0.25
k_ocean:    dd -0.10                    ; C below this is ocean
k_p010:     dd 0.10
k_p020:     dd 0.20
k_p025:     dd 0.25
k_p035:     dd 0.35
k_p006:     dd 0.06                     ; river band half width
k_river_t:  dd 0.025                    ; river biome
k_mtn_t:    dd 0.35                     ; mountain biome
k_snow_t:   dd -0.25                    ; snow biome / freezing
k_desert_t: dd 0.25
k_swamp_t:  dd 0.5
k_forest_t: dd -0.05
k_beach:    dd -0.06
k_mud:      dd 0.3
k_8:        dd 8.0
k_10:       dd 10.0
k_30:       dd 30.0
k_36:       dd 36.0
k_70:       dd 70.0
k_91:       dd 91.0
k_93:       dd 93.0
k_96:       dd 96.0
k_98:       dd 98.0
k_160:      dd 160.0
k_tun_t:    dd 0.07                     ; |tunnel noise| below this carves
k_cav_t:    dd 0.45                     ; cavern noise above this carves
k_rav_a:    dd 0.012                    ; ravine centre band
k_rav_b:    dd 0.30                     ; ravine gate noise
k_absmask:  dd 0x7FFFFFFF

; cave fields: shift, salt (tunnel A, tunnel B, cavern)
cave_fields:
    dd 5, 2000
    dd 5, 2001
    dd 6, 2002

; Ore table: salt, id, y_min, y_max, attempts per column, vein size (random-walk cells)
%define ORE_SALT 0
%define ORE_ID   4
%define ORE_YMIN 8
%define ORE_YMAX 12
%define ORE_ATT  16
%define ORE_SIZE 20
%define ORE_REC  24
ore_tab:
    dd 1, COAL_ORE,    40, 130, 20, 8
    dd 2, IRON_ORE,    15,  80, 12, 6
    dd 3, GOLD_ORE,     5,  40,  3, 5
    dd 4, DIAMOND_ORE,  2,  18,  1, 4
ore_tab_end:

section .bss
alignb 64
g_tc:       resb TC_CELLS * TCELL_size  ; terrain of the column and its margin, (lz + 3) * 22 + lx + 3
alignb 16
g_lat:      resb 3 * LAT_F              ; cave field samples, [field][level][k][i]
g_cp:       resd 3 * 22                 ; one cell's field values per level, [field][level]
g_buf:      resq 1                      ; the GENBUF being filled
g_acx:      resd 1
g_acz:      resd 1
g_ax0:      resd 1                      ; acx * 16
g_az0:      resd 1

section .text

; worldgen_set_seed(edi seed): the seed hash32 and every noise field use. Called by the main
; thread before a session starts (and by tests); read-only while a session runs.
worldgen_set_seed:
    mov     [gen_seed], edi
    ret

; ---------------------------------------------------------------------------------------------
; terrain fields

; SMOOTH f, t1, t2: f = f*f*(3 - 2f), clobbers t1 and t2
%macro SMOOTH 3
    movaps  %2, %1
    addss   %2, %2
    movss   %3, [k_three]
    subss   %3, %2
    mulss   %1, %1
    mulss   %1, %3
%endmacro

; CLAMP01 x: x = min(max(x, 0), 1)
%macro CLAMP01 1
    maxss   %1, [k_zero]
    minss   %1, [k_one]
%endmacro

; FBMC shift, octaves, salt, slot: [rsp + slot] = fbm2(ebx, r12d, shift, octaves, salt)
%macro FBMC 4
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, %1
    mov     ecx, %2
    mov     r8d, %3
    call    fbm2
    movss   [rsp + %4], xmm0
%endmacro

; terrain_cell(edi ax, esi az, rdx TCELL* out)
; The terrain of the block column at absolute (ax, az): its height, biome and layer blocks. Pure and
; reentrant. gen_height, gen_biome and gen_column all read their answers from here, so they agree
; bit for bit.
;   C continentalness, T temperature, M moisture, Rg ruggedness, D detail, Rv river distance.
;   C < -0.10: ocean, h = 91 - 36 clamp01((-0.10 - C) / 0.25) + 3 D.
;   Else land = clamp01((C + 0.10) / 0.20), mtn = clamp01((Rg - 0.20) / 0.35)^2 * land,
;   h = 98 + 10 land + 8 D + mtn (70 + 30 D); swamps (wet, not cold, flat) lerp toward 96 + 2 D by
;   sw = clamp01((M - 0.25) / 0.10) * (T >= -0.25) * (1 - mtn); rivers (Rv < 0.06, h < 160) lerp
;   toward 93 by smoothstep(Rv / 0.06). The height is floor(h) clamped to 8..240.
terrain_cell:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, TF_SIZE                ; rsp is 16-aligned again
    mov     ebx, edi
    mov     r12d, esi
    mov     r13, rdx
    FBMC    10, 4, SALT_C, TF_C
    FBMC    9, 3, 1100, TF_T
    FBMC    6, 4, 1400, TF_D
    movss   xmm0, [rsp + TF_C]
    comiss  xmm0, [k_ocean]
    jb      .ocean
    FBMC    9, 3, 1500, TF_RV
    movss   xmm0, [rsp + TF_RV]
    movss   xmm1, [k_absmask]
    andps   xmm0, xmm1
    movss   [rsp + TF_RV], xmm0
    FBMC    9, 3, 1300, TF_RG
    FBMC    9, 3, 1200, TF_M
    ; land = clamp01((C + 0.10) / 0.20)
    movss   xmm0, [rsp + TF_C]
    addss   xmm0, [k_p010]
    divss   xmm0, [k_p020]
    CLAMP01 xmm0
    ; mtn = clamp01((Rg - 0.20) / 0.35)^2 * land
    movss   xmm1, [rsp + TF_RG]
    subss   xmm1, [k_p020]
    divss   xmm1, [k_p035]
    CLAMP01 xmm1
    mulss   xmm1, xmm1
    mulss   xmm1, xmm0
    movss   [rsp + TF_MTN], xmm1
    ; h = 98 + 10 land + 8 D + mtn (70 + 30 D)
    mulss   xmm0, [k_10]
    addss   xmm0, [k_98]
    movss   xmm2, [rsp + TF_D]
    movaps  xmm3, xmm2
    mulss   xmm3, [k_8]
    addss   xmm0, xmm3
    mulss   xmm2, [k_30]
    addss   xmm2, [k_70]
    mulss   xmm2, xmm1
    addss   xmm0, xmm2
    ; sw = clamp01((M - 0.25) / 0.10), 0 when cold, times (1 - mtn)
    movss   xmm3, [rsp + TF_M]
    subss   xmm3, [k_p025]
    divss   xmm3, [k_p010]
    CLAMP01 xmm3
    movss   xmm4, [rsp + TF_T]
    comiss  xmm4, [k_snow_t]
    jae     .warm
    pxor    xmm3, xmm3
.warm:
    movss   xmm4, [k_one]
    subss   xmm4, xmm1
    mulss   xmm3, xmm4
    movss   [rsp + TF_SW], xmm3
    ; h = lerp(h, 96 + 2 D, sw)
    movss   xmm4, [rsp + TF_D]
    mulss   xmm4, [k_two]
    addss   xmm4, [k_96]
    subss   xmm4, xmm0
    mulss   xmm4, xmm3
    addss   xmm0, xmm4
    movss   [rsp + TF_HPRE], xmm0
    ; river: Rv < 0.06 and h < 160: h = lerp(93, h, smoothstep(Rv / 0.06))
    movss   xmm1, [rsp + TF_RV]
    comiss  xmm1, [k_p006]
    jae     .round
    comiss  xmm0, [k_160]
    jae     .round
    divss   xmm1, [k_p006]
    SMOOTH  xmm1, xmm2, xmm3
    movss   xmm2, [k_93]
    subss   xmm0, xmm2
    mulss   xmm0, xmm1
    addss   xmm0, xmm2
    jmp     .round
.ocean:
    movss   xmm0, [k_ocean]
    subss   xmm0, [rsp + TF_C]
    mulss   xmm0, [k_four]
    CLAMP01 xmm0
    mulss   xmm0, [k_36]
    movss   xmm1, [k_91]
    subss   xmm1, xmm0
    movss   xmm0, [rsp + TF_D]
    mulss   xmm0, [k_three]
    addss   xmm0, xmm1
.round:
    roundss xmm0, xmm0, 9
    cvttss2si r14d, xmm0
    mov     eax, 8
    cmp     r14d, eax
    cmovl   r14d, eax
    mov     eax, 240
    cmp     r14d, eax
    cmovg   r14d, eax
    ; ---- biome ----
    mov     r15d, BIOME_OCEAN
    movss   xmm0, [rsp + TF_C]
    comiss  xmm0, [k_ocean]
    jb      .materials
    mov     r15d, BIOME_RIVER
    movss   xmm0, [rsp + TF_RV]
    comiss  xmm0, [k_river_t]
    jae     .not_river
    movss   xmm0, [rsp + TF_HPRE]
    comiss  xmm0, [k_160]
    jb      .materials
.not_river:
    mov     r15d, BIOME_MOUNTAINS
    movss   xmm0, [rsp + TF_MTN]
    comiss  xmm0, [k_mtn_t]
    ja      .materials
    mov     r15d, BIOME_SNOW
    movss   xmm0, [rsp + TF_T]
    comiss  xmm0, [k_snow_t]
    jb      .materials
    comiss  xmm0, [k_desert_t]
    jbe     .not_desert
    movss   xmm1, [rsp + TF_M]
    comiss  xmm1, [k_zero]
    mov     r15d, BIOME_DESERT
    jb      .materials
.not_desert:
    mov     r15d, BIOME_SWAMP
    movss   xmm0, [rsp + TF_SW]
    comiss  xmm0, [k_swamp_t]
    ja      .materials
    mov     r15d, BIOME_FOREST
    movss   xmm0, [rsp + TF_M]
    comiss  xmm0, [k_forest_t]
    ja      .materials
    mov     r15d, BIOME_PLAINS
    ; ---- materials ----
.materials:
    mov     [r13 + TCELL.h], r14d
    mov     [r13 + TCELL.biome], r15d
    xor     eax, eax
    movss   xmm0, [rsp + TF_T]
    comiss  xmm0, [k_snow_t]
    setb    al
    mov     [r13 + TCELL.cold], eax
    mov     dword [r13 + TCELL.deep], STONE
    mov     dword [r13 + TCELL.cover], 0
    cmp     r15d, BIOME_OCEAN
    je      .m_ocean
    cmp     r15d, BIOME_RIVER
    je      .m_river
    cmp     r14d, 98
    jg      .m_land
    movss   xmm0, [rsp + TF_C]
    comiss  xmm0, [k_beach]
    jb      .m_beach
.m_land:
    cmp     r15d, BIOME_DESERT
    je      .m_desert
    cmp     r15d, BIOME_SNOW
    je      .m_snow
    cmp     r15d, BIOME_SWAMP
    je      .m_swamp
    cmp     r15d, BIOME_MOUNTAINS
    je      .m_mtn
    mov     eax, GRASS                  ; PLAINS, FOREST
    mov     ecx, DIRT
    jmp     .m_store
.m_desert:
    mov     dword [r13 + TCELL.deep], SANDSTONE
    mov     eax, SAND
    mov     ecx, SAND
    jmp     .m_store
.m_snow:
    mov     dword [r13 + TCELL.cover], SNOW_LAYER
    mov     eax, GRASS
    mov     ecx, DIRT
    jmp     .m_store
.m_swamp:
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 3
    mov     ecx, 1600
    call    noise2
    mov     eax, GRASS
    mov     ecx, DIRT
    comiss  xmm0, [k_mud]
    jbe     .m_store
    mov     eax, MUD
    jmp     .m_store
.m_mtn:
    cmp     r14d, 150
    jl      .m_mtn_grass
    cmp     r14d, 195
    jge     .m_mtn_snow
    mov     eax, STONE
    mov     ecx, STONE
    cmp     r14d, 175
    jl      .m_store
    mov     dword [r13 + TCELL.cover], SNOW_LAYER
    jmp     .m_store
.m_mtn_grass:
    mov     eax, GRASS
    mov     ecx, DIRT
    jmp     .m_store
.m_mtn_snow:
    mov     eax, SNOW_BLOCK
    mov     ecx, STONE
    jmp     .m_store
.m_ocean:
    mov     eax, SAND
    mov     ecx, SAND
    cmp     r14d, 80
    jge     .m_store
    mov     eax, GRAVEL
    mov     ecx, GRAVEL
    jmp     .m_store
.m_beach:
    mov     eax, SAND
    mov     ecx, SAND
    jmp     .m_store
.m_river:
    mov     dword [r13 + TCELL.top], SAND
    mov     dword [r13 + TCELL.f1], SAND
    mov     dword [r13 + TCELL.f2], SAND
    mov     dword [r13 + TCELL.f3], DIRT
    jmp     .m_done
.m_store:
    mov     [r13 + TCELL.top], eax
    mov     [r13 + TCELL.f1], ecx
    mov     [r13 + TCELL.f2], ecx
    mov     [r13 + TCELL.f3], ecx
.m_done:
    add     rsp, TF_SIZE
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gen_height(edi ax, esi az) -> eax
; The terrain surface height (8..240) of the column at absolute (ax, az), before caves, trees and
; sites. Reentrant.
gen_height:
    sub     rsp, 40                     ; TCELL (36 bytes), keeps rsp 16-aligned
    mov     rdx, rsp
    call    terrain_cell
    mov     eax, [rsp + TCELL.h]
    add     rsp, 40
    ret

; gen_biome(edi ax, esi az) -> eax BIOME_*
; Biome of the column at absolute (ax, az). Reentrant.
gen_biome:
    sub     rsp, 40
    mov     rdx, rsp
    call    terrain_cell
    mov     eax, [rsp + TCELL.biome]
    add     rsp, 40
    ret

; ---------------------------------------------------------------------------------------------
; caves and ravines

; ravine_at(edi ax, esi az) -> eax 0/1
; A ravine runs where |fbm2(x, z, 7, 2, 2003)| < 0.012 and fbm2(x, z, 8, 1, 2004) > 0.30. Reentrant.
ravine_at:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    mov     edx, 7
    mov     ecx, 2
    mov     r8d, 2003
    call    fbm2
    movss   xmm1, [k_absmask]
    andps   xmm0, xmm1
    xor     eax, eax
    comiss  xmm0, [k_rav_a]
    jae     .out
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 8
    mov     ecx, 1
    mov     r8d, 2004
    call    fbm2
    xor     eax, eax
    comiss  xmm0, [k_rav_b]
    seta    al
.out:
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; carve_test(edi y, esi h, edx ravine, xmm0 A, xmm1 B, xmm2 V) -> eax 0/1
; The one carve decision. h is the column's terrain height, A and B the two tunnel field values and
; V the cavern field value at the cell (only the ones whose y range holds y are read), ravine the
; ravine flag of its column. Nothing below y 5 or above the surface is carved, and in columns lower
; than 97 (oceans, rivers, swamps) nothing within 4 cells of the top, so no air sits under water.
;   tunnels y 12..72: |A| < 0.07 and |B| < 0.07;  caverns y 30..80: V > 0.45;  ravines y 25..h.
carve_test:
    xor     eax, eax
    cmp     edi, 5
    jl      .out
    cmp     edi, esi
    jg      .out
    cmp     esi, 97
    jge     .allowed
    lea     ecx, [rsi - 4]
    cmp     edi, ecx
    jge     .out
.allowed:
    cmp     edi, 12
    jl      .no_tunnel
    cmp     edi, 72
    jg      .no_tunnel
    movss   xmm3, [k_absmask]
    movaps  xmm4, xmm0
    andps   xmm4, xmm3
    comiss  xmm4, [k_tun_t]
    jae     .no_tunnel
    movaps  xmm4, xmm1
    andps   xmm4, xmm3
    comiss  xmm4, [k_tun_t]
    jae     .no_tunnel
    mov     eax, 1
    ret
.no_tunnel:
    cmp     edi, 30
    jl      .no_cavern
    cmp     edi, 80
    jg      .no_cavern
    comiss  xmm2, [k_cav_t]
    jbe     .no_cavern
    mov     eax, 1
    ret
.no_cavern:
    test    edx, edx
    jz      .out
    cmp     edi, 25
    jl      .out
    mov     eax, 1
.out:
    ret

; BILERP: xmm0 = bilerp of v00 = xmm0, v10 = xmm1, v01 = xmm2, v11 = xmm3 by wx = xmm4, wz = xmm5
; (a = v00 + (v10 - v00) wx, b = v01 + (v11 - v01) wx, a + (b - a) wz). Clobbers xmm1-xmm3.
; The cave pass and gen_carved both interpolate with this and nothing else.
%macro BILERP 0
    subss   xmm1, xmm0
    mulss   xmm1, xmm4
    addss   xmm0, xmm1
    subss   xmm3, xmm2
    mulss   xmm3, xmm4
    addss   xmm2, xmm3
    subss   xmm2, xmm0
    mulss   xmm2, xmm5
    addss   xmm0, xmm2
%endmacro

; cave_field(edi ax, esi y, edx az, ecx shift, r8d salt) -> xmm0
; The value of one cave field at the cell: noise3(4 i, 8 j, 4 k, shift, salt) sampled on the 4 block
; lattice (the 8 j is the vertical squash), bilinear in x and z at the two levels around y, then
; linear in y. gen_column's lattice holds the same samples, so both agree to the bit.
cave_field:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56                     ; [0] wx [4] wz [8] wy [12] shift [16] salt [20] level0 [24] level1
    mov     [rsp + 12], ecx
    mov     [rsp + 16], r8d
    mov     eax, edi
    and     eax, 3
    pxor    xmm0, xmm0
    cvtsi2ss xmm0, eax
    mulss   xmm0, [k_quarter]
    movss   [rsp], xmm0
    mov     eax, edx
    and     eax, 3
    pxor    xmm0, xmm0
    cvtsi2ss xmm0, eax
    mulss   xmm0, [k_quarter]
    movss   [rsp + 4], xmm0
    mov     eax, esi
    and     eax, 3
    pxor    xmm0, xmm0
    cvtsi2ss xmm0, eax
    mulss   xmm0, [k_quarter]
    movss   [rsp + 8], xmm0
    mov     r12d, edi
    sar     r12d, 2                     ; i0
    mov     r13d, edx
    sar     r13d, 2                     ; k0
    mov     r14d, esi
    sar     r14d, 2                     ; j0
    xor     ebp, ebp                    ; level 0 or 1
.level:
    xor     ebx, ebx                    ; corner 0..3: bit 0 = x + 1, bit 1 = z + 1
.corner:
    lea     edi, [r12 + 0]
    test    ebx, 1
    jz      .cx
    inc     edi
.cx:
    shl     edi, 2
    lea     esi, [r14 + rbp]
    shl     esi, 3
    lea     edx, [r13 + 0]
    test    ebx, 2
    jz      .cz
    inc     edx
.cz:
    shl     edx, 2
    mov     ecx, [rsp + 12]
    mov     r8d, [rsp + 16]
    call    noise3
    movss   [rsp + 32 + rbx*4], xmm0    ; corner values (shared by both levels in turn)
    inc     ebx
    cmp     ebx, 4
    jb      .corner
    movss   xmm0, [rsp + 32]
    movss   xmm1, [rsp + 36]
    movss   xmm2, [rsp + 40]
    movss   xmm3, [rsp + 44]
    movss   xmm4, [rsp]
    movss   xmm5, [rsp + 4]
    BILERP
    movss   [rsp + 20 + rbp*4], xmm0
    inc     ebp
    cmp     ebp, 2
    jb      .level
    movss   xmm0, [rsp + 20]
    movss   xmm1, [rsp + 24]
    subss   xmm1, xmm0
    mulss   xmm1, [rsp + 8]
    addss   xmm0, xmm1
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; carved_at(edi ax, esi y, edx az, ecx h) -> eax 0/1
; carve_test for the cell (ax, y, az) of a column whose terrain height h the caller already knows:
; it evaluates only the noise fields whose y range holds y. gen_carved and the vegetation pass call it.
carved_at:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40                     ; [0] A [4] B [8] V
    xor     eax, eax
    cmp     esi, 5
    jl      .out
    cmp     esi, ecx
    jg      .out
    cmp     ecx, 97
    jge     .go
    lea     eax, [rcx - 4]
    cmp     esi, eax
    jl      .go
    xor     eax, eax                    ; within 4 cells of the top of a low column
    jmp     .out
.go:
    mov     ebx, edi                    ; ax
    mov     r12d, esi                   ; y
    mov     r13d, edx                   ; az
    mov     r14d, ecx                   ; h
    xor     r15d, r15d                  ; ravine
    cmp     r12d, 25
    jl      .fields
    mov     edi, ebx
    mov     esi, r13d
    call    ravine_at
    mov     r15d, eax
.fields:
    pxor    xmm0, xmm0
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm0
    movss   [rsp + 8], xmm0
    cmp     r12d, 12
    jl      .test
    cmp     r12d, 72
    jg      .cavern
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, [cave_fields]
    mov     r8d, [cave_fields + 4]
    call    cave_field
    movss   [rsp], xmm0
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, [cave_fields + 8]
    mov     r8d, [cave_fields + 12]
    call    cave_field
    movss   [rsp + 4], xmm0
.cavern:
    cmp     r12d, 30
    jl      .test
    cmp     r12d, 80
    jg      .test
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, [cave_fields + 16]
    mov     r8d, [cave_fields + 20]
    call    cave_field
    movss   [rsp + 8], xmm0
.test:
    mov     edi, r12d
    mov     esi, r14d
    mov     edx, r15d
    movss   xmm0, [rsp]
    movss   xmm1, [rsp + 4]
    movss   xmm2, [rsp + 8]
    call    carve_test
.out:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gen_carved(edi ax, esi y, edx az) -> eax 0/1
; Whether the terrain cell (ax, y, az) is carved out by a tunnel, a cavern or a ravine: the one decision
; gen_column's cave pass and its vegetation pass both use. 0 above the terrain surface. Reentrant.
gen_carved:
    push    rbx
    push    r12
    push    r13
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     esi, edx
    call    gen_height                  ; edi is still ax
    mov     ecx, eax
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    call    carved_at
    pop     r13
    pop     r12
    pop     rbx
    ret

; ---------------------------------------------------------------------------------------------
; spawn

; gen_find_spawn(rdi out dd[3])
; The world spawn: the first column centre (16 i + 8, 16 j + 8), walking the rings max(|i|, |j|) = k for
; k = 0..256 (inside a ring j ascending, then i ascending), whose biome is PLAINS, FOREST, DESERT, SNOW or
; SWAMP and whose terrain is at least 97 high; out = absolute (x, height + 1, z). With none, the fallback is
; (8, max(height(8, 8), 96) + 1, 8). Reentrant.
gen_find_spawn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56                     ; a TCELL at [rsp]
    mov     r15, rdi
    xor     ebx, ebx                    ; ring k
.ring:
    mov     r12d, ebx
    neg     r12d                        ; j = -k
.row:
    mov     r13d, ebx
    neg     r13d                        ; i = -k
    mov     r14d, 1                     ; i step
    mov     eax, r12d
    mov     ecx, eax
    sar     ecx, 31
    xor     eax, ecx
    sub     eax, ecx                    ; |j|
    cmp     eax, ebx
    jge     .cell
    lea     r14d, [rbx*2]               ; an inner row only has i = -k and i = k
.cell:
    mov     edi, r13d
    shl     edi, 4
    add     edi, 8
    mov     esi, r12d
    shl     esi, 4
    add     esi, 8
    mov     rdx, rsp
    call    terrain_cell
    mov     eax, [rsp + TCELL.biome]
    dec     eax
    cmp     eax, 4                      ; PLAINS .. SWAMP are the biome ids 1..5
    ja      .next
    mov     ecx, [rsp + TCELL.h]
    cmp     ecx, 97
    jl      .next
    mov     edi, r13d
    shl     edi, 4
    add     edi, 8
    mov     [r15], edi
    inc     ecx
    mov     [r15 + 4], ecx
    mov     esi, r12d
    shl     esi, 4
    add     esi, 8
    mov     [r15 + 8], esi
    jmp     .done
.next:
    add     r13d, r14d
    cmp     r13d, ebx
    jle     .cell
    inc     r12d
    cmp     r12d, ebx
    jle     .row
    inc     ebx
    cmp     ebx, 256
    jle     .ring
    mov     edi, 8                      ; no land column in range: stand on the origin column
    mov     esi, 8
    call    gen_height
    mov     ecx, 96
    cmp     eax, ecx
    cmovl   eax, ecx
    inc     eax
    mov     dword [r15], 8
    mov     [r15 + 4], eax
    mov     dword [r15 + 8], 8
.done:
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---------------------------------------------------------------------------------------------
; the column

; gen_column(rdi GENBUF* buf)
; Generates the column (buf.cx, buf.cz) into buf.blocks (every byte is written), buf.biome and buf.top, and
; sets buf.nchests to what structures_stamp adds (the stamping is its own step) and buf.nconts to 0. Leaves
; .state and .session alone. Worker thread (or selftest) only. Order: materials and water, caves, ores and
; gravel, the roads' mask, trees and plants, sites.
gen_column:
    push    rbx
    mov     rbx, rdi
    mov     [g_buf], rdi
    mov     eax, [rdi + GENBUF.cx]
    mov     [g_acx], eax
    shl     eax, 4
    mov     [g_ax0], eax
    mov     eax, [rdi + GENBUF.cz]
    mov     [g_acz], eax
    shl     eax, 4
    mov     [g_az0], eax
    lea     rdi, [rbx + GENBUF.blocks]
    mov     ecx, 65536 / 8
    xor     eax, eax
    rep     stosq
    mov     dword [rbx + GENBUF.nchests], 0
    mov     dword [rbx + GENBUF.nconts], 0
    call    gen_tcells
    call    gen_fill
    call    gen_caves
    call    gen_ores
    call    gen_gravel
    mov     rdi, rbx
    call    roads_prepare
    call    gen_vegetation
    mov     rdi, rbx
    call    structures_stamp
    call    gen_finish
    pop     rbx
    ret

; gen_tcells(): terrain_cell of the column and its 3 cell margin into g_tc, index (lz + 3) * 22 + lx + 3
gen_tcells:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     r12d, -3                    ; lz
    lea     r14, [g_tc]
.lz:
    mov     r13d, -3                    ; lx
.lx:
    mov     edi, [g_ax0]
    add     edi, r13d
    mov     esi, [g_az0]
    add     esi, r12d
    mov     rdx, r14
    call    terrain_cell
    add     r14, TCELL_size
    inc     r13d
    cmp     r13d, 18
    jle     .lx
    inc     r12d
    cmp     r12d, 18
    jle     .lz
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gen_fill(): bedrock, stone, the 7 surface layers, water (ice in cold columns) up to sea level and the
; snow cover of every cell of the column.
gen_fill:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rax, [g_buf]
    lea     rbp, [rax + GENBUF.blocks]
    xor     r12d, r12d                  ; lz
.lz:
    xor     r13d, r13d                  ; lx
.lx:
    lea     eax, [r12 + 3]
    imul    eax, eax, TC_W
    lea     ecx, [r13 + 3]
    add     eax, ecx
    imul    eax, eax, TCELL_size
    lea     r14, [g_tc]
    add     r14, rax                    ; the cell's TCELL
    mov     eax, r12d
    shl     eax, 4
    add     eax, r13d
    lea     r15, [rbp + rax]            ; &blocks[0][lz][lx]
    mov     ecx, [r14 + TCELL.h]
    mov     byte [r15], BEDROCK
    lea     edx, [rcx - 7]              ; stone from y 1 to h - 7
    lea     rdi, [r15 + 256]
    mov     al, STONE
.stone:
    mov     [rdi], al
    add     rdi, 256
    dec     edx
    jnz     .stone
    mov     eax, ecx
    shl     eax, 8
    lea     rdi, [r15 + rax]            ; &cell (lx, h, lz)
    mov     eax, [r14 + TCELL.top]
    mov     [rdi], al
    sub     rdi, 256
    mov     eax, [r14 + TCELL.f1]
    mov     [rdi], al
    sub     rdi, 256
    mov     eax, [r14 + TCELL.f2]
    mov     [rdi], al
    sub     rdi, 256
    mov     eax, [r14 + TCELL.f3]
    mov     [rdi], al
    mov     eax, [r14 + TCELL.deep]
    sub     rdi, 256
    mov     [rdi], al
    sub     rdi, 256
    mov     [rdi], al
    sub     rdi, 256
    mov     [rdi], al
    cmp     ecx, SEA_LEVEL
    jge     .dry
    mov     edx, SEA_LEVEL
    sub     edx, ecx                    ; water in h + 1 .. 96
    lea     eax, [rcx + 1]
    shl     eax, 8
    lea     rdi, [r15 + rax]
    mov     al, WATER
.water:
    mov     [rdi], al
    add     rdi, 256
    dec     edx
    jnz     .water
    cmp     dword [r14 + TCELL.cold], 0
    je      .next
    mov     byte [r15 + SEA_LEVEL * 256], ICE
    jmp     .next
.dry:
    mov     eax, [r14 + TCELL.cover]
    test    eax, eax
    jz      .next
    lea     edx, [rcx + 1]
    shl     edx, 8
    mov     [r15 + rdx], al
.next:
    inc     r13d
    cmp     r13d, 16
    jb      .lx
    inc     r12d
    cmp     r12d, 16
    jb      .lz
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gen_caves(): samples the three cave fields on the 4 block lattice of the column (levels 3..21), then
; walks every cell of the column from y 5 up to the ravine or tunnel/cavern limit and clears the ones
; carve_test says are carved. A carved surface cell takes the snow layer above it along.
gen_caves:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40                     ; [0] lz [4] lx
    xor     r12d, r12d                  ; field
.f:
    mov     ebx, LAT_JLO                ; level j
.j:
    xor     r14d, r14d                  ; k
.k:
    xor     r15d, r15d                  ; i
.i:
    mov     edi, r15d
    shl     edi, 2
    add     edi, [g_ax0]                ; x = ax0 + 4 i
    mov     esi, ebx
    shl     esi, 3                      ; 8 j
    mov     edx, r14d
    shl     edx, 2
    add     edx, [g_az0]                ; z = az0 + 4 k
    lea     rax, [cave_fields]
    mov     ecx, [rax + r12*8]
    mov     r8d, [rax + r12*8 + 4]
    call    noise3
    imul    eax, r12d, LAT_F
    imul    ecx, ebx, LAT_J
    add     eax, ecx
    imul    ecx, r14d, LAT_K
    add     eax, ecx
    lea     eax, [rax + r15*4]
    lea     rcx, [g_lat]
    movss   [rcx + rax], xmm0
    inc     r15d
    cmp     r15d, 5
    jb      .i
    inc     r14d
    cmp     r14d, 5
    jb      .k
    inc     ebx
    cmp     ebx, LAT_JHI
    jbe     .j
    inc     r12d
    cmp     r12d, 3
    jb      .f
    mov     dword [rsp], 0
.lz:
    mov     dword [rsp + 4], 0
.lx:
    mov     eax, [rsp]
    add     eax, 3
    imul    eax, eax, TC_W
    mov     ecx, [rsp + 4]
    add     ecx, 3
    add     eax, ecx
    imul    eax, eax, TCELL_size
    lea     rcx, [g_tc]
    mov     r14d, [rcx + rax + TCELL.h]
    cmp     r14d, 12
    jl      .nextcell                   ; nothing below y 12 carves
    mov     edi, [rsp + 4]
    add     edi, [g_ax0]
    mov     esi, [rsp]
    add     esi, [g_az0]
    call    ravine_at
    mov     r15d, eax
    mov     ebx, 80                     ; highest y worth testing: 80, or the surface when a ravine cuts it
    cmp     ebx, r14d
    cmovg   ebx, r14d
    test    r15d, r15d
    cmovnz  ebx, r14d
    ; the cell's column pointer
    mov     rax, [g_buf]
    lea     r13, [rax + GENBUF.blocks]
    mov     eax, [rsp]
    shl     eax, 4
    add     eax, [rsp + 4]
    add     r13, rax
    ; weights and the field values of every level over this cell
    mov     eax, [rsp + 4]
    and     eax, 3
    pxor    xmm4, xmm4
    cvtsi2ss xmm4, eax
    mulss   xmm4, [k_quarter]           ; wx
    mov     eax, [rsp]
    and     eax, 3
    pxor    xmm5, xmm5
    cvtsi2ss xmm5, eax
    mulss   xmm5, [k_quarter]           ; wz
    mov     eax, [rsp + 4]
    shr     eax, 2
    shl     eax, 2                      ; 4 * (lx >> 2)
    mov     ecx, [rsp]
    shr     ecx, 2
    shl     ecx, 5                      ; 32 * (lz >> 2)
    add     eax, ecx
    lea     rsi, [g_lat]
    add     rsi, rax
    lea     rdi, [g_cp]
    xor     r12d, r12d                  ; field
.cpf:
    imul    eax, r12d, LAT_F
    lea     rdx, [rsi + rax + LAT_JLO * LAT_J]
    mov     ecx, LAT_JHI - LAT_JLO + 1
    imul    eax, r12d, 88
    lea     r8, [rdi + rax + LAT_JLO * 4]
.cpj:
    movss   xmm0, [rdx]
    movss   xmm1, [rdx + LAT_I]
    movss   xmm2, [rdx + LAT_K]
    movss   xmm3, [rdx + LAT_K + LAT_I]
    BILERP
    movss   [r8], xmm0
    add     rdx, LAT_J
    add     r8, 4
    dec     ecx
    jnz     .cpj
    inc     r12d
    cmp     r12d, 3
    jb      .cpf
    mov     r12d, 5                     ; y
.y:
    cmp     r12d, ebx
    jg      .nextcell
    pxor    xmm0, xmm0
    pxor    xmm1, xmm1
    pxor    xmm2, xmm2
    cmp     r12d, 12
    jl      .test
    cmp     r12d, 80
    jg      .test
    mov     eax, r12d
    shr     eax, 2                      ; level
    mov     ecx, r12d
    and     ecx, 3
    pxor    xmm3, xmm3
    cvtsi2ss xmm3, ecx
    mulss   xmm3, [k_quarter]           ; wy
    lea     rdx, [g_cp]
    lea     rdx, [rdx + rax*4]
    movss   xmm0, [rdx]
    movss   xmm4, [rdx + 4]
    subss   xmm4, xmm0
    mulss   xmm4, xmm3
    addss   xmm0, xmm4                  ; tunnel A
    movss   xmm1, [rdx + 88]
    movss   xmm4, [rdx + 92]
    subss   xmm4, xmm1
    mulss   xmm4, xmm3
    addss   xmm1, xmm4                  ; tunnel B
    movss   xmm2, [rdx + 176]
    movss   xmm4, [rdx + 180]
    subss   xmm4, xmm2
    mulss   xmm4, xmm3
    addss   xmm2, xmm4                  ; cavern
.test:
    mov     edi, r12d
    mov     esi, r14d
    mov     edx, r15d
    call    carve_test
    test    eax, eax
    jz      .ynext
    mov     eax, r12d
    shl     eax, 8
    mov     byte [r13 + rax], AIR
    cmp     r12d, r14d
    jne     .ynext
    lea     eax, [r14 + 1]
    shl     eax, 8
    cmp     byte [r13 + rax], SNOW_LAYER
    jne     .ynext
    mov     byte [r13 + rax], AIR
.ynext:
    inc     r12d
    jmp     .y
.nextcell:
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], 16
    jb      .lx
    inc     dword [rsp]
    cmp     dword [rsp], 16
    jb      .lz
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gen_ores(): per ore a fixed number of attempts per column. Attempt a starts a random walk at a cell
; of the column chosen by hash32(acx * 32 + a, acz, 500 + salt). The stride is 32, not 16: coal makes 20
; attempts, so with 16 its attempt 16 would share its seed with attempt 0 of the next column and repeat a
; vein at the same place there. Each step turns a STONE cell into ore (cells outside the column or the
; ore's y range are skipped) and moves by (h % 3 - 1, (h >> 8) % 3 - 1, (h >> 16) % 3 - 1) with
; h = hash32(acx * 32 + a, acz, salt * 64 + step).
gen_ores:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] x [4] y [8] z [12] step
    lea     r12, [ore_tab]
.ore:
    xor     r13d, r13d                  ; attempt
.att:
    mov     r14d, [g_acx]
    shl     r14d, 5
    add     r14d, r13d
    mov     edi, r14d
    mov     esi, [g_acz]
    mov     edx, [r12 + ORE_SALT]
    add     edx, 500
    call    hash32
    mov     r15d, eax
    mov     ecx, eax
    and     ecx, 15
    mov     [rsp], ecx                  ; x
    mov     ecx, eax
    shr     ecx, 4
    and     ecx, 15
    mov     [rsp + 8], ecx              ; z
    mov     ecx, [r12 + ORE_YMAX]
    sub     ecx, [r12 + ORE_YMIN]
    inc     ecx
    shr     eax, 8
    xor     edx, edx
    div     ecx
    add     edx, [r12 + ORE_YMIN]
    mov     [rsp + 4], edx              ; y
    mov     dword [rsp + 12], 0
.walk:
    mov     eax, [rsp]
    cmp     eax, 15
    ja      .step
    mov     ecx, [rsp + 8]
    cmp     ecx, 15
    ja      .step
    mov     edx, [rsp + 4]
    cmp     edx, [r12 + ORE_YMIN]
    jl      .step
    cmp     edx, [r12 + ORE_YMAX]
    jg      .step
    shl     edx, 8
    shl     ecx, 4
    or      edx, ecx
    or      edx, eax
    mov     rsi, [g_buf]
    lea     rsi, [rsi + GENBUF.blocks]
    cmp     byte [rsi + rdx], STONE
    jne     .step
    mov     eax, [r12 + ORE_ID]
    mov     [rsi + rdx], al
.step:
    mov     edi, r14d
    mov     esi, [g_acz]
    mov     edx, [r12 + ORE_SALT]
    shl     edx, 6
    add     edx, [rsp + 12]
    call    hash32
    mov     r15d, eax
    mov     ecx, 3
    xor     edx, edx
    div     ecx
    dec     edx
    add     [rsp], edx                  ; x += h % 3 - 1
    mov     eax, r15d
    shr     eax, 8
    xor     edx, edx
    div     ecx
    dec     edx
    add     [rsp + 4], edx              ; y += (h >> 8) % 3 - 1
    mov     eax, r15d
    shr     eax, 16
    xor     edx, edx
    div     ecx
    dec     edx
    add     [rsp + 8], edx              ; z += (h >> 16) % 3 - 1
    inc     dword [rsp + 12]
    mov     eax, [rsp + 12]
    cmp     eax, [r12 + ORE_SIZE]
    jb      .walk
    inc     r13d
    cmp     r13d, [r12 + ORE_ATT]
    jb      .att
    add     r12, ORE_REC
    lea     rax, [ore_tab_end]
    cmp     r12, rax
    jb      .ore
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gen_gravel(): two pockets per column, each a 3 x 2 x 3 box of gravel replacing STONE (the box's corner
; cell at the hash of (acx * 32 + pocket, acz, 520), y 5..90), clipped to the column.
gen_gravel:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] dz [4] dx [8] dy
    xor     ebx, ebx                    ; pocket
.pocket:
    mov     edi, [g_acx]
    shl     edi, 5
    add     edi, ebx
    mov     esi, [g_acz]
    mov     edx, 520
    call    hash32
    mov     r12d, eax
    and     r12d, 15                    ; centre x
    mov     r13d, eax
    shr     r13d, 4
    and     r13d, 15                    ; centre z
    shr     eax, 8
    xor     edx, edx
    mov     ecx, 86
    div     ecx
    lea     r14d, [rdx + 5]             ; y of the lower layer
    mov     dword [rsp], -1
.dz:
    mov     dword [rsp + 4], -1
.dx:
    mov     dword [rsp + 8], 0
.dy:
    mov     eax, r12d
    add     eax, [rsp + 4]
    cmp     eax, 15
    ja      .skip
    mov     ecx, r13d
    add     ecx, [rsp]
    cmp     ecx, 15
    ja      .skip
    mov     edx, r14d
    add     edx, [rsp + 8]
    shl     edx, 8
    shl     ecx, 4
    or      edx, ecx
    or      edx, eax
    mov     rsi, [g_buf]
    lea     rsi, [rsi + GENBUF.blocks]
    cmp     byte [rsi + rdx], STONE
    jne     .skip
    mov     byte [rsi + rdx], GRAVEL
.skip:
    inc     dword [rsp + 8]
    cmp     dword [rsp + 8], 1
    jle     .dy
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], 1
    jle     .dx
    inc     dword [rsp]
    cmp     dword [rsp], 1
    jle     .dz
    inc     ebx
    cmp     ebx, 2
    jb      .pocket
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; put_cell(edi lx, esi y, edx lz, ecx id, r8d only_air)
; Writes one block of the column in progress; cells outside it (lx, lz not in 0..15, y not in 0..255) are
; dropped. A non-zero only_air keeps any cell that is not AIR. Clobbers rax, rsi, rdx.
put_cell:
    cmp     edi, 15
    ja      .out
    cmp     edx, 15
    ja      .out
    cmp     esi, 255
    ja      .out
    shl     esi, 8
    shl     edx, 4
    or      esi, edx
    or      esi, edi
    mov     rax, [g_buf]
    lea     rax, [rax + GENBUF.blocks]
    add     rax, rsi
    test    r8d, r8d
    jz      .store
    cmp     byte [rax], AIR
    jne     .out
.store:
    mov     [rax], cl
.out:
    ret

; leaf_layer(edi lx, esi y, edx lz, ecx r, r8d skipcorners, r9d leaf)
; Fills the AIR cells of the square |dx|, |dz| <= r around (lx, lz) at height y with the leaf block,
; leaving out the four corners when skipcorners is non-zero. Cells outside the column are dropped.
leaf_layer:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8                      ; [0] dz [4] dx
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, r8d
    mov     ebp, r9d
    mov     eax, r14d
    neg     eax
    mov     [rsp], eax
.dz:
    mov     eax, r14d
    neg     eax
    mov     [rsp + 4], eax
.dx:
    test    r15d, r15d
    jz      .place
    mov     eax, [rsp]
    imul    eax, eax
    mov     ecx, r14d
    imul    ecx, ecx
    cmp     eax, ecx
    jne     .place
    mov     eax, [rsp + 4]
    imul    eax, eax
    cmp     eax, ecx
    je      .skip                       ; a corner
.place:
    mov     edi, [rsp + 4]
    add     edi, ebx
    mov     esi, r12d
    mov     edx, [rsp]
    add     edx, r13d
    mov     ecx, ebp
    mov     r8d, 1
    call    put_cell
.skip:
    inc     dword [rsp + 4]
    mov     eax, [rsp + 4]
    cmp     eax, r14d
    jle     .dx
    inc     dword [rsp]
    mov     eax, [rsp]
    cmp     eax, r14d
    jle     .dz
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; plant_tree(edi lx, esi lz, edx h, ecx t, r8d kind)   kind: 1 oak, 2 birch, 3 pine
; Stamps the tree rooted at the ground cell (lx, h, lz) into the column in progress; lx and lz may lie up
; to 3 cells outside it, and what falls outside is dropped. The ground becomes DIRT, the trunk is written
; over anything, leaves only into AIR. Oak: trunk 4 + (t >> 8) % 3, leaf layers at h + H - 2 and h + H - 1
; (radius 2, corners cut), h + H (radius 1) and h + H + 1 (radius 1, corners cut). Birch: the oak shape with
; birch blocks and a trunk of 5 + (t >> 8) % 3. Pine: PINE_LOG trunk 6 + (t >> 8) % 4, a layer at every
; height from the trunk top down to h + 3 with the radius alternating 1, 2, 1, ... (radius 2 corners cut),
; and one leaf above the top.
plant_tree:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8                      ; [0] trunk block, [4] leaf block
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r15d, r8d
    mov     eax, ecx
    shr     eax, 8                      ; t >> 8
    cmp     r15d, 3
    je      .pine
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    mov     dword [rsp], LOG
    mov     dword [rsp + 4], LEAVES
    lea     ebp, [rdx + 4]              ; oak trunk height
    cmp     r15d, 2
    jne     .stamp
    mov     dword [rsp], BIRCH_LOG
    mov     dword [rsp + 4], BIRCH_LEAVES
    lea     ebp, [rdx + 5]              ; birch trunk height
    jmp     .stamp
.pine:
    and     eax, 3
    lea     ebp, [rax + 6]
    mov     dword [rsp], PINE_LOG
    mov     dword [rsp + 4], PINE_LEAVES
.stamp:
    mov     edi, ebx
    mov     esi, r13d
    mov     edx, r12d
    mov     ecx, DIRT
    xor     r8d, r8d
    call    put_cell
    mov     r14d, 1
.trunk:
    mov     edi, ebx
    lea     esi, [r13 + r14]
    mov     edx, r12d
    mov     ecx, [rsp]
    xor     r8d, r8d
    call    put_cell
    inc     r14d
    cmp     r14d, ebp
    jle     .trunk
    cmp     r15d, 3
    je      .pine_leaves
    mov     edi, ebx
    lea     esi, [r13 + rbp - 2]
    mov     edx, r12d
    mov     ecx, 2
    mov     r8d, 1
    mov     r9d, [rsp + 4]
    call    leaf_layer
    mov     edi, ebx
    lea     esi, [r13 + rbp - 1]
    mov     edx, r12d
    mov     ecx, 2
    mov     r8d, 1
    mov     r9d, [rsp + 4]
    call    leaf_layer
    mov     edi, ebx
    lea     esi, [r13 + rbp]
    mov     edx, r12d
    mov     ecx, 1
    xor     r8d, r8d
    mov     r9d, [rsp + 4]
    call    leaf_layer
    mov     edi, ebx
    lea     esi, [r13 + rbp + 1]
    mov     edx, r12d
    mov     ecx, 1
    mov     r8d, 1
    mov     r9d, [rsp + 4]
    call    leaf_layer
    jmp     .out
.pine_leaves:
    xor     r14d, r14d                  ; d = trunk top - y
.layer:
    lea     esi, [r13 + rbp]
    sub     esi, r14d
    lea     eax, [r13 + 3]
    cmp     esi, eax
    jl      .tip
    mov     ecx, 1
    xor     r8d, r8d
    test    r14d, 1
    jz      .radius
    mov     ecx, 2
    mov     r8d, 1
.radius:
    mov     edi, ebx
    mov     edx, r12d
    mov     r9d, [rsp + 4]
    call    leaf_layer
    inc     r14d
    jmp     .layer
.tip:
    mov     edi, ebx
    lea     esi, [r13 + rbp + 1]
    mov     edx, r12d
    mov     ecx, [rsp + 4]
    mov     r8d, 1
    call    put_cell
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; plant_cactus(edi lx, esi lz, edx h, ecx t)
; A cactus of 1 + (t >> 9) % 3 cells on the ground cell (lx, h, lz), into AIR only.
plant_cactus:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8                      ; [0] y step
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    shr     ecx, 9
    mov     eax, ecx
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    lea     r14d, [rdx + 1]             ; height
    mov     dword [rsp], 1
.cell:
    mov     edi, ebx
    mov     eax, [rsp]
    lea     esi, [r13 + rax]
    mov     edx, r12d
    mov     ecx, CACTUS
    mov     r8d, 1
    call    put_cell
    inc     dword [rsp]
    mov     eax, [rsp]
    cmp     eax, r14d
    jle     .cell
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; veg_kind(edi biome, esi h, edx top, ecx t) -> eax 0 none, 1 oak, 2 birch, 3 pine, 4 cactus
; The pure planting decision of one terrain cell before the cave check. Nothing grows below h 97. Trees need
; a GRASS top, cacti a SAND top in a desert. With r = t & 255: plains oak r < 1, forest r < 7 (oak when
; t & 256, else birch), snow pine r < 3, mountains pine r < 2 (h < 150 only), swamp oak r < 3, desert cactus r < 2.
veg_kind:
    xor     eax, eax
    cmp     esi, 97
    jl      .out
    movzx   r8d, cl
    cmp     edi, BIOME_DESERT
    je      .desert
    cmp     edx, GRASS
    jne     .out
    cmp     edi, BIOME_PLAINS
    je      .plains
    cmp     edi, BIOME_FOREST
    je      .forest
    cmp     edi, BIOME_SNOW
    je      .snow
    cmp     edi, BIOME_MOUNTAINS
    je      .mountains
    cmp     edi, BIOME_SWAMP
    je      .swamp
    ret
.plains:
    cmp     r8d, 1
    jae     .out
    mov     eax, 1
    ret
.forest:
    cmp     r8d, 7
    jae     .out
    mov     eax, 1
    test    ecx, 256
    jnz     .out
    mov     eax, 2
    ret
.snow:
    cmp     r8d, 3
    jae     .out
    mov     eax, 3
    ret
.mountains:
    cmp     esi, 150
    jge     .out
    cmp     r8d, 2
    jae     .out
    mov     eax, 3
    ret
.swamp:
    cmp     r8d, 3
    jae     .out
    mov     eax, 1
    ret
.desert:
    cmp     edx, SAND
    jne     .out
    cmp     r8d, 2
    jae     .out
    mov     eax, 4
.out:
    ret

; grass_chance(edi biome, esi h, edx top) -> eax chance out of 256 for tall grass on this cell (0 = none)
; Only on a GRASS top: plains 26, forest 13, swamp 38, mountains below h 150 8.
grass_chance:
    xor     eax, eax
    cmp     edx, GRASS
    jne     .out
    cmp     edi, BIOME_PLAINS
    jne     .forest
    mov     eax, 26
    ret
.forest:
    cmp     edi, BIOME_FOREST
    jne     .swamp
    mov     eax, 13
    ret
.swamp:
    cmp     edi, BIOME_SWAMP
    jne     .mountains
    mov     eax, 38
    ret
.mountains:
    cmp     edi, BIOME_MOUNTAINS
    jne     .out
    cmp     esi, 150
    jge     .out
    mov     eax, 8
.out:
    ret

; gen_vegetation(): walks the cells of the column and a 3 cell margin around it in a fixed order (z, then x)
; and plants what veg_kind decides, unless a cave opens the top cell: trees and cacti stamp themselves
; clipped to the column, so a tree rooted in a neighbouring column leaves its leaves here and the
; neighbour's own generation leaves the same ones there. Tall grass goes on the GRASS tops of the column
; itself that got no tree, into AIR only (hash32(x, z, 98) & 255 below grass_chance). A cell with a
; non-zero road_mask (roads_prepare: on a road or within 4 of it) gets neither.
gen_vegetation:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] t [4] kind / chance
    mov     r12d, -3                    ; lz
.lz:
    mov     r13d, -3                    ; lx
.lx:
    lea     eax, [r12 + 3]
    imul    eax, eax, TC_W
    lea     ecx, [r13 + 3]
    add     eax, ecx
    lea     rcx, [road_mask]
    cmp     byte [rcx + rax], 0
    jne     .next                       ; no tree and no tall grass on or beside a road
    imul    eax, eax, TCELL_size
    lea     r14, [g_tc]
    add     r14, rax                    ; the cell's TCELL
    mov     ebx, [g_ax0]
    add     ebx, r13d                   ; ax
    mov     r15d, [g_az0]
    add     r15d, r12d                  ; az
    mov     edi, ebx
    mov     esi, r15d
    mov     edx, 99
    call    hash32
    mov     [rsp], eax
    mov     edi, [r14 + TCELL.biome]
    mov     esi, [r14 + TCELL.h]
    mov     edx, [r14 + TCELL.top]
    mov     ecx, eax
    call    veg_kind
    test    eax, eax
    jz      .grass
    mov     [rsp + 4], eax
    mov     edi, ebx
    mov     esi, [r14 + TCELL.h]
    mov     edx, r15d
    mov     ecx, esi
    call    carved_at
    test    eax, eax
    jnz     .next
    mov     edi, r13d
    mov     esi, r12d
    mov     edx, [r14 + TCELL.h]
    mov     ecx, [rsp]
    mov     r8d, [rsp + 4]
    cmp     r8d, 4
    je      .cactus
    call    plant_tree
    jmp     .next
.cactus:
    call    plant_cactus
    jmp     .next
.grass:
    cmp     r13d, 15
    ja      .next
    cmp     r12d, 15
    ja      .next
    mov     edi, [r14 + TCELL.biome]
    mov     esi, [r14 + TCELL.h]
    mov     edx, [r14 + TCELL.top]
    call    grass_chance
    test    eax, eax
    jz      .next
    mov     [rsp + 4], eax
    mov     edi, ebx
    mov     esi, r15d
    mov     edx, 98
    call    hash32
    movzx   eax, al
    cmp     eax, [rsp + 4]
    jae     .next
    mov     edi, ebx
    mov     esi, [r14 + TCELL.h]
    mov     edx, r15d
    mov     ecx, esi
    call    carved_at
    test    eax, eax
    jnz     .next
    mov     edi, r13d
    mov     esi, [r14 + TCELL.h]
    inc     esi
    mov     edx, r12d
    mov     ecx, TALL_GRASS
    mov     r8d, 1
    call    put_cell
.next:
    inc     r13d
    cmp     r13d, 18
    jle     .lx
    inc     r12d
    cmp     r12d, 18
    jle     .lz
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; gen_finish(): the biome map of the buffer and its top (the highest y holding a non-AIR block, -1 if none)
gen_finish:
    mov     rdi, [g_buf]
    xor     ecx, ecx
.bio:
    mov     eax, ecx
    shr     eax, 4
    add     eax, 3
    imul    eax, eax, TC_W
    mov     edx, ecx
    and     edx, 15
    add     edx, 3
    add     eax, edx
    imul    eax, eax, TCELL_size
    lea     rsi, [g_tc]
    mov     eax, [rsi + rax + TCELL.biome]
    mov     [rdi + GENBUF.biome + rcx], al
    inc     ecx
    cmp     ecx, 256
    jb      .bio
    mov     eax, 255
    lea     rsi, [rdi + GENBUF.blocks + 255 * 256]
.row:
    xor     edx, edx
    xor     ecx, ecx
.qw:
    or      rdx, [rsi + rcx*8]
    inc     ecx
    cmp     ecx, 32
    jb      .qw
    test    rdx, rdx
    jnz     .found
    sub     rsi, 256
    dec     eax
    jns     .row
.found:
    mov     [rdi + GENBUF.top], eax
    ret
