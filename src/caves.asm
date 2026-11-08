; caves.asm - the underground of a generated column: tunnels, caverns and roofed ravines, ores, gravel
; pockets, and the dressing of the caves (pools, floors, exposed ore).
;
; gen_underground(buf, tc, ax0, az0) is called by gen_column after the surface is laid; it carves, then
; places ores, gravel pockets and the cave dressing, in that order. carved_at, gen_carved and
; gen_cave_flags are pure functions of the absolute cell and of gen_seed and are reentrant (the main
; thread calls them while the worker runs gen_column); everything else belongs to the one thread that
; runs gen_column. carved_at agrees bit for bit with the lattice pass of gen_caves: both interpolate the
; same lattice samples with BILERP and the same y lerp, and take the one decision from carve_test.
;
; What carves (carve_test, rules in this order):
;   1  y < 5 or y > h: nothing.        2  h < 97 (water, swamp): nothing within 4 cells of the top.
;   3  tunnel: y 12..72 (and, in a CF_MOUTH column, y 73..h), |A| < 0.07 and |B| < 0.07 (0.05 above y 72).
;   4  cavern: y 20..56, CF_CAVERN, not CF_PILLAR, V > k_cav_t.
;   5  ravine: CF_RAVINE, y 25..min(70, h - 10): roofed, never open to the sky.
; The column flags of a cell (cave_flags): CF_RAVINE ravine_at, CF_PILLAR noise2(shift 2, salt 1750) > 0.82,
; CF_CAVERN noise2(shift 7, salt 1740) > -0.25, CF_MOUTH noise2(shift 6, salt 1730) > 0.65 on land (h >= 97)
; whose terrain falls 4 or more within 3 cells (h - min of the four neighbours at distance 3).
%include "common.inc"
default rel

global gen_underground, carved_at, gen_carved, gen_cave_flags

extern hash32, noise2, noise3, fbm2
extern gen_height

; cave lattice: 4 block spacing, levels j (y = 4 j) 0..61 of the three fields, 5 x 5 points per level.
; Levels LAT_JLO..LAT_JHI are always sampled; the two tunnel fields go on up to the level above the highest
; mouth cell's surface when the column has a mouth.
%define LAT_I       4                   ; bytes per x step
%define LAT_K       32                  ; per z step (5 floats, padded to 8)
%define LAT_J       160                 ; per level
%define LAT_LEVELS  62                  ; levels 0..61 cover y up to 244
%define LAT_F       (LAT_LEVELS * LAT_J) ; per field
%define LAT_JLO     3
%define LAT_JHI     21
%define CP_F        (LAT_LEVELS * 4)    ; bytes per field in g_cp

; dressing: the AIR bit masks of the column, 18 words per y (lz -1 .. 16, the two outer words stay 0)
%define AM_Y        133                 ; rows y 0..132
%define AM_ROW      36                  ; bytes per y

section .rodata
align 16
k_stone16:  times 16 db STONE
align 4
k_quarter:  dd 0.25
k_tun_t:    dd 0.07                     ; |tunnel noise| below this carves
k_tun_up:   dd 0.05                     ; the same above y 72, where only a mouth's tunnels carve (0.07 left a 23 deep run)
k_cav_t:    dd 0.44                     ; cavern noise above this carves: 4.9 % AIR over seed 42's 4096 x 4096
k_rav_a:    dd 0.012                    ; ravine centre band
k_rav_b:    dd 0.30                     ; ravine gate noise
k_pillar_t: dd 0.82                     ; CF_PILLAR: cavern pillars where this noise is above
k_cavern_f: dd -0.25                    ; CF_CAVERN: caverns where this noise is above
k_mouth_t:  dd 0.65                     ; CF_MOUTH: tunnel mouths where this noise is above (0.55 left a 22 deep run)
k_pool_t:   dd 0.40                     ; pool candidates where noise2(shift 4, salt 1770) is above
k_floor_t:  dd 0.30                     ; floor noise above: gravel
k_floor_n:  dd -0.30                    ; floor noise below: mossy cobblestone
k_absmask:  dd 0x7FFFFFFF

; cave fields: shift, salt, ymul (tunnel A, tunnel B, cavern V); the lattice samples noise3(4 i, ymul j, 4 k)
cave_fields:
    dd 5, 2000, 8
    dd 5, 2001, 8
    dd 5, 2005, 12

; Ore table: salt, id, y_min, y_max, attempts per column, vein size (random-walk cells), exposed weight
%define ORE_SALT 0
%define ORE_ID   4
%define ORE_YMIN 8
%define ORE_YMAX 12
%define ORE_ATT  16
%define ORE_SIZE 20
%define ORE_WGT  24
%define ORE_REC  28
ore_tab:
    dd 1, COAL_ORE,    40, 130, 20, 8, 40
    dd 2, IRON_ORE,    15,  80, 12, 6, 30
    dd 3, GOLD_ORE,     5,  40,  3, 5, 20
    dd 4, DIAMOND_ORE,  2,  18,  1, 4, 10
