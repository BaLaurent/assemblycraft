; test_mesher.asm - tests for mesh_chunk (vertex counts, chunk-local positions, packed light, the
; translucent range of water, the tall-grass cross) and for the renderer's view frustum.
; Everything goes through the contract of the streamed world: world_clear, world_set and the chunk
; data of world_chunk (a chunk exists once a non-AIR block was set in it).
%include "common.inc"
default rel

global test_mesh_single_block, test_mesh_adjacent_opaque, test_mesh_adjacent_leaves
global test_mesh_adjacent_glass, test_mesh_chunk_boundary
global test_mesh_slab_half_height, test_mesh_stairs_quads, test_mesh_light_packed
global test_mesher_water, test_mesher_cross, test_render_frustum

extern world_clear, world_set, world_chunk
extern mesh_chunk, mesh_scratch
extern frustum_setup, frustum_test

section .rodata
align 4
t_fov:      dd 70.0
t_aspect:   dd 1.7777778                ; 16 / 9
t_yaw90:    dd 90.0

; frustum rows: x, y, z (local frame), expected frame_test result. The eye is at (0, 1.62, 0).
; yaw 0, pitch 0: looking along -z, fov 70
fr_north:
    dd   0.0,  1.62, -20.0, 1           ; 20 ahead
    dd   0.0,  1.62,  20.0, 0           ; 20 behind: farther than the 14 margin
    dd  40.0,  1.62,   0.0, 0           ; 40 to the side, at 90 degrees
    dd -40.0,  1.62,   0.0, 0
    dd   0.0,  1.62,  10.0, 1           ; 10 behind: inside the 14 margin
    dd   0.0,  6.62, -20.0, 1           ; 5 above the line of sight
    dd   0.0, 61.62, -20.0, 0           ; 60 above it
%define FR_NORTH_N 7
; yaw 90: looking along +x
fr_east:
    dd  20.0,  1.62,   0.0, 1
    dd -20.0,  1.62,   0.0, 0
    dd -10.0,  1.62,   0.0, 1
    dd   0.0,  1.62,  40.0, 0
    dd   0.0,  1.62, -40.0, 0
%define FR_EAST_N 5
; pitch 90: looking straight down
fr_down:
    dd   0.0, -18.38,  0.0, 1           ; 20 below the eye
    dd   0.0,  21.62,  0.0, 0           ; 20 above it
    dd  40.0,   1.62,  0.0, 0
%define FR_DOWN_N 3

section .text

; SETB x, y, z, id
%macro SETB 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set
%endmacro

; mesh_one(edi acx, esi acy, edx acz) -> eax vertex count, edx first translucent vertex, into
; mesh_scratch
mesh_one:
    push    rbp
    mov     rbp, rsp
    lea     rcx, [mesh_scratch]
    call    mesh_chunk
    pop     rbp
    ret

; two blocks side by side at (5,5,5) and (6,5,5): expect %1 vertices
%macro PAIR_TEST 3
%1:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    SETB    5, 5, 5, %2
    SETB    6, 5, 5, %2
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    mesh_one
    cmp     eax, %3
    jne     .fail
    call    world_clear
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret
%endmacro

test_mesh_single_block:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    SETB    5, 5, 5, STONE
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    mesh_one
    cmp     eax, 24
    jne     .fail
    cmp     edx, 24                     ; no translucent block: the translucent range is empty
    jne     .fail
    ; a stone on the bottom layer: its +Y quad (vertices 8..11) sees the open sky, its -Y quad
    ; (12..15) the plane under the world, which has no light (what light_get answers for y < 0)
    call    world_clear
    SETB    5, 0, 5, STONE
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    mesh_one
    cmp     eax, 24
    jne     .fail
    mov     edi, 8
    mov     esi, 4
    mov     edx, VERTEX.pad
    mov     ecx, LIGHT_SKY_FULL
    call    vert_count
    cmp     eax, 4
    jne     .fail
    mov     edi, 12
    mov     esi, 4
    mov     edx, VERTEX.pad
    xor     ecx, ecx
    call    vert_count
    cmp     eax, 4
    jne     .fail
    call    world_clear
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

