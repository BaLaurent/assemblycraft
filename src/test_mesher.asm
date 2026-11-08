; test_mesher.asm - vertex-count tests for mesh_chunk.
%include "common.inc"
default rel

global test_mesh_single_block, test_mesh_adjacent_opaque, test_mesh_adjacent_leaves
global test_mesh_adjacent_glass, test_mesh_chunk_boundary
global test_mesh_slab_half_height, test_mesh_stairs_quads, test_mesh_light_packed

extern world_clear, world_set
extern mesh_chunk, mesh_scratch, light_cells

section .text

; SETB x, y, z, id
%macro SETB 4
    mov     edi, %1
    mov     esi, %2
    mov     edx, %3
    mov     ecx, %4
    call    world_set
%endmacro

; mesh(edi cx, esi cy, edx cz) -> eax vertex count, into mesh_scratch
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
    mov     edi, 1
    xor     esi, esi
    xor     edx, edx
    call    mesh_one
    cmp     eax, 20
    jne     .fail
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

; light_full: every light cell back to full sky light, the state world_clear leaves
light_full:
    lea     rdi, [light_cells]
    mov     ecx, WORLD_VOLUME
    mov     eax, LIGHT_SKY_FULL
    rep     stosb
    ret

; a lone slab: 24 vertices, 16 units wide, half a block (8 units) tall at 1/16 precision
test_mesh_slab_half_height:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    SETB    5, 5, 5, PLANK_SLAB
    xor     edi, edi
    xor     esi, esi
    xor     edx, edx
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

; smooth light: stone at (5,5,5) under a 3 x 3 patch of sky 14 / block 7 at y = 6, the rest dark.
; Quads are emitted +X, -X, +Y, -Y, +Z, -Z with the corners BL, BR, TR, TL. All four +Y vertices
; see only patch cells (0xE7). On the +X face the top corners average PV and the corner's three
; probes: block (0 + 0 + 7 + 7) / 4 = 3 at TR, TL and 0 at BL, BR (smooth per corner); the sky
; levels there are 7, 7, 0, 0, which a face flattens to their truncated average 3: 0x30 / 0x33.
test_mesh_light_packed:
    push    rbp
    mov     rbp, rsp
    call    world_clear
    SETB    5, 5, 5, STONE
    lea     rdi, [light_cells]
    mov     ecx, WORLD_VOLUME
    xor     eax, eax
    rep     stosb
    lea     rsi, [light_cells]
    mov     edx, 4                      ; z 4..6
.lz:
    mov     ecx, 4                      ; x 4..6
.lx:
    mov     eax, edx
    shl     eax, 8
    or      eax, ecx
    or      eax, 6 << 16                ; y = 6
    mov     byte [rsi + rax], 0xE7
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
    call    light_full
    call    world_clear
    xor     eax, eax
    pop     rbp
    ret
.fail:
    call    light_full
    call    world_clear
    mov     eax, 1
    pop     rbp
    ret
