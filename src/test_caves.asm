; test_caves.asm - the generator's underground: roofed ravines, tunnel mouths and the dressing of the caves.
%include "common.inc"
default rel

global test_caves_reworked

extern world_clear, fnv1a
extern worldgen_set_seed, gen_column, gen_height, gen_find_spawn
extern gen_carved, carved_at, gen_cave_flags, gen_underground
extern road_mask

%define WIN         20                  ; the window: WIN x WIN columns from the spawn column
%define BW          4                   ; the closing check's window: BW x BW bare columns
%define EXTRA       400                 ; more columns to look through when the window holds no mouth column

; counters, dwords of cnt
%define C_UNDER     0                   ; land cells (h >= 97) counted at y 5 .. h - 5
%define C_AIR       1                   ; ... of which AIR
%define C_ABAD      2                   ; (a) carved above y 72 in a column without a mouth
%define C_BBAD      3                   ; (b) surface runs of carved cells of 20 or more
%define C_LAVA      4                   ; (d) LAVA at y <= h - 8
%define C_WATER     5                   ; (d) WATER at y <= h - 8
%define C_PBAD      6                   ; (d) liquid cells that break the placement rules
%define C_POOL      7                   ; (d) liquid cells at y <= h - 8
%define C_FACE      8                   ; (d) ... with an AIR cell beside them in the column
%define C_EXORE     9                   ; (e) ore with an AIR neighbour in the column
%define C_GRAVEL    10                  ; (e) GRAVEL with AIR above at y <= h - 8
%define C_MOSS      11                  ; (e) MOSSY_COBBLESTONE with AIR above at y <= h - 8
%define C_MOUTH     12                  ; (f) 1 once a mouth column is found
%define C_FBAD      13                  ; (f) cells of that column where gen_carved and the block disagree
%define C_XSTONE    14                  ; (e) STONE cells with an AIR neighbour, in the cells with even lx and lz
%define C_MCX       15                  ; the mouth column
%define C_MCZ       16
%define C_XORE      17                  ; (e) ore cells among the exposed ones of those cells

; BUMP idx: one more for a counter
%macro BUMP 1
    inc     dword [cnt + %1 * 4]
%endmacro

section .bss
alignb 64
cbuf:       resb GENBUF_size            ; the column under test
bbuf:       resb BW * BW * GENBUF_size  ; the bare columns of the closing check, a BW x BW window
alignb 16
tctab:      resb TC_CELLS * TCELL_size  ; terrain cells (heights only) of a bare column
spawn:      resd 4
cnt:        resd 24
gcols:      resd 12                     ; (g) the columns that are generated twice, cx and cz
ghash:      resd 6                      ; and their hashes

section .rodata
gorder:     db 3, 0, 5, 2, 4, 1         ; (g) the order the columns are generated in the second time

section .text

; gen_into(edi cx, esi cz) -> rax cbuf
; Fills the buffer with 0xA5 (so a byte gen_column forgets to write stays visible), then generates column
; (cx, cz) into it with the current seed.
gen_into:
    push    rbx
    push    r12
    push    r13
    mov     r12d, edi
    mov     r13d, esi
    lea     rbx, [cbuf]
    mov     rdi, rbx
    mov     ecx, GENBUF_size
    mov     al, 0xA5
    rep     stosb
    mov     [rbx + GENBUF.cx], r12d
    mov     [rbx + GENBUF.cz], r13d
    mov     rdi, rbx
    call    gen_column
    mov     rax, rbx
    pop     r13
    pop     r12
    pop     rbx
    ret

; hash_col(rdi GENBUF*) -> eax: FNV-1a of the column's blocks and biome map
hash_col:
    sub     rsp, 8
    add     rdi, GENBUF.blocks
    mov     esi, 65536 + 256
    call    fnv1a
    add     rsp, 8
    ret

; air_around(rdi cell, esi lx, edx lz, ecx vertical) -> eax 1 when an AIR cell lies beside the cell in its
; column: lx -+ 1, lz -+ 1 and, when vertical is non-zero, y -+ 1 (rdi points at the cell in the blocks)
air_around:
    xor     eax, eax
    test    esi, esi
    jz      .a
    cmp     byte [rdi - 1], AIR
    jne     .a
    mov     eax, 1