PAIR_TEST test_mesh_adjacent_opaque, STONE, 40
PAIR_TEST test_mesh_adjacent_leaves, LEAVES, 48
PAIR_TEST test_mesh_adjacent_glass, GLASS, 40

; stone at (15,5,5) and (16,5,5): the face between them is hidden in both chunks, and the vertices
; are chunk-local: the stone at local x 15 spans 240..256 in chunk 0, the one at local x 0 spans
; 0..16 in chunk 1
test_mesh_chunk_boundary:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    SETB    15, 5, 5, STONE
    SETB    16, 5, 5, STONE
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    mesh_one
    cmp     eax, 20
    jne     .fail
    xor     edi, edi
    mov     esi, 20
    mov     edx, VERTEX.x
    call    vert_range
    cmp     eax, 15 * 16
    jne     .fail
    cmp     edx, 16 * 16
    jne     .fail
    mov     edi, 1
    xor     esi, esi
    xor     edx, edx
    call    mesh_one
    cmp     eax, 20
    jne     .fail
    xor     edi, edi
    mov     esi, 20
    mov     edx, VERTEX.x
    call    vert_range
    test    eax, eax
    jnz     .fail
    cmp     edx, 16
    jne     .fail
    call    world_clear
    xor     eax, eax
    pop     rbp
    ret
.fail:
    mov     eax, 1
    pop     rbp
    ret

; vert_range(edi first, esi count, edx field offset in VERTEX) -> eax min, edx max of that 16-bit
; field over `count` vertices of mesh_scratch starting at vertex `first`
vert_range:
    lea     rcx, [mesh_scratch]
    add     rcx, rdx
    mov     eax, edi
    shl     rax, 4
    add     rcx, rax
    mov     eax, 0x7FFF
    xor     edx, edx
.v:
    test    esi, esi
    jz      .ret
    movzx   r8d, word [rcx]
    cmp     r8d, eax
    cmovb   eax, r8d
    cmp     r8d, edx
    cmova   edx, r8d
    add     rcx, VERTEX_SIZE
    dec     esi
    jmp     .v
.ret:
    ret

; vert_count(edi first, esi count, edx field offset, ecx value) -> eax: how many of the `count`
; vertices from `first` have that 16-bit field equal to `value`
vert_count:
    lea     r8, [mesh_scratch]
    add     r8, rdx
    mov     eax, edi
    shl     rax, 4
    add     r8, rax
    xor     eax, eax
.v:
    test    esi, esi
    jz      .ret
    movzx   edx, word [r8]
    cmp     edx, ecx
    jne     .next
    inc     eax
.next:
    add     r8, VERTEX_SIZE
    dec     esi
    jmp     .v
.ret:
    ret

; vert_colour(edi first, esi count, edx colour) -> eax 1 when every one of the `count` vertices
; from `first` carries exactly that colour dword
vert_colour:
    lea     r8, [mesh_scratch]
    mov     eax, edi
    shl     rax, 4
    add     r8, rax
.v:
    test    esi, esi
    jz      .yes
    cmp     [r8 + VERTEX.r], edx
    jne     .no
    add     r8, VERTEX_SIZE
    dec     esi
    jmp     .v