ore_tab_end:

nbr_dx:     db -1, 1, 0, 0              ; the four horizontal neighbours of a cell
nbr_dz:     db 0, 0, -1, 1

section .bss
alignb 16
g_lat:      resb 3 * LAT_F              ; cave field samples, [field][level][k][i]
g_cp:       resd 3 * LAT_LEVELS         ; one cell's field values per level, [field][level]
g_cf:       resb 256                    ; the CF_* flags of every cell of the column, lz * 16 + lx
g_pnm:      resw 16                     ; per row lz, the mask (bit lx) of the cells whose pool noise is above k_pool_t
g_am:       resw AM_Y * 18              ; AIR bit masks of the column rows, [y][lz + 1] bit lx
g_hm:       resd 1                      ; the highest surface of a CF_MOUTH cell of the column, 0 with none
g_buf:      resq 1                      ; the GENBUF being filled
g_tc:       resq 1                      ; its TCELL table, (lz + 3) * TC_W + lx + 3
g_acx:      resd 1
g_acz:      resd 1
g_ax0:      resd 1                      ; acx * 16
g_az0:      resd 1

section .text

; gen_underground(rdi GENBUF* buf, rsi TCELL* tc, edx ax0, ecx az0)
; The caves, then the ores, then the gravel pockets, then the dressing of the column (ax0 / 16, az0 / 16)
; whose terrain is already in buf.blocks and whose terrain cells (the column plus its 3 cell margin) are tc.
gen_underground:
    sub     rsp, 8
    mov     [g_buf], rdi
    mov     [g_tc], rsi
    mov     [g_ax0], edx
    sar     edx, 4
    mov     [g_acx], edx
    mov     [g_az0], ecx
    sar     ecx, 4
    mov     [g_acz], ecx
    call    gen_caves
    call    gen_ores
    call    gen_gravel
    call    cave_dress
    add     rsp, 8
    ret

; tc_h(edi lx, esi lz) -> eax: the surface height of the terrain cell (lx, lz) of the column in progress,
; lx and lz in -3 .. 18. Clobbers rcx.
tc_h:
    add     esi, 3
    imul    esi, esi, TC_W
    lea     eax, [rdi + 3]
    add     eax, esi
    imul    eax, eax, TCELL_size
    mov     rcx, [g_tc]
    mov     eax, [rcx + rax + TCELL.h]
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

; mouth_flag(edi ax, esi az, edx h, ecx slope) -> eax CF_MOUTH or 0
; A tunnel mouth column is land (h >= 97) with noise2(ax, az, 6, 1730) > 0.65 whose terrain falls 4 or more
; within 3 cells: slope = h - min(h(ax -+ 3, az), h(ax, az -+ 3)). gen_underground hands in the slope it
; reads from its terrain cells; a negative slope is computed here with four gen_height calls, after the
; noise has passed. Reentrant.
mouth_flag:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    xor     r15d, r15d
    cmp     r13d, 97
    jl      .out
    mov     edx, 6
    mov     ecx, 1730
    call    noise2                      ; edi, esi are still ax, az
    comiss  xmm0, [k_mouth_t]
    jbe     .out
    test    r14d, r14d
    jns     .slope
    lea     edi, [rbx - 3]
    mov     esi, r12d
    call    gen_height
    mov     r14d, eax                   ; the lowest neighbour so far
    lea     edi, [rbx + 3]
    mov     esi, r12d
    call    gen_height
    cmp     eax, r14d
    cmovl   r14d, eax
    mov     edi, ebx
    lea     esi, [r12 - 3]
    call    gen_height
    cmp     eax, r14d
    cmovl   r14d, eax
    mov     edi, ebx
    lea     esi, [r12 + 3]
    call    gen_height
    cmp     eax, r14d
    cmovl   r14d, eax
    mov     eax, r13d
    sub     eax, r14d
    mov     r14d, eax
.slope:
    cmp     r14d, 4
    jl      .out
    mov     r15d, CF_MOUTH
.out:
    mov     eax, r15d
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; cave_flags(edi ax, esi az, edx h, ecx slope) -> eax CF_* flags of the column cell (ax, az)
; CF_RAVINE, CF_PILLAR, CF_CAVERN and CF_MOUTH, each a function of the cell alone (see the header). slope is
; mouth_flag's. Reentrant.
cave_flags:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    call    ravine_at                   ; CF_RAVINE is 1
    mov     r15d, eax
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 2
    mov     ecx, 1750
    call    noise2
    comiss  xmm0, [k_pillar_t]
    jbe     .no_pillar
    or      r15d, CF_PILLAR
.no_pillar:
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 7
    mov     ecx, 1740
    call    noise2
    comiss  xmm0, [k_cavern_f]
    jbe     .no_cavern
    or      r15d, CF_CAVERN
