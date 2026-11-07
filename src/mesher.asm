; mesher.asm - chunk mesher: one VERTEX quad (4 vertices) per visible block face,
; with per-vertex ambient occlusion baked into the vertex colour.
%include "common.inc"
default rel

global mesh_chunk, mesh_scratch

extern world_get, world_is_opaque, block_flags, block_tiles

section .rodata

; face order: 0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z
face_normals:
    db  1, 0, 0
    db -1, 0, 0
    db  0, 1, 0
    db  0,-1, 0
    db  0, 0, 1
    db  0, 0,-1

; the two axes (i1 < i2) perpendicular to each face normal
face_axes:
    db 1, 2
    db 1, 2
    db 0, 2
    db 0, 2
    db 0, 1
    db 0, 1

; corners BL, BR, TR, TL, counter-clockwise seen from outside
face_corners:
    db 1,0,1,  1,0,0,  1,1,0,  1,1,1        ; +X
    db 0,0,0,  0,0,1,  0,1,1,  0,1,0        ; -X
    db 0,1,1,  1,1,1,  1,1,0,  0,1,0        ; +Y
    db 1,0,1,  0,0,1,  0,0,0,  1,0,0        ; -Y
    db 0,0,1,  1,0,1,  1,1,1,  0,1,1        ; +Z
    db 1,0,0,  0,0,0,  0,1,0,  1,1,0        ; -Z

; brightness shade[d][ao]
face_shade:
    db  77,  99, 122, 153                   ; +X
    db  77,  99, 122, 153                   ; -X
    db 128, 166, 204, 255                   ; +Y
    db  64,  83, 102, 128                   ; -Y
    db 102, 133, 163, 204                   ; +Z
    db 102, 133, 163, 204                   ; -Z

section .bss
alignb 16
mesh_scratch: resb MAX_CHUNK_VERTS * VERTEX_SIZE

section .text

; stack locals (rsp-relative)
%define L_OX    0
%define L_OY    4
%define L_OZ    8
%define L_BX    12
%define L_BY    16
%define L_BZ    20
%define L_OUT0  24                      ; qword
%define L_AO    32                      ; 4 dwords
%define L_PV    48                      ; 3 dwords: block + normal
%define L_SV    60                      ; 3 dwords: corner sign per axis (0 on normal axis)
%define L_TP    72                      ; 3 dwords: probe position
%define L_S1    84
%define L_S2    88
%define L_S3    92
%define L_TILE  96
%define LOCALS  104                     ; 5 pushes (40) + 104 = 144 = 0 mod 16

; call world_is_opaque on the position in L_TP
%macro PROBE 0
    mov     edi, [rsp + L_TP]
    mov     esi, [rsp + L_TP + 4]
    mov     edx, [rsp + L_TP + 8]
    call    world_is_opaque
%endmacro

; mesh_chunk(edi cx, esi cy, edx cz, rcx out) -> eax vertex count
; rbx = write pointer, r12d = block index in chunk (ly*256 + lz*16 + lx),
; r13d = face, r14d = block id, r15d = corner / vertex counter
mesh_chunk:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, LOCALS
    mov     rbx, rcx
    mov     [rsp + L_OUT0], rcx
    shl     edi, 4
    shl     esi, 4
    shl     edx, 4
    mov     [rsp + L_OX], edi
    mov     [rsp + L_OY], esi
    mov     [rsp + L_OZ], edx
    xor     r12d, r12d

.block_loop:
    cmp     r12d, CHUNK * CHUNK * CHUNK
    jae     .done
    mov     eax, r12d
    and     eax, 15
    add     eax, [rsp + L_OX]
    mov     [rsp + L_BX], eax
    mov     edx, r12d
    shr     edx, 4
    and     edx, 15
    add     edx, [rsp + L_OZ]
    mov     [rsp + L_BZ], edx
    mov     esi, r12d
    shr     esi, 8
    add     esi, [rsp + L_OY]
    mov     [rsp + L_BY], esi
    mov     edi, eax
    call    world_get
    mov     r14d, eax
    test    eax, eax
    jz      .next_block
    xor     r13d, r13d

.face_loop:
    cmp     r13d, 6
    jae     .next_block
    ; PV = block + normal; neighbour = world_get(PV)
    lea     rax, [face_normals]
    lea     ecx, [r13 + r13*2]
    movsx   edi, byte [rax + rcx]
    add     edi, [rsp + L_BX]
    mov     [rsp + L_PV], edi
    movsx   esi, byte [rax + rcx + 1]
    add     esi, [rsp + L_BY]
    mov     [rsp + L_PV + 4], esi
    movsx   edx, byte [rax + rcx + 2]
    add     edx, [rsp + L_BZ]
    mov     [rsp + L_PV + 8], edx
    call    world_get
    test    eax, eax
    jz      .visible
    movzx   ecx, byte [block_flags + rax]
    test    cl, FLAG_OPAQUE
    jnz     .next_face
    cmp     eax, r14d
    jne     .visible
    test    byte [block_flags + r14], FLAG_CULL_SAME
    jnz     .next_face

.visible:
    ; ---- tile -> L_TILE ----
    mov     eax, 1
    cmp     r13d, 2
    jne     .not_top
    xor     eax, eax
.not_top:
    cmp     r13d, 3
    jne     .slot_done
    mov     eax, 2
.slot_done:
    lea     ecx, [r14 + r14*2]
    add     ecx, eax
    movzx   eax, byte [block_tiles + rcx]
    mov     [rsp + L_TILE], eax

    ; ---- ambient occlusion of the four corners ----
    xor     r15d, r15d