.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; a lone slab in chunk (1, 2, -1) at local cell (5, 5, 11): 24 vertices, 16 units wide, half a block
; (8 units) tall at 1/16 precision, positions relative to the chunk
test_mesh_slab_half_height:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    SETB    21, 37, -5, PLANK_SLAB
    mov     edi, 1
    mov     esi, 2
    mov     edx, -1
    call    mesh_one
    cmp     eax, 24
    jne     .fail
    xor     edi, edi
    mov     esi, 24
    mov     edx, VERTEX.y
    call    vert_range
    cmp     eax, 5 * 16
    jne     .fail
    cmp     edx, 5 * 16 + 8
    jne     .fail
    xor     edi, edi
    mov     esi, 24
    mov     edx, VERTEX.x
    call    vert_range
    cmp     eax, 5 * 16
    jne     .fail
    cmp     edx, 6 * 16
    jne     .fail
    xor     edi, edi
    mov     esi, 24
    mov     edx, VERTEX.z
    call    vert_range
    cmp     eax, 11 * 16
    jne     .fail
    cmp     edx, 12 * 16
    jne     .fail
    ; the +Z side (vertices 16..19, planks = tile 5) shows the lower half of the tile: its top
    ; corners TR, TL sit at y = 8, so v = 16 - 8 = 8 units = 128, u = 255 / 1 inside the tile
    lea     rsi, [mesh_scratch]
    cmp     word [rsi + 18 * 16 + VERTEX.u], 5 * 256 + 255
    jne     .fail
    cmp     word [rsi + 18 * 16 + VERTEX.v], 128
    jne     .fail
    cmp     word [rsi + 19 * 16 + VERTEX.u], 5 * 256 + 1
    jne     .fail
    cmp     word [rsi + 19 * 16 + VERTEX.v], 128
    jne     .fail
    call    world_clear
    xor     eax, eax
    pop     rbp
    ret
.fail:
    call    world_clear
    mov     eax, 1
    pop     rbp
    ret

; lone stairs: two boxes of 6 faces each = 48 vertices, a full block tall
test_mesh_stairs_quads:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    SETB    5, 5, 5, PLANK_STAIRS + DIR_E
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    mesh_one
    cmp     eax, 48
    jne     .fail
    xor     edi, edi
    mov     esi, 48
    mov     edx, VERTEX.y
    call    vert_range
    cmp     eax, 5 * 16
    jne     .fail
    cmp     edx, 6 * 16
    jne     .fail
    mov     edi, 24                     ; the second box, the east half of the upper step
    mov     esi, 24
    mov     edx, VERTEX.x
    call    vert_range
    cmp     eax, 5 * 16 + 8
    jne     .fail
    cmp     edx, 6 * 16
    jne     .fail
    call    world_clear
    xor     eax, eax
    pop     rbp
    ret
.fail:
    call    world_clear
    mov     eax, 1
    pop     rbp
    ret

; smooth light: stone at (5,5,5) under a 3 x 3 patch of sky 14 / block 7 at y = 6, the rest of the
; chunk dark. Quads are emitted +X, -X, +Y, -Y, +Z, -Z with the corners BL, BR, TR, TL. All four +Y
; vertices see only patch cells (0xE7). On the +X face the top corners average PV and the corner's
; three probes: block (0 + 0 + 7 + 7) / 4 = 3 at TR, TL and 0 at BL, BR (smooth per corner); the sky
; levels there are 7, 7, 0, 0, which a face flattens to their truncated average 3: 0x30 / 0x33.
test_mesh_light_packed:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    SETB    5, 5, 5, STONE
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    world_chunk                 ; the chunk the stone allocated
    test    rax, rax
    jz      .fail
    mov     rsi, rax
    lea     rdi, [rsi + 4096]           ; its light: dark everywhere ...
    xor     eax, eax
    mov     ecx, 4096 / 8
    rep     stosq
    mov     edx, 4                      ; ... but the patch, z 4..6
.lz:
    mov     ecx, 4                      ; x 4..6
.lx:
    mov     eax, edx
    shl     eax, 4
    or      eax, ecx
    or      eax, 6 << 8                 ; y = 6
    mov     byte [rsi + 4096 + rax], 0xE7
    inc     ecx
    cmp     ecx, 6
    jbe     .lx
    inc     edx
    cmp     edx, 6
    jbe     .lz
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    mesh_one
    cmp     eax, 24
    jne     .fail
    lea     rsi, [mesh_scratch]
    mov     ecx, 8                      ; +Y: vertices 8..11
.top:
    mov     rax, rcx
    shl     rax, 4
    cmp     word [rsi + rax + VERTEX.pad], 0xE7
    jne     .fail
    inc     ecx
    cmp     ecx, 12
    jb      .top
    cmp     word [rsi + 0 * 16 + VERTEX.pad], 0x30      ; +X: BL, BR on the dark side
    jne     .fail
    cmp     word [rsi + 1 * 16 + VERTEX.pad], 0x30
    jne     .fail
    cmp     word [rsi + 2 * 16 + VERTEX.pad], 0x33      ; TR, TL average the patch in
    jne     .fail
    cmp     word [rsi + 3 * 16 + VERTEX.pad], 0x33
    jne     .fail
    mov     ecx, 12                     ; -Y: vertices 12..15 see nothing lit
