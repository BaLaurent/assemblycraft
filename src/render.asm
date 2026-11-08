; render.asm - texture atlas, chunk VBOs and the world pass: sky colour, sun and moon,
; distance fog, the light map (texture unit 1), chunks, mobs, boats, dropped items, crack
; overlay, the target outline and the translucent (water, ice) pass. Chunk vertices are in 1/16
; block relative to their chunk (each chunk is drawn under its own glTranslatef and a 1/16 scale);
; unit 1 turns each vertex's packed light (VERTEX.pad = sky << 4 | block) into a colour through a
; 256 x 1 light map rebuilt every frame. Every chunk of the streamed world has two VBO ranges
; (opaque and alpha-tested vertices first, translucent vertices after them) in the buffer
; slot_vbo[slot * 16 + cy], slot = the column's index in the toroidal column table.
; render_box and render_box_px are the textured box primitives shared with mobrender.asm,
; itemmodel.asm and hand.asm; the CPU copy of the atlas is exported too.
%include "common.inc"
%include "gl.inc"
default rel

global render_init, render_update_chunks, render_column_freed, render_world
global render_box, render_box16, render_box_px, render_box_px16, frustum_setup, frustum_test, tex_id, atlas

extern texgen_build, mesh_chunk, mesh_scratch, mesh_face_uv
extern game_target, game_has_target, game_time, game_break_progress
extern settings, sky_brightness, sky_color, sky_angle, sincos_deg
extern mobs_render, boats_render, drops_render, arrows_render, tnt_render
extern fire_render, fx_render, fx_shake_yaw, fx_shake_pitch, game_aim
extern light_lut_build, light_bind_index, block_sel_bounds
extern columns, world_origin_x, world_origin_z
extern stream_spiral, stream_spiral_n, time_mono_ns
extern player, player_eye_in_water

section .rodata
align 8
d_near:     dq 0.05
d_far:      dq 300.0
d_ns:       dq 1.0e9                     ; seconds -> nanoseconds
align 4
f_texscale: dd 0.000244140625           ; 1/4096: texcoords are 1/16 px units (u, 256 px)
f_texscale_v: dd 0.0001220703125        ; 1/8192: v over the 512 px atlas height
f_one:      dd 1.0
f_aim_zoom: dd 0.3                     ; fully aimed the FOV narrows by 30 %
f_two:      dd 2.0
f_half:     dd 0.5
f_ten:      dd 10.0
f_16:       dd 16.0
f_8:        dd 8.0
f_fog_near: dd 0.6                      ; fog starts at 60 % of the draw distance
f_eye:      dd 1.62
f_neg_m:    dd -0.002                  ; target box margin
f_pos_m:    dd 0.002
f_sixteenth: dd 0.0625                 ; chunk vertices are in 1/16 block
f_tex1_off: dd 0.001953125             ; 1/512: the centre of a light map texel
f_tex1_scale: dd 0.00390625            ; 1/256: 256 light map texels
f_cull:     dd -14.0                   ; frustum margin: a chunk's bounding radius, 8 * sqrt(3) rounded up
f_water_end: dd 20.0                    ; fog end under water
water_rgba: dd 0.05, 0.15, 0.45, 1.0    ; fog and clear colour under water
px_full:    db 0, 0, 0, 16, 16, 16     ; cell-relative box of a whole cube (render_box)
align 4
flat_shade: times 6 dd 1.0
; sun and moon: x, half size, r, g, b
sky_bodies: dd 100.0, 12.0, 1.0, 0.93, 0.55
            dd -100.0, 8.0, 0.85, 0.88, 0.95
sky_signs:  dd -1.0, -1.0,  1.0, -1.0,  1.0, 1.0,  -1.0, 1.0   ; y, z sign of each quad corner
; the 12 box edges as corner pairs; corner bit0 = x, bit1 = y, bit2 = z (0 lo, 1 hi)
box_edges:  db 0,1, 2,3, 4,5, 6,7,  0,2, 1,3, 4,6, 5,7,  0,4, 1,5, 2,6, 3,7
; box faces +X -X +Y -Y +Z -Z, corners BL, BR, TR, TL: counter-clockwise seen from outside
face_corners:
    db 1,0,1,  1,0,0,  1,1,0,  1,1,1
    db 0,0,0,  0,0,1,  0,1,1,  0,1,0
    db 0,1,1,  1,1,1,  1,1,0,  0,1,0
    db 1,0,1,  0,0,1,  0,0,0,  1,0,0
    db 0,0,1,  1,0,1,  1,1,1,  0,1,1
    db 1,0,0,  0,0,0,  0,1,0,  1,1,0

section .bss
alignb 16
atlas:       resb ATLAS_W * ATLAS_H * 4
slot_vbo:    resd MAX_COLUMNS * COL_CHUNKS      ; GL buffer names, index slot * 16 + cy
slot_count:  resd MAX_COLUMNS * COL_CHUNKS      ; opaque and alpha-tested vertices of the buffer
slot_tcount: resd MAX_COLUMNS * COL_CHUNKS      ; translucent vertices, stored after them
tex_id:      resd 1
lightmap_tex: resd 1
bright:      resd 1                     ; sky brightness of the frame
lim2:        resd 1                     ; squared horizontal draw distance
r_under:     resd 1                     ; 1: the camera is the player and its eye is in water
r_fov:       resd 1                     ; vertical field of view of the frame, degrees
rc_acx:      resd 1                     ; the camera's column (absolute chunk coordinates), set by
rc_acz:      resd 1                     ; render_world and the centre of render_update_chunks
alignb 8
ru_deadline: resq 1                     ; time_mono_ns() value at which render_update_chunks stops
fog_rgba:    resd 4                     ; sky colour, alpha 1
eye:         resd 3
fr_n:        resd 12                    ; frustum: four inward unit normals (left, right, bottom, top)
fr_eye:      resd 3                     ; the frustum's apex
box:         resd 6                     ; target block lo xyz, hi xyz
crack_tiles: resb 8
lut_buf:     resb 1024                  ; the light map: 256 RGBA entries, index = sky << 4 | block

section .text

%macro TEXPARAM 2
    mov     edi, GL_TEXTURE_2D
    mov     esi, %1
    mov     edx, %2
    call    glTexParameteri
%endmacro
%macro TEXENV 2
    mov     edi, GL_TEXTURE_ENV
    mov     esi, %1
    mov     edx, %2
    call    glTexEnvi