.a:
    cmp     esi, 15
    jae     .b
    cmp     byte [rdi + 1], AIR
    jne     .b
    mov     eax, 1
.b:
    test    edx, edx
    jz      .c
    cmp     byte [rdi - 16], AIR
    jne     .c
    mov     eax, 1
.c:
    cmp     edx, 15
    jae     .d
    cmp     byte [rdi + 16], AIR
    jne     .d
    mov     eax, 1
.d:
    test    ecx, ecx
    jz      .out
    cmp     byte [rdi - 256], AIR
    jne     .e
    mov     eax, 1
.e:
    cmp     byte [rdi + 256], AIR
    jne     .out
    mov     eax, 1
.out:
    ret

; scan_cell_blocks(rdi p, esi h, edx lx, ecx lz)
; The generated blocks of one cell (p points at the cell at y 0, h is its terrain height): the underground
; air of land cells (y 5 .. h - 5), and, for y 6 .. h - 8, the liquid placement (LAVA only at y <= 30, WATER
; only at 31 .. 80, a cell that is not AIR below, an AIR cell beside it counted), ore with an AIR neighbour,
; and GRAVEL and MOSSY_COBBLESTONE with AIR above. In the cells whose lx and lz are even it also counts the
; STONE cells with an AIR neighbour (y <= min(h - 8, 130)) and the ore among the exposed cells.
scan_cell_blocks:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi                   ; h
    mov     r13d, edx                   ; lx
    mov     r14d, ecx                   ; lz
    xor     r15d, r15d                  ; bit 0: land, bit 1: lx and lz even
    cmp     r12d, 97
    setge   r15b
    mov     eax, r13d
    or      eax, r14d
    test    eax, 1
    jnz     .nosub
    or      r15d, 2
.nosub:
    lea     r9d, [r12 - 8]              ; last y of a cell that is not land
    test    r15d, 1
    jz      .go
    lea     r9d, [r12 - 5]
.go:
    mov     ebp, 5                      ; y
.y:
    cmp     ebp, r9d
    jg      .done
    mov     eax, ebp
    shl     eax, 8
    movzx   ecx, byte [rbx + rax]       ; the block
    test    r15d, 1
    jz      .classify
    BUMP    C_UNDER
    test    ecx, ecx
    jnz     .classify
    BUMP    C_AIR
.classify:
    cmp     ecx, STONE
    jne     .notstone
    test    r15d, 2
    jz      .next
    cmp     ebp, 6
    jl      .next
    lea     edx, [r12 - 8]
    cmp     ebp, edx
    jg      .next
    cmp     ebp, 130
    jg      .next
    lea     rdi, [rbx + rax]
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, 1
    call    air_around
    test    eax, eax
    jz      .next
    BUMP    C_XSTONE
    jmp     .next
.notstone:
    test    ecx, ecx
    jz      .next
    cmp     ebp, 6
    jl      .next
    lea     edx, [r12 - 8]
    cmp     ebp, edx
    jg      .next
    cmp     ecx, LAVA
    je      .lava
    cmp     ecx, WATER
    je      .water
    lea     edx, [rcx - COAL_ORE]
    cmp     edx, DIAMOND_ORE - COAL_ORE
    jbe     .ore
    cmp     ecx, GRAVEL
    je      .gravel
    cmp     ecx, MOSSY_COBBLESTONE
    je      .moss
    jmp     .next
.lava:
    BUMP    C_LAVA
    cmp     ebp, 30
    jle     .pool
    BUMP    C_PBAD                      ; LAVA above y 30
    jmp     .pool
.water:
    BUMP    C_WATER
    cmp     ebp, 31
    jl      .wrong
    cmp     ebp, 80
    jle     .pool
.wrong:
    BUMP    C_PBAD                      ; WATER outside 31 .. 80
.pool:
    BUMP    C_POOL
    cmp     byte [rbx + rax - 256], AIR
    jne     .bed
    BUMP    C_PBAD                      ; nothing under the liquid
