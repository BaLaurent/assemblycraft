; render.asm - texture atlas, chunk VBOs, world pass, target outline and HUD.
%include "common.inc"
%include "gl.inc"
default rel

global render_init, render_update_chunks, render_frame

extern texgen_build, mesh_chunk, mesh_scratch, chunk_dirty, block_tiles
extern player, player_eye, hotbar, hotbar_sel, game_target, game_has_target

section .rodata
align 8
d_hh:      dq 0.035010377               ; 0.05 * tan(35 deg): 70 deg vertical FOV
d_near:    dq 0.05
d_far:     dq 300.0
d_one:     dq 1.0
d_mone:    dq -1.0
align 4
f_texscale: dd 0.000244140625           ; 1/4096: texcoords are 1/16 px units
f_zero:    dd 0.0
f_one:     dd 1.0
f_two:     dd 2.0
f_half:    dd 0.5
f_fog_start: dd 80.0
f_fog_end: dd 128.0
f_sky_r:   dd 0.62
f_sky_g:   dd 0.80
f_hud_bg:  dd 0.45
f_lo:      dd -0.002
f_hi:      dd 1.002
f_draw_d2: dd 19600.0                   ; 140^2
fog_color: dd 0.62, 0.80, 1.0, 1.0
; 12 box edges as corner pairs; corner bit0 = x, bit1 = y, bit2 = z (0 lo, 1 hi)
box_edges: db 0,1, 2,3, 4,5, 6,7,  0,2, 1,3, 4,6, 5,7,  0,4, 1,5, 2,6, 3,7

section .bss
alignb 16
atlas:       resb ATLAS_PX * ATLAS_PX * 4
chunk_vbo:   resd NUM_CHUNKS
chunk_count: resd NUM_CHUNKS
tex_id:      resd 1
eye:         resd 3
box_lo:      resd 3
box_hi:      resd 3

section .text

; render_init(): atlas texture, texture matrix, VBO names, fog, alpha test
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
    mov     qword [rsp], GL_RGBA
    mov     qword [rsp + 8], GL_UNSIGNED_BYTE
    lea     rax, [atlas]
    mov     [rsp + 16], rax
    mov     edi, GL_TEXTURE_2D
    xor     esi, esi
    mov     edx, GL_RGBA
    mov     ecx, ATLAS_PX
    mov     r8d, ATLAS_PX
    xor     r9d, r9d
    call    glTexImage2D
%macro TEXPARAM 2
    mov     edi, GL_TEXTURE_2D
    mov     esi, %1
    mov     edx, %2
    call    glTexParameteri
%endmacro
    TEXPARAM GL_TEXTURE_MIN_FILTER, GL_NEAREST
    TEXPARAM GL_TEXTURE_MAG_FILTER, GL_NEAREST
    TEXPARAM GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE
    TEXPARAM GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE

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
    mov     edi, GL_FOG_START
    movss   xmm0, [f_fog_start]
    call    glFogf
    mov     edi, GL_FOG_END
    movss   xmm0, [f_fog_end]
    call    glFogf
    mov     edi, GL_FOG_COLOR
    lea     rsi, [fog_color]
    call    glFogfv
    mov     edi, GL_GREATER
    movss   xmm0, [f_half]
    call    glAlphaFunc
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