.no_cavern:
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r14d
    call    mouth_flag
    or      eax, r15d
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; gen_cave_flags(edi ax, esi az) -> eax CF_* flags
; The column flags of the cell at absolute (ax, az), with its terrain height from gen_height. Reentrant.
gen_cave_flags:
    push    rbx
    push    r12
    sub     rsp, 8
    mov     ebx, edi
    mov     r12d, esi
    call    gen_height
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, eax
    mov     ecx, -1
    call    cave_flags
    add     rsp, 8
    pop     r12
    pop     rbx
    ret

; carve_test(edi y, esi h, edx flags, xmm0 A, xmm1 B, xmm2 V) -> eax 0/1
; The one carve decision (the rules are in the header). h is the column's terrain height, flags its CF_*
; flags, A and B the two tunnel field values and V the cavern field value at the cell: only the ones the
; rules read for this y and these flags need to be valid.
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
    movss   xmm5, [k_tun_t]
    cmp     edi, 72
    jle     .tunnel
    test    edx, CF_MOUTH
    jz      .no_tunnel                  ; above y 72 only a mouth's tunnels carve
    movss   xmm5, [k_tun_up]            ; and they are narrower
.tunnel:
    movss   xmm3, [k_absmask]
    movaps  xmm4, xmm0
    andps   xmm4, xmm3
    comiss  xmm4, xmm5
    jae     .no_tunnel
    movaps  xmm4, xmm1
    andps   xmm4, xmm3
    comiss  xmm4, xmm5
    jae     .no_tunnel
    mov     eax, 1
    ret
.no_tunnel:
    cmp     edi, 20
    jl      .no_cavern
    cmp     edi, 56
    jg      .no_cavern
    test    edx, CF_CAVERN
    jz      .no_cavern
    test    edx, CF_PILLAR
    jnz     .no_cavern
    comiss  xmm2, [k_cav_t]
    jbe     .no_cavern
    mov     eax, 1
    ret
.no_cavern:
    test    edx, CF_RAVINE
    jz      .out
    cmp     edi, 25
    jl      .out
    cmp     edi, 70
    jg      .out
    lea     ecx, [rsi - 10]
    cmp     edi, ecx
    jg      .out                        ; a ravine keeps 10 cells of roof
    mov     eax, 1
.out:
    ret

; BILERP: xmm0 = bilerp of v00 = xmm0, v10 = xmm1, v01 = xmm2, v11 = xmm3 by wx = xmm4, wz = xmm5
; (a = v00 + (v10 - v00) wx, b = v01 + (v11 - v01) wx, a + (b - a) wz). Clobbers xmm1-xmm3.
; The cave pass and carved_at both interpolate with this and nothing else.
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

; cave_field(edi ax, esi y, edx az, ecx shift, r8d salt, r9d ymul) -> xmm0
; The value of one cave field at the cell: noise3(4 i, ymul j, 4 k, shift, salt) sampled on the 4 block
; lattice (ymul is the vertical squash), bilinear in x and z at the two levels around y, then linear in y.
; gen_column's lattice holds the same samples, so both agree to the bit.
cave_field:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56                     ; [0] wx [4] wz [8] wy [12] shift [16] salt [20] level0 [24] level1 [28] ymul
    mov     [rsp + 12], ecx
    mov     [rsp + 16], r8d
    mov     [rsp + 28], r9d
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
    imul    esi, [rsp + 28]
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
; carve_test for the cell (ax, y, az) of a column whose terrain height h the caller already knows. It
; evaluates only the flags and noise fields the rules read for this y: nothing below y 12 carves, above
; y 72 only a mouth's tunnels, the cavern flags only at y 20..56, the ravine only at y 25..min(70, h - 10).
; gen_carved, the vegetation pass and the pool step of cave_dress call it. Reentrant.
carved_at:
    push    rbp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40                     ; [0] A [4] B [8] V
    xor     eax, eax
    cmp     esi, 12
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
    xor     r15d, r15d                  ; flags
    pxor    xmm0, xmm0
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm0
    movss   [rsp + 8], xmm0
    cmp     r12d, 72
    jg      .upper
    cmp     r12d, 20
    jl      .ravine
    cmp     r12d, 56
    jg      .ravine
    mov     edi, ebx                    ; y 20..56: the cavern and pillar flags
    mov     esi, r13d
    mov     edx, 7
    mov     ecx, 1740
    call    noise2
    comiss  xmm0, [k_cavern_f]
    jbe     .ravine
    or      r15d, CF_CAVERN
    mov     edi, ebx
    mov     esi, r13d
    mov     edx, 2
    mov     ecx, 1750
    call    noise2
    comiss  xmm0, [k_pillar_t]
    jbe     .ravine
    or      r15d, CF_PILLAR
