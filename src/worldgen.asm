; worldgen.asm - the infinite terrain generator: biomes, heights, trees. The underground is caves.asm.
;
; gen_column() fills one 16 x 256 x 16 column of a GENBUF from the seed alone; the same column
; always comes out the same, whatever was generated before (no state survives a call), so columns
; can be built in any order on the generator thread. gen_height, gen_biome, gen_surface and gen_find_spawn
; (and caves.asm's gen_carved) are pure functions of the absolute cell and of gen_seed and are reentrant (stack
; and registers only); the main thread calls them while the worker runs gen_column. The statics
; below belong to gen_column alone: exactly one thread runs it at a time (the worker during a
; session, the main thread in the selftests).
;
; Coordinates in this file are absolute (the generator never sees the floating origin); a column's
; own cells are local lx, lz in 0..15 and ax = acx * 16 + lx. The block layout is the world's own:
; blocks[(y << 8) | (lz << 4) | lx]. Nothing here calls world_*.
%include "common.inc"
default rel

global worldgen_set_seed, gen_column, gen_height, gen_biome, gen_surface, gen_find_spawn, veg_kind

extern hash32, noise2, fbm2, gen_seed
extern structures_stamp, roads_prepare, road_mask, gen_underground, carved_at

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
%define TF_TW       36                  ; T' = T + the dither: what the surface materials read
%define TF_SIZE     40                  ; keeps rsp 16-aligned after the five pushes

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
k_swamp_t:  dd 0.5                      ; swamp biome: sw above this
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
k_absmask:  dd 0x7FFFFFFF
; the climate ladder: T and M are cut at percentiles of fbm2 over seed 42's 16 block grid of |x|, |z| <= 3072
; (385 x 385 samples, oceans included), rounded to 3 decimals
k_t_snow:     dd -0.345                 ; T below: snow (P14 of T)
k_t_taiga:    dd -0.164                 ; T below: taiga, and the freezing line (P28)
k_t_swamp_lo: dd -0.057                 ; swamps start to grow here (P38)
k_t_swamp_hi: dd 0.178                  ; and stop here (P66)
k_t_savanna:  dd 0.255                  ; T from here: savanna or desert, dry grass (P74)
k_t_desert:   dd 0.400                  ; T from here: desert where it is dry (P86)
k_m_plains:   dd -0.122                 ; M below: plains (P35 of M)
k_m_birch:    dd 0.056                  ; M below: birch forest, from here: forest (P55)
k_m_desert:   dd 0.100                  ; M below: desert, from here: savanna (P60)
k_wobble:     dd 0.015                  ; how far the surface materials dither T and M over a border
k_p002:       dd 0.02                   ; width of the swamp band's ramps in T
k_shore_c:    dd -0.05                  ; stony shore: C below this
k_20:         dd 20.0
k_80:         dd 80.0
k_165:        dd 165.0

section .bss
alignb 64
g_tc:       resb TC_CELLS * TCELL_size  ; terrain of the column and its margin, (lz + 3) * 22 + lx + 3
alignb 16
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

; WOBBLE salt, slot: xmm0 = [rsp + slot] + 0.015 noise2(ebx, r12d, 3, salt), the dithered T or M
%macro WOBBLE 2
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 3
    mov     ecx, %1
    call    noise2
    mulss   xmm0, [k_wobble]
    addss   xmm0, [rsp + %2]
%endmacro

; terrain_cell(edi ax, esi az, rdx TCELL* out)
; The terrain of the block column at absolute (ax, az): its height, biome and layer blocks. Pure and
; reentrant. gen_height, gen_biome, gen_surface and gen_column all read their answers from here, so they agree
; bit for bit.
;   C continentalness, T temperature, M moisture, Rg ruggedness, D detail, Rv river distance.
;   C < -0.10: ocean, h = 91 - 36 clamp01((-0.10 - C) / 0.25) + 3 D.
;   Else land = clamp01((C + 0.10) / 0.20), mtn = clamp01((Rg - 0.20) / 0.35)^2 * land,
;   h = 98 + 10 land + 8 D + mtn (70 + 30 D); swamps (wet, temperate, flat) lerp toward 96 + 2 D by
;   sw = clamp01((M - 0.25) / 0.10) * bT * (1 - mtn), bT = clamp01((T - k_t_swamp_lo) / 0.02) *
;   clamp01((k_t_swamp_hi - T) / 0.02); rivers (Rv < 0.06, h < 160) lerp toward 93 by smoothstep(Rv / 0.06).
;   The height is floor(h) clamped to 8..240.
; The biome follows a climate ladder; the first rule that matches wins: ocean (C < -0.10), river, mountains
; (mtn > 0.35), stony shore (C < -0.05 and Rg > 0.10), snow (T < k_t_snow), taiga (T < k_t_taiga), then for
; T >= k_t_desert desert where M < k_m_desert and savanna elsewhere, savanna from k_t_savanna, swamp (sw > 0.5),
; plains (M < k_m_plains), birch forest (M < k_m_birch), forest. Only neighbours on the ladder touch, so a
; desert never meets snow. The surface materials of land blend over a border: they read T' = T + 0.015 n and
; M' = M + 0.015 n' (8 block noises, land only) in place of T and M: dry grass from k_t_savanna, snow
; cover and frozen water below k_t_taiga, sand patches in a savanna, dry grass in a desert. Mountains of
; h >= 150 are bare stone under a snow line S = 165 + 80 clamp01((T - k_t_taiga) / (k_t_desert - k_t_taiga)):
; snow cover from S, a SNOW_BLOCK top from S + 20.
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
    FBMC    10, 2, 1700, TF_T
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
    WOBBLE  1710, TF_T                  ; T' (land only)
    movss   [rsp + TF_TW], xmm0
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
    ; sw = clamp01((M - 0.25) / 0.10) * bT * (1 - mtn); bT = clamp01((T - k_t_swamp_lo) / 0.02) *
    ; clamp01((k_t_swamp_hi - T) / 0.02) keeps the swamps to the temperate band
    movss   xmm3, [rsp + TF_M]
    subss   xmm3, [k_p025]
    divss   xmm3, [k_p010]
    CLAMP01 xmm3
    movss   xmm5, [rsp + TF_T]
    movaps  xmm4, xmm5
    subss   xmm4, [k_t_swamp_lo]
    divss   xmm4, [k_p002]
    CLAMP01 xmm4
    movss   xmm6, [k_t_swamp_hi]
    subss   xmm6, xmm5
    divss   xmm6, [k_p002]
    CLAMP01 xmm6
    mulss   xmm4, xmm6
    mulss   xmm3, xmm4
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
    movss   xmm1, [rsp + TF_T]          ; no dither over the sea: T' is T
    movss   [rsp + TF_TW], xmm1
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
    ; ---- biome: the first rule that matches wins ----
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
    mov     r15d, BIOME_SHORE           ; a rugged coast
    movss   xmm0, [rsp + TF_C]
    comiss  xmm0, [k_shore_c]
    jae     .not_shore
    movss   xmm0, [rsp + TF_RG]
    comiss  xmm0, [k_p010]
    ja      .materials
.not_shore:
    movss   xmm0, [rsp + TF_T]          ; the temperature ladder
    mov     r15d, BIOME_SNOW
    comiss  xmm0, [k_t_snow]
    jb      .materials
    mov     r15d, BIOME_TAIGA
    comiss  xmm0, [k_t_taiga]
    jb      .materials
    comiss  xmm0, [k_t_desert]
    jb      .not_desert
    mov     r15d, BIOME_SAVANNA         ; hot: desert where it is dry, savanna where it is not
    movss   xmm1, [rsp + TF_M]
    comiss  xmm1, [k_m_desert]
    jae     .materials
    mov     r15d, BIOME_DESERT
    jmp     .materials
.not_desert:
    mov     r15d, BIOME_SAVANNA
    comiss  xmm0, [k_t_savanna]
    jae     .materials
    mov     r15d, BIOME_SWAMP
    movss   xmm0, [rsp + TF_SW]
    comiss  xmm0, [k_swamp_t]
    ja      .materials
    movss   xmm0, [rsp + TF_M]
    mov     r15d, BIOME_PLAINS
    comiss  xmm0, [k_m_plains]
    jb      .materials
    mov     r15d, BIOME_BIRCH
    comiss  xmm0, [k_m_birch]
    jb      .materials
    mov     r15d, BIOME_FOREST
    ; ---- materials ----
.materials:
    mov     [r13 + TCELL.h], r14d
    mov     [r13 + TCELL.biome], r15d
    xor     eax, eax
    movss   xmm0, [rsp + TF_TW]
    comiss  xmm0, [k_t_taiga]
    setb    al
    mov     [r13 + TCELL.cold], eax     ; T' below the freezing line
    mov     dword [r13 + TCELL.deep], STONE
    mov     dword [r13 + TCELL.cover], 0
    cmp     r15d, BIOME_OCEAN
    je      .m_ocean
    cmp     r15d, BIOME_RIVER
    je      .m_river
    cmp     r15d, BIOME_SHORE
    je      .m_shore                    ; no beach on a stony shore
    cmp     r14d, 98
    jg      .m_land
    movss   xmm0, [rsp + TF_C]
    comiss  xmm0, [k_beach]
    jb      .m_beach
.m_land:
    cmp     r15d, BIOME_DESERT
    je      .m_desert
    cmp     r15d, BIOME_SAVANNA
    je      .m_savanna
    cmp     r15d, BIOME_SNOW
    je      .m_snow
    cmp     r15d, BIOME_TAIGA
    je      .m_snow
    cmp     r15d, BIOME_SWAMP
    je      .m_swamp
    cmp     r15d, BIOME_MOUNTAINS
    je      .m_mtn
.m_temperate:                           ; plains, birch forest, forest, swamp without mud, mountain below h 150
    mov     eax, GRASS
    mov     ecx, DIRT
    movss   xmm0, [rsp + TF_TW]
    comiss  xmm0, [k_t_savanna]
    jb      .m_covered
    mov     eax, DRY_GRASS
.m_covered:                             ; the surface in eax / ecx, and snow over it where T' is below k_t_taiga
    cmp     dword [r13 + TCELL.cold], 0
    je      .m_store
    mov     dword [r13 + TCELL.cover], SNOW_LAYER
    jmp     .m_store
.m_snow:                                ; snow and taiga
    mov     dword [r13 + TCELL.cover], SNOW_LAYER
    mov     eax, GRASS
    mov     ecx, DIRT
    jmp     .m_store
.m_savanna:                             ; dry grass, sand where T' and M' say desert
    movss   xmm0, [rsp + TF_TW]
    comiss  xmm0, [k_t_desert]
    jb      .m_savanna_dry
    WOBBLE  1711, TF_M
    comiss  xmm0, [k_m_desert]
    jae     .m_savanna_dry
    mov     eax, SAND
    mov     ecx, SAND
    jmp     .m_store
.m_savanna_dry:
    mov     eax, DRY_GRASS
    mov     ecx, DIRT
    jmp     .m_store
.m_desert:                              ; sand, dry grass over sand where T' or M' say savanna
    mov     dword [r13 + TCELL.deep], SANDSTONE
    movss   xmm0, [rsp + TF_TW]
    comiss  xmm0, [k_t_desert]
    jb      .m_desert_dry
    WOBBLE  1711, TF_M
    comiss  xmm0, [k_m_desert]
    jae     .m_desert_dry
    mov     eax, SAND
    mov     ecx, SAND
    jmp     .m_store
.m_desert_dry:
    mov     eax, DRY_GRASS
    mov     ecx, SAND
    jmp     .m_store
.m_swamp:
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 3
    mov     ecx, 1600
    call    noise2
    comiss  xmm0, [k_mud]
    jbe     .m_temperate
    mov     eax, MUD
    mov     ecx, DIRT
    jmp     .m_store
.m_mtn:
    cmp     r14d, 150
    jl      .m_temperate
    movss   xmm0, [rsp + TF_T]          ; the snow line S = 165 + 80 clamp01((T - k_t_taiga) / (k_t_desert - k_t_taiga))
    subss   xmm0, [k_t_taiga]
    movss   xmm1, [k_t_desert]
    subss   xmm1, [k_t_taiga]
    divss   xmm0, xmm1
    CLAMP01 xmm0
    mulss   xmm0, [k_80]
    addss   xmm0, [k_165]
    cvtsi2ss xmm1, r14d
    comiss  xmm1, xmm0
    jb      .m_mtn_stone                ; below the snow line
    addss   xmm0, [k_20]
    comiss  xmm1, xmm0
    jae     .m_mtn_snow                 ; from S + 20: a block of snow
    mov     dword [r13 + TCELL.cover], SNOW_LAYER
.m_mtn_stone:
    mov     eax, STONE
    mov     ecx, STONE
    jmp     .m_store
.m_mtn_snow:
    mov     eax, SNOW_BLOCK
    mov     ecx, STONE
    jmp     .m_store
.m_shore:                               ; stone, gravel in patches
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 2
    mov     ecx, 1720
    call    noise2
    mov     eax, STONE
    mov     ecx, STONE
    comiss  xmm0, [k_p020]
    jbe     .m_covered
    mov     eax, GRAVEL
    jmp     .m_covered
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
    jmp     .m_covered
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

; gen_surface(edi ax, esi az) -> eax top, edx filler, ecx cover
; The surface blocks of the column at absolute (ax, az), before caves, trees and sites: the block at y = h
; (TCELL.top), the block under it (TCELL.f1, the filler) and the cover placed at h + 1 when the column is above
; water (TCELL.cover: SNOW_LAYER or 0). Reentrant.
gen_surface:
    sub     rsp, 40
    mov     rdx, rsp
    call    terrain_cell
    mov     eax, [rsp + TCELL.top]
    mov     edx, [rsp + TCELL.f1]
    mov     ecx, [rsp + TCELL.cover]
    add     rsp, 40
    ret

; ---------------------------------------------------------------------------------------------
; spawn

; gen_find_spawn(rdi out dd[3])
; The world spawn: the first column centre (16 i + 8, 16 j + 8), walking the rings max(|i|, |j|) = k for
; k = 0..256 (inside a ring j ascending, then i ascending), whose biome is one of SPAWN_BIOMES (plains, forest,
; desert, snow, swamp, taiga, savanna, birch forest) and whose terrain is at least 97 high; out = absolute
; (x, height + 1, z). With none, the fallback is (8, max(height(8, 8), 96) + 1, 8). Reentrant.
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
    mov     ecx, SPAWN_BIOMES
    bt      ecx, eax
    jnc     .next
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
    mov     rdi, rbx
    lea     rsi, [g_tc]
    mov     edx, [g_ax0]
    mov     ecx, [g_az0]
    call    gen_underground
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

; plant_tree(edi lx, esi lz, edx h, ecx t, r8d kind)   kind: 1 oak, 2 birch, 3 pine, 5 snowy pine, 6 acacia
; Stamps the tree rooted at the ground cell (lx, h, lz) into the column in progress; lx and lz may lie up
; to 3 cells outside it, and what falls outside is dropped. The ground becomes DIRT, the trunk is written
; over anything, leaves only into AIR. Oak: trunk 4 + (t >> 8) % 3, leaf layers at h + H - 2 and h + H - 1
; (radius 2, corners cut), h + H (radius 1) and h + H + 1 (radius 1, corners cut). Birch: the oak shape with
; birch blocks and a trunk of 5 + (t >> 8) % 3. Pine: PINE_LOG trunk 6 + (t >> 8) % 4, a layer at every
; height from the trunk top down to h + 3 with the radius alternating 1, 2, 1, ... (radius 2 corners cut),
; and one leaf above the top. Snowy pine: the pine with a SNOW_LAYER (into AIR only) on the leaf above the top.
; Acacia: LOG trunk 4 + ((t >> 8) & 1), a flat crown of LEAVES: radius 2 (corners cut) at the trunk top and
; radius 1 on the layer above it.
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
    cmp     r15d, 5
    je      .pine
    cmp     r15d, 6
    je      .acacia
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
.acacia:
    and     eax, 1
    lea     ebp, [rax + 4]              ; acacia trunk height
    mov     dword [rsp], LOG
    mov     dword [rsp + 4], LEAVES
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
    cmp     r15d, 5
    je      .pine_leaves
    cmp     r15d, 6
    je      .acacia_leaves
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
.acacia_leaves:
    mov     edi, ebx
    lea     esi, [r13 + rbp]
    mov     edx, r12d
    mov     ecx, 2
    mov     r8d, 1
    mov     r9d, [rsp + 4]
    call    leaf_layer
    mov     edi, ebx
    lea     esi, [r13 + rbp + 1]
    mov     edx, r12d
    mov     ecx, 1
    xor     r8d, r8d
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
    cmp     r15d, 5
    jne     .out
    mov     edi, ebx                    ; a snowy pine: snow on the top leaf
    lea     esi, [r13 + rbp + 2]
    mov     edx, r12d
    mov     ecx, SNOW_LAYER
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

; veg_kind(edi biome, esi h, edx top, ecx t) -> eax 0 none, 1 oak, 2 birch, 3 pine, 4 cactus, 5 snowy pine, 6 acacia
; The pure planting decision of one terrain cell before the cave check. Nothing grows below h 97. Trees need
; a GRASS top, cacti a SAND top in a desert, acacias a DRY_GRASS top in a savanna. With r = t & 255: plains
; oak r < 1, forest r < 7 (oak when t & 256, else birch), birch forest birch r < 7, snow snowy pine r < 3, taiga
; snowy pine r < 8, mountains pine r < 2 (h < 150 only), swamp oak r < 3, desert cactus r < 2, savanna acacia r < 2.
veg_kind:
    xor     eax, eax
    cmp     esi, 97
    jl      .out
    movzx   r8d, cl
    cmp     edi, BIOME_DESERT
    je      .desert
    cmp     edi, BIOME_SAVANNA
    je      .savanna
    cmp     edx, GRASS
    jne     .out
    cmp     edi, BIOME_PLAINS
    je      .plains
    cmp     edi, BIOME_FOREST
    je      .forest
    cmp     edi, BIOME_BIRCH
    je      .birch
    cmp     edi, BIOME_SNOW
    je      .snow
    cmp     edi, BIOME_TAIGA
    je      .taiga
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
.birch:
    cmp     r8d, 7
    jae     .out
    mov     eax, 2
    ret
.snow:
    cmp     r8d, 3
    jae     .out
    mov     eax, 5
    ret
.taiga:
    cmp     r8d, 8
    jae     .out
    mov     eax, 5
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
.savanna:
    cmp     edx, DRY_GRASS
    jne     .out
    cmp     r8d, 2
    jae     .out
    mov     eax, 6
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
; Only on a GRASS or DRY_GRASS top: plains 26, forest 13, birch forest 18, swamp 38, mountains below h 150 8,
; taiga 4, savanna 40; every other biome 0.
grass_chance:
    xor     eax, eax
    cmp     edx, GRASS
    je      .top
    cmp     edx, DRY_GRASS
    jne     .out
.top:
    lea     rcx, [grass_chances]
    movzx   eax, byte [rcx + rdi]
    cmp     edi, BIOME_MOUNTAINS
    jne     .out
    cmp     esi, 150
    jl      .out
    xor     eax, eax
.out:
    ret

section .rodata
; grass_chance by biome id (the mountains' 8 only counts below h 150)
grass_chances:
    db 0, 26, 13, 0, 0, 38, 8, 0, 4, 40, 0, 18
%if $ - grass_chances != NUM_BIOMES
%error "grass_chances needs one entry per biome"
%endif
section .text

; gen_vegetation(): walks the cells of the column and a 3 cell margin around it in a fixed order (z, then x)
; and plants what veg_kind decides, unless a cave opens the top cell: trees and cacti stamp themselves
; clipped to the column, so a tree rooted in a neighbouring column leaves its leaves here and the
; neighbour's own generation leaves the same ones there. Tall grass goes on the GRASS and DRY_GRASS tops of the
; column itself that got no tree, into AIR only (hash32(x, z, 98) & 255 below grass_chance). A cell with a
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
