; test_worldgen.asm - terrain generator tests (gen_column and the pure gen_* functions).
%include "common.inc"
default rel

global test_worldgen_deterministic, test_worldgen_shape, test_worldgen_ores
global test_worldgen_biomes, test_worldgen_column_independence
global test_worldgen_spawn, test_worldgen_water_ice, test_biome_ladder

extern world_clear, fnv1a
extern worldgen_set_seed, gen_column, gen_height, gen_biome, gen_surface, gen_find_spawn, veg_kind

%define BIOME_TOTAL 148225              ; 385 x 385 samples of the 16 block grid over |x|, |z| <= 3072
%define GB_SCRATCH  8                   ; generator buffers below
%define WI_STRIDE   700                 ; water_ice looks at every 700th ocean or river centre
; every land biome with a stable share: all but the rivers and the stony shore, which only have to occur
%define SHARE_BIOMES ((1 << BIOME_PLAINS) | (1 << BIOME_FOREST) | (1 << BIOME_DESERT) | (1 << BIOME_SNOW) | \
                      (1 << BIOME_SWAMP) | (1 << BIOME_MOUNTAINS) | (1 << BIOME_TAIGA) | (1 << BIOME_SAVANNA) | \
                      (1 << BIOME_BIRCH))
%define LAD_N       257                 ; biome_ladder's window: |x|, |z| <= 512 at 4 blocks, 257 samples a side
%define SG_N        385                 ; and its grid: the 385 x 385 samples of BIOME_TOTAL
; what biome_ladder knows of a grid sample (sg_cls bits)
%define SC_DESERT   1                   ; the biome is a desert
%define SC_SAVANNA  2
%define SC_COLD     4                   ; snow or taiga
%define SC_SNOWY    8                   ; SNOW_LAYER cover or a SNOW_BLOCK top
%define SC_QB       16                  ; plains, birch forest or forest with a DRY_GRASS top
%define SC_QC       32                  ; plains, birch forest or forest with SNOW_LAYER cover
%define SC_QD       64                  ; savanna with a SAND top above the beach (h > 98)
%define SC_TEMP     128                 ; plains, birch forest or forest

section .bss
alignb 64
gbufs:     resb GB_SCRATCH * GENBUF_size
alignb 16
biome_n:   resd NUM_BIOMES
ore_count: resd NUM_BLOCKS
ore_miny:  resd NUM_BLOCKS
ore_maxy:  resd NUM_BLOCKS
spawn_a:   resd 4
spawn_b:   resd 4
wi_ice:    resd 1
wi_water:  resd 1
lad_win:   resb LAD_N * LAD_N          ; gen_biome over the window, row z, column x
sg_bio:    resb SG_N * SG_N            ; gen_biome of the grid
sg_cls:    resb SG_N * SG_N            ; SC_* bits of the grid, row z, column x
alignb 4
lad_forbid: resd NUM_BIOMES            ; per biome the mask of the biomes that may not touch it

section .text

; gen_into(edi idx, esi cx, edx cz) -> rax GENBUF*
; Fills generator buffer idx with 0xA5 (so a byte gen_column forgets to write stays visible), then
; generates column (cx, cz) into it with the current seed.
gen_into:
    push    rbx
    push    r12
    push    r13
    mov     r12d, esi
    mov     r13d, edx
    imul    eax, edi, GENBUF_size
    lea     rbx, [gbufs]
    add     rbx, rax
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

test_worldgen_deterministic:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    call    world_clear
    mov     edi, 42
    call    worldgen_set_seed
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    gen_into
    mov     rdi, rax
    call    hash_col
    mov     ebx, eax                    ; (0, 0), seed 42
    xor     edi, edi
    mov     esi, -3
    mov     edx, 5
    call    gen_into
    mov     rdi, rax
    call    hash_col
    mov     r12d, eax                   ; (-3, 5), seed 42
    cmp     ebx, r12d
    je      .fail                       ; two columns must differ
    mov     edi, 1                      ; another column in between, then (0, 0) again into a dirty buffer
    mov     esi, 9
    mov     edx, 9
    call    gen_into
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    gen_into
    mov     rdi, rax
    call    hash_col
    cmp     eax, ebx
    jne     .fail
    mov     edi, 43
    call    worldgen_set_seed
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    gen_into
    mov     rdi, rax
    call    hash_col
    cmp     eax, ebx
    je      .fail                       ; another seed gives another column
    xor     edi, edi
    mov     esi, -3
    mov     edx, 5
    call    gen_into
    mov     rdi, rax
    call    hash_col
    cmp     eax, r12d
    je      .fail
    mov     edi, 42
    call    worldgen_set_seed
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; over 4 x 4 columns: bedrock floor, only known block ids, water at or below sea level, a plausible top
test_worldgen_shape:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    call    world_clear
    mov     edi, 42
    call    worldgen_set_seed
    mov     r12d, -2                    ; cz
.cz:
    mov     r13d, -2                    ; cx
.cx:
    xor     edi, edi
    mov     esi, r13d
    mov     edx, r12d
    call    gen_into
    mov     rbx, rax
    lea     rsi, [rbx + GENBUF.blocks]
    mov     ecx, 256
.bed:
    cmp     byte [rsi + rcx - 1], BEDROCK ; y = 0 is the first 256 bytes
    jne     .fail
    dec     ecx
    jnz     .bed
    xor     r14d, r14d                  ; y
    mov     r15d, -1
.row:
    mov     rsi, r14
    shl     rsi, 8
    lea     rsi, [rbx + GENBUF.blocks + rsi]
    mov     ecx, 256
.cell:
    movzx   eax, byte [rsi + rcx - 1]
    cmp     eax, NUM_BLOCKS
    jae     .fail
    test    eax, eax
    jz      .next
    mov     r15d, r14d                  ; y only grows, so the last write is the highest row
    cmp     eax, WATER
    jne     .next
    cmp     r14d, SEA_LEVEL
    ja      .fail