.ravine:
    cmp     r12d, 25
    jl      .tunnels
    cmp     r12d, 70
    jg      .tunnels
    lea     eax, [r14 - 10]
    cmp     r12d, eax
    jg      .tunnels
    mov     edi, ebx
    mov     esi, r13d
    call    ravine_at
    or      r15d, eax
.tunnels:
    mov     edi, ebx                    ; the tunnel fields A and B
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, [cave_fields]
    mov     r8d, [cave_fields + 4]
    mov     r9d, [cave_fields + 8]
    call    cave_field
    movss   [rsp], xmm0
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, [cave_fields + 12]
    mov     r8d, [cave_fields + 16]
    mov     r9d, [cave_fields + 20]
    call    cave_field
    movss   [rsp + 4], xmm0
    mov     eax, r15d
    and     eax, CF_CAVERN | CF_PILLAR
    cmp     eax, CF_CAVERN
    jne     .test                       ; the cavern field only where a cavern can carve
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, [cave_fields + 24]
    mov     r8d, [cave_fields + 28]
    mov     r9d, [cave_fields + 32]
    call    cave_field
    movss   [rsp + 8], xmm0
    jmp     .test
.upper:                                 ; y 73..h: a mouth's tunnels only
    mov     edi, ebx
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, -1
    call    mouth_flag
    test    eax, eax
    jz      .out
    mov     r15d, eax
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, [cave_fields]
    mov     r8d, [cave_fields + 4]
    mov     r9d, [cave_fields + 8]
    call    cave_field
    movss   [rsp], xmm0
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, [cave_fields + 12]
    mov     r8d, [cave_fields + 16]
    mov     r9d, [cave_fields + 20]
    call    cave_field
    movss   [rsp + 4], xmm0
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

; gen_caves(): the flags of every cell, the lattice samples of the three cave fields and the carving.
gen_caves:
    sub     rsp, 8
    call    cave_flag_cells
    call    cave_lattice
    call    cave_carve
    add     rsp, 8
    ret

; cave_flag_cells(): g_cf of the column's cells (cave_flags with the slope read from the terrain cells) and
; g_hm, the highest surface among its mouth cells (0 with none). Cells lower than 12 carve nothing: flags 0.
cave_flag_cells:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16                     ; [0] lz [4] lx
    mov     dword [g_hm], 0
    mov     dword [rsp], 0
.lz:
    mov     dword [rsp + 4], 0
.lx:
    mov     edi, [rsp + 4]
    mov     esi, [rsp]
    call    tc_h
    mov     r14d, eax                   ; h
    xor     r15d, r15d                  ; flags
    cmp     r14d, 12
    jl      .store
    mov     eax, [rsp]
    add     eax, 3
    imul    eax, eax, TC_W
    mov     ecx, [rsp + 4]
    add     ecx, 3
    add     eax, ecx
    imul    eax, eax, TCELL_size
    mov     rcx, [g_tc]
    lea     r13, [rcx + rax]            ; the cell's TCELL
    xor     ecx, ecx
    cmp     r14d, 97
    jl      .call                       ; no mouth on low land: the slope does not matter
    mov     eax, [r13 - 3 * TCELL_size]
    mov     edx, [r13 + 3 * TCELL_size]
    cmp     edx, eax
    cmovl   eax, edx
    mov     edx, [r13 - 3 * TC_W * TCELL_size]
    cmp     edx, eax
    cmovl   eax, edx
    mov     edx, [r13 + 3 * TC_W * TCELL_size]
    cmp     edx, eax
    cmovl   eax, edx
    mov     ecx, r14d
    sub     ecx, eax                    ; slope
.call:
    mov     edi, [rsp + 4]
    add     edi, [g_ax0]
    mov     esi, [rsp]
    add     esi, [g_az0]
    mov     edx, r14d
    call    cave_flags
    mov     r15d, eax
    test    r15d, CF_MOUTH
    jz      .store
    cmp     r14d, [g_hm]
    jle     .store
    mov     [g_hm], r14d
.store:
    mov     eax, [rsp]
    shl     eax, 4
    add     eax, [rsp + 4]
    lea     rcx, [g_cf]
    mov     [rcx + rax], r15b
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], 16
    jb      .lx
    inc     dword [rsp]
    cmp     dword [rsp], 16
    jb      .lz
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; cave_lattice(): samples the three cave fields on the 4 block lattice of the column into g_lat: levels
; LAT_JLO..LAT_JHI of each, and for the two tunnel fields of a column with a mouth the levels up to the one
; above its highest mouth surface.
cave_lattice:
    push    rbx
    push    r12
    push    r14
    push    r15
    sub     rsp, 8                      ; [0] last level of the field
    xor     r12d, r12d                  ; field
.f:
    mov     eax, LAT_JHI
    cmp     r12d, 2
    jae     .last
    mov     ecx, [g_hm]
    test    ecx, ecx
    jz      .last
    shr     ecx, 2
    inc     ecx
    mov     eax, ecx