; hud_quad(edi x, esi y, edx w, ecx h): untextured screen-space quad
hud_quad:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r12d, esi
    lea     r13d, [rdi + rdx]           ; x + w
    lea     r14d, [rsi + rcx]           ; y + h
    mov     edi, GL_QUADS
    call    glBegin
    mov     edi, ebx
    mov     esi, r12d
    call    glVertex2i
    mov     edi, r13d
    mov     esi, r12d
    call    glVertex2i
    mov     edi, r13d
    mov     esi, r14d
    call    glVertex2i
    mov     edi, ebx
    mov     esi, r14d
    call    glVertex2i
    call    glEnd
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; hud_icon(edi x, esi y, edx tile): 32x32 textured quad of one atlas tile
hud_icon:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     ebx, edi                    ; x
    mov     r12d, esi                   ; y
    mov     eax, edx
    and     eax, 15
    shl     eax, 8
    lea     r13d, [rax + 1]             ; u0
    shr     edx, 4
    shl     edx, 8
    lea     r14d, [rdx + 1]             ; v0
    mov     edi, GL_QUADS
    call    glBegin
    mov     edi, r13d
    mov     esi, r14d
    call    glTexCoord2i
    mov     edi, ebx
    mov     esi, r12d
    call    glVertex2i
    lea     edi, [r13 + 254]
    mov     esi, r14d
    call    glTexCoord2i
    lea     edi, [rbx + 32]
    mov     esi, r12d
    call    glVertex2i
    lea     edi, [r13 + 254]
    lea     esi, [r14 + 254]
    call    glTexCoord2i
    lea     edi, [rbx + 32]
    lea     esi, [r12 + 32]
    call    glVertex2i
    mov     edi, r13d
    lea     esi, [r14 + 254]
    call    glTexCoord2i
    mov     edi, ebx
    lea     esi, [r12 + 32]
    call    glVertex2i
    call    glEnd
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; render_frame(edi fb_w, esi fb_h)
render_frame:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12d, edi                   ; w
    mov     r13d, esi                   ; h

    ; ---- world pass -------------------------------------------------------
    xor     edi, edi
    xor     esi, esi
    mov     edx, r12d
    mov     ecx, r13d
    call    glViewport
    movss   xmm0, [f_sky_r]
    movss   xmm1, [f_sky_g]
    movss   xmm2, [f_one]
    movss   xmm3, [f_one]
    call    glClearColor
    mov     edi, GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT
    call    glClear

    mov     edi, GL_PROJECTION
    call    glMatrixMode
    call    glLoadIdentity
    cvtsi2sd xmm0, r12d
    cvtsi2sd xmm1, r13d
    divsd   xmm0, xmm1
    mulsd   xmm0, [d_hh]                ; hh * aspect
    movapd  xmm1, xmm0
    xorpd   xmm0, xmm0
    subsd   xmm0, xmm1
    movsd   xmm3, [d_hh]
    xorpd   xmm2, xmm2
    subsd   xmm2, xmm3
    movsd   xmm4, [d_near]
    movsd   xmm5, [d_far]
    call    glFrustum

    mov     edi, GL_MODELVIEW
    call    glMatrixMode
    call    glLoadIdentity
    movss   xmm0, [player + PLAYER.pitch]
    movss   xmm1, [f_one]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    glRotatef
    movss   xmm0, [player + PLAYER.yaw]
    xorps   xmm1, xmm1
    movss   xmm2, [f_one]
    xorps   xmm3, xmm3
    call    glRotatef
    lea     rdi, [eye]
    call    player_eye
    xorps   xmm0, xmm0
    subss   xmm0, [eye]
    xorps   xmm1, xmm1
    subss   xmm1, [eye + 4]
    xorps   xmm2, xmm2
    subss   xmm2, [eye + 8]
    call    glTranslatef

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
    comiss  xmm0, [f_draw_d2]
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

    ; ---- target outline ---------------------------------------------------
    cmp     dword [game_has_target], 0
    je      .hud
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
    xor     ecx, ecx
.box_axis:
    cvtsi2ss xmm0, dword [game_target + RAYHIT.bx + rcx*4]
    movss   xmm1, xmm0
    addss   xmm0, [f_lo]
    addss   xmm1, [f_hi]
    movss   [box_lo + rcx*4], xmm0
    movss   [box_hi + rcx*4], xmm1
    inc     ecx
    cmp     ecx, 3
    jb      .box_axis
    mov     edi, GL_LINES
    call    glBegin
    xor     ebx, ebx
.edge:
    movzx   eax, byte [box_edges + rbx]
    movss   xmm0, [box_lo]
    test    eax, 1
    jz      .ex
    movss   xmm0, [box_hi]
.ex:
    movss   xmm1, [box_lo + 4]
    test    eax, 2
    jz      .ey
    movss   xmm1, [box_hi + 4]
.ey:
    movss   xmm2, [box_lo + 8]
    test    eax, 4
    jz      .ez
    movss   xmm2, [box_hi + 8]
.ez:
    call    glVertex3f
    inc     ebx
    cmp     ebx, 24
    jb      .edge
    call    glEnd

    ; ---- HUD --------------------------------------------------------------
.hud:
    mov     edi, GL_DEPTH_TEST
    call    glDisable
    mov     edi, GL_CULL_FACE
    call    glDisable
    mov     edi, GL_FOG
    call    glDisable
    mov     edi, GL_PROJECTION
    call    glMatrixMode
    call    glLoadIdentity
    xorpd   xmm0, xmm0
    cvtsi2sd xmm1, r12d
    cvtsi2sd xmm2, r13d
    xorpd   xmm3, xmm3
    movsd   xmm4, [d_mone]
    movsd   xmm5, [d_one]
    call    glOrtho
    mov     edi, GL_MODELVIEW
    call    glMatrixMode
    call    glLoadIdentity

    mov     r14d, r12d
    sub     r14d, 396
    sar     r14d, 1                     ; x0
    lea     r15d, [r13 - 52]            ; y0

    ; translucent hotbar background
    mov     edi, GL_BLEND
    call    glEnable
    mov     edi, GL_SRC_ALPHA
    mov     esi, GL_ONE_MINUS_SRC_ALPHA
    call    glBlendFunc
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    xorps   xmm0, xmm0
    xorps   xmm1, xmm1
    xorps   xmm2, xmm2
    movss   xmm3, [f_hud_bg]
    call    glColor4f
    lea     edi, [r14 - 2]
    lea     esi, [r15 - 2]
    mov     edx, 400
    mov     ecx, 48
    call    hud_quad

    ; block icons (side tile of each slot)
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     edi, GL_ALPHA_TEST
    call    glEnable
    movss   xmm0, [f_one]
    movss   xmm1, [f_one]
    movss   xmm2, [f_one]
    movss   xmm3, [f_one]
    call    glColor4f
    xor     ebx, ebx
.icon:
    movzx   eax, byte [hotbar + rbx]
    lea     eax, [rax + rax*2]
    movzx   edx, byte [block_tiles + rax + 1]
    imul    edi, ebx, 44
    lea     edi, [rdi + r14 + 6]
    lea     esi, [r15 + 6]
    call    hud_icon
    inc     ebx
    cmp     ebx, HOTBAR_SLOTS
    jb      .icon

    ; selection frame
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    movss   xmm0, [f_two]
    call    glLineWidth
    imul    ebx, [hotbar_sel], 44
    add     ebx, r14d
    mov     edi, GL_LINE_LOOP
    call    glBegin
    lea     edi, [rbx + 1]
    lea     esi, [r15 + 1]
    call    glVertex2i
    lea     edi, [rbx + 43]
    lea     esi, [r15 + 1]
    call    glVertex2i
    lea     edi, [rbx + 43]
    lea     esi, [r15 + 43]
    call    glVertex2i
    lea     edi, [rbx + 1]
    lea     esi, [r15 + 43]
    call    glVertex2i
    call    glEnd

    ; inverting crosshair (vertical bar split so the centre inverts once)
    mov     edi, GL_ONE_MINUS_DST_COLOR
    mov     esi, GL_ZERO
    call    glBlendFunc
    mov     ebx, r12d
    sar     ebx, 1                      ; cx
    mov     r14d, r13d
    sar     r14d, 1                     ; cy
    lea     edi, [rbx - 10]
    lea     esi, [r14 - 1]
    mov     edx, 20
    mov     ecx, 2
    call    hud_quad
    lea     edi, [rbx - 1]
    lea     esi, [r14 - 10]
    mov     edx, 2
    mov     ecx, 9
    call    hud_quad
    lea     edi, [rbx - 1]
    lea     esi, [r14 + 1]
    mov     edx, 2
    mov     ecx, 9
    call    hud_quad
    mov     edi, GL_SRC_ALPHA
    mov     esi, GL_ONE_MINUS_SRC_ALPHA
    call    glBlendFunc
    mov     edi, GL_BLEND
    call    glDisable

    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