.next:
    dec     ecx
    jnz     .cell
    inc     r14d
    cmp     r14d, 256
    jb      .row
    cmp     r15d, [rbx + GENBUF.top]    ; the stored top is the highest row holding a block
    jne     .fail
    mov     eax, r15d
    cmp     eax, 8
    jl      .fail
    cmp     eax, 240
    jg      .fail
    lea     rsi, [rbx + GENBUF.biome]
    xor     ecx, ecx
.bio:
    cmp     byte [rsi + rcx], NUM_BIOMES
    jae     .fail
    inc     ecx
    cmp     ecx, 256
    jb      .bio
    cmp     dword [rbx + GENBUF.nconts], 0
    jne     .fail
    inc     r13d
    cmp     r13d, 1
    jle     .cx
    inc     r12d
    cmp     r12d, 1
    jle     .cz
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

section .rodata
; floors: id, minimum count
ore_floors:
    dd COAL_ORE, 200
    dd IRON_ORE, 100
    dd GOLD_ORE, 10
    dd DIAMOND_ORE, 2
ore_floors_end:
; y ranges: id, lowest allowed y, highest allowed y
ore_ranges:
    dd COAL_ORE, 40, 130
    dd IRON_ORE, 15, 80
    dd GOLD_ORE, 5, 40
    dd DIAMOND_ORE, 2, 18
ore_ranges_end:

section .text
; 8 x 8 columns from the spawn column: enough of each ore, each inside its y range
test_worldgen_ores:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] first cx [4] first cz (24 keeps rsp 16-aligned)
    call    world_clear
    mov     edi, 42
    call    worldgen_set_seed
    lea     rdi, [spawn_a]
    call    gen_find_spawn
    mov     eax, [spawn_a]
    sar     eax, 4
    mov     [rsp], eax
    mov     eax, [spawn_a + 8]
    sar     eax, 4
    mov     [rsp + 4], eax
    lea     rdi, [ore_count]
    xor     eax, eax
    mov     ecx, NUM_BLOCKS
    rep     stosd
    lea     rdi, [ore_maxy]
    mov     ecx, NUM_BLOCKS
    rep     stosd
    lea     rdi, [ore_miny]
    mov     eax, 0xFFFF
    mov     ecx, NUM_BLOCKS
    rep     stosd
    xor     r12d, r12d                  ; dz
.dz:
    xor     r13d, r13d                  ; dx
.dx:
    xor     edi, edi
    mov     esi, [rsp]
    add     esi, r13d
    mov     edx, [rsp + 4]
    add     edx, r12d
    call    gen_into
    lea     rsi, [rax + GENBUF.blocks]
    lea     r8, [ore_count]
    lea     r9, [ore_miny]
    lea     r10, [ore_maxy]
    xor     r11d, r11d                  ; y
.y:
    mov     ecx, 256
.c:
    movzx   eax, byte [rsi]
    inc     dword [r8 + rax*4]
    cmp     r11d, [r9 + rax*4]
    jge     .nomin
    mov     [r9 + rax*4], r11d
.nomin:
    cmp     r11d, [r10 + rax*4]
    jle     .nomax
    mov     [r10 + rax*4], r11d
.nomax:
    inc     rsi
    dec     ecx
    jnz     .c
    inc     r11d
    cmp     r11d, 256
    jb      .y
    inc     r13d
    cmp     r13d, 8
    jb      .dx
    inc     r12d
    cmp     r12d, 8
    jb      .dz
    lea     rbx, [ore_floors]
.floor:
    mov     eax, [rbx]
    lea     rcx, [ore_count]
    mov     eax, [rcx + rax*4]
    cmp     eax, [rbx + 4]
    jb      .fail
    add     rbx, 8
    lea     rax, [ore_floors_end]
    cmp     rbx, rax
    jb      .floor
    lea     rbx, [ore_ranges]
.range:
    mov     eax, [rbx]
    lea     rcx, [ore_miny]
    mov     edx, [rcx + rax*4]
    cmp     edx, [rbx + 4]
    jl      .fail
    lea     rcx, [ore_maxy]
    mov     edx, [rcx + rax*4]
    cmp     edx, [rbx + 8]
    jg      .fail
    add     rbx, 12
    lea     rax, [ore_ranges_end]
    cmp     rbx, rax
    jb      .range
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; seed 42, gen_biome on the 16 block grid over |x|, |z| <= 3072: every biome occurs (rivers and the stony shore
; included), the ocean covers 10..45 %, and plains, forest, desert, snow, swamp, mountains, taiga, savanna and
; birch forest take at least 2 % each
test_worldgen_biomes:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    mov     edi, 42
    call    worldgen_set_seed
    lea     rdi, [biome_n]
    xor     eax, eax
    mov     ecx, NUM_BIOMES
    rep     stosd
    mov     r12d, -3072                 ; z
.z:
    mov     ebx, -3072                  ; x
.x:
    mov     edi, ebx
    mov     esi, r12d
    call    gen_biome
    lea     rcx, [biome_n]
    inc     dword [rcx + rax*4]
    add     ebx, 16
    cmp     ebx, 3072
    jle     .x
    add     r12d, 16
    cmp     r12d, 3072
    jle     .z
    lea     rsi, [biome_n]
    xor     ecx, ecx
.all:
    cmp     dword [rsi + rcx*4], 0
    je      .fail
    inc     ecx
    cmp     ecx, NUM_BIOMES
    jb      .all
    mov     eax, [rsi + BIOME_OCEAN*4]
    imul    rax, rax, 100
    cmp     rax, BIOME_TOTAL * 10
    jb      .fail
    cmp     rax, BIOME_TOTAL * 45
    ja      .fail
    mov     ecx, BIOME_PLAINS