.last:
    mov     [rsp], eax
    mov     ebx, LAT_JLO                ; level j
.j:
    xor     r14d, r14d                  ; k
.k:
    xor     r15d, r15d                  ; i
.i:
    lea     rax, [cave_fields]
    lea     rcx, [r12 + r12*2]
    lea     rax, [rax + rcx*4]          ; this field's row
    mov     esi, ebx
    imul    esi, [rax + 8]              ; y = ymul * j
    mov     edi, r15d
    shl     edi, 2
    add     edi, [g_ax0]                ; x = ax0 + 4 i
    mov     edx, r14d
    shl     edx, 2
    add     edx, [g_az0]                ; z = az0 + 4 k
    mov     ecx, [rax]
    mov     r8d, [rax + 4]
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
    cmp     ebx, [rsp]
    jbe     .j
    inc     r12d
    cmp     r12d, 3
    jb      .f
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r12
    pop     rbx
    ret

; cave_carve(): walks every cell of the column from y 12 up to its carve limit (the surface in a mouth
; cell, otherwise 72 or the surface) and clears the ones carve_test says are carved, with the field values
; interpolated from the lattice. A carved surface cell takes the snow layer above it along.
cave_carve:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40                     ; [0] lz [4] lx [12] 1 when the cell's cavern can carve
    mov     dword [rsp], 0
.lz:
    mov     dword [rsp + 4], 0
.lx:
    mov     edi, [rsp + 4]
    mov     esi, [rsp]
    call    tc_h
    mov     r14d, eax                   ; h
    cmp     r14d, 12
    jl      .nextcell                   ; nothing below y 12 carves
    mov     eax, [rsp]
    shl     eax, 4
    add     eax, [rsp + 4]
    lea     rcx, [g_cf]
    movzx   r15d, byte [rcx + rax]      ; the cell's flags
    mov     rcx, [g_buf]
    lea     r13, [rcx + GENBUF.blocks]
    add     r13, rax                    ; the cell's column pointer
    mov     ebx, 72                     ; highest y worth testing: 72, or the surface of a low or mouth cell
    cmp     ebx, r14d
    cmovg   ebx, r14d
    test    r15d, CF_MOUTH
    cmovnz  ebx, r14d
    mov     eax, r15d
    and     eax, CF_CAVERN | CF_PILLAR
    xor     ecx, ecx
    cmp     eax, CF_CAVERN
    sete    cl
    mov     [rsp + 12], ecx
    ; weights, and the field values of every level over this cell
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
    mov     r8d, ebx
    shr     r8d, 2
    inc     r8d                         ; the tunnel fields' last level: the one above the limit's
    xor     r12d, r12d                  ; field
.cpf:
    cmp     r12d, 2
    jb      .tunnel_levels
    cmp     dword [rsp + 12], 0
    je      .cp_done                    ; no cavern in this cell: the cavern field is not read
    mov     r9d, 5                      ; the cavern field is read at y 20..56: levels 5..15
    mov     ecx, 15 - 5 + 1
    jmp     .cp_go
.tunnel_levels:
    mov     r9d, LAT_JLO
    mov     ecx, r8d
    sub     ecx, LAT_JLO - 1