%endmacro
; TEXIMAGE width, height, pixels: upload RGBA bytes to the bound texture (needs 24 bytes at rsp)
%macro TEXIMAGE 3
    mov     qword [rsp], GL_RGBA
    mov     qword [rsp + 8], GL_UNSIGNED_BYTE
    lea     rax, [%3]
    mov     [rsp + 16], rax
    mov     edi, GL_TEXTURE_2D
    xor     esi, esi
    mov     edx, GL_RGBA
    mov     ecx, %1
    mov     r8d, %2
    xor     r9d, r9d
    call    glTexImage2D
%endmacro
%macro NEAREST_CLAMP 0
    TEXPARAM GL_TEXTURE_MIN_FILTER, GL_NEAREST
    TEXPARAM GL_TEXTURE_MAG_FILTER, GL_NEAREST
    TEXPARAM GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE
    TEXPARAM GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE
%endmacro

; render_init(): atlas texture, texture matrix, VBO names, fog mode, alpha test, and the
; unit-1 light map: a 256 x 1 texture (filled every frame) that multiplies the previous colour,
; previous alpha untouched. Its texture matrix maps the vertex's packed light index i (the s
; coordinate, t = 0) to ((i + 0.5) / 256, 0.5): translate(1/512, 0.5, 0) . scale(1/256, 1, 1)
render_init:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32
    lea     rdi, [atlas]
    call    texgen_build
    mov     edi, 1
    lea     rsi, [tex_id]
    call    glGenTextures
    mov     edi, GL_TEXTURE_2D
    mov     esi, [tex_id]
    call    glBindTexture
    mov     edi, GL_UNPACK_ALIGNMENT
    mov     esi, 1
    call    glPixelStorei
    TEXIMAGE ATLAS_W, ATLAS_H, atlas
    NEAREST_CLAMP

    mov     edi, GL_TEXTURE
    call    glMatrixMode
    call    glLoadIdentity
    movss   xmm0, [f_texscale]
    movss   xmm1, [f_texscale_v]
    movss   xmm2, [f_one]
    call    glScalef
    mov     edi, GL_MODELVIEW
    call    glMatrixMode

    mov     edi, MAX_COLUMNS * COL_CHUNKS
    lea     rsi, [slot_vbo]
    call    glGenBuffers

    mov     edi, GL_FOG_MODE
    mov     esi, GL_LINEAR
    call    glFogi
    mov     edi, GL_GREATER
    movss   xmm0, [f_half]
    call    glAlphaFunc

    mov     edi, GL_TEXTURE1
    call    glActiveTexture
    mov     edi, 1
    lea     rsi, [lightmap_tex]
    call    glGenTextures
    mov     edi, GL_TEXTURE_2D
    mov     esi, [lightmap_tex]
    call    glBindTexture
    TEXIMAGE 256, 1, lut_buf
    NEAREST_CLAMP                       ; a texture without mipmaps must not use a mipmap filter
    TEXENV  GL_TEXTURE_ENV_MODE, GL_COMBINE
    TEXENV  GL_COMBINE_RGB, GL_MODULATE
    TEXENV  GL_SOURCE0_RGB, GL_PREVIOUS
    TEXENV  GL_SOURCE1_RGB, GL_TEXTURE
    TEXENV  GL_OPERAND0_RGB, GL_SRC_COLOR
    TEXENV  GL_OPERAND1_RGB, GL_SRC_COLOR
    TEXENV  GL_COMBINE_ALPHA, GL_REPLACE
    TEXENV  GL_SOURCE0_ALPHA, GL_PREVIOUS
    TEXENV  GL_OPERAND0_ALPHA, GL_SRC_ALPHA
    mov     edi, GL_TEXTURE
    call    glMatrixMode
    call    glLoadIdentity
    movss   xmm0, [f_tex1_off]
    movss   xmm1, [f_half]
    xorps   xmm2, xmm2
    call    glTranslatef
    movss   xmm0, [f_tex1_scale]
    movss   xmm1, [f_one]
    movss   xmm2, [f_one]
    call    glScalef
    mov     edi, GL_MODELVIEW
    call    glMatrixMode
    mov     edi, GL_TEXTURE0
    call    glActiveTexture
    add     rsp, 32
    pop     rbp
    ret

; render_column_freed(edi slot): the column in table slot `slot` is gone; give back the storage of
; its chunk buffers (glBufferData with size 0) and zero their vertex counts. A chunk whose counts
; are 0 never had a buffer filled, so a process without a GL context (the self-tests) makes no GL
; call here.
render_column_freed:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     ebx, edi
    shl     ebx, 4                      ; first buffer index of the slot
    xor     r12d, r12d                  ; cy
    xor     r13d, r13d                  ; 1 once a buffer was bound
.chunk:
    lea     eax, [rbx + r12]
    mov     ecx, [slot_count + rax*4]
    or      ecx, [slot_tcount + rax*4]
    jz      .next
    mov     dword [slot_count + rax*4], 0
    mov     dword [slot_tcount + rax*4], 0
    mov     edi, GL_ARRAY_BUFFER
    mov     esi, [slot_vbo + rax*4]
    call    glBindBuffer
    mov     edi, GL_ARRAY_BUFFER
    xor     esi, esi
    xor     edx, edx
    mov     ecx, GL_STATIC_DRAW
    call    glBufferData
    mov     r13d, 1
.next:
    inc     r12d
    cmp     r12d, COL_CHUNKS
    jb      .chunk
    test    r13d, r13d
    jz      .ret
    mov     edi, GL_ARRAY_BUFFER
    xor     esi, esi
    call    glBindBuffer
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; mesh_column(rdi COLUMN*, esi slot) -> eax 1 when the time budget ran out, else 0
; Remeshes every dirty chunk of the column into its slot's buffer (opaque range first, translucent
; range after it) and clears its dirty bit; stops after the chunk that passes ru_deadline.
mesh_column:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8                      ; [rsp] buffer index of the chunk being meshed
    mov     rbx, rdi
    mov     r12d, esi
    shl     r12d, 4                     ; slot * 16
    xor     r13d, r13d                  ; cy
.cy:
    bt      dword [rbx + COLUMN.dirty], r13d
    jnc     .next
    mov     edi, [rbx + COLUMN.cx]
    mov     esi, r13d
    mov     edx, [rbx + COLUMN.cz]
    lea     rcx, [mesh_scratch]
    call    mesh_chunk                  ; eax vertices, edx first translucent vertex
    mov     r14d, eax
    mov     r15d, edx
    lea     eax, [r12 + r13]
    mov     [rsp], eax
    test    r14d, r14d
    jz      .empty
    mov     edi, GL_ARRAY_BUFFER
    mov     eax, [rsp]
    mov     esi, [slot_vbo + rax*4]
    call    glBindBuffer
    mov     edi, GL_ARRAY_BUFFER
    mov     esi, r14d
    shl     rsi, 4                      ; bytes = vertices * 16
    lea     rdx, [mesh_scratch]
    mov     ecx, GL_STATIC_DRAW
    call    glBufferData
    jmp     .counts
