; itemmodel.asm - 3D model of an item, shared by the first-person hand, dropped items and the
; items held in other hands (held_item_draw: mobs, folk, other players).
; Cubes, slabs and stairs are boxes carrying the block's own tiles (slabs and stairs in the
; north-facing item form of shapes.asm); every other item - tools, food, doors, torches,
; ladders, fences, panes - is its icon extruded 1/16 thick (front and back faces plus a side
; face on every pixel edge that borders transparency). The extrusion reads any square rect of
; the atlas, spr_x0 / spr_y0 / spr_n (n = 16 for an icon tile, 32 for an icon cell), one pixel
; box 1/n wide per texel.
%include "common.inc"
%include "gl.inc"
default rel

global item_model_draw, item_model_is_block, held_item_draw

extern render_box16, render_box_px16, atlas, block_tiles, block_shape, item_icon, item_max_stack
extern shape_boxes, gun_index, gun_model_draw

section .rodata
align 4
cube:        dd -0.5, -0.5, -0.5, 0.5, 0.5, 0.5
; block faces +X -X +Y -Y +Z -Z: side, side, top, bottom, side, side shades
cube_shade:  dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8
f_half:      dd 0.5
f_px:        dd 0.0625                  ; 1/16 block: one shape-box unit
f_h:         dd 0.03125                 ; half thickness
f_one:       dd 1.0
f_side:      dd 0.7
f_bottom:    dd 0.5
; held_item_draw: how an item sits in a holder's hand
f_hold_gun:       dd 0.6                ; firearm scale
f_hold_blk_y:     dd -0.05              ; block: a little below and in front of the fist,
f_hold_blk_z:     dd -0.12
f_hold_blk_ang:   dd 45.0               ;   turned about Y,
f_hold_blk_s:     dd 0.3                ;   scaled
f_hold_item_ang:  dd 90.0               ; other items: the icon plane turned about Y,
f_hold_item_s:    dd 0.55               ;   scaled,
f_hold_item_t:    dd 0.3                ;   its lower-left grip moved to the hand (x and y)

section .bss
alignb 4
shades:      resd 6
tiles:       resw 6
light:       resd 1
quad_x0:     resd 1                     ; current pixel box
quad_x1:     resd 1
quad_y0:     resd 1
quad_y1:     resd 1
spr_x0:      resd 1                     ; the atlas rect the sprite path extrudes: first texel,
spr_y0:      resd 1
spr_n:       resd 1                     ;   side in texels (16 an icon tile, 32 an icon cell)
spr_px:      resd 1                     ;   float 1 / n: one texel's box in blocks
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
    mov     edi, ebx
    call    sprite_source               ; spr_x0, spr_y0, spr_n, spr_px of this item's icon
    mov     r13d, [spr_x0]
    shl     r13d, 4                     ; u0 = x0 * 16 (texcoords are in 1/16 texel units)
    mov     r14d, [spr_y0]
    shl     r14d, 4                     ; v0 = y0 * 16
    mov     r12d, [spr_n]
    shl     r12d, 4
    dec     r12d                        ; n * 16 - 1: the far texcoord offset, 1 unit inset
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
    VTX     {r13 + 1},   {r14 + r12}, -1, -1, 1
    VTX     {r13 + r12}, {r14 + r12},  1, -1, 1
    VTX     {r13 + r12}, {r14 + 1},    1,  1, 1
    VTX     {r13 + 1},   {r14 + 1},   -1,  1, 1
    ; back (-z): same texels, reversed winding
    VTX     {r13 + 1},   {r14 + r12}, -1, -1, -1
    VTX     {r13 + 1},   {r14 + 1},   -1,  1, -1
    VTX     {r13 + r12}, {r14 + 1},    1,  1, -1
    VTX     {r13 + r12}, {r14 + r12},  1, -1, -1

    ; ---- side faces on every opaque pixel edge next to transparency -------------
    ; r15d = py, ebx = px; texel_alpha reads the alpha of texel (x0 + px, y0 + py)
    xor     r15d, r15d
.py:
    xor     ebx, ebx
.px:
    mov     edi, ebx
    mov     esi, r15d
    call    texel_alpha
    test    eax, eax
    jz      .px_next
    ; pixel box: x0 = -0.5 + px / n, y1 = 0.5 - py / n
    cvtsi2ss xmm0, ebx
    mulss   xmm0, [spr_px]
    subss   xmm0, [f_half]
    movss   [quad_x0], xmm0
    addss   xmm0, [spr_px]
    movss   [quad_x1], xmm0
    cvtsi2ss xmm0, r15d
    mulss   xmm0, [spr_px]
    movss   xmm1, [f_half]
    subss   xmm1, xmm0
    movss   [quad_y1], xmm1
    subss   xmm1, [spr_px]
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
    cmp     ebx, [spr_n]
    jb      .px
    inc     r15d
    cmp     r15d, [spr_n]
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

