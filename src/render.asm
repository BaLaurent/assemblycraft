; render.asm - texture atlas, chunk VBOs and the world pass: sky colour, sun and moon,
; distance fog, night darkening (texture unit 1), chunks, mobs, dropped items, crack
; overlay and the target outline. render_box is the textured box primitive shared with
; mobrender.asm, itemmodel.asm and hand.asm; the CPU copy of the atlas is exported too.
%include "common.inc"
%include "gl.inc"
default rel

global render_init, render_update_chunks, render_world, render_box, tex_id, atlas

extern texgen_build, mesh_chunk, mesh_scratch, chunk_dirty
extern game_target, game_has_target, game_time, game_break_progress
extern settings, sky_brightness, sky_color, sky_angle, sincos_deg
extern mobs_render, drops_render, arrows_render, tnt_render

section .rodata
align 8
d_near:     dq 0.05
d_far:      dq 300.0
align 4
f_texscale: dd 0.000244140625           ; 1/4096: texcoords are 1/16 px units
f_one:      dd 1.0
f_two:      dd 2.0
f_half:     dd 0.5
f_ten:      dd 10.0
f_16:       dd 16.0
f_8:        dd 8.0
f_fog_near: dd 0.6                      ; fog starts at 60 % of the draw distance
f_eye:      dd 1.62
f_lo:       dd -0.002
f_hi:       dd 1.002
white_px:   db 255, 255, 255, 255
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
align 4
corner_du:  dd 0, 254, 254, 0           ; uv offset of corners BL, BR, TR, TL (1/16 px)
corner_dv:  dd 254, 254, 0, 0

section .bss
alignb 16
atlas:       resb ATLAS_PX * ATLAS_PX * 4
chunk_vbo:   resd NUM_CHUNKS
chunk_count: resd NUM_CHUNKS
tex_id:      resd 1
white_tex:   resd 1
bright:      resd 1                     ; sky brightness of the frame
lim2:        resd 1                     ; squared horizontal draw distance
fog_rgba:    resd 4                     ; sky colour, alpha 1
env_rgba:    resd 4                     ; texture unit 1 constant: (brightness x3, 1)
eye:         resd 3
box:         resd 6                     ; target block lo xyz, hi xyz
crack_tiles: resb 8

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
; unit-1 night combiner: previous colour x constant colour, previous alpha untouched
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
    TEXIMAGE ATLAS_PX, ATLAS_PX, atlas
    NEAREST_CLAMP

    mov     edi, GL_TEXTURE
    call    glMatrixMode
    call    glLoadIdentity
    movss   xmm0, [f_texscale]
    movss   xmm1, [f_texscale]
    movss   xmm2, [f_one]
    call    glScalef
    mov     edi, GL_MODELVIEW
    call    glMatrixMode

    mov     edi, NUM_CHUNKS
    lea     rsi, [chunk_vbo]
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
    lea     rsi, [white_tex]
    call    glGenTextures
    mov     edi, GL_TEXTURE_2D
    mov     esi, [white_tex]
    call    glBindTexture
    TEXIMAGE 1, 1, white_px
    NEAREST_CLAMP                       ; a texture without mipmaps must not use a mipmap filter
    TEXENV  GL_TEXTURE_ENV_MODE, GL_COMBINE
    TEXENV  GL_COMBINE_RGB, GL_MODULATE
    TEXENV  GL_SOURCE0_RGB, GL_PREVIOUS
    TEXENV  GL_SOURCE1_RGB, GL_CONSTANT
    TEXENV  GL_OPERAND0_RGB, GL_SRC_COLOR
    TEXENV  GL_OPERAND1_RGB, GL_SRC_COLOR
    TEXENV  GL_COMBINE_ALPHA, GL_REPLACE
    TEXENV  GL_SOURCE0_ALPHA, GL_PREVIOUS
    TEXENV  GL_OPERAND0_ALPHA, GL_SRC_ALPHA
    mov     edi, GL_TEXTURE0
    call    glActiveTexture
    add     rsp, 32
    pop     rbp
    ret

; render_update_chunks(): remesh every dirty chunk into its VBO
render_update_chunks:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    xor     ebx, ebx
.chunk:
    cmp     byte [chunk_dirty + rbx], 0
    je      .next
    mov     edi, ebx
    and     edi, 15                     ; cx
    mov     esi, ebx
    shr     esi, 8                      ; cy
    mov     edx, ebx
    shr     edx, 4
    and     edx, 15                     ; cz
    lea     rcx, [mesh_scratch]
    call    mesh_chunk
    mov     r12d, eax
    test    eax, eax
    jz      .store
    mov     edi, GL_ARRAY_BUFFER
    mov     esi, [chunk_vbo + rbx*4]
    call    glBindBuffer
    mov     edi, GL_ARRAY_BUFFER
    mov     esi, r12d
    shl     rsi, 4                      ; bytes = n * 16
    lea     rdx, [mesh_scratch]
    mov     ecx, GL_STATIC_DRAW
    call    glBufferData
.store:
    mov     [chunk_count + rbx*4], r12d
    mov     byte [chunk_dirty + rbx], 0
.next:
    inc     ebx
    cmp     ebx, NUM_CHUNKS
    jb      .chunk
    mov     edi, GL_ARRAY_BUFFER
    xor     esi, esi
    call    glBindBuffer
    pop     r12
    pop     rbx
    pop     rbp
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