.land:
    mov     eax, SHARE_BIOMES
    bt      eax, ecx
    jnc     .skip
    mov     eax, [rsi + rcx*4]
    imul    rax, rax, 100
    cmp     rax, BIOME_TOTAL * 2
    jb      .fail
.skip:
    inc     ecx
    cmp     ecx, NUM_BIOMES
    jb      .land
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; col_block(edi ax, esi y, edx az) -> eax: the block of the generated 3 x 3 neighbourhood of
; columns (0..1, -1..1) held in generator buffers 2..7 (index (cz + 1) * 2 + cx); AIR outside it
col_block:
    xor     eax, eax
    cmp     esi, 255
    ja      .out
    cmp     edi, 31
    ja      .out
    mov     ecx, edx
    sar     ecx, 4
    inc     ecx                         ; cz + 1
    cmp     ecx, 2
    ja      .out
    mov     eax, edi
    shr     eax, 4                      ; cx
    lea     ecx, [rax + rcx*2 + 2]      ; buffer index
    imul    ecx, ecx, GENBUF_size
    lea     r8, [gbufs]
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

; has_log(edi ax, esi y, edx az) -> eax 1 when a LOG, PINE_LOG or BIRCH_LOG lies within 3 cells
; horizontally and 6 vertically of the cell in the generated neighbourhood
has_log:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    push    rbp
    sub     rsp, 24                     ; [0] ax [4] y [8] az [12] dy [16] dz
    mov     [rsp], edi
    mov     [rsp + 4], esi
    mov     [rsp + 8], edx
    mov     dword [rsp + 12], -6
.dy:
    mov     dword [rsp + 16], -3
.dz:
    mov     r14d, -3                    ; dx
.dx:
    mov     edi, [rsp]
    add     edi, r14d
    mov     esi, [rsp + 4]
    add     esi, [rsp + 12]
    mov     edx, [rsp + 8]
    add     edx, [rsp + 16]
    call    col_block
    cmp     eax, LOG
    je      .yes
    cmp     eax, PINE_LOG
    je      .yes
    cmp     eax, BIRCH_LOG
    je      .yes
    inc     r14d
    cmp     r14d, 3
    jle     .dx
    inc     dword [rsp + 16]
    cmp     dword [rsp + 16], 3
    jle     .dz
    inc     dword [rsp + 12]
    cmp     dword [rsp + 12], 6
    jle     .dy
    xor     eax, eax
    jmp     .out
.yes:
    mov     eax, 1
.out:
    add     rsp, 24
    pop     rbp
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

section .rodata
; columns of the neighbourhood: cx, cz in the order of the buffers 2..7
nb_cols:
    dd 0, -1,  1, -1
    dd 0,  0,  1,  0
    dd 0,  1,  1,  1
other_cols:
    dd 1, 0,  -1, 0,  0, 1,  0, -1,  5, 5,  -7, 3,  12, -9,  100, 100,  -50, 20,  3, 3
log_ids:
    dd LOG, PINE_LOG, BIRCH_LOG
log_ids_end:

section .text
; border_side(rdi from, esi lx_from, rdx to, ecx lx_to) -> eax trunks found, or -1
; For every trunk standing at column lx_from of the generated column `from`, the cell beside its top in
; column `to` (at lx_to, same y and z) must not be AIR: the canopy of a tree reaches across the border,
; so the neighbouring column has to hold its leaves.
border_side:
    push    rbx
    xor     r11d, r11d                  ; trunks
    xor     r8d, r8d                    ; lz
.lz:
    lea     r9, [log_ids]
.sp:
    mov     r10d, 255                   ; y, downwards: the first hit is the trunk top
.y:
    mov     eax, r10d
    shl     eax, 8
    mov     ebx, r8d
    shl     ebx, 4
    or      eax, ebx
    or      eax, esi
    movzx   ebx, byte [rdi + GENBUF.blocks + rax]
    cmp     ebx, [r9]
    je      .found
    dec     r10d
    jns     .y
    jmp     .nextsp
.found:
    inc     r11d
    mov     eax, r10d
    shl     eax, 8
    mov     ebx, r8d
    shl     ebx, 4
    or      eax, ebx
    or      eax, ecx
    cmp     byte [rdx + GENBUF.blocks + rax], AIR
    je      .bad
.nextsp:
    add     r9, 4
    lea     rax, [log_ids_end]
    cmp     r9, rax
    jb      .sp
    inc     r8d
    cmp     r8d, 16
    jb      .lz
    mov     eax, r11d
    pop     rbx
    ret
.bad:
    mov     eax, -1
    pop     rbx
    ret

; border_pass() -> eax 0 ok / 1 fail
; The column pairs (cx, cz) | (cx + 1, cz) for cz 0 and 1 and cx -6..8, both directions through
; border_side; at least one trunk must have been seen, or the check proved nothing.
border_pass:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    xor     r15d, r15d
    xor     r12d, r12d                  ; cz
.cz:
    mov     r13d, -6                    ; cx
.cx:
    xor     edi, edi
    mov     esi, r13d
    mov     edx, r12d
    call    gen_into
    mov     rbx, rax                    ; column (cx, cz)
    mov     edi, 1
    lea     esi, [r13 + 1]
    mov     edx, r12d
    call    gen_into
    mov     r14, rax                    ; column (cx + 1, cz)
    mov     rdi, rbx
    mov     esi, 15
    mov     rdx, r14
    xor     ecx, ecx
    call    border_side
    cmp     eax, -1
    je      .fail
    add     r15d, eax
    mov     rdi, r14
    xor     esi, esi
    mov     rdx, rbx
    mov     ecx, 15
    call    border_side
    cmp     eax, -1
    je      .fail
    add     r15d, eax
    inc     r13d
    cmp     r13d, 8
    jle     .cx
    inc     r12d
    cmp     r12d, 1
    jle     .cz
    xor     eax, eax
    test    r15d, r15d
    jnz     .out