.bed:
    lea     rdi, [rbx + rax]
    mov     esi, r13d
    mov     edx, r14d
    xor     ecx, ecx
    call    air_around
    test    eax, eax
    jz      .next
    BUMP    C_FACE
    jmp     .next
.ore:
    lea     rdi, [rbx + rax]
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, 1
    call    air_around
    test    eax, eax
    jz      .next
    BUMP    C_EXORE
    test    r15d, 2
    jz      .next
    BUMP    C_XORE
    jmp     .next
.gravel:
    cmp     byte [rbx + rax + 256], AIR
    jne     .next
    BUMP    C_GRAVEL
    jmp     .next
.moss:
    cmp     byte [rbx + rax + 256], AIR
    jne     .next
    BUMP    C_MOSS
.next:
    inc     ebp
    jmp     .y
.done:
    add     rsp, 8
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; scan_cell_carve(edi ax, esi az, edx h, ecx viag)
; The carve decision at the cell's surface and above (viag non-zero: through gen_carved, which looks the
; height up itself, otherwise carved_at with h). (b) the run of carved cells from y = h downward must be
; shorter than 20. (a) on land, a cell carved at y 73 .. h (every 8th y and the surface are looked at) must
; be in a column whose flags hold CF_MOUTH.
scan_cell_carve:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, 8
    mov     ebx, edi                    ; ax
    mov     r12d, esi                   ; az
    mov     r13d, edx                   ; h
    mov     ebp, ecx                    ; via gen_carved
    mov     r14d, r13d                  ; y
    xor     r15d, r15d                  ; run
.run:
    cmp     r14d, 5
    jl      .runend
    mov     edi, ebx
    mov     esi, r14d
    mov     edx, r12d
    mov     ecx, r13d
    call    .carved
    test    eax, eax
    jz      .runend
    inc     r15d
    dec     r14d
    cmp     r15d, 20
    jb      .run
    BUMP    C_BBAD
.runend:
    cmp     r13d, 97
    jl      .out
    mov     r14d, 73
.up:
    cmp     r14d, r13d
    jg      .out
    mov     edi, ebx
    mov     esi, r14d
    mov     edx, r12d
    mov     ecx, r13d
    call    .carved
    test    eax, eax
    jz      .upnext
    mov     edi, ebx
    mov     esi, r12d
    call    gen_cave_flags
    test    eax, CF_MOUTH
    jnz     .upnext
    BUMP    C_ABAD
.upnext:
    cmp     r14d, r13d
    je      .out
    lea     eax, [r14 + 8]
    cmp     eax, r13d
    jle     .setup
    mov     eax, r13d                   ; the last step lands on the surface
.setup:
    mov     r14d, eax
    jmp     .up
.out:
    add     rsp, 8
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret
; .carved(edi ax, esi y, edx az, ecx h) -> eax: gen_carved when ebp is set, else carved_at
.carved:
    test    ebp, ebp
    jz      .point
    jmp     gen_carved                  ; (edi ax, esi y, edx az); the tail call returns to the caller
.point:
    jmp     carved_at

; analyse_column(rdi GENBUF*)
; Every cell of a generated column goes through scan_cell_blocks and scan_cell_carve.
analyse_column:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] lz [4] lx
    mov     rbx, rdi
    mov     dword [rsp], 0
.lz:
    mov     dword [rsp + 4], 0
.lx:
    mov     eax, [rbx + GENBUF.cx]
    shl     eax, 4
    add     eax, [rsp + 4]
    mov     r12d, eax                   ; ax
    mov     eax, [rbx + GENBUF.cz]
    shl     eax, 4
    add     eax, [rsp]
    mov     r13d, eax                   ; az
    mov     edi, r12d
    mov     esi, r13d
    call    gen_height
    mov     r14d, eax                   ; h
    mov     eax, [rsp]
    shl     eax, 4
    add     eax, [rsp + 4]
    lea     rdi, [rbx + GENBUF.blocks]
    add     rdi, rax
    mov     esi, r14d
    mov     edx, [rsp + 4]
    mov     ecx, [rsp]
    call    scan_cell_blocks
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, [rsp + 4]
    or      ecx, [rsp]
    and     ecx, 3
    sete    cl                          ; the cells whose lx and lz are multiples of 4 go through gen_carved
    movzx   ecx, cl
    call    scan_cell_carve
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], 16
    jb      .lx
    inc     dword [rsp]
    cmp     dword [rsp], 16
    jb      .lz
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mouth_column(rdi GENBUF*) -> eax 1 when the generated column holds a cell whose gen_cave_flags has
; CF_MOUTH and no site or road touched it (no chest, no road cell), so its blocks are the caves' alone
mouth_column:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     rbx, rdi
    xor     eax, eax
    cmp     dword [rbx + GENBUF.nchests], 0
    jne     .out
    lea     rsi, [road_mask]
    mov     ecx, 22 * 22
