; mesher.asm - chunk mesher: one VERTEX quad (4 vertices) per visible face. Full cubes get per-vertex
; ambient occlusion (baked into the vertex colour) and smooth light (block light averaged per
; corner, one sky level per face); shaped blocks (slabs, stairs, doors, ladders, torches, fences,
; panes, beds, snow, cacti) are emitted box by box from shapes.asm with one flat light per face;
; tall grass is two crossed diagonal quads; water, ice and lava are drawn in a second, translucent range.
; Vertex positions are in 1/16 block RELATIVE TO THE CHUNK (0..256; render.asm translates each chunk
; and scales by 1/16); VERTEX.pad carries the packed light (sky << 4 | block) that texture unit 1
; turns into a colour through the light map.
;
; The mesher never touches the world while it works: mesh_chunk first copies the blocks and the light
; of the chunk and its 26 neighbours into two 18 x 18 x 18 pads (index (py*18 + pz)*18 + px, p = chunk
; local coordinate + 1) and every neighbour, occlusion and light probe reads the pads.
%include "common.inc"
default rel

global mesh_chunk, mesh_scratch, mesh_face_uv

extern world_chunk, world_origin_x, world_origin_z
extern block_flags, block_tiles, block_shape
extern shape_boxes

%define PAD     18                      ; the padded copy: the chunk plus a one-cell border
%define PAD_Z   18                      ; pad index step along z
%define PAD_Y   324                     ; ... along y
%define PAD_N   5832                    ; PAD ^ 3

section .rodata

; face order: 0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z
face_normals:
    db  1, 0, 0
    db -1, 0, 0
    db  0, 1, 0
    db  0,-1, 0
    db  0, 0, 1
    db  0, 0,-1

; pad index step to the neighbour in front of each face, and along each axis (x, y, z)
align 4
face_delta:
    dd  1, -1, PAD_Y, -PAD_Y, PAD_Z, -PAD_Z
pad_stride:
    dd  1, PAD_Y, PAD_Z

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

; pad rows: pad coordinate 0..17 -> which neighbour chunk (0 below, 1 this one, 2 above) and the
; chunk-local coordinate read there (15 for the border below, 0..15 inside, 0 for the border above)
pad_class: db 0, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 2
pad_loc:   db 15, 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15, 0

; tall grass: two vertical diagonal quads, each in both windings (the chunk pass culls back faces).
; Per vertex: x, y, z in 1/16 block inside the cell, u, v inside the tile (the cube inset 1..255)
cross_verts:
    db  0,  0,  0,   1, 255                 ; A front: BL, BR, TR, TL
    db 16,  0, 16, 255, 255
    db 16, 16, 16, 255,   1
    db  0, 16,  0,   1,   1
    db 16,  0, 16, 255, 255                 ; A back: BR, BL, TL, TR
    db  0,  0,  0,   1, 255
    db  0, 16,  0,   1,   1
    db 16, 16, 16, 255,   1
    db 16,  0,  0,   1, 255                 ; B front
    db  0,  0, 16, 255, 255
    db  0, 16, 16, 255,   1
    db 16, 16,  0,   1,   1
    db  0,  0, 16, 255, 255                 ; B back
    db 16,  0,  0,   1, 255
    db 16, 16,  0,   1,   1
    db  0, 16, 16, 255,   1

section .bss
alignb 16
mesh_scratch: resb MAX_CHUNK_VERTS * VERTEX_SIZE
pad_blocks:   resb PAD_N
pad_light:    resb PAD_N

section .text