.fail:
    mov     eax, 1
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; Seed 42. A column does not depend on what was generated before it (column (0, 0) hashes the same after
; ten other columns went into a dirty buffer), and the trees that cross the border between two columns come
; out the same on both sides: every leaf within 3 cells of the border of columns (0, 0) and (1, 0) has a
; trunk within 3 cells horizontally and 6 vertically in the 2 x 3 neighbourhood of columns (so no leaf floats
; where its trunk was clipped away), and the other way round every trunk standing at a border has a canopy
; cell next to its top in the neighbouring column (border_pass).
test_worldgen_column_independence:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8                      ; [0] leaves examined
    call    world_clear
    mov     edi, 42
    call    worldgen_set_seed
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    gen_into
    mov     rdi, rax
    call    hash_col
    mov     ebx, eax                    ; (0, 0) generated first
    lea     r12, [other_cols]
    mov     r13d, 10
.others:
    mov     edi, 1
    mov     esi, [r12]
    mov     edx, [r12 + 4]
    call    gen_into
    add     r12, 8
    dec     r13d
    jnz     .others
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    gen_into
    mov     rdi, rax
    call    hash_col
    cmp     eax, ebx
    jne     .fail
    ; the neighbourhood into buffers 2..7
    lea     r12, [nb_cols]
    mov     r13d, 2
.nb:
    mov     edi, r13d
    mov     esi, [r12]
    mov     edx, [r12 + 4]
    call    gen_into
    add     r12, 8
    inc     r13d
    cmp     r13d, 8
    jb      .nb
    mov     dword [rsp], 0
    mov     r13d, 0                     ; az
.az:
    mov     r12d, 13                    ; ax: 13..18, the 3 cells either side of the border at 16
.ax:
    xor     r14d, r14d                  ; y
.y:
    mov     edi, r12d
    mov     esi, r14d
    mov     edx, r13d
    call    col_block
    cmp     eax, LEAVES
    je      .leaf
    cmp     eax, PINE_LEAVES
    je      .leaf
    cmp     eax, BIRCH_LEAVES
    jne     .nexty
.leaf:
    inc     dword [rsp]
    mov     edi, r12d
    mov     esi, r14d
    mov     edx, r13d
    call    has_log
    test    eax, eax
    jz      .fail
.nexty:
    inc     r14d
    cmp     r14d, 255
    jbe     .y
    inc     r12d
    cmp     r12d, 18
    jle     .ax
    inc     r13d
    cmp     r13d, 15
    jle     .az
    cmp     dword [rsp], 0              ; the test must have looked at something
    je      .fail
    call    border_pass
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; col_ok(edi ax, esi az) -> eax 1 when the column is spawn material: a SPAWN_BIOMES biome and terrain >= 97
col_ok:
    push    rbx
    push    r12
    push    r13
    mov     ebx, edi
    mov     r12d, esi
    call    gen_biome
    mov     ecx, SPAWN_BIOMES
    bt      ecx, eax
    jnc     .no
    mov     edi, ebx
    mov     esi, r12d
    call    gen_height
    cmp     eax, 97
    jl      .no
    mov     eax, 1
    jmp     .out
.no:
    xor     eax, eax
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; check_spawn(edi seed) -> eax 0 ok / 1 fail
; The spawn is deterministic, on a column centre, in one of the SPAWN_BIOMES (so on land that is neither ocean,
; river, mountains nor stony shore), stands on the terrain surface, and no column that comes before it in the ring
; order qualifies.
check_spawn:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] i [4] j [8] k [12] jj [16] ii
    call    worldgen_set_seed
    lea     rdi, [spawn_a]
    call    gen_find_spawn
    lea     rdi, [spawn_b]
    call    gen_find_spawn
    mov     eax, [spawn_a]
    cmp     eax, [spawn_b]
    jne     .fail
    mov     eax, [spawn_a + 4]
    cmp     eax, [spawn_b + 4]
    jne     .fail
    mov     eax, [spawn_a + 8]
    cmp     eax, [spawn_b + 8]
    jne     .fail
    mov     ebx, [spawn_a]              ; x
    mov     r12d, [spawn_a + 8]         ; z
    lea     eax, [rbx - 8]
    test    eax, 15
    jnz     .fail
    lea     eax, [r12 - 8]
    test    eax, 15
    jnz     .fail
    mov     edi, ebx
    mov     esi, r12d
    call    gen_biome
    mov     ecx, SPAWN_BIOMES
    bt      ecx, eax
    jnc     .fail
    mov     edi, ebx
    mov     esi, r12d
    call    gen_height
    cmp     eax, 97
    jl      .fail
    inc     eax
    cmp     eax, [spawn_a + 4]
    jne     .fail
    lea     eax, [rbx - 8]
    sar     eax, 4
    mov     [rsp], eax                  ; i
    lea     eax, [r12 - 8]
    sar     eax, 4
    mov     [rsp + 4], eax              ; j
    mov     ecx, eax                    ; k = max(|i|, |j|)
    sar     ecx, 31
    xor     eax, ecx
    sub     eax, ecx
    mov     r13d, eax                   ; |j|
    mov     eax, [rsp]
    mov     ecx, eax
    sar     ecx, 31
    xor     eax, ecx
    sub     eax, ecx                    ; |i|
    cmp     eax, r13d
    cmovl   eax, r13d
    mov     [rsp + 8], eax              ; k
    mov     r14d, eax
    neg     r14d                        ; jj
.jj:
    mov     r15d, [rsp + 8]
    neg     r15d                        ; ii