.road:
    cmp     byte [rsi + rcx - 1], 2
    je      .out
    dec     ecx
    jnz     .road
    xor     r12d, r12d                  ; lz
.lz:
    xor     r13d, r13d                  ; lx
.lx:
    mov     eax, [rbx + GENBUF.cx]
    shl     eax, 4
    add     eax, r13d
    mov     edi, eax
    mov     eax, [rbx + GENBUF.cz]
    shl     eax, 4
    add     eax, r12d
    mov     esi, eax
    call    gen_cave_flags
    test    eax, CF_MOUTH
    jnz     .found
    inc     r13d
    cmp     r13d, 16
    jb      .lx
    inc     r12d
    cmp     r12d, 16
    jb      .lz
    xor     eax, eax
    jmp     .out
.found:
    mov     eax, 1
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; check_mouth_column(rdi GENBUF*)
; (f) gen_carved of every cell y 5 .. h of the generated column equals "the block is AIR": the carving is
; what the point query says, mouth cells included; floors of gravel and moss and pool cells are not carved.
; Counts the disagreements in C_FBAD.
check_mouth_column:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] lz [4] lx
    mov     rbx, rdi
    mov     dword [rsp], 0
.lz:
    mov     dword [rsp + 4], 0
.lx:
    mov     eax, [rbx + GENBUF.cx]
    shl     eax, 4
    add     eax, [rsp + 4]
    mov     r12d, eax                   ; ax
    mov     eax, [rbx + GENBUF.cz]
    shl     eax, 4
    add     eax, [rsp]
    mov     r13d, eax                   ; az
    mov     edi, r12d
    mov     esi, r13d
    call    gen_height
    mov     r14d, eax                   ; h
    mov     r15d, 5                     ; y
.y:
    cmp     r15d, r14d
    jg      .nextcell
    mov     edi, r12d
    mov     esi, r15d
    mov     edx, r13d
    call    gen_carved
    mov     ecx, eax
    mov     eax, [rsp]
    shl     eax, 4
    add     eax, [rsp + 4]
    mov     edx, r15d
    shl     edx, 8
    add     eax, edx
    xor     edx, edx
    cmp     byte [rbx + GENBUF.blocks + rax], AIR
    sete    dl
    cmp     ecx, edx
    je      .same
    BUMP    C_FBAD
.same:
    inc     r15d
    jmp     .y
.nextcell:
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], 16
    jb      .lx
    inc     dword [rsp]
    cmp     dword [rsp], 16
    jb      .lz
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; bare_column(rdi GENBUF* buf, esi cx, edx cz)
; A column of the underground alone: bedrock at y 0 and STONE up to the terrain height gen_height gives for
; every cell, a terrain cell table that holds those heights for the column and its 3 cell margin, and
; gen_underground on it. No tree, site or road touches it.
bare_column:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] lz [4] lx
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    lea     rdi, [rbx + GENBUF.blocks]
    mov     ecx, 65536 / 8
    xor     eax, eax
    rep     stosq
    mov     [rbx + GENBUF.cx], r12d
    mov     [rbx + GENBUF.cz], r13d
    lea     rdi, [tctab]
    mov     ecx, (TC_CELLS * TCELL_size) / 8
    xor     eax, eax
    rep     stosq
    mov     dword [rsp], -3
.tz:
    mov     dword [rsp + 4], -3