; render_box(rdi box float[6] = lo xyz, hi xyz; rsi tiles byte[6]; rdx shades float[6];
;            xmm0 r, xmm1 g, xmm2 b)
; Six textured quads, counter-clockwise seen from outside, in face order +X -X +Y -Y +Z -Z.
; Every face is one whole atlas tile (uv inset 1 unit, tile top edge = box top edge) and
; is coloured shade[face] * (r, g, b). Texture unit 0 and the atlas are set up by the caller.
render_box:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [rsp] r, g, b; +12 u0; +16 v0
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
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
    movzx   eax, byte [r12 + r14]       ; atlas tile of this face
    mov     edx, eax
    and     eax, 15
    shl     eax, 8
    inc     eax
    mov     [rsp + 12], eax             ; u0 = col * 256 + 1
    shr     edx, 4
    shl     edx, 8
    inc     edx
    mov     [rsp + 16], edx             ; v0 = row * 256 + 1
    xor     r15d, r15d                  ; corner
.corner:
    mov     edi, [rsp + 12]
    add     edi, [corner_du + r15*4]
    mov     esi, [rsp + 16]
    add     esi, [corner_dv + r15*4]
    call    glTexCoord2i
    lea     eax, [r14*4 + r15]
    lea     eax, [rax + rax*2]          ; offset of the corner's three lo/hi bits
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
; r15 = cam, r12d = width, r13d = height, ebx = chunk index, r14d = chunk vertex count
render_world:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r15, rdi
    mov     r12d, esi
    mov     r13d, edx

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
    movss   xmm1, [f_one]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    glRotatef
    movss   xmm0, [r15 + BODY.yaw]
    xorps   xmm1, xmm1
    movss   xmm2, [f_one]
    xorps   xmm3, xmm3
    call    glRotatef
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

    ; ---- fog and draw distance from the render distance -----------------------
    cvtsi2ss xmm0, dword [settings + SETTINGS.render_dist]
    mulss   xmm0, [f_16]                ; fog end = render_dist * 16
    movss   xmm1, xmm0
    addss   xmm1, [f_8]
    mulss   xmm1, xmm1
    movss   [lim2], xmm1                ; chunks are drawn up to (end + 8)^2
    mov     edi, GL_FOG_END
    call    glFogf
    cvtsi2ss xmm0, dword [settings + SETTINGS.render_dist]
    mulss   xmm0, [f_16]
    mulss   xmm0, [f_fog_near]
    mov     edi, GL_FOG_START
    call    glFogf
    mov     edi, GL_FOG_COLOR
    lea     rsi, [fog_rgba]
    call    glFogfv

    ; ---- night darkening: unit 1 multiplies the lit texel by (b, b, b) --------
    mov     edi, GL_TEXTURE1
    call    glActiveTexture
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     eax, [bright]
    mov     [env_rgba], eax
    mov     [env_rgba + 4], eax
    mov     [env_rgba + 8], eax
    mov     dword [env_rgba + 12], __float32__(1.0)
    mov     edi, GL_TEXTURE_ENV
    mov     esi, GL_TEXTURE_ENV_COLOR
    lea     rdx, [env_rgba]
    call    glTexEnvfv
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
    mov     edi, GL_VERTEX_ARRAY
    call    glEnableClientState
    mov     edi, GL_TEXTURE_COORD_ARRAY
    call    glEnableClientState
    mov     edi, GL_COLOR_ARRAY
    call    glEnableClientState

    xor     ebx, ebx
.chunk:
    mov     r14d, [chunk_count + rbx*4]
    test    r14d, r14d
    jz      .chunk_next
    mov     eax, ebx
    and     eax, 15
    shl     eax, 4
    add     eax, 8
    cvtsi2ss xmm0, eax
    subss   xmm0, [eye]
    mulss   xmm0, xmm0
    mov     eax, ebx
    shr     eax, 4
    and     eax, 15
    shl     eax, 4
    add     eax, 8
    cvtsi2ss xmm1, eax
    subss   xmm1, [eye + 8]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1
    comiss  xmm0, [lim2]
    ja      .chunk_next
    mov     edi, GL_ARRAY_BUFFER
    mov     esi, [chunk_vbo + rbx*4]
    call    glBindBuffer
    mov     edi, 3
    mov     esi, GL_SHORT
    mov     edx, VERTEX_SIZE
    xor     ecx, ecx
    call    glVertexPointer
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
    mov     edi, GL_QUADS
    xor     esi, esi
    mov     edx, r14d
    call    glDrawArrays
.chunk_next:
    inc     ebx
    cmp     ebx, NUM_CHUNKS
    jb      .chunk

    mov     edi, GL_VERTEX_ARRAY
    call    glDisableClientState
    mov     edi, GL_TEXTURE_COORD_ARRAY
    call    glDisableClientState
    mov     edi, GL_COLOR_ARRAY
    call    glDisableClientState
    mov     edi, GL_ARRAY_BUFFER
    xor     esi, esi
    call    glBindBuffer
    call    mobs_render
    call    drops_render
    call    arrows_render
    call    tnt_render

    ; ---- target block: crack overlay, then the outline -------------------------
    cmp     dword [game_has_target], 0
    je      .after_crack
    xor     ecx, ecx
.box_axis:
    cvtsi2ss xmm0, dword [game_target + RAYHIT.bx + rcx*4]
    movss   xmm1, xmm0
    addss   xmm0, [f_lo]
    addss   xmm1, [f_hi]
    movss   [box + rcx*4], xmm0
    movss   [box + 12 + rcx*4], xmm1
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
    cmp     dword [game_has_target], 0
    je      .done
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
.done:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