.bottom:
    mov     rax, rcx
    shl     rax, 4
    cmp     word [rsi + rax + VERTEX.pad], 0x00
    jne     .fail
    inc     ecx
    cmp     ecx, 16
    jb      .bottom
    call    world_clear
    xor     eax, eax
    pop     rbp
    ret
.fail:
    call    world_clear
    mov     eax, 1
    pop     rbp
    ret

; water: a 5 x 5 stone floor at y = 9 with a 3 x 3 pool of WATER at y = 10 on x, z 1..3. The
; opaque range is the floor alone (25 tops, 25 bottoms, 20 outer sides = 70 quads: the stone under
; the water keeps its top). The translucent range holds exactly 21 quads: the 9 tops at
; y = 10 * 16 + 14 and the 12 outer sides (the sides between pool cells, the sides in contact
; with the floor and the faces against other water are culled), all coloured 0xFFFFFFFF, light
; of the cell they face, tile TILE_WATER. No opaque vertex lies on the water surface.
test_mesher_water:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    call    world_clear
    xor     r12d, r12d                  ; z
.floor_z:
    xor     r13d, r13d                  ; x
.floor_x:
    mov     edi, r13d
    mov     esi, 9
    mov     edx, r12d
    mov     ecx, STONE
    call    world_set
    inc     r13d
    cmp     r13d, 4
    jbe     .floor_x
    inc     r12d
    cmp     r12d, 4
    jbe     .floor_z
    mov     r12d, 1
.pool_z:
    mov     r13d, 1
.pool_x:
    mov     edi, r13d
    mov     esi, 10
    mov     edx, r12d
    mov     ecx, WATER
    call    world_set
    inc     r13d
    cmp     r13d, 3
    jbe     .pool_x
    inc     r12d
    cmp     r12d, 3
    jbe     .pool_z
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    mesh_one
    mov     ebx, eax                    ; total vertices
    mov     r12d, edx                   ; first translucent vertex
    cmp     r12d, 70 * 4
    jne     .fail
    mov     eax, ebx
    sub     eax, r12d
    mov     r13d, eax                   ; translucent vertices
    cmp     r13d, 21 * 4
    jne     .fail
    ; the surface sits at 14/16: 9 tops (4 vertices each) and the top edge of the 12 sides
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, VERTEX.y
    mov     ecx, 10 * 16 + 14
    call    vert_count
    cmp     eax, 9 * 4 + 12 * 2
    jne     .fail
    mov     edi, r12d                   ; the sides' bottom edges rest on the cell floor
    mov     esi, r13d
    mov     edx, VERTEX.y
    mov     ecx, 10 * 16
    call    vert_count
    cmp     eax, 12 * 2
    jne     .fail
    xor     edi, edi                    ; nothing opaque on the water surface
    mov     esi, r12d
    mov     edx, VERTEX.y
    mov     ecx, 10 * 16 + 14
    call    vert_count
    test    eax, eax
    jnz     .fail
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, 0xFFFFFFFF
    call    vert_colour
    test    eax, eax
    jz      .fail
    mov     edi, r12d                   ; inside the tile TILE_WATER (column 0, row 12)
    mov     esi, r13d
    mov     edx, VERTEX.u
    call    vert_range
    test    eax, eax
    jz      .fail                       ; u >= 1
    cmp     edx, 255
    ja      .fail
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, VERTEX.v
    call    vert_range
    cmp     eax, 12 * 256 + 1
    jb      .fail
    cmp     edx, 12 * 256 + 255
    ja      .fail
    mov     edi, r12d                   ; the light the faces face: full sky
    mov     esi, r13d
    mov     edx, VERTEX.pad
    call    vert_range
    cmp     eax, LIGHT_SKY_FULL
    jne     .fail
    cmp     edx, LIGHT_SKY_FULL
    jne     .fail
    call    world_clear
    xor     eax, eax
    jmp     .ret