.ii:
    ; m = max(|ii|, |jj|)
    mov     eax, r14d
    mov     ecx, eax
    sar     ecx, 31
    xor     eax, ecx
    sub     eax, ecx
    mov     r13d, eax
    mov     eax, r15d
    mov     ecx, eax
    sar     ecx, 31
    xor     eax, ecx
    sub     eax, ecx
    cmp     eax, r13d
    cmovl   eax, r13d                   ; m
    cmp     eax, [rsp + 8]
    jb      .before                     ; an inner ring: it comes first
    cmp     r14d, [rsp + 4]
    jl      .before                     ; this ring, an earlier row
    jg      .after
    cmp     r15d, [rsp]
    jl      .before
    jmp     .after
.before:
    mov     edi, r15d
    shl     edi, 4
    add     edi, 8
    mov     esi, r14d
    shl     esi, 4
    add     esi, 8
    call    col_ok
    test    eax, eax
    jnz     .fail                       ; a column before the spawn qualifies
.after:
    inc     r15d
    cmp     r15d, [rsp + 8]
    jle     .ii
    inc     r14d
    cmp     r14d, [rsp + 8]
    jle     .jj
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

test_worldgen_spawn:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    mov     edi, 42
    call    check_spawn
    test    eax, eax
    jnz     .out
    mov     edi, 7
    call    check_spawn
    test    eax, eax
    jnz     .out
    mov     edi, 42
    call    worldgen_set_seed
    xor     eax, eax
.out:
    pop     rbp
    ret

; check_wet(edi ci, esi cj) -> eax 0 ok / 1 fail; generates column (ci, cj), looks at its centre cell
; (8, 8): when the terrain is below sea level every cell above it up to y 95 is WATER and y 96 is WATER
; or ICE (counted); the cell above 96 is air or ice-free
check_wet:
    push    rbx
    push    r12
    push    r13
    push    r14
    sub     rsp, 8
    mov     r12d, edi
    mov     r13d, esi
    mov     eax, edi
    shl     eax, 4
    add     eax, 8
    mov     edi, eax
    mov     eax, r13d
    shl     eax, 4
    add     eax, 8
    mov     esi, eax
    call    gen_height
    mov     r14d, eax                   ; h
    xor     edi, edi
    mov     esi, r12d
    mov     edx, r13d
    call    gen_into
    mov     rbx, rax
    cmp     r14d, SEA_LEVEL
    jge     .ok
    lea     ecx, [r14 + 1]
.water:
    cmp     ecx, SEA_LEVEL
    jge     .top
    mov     eax, ecx
    shl     eax, 8
    cmp     byte [rbx + GENBUF.blocks + rax + 136], WATER
    jne     .fail
    inc     ecx
    jmp     .water
.top:
    movzx   eax, byte [rbx + GENBUF.blocks + SEA_LEVEL * 256 + 136]
    cmp     eax, WATER
    je      .is_water
    cmp     eax, ICE
    jne     .fail
    inc     dword [wi_ice]
    jmp     .ok
.is_water:
    inc     dword [wi_water]
.ok:
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 8
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; Seed 42. The first ocean column centre from the origin is water up to sea level. Of the ocean and river
; column centres of the 16 block grid within 3072 (rows from z = -3072, x ascending) every WI_STRIDE-th one,
; up to 64 columns, is generated; each one below sea level is water up to sea level, and some are ice-topped
; (cold columns) and some water-topped.
test_worldgen_water_ice:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] generated [4] seen
    call    world_clear
    mov     edi, 42
    call    worldgen_set_seed
    mov     dword [wi_ice], 0
    mov     dword [wi_water], 0
    xor     ebx, ebx                    ; ring k
.ring:
    mov     r12d, ebx
    neg     r12d                        ; j
.row:
    mov     r13d, ebx
    neg     r13d                        ; i
    mov     r14d, 1
    mov     eax, r12d
    mov     ecx, eax
    sar     ecx, 31
    xor     eax, ecx
    sub     eax, ecx
    cmp     eax, ebx
    jge     .cell
    lea     r14d, [rbx*2]
.cell:
    mov     edi, r13d
    shl     edi, 4
    add     edi, 8
    mov     esi, r12d
    shl     esi, 4
    add     esi, 8
    call    gen_biome
    cmp     eax, BIOME_OCEAN
    je      .first
    add     r13d, r14d
    cmp     r13d, ebx
    jle     .cell
    inc     r12d
    cmp     r12d, ebx
    jle     .row
    inc     ebx
    cmp     ebx, 256
    jle     .ring
    jmp     .fail                       ; no ocean at all
.first:
    mov     edi, r13d
    mov     esi, r12d
    call    check_wet
    test    eax, eax
    jnz     .fail
    mov     dword [wi_ice], 0
    mov     dword [wi_water], 0
    mov     dword [rsp], 0              ; columns generated
    mov     dword [rsp + 4], 0          ; ocean and river centres seen
    mov     r12d, -192                  ; j
.j:
    mov     r13d, -192                  ; i
.i:
    mov     edi, r13d
    shl     edi, 4
    add     edi, 8
    mov     esi, r12d
    shl     esi, 4
    add     esi, 8
    call    gen_biome
    cmp     eax, BIOME_OCEAN
    je      .take
    cmp     eax, BIOME_RIVER
    jne     .nexti
.take:
    mov     eax, [rsp + 4]
    inc     dword [rsp + 4]
    xor     edx, edx
    mov     ecx, WI_STRIDE
    div     ecx
    test    edx, edx
    jnz     .nexti                      ; only every WI_STRIDE-th centre is generated
    mov     edi, r13d
    mov     esi, r12d
    call    check_wet
    test    eax, eax
    jnz     .fail
    inc     dword [rsp]
    cmp     dword [rsp], 64
    jae     .done
.nexti:
    inc     r13d
    cmp     r13d, 191
    jle     .i
    inc     r12d
    cmp     r12d, 191
    jle     .j
.done:
    cmp     dword [rsp], 32             ; enough columns were looked at
    jb      .fail
    cmp     dword [wi_ice], 0
    je      .fail
    cmp     dword [wi_water], 0
    je      .fail
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---------------------------------------------------------------------------------------------
; biome_ladder