.empty:                                 ; nothing to draw any more: free the buffer of an old mesh
    mov     eax, [rsp]
    mov     ecx, [slot_count + rax*4]
    or      ecx, [slot_tcount + rax*4]
    jz      .counts
    mov     edi, GL_ARRAY_BUFFER
    mov     esi, [slot_vbo + rax*4]
    call    glBindBuffer
    mov     edi, GL_ARRAY_BUFFER
    xor     esi, esi
    xor     edx, edx
    mov     ecx, GL_STATIC_DRAW
    call    glBufferData
.counts:
    mov     eax, [rsp]
    mov     [slot_count + rax*4], r15d
    mov     ecx, r14d
    sub     ecx, r15d
    mov     [slot_tcount + rax*4], ecx
    btr     dword [rbx + COLUMN.dirty], r13d
    call    time_mono_ns
    cmp     rax, [ru_deadline]
    jae     .spent
.next:
    inc     r13d
    cmp     r13d, COL_CHUNKS
    jb      .cy
    xor     eax, eax
    jmp     .ret
.spent:
    mov     eax, 1
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; try_column(edi acx, esi acz) -> eax 0 nothing to do, 1 remeshed it, 2 the budget ran out
; A column is meshable when it is COL_LIT and its 8 neighbours are COL_LIT too (the mesher reads
; one cell of each neighbour for culling, occlusion and light); it is worth meshing when a chunk
; of it is dirty. Table slots are checked directly: a slot is the column only if its cx/cz match.
try_column:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12d, edi
    mov     r13d, esi
    mov     eax, esi
    and     eax, COL_GRID - 1
    shl     eax, 6
    mov     ecx, edi
    and     ecx, COL_GRID - 1
    or      eax, ecx
    mov     ebx, eax                    ; slot
    imul    rax, rax, COLUMN_size
    lea     rcx, [columns]
    add     rax, rcx
    cmp     [rax + COLUMN.cx], r12d
    jne     .no
    cmp     [rax + COLUMN.cz], r13d
    jne     .no
    cmp     dword [rax + COLUMN.state], COL_LIT
    jne     .no
    cmp     dword [rax + COLUMN.dirty], 0
    je      .no
    mov     r8d, -1                     ; dz
.nz:
    mov     r9d, -1                     ; dx
.nx:
    mov     edi, r12d
    add     edi, r9d
    mov     esi, r13d
    add     esi, r8d
    mov     eax, esi
    and     eax, COL_GRID - 1
    shl     eax, 6
    mov     ecx, edi
    and     ecx, COL_GRID - 1
    or      eax, ecx
    imul    rax, rax, COLUMN_size
    lea     rcx, [columns]
    add     rax, rcx
    cmp     [rax + COLUMN.cx], edi
    jne     .no
    cmp     [rax + COLUMN.cz], esi
    jne     .no
    cmp     dword [rax + COLUMN.state], COL_LIT
    jne     .no
    inc     r9d
    cmp     r9d, 1
    jle     .nx
    inc     r8d
    cmp     r8d, 1
    jle     .nz
    imul    rdi, rbx, COLUMN_size
    lea     rcx, [columns]
    add     rdi, rcx
    mov     esi, ebx
    call    mesh_column                 ; eax = 1 when the budget ran out
    inc     eax                         ; 1 meshed, 2 out of budget
    jmp     .ret
.no:
    xor     eax, eax
.ret:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; render_update_chunks(xmm0 budget_s): remesh the dirty chunks of meshable columns, nearest first,
; until time_mono_ns() passes the budget (at least one chunk is meshed whenever there is work).
; Walks stream_spiral (nearest first) up to render_dist + 1 columns around the camera column
; (rc_acx, rc_acz: the camera of the last render_world). When that walk finds nothing it falls
; back to every column of the table, so a stale centre (a load wait that draws no world frame)
; cannot leave a dirty meshable column unmeshed.
render_update_chunks:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    movss   [rsp], xmm0
    call    time_mono_ns
    cvtss2sd xmm0, [rsp]
    mulsd   xmm0, [d_ns]
    cvttsd2si rcx, xmm0
    add     rax, rcx
    mov     [ru_deadline], rax
    mov     r15d, [settings + SETTINGS.render_dist]
    inc     r15d                        ; walk radius R + 1 (Chebyshev)
    mov     r13d, r15d
    imul    r13d, r13d
    add     r13d, r13d                  ; 2 (R + 1)^2: no square cell lies farther out
    xor     r14d, r14d                  ; columns meshed by the spiral
    xor     ebx, ebx                    ; spiral index
.spiral:
    cmp     ebx, [stream_spiral_n]
    jae     .spiral_end
    mov     r8d, [stream_spiral + rbx*8]
    mov     r9d, [stream_spiral + rbx*8 + 4]
    mov     eax, r8d
    imul    eax, eax
    mov     ecx, r9d
    imul    ecx, ecx
    add     eax, ecx
    cmp     eax, r13d
    ja      .spiral_end                 ; sorted by distance: nothing nearer follows
    mov     eax, r8d
    cdq
    xor     eax, edx
    sub     eax, edx                    ; |dx|
    cmp     eax, r15d
    ja      .spiral_next
    mov     eax, r9d
    cdq
    xor     eax, edx
    sub     eax, edx                    ; |dz|
    cmp     eax, r15d
    ja      .spiral_next
    mov     edi, [rc_acx]
    add     edi, r8d
    mov     esi, [rc_acz]
    add     esi, r9d
    call    try_column
    cmp     eax, 2
    je      .finish                     ; the budget is spent
    add     r14d, eax
.spiral_next:
    inc     ebx
    jmp     .spiral
.spiral_end:
    test    r14d, r14d
    jnz     .finish
    xor     ebx, ebx                    ; slot
.scan:
    cmp     ebx, MAX_COLUMNS
    jae     .finish
    imul    rax, rbx, COLUMN_size
    lea     rcx, [columns]
    add     rax, rcx
    cmp     dword [rax + COLUMN.state], COL_LIT
    jne     .scan_next
    cmp     dword [rax + COLUMN.dirty], 0
    je      .scan_next
    mov     edi, [rax + COLUMN.cx]
    mov     esi, [rax + COLUMN.cz]
    call    try_column
    cmp     eax, 2
    je      .finish
.scan_next:
    inc     ebx
    jmp     .scan
