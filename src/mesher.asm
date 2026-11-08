; mesher.asm - chunk mesher: one VERTEX quad (4 vertices) per visible face. Full cubes get per-vertex
; ambient occlusion (baked into the vertex colour) and smooth light (block light averaged per
; corner, one sky level per face); shaped blocks (slabs, stairs, doors, ladders, torches, fences,
; panes) are emitted box by box from shapes.asm with one flat light per face. Vertex positions are
; in 1/16 block (render.asm scales the chunk pass by 1/16); VERTEX.pad carries the packed light
; (sky << 4 | block) that texture unit 1 turns into a colour through the light map.
%include "common.inc"
default rel

global mesh_chunk, mesh_scratch, mesh_face_uv

extern world_get, world_is_opaque, block_flags, block_tiles, block_shape
extern shape_boxes, light_get

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

; texture mapping per face: axis of u, 1 = u runs backwards (16 - c), axis of v, same for v
; (axis 0 x, 1 y, 2 z; c = cell-relative coordinate in 1/16 block)
face_uv_tab:
    db 2, 1, 1, 1                           ; +X: u = 16 - z, v = 16 - y
    db 2, 0, 1, 1                           ; -X: u = z,      v = 16 - y
    db 0, 0, 2, 0                           ; +Y: u = x,      v = z
    db 0, 1, 2, 0                           ; -Y: u = 16 - x, v = z
    db 0, 0, 1, 1                           ; +Z: u = x,      v = 16 - y
    db 0, 1, 1, 1                           ; -Z: u = 16 - x, v = 16 - y

; per face: index of the box byte holding the face's plane coordinate, and the cell-boundary value
face_plane:
    db 3, 16                                ; +X: x1 == 16
    db 0, 0                                 ; -X: x0 == 0
    db 4, 16                                ; +Y: y1 == 16
    db 1, 0                                 ; -Y: y0 == 0
    db 5, 16                                ; +Z: z1 == 16
    db 2, 0                                 ; -Z: z0 == 0

b_cube: db 0, 0, 0, 16, 16, 16
align 4
recip:  dd 0, 65536, 32768, 21846, 16384    ; 65536 / n, rounded up, n = 1..4 light samples

section .bss
alignb 16
mesh_scratch: resb MAX_CHUNK_VERTS * VERTEX_SIZE

section .text

; stack locals, addressed from rbp so the helper routines below share the frame
%define L_OX    0
%define L_OY    4
%define L_OZ    8
%define L_BX    12                      ; block being meshed
%define L_BY    16
%define L_BZ    20
%define L_OUT0  24                      ; qword: start of the output
%define L_AO    32                      ; 4 dwords: ao level 0..3 of each corner of the face
%define L_LT    48                      ; 4 dwords: packed light of each corner
%define L_PV    64                      ; 3 dwords: block + normal
%define L_SV    76                      ; 3 dwords: corner sign per axis (0 on normal axis)
%define L_TP    88                      ; 3 dwords: probe position
%define L_P1    100                     ; probe results: -1 opaque, else the packed light
%define L_P2    104
%define L_P3    108
%define L_TILE  112
%define L_PVL   116                     ; packed light of PV
%define L_BOXP  120                     ; qword: the box being emitted
%define L_NBOX  128
%define L_BOXI  132
%define L_CELLL 136                     ; packed light of the shaped block's own cell
%define L_J     140                     ; emit_face: vertex counter
%define L_K     144                     ; emit_face: corner of the vertex
%define L_BOXES 152                     ; 6 * MAX_SHAPE_BOXES bytes of shape boxes
%define LOCALS  216                     ; 5 pushes (40) + 216 = 256 = 0 mod 16
%define FRAME   (40 + LOCALS)
%define V(off)  rbp + (off) - FRAME

; PROBE: eax = -1 when the cell at L_TP is opaque, else its packed light
%macro PROBE 0
    mov     edi, [V(L_TP)]
    mov     esi, [V(L_TP) + 4]
    mov     edx, [V(L_TP) + 8]
    call    world_is_opaque
    test    eax, eax
    jz      %%open
    mov     eax, -1
    jmp     %%done
%%open:
    mov     edi, [V(L_TP)]
    mov     esi, [V(L_TP) + 4]
    mov     edx, [V(L_TP) + 8]
    call    light_get
%%done:
%endmacro

; ACC probe: add the probe's sky (r8d) and block (r9d) light and count it (r10d) unless it is opaque
%macro ACC 1
    mov     eax, [V(%1)]
    test    eax, eax
    js      %%skip
    mov     ecx, eax
    shr     ecx, 4
    add     r8d, ecx
    and     eax, 15
    add     r9d, eax
    inc     r10d
%%skip:
%endmacro

; mesh_chunk(edi cx, esi cy, edx cz, rcx out) -> eax vertex count
; The output holds at most MAX_CHUNK_VERTS vertices. Cubes always fit; a shaped block is skipped
; when it could leave too little room for the cubes still to come.
; rbx = write pointer, r12d = block index in chunk (ly*256 + lz*16 + lx),
; r13d = face, r14d = block id, r15d = corner / first corner of the quad
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
    mov     [V(L_OUT0)], rcx
    shl     edi, 4
    shl     esi, 4
    shl     edx, 4
    mov     [V(L_OX)], edi
    mov     [V(L_OY)], esi
    mov     [V(L_OZ)], edx
    xor     r12d, r12d

.block_loop:
    cmp     r12d, CHUNK * CHUNK * CHUNK
    jae     .done
    mov     eax, r12d
    and     eax, 15
    add     eax, [V(L_OX)]
    mov     [V(L_BX)], eax
    mov     edx, r12d
    shr     edx, 4
    and     edx, 15
    add     edx, [V(L_OZ)]
    mov     [V(L_BZ)], edx
    mov     esi, r12d
    shr     esi, 8
    add     esi, [V(L_OY)]
    mov     [V(L_BY)], esi
    mov     edi, eax
    call    world_get
    mov     r14d, eax
    test    eax, eax
    jz      .next_block
    movzx   eax, byte [block_shape + r14]
    cmp     eax, SHAPE_CUBE
    je      .cube
    test    eax, eax
    jz      .next_block                 ; SHAPE_NONE: fire.asm draws the flames
    jmp     .shaped

; ---- full cube: culled faces, smooth light and ambient occlusion per corner ------------------
.cube:
    xor     r13d, r13d

.face_loop:
    cmp     r13d, 6
    jae     .next_block
    call    face_pv                     ; PV = block + normal; neighbour = world_get(PV)
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
    call    face_tile
    mov     [V(L_TILE)], eax
    mov     edi, [V(L_PV)]
    mov     esi, [V(L_PV) + 4]
    mov     edx, [V(L_PV) + 8]
    call    light_get                   ; the light the face sees
    mov     [V(L_PVL)], eax

    xor     r15d, r15d
.corner_loop:
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
    mov     [V(L_SV) + rdx*4], eax
    inc     edx
    cmp     edx, 3
    jb      .sv_loop
    ; TP = PV
    mov     eax, [V(L_PV)]
    mov     [V(L_TP)], eax
    mov     eax, [V(L_PV) + 4]
    mov     [V(L_TP) + 4], eax
    mov     eax, [V(L_PV) + 8]
    mov     [V(L_TP) + 8], eax
    ; side2: PV + s[i2]*e_i2
    lea     rax, [face_axes]
    movzx   ecx, byte [rax + r13*2 + 1]
    mov     eax, [V(L_SV) + rcx*4]
    add     [V(L_TP) + rcx*4], eax
    PROBE
    mov     [V(L_P2)], eax
    ; corner: PV + a + b
    lea     rax, [face_axes]
    movzx   ecx, byte [rax + r13*2]
    mov     eax, [V(L_SV) + rcx*4]
    add     [V(L_TP) + rcx*4], eax
    PROBE
    mov     [V(L_P3)], eax
    ; side1: back off b
    lea     rax, [face_axes]
    movzx   ecx, byte [rax + r13*2 + 1]
    mov     eax, [V(L_SV) + rcx*4]
    sub     [V(L_TP) + rcx*4], eax
    PROBE
    mov     [V(L_P1)], eax

    ; ---- ambient occlusion: the sign bit of a probe is its "opaque" flag ----
    mov     ecx, [V(L_P2)]
    mov     edx, [V(L_P3)]
    mov     r8d, eax
    shr     r8d, 31                     ; side1 opaque
    mov     r9d, ecx
    shr     r9d, 31                     ; side2 opaque
    shr     edx, 31                     ; corner opaque
    mov     r10d, 3
    test    r8d, r9d                    ; side1 && side2 -> darkest
    jnz     .ao_dark
    sub     r10d, r8d
    sub     r10d, r9d
    sub     r10d, edx
    jmp     .ao_store
.ao_dark:
    xor     r10d, r10d
    mov     dword [V(L_P3)], -1         ; a closed corner passes no light either
.ao_store:
    mov     [V(L_AO) + r15*4], r10d

    ; ---- smooth light: PV plus every open probe, sky and block averaged apart (truncated) ----
    mov     eax, [V(L_PVL)]
    mov     r8d, eax
    shr     r8d, 4                      ; sky sum
    and     eax, 15
    mov     r9d, eax                    ; block sum
    mov     r10d, 1                     ; samples
    ACC     L_P1
    ACC     L_P2
    ACC     L_P3
    lea     rdx, [recip]
    mov     ecx, [rdx + r10*4]          ; 65536 / samples, rounded up: exact for sums <= 60
    imul    r8d, ecx
    shr     r8d, 16                     ; sky = sum / samples, truncated
    imul    r9d, ecx
    shr     r9d, 16                     ; block
    shl     r8d, 4
    or      r8d, r9d
    mov     [V(L_LT) + r15*4], r8d
    inc     r15d
    cmp     r15d, 4
    jb      .corner_loop

    ; ---- one sky level per face: the sky nibble is the high nibble of the light-map index, so
    ; corners with different sky levels would make the interpolated index sweep every block level
    ; in between (colours of unrelated light-map entries); the block nibble changes by single steps
    ; and blends cleanly. Every corner takes the truncated average of the four sky levels.
    mov     eax, [V(L_LT)]
    shr     eax, 4
    mov     ecx, [V(L_LT) + 4]
    shr     ecx, 4
    add     eax, ecx
    mov     ecx, [V(L_LT) + 8]
    shr     ecx, 4
    add     eax, ecx
    mov     ecx, [V(L_LT) + 12]
    shr     ecx, 4
    add     eax, ecx
    shr     eax, 2
    shl     eax, 4
    xor     ecx, ecx
.sky_flat:
    mov     edx, [V(L_LT) + rcx*4]
    and     edx, 15
    or      edx, eax
    mov     [V(L_LT) + rcx*4], edx
    inc     ecx
    cmp     ecx, 4
    jb      .sky_flat

    ; ---- diagonal flip: start corner 1 if ao1 + ao3 > ao0 + ao2 ----
    mov     eax, [V(L_AO) + 4]
    add     eax, [V(L_AO) + 12]
    mov     ecx, [V(L_AO)]
    add     ecx, [V(L_AO) + 8]
    xor     r15d, r15d                  ; r15d = start corner
    cmp     eax, ecx
    jle     .no_flip
    mov     r15d, 1
.no_flip:
    lea     rsi, [b_cube]
    call    emit_face

.next_face:
    inc     r13d
    jmp     .face_loop

; ---- shaped block: every box of shape_boxes, flat light, no occlusion shading ----------------
.shaped:
    ; room check: this block (at most MAX_SHAPE_BOXES * 24 vertices) plus a full cube for every
    ; block still to come must fit the output
    mov     eax, CHUNK * CHUNK * CHUNK - 1
    sub     eax, r12d
    imul    eax, eax, 24 * VERTEX_SIZE
    add     eax, MAX_SHAPE_BOXES * 24 * VERTEX_SIZE
    mov     rcx, rbx
    sub     rcx, [V(L_OUT0)]
    add     rcx, rax
    cmp     rcx, MAX_CHUNK_VERTS * VERTEX_SIZE
    ja      .next_block
    mov     edi, [V(L_BX)]
    mov     esi, [V(L_BY)]
    mov     edx, [V(L_BZ)]
    call    light_get
    mov     [V(L_CELLL)], eax
    mov     edi, r14d
    mov     esi, [V(L_BX)]
    mov     edx, [V(L_BY)]
    mov     ecx, [V(L_BZ)]
    lea     r8, [V(L_BOXES)]
    mov     r9d, BOXES_RENDER
    call    shape_boxes
    mov     [V(L_NBOX)], eax
    mov     dword [V(L_BOXI)], 0

.box_loop:
    mov     eax, [V(L_BOXI)]
    cmp     eax, [V(L_NBOX)]
    jae     .next_block
    lea     rsi, [rax + rax*2]
    lea     rsi, [V(L_BOXES) + rsi*2]   ; box i = L_BOXES + 6 * i
    mov     [V(L_BOXP)], rsi
    xor     r13d, r13d

.sface:
    cmp     r13d, 6
    jae     .next_box
    lea     rax, [face_plane]
    movzx   ecx, byte [rax + r13*2]     ; box byte holding the face's plane coordinate
    movzx   edx, byte [rax + r13*2 + 1] ; its value on the cell boundary
    mov     rsi, [V(L_BOXP)]
    cmp     byte [rsi + rcx], dl
    jne     .internal
    ; the face lies on the cell boundary: an opaque neighbour hides it, else it sees its light
    call    face_pv
    call    world_get
    movzx   ecx, byte [block_flags + rax]
    test    cl, FLAG_OPAQUE
    jnz     .next_sface
    mov     edi, [V(L_PV)]
    mov     esi, [V(L_PV) + 4]
    mov     edx, [V(L_PV) + 8]
    call    light_get
    jmp     .flat
.internal:
    mov     eax, [V(L_CELLL)]           ; inside the cell: the cell's own light
.flat:
    mov     ecx, 3
    mov     [V(L_AO)], ecx
    mov     [V(L_AO) + 4], ecx
    mov     [V(L_AO) + 8], ecx
    mov     [V(L_AO) + 12], ecx
    mov     [V(L_LT)], eax
    mov     [V(L_LT) + 4], eax
    mov     [V(L_LT) + 8], eax
    mov     [V(L_LT) + 12], eax
    call    face_tile
    mov     [V(L_TILE)], eax
    xor     r15d, r15d
    mov     rsi, [V(L_BOXP)]
    call    emit_face
.next_sface:
    inc     r13d
    jmp     .sface
.next_box:
    inc     dword [V(L_BOXI)]
    jmp     .box_loop

.next_block:
    inc     r12d
    jmp     .block_loop

.done:
    sub     rbx, [V(L_OUT0)]
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

; face_pv: L_PV = block + normal of face r13d; edi, esi, edx = its coordinates
face_pv:
    lea     rax, [face_normals]
    lea     ecx, [r13 + r13*2]
    movsx   edi, byte [rax + rcx]
    add     edi, [V(L_BX)]
    mov     [V(L_PV)], edi
    movsx   esi, byte [rax + rcx + 1]
    add     esi, [V(L_BY)]
    mov     [V(L_PV) + 4], esi
    movsx   edx, byte [rax + rcx + 2]
    add     edx, [V(L_BZ)]
    mov     [V(L_PV) + 8], edx
    ret

; face_tile -> eax: atlas tile of face r13d of block r14d (block_tiles slot: top, side or bottom)
face_tile:
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
    ret

; emit_face(rsi box, r13d face, r15d first corner): the 4 vertices of one face of a box at rbx.
; The box is 6 bytes x0,y0,z0,x1,y1,z1 in 1/16 block relative to the block at L_BX..L_BZ. Corner k
; carries the ao level L_AO[k] and the packed light L_LT[k]; the tile is L_TILE. The vertices go out
; starting at corner r15d (diagonal flip), counter-clockwise seen from outside. rbx advances.
; Clobbers rax, rcx, rdx, rsi, rdi, r8-r11.
emit_face:
    mov     [V(L_BOXP)], rsi
    mov     dword [V(L_J)], 0
.vertex:
    mov     eax, [V(L_J)]
    add     eax, r15d
    and     eax, 3                      ; k
    mov     [V(L_K)], eax
    mov     ecx, eax
    mov     eax, r13d
    shl     eax, 2
    add     eax, ecx
    lea     eax, [rax + rax*2]
    lea     rdi, [face_corners]
    add     rdi, rax                    ; the corner's lo/hi bits per axis
    mov     rsi, [V(L_BOXP)]
    movzx   eax, byte [rdi]
    lea     eax, [rax + rax*2]          ; bit * 3: the lo or hi byte of the x pair
    movzx   r8d, byte [rsi + rax]       ; cx
    movzx   eax, byte [rdi + 1]
    lea     eax, [rax + rax*2 + 1]
    movzx   r9d, byte [rsi + rax]       ; cy
    movzx   eax, byte [rdi + 2]
    lea     eax, [rax + rax*2 + 2]
    movzx   r10d, byte [rsi + rax]      ; cz
    mov     eax, [V(L_BX)]
    shl     eax, 4
    add     eax, r8d
    mov     [rbx + VERTEX.x], ax
    mov     eax, [V(L_BY)]
    shl     eax, 4
    add     eax, r9d
    mov     [rbx + VERTEX.y], ax
    mov     eax, [V(L_BZ)]
    shl     eax, 4
    add     eax, r10d
    mov     [rbx + VERTEX.z], ax
    ; texcoords: tile origin + the mapped offset inside the tile
    mov     edi, r13d
    mov     esi, r8d
    mov     edx, r9d
    mov     ecx, r10d
    call    mesh_face_uv                ; eax = u, edx = v
    mov     ecx, [V(L_TILE)]
    mov     esi, ecx
    and     ecx, 15
    shl     ecx, 8
    add     eax, ecx
    mov     [rbx + VERTEX.u], ax
    shr     esi, 4
    shl     esi, 8
    add     edx, esi
    mov     [rbx + VERTEX.v], dx
    ; light and colour
    mov     ecx, [V(L_K)]
    mov     eax, [V(L_LT) + rcx*4]
    mov     [rbx + VERTEX.pad], ax
    mov     eax, [V(L_AO) + rcx*4]
    lea     rdi, [face_shade]
    lea     eax, [r13*4 + rax]
    movzx   eax, byte [rdi + rax]
    imul    eax, eax, 0x010101
    or      eax, 0xFF000000
    mov     [rbx + VERTEX.r], eax
    add     rbx, VERTEX_SIZE
    inc     dword [V(L_J)]
    cmp     dword [V(L_J)], 4
    jb      .vertex
    ret

; mesh_face_uv(edi face, esi x, edx y, ecx z) -> eax u, edx v
; The texel offsets (1/16 px, 1..255) inside the atlas tile of the cell-relative point (x, y, z in
; 1/16 block, 0..16) on face `face` (0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z):
;   +X u = 16 - z, v = 16 - y    -X u = z, v = 16 - y     +Y u = x, v = z
;   -Y u = 16 - x, v = z         +Z u = x, v = 16 - y     -Z u = 16 - x, v = 16 - y
; each scaled by 16 and clamped to [1, 255]: a whole 16 x 16 face covers the tile inset by one unit.
; Leaf: clobbers rax, rdx, r8-r11.
mesh_face_uv:
    lea     r8, [face_uv_tab]
    lea     r8, [r8 + rdi*4]
    movzx   eax, byte [r8]              ; axis of u
    mov     r9d, esi
    cmp     eax, 1
    cmove   r9d, edx
    cmp     eax, 2
    cmove   r9d, ecx                    ; r9d = that coordinate
    mov     eax, 16
    sub     eax, r9d
    cmp     byte [r8 + 1], 0
    cmove   eax, r9d                    ; not flipped: the coordinate itself
    shl     eax, 4
    mov     r10d, 1
    cmp     eax, r10d
    cmovl   eax, r10d
    mov     r10d, 255
    cmp     eax, r10d
    cmovg   eax, r10d                   ; u
    movzx   r11d, byte [r8 + 2]         ; axis of v
    mov     r9d, esi
    cmp     r11d, 1
    cmove   r9d, edx
    cmp     r11d, 2
    cmove   r9d, ecx
    mov     edx, 16
    sub     edx, r9d
    cmp     byte [r8 + 3], 0
    cmove   edx, r9d
    shl     edx, 4
    mov     r10d, 1
    cmp     edx, r10d
    cmovl   edx, r10d
    mov     r10d, 255
    cmp     edx, r10d
    cmovg   edx, r10d                   ; v
    ret