.fail:
    call    world_clear
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; vert_same(edi i, esi j) -> eax 1 when vertices i and j of mesh_scratch are byte-identical
vert_same:
    lea     r8, [mesh_scratch]
    mov     eax, edi
    shl     rax, 4
    add     rax, r8
    mov     ecx, esi
    shl     rcx, 4
    add     rcx, r8
    movups  xmm0, [rax]
    movups  xmm1, [rcx]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    cmp     eax, 0xFFFF
    sete    al
    movzx   eax, al
    ret

; tall grass: TALL_GRASS at (5,10,5) on a stone block at (5,9,5). The stone still shows its top
; (24 vertices, its +Y quad is 8..11 at y = 160) and the grass adds exactly 16 vertices (vertices
; 24..39), all in the opaque range (the cross is alpha-tested, not translucent): two diagonal quads,
; each in both windings, inside the cell, tile TILE_TALL_GRASS (column 4, row 12), light of its own
; cell, colour 0xFFFFFFFF.
test_mesher_cross:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    SETB    5, 9, 5, STONE
    SETB    5, 10, 5, TALL_GRASS
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
    call    mesh_one
    cmp     eax, 24 + 16
    jne     .fail
    cmp     edx, 24 + 16                ; opaque range: the cross is alpha-tested, not translucent
    jne     .fail
    mov     edi, 8                      ; the stone's top quad is still there
    mov     esi, 4
    mov     edx, VERTEX.y
    mov     ecx, 10 * 16
    call    vert_count
    cmp     eax, 4
    jne     .fail
    mov     edi, 24
    mov     esi, 16
    mov     edx, VERTEX.x
    call    vert_range
    cmp     eax, 5 * 16
    jne     .fail
    cmp     edx, 6 * 16
    jne     .fail
    mov     edi, 24
    mov     esi, 16
    mov     edx, VERTEX.y
    call    vert_range
    cmp     eax, 10 * 16
    jne     .fail
    cmp     edx, 11 * 16
    jne     .fail
    mov     edi, 24
    mov     esi, 16
    mov     edx, VERTEX.z
    call    vert_range
    cmp     eax, 5 * 16
    jne     .fail
    cmp     edx, 6 * 16
    jne     .fail
    mov     edi, 24
    mov     esi, 16
    mov     edx, VERTEX.u
    call    vert_range
    cmp     eax, 4 * 256 + 1
    jne     .fail
    cmp     edx, 4 * 256 + 255
    jne     .fail
    mov     edi, 24
    mov     esi, 16
    mov     edx, VERTEX.v
    call    vert_range
    cmp     eax, 12 * 256 + 1
    jne     .fail
    cmp     edx, 12 * 256 + 255
    jne     .fail
    mov     edi, 24
    mov     esi, 16
    mov     edx, VERTEX.pad
    mov     ecx, LIGHT_SKY_FULL
    call    vert_count
    cmp     eax, 16
    jne     .fail
    mov     edi, 24
    mov     esi, 16
    mov     edx, 0xFFFFFFFF
    call    vert_colour
    test    eax, eax
    jz      .fail
    ; the diagonals: quad A runs along x = z, quad B along x + z = 16 (cell-relative 1/16 units);
    ; 8 vertices each, 4 bottom and 4 top
    mov     edi, 24
    mov     esi, 4
    call    cross_diag
    cmp     eax, 4
    jne     .fail
    mov     edi, 28
    mov     esi, 4
    call    cross_diag
    cmp     eax, 4
    jne     .fail
    mov     edi, 32
    mov     esi, 4
    call    cross_anti
    cmp     eax, 4
    jne     .fail
    mov     edi, 36
    mov     esi, 4
    call    cross_anti
    cmp     eax, 4
    jne     .fail
    ; both windings: the back quad lists the front quad's corners in reverse order
    mov     edi, 28                     ; A back BR = A front BR
    mov     esi, 25
    call    vert_same
    test    eax, eax
    jz      .fail
    mov     edi, 29                     ; BL
    mov     esi, 24
    call    vert_same
    test    eax, eax
    jz      .fail
    mov     edi, 30                     ; TL
    mov     esi, 27
    call    vert_same
    test    eax, eax
    jz      .fail
    mov     edi, 31                     ; TR
    mov     esi, 26
    call    vert_same
    test    eax, eax
    jz      .fail
    mov     edi, 36                     ; B back BR = B front BR
    mov     esi, 33
    call    vert_same
    test    eax, eax
    jz      .fail
    call    world_clear
    xor     eax, eax
    pop     rbp
    ret