.finish:
    mov     edi, GL_ARRAY_BUFFER
    xor     esi, esi
    call    glBindBuffer
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; frustum_setup(rdi BODY* cam, xmm0 fov_deg, xmm1 aspect): the four side planes of the camera's
; view. The eye is the body's feet + 1.62, looking along yaw / pitch with the vertical field of
; view fov_deg and width / height = aspect. With f = (sin y cos p, -sin p, -cos y cos p),
; r = (cos y, 0, sin y), u = (sin y sin p, cos p, -cos y sin p), ty = tan(fov / 2), tx = ty aspect
; the inward unit normals are (r + tx f), (-r + tx f), (u + ty f), (-u + ty f), each divided by
; sqrt(1 + k^2). Until the first call every point tests visible.
frustum_setup:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 72                     ; [0] f, [12] r, [24] u, [36] ty, [40] tx, [44] ix, [48] iy
                                        ; [52] sin y, [56] cos y, [60] sin p, [64] cos p, [68] aspect
    mov     rbx, rdi
    movss   [rsp + 68], xmm1
    mulss   xmm0, [f_half]
    call    sincos_deg                  ; xmm0 sin, xmm1 cos of fov / 2
    divss   xmm0, xmm1
    movss   [rsp + 36], xmm0            ; ty
    movss   xmm1, xmm0
    mulss   xmm1, [rsp + 68]
    movss   [rsp + 40], xmm1            ; tx
    mulss   xmm1, xmm1
    addss   xmm1, [f_one]
    sqrtss  xmm1, xmm1
    movss   xmm2, [f_one]
    divss   xmm2, xmm1
    movss   [rsp + 44], xmm2            ; ix = 1 / sqrt(1 + tx^2)
    movss   xmm0, [rsp + 36]
    mulss   xmm0, xmm0
    addss   xmm0, [f_one]
    sqrtss  xmm0, xmm0
    movss   xmm2, [f_one]
    divss   xmm2, xmm0
    movss   [rsp + 48], xmm2            ; iy = 1 / sqrt(1 + ty^2)
    movss   xmm0, [rbx + BODY.yaw]
    call    sincos_deg
    movss   [rsp + 52], xmm0
    movss   [rsp + 56], xmm1
    movss   xmm0, [rbx + BODY.pitch]
    call    sincos_deg
    movss   [rsp + 60], xmm0
    movss   [rsp + 64], xmm1
    movss   xmm0, [rsp + 52]
    mulss   xmm0, [rsp + 64]
    movss   [rsp], xmm0                 ; fx = sin y cos p
    xorps   xmm0, xmm0
    subss   xmm0, [rsp + 60]
    movss   [rsp + 4], xmm0             ; fy = -sin p
    movss   xmm0, [rsp + 56]
    mulss   xmm0, [rsp + 64]
    xorps   xmm1, xmm1
    subss   xmm1, xmm0
    movss   [rsp + 8], xmm1             ; fz = -cos y cos p
    mov     eax, [rsp + 56]
    mov     [rsp + 12], eax             ; rx = cos y
    mov     dword [rsp + 16], 0         ; ry = 0
    mov     eax, [rsp + 52]
    mov     [rsp + 20], eax             ; rz = sin y
    movss   xmm0, [rsp + 52]
    mulss   xmm0, [rsp + 60]
    movss   [rsp + 24], xmm0            ; ux = sin y sin p
    mov     eax, [rsp + 64]
    mov     [rsp + 28], eax             ; uy = cos p
    movss   xmm0, [rsp + 56]
    mulss   xmm0, [rsp + 60]
    xorps   xmm1, xmm1
    subss   xmm1, xmm0
    movss   [rsp + 32], xmm1            ; uz = -cos y sin p
    lea     rdi, [fr_n]
    xor     ecx, ecx                    ; plane 0 left, 1 right, 2 bottom, 3 top
.plane:
    lea     rsi, [rsp + 12]             ; a = r for the side planes, u for the others
    movss   xmm3, [rsp + 40]            ; k = tx or ty
    movss   xmm4, [rsp + 44]            ; 1 / sqrt(1 + k^2)
    cmp     ecx, 2
    jb      .have
    lea     rsi, [rsp + 24]
    movss   xmm3, [rsp + 36]
    movss   xmm4, [rsp + 48]
.have:
    movss   xmm5, [f_one]               ; +a for planes 0 and 2, -a for 1 and 3
    test    ecx, 1
    jz      .sign
    xorps   xmm5, xmm5
    subss   xmm5, [f_one]
.sign:
    xor     edx, edx                    ; component
.comp:
    movss   xmm0, [rsi + rdx*4]
    mulss   xmm0, xmm5
    movss   xmm1, [rsp + rdx*4]
    mulss   xmm1, xmm3
    addss   xmm0, xmm1
    mulss   xmm0, xmm4
    movss   [rdi], xmm0
    add     rdi, 4
    inc     edx
    cmp     edx, 3
    jb      .comp
    inc     ecx
    cmp     ecx, 4
    jb      .plane
    movss   xmm0, [rbx + BODY.x]
    movss   [fr_eye], xmm0
    movss   xmm0, [rbx + BODY.y]
    addss   xmm0, [f_eye]
    movss   [fr_eye + 4], xmm0
    movss   xmm0, [rbx + BODY.z]
    movss   [fr_eye + 8], xmm0
    add     rsp, 72
    pop     rbx
    pop     rbp
    ret

; frustum_test(xmm0 x, xmm1 y, xmm2 z) -> eax 1 visible, 0 outside
; The point (local coordinates, a chunk centre) is outside when it lies more than 14.0 behind any
; of the four side planes of the last frustum_setup. There is no near or far plane.
; Leaf: clobbers xmm0-xmm4, ecx, edx.
frustum_test:
    subss   xmm0, [fr_eye]
    subss   xmm1, [fr_eye + 4]
    subss   xmm2, [fr_eye + 8]
    lea     rcx, [fr_n]
    mov     edx, 4
.plane:
    movss   xmm3, [rcx]
    mulss   xmm3, xmm0
    movss   xmm4, [rcx + 4]
    mulss   xmm4, xmm1
    addss   xmm3, xmm4
    movss   xmm4, [rcx + 8]
    mulss   xmm4, xmm2
    addss   xmm3, xmm4
    comiss  xmm3, [f_cull]
    jb      .outside
    add     rcx, 12
    dec     edx
    jnz     .plane
    mov     eax, 1
    ret
.outside:
    xor     eax, eax
    ret

; sky_quad(rdi body): one flat quad on the plane x = body.x; body = x, half size, r, g, b
sky_quad:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    mov     rbx, rdi
    movss   xmm0, [rbx + 8]
    movss   xmm1, [rbx + 12]
    movss   xmm2, [rbx + 16]
    call    glColor3f
    mov     edi, GL_QUADS
    call    glBegin
    xor     r12d, r12d