.cp_go:
    imul    eax, r12d, LAT_F
    imul    r10d, r9d, LAT_J
    add     eax, r10d
    lea     rdx, [rsi + rax]            ; the lattice at (field, first level, this cell's k, i)
    imul    eax, r12d, CP_F
    lea     r10, [rdi + r9*4]
    add     r10, rax                    ; g_cp[field][first level]
.cpj:
    movss   xmm0, [rdx]
    movss   xmm1, [rdx + LAT_I]
    movss   xmm2, [rdx + LAT_K]
    movss   xmm3, [rdx + LAT_K + LAT_I]
    BILERP
    movss   [r10], xmm0
    add     rdx, LAT_J
    add     r10, 4
    dec     ecx
    jnz     .cpj
    inc     r12d
    cmp     r12d, 3
    jb      .cpf
.cp_done:
    mov     r12d, 12                    ; y
.y:
    cmp     r12d, ebx
    jg      .nextcell
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
    movss   xmm1, [rdx + CP_F]
    movss   xmm4, [rdx + CP_F + 4]
    subss   xmm4, xmm1
    mulss   xmm4, xmm3
    addss   xmm1, xmm4                  ; tunnel B
    pxor    xmm2, xmm2
    cmp     dword [rsp + 12], 0
    je      .test
    cmp     r12d, 20
    jl      .test
    cmp     r12d, 56
    jg      .test
    movss   xmm2, [rdx + 2 * CP_F]
    movss   xmm4, [rdx + 2 * CP_F + 4]
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

; ---------------------------------------------------------------------------------------------
; the dressing of the caves

; cave_dress(): after the carving, ores and gravel pockets: pools sunk into the floors, gravel and moss on the
; rest of the floors, then ore on the cave walls. Pools go first so that floors do not break up a pool. The
; passes only ever replace STONE cells, so the AIR bit masks g_am are taken once and stay right.
cave_dress:
    sub     rsp, 8
    call    dress_masks
    call    dress_pools
    call    dress_floors
    call    dress_ore
    add     rsp, 8
    ret

; dress_masks(): g_am[y][lz + 1] = the bit mask (bit lx) of the AIR cells of row (y, lz), y 0..132.
dress_masks:
    mov     rsi, [g_buf]
    lea     rsi, [rsi + GENBUF.blocks]
    lea     rdx, [g_am]
    pxor    xmm1, xmm1
    xor     ecx, ecx                    ; y
.y:
    lea     r8, [rdx + 2]               ; the word of lz 0
    mov     r9, rsi                     ; the row (y, 0)
    mov     r10d, 16
.lz:
    movdqu  xmm0, [r9]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    mov     [r8], ax
    add     r9, 16
    add     r8, 2
    dec     r10d
    jnz     .lz
    add     rsi, 256
    add     rdx, AM_ROW
    inc     ecx
    cmp     ecx, AM_Y
    jb      .y
    ret

; dress_floors(): every STONE cell with an AIR cell above it, 6 <= y <= min(h - 8, 80), becomes GRAVEL where
; noise3(ax, y, az, 3, 1760) > 0.30 and MOSSY_COBBLESTONE where it is below -0.30.
dress_floors:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16                     ; [0] y [4] lz
    mov     dword [rsp], 6
.y:
    mov     dword [rsp + 4], 0
.lz:
    mov     eax, [rsp]
    shl     eax, 8
    mov     ecx, [rsp + 4]
    shl     ecx, 4
    add     eax, ecx
    mov     rsi, [g_buf]
    movdqu  xmm0, [rsi + GENBUF.blocks + rax]
    pcmpeqb xmm0, [k_stone16]
    pmovmskb ebx, xmm0                  ; the STONE cells of the row
    test    ebx, ebx
    jz      .nextlz
    mov     eax, [rsp]
    inc     eax
    imul    eax, eax, 18
    add     eax, [rsp + 4]
    inc     eax
    lea     rcx, [g_am]
    movzx   eax, word [rcx + rax*2]     ; the AIR cells of the row above
    and     ebx, eax
    jz      .nextlz
.bit:
    bsf     r12d, ebx                   ; lx
    lea     eax, [rbx - 1]
    and     ebx, eax
    mov     edi, r12d
    mov     esi, [rsp + 4]
    call    tc_h
    sub     eax, 8
    cmp     [rsp], eax
    jg      .nextbit                    ; y <= h - 8
    mov     edi, [g_ax0]
    add     edi, r12d
    mov     esi, [rsp]
    mov     edx, [g_az0]
    add     edx, [rsp + 4]
    mov     ecx, 3
    mov     r8d, 1760
    call    noise3
    mov     r13d, GRAVEL
    comiss  xmm0, [k_floor_t]
    ja      .set
    movss   xmm1, [k_floor_n]
    mov     r13d, MOSSY_COBBLESTONE
    comiss  xmm1, xmm0
    jbe     .nextbit
.set:
    mov     eax, [rsp]
    shl     eax, 8
    mov     ecx, [rsp + 4]
    shl     ecx, 4
    add     eax, ecx
    add     eax, r12d
    mov     rsi, [g_buf]
    mov     [rsi + GENBUF.blocks + rax], r13b
.nextbit:
    test    ebx, ebx
    jnz     .bit
.nextlz:
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], 16
    jb      .lz
    inc     dword [rsp]
    cmp     dword [rsp], 80
    jbe     .y
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; ore_pick(edi y, esi r) -> eax block id (0 when no ore row holds y)
; The exposed ore of the cell at height y: among the ore_tab rows whose [ymin, ymax] holds y, the one that
; ((r >> 10) % total weight) lands on when the weights are walked in table order.
ore_pick:
    lea     rdx, [ore_tab]
    xor     ecx, ecx                    ; the total weight of the rows that hold y
.sum:
    cmp     edi, [rdx + ORE_YMIN]
    jl      .snext
    cmp     edi, [rdx + ORE_YMAX]
    jg      .snext
    add     ecx, [rdx + ORE_WGT]
.snext:
    add     rdx, ORE_REC
    lea     rax, [ore_tab_end]
    cmp     rdx, rax
    jb      .sum
    xor     eax, eax
    test    ecx, ecx
    jz      .out
    mov     eax, esi
    shr     eax, 10
    xor     edx, edx
    div     ecx
    mov     esi, edx                    ; the pick
    lea     rdx, [ore_tab]
.walk:
    cmp     edi, [rdx + ORE_YMIN]
    jl      .wnext
    cmp     edi, [rdx + ORE_YMAX]
    jg      .wnext
    mov     eax, [rdx + ORE_WGT]
    cmp     esi, eax
    jb      .found
    sub     esi, eax
