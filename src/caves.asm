; caves.asm - the underground of a generated column: tunnels, caverns and ravines, ores, gravel pockets.
;
; gen_underground(buf, tc, ax0, az0) is called by gen_column after the surface is laid; it carves,
; then places ores and gravel, in that order. carved_at, gen_carved and gen_cave_flags are pure
; functions of the absolute cell and of gen_seed and are reentrant (the main thread calls them while
; the worker runs gen_column); everything else belongs to the one thread that runs gen_column.
; carved_at agrees bit for bit with the lattice pass of gen_caves: both interpolate the same
; lattice samples with BILERP and the same carve_test.
%include "common.inc"
default rel

global gen_underground, carved_at, gen_carved

extern hash32, noise3, fbm2
extern gen_height

; cave lattice: 4 block spacing, levels j (y = 4 j) 0..21 of the three fields, 5 x 5 points per level
%define LAT_I       4                   ; bytes per x step
%define LAT_K       32                  ; per z step (5 floats, padded to 8)
%define LAT_J       160                 ; per level
%define LAT_F       3520                ; per field (22 levels)
%define LAT_JLO     3
%define LAT_JHI     21

section .rodata
align 4
k_quarter:  dd 0.25
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
alignb 16
g_lat:      resb 3 * LAT_F              ; cave field samples, [field][level][k][i]
g_cp:       resd 3 * 22                 ; one cell's field values per level, [field][level]
g_buf:      resq 1                      ; the GENBUF being filled
g_tc:       resq 1                      ; its TCELL table, (lz + 3) * TC_W + lx + 3
g_acx:      resd 1
g_acz:      resd 1
g_ax0:      resd 1                      ; acx * 16
g_az0:      resd 1

section .text

; gen_underground(rdi GENBUF* buf, rsi TCELL* tc, edx ax0, ecx az0)
; The caves, then the ores, then the gravel pockets of the column (ax0 / 16, az0 / 16) whose terrain
; is already in buf.blocks and whose terrain cells (the column plus its 3 cell margin) are tc.
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
    add     rsp, 8
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
    mov     rcx, [g_tc]
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