.vertex:
    movss   xmm1, [rbx + 4]
    movaps  xmm2, xmm1
    mulss   xmm1, [sky_signs + r12*8]
    mulss   xmm2, [sky_signs + r12*8 + 4]
    movss   xmm0, [rbx]
    call    glVertex3f
    inc     r12d
    cmp     r12d, 4
    jb      .vertex
    call    glEnd
    pop     r12
    pop     rbx
    pop     rbp
    ret

; unit1_off(): texturing off on texture unit 1; texture unit 0 stays the active one
unit1_off:
    sub     rsp, 8
    mov     edi, GL_TEXTURE1
    call    glActiveTexture
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    mov     edi, GL_TEXTURE0
    call    glActiveTexture
    add     rsp, 8
    ret

; unit1_on(): texturing on again for texture unit 1 (the light map stays bound there); texture
; unit 0 stays the active one
unit1_on:
    sub     rsp, 8
    mov     edi, GL_TEXTURE1
    call    glActiveTexture
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     edi, GL_TEXTURE0
    call    glActiveTexture
    add     rsp, 8
    ret

; chunk_arrays_on(): the client arrays of a chunk draw: positions, atlas texcoords and colours on
; unit 0, the packed light as the texcoord of unit 1
chunk_arrays_on:
    sub     rsp, 8
    mov     edi, GL_VERTEX_ARRAY
    call    glEnableClientState
    mov     edi, GL_TEXTURE_COORD_ARRAY
    call    glEnableClientState
    mov     edi, GL_COLOR_ARRAY
    call    glEnableClientState
    mov     edi, GL_TEXTURE1            ; unit 1's array carries the packed light
    call    glClientActiveTexture
    mov     edi, GL_TEXTURE_COORD_ARRAY
    call    glEnableClientState
    mov     edi, GL_TEXTURE0
    call    glClientActiveTexture
    add     rsp, 8
    ret

; chunk_arrays_off(): undo chunk_arrays_on and unbind the buffer
chunk_arrays_off:
    sub     rsp, 8
    mov     edi, GL_VERTEX_ARRAY
    call    glDisableClientState
    mov     edi, GL_TEXTURE_COORD_ARRAY
    call    glDisableClientState
    mov     edi, GL_COLOR_ARRAY
    call    glDisableClientState
    mov     edi, GL_TEXTURE1
    call    glClientActiveTexture
    mov     edi, GL_TEXTURE_COORD_ARRAY
    call    glDisableClientState
    mov     edi, GL_TEXTURE0
    call    glClientActiveTexture
    mov     edi, GL_ARRAY_BUFFER
    xor     esi, esi
    call    glBindBuffer
    add     rsp, 8
    ret

; draw_chunks(edi pass): draw the chunk buffers of the columns within render_dist (Chebyshev) of the
; camera column (rc_acx, rc_acz), walking stream_spiral. Pass 0 goes nearest first and draws the
; opaque and alpha-tested vertices [0, slot_count); pass 1 goes farthest first and draws the
; translucent vertices [slot_count, slot_count + slot_tcount). A column counts only while its table
; slot still holds it (cx, cz, COL_LIT); it is skipped when its centre is farther than lim2 from the
; eye, a chunk when it is empty or frustum_test says it is outside. Each chunk is drawn under
; glTranslatef(its local origin) and glScalef(1/16). The caller sets the client arrays, the texture
; units, fog and blend state.
; Frame: [0] pass, [4] R, [8] acx, [12] acz, [16] slot, [20] local x of the column, [24] local z,
; [28] buffer index, [32] first vertex, [36] vertex count. ebx = spiral index, r14d = step,
; r15d = end index, r12 = COLUMN*, r13d = cy.
draw_chunks:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 56
    mov     [rsp], edi
    mov     eax, [settings + SETTINGS.render_dist]
    mov     [rsp + 4], eax
    xor     ebx, ebx
    mov     r14d, 1
    mov     r15d, [stream_spiral_n]
    test    edi, edi
    jz      .entry
    mov     ebx, [stream_spiral_n]
    dec     ebx
    mov     r14d, -1
    mov     r15d, -1
.entry:
    cmp     ebx, r15d
    je      .done
    mov     eax, [stream_spiral + rbx*8]        ; dx
    mov     edx, [stream_spiral + rbx*8 + 4]    ; dz
    mov     ecx, eax
    sar     ecx, 31
    mov     esi, eax
    xor     esi, ecx
    sub     esi, ecx                    ; |dx|
    cmp     esi, [rsp + 4]
    jg      .skip
    mov     ecx, edx
    sar     ecx, 31
    mov     esi, edx
    xor     esi, ecx
    sub     esi, ecx                    ; |dz|
    cmp     esi, [rsp + 4]
    jg      .skip
    add     eax, [rc_acx]
    add     edx, [rc_acz]
    mov     [rsp + 8], eax
    mov     [rsp + 12], edx
    mov     ecx, edx
    and     ecx, COL_GRID - 1
    shl     ecx, 6
    mov     esi, eax
    and     esi, COL_GRID - 1
    or      ecx, esi
    mov     [rsp + 16], ecx             ; slot
    imul    r12, rcx, COLUMN_size
    lea     rsi, [columns]
    add     r12, rsi
    cmp     [r12 + COLUMN.cx], eax
    jne     .skip
    cmp     [r12 + COLUMN.cz], edx
    jne     .skip
    cmp     dword [r12 + COLUMN.state], COL_LIT
    jne     .skip
    mov     eax, [rsp + 8]
    shl     eax, 4
    sub     eax, [world_origin_x]
    mov     [rsp + 20], eax             ; local x of the column's minimum corner
    mov     eax, [rsp + 12]
    shl     eax, 4
    sub     eax, [world_origin_z]
    mov     [rsp + 24], eax
    cvtsi2ss xmm0, dword [rsp + 20]     ; horizontal distance of the column centre to the eye
    addss   xmm0, [f_8]
    subss   xmm0, [eye]
    mulss   xmm0, xmm0
    cvtsi2ss xmm1, dword [rsp + 24]
    addss   xmm1, [f_8]
    subss   xmm1, [eye + 8]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [lim2]
    ja      .skip
    xor     r13d, r13d
.chunk:
    mov     eax, [rsp + 16]
    shl     eax, 4
    add     eax, r13d
    mov     [rsp + 28], eax             ; buffer index slot * 16 + cy
    cmp     dword [rsp], 0
    jne     .translucent
    mov     ecx, [slot_count + rax*4]
    mov     dword [rsp + 32], 0
    jmp     .have