.wnext:
    add     rdx, ORE_REC
    jmp     .walk                       ; the pick is below the total: some row holds it
.found:
    mov     eax, [rdx + ORE_ID]
.out:
    ret

; dress_ore(): every STONE cell with 2 <= y <= min(h - 6, 130) and an AIR cell among its six neighbours in
; the column turns to ore where (hash32(ax, az, 4000 + y) & 1023) < 20, the ore picked by ore_pick. The
; exposed cells of a row are found with its bit mask: the STONE cells of the row, and the AIR cells of the
; rows next to it (the same row shifted by one cell, the rows lz -+ 1, the rows y -+ 1).
dress_ore:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16                     ; [0] y [4] lz
    mov     dword [rsp], 2
.y:
    mov     dword [rsp + 4], 0
.lz:
    mov     eax, [rsp]
    shl     eax, 8
    mov     ecx, [rsp + 4]
    shl     ecx, 4
    add     eax, ecx
    mov     rsi, [g_buf]
    movdqu  xmm0, [rsi + GENBUF.blocks + rax]
    pcmpeqb xmm0, [k_stone16]
    pmovmskb ebx, xmm0                  ; the STONE cells of the row
    test    ebx, ebx
    jz      .nextlz
    mov     eax, [rsp]
    imul    eax, eax, 18
    add     eax, [rsp + 4]
    inc     eax
    lea     rcx, [g_am]
    lea     rcx, [rcx + rax*2]          ; the AIR word of this row
    movzx   eax, word [rcx]
    mov     edx, eax
    add     edx, edx                    ; AIR at lx - 1
    shr     eax, 1                      ; AIR at lx + 1
    or      edx, eax
    movzx   eax, word [rcx - 2]
    or      edx, eax                    ; AIR at lz - 1
    movzx   eax, word [rcx + 2]
    or      edx, eax                    ; AIR at lz + 1
    movzx   eax, word [rcx - AM_ROW]
    or      edx, eax                    ; AIR at y - 1
    movzx   eax, word [rcx + AM_ROW]
    or      edx, eax                    ; AIR at y + 1
    and     ebx, edx
    jz      .nextlz
.bit:
    bsf     r12d, ebx                   ; lx
    lea     eax, [rbx - 1]
    and     ebx, eax
    mov     edi, r12d
    mov     esi, [rsp + 4]
    call    tc_h
    sub     eax, 6
    cmp     [rsp], eax
    jg      .nextbit                    ; y <= h - 6
    mov     edi, [g_ax0]
    add     edi, r12d
    mov     esi, [g_az0]
    add     esi, [rsp + 4]
    mov     edx, [rsp]
    add     edx, 4000
    call    hash32
    mov     r13d, eax
    and     eax, 1023
    cmp     eax, 20
    jae     .nextbit
    mov     edi, [rsp]
    mov     esi, r13d
    call    ore_pick
    test    eax, eax
    jz      .nextbit
    mov     ecx, [rsp]
    shl     ecx, 8
    mov     edx, [rsp + 4]
    shl     edx, 4
    add     ecx, edx
    add     ecx, r12d
    mov     rsi, [g_buf]
    mov     [rsi + GENBUF.blocks + rcx], al
.nextbit:
    test    ebx, ebx
    jnz     .bit
.nextlz:
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], 16
    jb      .lz
    inc     dword [rsp]
    cmp     dword [rsp], 130
    jbe     .y
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; pool_nbr_carved(edi nlx, esi nlz, edx y) -> eax 1 when the cell (nlx, y, nlz), nlx and nlz in -1 .. 16, is
; carved (a cave cell, not the sky over lower ground)
; In the column that is an AIR cell at or below the terrain surface tc_h gives for it; outside the column,
; which the buffer does not hold, it is carved_at. The two agree, so both sides of a column border decide a
; pool cell the same way.
pool_nbr_carved:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     ebx, edi                    ; nlx
    mov     r12d, esi                   ; nlz
    mov     r13d, edx                   ; y
    call    tc_h
    mov     r14d, eax                   ; the neighbour's surface
    cmp     ebx, 15
    ja      .outside
    cmp     r12d, 15
    ja      .outside
    xor     eax, eax
    cmp     r13d, r14d
    jg      .out                        ; sky
    mov     eax, r12d
    shl     eax, 4
    add     eax, ebx
    mov     ecx, r13d
    shl     ecx, 8
    add     eax, ecx
    mov     rcx, [g_buf]
    cmp     byte [rcx + GENBUF.blocks + rax], AIR
    sete    al
    movzx   eax, al
    jmp     .out
.outside:
    mov     edi, [g_ax0]
    add     edi, ebx
    mov     esi, r13d
    mov     edx, [g_az0]
    add     edx, r12d
    mov     ecx, r14d
    call    carved_at