section .rodata
; pairs of biomes that must never touch, a and b: the far ends of the climate ladder
lad_pairs:
    dd BIOME_SNOW, BIOME_PLAINS
    dd BIOME_SNOW, BIOME_BIRCH
    dd BIOME_SNOW, BIOME_FOREST
    dd BIOME_SNOW, BIOME_SWAMP
    dd BIOME_SNOW, BIOME_SAVANNA
    dd BIOME_SNOW, BIOME_DESERT
    dd BIOME_TAIGA, BIOME_SWAMP
    dd BIOME_TAIGA, BIOME_SAVANNA
    dd BIOME_TAIGA, BIOME_DESERT
    dd BIOME_SWAMP, BIOME_SAVANNA
    dd BIOME_SWAMP, BIOME_DESERT
    dd BIOME_DESERT, BIOME_PLAINS
    dd BIOME_DESERT, BIOME_BIRCH
    dd BIOME_DESERT, BIOME_FOREST
lad_pairs_end:
; the SC_* role bits of a grid sample, by its biome id
sg_roles:
    db 0                                ; ocean
    db SC_TEMP                          ; plains
    db SC_TEMP                          ; forest
    db SC_DESERT
    db SC_COLD                          ; snow
    db 0                                ; swamp
    db 0                                ; mountains
    db 0                                ; river
    db SC_COLD                          ; taiga
    db SC_SAVANNA
    db 0                                ; stony shore
    db SC_TEMP                          ; birch forest
%if $ - sg_roles != NUM_BIOMES
%error "sg_roles needs one entry per biome"
%endif

section .text
; ladder_masks(): lad_forbid[a] = the mask of the biomes that may not touch a, built from lad_pairs both ways
ladder_masks:
    lea     rdi, [lad_forbid]
    xor     eax, eax
    mov     ecx, NUM_BIOMES
    rep     stosd
    lea     rdi, [lad_forbid]
    lea     rsi, [lad_pairs]
    lea     r8, [lad_pairs_end]
.pair:
    mov     eax, [rsi]                  ; a
    mov     ecx, [rsi + 4]              ; b
    mov     edx, 1
    shl     edx, cl
    or      [rdi + rax*4], edx          ; a may not touch b
    mov     r9d, ecx
    mov     ecx, eax
    mov     edx, 1
    shl     edx, cl
    or      [rdi + r9*4], edx           ; and b may not touch a
    add     rsi, 8
    cmp     rsi, r8
    jb      .pair
    ret

; ladder_pairs_ok(rsi biome array, edi n) -> eax 0 ok / 1 a forbidden pair
; No two 4-neighbours of the n x n array of biome ids (row z, column x) may be a forbidden pair of lad_forbid.
ladder_pairs_ok:
    lea     r8, [lad_forbid]
    lea     r11d, [rdi - 1]             ; the last row and column
    xor     r10d, r10d                  ; row
.row:
    xor     r9d, r9d                    ; column
    mov     eax, r10d
    imul    eax, edi                    ; index of (row, 0)
.col:
    movzx   ecx, byte [rsi + rax]
    mov     edx, [r8 + rcx*4]           ; the biomes this one may not touch
    cmp     r9d, r11d
    jae     .no_x
    movzx   ecx, byte [rsi + rax + 1]
    bt      edx, ecx
    jc      .fail
.no_x:
    cmp     r10d, r11d
    jae     .no_z
    lea     ecx, [rax + rdi]
    movzx   ecx, byte [rsi + rcx]
    bt      edx, ecx
    jc      .fail
.no_z:
    inc     eax
    inc     r9d
    cmp     r9d, edi
    jb      .col
    inc     r10d
    cmp     r10d, edi
    jb      .row
    xor     eax, eax
    ret
.fail:
    mov     eax, 1
    ret

; ladder_adjacent(edi seed) -> eax 0 ok / 1 fail
; gen_biome of the seed over the window |x|, |z| <= 512 at 4 blocks (lad_win), then ladder_pairs_ok on it.
ladder_adjacent:
    push    rbx
    push    r12
    push    r13
    call    worldgen_set_seed
    lea     r13, [lad_win]
    mov     r12d, -512                  ; z
.z:
    mov     ebx, -512                   ; x
.x:
    mov     edi, ebx
    mov     esi, r12d
    call    gen_biome
    mov     [r13], al
    inc     r13
    add     ebx, 4
    cmp     ebx, 512
    jle     .x
    add     r12d, 4
    cmp     r12d, 512
    jle     .z
    lea     rsi, [lad_win]
    mov     edi, LAD_N
    call    ladder_pairs_ok
    pop     r13
    pop     r12
    pop     rbx
    ret

; sg_fill() -> eax 0 ok / 1 fail
; For the 16 block grid |x|, |z| <= 3072 of the current seed, sg_bio gets the biome and sg_cls the SC_* bits of
; every sample. gen_surface must also keep its layering: the cover is 0 or SNOW_LAYER, a SAND top lies on SAND,
; GRASS and MUD on DIRT, a SNOW_BLOCK on STONE, and DRY_GRASS on SAND in a desert and on DIRT elsewhere.
sg_fill:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] top [4] filler [8] cover
    lea     r14, [sg_cls]
    mov     r12d, -3072                 ; z
.z:
    mov     ebx, -3072                  ; x
.x:
    mov     edi, ebx
    mov     esi, r12d
    call    gen_biome
    mov     r13d, eax                   ; biome
    lea     rcx, [sg_roles]
    movzx   r15d, byte [rcx + rax]      ; its role bits
    mov     edi, ebx
    mov     esi, r12d
    call    gen_surface
    mov     [rsp], eax
    mov     [rsp + 4], edx
    mov     [rsp + 8], ecx
    test    ecx, ecx
    jz      .top
    cmp     ecx, SNOW_LAYER
    jne     .fail
    or      r15d, SC_SNOWY
    test    r15d, SC_TEMP
    jz      .top
    or      r15d, SC_QC