.translucent:
    mov     ecx, [slot_tcount + rax*4]
    mov     edx, [slot_count + rax*4]
    mov     [rsp + 32], edx
.have:
    mov     [rsp + 36], ecx
    test    ecx, ecx
    jz      .next_chunk
    cvtsi2ss xmm0, dword [rsp + 20]     ; the chunk's centre
    addss   xmm0, [f_8]
    mov     eax, r13d
    shl     eax, 4
    add     eax, 8
    cvtsi2ss xmm1, eax
    cvtsi2ss xmm2, dword [rsp + 24]
    addss   xmm2, [f_8]
    call    frustum_test
    test    eax, eax
    jz      .next_chunk
    mov     edi, GL_ARRAY_BUFFER
    mov     eax, [rsp + 28]
    mov     esi, [slot_vbo + rax*4]
    call    glBindBuffer
    mov     edi, 3
    mov     esi, GL_SHORT
    mov     edx, VERTEX_SIZE
    xor     ecx, ecx
    call    glVertexPointer
    mov     edi, GL_TEXTURE1
    call    glClientActiveTexture
    mov     edi, 1                      ; VERTEX.pad: one short, the packed light
    mov     esi, GL_SHORT
    mov     edx, VERTEX_SIZE
    mov     ecx, VERTEX.pad
    call    glTexCoordPointer
    mov     edi, GL_TEXTURE0
    call    glClientActiveTexture
    mov     edi, 2
    mov     esi, GL_SHORT
    mov     edx, VERTEX_SIZE
    mov     ecx, VERTEX.u
    call    glTexCoordPointer
    mov     edi, 4
    mov     esi, GL_UNSIGNED_BYTE
    mov     edx, VERTEX_SIZE
    mov     ecx, VERTEX.r
    call    glColorPointer
    call    glPushMatrix
    cvtsi2ss xmm0, dword [rsp + 20]
    mov     eax, r13d
    shl     eax, 4
    cvtsi2ss xmm1, eax
    cvtsi2ss xmm2, dword [rsp + 24]
    call    glTranslatef
    movss   xmm0, [f_sixteenth]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    glScalef
    mov     edi, GL_QUADS
    mov     esi, [rsp + 32]
    mov     edx, [rsp + 36]
    call    glDrawArrays
    call    glPopMatrix
.next_chunk:
    inc     r13d
    cmp     r13d, COL_CHUNKS
    jb      .chunk
.skip:
    add     ebx, r14d
    jmp     .entry
.done:
    add     rsp, 56
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; render_box(rdi box float[6] = lo xyz, hi xyz; rsi tiles byte[6]; rdx shades float[6];
;            xmm0 r, xmm1 g, xmm2 b)
; Six textured quads, counter-clockwise seen from outside, in face order +X -X +Y -Y +Z -Z.
; Every face is one whole atlas tile (uv inset 1 unit, tile top edge = box top edge) and
; is coloured shade[face] * (r, g, b). Texture unit 0 and the atlas are set up by the caller.
; The whole-tile mapping is render_box_px with the box of a whole cube.
render_box:
    lea     rcx, [px_full]
    xor     eax, eax
    jmp     box_draw

; render_box16(rdi box float[6]; rsi tiles word[6]; rdx shades float[6]; xmm0 r, xmm1 g, xmm2 b)
; render_box with 16-bit atlas tile ids (the faction skins live at tiles 304..323).
render_box16:
    lea     rcx, [px_full]
    mov     eax, 1
    jmp     box_draw

; render_box_px(rdi box float[6] = lo xyz, hi xyz; rsi tiles byte[6]; rdx shades float[6];
;               xmm0 r, xmm1 g, xmm2 b; rcx px byte[6])
; render_box with the texture mapping of the chunk mesher: px is the box as the part of the
; cell it fills (x0, y0, z0, x1, y1, z1 in 1/16 block, 0..16) and every corner samples the
; tile where mesh_face_uv puts that cell-relative point, so a slab shows the lower half of its
; side tiles and a thin box a thin strip. Colour as render_box.
render_box_px:
    xor     eax, eax
    jmp     box_draw

; render_box_px16(rdi box float[6]; rsi tiles word[6]; rdx shades float[6]; xmm0 r, xmm1 g,
;                 xmm2 b; rcx px byte[6]): render_box_px with 16-bit atlas tile ids.
render_box_px16:
    mov     eax, 1
    ; fall through

; box_draw: the body of render_box, render_box_px and render_box16. In: the register arguments
; of render_box_px; eax = 0 for byte tile ids, 1 for word tile ids.
box_draw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [rsp] r, g, b; +12 wide tile ids; +16 px
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     [rsp + 12], eax
    mov     [rsp + 16], rcx
    movss   [rsp], xmm0
    movss   [rsp + 4], xmm1
    movss   [rsp + 8], xmm2
    mov     edi, GL_QUADS
    call    glBegin
    xor     r14d, r14d                  ; face
.face:
    movss   xmm3, [r13 + r14*4]
    movss   xmm0, [rsp]
    mulss   xmm0, xmm3
    movss   xmm1, [rsp + 4]
    mulss   xmm1, xmm3
    movss   xmm2, [rsp + 8]
    mulss   xmm2, xmm3
    movss   xmm3, [f_one]
    call    glColor4f
    xor     r15d, r15d                  ; corner
.corner:
    lea     eax, [r14*4 + r15]
    lea     eax, [rax + rax*2]          ; offset of the corner's three lo/hi bits
    mov     r8, [rsp + 16]
    movzx   ecx, byte [face_corners + rax]
    lea     ecx, [rcx + rcx*2]          ; px[bit*3 + 0]
    movzx   esi, byte [r8 + rcx]        ; x in the cell
    movzx   ecx, byte [face_corners + rax + 1]
    lea     ecx, [rcx + rcx*2 + 1]
    movzx   edx, byte [r8 + rcx]        ; y
    movzx   ecx, byte [face_corners + rax + 2]
    lea     ecx, [rcx + rcx*2 + 2]
    movzx   ecx, byte [r8 + rcx]        ; z
    mov     edi, r14d
    call    mesh_face_uv                ; eax = u, edx = v inside the tile
    cmp     dword [rsp + 12], 0
    jne     .wide_tile
    movzx   ecx, byte [r12 + r14]       ; atlas tile of this face
    jmp     .tile_loaded
.wide_tile:
    movzx   ecx, word [r12 + r14*2]
.tile_loaded:
    mov     esi, ecx
    and     ecx, 15
    shl     ecx, 8
    add     eax, ecx                    ; + column * 256
    shr     esi, 4
    shl     esi, 8
    add     edx, esi                    ; + row * 256
    mov     edi, eax
    mov     esi, edx
    call    glTexCoord2i
    lea     eax, [r14*4 + r15]
    lea     eax, [rax + rax*2]
    movzx   ecx, byte [face_corners + rax]
    lea     ecx, [rcx + rcx*2]          ; box[bit*3 + 0]
    movss   xmm0, [rbx + rcx*4]
    movzx   ecx, byte [face_corners + rax + 1]
    lea     ecx, [rcx + rcx*2 + 1]
    movss   xmm1, [rbx + rcx*4]
    movzx   ecx, byte [face_corners + rax + 2]
    lea     ecx, [rcx + rcx*2 + 2]
    movss   xmm2, [rbx + rcx*4]
    call    glVertex3f
    inc     r15d
    cmp     r15d, 4
    jb      .corner
    inc     r14d
    cmp     r14d, 6
    jb      .face
    call    glEnd
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; render_world(rdi cam BODY*, esi fb_w, edx fb_h)
; r15 = cam, r12d = width, r13d = height, ebx = the target block has a box to show
; Order: sky (sun and moon unless the player's eye is under water), camera, chunks (opaque and
; alpha-tested), mobs, boats, drops, arrows, tnt, fire, particles, crack overlay, target outline, and
; last the translucent chunk faces (water, ice) blended with the depth mask off.
render_world:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40                     ; 24 bytes of stack arguments for glTexImage2D, aligned
    mov     r15, rdi
    mov     r12d, esi
    mov     r13d, edx

    ; ---- under water: the camera is the player (not the title panorama) and its eye is in water
    xor     eax, eax
    lea     rcx, [player]
    cmp     r15, rcx
    jne     .under_set
    call    player_eye_in_water
.under_set:
    mov     [r_under], eax

    ; ---- viewport, sky brightness and colour, clear -------------------------
    xor     edi, edi
    xor     esi, esi
    mov     edx, r12d
    mov     ecx, r13d
    call    glViewport
    mov     edi, [game_time]
    call    sky_brightness
    movss   [bright], xmm0
    mov     edi, [game_time]
    lea     rsi, [fog_rgba]
    call    sky_color
    mov     dword [fog_rgba + 12], __float32__(1.0)
    cmp     dword [r_under], 0
    je      .clear
    movups  xmm0, [water_rgba]          ; under water: blue fog and clear colour
    movups  [fog_rgba], xmm0
.clear:
    movss   xmm0, [fog_rgba]
    movss   xmm1, [fog_rgba + 4]
    movss   xmm2, [fog_rgba + 8]
    movss   xmm3, [f_one]
    call    glClearColor
    mov     edi, GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT
    call    glClear

    ; ---- projection: hh = 0.05 * tan(fov / 2) ------------------------------
    mov     edi, GL_PROJECTION
    call    glMatrixMode
    call    glLoadIdentity
    cvtsi2ss xmm0, dword [settings + SETTINGS.fov]
    movss   xmm1, [game_aim]            ; aiming narrows the view: fov (1 - 0.3 aim)
    mulss   xmm1, [f_aim_zoom]
    movss   xmm2, [f_one]
    subss   xmm2, xmm1
    mulss   xmm0, xmm2
    movss   [r_fov], xmm0
    mulss   xmm0, [f_half]
    call    sincos_deg                  ; xmm0 = sin, xmm1 = cos
    divss   xmm0, xmm1
    cvtss2sd xmm0, xmm0
    mulsd   xmm0, [d_near]              ; hh
    cvtsi2sd xmm1, r12d
    cvtsi2sd xmm2, r13d
    divsd   xmm1, xmm2
    mulsd   xmm1, xmm0                  ; right = hh * aspect
    movapd  xmm3, xmm0                  ; top = hh
    xorpd   xmm2, xmm2
    subsd   xmm2, xmm0                  ; bottom = -hh
    xorpd   xmm0, xmm0
    subsd   xmm0, xmm1                  ; left = -right
    movsd   xmm4, [d_near]
    movsd   xmm5, [d_far]
    call    glFrustum

    ; ---- sun and moon: view rotation only, turned by the day angle -------------
    mov     edi, GL_MODELVIEW
    call    glMatrixMode
    call    glLoadIdentity
    movss   xmm0, [r15 + BODY.pitch]
    addss   xmm0, [fx_shake_pitch]      ; explosions shake the camera
    movss   xmm1, [f_one]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    glRotatef
    movss   xmm0, [r15 + BODY.yaw]
    addss   xmm0, [fx_shake_yaw]
    xorps   xmm1, xmm1
    movss   xmm2, [f_one]
    xorps   xmm3, xmm3
    call    glRotatef
    cmp     dword [r_under], 0
    jne     .no_sky_bodies              ; no sun or moon seen through water
    call    glPushMatrix
    mov     edi, [game_time]
    call    sky_angle
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    movss   xmm3, [f_one]
    call    glRotatef
    mov     edi, GL_DEPTH_TEST
    call    glDisable
    mov     edi, GL_FOG
    call    glDisable
    mov     edi, GL_CULL_FACE
    call    glDisable
    mov     edi, GL_BLEND
    call    glDisable
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    call    unit1_off
    lea     rdi, [sky_bodies]
    call    sky_quad
    lea     rdi, [sky_bodies + 20]
    call    sky_quad
    call    glPopMatrix
.no_sky_bodies:

    ; ---- camera: eye = feet + 1.62 ------------------------------------------
    movss   xmm0, [r15 + BODY.x]
    movss   [eye], xmm0
    movss   xmm0, [r15 + BODY.y]
    addss   xmm0, [f_eye]
    movss   [eye + 4], xmm0
    movss   xmm0, [r15 + BODY.z]
    movss   [eye + 8], xmm0
    xorps   xmm0, xmm0
    subss   xmm0, [eye]
    xorps   xmm1, xmm1
    subss   xmm1, [eye + 4]
    xorps   xmm2, xmm2
    subss   xmm2, [eye + 8]
    call    glTranslatef

    ; ---- frustum of the camera and its column (the chunk walks and render_update_chunks) --------
    mov     rdi, r15
    movss   xmm0, [r_fov]
    cvtsi2ss xmm1, r12d
    cvtsi2ss xmm2, r13d
    divss   xmm1, xmm2                  ; aspect
    call    frustum_setup
    movss   xmm0, [eye]
    roundss xmm0, xmm0, 9               ; floor
    cvttss2si eax, xmm0
    add     eax, [world_origin_x]       ; absolute block, then its chunk column
    sar     eax, 4
    mov     [rc_acx], eax
    movss   xmm0, [eye + 8]
    roundss xmm0, xmm0, 9
    cvttss2si eax, xmm0
    add     eax, [world_origin_z]
    sar     eax, 4
    mov     [rc_acz], eax

    ; ---- fog and draw distance from the render distance -----------------------
    cvtsi2ss xmm0, dword [settings + SETTINGS.render_dist]
    mulss   xmm0, [f_16]                ; fog end = render_dist * 16
    movss   xmm1, xmm0
    addss   xmm1, [f_8]
    mulss   xmm1, xmm1
    movss   [lim2], xmm1                ; chunks are drawn up to (end + 8)^2
    cmp     dword [r_under], 0
    je      .fog_air
    movss   xmm0, [f_water_end]         ; under water the fog closes in at 20 blocks
    mov     edi, GL_FOG_END
    call    glFogf
    xorps   xmm0, xmm0
    jmp     .fog_start
.fog_air:
    mov     edi, GL_FOG_END
    call    glFogf
    cvtsi2ss xmm0, dword [settings + SETTINGS.render_dist]
    mulss   xmm0, [f_16]
    mulss   xmm0, [f_fog_near]
.fog_start:
    mov     edi, GL_FOG_START
    call    glFogf
    mov     edi, GL_FOG_COLOR
    lea     rsi, [fog_rgba]
    call    glFogfv

    ; ---- light map: unit 1 turns a vertex's packed light into a colour --------
    ; (rebuilt each frame: the sky columns follow the time of day)
    mov     edi, GL_TEXTURE1
    call    glActiveTexture
    mov     edi, GL_TEXTURE_2D
    mov     esi, [lightmap_tex]
    call    glBindTexture
    movss   xmm0, [bright]
    lea     rdi, [lut_buf]
    call    light_lut_build
    TEXIMAGE 256, 1, lut_buf
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     edi, GL_TEXTURE0
    call    glActiveTexture

    ; ---- world state ----------------------------------------------------------
    mov     edi, GL_DEPTH_TEST
    call    glEnable
    mov     edi, GL_CULL_FACE
    call    glEnable
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     edi, GL_TEXTURE_2D
    mov     esi, [tex_id]
    call    glBindTexture
    mov     edi, GL_ALPHA_TEST
    call    glEnable
    mov     edi, GL_FOG
    call    glEnable
    mov     edi, GL_BLEND
    call    glDisable
    call    chunk_arrays_on
    xor     edi, edi
    call    draw_chunks                 ; opaque and alpha-tested faces, nearest first
    call    chunk_arrays_off
    mov     edi, LIGHT_SKY_FULL         ; the array draw left unit 1's texcoord undefined;
    call    light_bind_index            ; entities bind their own light and put this back
    call    mobs_render
    call    boats_render
    call    drops_render
    call    arrows_render
    call    tnt_render
    call    fire_render
    call    fx_render

    ; ---- target block: crack overlay, then the outline -------------------------
    xor     ebx, ebx                    ; ebx = 1: the target has a box to show
    cmp     dword [game_has_target], 0
    je      .after_crack
    mov     edi, [game_target + RAYHIT.bx]
    mov     esi, [game_target + RAYHIT.by]
    mov     edx, [game_target + RAYHIT.bz]
    lea     rcx, [box]
    call    block_sel_bounds            ; union of the block's selection boxes
    test    eax, eax
    jz      .after_crack                ; nothing to select: neither crack nor outline
    mov     ebx, 1
    xor     ecx, ecx
.box_axis:
    movss   xmm0, [box + rcx*4]
    addss   xmm0, [f_neg_m]
    movss   [box + rcx*4], xmm0
    movss   xmm0, [box + 12 + rcx*4]
    addss   xmm0, [f_pos_m]
    movss   [box + 12 + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 3
    jb      .box_axis
    movss   xmm0, [game_break_progress]
    xorps   xmm1, xmm1
    comiss  xmm0, xmm1
    jbe     .after_crack                ; no progress (or NaN)
    mulss   xmm0, [f_ten]
    cvttss2si eax, xmm0                 ; crack stage = min(9, floor(progress * 10))
    mov     ecx, 9
    cmp     eax, ecx
    cmova   eax, ecx
    add     eax, TILE_CRACK0
    mov     rcx, 0x0101010101010101
    imul    rax, rcx
    mov     [crack_tiles], rax          ; the same tile on all six faces
    lea     rdi, [box]
    lea     rsi, [crack_tiles]
    lea     rdx, [flat_shade]
    movss   xmm0, [f_one]
    movss   xmm1, [f_one]
    movss   xmm2, [f_one]
    call    render_box
.after_crack:
    call    unit1_off
    test    ebx, ebx
    jz      .water_pass
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    mov     edi, GL_ALPHA_TEST
    call    glDisable
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    movss   xmm3, [f_one]
    call    glColor4f
    movss   xmm0, [f_two]
    call    glLineWidth
    mov     edi, GL_LINES
    call    glBegin
    xor     ebx, ebx
.edge:
    movzx   eax, byte [box_edges + rbx]
    movss   xmm0, [box]
    test    eax, 1
    jz      .ex
    movss   xmm0, [box + 12]
.ex:
    movss   xmm1, [box + 4]
    test    eax, 2
    jz      .ey
    movss   xmm1, [box + 16]
.ey:
    movss   xmm2, [box + 8]
    test    eax, 4
    jz      .ez
    movss   xmm2, [box + 20]
.ez:
    call    glVertex3f
    inc     ebx
    cmp     ebx, 24
    jb      .edge
    call    glEnd

    ; ---- translucent faces (water, ice): the chunks again, farthest first, blended; the depth
    ; buffer is tested but not written and both faces of a cell show (culling off) ----------------
.water_pass:
    call    unit1_on
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     edi, GL_TEXTURE_2D
    mov     esi, [tex_id]
    call    glBindTexture
    mov     edi, GL_ALPHA_TEST
    call    glDisable
    mov     edi, GL_CULL_FACE
    call    glDisable
    mov     edi, GL_DEPTH_TEST
    call    glEnable
    mov     edi, GL_FOG
    call    glEnable
    mov     edi, GL_BLEND
    call    glEnable
    mov     edi, GL_SRC_ALPHA
    mov     esi, GL_ONE_MINUS_SRC_ALPHA
    call    glBlendFunc
    xor     edi, edi
    call    glDepthMask
    call    chunk_arrays_on
    mov     edi, 1
    call    draw_chunks
    call    chunk_arrays_off
    mov     edi, 1
    call    glDepthMask
    mov     edi, GL_BLEND
    call    glDisable
    mov     edi, GL_CULL_FACE
    call    glEnable
    mov     edi, GL_ALPHA_TEST
    call    glEnable
    call    unit1_off
.done:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