.tx:
    mov     eax, r12d
    shl     eax, 4
    add     eax, [rsp + 4]
    mov     edi, eax
    mov     eax, r13d
    shl     eax, 4
    add     eax, [rsp]
    mov     esi, eax
    call    gen_height
    mov     ecx, [rsp]
    add     ecx, 3
    imul    ecx, ecx, TC_W
    mov     edx, [rsp + 4]
    add     edx, 3
    add     ecx, edx
    imul    ecx, ecx, TCELL_size
    lea     rdx, [tctab]
    mov     [rdx + rcx + TCELL.h], eax
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], 18
    jle     .tx
    inc     dword [rsp]
    cmp     dword [rsp], 18
    jle     .tz
    mov     dword [rsp], 0
.fz:
    mov     dword [rsp + 4], 0
.fx:
    mov     ecx, [rsp]
    add     ecx, 3
    imul    ecx, ecx, TC_W
    mov     edx, [rsp + 4]
    add     edx, 3
    add     ecx, edx
    imul    ecx, ecx, TCELL_size
    lea     rdx, [tctab]
    mov     r14d, [rdx + rcx + TCELL.h]
    mov     eax, [rsp]
    shl     eax, 4
    add     eax, [rsp + 4]
    lea     rdi, [rbx + GENBUF.blocks]
    add     rdi, rax
    mov     byte [rdi], BEDROCK
    mov     ecx, r14d                   ; STONE at y 1 .. h
    mov     eax, 256
.stone:
    add     rdi, rax
    mov     byte [rdi], STONE
    dec     ecx
    jnz     .stone
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], 16
    jb      .fx
    inc     dword [rsp]
    cmp     dword [rsp], 16
    jb      .fz
    mov     rdi, rbx
    lea     rsi, [tctab]
    mov     edx, r12d
    shl     edx, 4
    mov     ecx, r13d
    shl     ecx, 4
    call    gen_underground
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; bare_block(edi wx, esi y, edx wz) -> eax: the block of the BW x BW bare columns, a window of BW * 16 cells a
; side (column BW * (wz / 16) + wx / 16 of bbuf), or STONE outside it (so it never reads as AIR)
bare_block:
    mov     eax, STONE
    cmp     edi, BW * 16 - 1
    ja      .out
    cmp     edx, BW * 16 - 1
    ja      .out
    mov     ecx, edx
    shr     ecx, 4
    imul    ecx, ecx, BW
    mov     r8d, edi
    shr     r8d, 4
    add     ecx, r8d
    imul    ecx, ecx, GENBUF_size
    lea     r8, [bbuf]
    add     r8, rcx
    and     edi, 15
    and     edx, 15
    shl     esi, 8
    shl     edx, 4
    or      esi, edx
    or      esi, edi
    movzx   eax, byte [r8 + rsi + GENBUF.blocks]
.out:
    ret

; bare_verify(esi cx, edx cz) -> eax violations
; Builds the BW x BW bare columns (cx + i, cz + j) and checks, for every cell y 5 .. h: every liquid cell has
; AIR above it, a cell that is not AIR below it, LAVA only at y <= 30 and WATER only above, and no AIR cell
; beside it in the window, across the borders of the columns as well; and, in the cells whose lx and lz are
; multiples of 3, carved_at equals "the block is AIR" (the lattice pass and the point query agree to the bit).
bare_verify:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56                     ; [0] lz [4] lx [8] col [12] h [16] y [20] violations [24] ax [28] az
                                        ; [32] wx [36] wz [40] 1 when the carving is compared in this cell
    mov     r12d, esi
    mov     r13d, edx
    xor     r14d, r14d                  ; the column to build, BW * row + column
.build:
    mov     eax, r14d
    imul    eax, eax, GENBUF_size
    lea     rdi, [bbuf]
    add     rdi, rax
    mov     eax, r14d
    and     eax, BW - 1
    add     eax, r12d
    mov     esi, eax
    mov     eax, r14d
    shr     eax, 2
    add     eax, r13d
    mov     edx, eax
    call    bare_column
    inc     r14d
    cmp     r14d, BW * BW
    jb      .build
    mov     dword [rsp + 20], 0
    mov     dword [rsp + 8], 0