; stack locals, addressed from rbp so the helper routines below share the frame
%define L_WX0   0                       ; the chunk's minimum corner in the local frame (the
%define L_WY0   4                       ; coordinates world_get / shape_boxes take)
%define L_WZ0   8
%define L_BX    12                      ; block being meshed, chunk-local 0..15
%define L_BY    16
%define L_BZ    20
%define L_OUT0  24                      ; qword: start of the output
%define L_AO    32                      ; 4 dwords: ao level 0..3 of each corner of the face
%define L_LT    48                      ; 4 dwords: packed light of each corner
%define L_PI    64                      ; pad index of the block
%define L_PVI   68                      ; pad index of the cell in front of the face
%define L_SV    72                      ; 3 dwords: corner sign per axis (0 on the normal axis)
%define L_TPI   84                      ; pad index of the probe
%define L_P1    88                      ; probe results: -1 opaque, else the packed light
%define L_P2    92
%define L_P3    96
%define L_TILE  100
%define L_PVL   104                     ; packed light of PV
%define L_BOXP  112                     ; qword: the box being emitted
%define L_NBOX  120
%define L_BOXI  124
%define L_CELLL 128                     ; packed light of the shaped block's own cell
%define L_J     132                     ; emit_face: vertex counter
%define L_K     136                     ; emit_face: corner of the vertex
%define L_CHUNK 144                     ; qword: the chunk's block bytes
%define L_ACX   152                     ; absolute chunk coordinates
%define L_ACY   156
%define L_ACZ   160
%define L_PASS  164                     ; 0 opaque and alpha-tested blocks, 1 translucent blocks
%define L_NTRANS 168                    ; translucent cells met so far in pass 0
%define L_TSTART 172                    ; first translucent vertex
%define L_WHITE 176                     ; 1: emit_face writes colour 0xFFFFFFFF (water, ice)
%define L_WBOX  180                     ; 6 bytes: the box of a translucent cell
%define L_BOXES 192                     ; 6 * MAX_SHAPE_BOXES bytes of shape boxes
%define LOCALS  248                     ; 5 pushes (40) + 248 = 288 = 0 mod 16
%define FRAME   (40 + LOCALS)
%define V(off)  rbp + (off) - FRAME

; PROBE: eax = -1 when the pad cell L_TPI is opaque, else its packed light
%macro PROBE 0
    mov     ecx, [V(L_TPI)]
    movzx   eax, byte [pad_blocks + rcx]
    test    byte [block_flags + rax], FLAG_OPAQUE
    jz      %%open
    mov     eax, -1
    jmp     %%done
%%open:
    movzx   eax, byte [pad_light + rcx]
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

; mesh_chunk(edi acx, esi acy, edx acz, rcx out) -> eax vertex count, edx first translucent vertex
; The chunk (absolute chunk coordinates) and its 26 neighbours are read through world_chunk; an
; unallocated chunk or an unloaded column reads as AIR with full sky light. Opaque, alpha-tested
; and shaped geometry is written first, the faces of translucent blocks (FLAG_TRANSLUCENT: water,
; ice) after it: vertices [0, edx) draw in the opaque pass, [edx, eax) in the blended pass.
; The output holds at most MAX_CHUNK_VERTS vertices. Cubes, crosses and translucent cells always
; fit (<= 24 vertices each); a shaped block is skipped when it could leave too little room for the
; cells still to come and for the translucent cells already passed.
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
    mov     [V(L_ACX)], edi
    mov     [V(L_ACY)], esi
    mov     [V(L_ACZ)], edx
    xor     eax, eax
    mov     [V(L_TSTART)], eax
    mov     [V(L_NTRANS)], eax
    mov     [V(L_PASS)], eax
    mov     [V(L_WHITE)], eax
    call    world_chunk                 ; edi, esi, edx still hold the chunk
    test    rax, rax
    jz      .done                       ; an unallocated chunk is all AIR
    mov     [V(L_CHUNK)], rax
    mov     eax, [V(L_ACX)]
    shl     eax, 4
    sub     eax, [world_origin_x]
    mov     [V(L_WX0)], eax
    mov     eax, [V(L_ACY)]
    shl     eax, 4
    mov     [V(L_WY0)], eax
    mov     eax, [V(L_ACZ)]
    shl     eax, 4
    sub     eax, [world_origin_z]
    mov     [V(L_WZ0)], eax
    mov     edi, [V(L_ACX)]
    mov     esi, [V(L_ACY)]
    mov     edx, [V(L_ACZ)]
    call    pad_fill