.ao_loop:
    lea     rsi, [face_corners]
    mov     eax, r13d
    shl     eax, 2
    add     eax, r15d
    lea     eax, [rax + rax*2]
    add     rsi, rax                    ; this corner's offsets
    lea     rdi, [face_normals]
    lea     eax, [r13 + r13*2]
    add     rdi, rax                    ; this face's normal
    xor     edx, edx
.sv_loop:
    xor     eax, eax
    cmp     byte [rdi + rdx], 0
    jne     .sv_store                   ; normal axis -> 0
    movzx   eax, byte [rsi + rdx]
    lea     eax, [rax*2 - 1]
.sv_store:
    mov     [rsp + L_SV + rdx*4], eax
    inc     edx
    cmp     edx, 3
    jb      .sv_loop
    ; TP = PV
    mov     eax, [rsp + L_PV]
    mov     [rsp + L_TP], eax
    mov     eax, [rsp + L_PV + 4]
    mov     [rsp + L_TP + 4], eax
    mov     eax, [rsp + L_PV + 8]
    mov     [rsp + L_TP + 8], eax
    ; side2: PV + s[i2]*e_i2
    lea     rax, [face_axes]
    movzx   ecx, byte [rax + r13*2 + 1]
    mov     eax, [rsp + L_SV + rcx*4]
    add     [rsp + L_TP + rcx*4], eax
    PROBE
    mov     [rsp + L_S2], eax
    ; corner: PV + a + b
    lea     rax, [face_axes]
    movzx   ecx, byte [rax + r13*2]
    mov     eax, [rsp + L_SV + rcx*4]
    add     [rsp + L_TP + rcx*4], eax
    PROBE
    mov     [rsp + L_S3], eax
    ; side1: back off b
    lea     rax, [face_axes]
    movzx   ecx, byte [rax + r13*2 + 1]
    mov     eax, [rsp + L_SV + rcx*4]
    sub     [rsp + L_TP + rcx*4], eax
    PROBE
    mov     ecx, [rsp + L_S2]
    mov     edx, [rsp + L_S3]
    mov     [rsp + L_S1], eax
    test    eax, ecx                    ; side1 && side2 -> darkest
    mov     eax, 3
    jnz     .ao_dark
    sub     eax, [rsp + L_S1]
    sub     eax, ecx
    sub     eax, edx
    jmp     .ao_store
.ao_dark:
    xor     eax, eax
.ao_store:
    mov     [rsp + L_AO + r15*4], eax
    inc     r15d
    cmp     r15d, 4
    jb      .ao_loop

    ; ---- diagonal flip: start corner 1 if ao1+ao3 > ao0+ao2 ----
    mov     eax, [rsp + L_AO + 4]
    add     eax, [rsp + L_AO + 12]
    mov     ecx, [rsp + L_AO]
    add     ecx, [rsp + L_AO + 8]
    xor     r15d, r15d                  ; r15d = start corner
    cmp     eax, ecx
    jle     .no_flip
    mov     r15d, 1
.no_flip:

    ; ---- emit 4 vertices, corners start, start+1, ... (mod 4) ----
    xor     r8d, r8d                    ; j
.emit_loop:
    lea     ecx, [r15 + r8]
    and     ecx, 3                      ; k
    ; corner offsets pointer
    lea     rsi, [face_corners]
    mov     eax, r13d
    shl     eax, 2
    add     eax, ecx
    lea     eax, [rax + rax*2]
    add     rsi, rax
    movzx   eax, byte [rsi]
    add     eax, [rsp + L_BX]
    mov     [rbx + VERTEX.x], ax
    movzx   eax, byte [rsi + 1]
    add     eax, [rsp + L_BY]
    mov     [rbx + VERTEX.y], ax
    movzx   eax, byte [rsi + 2]
    add     eax, [rsp + L_BZ]
    mov     [rbx + VERTEX.z], ax
    mov     word [rbx + VERTEX.pad], 0
    ; texcoords
    mov     eax, [rsp + L_TILE]
    mov     edx, eax
    and     eax, 15
    shl     eax, 8
    inc     eax                         ; u0
    shr     edx, 4
    shl     edx, 8
    inc     edx                         ; v0
    lea     esi, [rcx + 1]
    shr     esi, 1
    and     esi, 1                      ; 1 for corners BR, TR
    imul    esi, esi, 254
    add     eax, esi
    mov     [rbx + VERTEX.u], ax
    mov     esi, ecx
    shr     esi, 1
    xor     esi, 1                      ; 1 for corners BL, BR
    imul    esi, esi, 254
    add     edx, esi
    mov     [rbx + VERTEX.v], dx
    ; colour
    mov     esi, [rsp + L_AO + rcx*4]
    lea     rdi, [face_shade]
    lea     eax, [r13*4 + rsi]
    movzx   eax, byte [rdi + rax]
    imul    eax, eax, 0x010101
    or      eax, 0xFF000000
    mov     [rbx + VERTEX.r], eax
    add     rbx, VERTEX_SIZE
    inc     r8d
    cmp     r8d, 4
    jb      .emit_loop

.next_face:
    inc     r13d
    jmp     .face_loop

.next_block:
    inc     r12d
    jmp     .block_loop

.done:
    sub     rbx, [rsp + L_OUT0]
    shr     rbx, 4
    mov     eax, ebx
    add     rsp, LOCALS
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