.col:
    mov     dword [rsp], 0
.lz:
    mov     dword [rsp + 4], 0
.lx:
    mov     eax, [rsp + 8]
    and     eax, BW - 1                 ; the column's place in the window: x
    mov     ecx, [rsp + 8]
    shr     ecx, 2                      ; and z
    mov     edx, eax
    shl     edx, 4
    add     edx, [rsp + 4]
    mov     [rsp + 32], edx             ; wx
    mov     edx, ecx
    shl     edx, 4
    add     edx, [rsp]
    mov     [rsp + 36], edx             ; wz
    add     eax, r12d
    shl     eax, 4
    add     eax, [rsp + 4]
    mov     [rsp + 24], eax             ; ax
    add     ecx, r13d
    shl     ecx, 4
    add     ecx, [rsp]
    mov     [rsp + 28], ecx             ; az
    mov     eax, [rsp + 4]              ; compare the carving where lx and lz are multiples of 3
    xor     edx, edx
    mov     ecx, 3
    div     ecx
    mov     ebx, edx
    mov     eax, [rsp]
    xor     edx, edx
    div     ecx
    or      ebx, edx
    xor     eax, eax
    test    ebx, ebx
    setz    al
    mov     [rsp + 40], eax
    mov     edi, [rsp + 24]
    mov     esi, [rsp + 28]
    call    gen_height
    mov     [rsp + 12], eax
    mov     dword [rsp + 16], 5
.y:
    mov     eax, [rsp + 16]
    cmp     eax, [rsp + 12]
    jg      .nextcell
    mov     edi, [rsp + 32]
    mov     esi, eax
    mov     edx, [rsp + 36]
    call    bare_block
    mov     r14d, eax                   ; the block
    cmp     dword [rsp + 40], 0
    je      .agree
    mov     edi, [rsp + 24]
    mov     esi, [rsp + 16]
    mov     edx, [rsp + 28]
    mov     ecx, [rsp + 12]
    call    carved_at
    mov     ebx, eax                    ; carved
    xor     edx, edx
    test    r14d, r14d
    sete    dl
    cmp     ebx, edx
    je      .agree
    inc     dword [rsp + 20]            ; carved_at and the block disagree
.agree:
    cmp     r14d, LAVA
    je      .liquid
    cmp     r14d, WATER
    jne     .next
.liquid:
    mov     eax, [rsp + 16]             ; level rules
    mov     ecx, [rsp + 12]
    sub     ecx, 8
    cmp     eax, 6
    jl      .badpool
    cmp     eax, ecx
    jg      .badpool
    cmp     eax, 80
    jg      .badpool
    cmp     r14d, LAVA
    sete    dl
    cmp     eax, 30
    setle   cl
    cmp     dl, cl
    jne     .badpool                    ; LAVA exactly where y <= 30
    mov     edi, [rsp + 32]             ; the cell above is AIR, the cell below is not
    mov     esi, [rsp + 16]
    inc     esi
    mov     edx, [rsp + 36]
    call    bare_block
    test    eax, eax
    jnz     .badpool
    mov     edi, [rsp + 32]
    mov     esi, [rsp + 16]
    dec     esi
    mov     edx, [rsp + 36]
    call    bare_block
    test    eax, eax
    jz      .badpool
    xor     r15d, r15d                  ; the four neighbours, in the window or outside it
.nb:
    mov     edi, [rsp + 32]
    mov     edx, [rsp + 36]
    cmp     r15d, 2
    jae     .dz
    lea     edi, [rdi + r15*2 - 1]      ; wx -1 / +1
    jmp     .look
.dz:
    lea     edx, [rdx + r15*2 - 5]      ; wz -1 / +1
.look:
    mov     esi, [rsp + 16]
    call    bare_block
    test    eax, eax
    jnz     .nbnext
    inc     dword [rsp + 20]            ; AIR beside a liquid cell
.nbnext:
    inc     r15d
    cmp     r15d, 4
    jb      .nb
    jmp     .next
.badpool:
    inc     dword [rsp + 20]
.next:
    inc     dword [rsp + 16]
    jmp     .y