.fail:
    call    world_clear
    mov     eax, 1
    pop     rbp
    ret

; cross_diag(edi first, esi count) -> eax vertices of mesh_scratch[first..first+count) of the cell
; (5, 10, 5) with x - 80 == z - 80; cross_anti: with (x - 80) + (z - 80) == 16
cross_diag:
    lea     r8, [mesh_scratch]
    mov     eax, edi
    shl     rax, 4
    add     r8, rax
    xor     eax, eax
.v:
    test    esi, esi
    jz      .ret
    movzx   edx, word [r8 + VERTEX.x]
    movzx   ecx, word [r8 + VERTEX.z]
    cmp     edx, ecx
    jne     .next
    inc     eax
.next:
    add     r8, VERTEX_SIZE
    dec     esi
    jmp     .v
.ret:
    ret

cross_anti:
    lea     r8, [mesh_scratch]
    mov     eax, edi
    shl     rax, 4
    add     r8, rax
    xor     eax, eax
.v:
    test    esi, esi
    jz      .ret
    movzx   edx, word [r8 + VERTEX.x]
    movzx   ecx, word [r8 + VERTEX.z]
    add     edx, ecx
    cmp     edx, 2 * 5 * 16 + 16
    jne     .next
    inc     eax
.next:
    add     r8, VERTEX_SIZE
    dec     esi
    jmp     .v
.ret:
    ret

; run_cases(rsi rows, edx count) -> eax 0 when frustum_test answers every row's expectation
; (a row is x, y, z floats and the expected 0 / 1)
run_cases:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rsi
    mov     r12d, edx
.row:
    movss   xmm0, [rbx]
    movss   xmm1, [rbx + 4]
    movss   xmm2, [rbx + 8]
    call    frustum_test
    cmp     eax, [rbx + 12]
    jne     .fail
    add     rbx, 16
    dec     r12d
    jnz     .row
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    pop     r12
    pop     rbx
    pop     rbp
    ret

; the camera at the origin (eye (0, 1.62, 0)), fov 70, aspect 16 / 9: a point 20 ahead is inside, 20
; behind and 40 to the side at 90 degrees are outside, 10 behind is inside the 14 margin; the same
; for yaw 90 (looking +x) and pitch 90 (looking down)
test_render_frustum:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 80                     ; a BODY
    mov     rdi, rsp
    xor     eax, eax
    mov     ecx, BODY_size / 4
    rep     stosd
    mov     rdi, rsp
    movss   xmm0, [t_fov]
    movss   xmm1, [t_aspect]
    call    frustum_setup
    lea     rsi, [fr_north]
    mov     edx, FR_NORTH_N
    call    run_cases
    test    eax, eax
    jnz     .fail
    mov     eax, [t_yaw90]
    mov     [rsp + BODY.yaw], eax
    mov     rdi, rsp
    movss   xmm0, [t_fov]
    movss   xmm1, [t_aspect]
    call    frustum_setup
    lea     rsi, [fr_east]
    mov     edx, FR_EAST_N
    call    run_cases
    test    eax, eax
    jnz     .fail
    mov     dword [rsp + BODY.yaw], 0
    mov     eax, [t_yaw90]
    mov     [rsp + BODY.pitch], eax
    mov     rdi, rsp
    movss   xmm0, [t_fov]
    movss   xmm1, [t_aspect]
    call    frustum_setup
    lea     rsi, [fr_down]
    mov     edx, FR_DOWN_N
    call    run_cases
    test    eax, eax
    jnz     .fail
    xor     eax, eax
    jmp     .ret
.fail:
    mov     eax, 1
.ret:
    add     rsp, 80
    pop     rbp
    ret
