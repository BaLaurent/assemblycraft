; test_mesher.asm - vertex-count tests for mesh_chunk.
%include "common.inc"
default rel

global test_mesh_single_block, test_mesh_adjacent_opaque, test_mesh_adjacent_leaves
global test_mesh_adjacent_glass, test_mesh_chunk_boundary

extern world_clear, world_set
extern mesh_chunk, mesh_scratch

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