; held_item_draw(edi id, xmm0 light): item id in a holder's hand, in the current modelview with its origin
; at the hand, units blocks, the holder facing -Z, +Y up; the atlas bound with alpha test on. Its own matrix
; is bracketed by glPushMatrix / glPopMatrix.
;   firearm (gun_index >= 0): scaled 0.6, drawn loaded and without a muzzle flash;
;   block (cube, slab, stairs): a 0.3 cube a little below and in front of the fist, turned 45 degrees;
;   anything else: the extruded icon turned 90 degrees about Y (its XY plane becomes the holder's YZ plane),
;   scaled 0.55 and shifted by (0.3, 0.3, 0) before the scale, so that its lower-left grip lands on the
;   hand and its upper-right tip points forward (-Z) and up.
held_item_draw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8                      ; [rsp] light
    mov     ebx, edi
    movss   [rsp], xmm0
    call    glPushMatrix
    mov     edi, ebx
    call    gun_index
    test    eax, eax
    js      .not_gun
    movss   xmm0, [f_hold_gun]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    glScalef
    mov     edi, ebx
    mov     esi, 1                      ; loaded
    movss   xmm0, [rsp]
    xorps   xmm1, xmm1                  ; no kick, so no muzzle flash
    call    gun_model_draw
    jmp     .pop
.not_gun:
    mov     edi, ebx
    call    item_model_is_block
    test    eax, eax
    jz      .item
    xorps   xmm0, xmm0
    movss   xmm1, [f_hold_blk_y]
    movss   xmm2, [f_hold_blk_z]
    call    glTranslatef
    movss   xmm0, [f_hold_blk_ang]
    xorps   xmm1, xmm1
    movss   xmm2, [f_one]
    xorps   xmm3, xmm3
    call    glRotatef
    movss   xmm0, [f_hold_blk_s]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    glScalef
    jmp     .model
.item:
    movss   xmm0, [f_hold_item_ang]
    xorps   xmm1, xmm1
    movss   xmm2, [f_one]
    xorps   xmm3, xmm3
    call    glRotatef
    movss   xmm0, [f_hold_item_s]
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    glScalef
    movss   xmm0, [f_hold_item_t]
    movaps  xmm1, xmm0
    xorps   xmm2, xmm2
    call    glTranslatef
.model:
    mov     edi, ebx
    movss   xmm0, [rsp]
    call    item_model_draw
.pop:
    call    glPopMatrix
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; sprite_source(edi id): chooses the atlas rect the sprite path extrudes for item id and stores it with
; sprite_set: today the id's 16x16 icon tile from item_icon. Clobbers eax, edx, esi, edi, xmm0, xmm1.
sprite_source:
    movzx   eax, word [item_icon + rdi*2]   ; tile
    mov     edi, eax
    and     edi, 15
    shl     edi, 4                      ; x0 = col * 16
    shr     eax, 4
    shl     eax, 4
    mov     esi, eax                    ; y0 = row * 16
    mov     edx, TILE_PX
    jmp     sprite_set

; sprite_set(edi x0, esi y0, edx n): the sprite path extrudes the n x n texels of the atlas from texel
; (x0, y0); spr_px = 1 / n is the width of one texel's box in blocks. Clobbers xmm0, xmm1.
sprite_set:
    mov     [spr_x0], edi
    mov     [spr_y0], esi
    mov     [spr_n], edx
    movss   xmm0, [f_one]
    cvtsi2ss xmm1, edx
    divss   xmm0, xmm1
    movss   [spr_px], xmm0
    ret

; texel_alpha(edi px, esi py) -> eax alpha of texel (spr_x0 + px, spr_y0 + py) of the atlas, 0 outside
; the spr_n x spr_n source rect (a negative px or py is a huge unsigned value, so it is outside too).
; Clobbers ecx, edx.
texel_alpha:
    xor     eax, eax
    mov     ecx, [spr_n]
    cmp     edi, ecx
    jae     .ret
    cmp     esi, ecx
    jae     .ret
    mov     edx, esi
    add     edx, [spr_y0]               ; atlas row = y0 + py
    imul    edx, edx, ATLAS_W
    add     edx, [spr_x0]
    add     edx, edi                    ; atlas texel = row * ATLAS_W + x0 + px
    lea     rcx, [atlas]
    movzx   eax, byte [rcx + rdx*4 + 3]
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