.top:
    mov     eax, [rsp]
    mov     edx, [rsp + 4]
    cmp     eax, SNOW_BLOCK
    je      .snow_block
    cmp     eax, SAND
    je      .sand
    cmp     eax, DRY_GRASS
    je      .dry
    cmp     eax, GRASS
    je      .dirt
    cmp     eax, MUD
    je      .dirt
    jmp     .store
.snow_block:
    or      r15d, SC_SNOWY
    cmp     edx, STONE
    jne     .fail
    jmp     .store
.sand:
    cmp     edx, SAND
    jne     .fail
    test    r15d, SC_SAVANNA
    jz      .store
    mov     edi, ebx                    ; a sand-topped savanna: a patch, unless it is a beach
    mov     esi, r12d
    call    gen_height
    cmp     eax, 98
    jle     .store
    or      r15d, SC_QD
    jmp     .store
.dry:
    test    r15d, SC_TEMP
    jz      .dry_filler
    or      r15d, SC_QB
.dry_filler:
    mov     ecx, DIRT
    cmp     r13d, BIOME_DESERT
    jne     .dry_cmp
    mov     ecx, SAND
.dry_cmp:
    cmp     edx, ecx
    jne     .fail
    jmp     .store
.dirt:
    cmp     edx, DIRT
    jne     .fail
.store:
    lea     rcx, [sg_cls]
    mov     rax, r14
    sub     rax, rcx                    ; the sample's index
    mov     [r14], r15b
    inc     r14
    lea     rcx, [sg_bio]
    mov     [rcx + rax], r13b
    add     ebx, 16
    cmp     ebx, 3072
    jle     .x
    add     r12d, 16
    cmp     r12d, 3072
    jle     .z
    xor     eax, eax
    jmp     .out
.fail:
    mov     eax, 1
.out:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sg_near(edi i, esi j, edx r, ecx mask) -> eax 1 when some grid sample within r steps of (i, j) (a square window,
; clipped to the grid) has a class bit of mask
sg_near:
    mov     r8d, esi
    sub     r8d, edx                    ; first row
    jns     .row0
    xor     r8d, r8d
.row0:
    lea     r9d, [rsi + rdx]            ; last row
    cmp     r9d, SG_N - 1
    jbe     .row1
    mov     r9d, SG_N - 1
.row1:
    mov     r10d, edi
    sub     r10d, edx                   ; first column
    jns     .col0
    xor     r10d, r10d
.col0:
    lea     r11d, [rdi + rdx]           ; last column
    cmp     r11d, SG_N - 1
    jbe     .col1
    mov     r11d, SG_N - 1
.col1:
    lea     rsi, [sg_cls]
.row:
    imul    eax, r8d, SG_N
    add     eax, r10d
    mov     edx, r10d
.col:
    movzx   edi, byte [rsi + rax]
    test    edi, ecx
    jnz     .yes
    inc     eax
    inc     edx
    cmp     edx, r11d
    jbe     .col
    inc     r8d
    cmp     r8d, r9d
    jbe     .row
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; sg_check() -> eax 0 ok / 4..10 the failed check (see test_biome_ladder)
; Over sg_cls: no sample with a snowy surface lies within 2 steps (32 blocks) of a desert; some plains, birch
; forest or forest sample has a DRY_GRASS top, some has SNOW_LAYER cover, and some savanna sample has a sand
; patch; and these patches sit by their borders: every sand patch has a desert within 3 steps (48 blocks), and
; at least 90 % of the dry grass ones a savanna, of the snow ones a taiga or snow biome (the rest are patches
; around a temperature peak or dip that just misses the border).
sg_check:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [0] dry grass patches [4] with no savanna near [8] snow patches
                                        ; [12] with no taiga or snow near [16] sand patches [20] with no desert near
    xor     eax, eax
    mov     [rsp], eax
    mov     [rsp + 4], eax
    mov     [rsp + 8], eax
    mov     [rsp + 12], eax
    mov     [rsp + 16], eax
    mov     [rsp + 20], eax
    xor     r12d, r12d                  ; j
.j:
    xor     ebx, ebx                    ; i
.i:
    imul    eax, r12d, SG_N
    add     eax, ebx
    lea     rcx, [sg_cls]
    movzx   r13d, byte [rcx + rax]
    test    r13d, SC_DESERT
    jz      .no_desert
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 2
    mov     ecx, SC_SNOWY
    call    sg_near
    test    eax, eax
    jnz     .f4                         ; snow beside a desert
.no_desert:
    test    r13d, SC_QB
    jz      .no_qb
    inc     dword [rsp]
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 3
    mov     ecx, SC_SAVANNA
    call    sg_near
    test    eax, eax
    jnz     .no_qb
    inc     dword [rsp + 4]
.no_qb:
    test    r13d, SC_QC
    jz      .no_qc
    inc     dword [rsp + 8]
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 3
    mov     ecx, SC_COLD
    call    sg_near
    test    eax, eax
    jnz     .no_qc
    inc     dword [rsp + 12]
.no_qc:
    test    r13d, SC_QD
    jz      .next
    inc     dword [rsp + 16]
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, 3
    mov     ecx, SC_DESERT
    call    sg_near
    test    eax, eax
    jnz     .next
    inc     dword [rsp + 20]