.nextcell:
    inc     dword [rsp + 4]
    cmp     dword [rsp + 4], 16
    jb      .lx
    inc     dword [rsp]
    cmp     dword [rsp], 16
    jb      .lz
    inc     dword [rsp + 8]
    cmp     dword [rsp + 8], BW * BW
    jb      .col
    mov     eax, [rsp + 20]
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; seed 42, 20 x 20 columns from the spawn column. (a) nothing is carved above y 72 outside a tunnel mouth,
; (b) no surface run of carved cells is 20 deep, (c) the underground of land is 3.5 .. 6.5 % AIR, (d) liquid
; cells have a bed, LAVA lies at y <= 30 and WATER at 31 .. 80, and none has AIR beside it, (e) the window
; holds lava, water, ore with AIR beside it (and the ore is 1.8 % or more of the exposed stone and ore),
; gravel and moss floors, (f) in the first mouth column that no site or road touched gen_carved is what the
; generated blocks say (AIR is carved; the floors of gravel and moss and the pools sunk into floors are not),
; (g) six columns generate again the same, and the closing check builds two 4 x 4 windows of bare columns,
; one at the mouth column and one at the spawn column, to compare the lattice pass with the point query and
; to test the pool rules across the column borders.
test_caves_reworked:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40                     ; [0] first cx [4] first cz [8] hash (0,0) [12] hash (-3,5)
    call    world_clear
    mov     edi, 42
    call    worldgen_set_seed
    lea     rdi, [cnt]
    xor     eax, eax
    mov     ecx, 24
    rep     stosd
    lea     rdi, [spawn]
    call    gen_find_spawn
    mov     eax, [spawn]
    sar     eax, 4
    mov     [rsp], eax
    mov     eax, [spawn + 8]
    sar     eax, 4
    mov     [rsp + 4], eax
    xor     r12d, r12d                  ; dz
.dz:
    xor     r13d, r13d                  ; dx
.dx:
    mov     edi, [rsp]
    add     edi, r13d
    mov     esi, [rsp + 4]
    add     esi, r12d
    call    gen_into
    mov     rdi, rax
    call    analyse_column
    cmp     dword [cnt + C_MOUTH * 4], 0
    jne     .next
    lea     rdi, [cbuf]
    call    mouth_column
    test    eax, eax
    jz      .next
    mov     dword [cnt + C_MOUTH * 4], 1
    mov     eax, [rsp]
    add     eax, r13d
    mov     [cnt + C_MCX * 4], eax
    mov     eax, [rsp + 4]
    add     eax, r12d
    mov     [cnt + C_MCZ * 4], eax
    lea     rdi, [cbuf]
    call    check_mouth_column
.next:
    inc     r13d
    cmp     r13d, WIN
    jb      .dx
    inc     r12d
    cmp     r12d, WIN
    jb      .dz
    cmp     dword [cnt + C_MOUTH * 4], 0
    jne     .verdicts
    xor     r12d, r12d                  ; no mouth column in the window: look on, row by row below it
.more:
    mov     edi, [rsp]
    mov     eax, r12d
    xor     edx, edx
    mov     ecx, WIN
    div     ecx
    add     edi, edx                    ; cx
    mov     esi, [rsp + 4]
    add     esi, WIN
    add     esi, eax                    ; cz
    mov     r13d, edi
    mov     r14d, esi
    call    gen_into
    lea     rdi, [cbuf]
    call    mouth_column
    test    eax, eax
    jz      .morenext
    mov     dword [cnt + C_MOUTH * 4], 1
    mov     [cnt + C_MCX * 4], r13d
    mov     [cnt + C_MCZ * 4], r14d
    lea     rdi, [cbuf]
    call    check_mouth_column
    jmp     .verdicts
.morenext:
    inc     r12d
    cmp     r12d, EXTRA
    jb      .more
.verdicts:
    cmp     dword [cnt + C_ABAD * 4], 0
    jne     .fail                       ; (a)
    cmp     dword [cnt + C_BBAD * 4], 0
    jne     .fail                       ; (b)
    mov     eax, [cnt + C_AIR * 4]      ; (c) 3.5 % <= air / under <= 6.5 %
    imul    rax, rax, 200
    mov     ecx, [cnt + C_UNDER * 4]
    imul    rdx, rcx, 7
    cmp     rax, rdx
    jb      .fail
    imul    rdx, rcx, 13
    cmp     rax, rdx
    ja      .fail
    cmp     dword [cnt + C_PBAD * 4], 0
    jne     .fail                       ; (d)
    mov     eax, [cnt + C_POOL * 4]
    test    eax, eax
    jz      .fail
    mov     ecx, [cnt + C_FACE * 4]
    imul    ecx, ecx, 20
    cmp     ecx, eax
    jae     .fail                       ; fewer than 5 % of the pool cells with AIR beside them
    cmp     dword [cnt + C_LAVA * 4], 1 ; (e)
    jb      .fail
    cmp     dword [cnt + C_WATER * 4], 1
    jb      .fail
    cmp     dword [cnt + C_EXORE * 4], 10
    jb      .fail
    cmp     dword [cnt + C_GRAVEL * 4], 1
    jb      .fail
    cmp     dword [cnt + C_MOSS * 4], 1
    jb      .fail
    mov     eax, [cnt + C_XORE * 4]     ; (e) the dressing: ore is 1.8 % or more of the exposed stone and ore
    mov     ecx, [cnt + C_XSTONE * 4]
    add     ecx, eax
    imul    rax, rax, 1000
    imul    rcx, rcx, 18
    cmp     rax, rcx
    jb      .fail
    cmp     dword [cnt + C_MOUTH * 4], 0
    je      .fail                       ; (f) a mouth column was found, and its carving matches
    cmp     dword [cnt + C_FBAD * 4], 0
    jne     .fail
    lea     rdi, [gcols]                ; (g) (0, 0), (-3, 5), the spawn column, two more of the window and the
    mov     dword [rdi], 0              ; mouth column: hashed once, then generated again in another order
    mov     dword [rdi + 4], 0
    mov     dword [rdi + 8], -3
    mov     dword [rdi + 12], 5
    mov     eax, [rsp]
    mov     ecx, [rsp + 4]
    mov     [rdi + 16], eax
    mov     [rdi + 20], ecx
    lea     edx, [rax + 7]
    mov     [rdi + 24], edx
    lea     edx, [rcx + 3]
    mov     [rdi + 28], edx
    mov     edx, [cnt + C_MCX * 4]
    mov     [rdi + 32], edx
    mov     edx, [cnt + C_MCZ * 4]
    mov     [rdi + 36], edx
    lea     edx, [rax + 19]
    mov     [rdi + 40], edx
    lea     edx, [rcx + 19]
    mov     [rdi + 44], edx
    xor     r12d, r12d
.g1:
    lea     rax, [gcols]
    mov     edi, [rax + r12*8]
    mov     esi, [rax + r12*8 + 4]
    call    gen_into
    mov     rdi, rax
    call    hash_col
    lea     rcx, [ghash]
    mov     [rcx + r12*4], eax
    inc     r12d
    cmp     r12d, 6
    jb      .g1
    lea     rcx, [ghash]
    mov     eax, [rcx]
    cmp     eax, [rcx + 4]
    je      .fail                       ; (0, 0) and (-3, 5) must differ
    xor     r12d, r12d
.g2:
    lea     rax, [gorder]
    movzx   r13d, byte [rax + r12]
    lea     rax, [gcols]
    mov     edi, [rax + r13*8]
    mov     esi, [rax + r13*8 + 4]
    call    gen_into
    mov     rdi, rax
    call    hash_col
    lea     rcx, [ghash]
    cmp     eax, [rcx + r13*4]
    jne     .fail
    inc     r12d
    cmp     r12d, 6
    jb      .g2
    mov     esi, [cnt + C_MCX * 4]      ; the bare columns: a 2 x 2 window at the mouth column, another at the spawn
    mov     edx, [cnt + C_MCZ * 4]
    call    bare_verify
    test    eax, eax
    jnz     .fail
    mov     esi, [rsp]
    mov     edx, [rsp + 4]
    call    bare_verify
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