.pass:
    xor     r12d, r12d
.block_loop:
    cmp     r12d, CHUNK * CHUNK * CHUNK
    jae     .pass_end
    mov     rax, [V(L_CHUNK)]
    movzx   r14d, byte [rax + r12]
    test    r14d, r14d
    jz      .next_block
    mov     ecx, [V(L_PASS)]
    test    byte [block_flags + r14], FLAG_TRANSLUCENT
    jnz     .trans_cell
    test    ecx, ecx
    jnz     .next_block                 ; pass 1 draws only the translucent cells
    call    cell_coords
    movzx   eax, byte [block_shape + r14]
    cmp     eax, SHAPE_CUBE
    je      .cube
    test    eax, eax
    jz      .next_block                 ; SHAPE_NONE: fire.asm draws the flames
    cmp     eax, SHAPE_CROSS
    je      .cross
    jmp     .shaped
.trans_cell:
    test    ecx, ecx
    jnz     .water
    inc     dword [V(L_NTRANS)]         ; pass 0 only counts them: their faces come in pass 1
    jmp     .next_block

; ---- full cube: culled faces, smooth light and ambient occlusion per corner ------------------
.cube:
    xor     r13d, r13d

.face_loop:
    cmp     r13d, 6
    jae     .next_block
    call    face_pv                     ; L_PVI = the pad cell in front of the face
    mov     ecx, [V(L_PVI)]
    movzx   eax, byte [pad_blocks + rcx]
    test    eax, eax
    jz      .visible
    test    byte [block_flags + rax], FLAG_OPAQUE
    jnz     .next_face
    cmp     eax, r14d
    jne     .visible
    test    byte [block_flags + r14], FLAG_CULL_SAME
    jnz     .next_face

.visible:
    call    face_tile
    mov     [V(L_TILE)], eax
    mov     ecx, [V(L_PVI)]
    movzx   eax, byte [pad_light + rcx] ; the light the face sees
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
    mov     eax, [V(L_PVI)]
    mov     [V(L_TPI)], eax
    ; side2: PV + s[i2]*e_i2
    lea     rax, [face_axes]
    movzx   ecx, byte [rax + r13*2 + 1]
    mov     eax, [V(L_SV) + rcx*4]
    imul    eax, [pad_stride + rcx*4]
    add     [V(L_TPI)], eax
    PROBE
    mov     [V(L_P2)], eax
    ; corner: PV + a + b
    lea     rax, [face_axes]
    movzx   ecx, byte [rax + r13*2]
    mov     eax, [V(L_SV) + rcx*4]
    imul    eax, [pad_stride + rcx*4]
    add     [V(L_TPI)], eax
    PROBE
    mov     [V(L_P3)], eax
    ; side1: back off b
    lea     rax, [face_axes]
    movzx   ecx, byte [rax + r13*2 + 1]
    mov     eax, [V(L_SV) + rcx*4]
    imul    eax, [pad_stride + rcx*4]
    sub     [V(L_TPI)], eax
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

; ---- tall grass: two crossed diagonal quads, both windings, flat light of its own cell -------
.cross:
    call    emit_cross
    jmp     .next_block

; ---- shaped block: every box of shape_boxes, flat light, no occlusion shading ----------------
.shaped:
    ; room check: this block (at most MAX_SHAPE_BOXES * 24 vertices) plus a full cube for every
    ; block still to come and for every translucent cell already passed (their faces come in
    ; pass 1) must fit the output
    mov     eax, CHUNK * CHUNK * CHUNK - 1
    sub     eax, r12d
    add     eax, [V(L_NTRANS)]
    imul    eax, eax, 24 * VERTEX_SIZE
    add     eax, MAX_SHAPE_BOXES * 24 * VERTEX_SIZE
    mov     rcx, rbx
    sub     rcx, [V(L_OUT0)]
    add     rcx, rax
    cmp     rcx, MAX_CHUNK_VERTS * VERTEX_SIZE
    ja      .next_block
    mov     ecx, [V(L_PI)]
    movzx   eax, byte [pad_light + rcx]
    mov     [V(L_CELLL)], eax
    mov     edi, r14d
    mov     esi, [V(L_WX0)]
    add     esi, [V(L_BX)]
    mov     edx, [V(L_WY0)]
    add     edx, [V(L_BY)]
    mov     ecx, [V(L_WZ0)]
    add     ecx, [V(L_BZ)]
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
    mov     ecx, [V(L_PVI)]
    movzx   eax, byte [pad_blocks + rcx]
    test    byte [block_flags + rax], FLAG_OPAQUE
    jnz     .next_sface
    movzx   eax, byte [pad_light + rcx]
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