.next:
    inc     ebx
    cmp     ebx, SG_N
    jb      .i
    inc     r12d
    cmp     r12d, SG_N
    jb      .j
    cmp     dword [rsp], 0
    je      .f5                         ; no dry grass in a temperate biome
    cmp     dword [rsp + 8], 0
    je      .f6                         ; no snow cover in one
    cmp     dword [rsp + 16], 0
    je      .f7                         ; no sand patch in a savanna
    cmp     dword [rsp + 20], 0
    jne     .f8                         ; a sand patch far from any desert
    mov     eax, [rsp + 4]
    imul    eax, eax, 10
    cmp     eax, [rsp]
    ja      .f9                         ; over 10 % of the dry grass patches far from a savanna
    mov     eax, [rsp + 12]
    imul    eax, eax, 10
    cmp     eax, [rsp + 8]
    ja      .f10                        ; over 10 % of the snow patches far from a taiga or snow biome
    xor     eax, eax
    jmp     .out
.f4:
    mov     eax, 4
    jmp     .out
.f5:
    mov     eax, 5
    jmp     .out
.f6:
    mov     eax, 6
    jmp     .out
.f7:
    mov     eax, 7
    jmp     .out
.f8:
    mov     eax, 8
    jmp     .out
.f9:
    mov     eax, 9
    jmp     .out
.f10:
    mov     eax, 10
.out:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; veg_rows: biome, h, top, t, the veg_kind that cell must give (0 none, 1 oak, 2 birch, 3 pine, 4 cactus,
; 5 snowy pine, 6 acacia): the planting rules of the design, one row at and one row past each threshold
section .rodata
align 4
veg_rows:
    dd BIOME_PLAINS,    100, GRASS,     0,       1
    dd BIOME_PLAINS,    100, GRASS,     1,       0
    dd BIOME_PLAINS,    96,  GRASS,     0,       0
    dd BIOME_PLAINS,    100, DRY_GRASS, 0,       0
    dd BIOME_FOREST,    100, GRASS,     6,       2
    dd BIOME_FOREST,    100, GRASS,     256 + 6, 1
    dd BIOME_FOREST,    100, GRASS,     7,       0
    dd BIOME_BIRCH,     100, GRASS,     6,       2
    dd BIOME_BIRCH,     100, GRASS,     7,       0
    dd BIOME_SNOW,      100, GRASS,     2,       5
    dd BIOME_SNOW,      100, GRASS,     3,       0
    dd BIOME_TAIGA,     100, GRASS,     7,       5
    dd BIOME_TAIGA,     100, GRASS,     8,       0
    dd BIOME_MOUNTAINS, 149, GRASS,     1,       3
    dd BIOME_MOUNTAINS, 149, GRASS,     2,       0
    dd BIOME_MOUNTAINS, 150, GRASS,     1,       0
    dd BIOME_SWAMP,     100, GRASS,     2,       1
    dd BIOME_SWAMP,     100, GRASS,     3,       0
    dd BIOME_DESERT,    100, SAND,      1,       4
    dd BIOME_DESERT,    100, GRASS,     1,       0
    dd BIOME_SAVANNA,   100, DRY_GRASS, 1,       6
    dd BIOME_SAVANNA,   100, GRASS,     1,       0
    dd BIOME_SHORE,     100, GRASS,     0,       0
    dd BIOME_OCEAN,     100, GRASS,     0,       0
veg_rows_end:

section .text
; veg_rows_ok() -> eax 0 when veg_kind gives every veg_rows row its kind
veg_rows_ok:
    push    rbx
    lea     rbx, [veg_rows]
.row:
    mov     edi, [rbx]
    mov     esi, [rbx + 4]
    mov     edx, [rbx + 8]
    mov     ecx, [rbx + 12]
    call    veg_kind
    cmp     eax, [rbx + 16]
    jne     .bad
    add     rbx, 20
    lea     rax, [veg_rows_end]
    cmp     rbx, rax
    jb      .row
    xor     eax, eax
    pop     rbx
    ret
.bad:
    mov     eax, 1
    pop     rbx
    ret

; The climate ladder. Seeds 42 and 7: over the window |x|, |z| <= 512 at 4 blocks no two 4-neighbours are snow
; beside plains, birch forest, forest, swamp, savanna or desert, taiga beside swamp, savanna or desert, swamp
; beside savanna or desert, or desert beside plains, birch forest or forest. Seed 42, the 16 block grid over
; |x|, |z| <= 3072 with gen_surface: no snowy surface within 32 blocks of a desert, and the patches of dry grass,
; snow and sand that the surface materials dither over a border sit by that border (sg_check); gen_surface also
; keeps its layering (sg_fill); and the same forbidden pairs do not touch on that grid either. eax tells which
; check failed: 1 forbidden neighbours with seed 42, 2 with seed 7, 3 gen_surface's layering, 4 snow within 32
; blocks of a desert, 5 no dry grass patch in a temperate biome, 6 no snow patch in one, 7 no sand patch in a
; savanna, 8 a sand patch far from a desert, 9 dry grass patches far from a savanna, 10 snow patches far from a
; taiga or snow biome, 11 forbidden neighbours on the grid, 12 a plant decision of veg_kind (veg_rows).
test_biome_ladder:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    call    world_clear
    call    ladder_masks
    mov     edi, 42
    call    ladder_adjacent
    test    eax, eax
    jz      .seed7
    mov     eax, 1
    jmp     .out
.seed7:
    mov     edi, 7
    call    ladder_adjacent
    test    eax, eax
    jz      .surface
    mov     eax, 2
    jmp     .out
.surface:
    mov     edi, 42
    call    worldgen_set_seed
    call    sg_fill
    test    eax, eax
    jz      .check
    mov     eax, 3
    jmp     .out
.check:
    call    sg_check
    test    eax, eax
    jnz     .out
    lea     rsi, [sg_bio]
    mov     edi, SG_N
    call    ladder_pairs_ok
    test    eax, eax
    jz      .veg
    mov     eax, 11
    jmp     .out
.veg:
    call    veg_rows_ok
    test    eax, eax
    jz      .out
    mov     eax, 12
.out:
    mov     ebx, eax
    mov     edi, 42
    call    worldgen_set_seed
    mov     eax, ebx
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret
