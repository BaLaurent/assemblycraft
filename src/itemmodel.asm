; itemmodel.asm - 3D model of an item, shared by the first-person hand and dropped items.
; Cubes, slabs and stairs are boxes carrying the block's own tiles (slabs and stairs in the
; north-facing item form of shapes.asm); every other item - tools, food, doors, torches,
; ladders, fences, panes - is its icon extruded 1/16 thick (front and back faces plus a side
; face on every pixel edge that borders transparency).
%include "common.inc"
%include "gl.inc"
default rel

global item_model_draw, item_model_is_block

extern render_box16, render_box_px16, atlas, block_tiles, block_shape, item_icon, item_max_stack
extern shape_boxes

section .rodata
align 4
cube:        dd -0.5, -0.5, -0.5, 0.5, 0.5, 0.5
; block faces +X -X +Y -Y +Z -Z: side, side, top, bottom, side, side shades
cube_shade:  dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8
f_half:      dd 0.5
f_px:        dd 0.0625                  ; one icon pixel
f_h:         dd 0.03125                 ; half thickness
f_one:       dd 1.0
f_side:      dd 0.7
f_bottom:    dd 0.5

section .bss
alignb 4
shades:      resd 6
tiles:       resw 6
light:       resd 1
quad_x0:     resd 1                     ; current pixel box
quad_x1:     resd 1
quad_y0:     resd 1
quad_y1:     resd 1
pxboxes:     resb 6 * MAX_SHAPE_BOXES   ; shape boxes in 1/16 block, cell-relative
alignb 4
fbox:        resd 6                     ; one of them in model space

section .text

; item_model_is_block(edi id) -> eax 1 when the id is a block drawn as boxes with its own tiles
; (cube, slab or stairs); 0 for items and for the blocks drawn as icon sprites
item_model_is_block:
    mov     edi, edi
    xor     eax, eax
    cmp     edi, NUM_BLOCKS
    jae     .ret
    movzx   ecx, byte [block_shape + rdi]
    cmp     ecx, SHAPE_CUBE
    je      .yes
    cmp     ecx, SHAPE_SLAB
    je      .yes
    cmp     ecx, SHAPE_STAIRS
    jne     .ret
.yes:
    mov     eax, 1
.ret:
    ret

; item_model_draw(edi id, xmm0 light): model centred on the origin, 1 unit wide, in the
; current modelview; the atlas must be bound on texture unit 0 with alpha test on.
item_model_draw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    movss   [light], xmm0
    mov     ebx, edi
    cmp     ebx, NUM_ITEMS
    jae     .ret
    cmp     byte [item_max_stack + rbx], 0
    je      .ret                        ; air and unused ids
    mov     edi, ebx
    call    item_model_is_block
    test    eax, eax
    jz      .sprite

    ; ---- block: the block's own tiles on a cube, or on the boxes of a slab / stairs ------
    lea     eax, [rbx + rbx*2]
    movzx   ecx, word [block_tiles + rax*2]      ; top
    movzx   edx, word [block_tiles + rax*2 + 2]  ; side
    movzx   esi, word [block_tiles + rax*2 + 4]  ; bottom
    mov     [tiles], dx
    mov     [tiles + 2], dx
    mov     [tiles + 4], cx
    mov     [tiles + 6], si
    mov     [tiles + 8], dx
    mov     [tiles + 10], dx
    xor     ecx, ecx
.shade:
    movss   xmm0, [cube_shade + rcx*4]
    mulss   xmm0, [light]
    movss   [shades + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 6
    jb      .shade
    cmp     byte [block_shape + rbx], SHAPE_CUBE
    jne     .boxes
    lea     rdi, [cube]
    lea     rsi, [tiles]
    lea     rdx, [shades]
    movss   xmm0, [f_one]
    movss   xmm1, [f_one]
    movss   xmm2, [f_one]
    call    render_box16
    jmp     .ret

    ; slab / stairs: the RENDER boxes of the item form, each mapped to model space as px / 16 - 0.5
.boxes:
    mov     edi, ebx
    xor     esi, esi
    xor     edx, edx
    xor     ecx, ecx
    lea     r8, [pxboxes]
    mov     r9d, BOXES_RENDER
    call    shape_boxes
    mov     r12d, eax                   ; box count
    xor     r13d, r13d
.box:
    cmp     r13d, r12d
    jae     .ret
    imul    eax, r13d, 6
    lea     r14, [pxboxes]
    add     r14, rax
    xor     ecx, ecx
.model_box:
    movzx   eax, byte [r14 + rcx]
    cvtsi2ss xmm0, eax
    mulss   xmm0, [f_px]
    subss   xmm0, [f_half]
    movss   [fbox + rcx*4], xmm0
    inc     ecx
    cmp     ecx, 6
    jb      .model_box
    lea     rdi, [fbox]
    lea     rsi, [tiles]
    lea     rdx, [shades]
    movss   xmm0, [f_one]
    movss   xmm1, [f_one]
    movss   xmm2, [f_one]
    mov     rcx, r14
    call    render_box_px16
    inc     r13d
    jmp     .box

    ; ---- sprite: front and back faces with the whole icon ----------------------
.sprite:
    movzx   r12d, byte [item_icon + rbx]   ; tile
    mov     r13d, r12d
    and     r13d, 15
    shl     r13d, 8                     ; u0 = col * 256
    mov     r14d, r12d
    shr     r14d, 4
    shl     r14d, 8                     ; v0 = row * 256
    mov     edi, GL_QUADS
    call    glBegin
    movss   xmm0, [light]
    movss   xmm1, xmm0
    movss   xmm2, xmm0
    movss   xmm3, [f_one]
    call    glColor4f
%macro VTX 5                            ; u, v, x, y, z (z: +1 front, -1 back)
    lea     edi, [%1]
    lea     esi, [%2]
    call    glTexCoord2i
    movss   xmm0, [f_half]
%if %3 < 0
    xorps   xmm0, xmm0
    subss   xmm0, [f_half]
%endif
    movss   xmm1, [f_half]
%if %4 < 0
    xorps   xmm1, xmm1
    subss   xmm1, [f_half]
%endif
    movss   xmm2, [f_h]
%if %5 < 0
    xorps   xmm2, xmm2
    subss   xmm2, [f_h]
%endif
    call    glVertex3f
%endmacro
    ; front (+z): bottom-left, bottom-right, top-right, top-left
    VTX     {r13 + 1},   {r14 + 255}, -1, -1, 1
    VTX     {r13 + 255}, {r14 + 255},  1, -1, 1
    VTX     {r13 + 255}, {r14 + 1},    1,  1, 1
    VTX     {r13 + 1},   {r14 + 1},   -1,  1, 1
    ; back (-z): same texels, reversed winding
    VTX     {r13 + 1},   {r14 + 255}, -1, -1, -1
    VTX     {r13 + 1},   {r14 + 1},   -1,  1, -1
    VTX     {r13 + 255}, {r14 + 1},    1,  1, -1
    VTX     {r13 + 255}, {r14 + 255},  1, -1, -1

    ; ---- side faces on every opaque pixel edge next to transparency -------------
    ; r15d = py, ebx = px; [atlas + ((row*16 + py) * 256 + col*16 + px) * 4 + 3] = alpha
    xor     r15d, r15d
.py:
    xor     ebx, ebx
.px:
    mov     edi, ebx
    mov     esi, r15d
    call    texel_alpha
    test    eax, eax
    jz      .px_next
    ; pixel box: x0 = -0.5 + px/16, y1 = 0.5 - py/16
    cvtsi2ss xmm0, ebx
    mulss   xmm0, [f_px]
    subss   xmm0, [f_half]
    movss   [quad_x0], xmm0
    addss   xmm0, [f_px]
    movss   [quad_x1], xmm0
    cvtsi2ss xmm0, r15d
    mulss   xmm0, [f_px]
    movss   xmm1, [f_half]
    subss   xmm1, xmm0
    movss   [quad_y1], xmm1
    subss   xmm1, [f_px]
    movss   [quad_y0], xmm1
    ; every edge quad of this pixel samples the pixel's own texel
    mov     edi, ebx
    shl     edi, 4
    lea     edi, [r13 + rdi + 8]
    mov     esi, r15d
    shl     esi, 4
    lea     esi, [r14 + rsi + 8]
    call    glTexCoord2i
    ; left (-X)
    lea     edi, [rbx - 1]
    mov     esi, r15d
    call    texel_alpha
    test    eax, eax
    jnz     .no_left
    movss   xmm0, [f_side]
    call    edge_color
    mov     edi, 0
    call    edge_quad
.no_left:
    lea     edi, [rbx + 1]
    mov     esi, r15d
    call    texel_alpha
    test    eax, eax
    jnz     .no_right
    movss   xmm0, [f_side]
    call    edge_color
    mov     edi, 1
    call    edge_quad
.no_right:
    mov     edi, ebx
    lea     esi, [r15 - 1]
    call    texel_alpha
    test    eax, eax
    jnz     .no_top
    movss   xmm0, [f_one]
    call    edge_color
    mov     edi, 2
    call    edge_quad
.no_top:
    mov     edi, ebx
    lea     esi, [r15 + 1]
    call    texel_alpha
    test    eax, eax
    jnz     .px_next
    movss   xmm0, [f_bottom]
    call    edge_color
    mov     edi, 3
    call    edge_quad
.px_next:
    inc     ebx
    cmp     ebx, 16
    jb      .px
    inc     r15d
    cmp     r15d, 16
    jb      .py
    call    glEnd
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; texel_alpha(edi px, esi py) -> eax alpha of the icon pixel (0 outside the tile).
; Reads the icon tile from r12d (callee-saved in item_model_draw).
texel_alpha:
    xor     eax, eax
    cmp     edi, 15
    ja      .ret
    cmp     esi, 15
    ja      .ret
    mov     ecx, r12d
    shr     ecx, 4
    shl     ecx, 4
    add     ecx, esi                    ; atlas row = row*16 + py
    shl     ecx, 8
    mov     edx, r12d
    and     edx, 15
    shl     edx, 4
    add     edx, edi                    ; atlas column = col*16 + px
    add     ecx, edx
    lea     rdx, [atlas]
    movzx   eax, byte [rdx + rcx*4 + 3]
.ret:
    ret

; edge_color(xmm0 shade): glColor = shade * light
edge_color:
    sub     rsp, 8
    mulss   xmm0, [light]
    movss   xmm1, xmm0
    movss   xmm2, xmm0
    movss   xmm3, [f_one]
    call    glColor4f
    add     rsp, 8
    ret

; edge_quad(edi side 0 left / 1 right / 2 top / 3 bottom): one side face of the current
; pixel box, counter-clockwise seen from outside
edge_quad:
    push    rbx
    push    r12
    sub     rsp, 24                     ; 4 corners as (x, y, zsign) indices into a table
    mov     ebx, edi
    lea     r12, [edge_corners]
    imul    eax, ebx, 12
    add     r12, rax
    xor     ecx, ecx
.corner:
    mov     [rsp], ecx
    lea     edx, [rcx + rcx*2]
    movzx   eax, byte [r12 + rdx]       ; 0 = x0, 1 = x1
    movss   xmm0, [quad_x0 + rax*4]
    movzx   eax, byte [r12 + rdx + 1]   ; 0 = y0, 1 = y1
    movss   xmm1, [quad_y0 + rax*4]
    movss   xmm2, [f_h]
    cmp     byte [r12 + rdx + 2], 0
    jne     .zpos
    xorps   xmm2, xmm2
    subss   xmm2, [f_h]
.zpos:
    call    glVertex3f
    mov     ecx, [rsp]
    inc     ecx
    cmp     ecx, 4
    jb      .corner
    add     rsp, 24
    pop     r12
    pop     rbx
    ret

section .rodata
; per side: 4 corners of (x index, y index, z positive?)
edge_corners:
    db 0,0,0,  0,0,1,  0,1,1,  0,1,0    ; left  (-X)
    db 1,0,1,  1,0,0,  1,1,0,  1,1,1    ; right (+X)
    db 0,1,1,  1,1,1,  1,1,0,  0,1,0    ; top   (+Y)
    db 0,0,0,  1,0,0,  1,0,1,  0,0,1    ; bottom (-Y)