; ---- translucent block (pass 1): water, ice and lava, flat light of the cell each face looks into
; A face is culled against an opaque neighbour or a translucent one; a LAVA cell is culled only
; against LAVA (its opaque-looking face stays visible from inside water). The open top of a WATER
; cell (nothing watery above) and of a LAVA cell (no LAVA above) sits at 14/16 of the cell, and so
; does the top edge of its sides.
.water:
    call    cell_coords
    mov     dword [V(L_WBOX)], 0x10000000       ; x0 y0 z0 = 0, x1 = 16
    mov     byte [V(L_WBOX) + 4], 16
    mov     byte [V(L_WBOX) + 5], 16
    cmp     r14d, WATER
    jne     .wnot_water
    mov     ecx, [V(L_PI)]
    movzx   eax, byte [pad_blocks + rcx + PAD_Y]    ; the cell above
    cmp     eax, WATER
    je      .wface_init
    cmp     eax, ICE
    je      .wface_init
    mov     byte [V(L_WBOX) + 4], 14
    jmp     .wface_init
.wnot_water:
    cmp     r14d, LAVA
    jne     .wface_init
    mov     ecx, [V(L_PI)]
    movzx   eax, byte [pad_blocks + rcx + PAD_Y]    ; the cell above
    cmp     eax, LAVA
    je      .wface_init
    mov     byte [V(L_WBOX) + 4], 14
.wface_init:
    mov     dword [V(L_WHITE)], 1
    xor     r13d, r13d
.wface:
    cmp     r13d, 6
    jae     .wdone
    call    face_pv
    mov     ecx, [V(L_PVI)]
    movzx   eax, byte [pad_blocks + rcx]
    test    byte [block_flags + rax], FLAG_OPAQUE
    jnz     .wnext
    test    byte [block_flags + rax], FLAG_TRANSLUCENT
    jz      .wvisible
    cmp     r14d, LAVA
    jne     .wnext                              ; water and ice hide against any translucent cell
    cmp     eax, LAVA
    je      .wnext                              ; lava hides only against lava
.wvisible:
    movzx   eax, byte [pad_light + rcx]
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
    lea     rsi, [V(L_WBOX)]
    call    emit_face
.wnext:
    inc     r13d
    jmp     .wface
.wdone:
    mov     dword [V(L_WHITE)], 0
    jmp     .next_block

.next_block:
    inc     r12d
    jmp     .block_loop

.pass_end:
    cmp     dword [V(L_PASS)], 0
    jne     .done
    mov     rax, rbx                    ; the translucent range starts where pass 0 ended
    sub     rax, [V(L_OUT0)]
    shr     rax, 4
    mov     [V(L_TSTART)], eax
    cmp     dword [V(L_NTRANS)], 0
    je      .done
    mov     dword [V(L_PASS)], 1
    jmp     .pass

.done:
    mov     rax, rbx
    sub     rax, [V(L_OUT0)]
    shr     rax, 4                      ; eax = vertices written
    mov     edx, [V(L_TSTART)]
    add     rsp, LOCALS
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; pad_fill(edi acx, esi acy, edx acz): pad_blocks / pad_light = the chunk and its 26 neighbours.
; Unallocated chunks and unloaded columns read as AIR with sky light 15; the plane below the world
; (acy = 0) reads as AIR with light 0, which is what light_get answers for y < 0.
; Frame: [rsp + 0] 27 chunk pointers (index (dy*3 + dz)*3 + dx, each + 1), [rsp + 216] acx, acy, acz.
pad_fill:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 232
    mov     [rsp + 216], edi
    mov     [rsp + 220], esi
    mov     [rsp + 224], edx
    lea     rdi, [pad_blocks]
    xor     eax, eax
    mov     ecx, PAD_N / 8
    rep     stosq
    lea     rdi, [pad_light]
    mov     rax, 0xF0F0F0F0F0F0F0F0
    mov     ecx, PAD_N / 8
    rep     stosq
    cmp     dword [rsp + 220], 0
    jne     .pointers
    lea     rdi, [pad_light]            ; y = -1: the plane under the world sees no light
    xor     eax, eax
    mov     ecx, PAD_Y / 4
    rep     stosd
.pointers:
    xor     r12d, r12d                  ; index into the pointer array
    xor     r13d, r13d                  ; dy + 1
.ny:
    xor     r14d, r14d                  ; dz + 1
.nz:
    xor     r15d, r15d                  ; dx + 1
.nx:
    mov     esi, [rsp + 220]
    lea     esi, [rsi + r13 - 1]        ; chunk y
    cmp     esi, 15
    ja      .nb_none                    ; below 0 or above 15 (unsigned)
    mov     edi, [rsp + 216]
    lea     edi, [rdi + r15 - 1]
    mov     edx, [rsp + 224]
    lea     edx, [rdx + r14 - 1]
    call    world_chunk
    mov     [rsp + r12*8], rax
    jmp     .nb_next
.nb_none:
    mov     qword [rsp + r12*8], 0
.nb_next:
    inc     r12d
    inc     r15d
    cmp     r15d, 3
    jb      .nx
    inc     r14d
    cmp     r14d, 3
    jb      .nz
    inc     r13d
    cmp     r13d, 3
    jb      .ny

    xor     r12d, r12d                  ; py
.py:
    lea     rax, [pad_class]
    movzx   r13d, byte [rax + r12]      ; dy + 1
    lea     rax, [pad_loc]
    movzx   r14d, byte [rax + r12]      ; chunk-local y
    xor     r15d, r15d                  ; pz
.pz:
    lea     rax, [pad_class]
    movzx   ecx, byte [rax + r15]       ; dz + 1
    lea     rax, [pad_loc]
    movzx   edx, byte [rax + r15]       ; chunk-local z
    mov     esi, r14d
    shl     esi, 8
    shl     edx, 4
    or      esi, edx                    ; esi = offset of the source row in a chunk
    imul    edi, r12d, PAD
    add     edi, r15d
    imul    edi, edi, PAD               ; edi = pad index of the row's px = 0
    lea     eax, [r13 + r13*2]
    add     eax, ecx
    lea     eax, [rax + rax*2]          ; first of the row's three chunk pointers
    mov     r8, [rsp + rax*8]           ; dx = -1
    mov     r9, [rsp + rax*8 + 8]       ; dx = 0
    mov     r10, [rsp + rax*8 + 16]     ; dx = +1
    test    r8, r8
    jz      .no_lo
    movzx   eax, byte [r8 + rsi + 15]
    mov     [pad_blocks + rdi], al
    movzx   eax, byte [r8 + rsi + 15 + 4096]
    mov     [pad_light + rdi], al
.no_lo:
    test    r9, r9
    jz      .no_mid
    movups  xmm0, [r9 + rsi]
    movups  [pad_blocks + rdi + 1], xmm0
    movups  xmm0, [r9 + rsi + 4096]
    movups  [pad_light + rdi + 1], xmm0
.no_mid:
    test    r10, r10
    jz      .no_hi
    movzx   eax, byte [r10 + rsi]
    mov     [pad_blocks + rdi + 17], al
    movzx   eax, byte [r10 + rsi + 4096]
    mov     [pad_light + rdi + 17], al
.no_hi:
    inc     r15d
    cmp     r15d, PAD
    jb      .pz
    inc     r12d
    cmp     r12d, PAD
    jb      .py
    add     rsp, 232
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; cell_coords: L_BX, L_BY, L_BZ (chunk-local) and L_PI (pad index) of the block index r12d
cell_coords:
    mov     eax, r12d
    and     eax, 15
    mov     [V(L_BX)], eax
    mov     edx, r12d
    shr     edx, 4
    and     edx, 15
    mov     [V(L_BZ)], edx
    mov     ecx, r12d
    shr     ecx, 8
    mov     [V(L_BY)], ecx
    imul    ecx, ecx, PAD_Y
    imul    edx, edx, PAD_Z
    add     ecx, edx
    lea     eax, [rax + rcx + PAD_Y + PAD_Z + 1]
    mov     [V(L_PI)], eax
    ret

; face_pv: L_PVI = pad index of the cell in front of face r13d of the block at L_PI
face_pv:
    mov     eax, [V(L_PI)]
    lea     rcx, [face_delta]
    add     eax, [rcx + r13*4]
    mov     [V(L_PVI)], eax
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
    movzx   eax, word [block_tiles + rcx*2]
    ret

; emit_cross: the 16 vertices of the cross-shaped block r14d at L_BX..L_BZ (pad index L_PI): two
; vertical diagonal quads in both windings. Flat light of the block's own cell, the tile of its
; side slot, colour 0xFFFFFFFF. rbx advances. Clobbers rax, rcx, rdx, rsi, rdi, r8-r11.
emit_cross:
    mov     ecx, [V(L_PI)]
    movzx   eax, byte [pad_light + rcx]
    lea     edx, [r14 + r14*2]
    movzx   edx, word [block_tiles + rdx*2 + 2]
    mov     r8d, edx
    and     r8d, 15
    shl     r8d, 8                      ; tile column * 256
    shr     edx, 4
    shl     edx, 8                      ; tile row * 256
    mov     r9d, [V(L_BX)]
    shl     r9d, 4
    mov     r10d, [V(L_BY)]
    shl     r10d, 4
    mov     r11d, [V(L_BZ)]
    shl     r11d, 4
    lea     rsi, [cross_verts]
    mov     ecx, 16
.vertex:
    movzx   edi, byte [rsi]
    add     edi, r9d
    mov     [rbx + VERTEX.x], di
    movzx   edi, byte [rsi + 1]
    add     edi, r10d
    mov     [rbx + VERTEX.y], di
    movzx   edi, byte [rsi + 2]
    add     edi, r11d
    mov     [rbx + VERTEX.z], di
    mov     [rbx + VERTEX.pad], ax
    movzx   edi, byte [rsi + 3]
    add     edi, r8d
    mov     [rbx + VERTEX.u], di
    movzx   edi, byte [rsi + 4]
    add     edi, edx
    mov     [rbx + VERTEX.v], di
    mov     dword [rbx + VERTEX.r], 0xFFFFFFFF
    add     rbx, VERTEX_SIZE
    add     rsi, 5
    dec     ecx
    jnz     .vertex
    ret

; emit_face(rsi box, r13d face, r15d first corner): the 4 vertices of one face of a box at rbx.
; The box is 6 bytes x0,y0,z0,x1,y1,z1 in 1/16 block relative to the block at L_BX..L_BZ (chunk-
; local). Corner k carries the ao level L_AO[k] and the packed light L_LT[k]; the tile is L_TILE.
; The vertices go out starting at corner r15d (diagonal flip), counter-clockwise seen from outside.
; The colour is the face shade for the ao level, or 0xFFFFFFFF while L_WHITE is set. rbx advances.
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
    mov     edx, 0xFFFFFFFF
    cmp     dword [V(L_WHITE)], 0
    jne     .colour
    mov     eax, [V(L_AO) + rcx*4]
    lea     rdi, [face_shade]
    lea     eax, [r13*4 + rax]
    movzx   edx, byte [rdi + rax]
    imul    edx, edx, 0x010101
    or      edx, 0xFF000000
.colour:
    mov     [rbx + VERTEX.r], edx
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
