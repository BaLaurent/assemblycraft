; test_worldgen.asm - terrain generator tests (gen_column and the pure gen_* functions).
%include "common.inc"
default rel

global test_worldgen_deterministic, test_worldgen_shape, test_worldgen_ores
global test_worldgen_biomes, test_worldgen_column_independence
global test_worldgen_spawn, test_worldgen_water_ice

extern world_clear, fnv1a
extern worldgen_set_seed, gen_column, gen_height, gen_biome, gen_find_spawn

%define BIOME_TOTAL 148225              ; 385 x 385 samples of the 16 block grid over |x|, |z| <= 3072
%define GB_SCRATCH  8                   ; generator buffers below
%define WI_STRIDE   700                 ; water_ice looks at every 700th ocean or river centre

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

; seed 42, gen_biome on the 16 block grid over |x|, |z| <= 3072: every biome occurs, the ocean covers
; 10..45 %, each other land biome at least 2 %
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
    mov     eax, [rsi + rcx*4]
    imul    rax, rax, 100
    cmp     rax, BIOME_TOTAL * 2
    jb      .fail
    inc     ecx
    cmp     ecx, BIOME_MOUNTAINS
    jbe     .land
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

; col_ok(edi ax, esi az) -> eax 1 when the column is spawn material: biome PLAINS .. SWAMP and terrain >= 97
col_ok:
    push    rbx
    push    r12
    push    r13
    mov     ebx, edi
    mov     r12d, esi
    call    gen_biome
    dec     eax
    cmp     eax, 4
    ja      .no
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
; The spawn is deterministic, on a column centre, on land that is neither ocean, river nor mountains,
; stands on the terrain surface, and no column that comes before it in the ring order qualifies.
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
    cmp     eax, BIOME_OCEAN
    je      .fail
    cmp     eax, BIOME_RIVER
    je      .fail
    cmp     eax, BIOME_MOUNTAINS
    je      .fail
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