.out:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; dress_pools(): the floor cell of a cave sinks into a pool. A STONE cell at 6 <= y <= min(h - 8, 80) turns
; to LAVA (y <= 30) or WATER (above) where all of these hold: the cell above it is AIR (an open floor), the cell
; below it is not AIR (the pool is one cell deep and has a bed), noise2(ax, az, 4, 1770) > 0.40, and none of
; its four horizontal neighbours at its own level is carved (pool_nbr_carved): the pool sits in a basin of
; rock, so no liquid cell has AIR beside it. Everything a cell reads is the carving (AIR in the buffer or
; carved_at) or its own block, which no other pool cell changes, so the order of the cells does not matter and
; both sides of a column border decide alike. Candidate cells of a row are found with the row's bit masks:
; STONE, with AIR above and not below, in the cells whose pool noise is high.
; Why not the AIR cell above the floor, with neighbours that are rock or candidates themselves: whatever
; subset of a carved level a local rule turns to liquid ends in a candidate that the rule rejected for its
; own neighbours, so 31 % of such pool cells had AIR beside them (28 % with a second ring), where this has none.
dress_pools:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 16                     ; [0] y [4] lz
    xor     r14d, r14d                  ; the pool noise masks of all rows, or-ed
    xor     r13d, r13d                  ; lz
.pnz:
    xor     ebx, ebx                    ; the row's mask: bit lx = pool noise above k_pool_t
    xor     r12d, r12d                  ; lx
.pnx:
    mov     edi, [g_ax0]
    add     edi, r12d
    mov     esi, [g_az0]
    add     esi, r13d
    mov     edx, 4
    mov     ecx, 1770
    call    noise2
    comiss  xmm0, [k_pool_t]
    jbe     .pnno
    bts     ebx, r12d
.pnno:
    inc     r12d
    cmp     r12d, 16
    jb      .pnx
    lea     rax, [g_pnm]
    mov     [rax + r13*2], bx
    or      r14d, ebx
    inc     r13d
    cmp     r13d, 16
    jb      .pnz
    test    r14d, r14d
    jz      .out                        ; no cell of the column has pool noise
    mov     dword [rsp], 6
.y:
    mov     dword [rsp + 4], 0
.lz:
    mov     eax, [rsp + 4]
    lea     rcx, [g_pnm]
    movzx   ebx, word [rcx + rax*2]
    test    ebx, ebx
    jz      .nextlz
    mov     eax, [rsp]
    shl     eax, 8
    mov     ecx, [rsp + 4]
    shl     ecx, 4
    add     eax, ecx
    mov     rsi, [g_buf]
    movdqu  xmm0, [rsi + GENBUF.blocks + rax]
    pcmpeqb xmm0, [k_stone16]
    pmovmskb eax, xmm0                  ; the STONE cells of the row
    and     ebx, eax
    jz      .nextlz
    mov     eax, [rsp]
    imul    eax, eax, 18
    add     eax, [rsp + 4]
    inc     eax
    lea     rcx, [g_am]
    lea     rcx, [rcx + rax*2]          ; the AIR word of this row
    movzx   eax, word [rcx + AM_ROW]
    and     ebx, eax                    ; AIR above
    movzx   eax, word [rcx - AM_ROW]
    not     eax
    and     ebx, eax                    ; and not AIR below
    jz      .nextlz
.bit:
    bsf     r12d, ebx                   ; lx
    lea     eax, [rbx - 1]
    and     ebx, eax
    mov     edi, r12d
    mov     esi, [rsp + 4]
    call    tc_h
    sub     eax, 8
    cmp     [rsp], eax
    jg      .nextbit                    ; y <= h - 8
    xor     r15d, r15d                  ; neighbour
.nb:
    lea     rcx, [nbr_dx]
    movsx   edi, byte [rcx + r15]
    add     edi, r12d
    lea     rcx, [nbr_dz]
    movsx   esi, byte [rcx + r15]
    add     esi, [rsp + 4]
    mov     edx, [rsp]
    call    pool_nbr_carved
    test    eax, eax
    jnz     .nextbit                    ; carved beside it: the liquid would have AIR at its side
    inc     r15d
    cmp     r15d, 4
    jb      .nb
    mov     eax, [rsp]
    shl     eax, 8
    mov     ecx, [rsp + 4]
    shl     ecx, 4
    add     eax, ecx
    add     eax, r12d
    mov     cl, WATER
    cmp     dword [rsp], 30
    jg      .set
    mov     cl, LAVA
.set:
    mov     rsi, [g_buf]
    mov     [rsi + GENBUF.blocks + rax], cl
.nextbit:
    test    ebx, ebx
    jnz     .bit
.nextlz:
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], 16
    jb      .lz
    inc     dword [rsp]
    cmp     dword [rsp], 80
    jbe     .y
.out:
    add     rsp, 16
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
