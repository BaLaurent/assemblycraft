; skin.asm: the skinned box models of the 0.13 "looks" (characters, vehicles, guns). A model is a stream
; of 20-byte bone and part records plus a list of paint ops (art.inc, common.inc "0.13 looks"); this file
; packs the models' unwraps into the skin region of the atlas, paints them, and draws them.
;
;   skin_build(rdi atlas, rsi registry) -> eax 0 fits / 1 overflow
;       registry = SKMODEL* array, 0-terminated. Packs first (registry order, record order; a shelf cursor
;       from (0, SKIN_Y0), a part's unwrap footprint is 2(w+d) x (d+h) texels; a SKPART_AS part copies the
;       size and place of its source), then paints every model's ops. On overflow nothing is painted.
;   skin_face_rect(rdi part, esi face) -> eax u, edx v, ecx width, r8d height (atlas texels)
;   skin_face_uvs(rdi part, esi face, rdx out dd[8])   the four corners' (u, v) in 1/16 texel units
;   skin_model_draw(rdi SKMODEL*, rsi SKPOSE* or 0, xmm0 swing_deg, xmm1 r, xmm2 g, xmm3 b)
;   skin_check(rdi atlas, rsi registry) -> eax 0 / failing check: the proof for a registry (skin_build, then
;       skin_verify), what a test calls
;   skin_verify(rdi atlas, rsi registry) -> eax 0 / failing check: the checks alone, on an atlas already built
;
; Faces are in box_draw order (SKF_RIGHT +X, LEFT -X, TOP +Y, BOTTOM -Y, BACK +Z, FRONT -Z; models face
; -Z). A part's face images are the Minecraft box unwrap, upright as seen from outside (top left = (0, 0)):
;     TOP    (u+d,     v  ) w x d     BOTTOM (u+d+w,   v  ) w x d     RIGHT (u,       v+d) d x h
;     FRONT  (u+d,     v+d) w x h     LEFT   (u+d+w,   v+d) d x h     BACK  (u+2d+w,  v+d) w x h
; Each face is the quad of face_corners (render.asm; counter-clockwise from outside, same winding as
; box_draw). Every corner of a face is one of the four corners of the face's image rectangle, so a face's
; texcoords are the image corners (u_f + ix, v_f + iy), scaled by 16 and pulled one unit into the image
; (+1 at the near edge, -1 at the far edge); corner_xy below is that map, face by face.
;
; Paint ops (all alpha 255, no op can make a texel transparent except SK_BMP with a PALT entry):
;   FILL  every texel of each masked face = colour * m >> 8 per channel, m = 256 - (hash(ax, ay) & noise),
;         (ax, ay) the atlas texel, hash: h = ax * 0x27d4eb2d ^ ay * 0x165667b1; h ^= h >> 15;
;         h *= 0x85ebca6b; h ^= h >> 13 (32 bit)
;   RECT  the same on a face-local rect clipped to the face
;   BMP   art_blit of the SKBMP at the face origin + (x, y), clipped to the face
;   GRAD  the rgb of each texel of each masked face * m(iy) / 256 (clamped to 255, alpha kept),
;         m(iy) = top + (bottom - top) * iy / (fh - 1) (signed division, truncated), top when fh = 1
%include "common.inc"
%include "gl.inc"
default rel

global skin_build, skin_check, skin_verify, skin_face_rect, skin_face_uvs, skin_model_draw, skin_shades

extern art_blit, face_corners, held_item_draw

%define SK_MAX_RECTS   4096             ; own-skin footprints skin_check can compare

; skin_model_draw locals (rsp-relative) and the draw state bits kept in DR_STATE
%define DR_TINT        0                ; float r, g, b
%define DR_SWING       12               ; float walk swing, degrees
%define DR_HELD        16               ; dword resolved held item id
%define DR_STATE       20               ; dword DRS_*
%define DR_KIND        24               ; dword kind of the open bone
%define DR_ANGLE       28               ; float the open bone's angle
%define DR_BOX         32               ; float lo xyz, hi xyz of the part, texels
%define DR_UV          56               ; dword[8] the face's corner texcoords
%define DR_SIZE        88
%define DRS_ACTIVE     1                ; the open bone is drawn (not skipped)
%define DRS_QUADS      2                ; its glBegin(GL_QUADS) has been issued
%define DRS_PUSHED     4                ; it pushed a matrix for its rotation

section .rodata
align 4
skin_shades:    dd 0.6, 0.6, 1.0, 0.5, 0.8, 0.8     ; per face, box_draw order (the mob shades)
f_one:          dd 1.0
f_eighth:       dd 0.125                ; one grow unit, texels
f_held_arm:     dd 20.0                 ; the right arm's raise while it holds an item, degrees
skin_pose_none: dd 0, 0.0, 0, 1.0, 1.0, 1.0         ; SKPOSE: flags, arm_deg, held, accent rgb
; per face: u_f = u + a_d * d + a_w * w, v_f = v + b_d * d, width = (sel_w ? d : w), height = (sel_h ? d : h)
face_rect_tab:  ;  a_d a_w b_d sel_w sel_h
    db 0, 0, 1, 1, 0                    ; RIGHT   (u,        v+d) d x h
    db 1, 1, 1, 1, 0                    ; LEFT    (u+d+w,    v+d) d x h
    db 1, 0, 0, 0, 1                    ; TOP     (u+d,      v  ) w x d
    db 1, 1, 0, 0, 1                    ; BOTTOM  (u+d+w,    v  ) w x d
    db 2, 1, 1, 0, 0                    ; BACK    (u+2d+w,   v+d) w x h
    db 1, 0, 1, 0, 0                    ; FRONT   (u+d,      v+d) w x h
; per face and corner (face_corners order): the image corner it lands on, (0|1 = left|right, 0|1 = top|bottom)
corner_xy:
    db 0,1, 1,1, 1,0, 0,0               ; RIGHT
    db 0,1, 1,1, 1,0, 0,0               ; LEFT
    db 1,0, 0,0, 0,1, 1,1               ; TOP
    db 0,1, 1,1, 1,0, 0,0               ; BOTTOM
    db 0,1, 1,1, 1,0, 0,0               ; BACK
    db 0,1, 1,1, 1,0, 0,0               ; FRONT

section .bss
align 8
sk_parts:       resq 256                ; the part records of the model being worked on, by part index
sk_rects:       resw 4 * SK_MAX_RECTS   ; skin_check: own-skin footprints (u, v, u_end, v_end)
sk_cu:          resd 1                  ; the packer's shelf cursor and shelf height
sk_cv:          resd 1
sk_sh:          resd 1
sk_nrects:      resd 1

section .text

; skin_face_rect(rdi part record, esi face) -> eax u, edx v, ecx width, r8d height
; The face's image rectangle in the atlas (the unwrap table in the header). Leaf; clobbers r9-r11.
skin_face_rect:
    mov     r10d, esi
    lea     r10d, [r10 + r10*4]                 ; face * 5
    lea     r9, [face_rect_tab]
    add     r9, r10
    movzx   eax, byte [rdi + SKR_W]
    movzx   edx, byte [rdi + SKR_D]
    movzx   r8d, byte [rdi + SKR_H]
    movzx   r10d, byte [r9]
    imul    r10d, edx
    movzx   r11d, byte [r9 + 1]
    imul    r11d, eax
    add     r10d, r11d
    movzx   r11d, word [rdi + SKR_U]
    add     r10d, r11d                          ; r10d = u_f
    movzx   r11d, byte [r9 + 2]
    imul    r11d, edx
    movzx   ecx, word [rdi + SKR_V]
    add     r11d, ecx                           ; r11d = v_f
    cmp     byte [r9 + 3], 0
    cmovne  eax, edx                            ; width = sel_w ? d : w
    cmp     byte [r9 + 4], 0
    cmovne  r8d, edx                            ; height = sel_h ? d : h
    mov     ecx, eax
    mov     eax, r10d
    mov     edx, r11d
    ret

; skin_face_uvs(rdi part record, esi face, rdx out dd[8])
; out = (u, v) of the face's four corners in face_corners order, in 1/16 texel units: the image corner
; (u_f + ix, v_f + iy) * 16, one unit inside the rectangle (+1 on the near edge, -1 on the far one).
; Clobbers the caller-saved registers.
skin_face_uvs:
    push    rbx
    mov     rbx, rdx                            ; skin_face_rect clobbers rdx and r9-r11
    call    skin_face_rect                      ; eax u_f, edx v_f, ecx width, r8d height (esi kept)
    mov     r10d, esi
    shl     r10d, 3                             ; 8 bytes of corner_xy per face
    lea     r11, [corner_xy]
    add     r11, r10
    xor     r10d, r10d                          ; corner
.corner:
    movzx   edi, byte [r11 + r10*2]             ; 0 left, 1 right
    mov     esi, edi
    imul    edi, ecx
    add     edi, eax
    shl     edi, 4
    inc     edi
    add     esi, esi
    sub     edi, esi                            ; (u_f + cx * width) * 16 + 1 - 2 * cx
    mov     [rbx + r10*8], edi
    movzx   edi, byte [r11 + r10*2 + 1]         ; 0 top, 1 bottom
    mov     esi, edi
    imul    edi, r8d
    add     edi, edx
    shl     edi, 4
    inc     edi
    add     esi, esi
    sub     edi, esi
    mov     [rbx + r10*8 + 4], edi
    inc     r10d
    cmp     r10d, 4
    jb      .corner
    pop     rbx
    ret

; sk_index_parts(rdi model) -> eax part count; sk_parts[i] = the model's i-th part record. Leaf.
sk_index_parts:
    mov     rsi, [rdi + SKMODEL.recs]
    lea     r8, [sk_parts]
    xor     eax, eax
.rec:
    movzx   ecx, byte [rsi + SKR_TYPE]
    cmp     ecx, SKR_PART
    je      .part
    cmp     ecx, SKR_BONE
    jne     .done
    add     rsi, SKREC_SIZE
    jmp     .rec
.part:
    mov     [r8 + rax*8], rsi
    inc     eax
    add     rsi, SKREC_SIZE
    jmp     .rec
.done:
    ret

; sk_pack(rdi model) -> eax 0 placed / 1 overflow
; Places the model's own-skin parts on the shelf cursor (sk_cu, sk_cv, sk_sh) and copies size and place
; into its SKPART_AS parts. Also leaves the part records in sk_parts. Leaf.
sk_pack:
    mov     rsi, [rdi + SKMODEL.recs]
    lea     r8, [sk_parts]
    xor     r9d, r9d                            ; part index
    mov     r10d, [sk_cu]
    mov     r11d, [sk_cv]
    mov     edi, [sk_sh]
.rec:
    movzx   eax, byte [rsi + SKR_TYPE]
    cmp     eax, SKR_PART
    je      .part
    cmp     eax, SKR_BONE
    jne     .done                               ; SKR_END
    add     rsi, SKREC_SIZE
    jmp     .rec
.part:
    mov     [r8 + r9*8], rsi
    inc     r9d
    movzx   eax, byte [rsi + SKR_AS]
    cmp     eax, SKAS_NONE
    jne     .shared
    movzx   ecx, byte [rsi + SKR_W]
    movzx   edx, byte [rsi + SKR_D]
    add     ecx, edx
    add     ecx, ecx                            ; footprint width 2 (w + d)
    cmp     ecx, ATLAS_W
    ja      .overflow
    lea     eax, [r10 + rcx]
    cmp     eax, ATLAS_W
    jbe     .on_shelf
    xor     r10d, r10d                          ; next shelf
    add     r11d, edi
    xor     edi, edi
.on_shelf:
    movzx   eax, byte [rsi + SKR_H]
    add     eax, edx                            ; footprint height d + h
    lea     edx, [r11 + rax]
    cmp     edx, ATLAS_H
    ja      .overflow
    mov     [rsi + SKR_U], r10w
    mov     [rsi + SKR_V], r11w
    add     r10d, ecx
    cmp     edi, eax
    cmovb   edi, eax                            ; shelf height = the tallest footprint
    jmp     .next
.shared:
    mov     rdx, [r8 + rax*8]                   ; the source part (SKPART_AS: an earlier one)
    movzx   eax, byte [rdx + SKR_W]
    mov     [rsi + SKR_W], al
    movzx   eax, byte [rdx + SKR_H]
    mov     [rsi + SKR_H], al
    movzx   eax, byte [rdx + SKR_D]
    mov     [rsi + SKR_D], al
    mov     eax, [rdx + SKR_U]                  ; u and v, two words
    mov     [rsi + SKR_U], eax
.next:
    add     rsi, SKREC_SIZE
    jmp     .rec
.done:
    mov     [sk_cu], r10d
    mov     [sk_cv], r11d
    mov     [sk_sh], edi
    xor     eax, eax
    ret
.overflow:
    mov     eax, 1
    ret

; sk_fill_rect(rdi atlas, esi x, edx y, ecx w, r8d h, r9d colour, r10d noise)
; The atlas rect = colour with alpha 255; with noise, each channel * m >> 8, m = 256 - (hash(ax, ay) & noise).
; Leaf.
sk_fill_rect:
    test    ecx, ecx
    jz      .out
    test    r8d, r8d
    jz      .out
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    mov     eax, edx
    imul    eax, eax, ATLAS_W
    add     eax, esi
    lea     rdi, [rdi + rax*4]                  ; the first texel
    mov     r12d, r9d
    and     r12d, 255                           ; colour channels
    mov     r13d, r9d
    shr     r13d, 8
    and     r13d, 255
    mov     r14d, r9d
    shr     r14d, 16
    and     r14d, 255
    and     r9d, 0x00FFFFFF
    or      r9d, 0xFF000000                     ; the plain colour, opaque
.row:
    mov     r15d, edx
    imul    r15d, r15d, 0x165667b1              ; the row's half of the hash
    xor     ebx, ebx
.col:
    test    r10d, r10d
    jnz     .noise
    mov     [rdi + rbx*4], r9d
    jmp     .next
.noise:
    mov     eax, esi
    add     eax, ebx                            ; ax
    imul    eax, eax, 0x27d4eb2d
    xor     eax, r15d
    mov     ebp, eax
    shr     ebp, 15
    xor     eax, ebp
    imul    eax, eax, 0x85ebca6b
    mov     ebp, eax
    shr     ebp, 13
    xor     eax, ebp
    and     eax, r10d
    neg     eax
    add     eax, 256                            ; m
    mov     ebp, r12d
    imul    ebp, eax
    shr     ebp, 8
    mov     r11d, r13d
    imul    r11d, eax
    shr     r11d, 8
    shl     r11d, 8
    or      ebp, r11d
    mov     r11d, r14d
    imul    r11d, eax
    shr     r11d, 8
    shl     r11d, 16
    or      ebp, r11d
    or      ebp, 0xFF000000
    mov     [rdi + rbx*4], ebp
.next:
    inc     ebx
    cmp     ebx, ecx
    jb      .col
    add     rdi, ATLAS_W * 4
    inc     edx
    dec     r8d
    jnz     .row
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
.out:
    ret

; scale one channel of the texel in r10d (shift %1) by m (ebx) / 256, clamp to 255, or into r14d
%macro GRAD_CHANNEL 1
    mov     eax, r10d
    shr     eax, %1
    movzx   eax, al
    imul    eax, ebx
    shr     eax, 8
    mov     r15d, 255
    cmp     eax, 255
    cmova   eax, r15d
    shl     eax, %1
    or      r14d, eax
%endmacro

; sk_grad_rect(rdi atlas, esi x, edx y, ecx w, r8d h, r9d top, r10d bottom)
; Row iy of the rect: rgb * m / 256, m = top + (bottom - top) * iy / (h - 1) (top when h = 1); alpha kept. Leaf.
sk_grad_rect:
    test    ecx, ecx
    jz      .out
    test    r8d, r8d
    jz      .out
    push    rbx
    push    rbp
    push    r12
    push    r13
    push    r14
    push    r15
    mov     eax, edx
    imul    eax, eax, ATLAS_W
    add     eax, esi
    lea     rdi, [rdi + rax*4]
    mov     r11d, r10d
    sub     r11d, r9d                           ; bottom - top, signed
    lea     r12d, [r8 - 1]                      ; the divisor
    xor     r13d, r13d                          ; iy
.row:
    mov     ebx, r9d
    test    r12d, r12d
    jz      .m_ready
    mov     eax, r11d
    imul    eax, r13d
    cdq
    idiv    r12d
    add     ebx, eax
.m_ready:
    xor     ebp, ebp                            ; column
.col:
    mov     r10d, [rdi + rbp*4]
    mov     r14d, r10d
    and     r14d, 0xFF000000                    ; alpha kept
    GRAD_CHANNEL 0
    GRAD_CHANNEL 8
    GRAD_CHANNEL 16
    mov     [rdi + rbp*4], r14d
    inc     ebp
    cmp     ebp, ecx
    jb      .col
    add     rdi, ATLAS_W * 4
    inc     r13d
    cmp     r13d, r8d
    jb      .row
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbp
    pop     rbx
.out:
    ret

; sk_paint(rdi atlas, rsi model): runs the model's paint ops (every model is packed already).
; r12 = atlas, rbx = op, r13 = part record, r14d = face mask, r15d = face
sk_paint:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     r12, rdi
    mov     rbx, [rsi + SKMODEL.ops]
    mov     rdi, rsi
    call    sk_index_parts
.op:
    movzx   eax, byte [rbx + SKOP_OP]
    cmp     eax, SKO_FILL
    je      .fill
    cmp     eax, SKO_RECT
    je      .rect
    cmp     eax, SKO_BMP
    je      .bmp
    cmp     eax, SKO_GRAD
    je      .grad
    jmp     .done                               ; SKO_END
.fill:
    movzx   eax, byte [rbx + SKOP_PART]
    lea     rcx, [sk_parts]
    mov     r13, [rcx + rax*8]
    movzx   r14d, byte [rbx + SKOP_FACES]
    xor     r15d, r15d
.fill_face:
    bt      r14d, r15d
    jnc     .fill_skip
    mov     rdi, r13
    mov     esi, r15d
    call    skin_face_rect
    mov     esi, eax
    mov     rdi, r12
    mov     r9d, [rbx + SKOP_COLOUR]
    movzx   r10d, byte [rbx + SKOP_NOISE]
    call    sk_fill_rect
.fill_skip:
    inc     r15d
    cmp     r15d, 6
    jb      .fill_face
.next_op:
    add     rbx, SKOP_SIZE
    jmp     .op
.rect:
    movzx   eax, byte [rbx + SKOP_PART]
    lea     rcx, [sk_parts]
    mov     rdi, [rcx + rax*8]
    movzx   esi, byte [rbx + SKOP_FACES]
    call    skin_face_rect                      ; eax u_f, edx v_f, ecx fw, r8d fh
    movzx   r9d, byte [rbx + SKOP_X]
    movzx   r10d, byte [rbx + SKOP_Y]
    cmp     r9d, ecx
    jae     .next_op                            ; starts right of or below the face
    cmp     r10d, r8d
    jae     .next_op
    sub     ecx, r9d                            ; room to the right
    movzx   edi, byte [rbx + SKOP_W]
    cmp     edi, ecx
    cmova   edi, ecx                            ; clipped width
    sub     r8d, r10d                           ; room below
    movzx   r11d, byte [rbx + SKOP_H]
    cmp     r11d, r8d
    cmova   r11d, r8d                           ; clipped height
    add     eax, r9d                            ; atlas x
    add     edx, r10d                           ; atlas y
    mov     esi, eax
    mov     ecx, edi
    mov     r8d, r11d
    mov     rdi, r12
    mov     r9d, [rbx + SKOP_COLOUR]
    movzx   r10d, byte [rbx + SKOP_NOISE]
    call    sk_fill_rect
    jmp     .next_op
.bmp:
    movzx   eax, byte [rbx + SKOP_PART]
    lea     rcx, [sk_parts]
    mov     rdi, [rcx + rax*8]
    movzx   esi, byte [rbx + SKOP_FACES]
    call    skin_face_rect
    movzx   r9d, byte [rbx + SKOP_X]
    movzx   r10d, byte [rbx + SKOP_Y]
    cmp     r9d, ecx
    jae     .next_op
    cmp     r10d, r8d
    jae     .next_op
    sub     ecx, r9d                            ; clip width
    sub     r8d, r10d                           ; clip height
    add     eax, r9d
    add     edx, r10d
    imul    edx, edx, ATLAS_W
    add     edx, eax
    lea     rdi, [r12 + rdx*4]                  ; the bitmap's first texel
    mov     esi, ATLAS_W
    mov     rdx, [rbx + SKOP_BMP]
    call    art_blit
    jmp     .next_op
.grad:
    movzx   eax, byte [rbx + SKOP_PART]
    lea     rcx, [sk_parts]
    mov     r13, [rcx + rax*8]
    movzx   r14d, byte [rbx + SKOP_FACES]
    xor     r15d, r15d
.grad_face:
    bt      r14d, r15d
    jnc     .grad_skip
    mov     rdi, r13
    mov     esi, r15d
    call    skin_face_rect
    mov     esi, eax
    mov     rdi, r12
    movzx   r9d, word [rbx + SKOP_TOP]
    movzx   r10d, word [rbx + SKOP_BOTTOM]
    call    sk_grad_rect
.grad_skip:
    inc     r15d
    cmp     r15d, 6
    jb      .grad_face
    jmp     .next_op
.done:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; skin_build(rdi atlas, rsi registry: SKMODEL* array, 0-terminated) -> eax 0 fits / 1 overflow
; Packs every model (writing SKR_U / SKR_V and the sizes of the SKPART_AS parts into the records), then
; paints every model's ops into the atlas. On overflow it returns 1 before painting anything.
skin_build:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12, rsi
    mov     dword [sk_cu], 0
    mov     dword [sk_cv], SKIN_Y0
    mov     dword [sk_sh], 0
    mov     r13, rsi
.pack:
    mov     rdi, [r13]
    test    rdi, rdi
    jz      .paint
    call    sk_pack
    test    eax, eax
    jnz     .out
    add     r13, 8
    jmp     .pack
.paint:
    mov     r13, r12
.paint_one:
    mov     rsi, [r13]
    test    rsi, rsi
    jz      .ok
    mov     rdi, rbx
    call    sk_paint
    add     r13, 8
    jmp     .paint_one
.ok:
    xor     eax, eax
.out:
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; sk_chk_geom(rdi registry) -> eax 0 / 2 a footprint outside the skin region / 3 a SKPART_AS part that
; differs from its source / 6 more than SK_MAX_RECTS own-skin footprints
; Fills sk_rects with the own-skin footprints (u, v, u_end, v_end), empty ones left out.
sk_chk_geom:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     dword [sk_nrects], 0
.model:
    mov     rdi, [r12]
    test    rdi, rdi
    jz      .ok
    call    sk_index_parts
    mov     rbx, [r12]
    mov     rbx, [rbx + SKMODEL.recs]
    xor     r13d, r13d                          ; part index
.rec:
    movzx   eax, byte [rbx + SKR_TYPE]
    cmp     eax, SKR_PART
    je      .part
    cmp     eax, SKR_BONE
    jne     .model_done
    add     rbx, SKREC_SIZE
    jmp     .rec
.part:
    movzx   ecx, byte [rbx + SKR_W]
    movzx   edx, byte [rbx + SKR_D]
    movzx   esi, byte [rbx + SKR_H]
    add     ecx, edx
    add     ecx, ecx                            ; footprint width
    add     esi, edx                            ; footprint height
    movzx   eax, word [rbx + SKR_U]
    movzx   edi, word [rbx + SKR_V]
    add     ecx, eax                            ; u_end
    add     esi, edi                            ; v_end
    cmp     ecx, ATLAS_W
    ja      .outside
    cmp     edi, SKIN_Y0
    jb      .outside
    cmp     esi, ATLAS_H
    ja      .outside
    movzx   edx, byte [rbx + SKR_AS]
    cmp     edx, SKAS_NONE
    jne     .shared
    cmp     ecx, eax
    je      .next                               ; no footprint
    cmp     esi, edi
    je      .next
    mov     edx, [sk_nrects]
    cmp     edx, SK_MAX_RECTS
    jae     .too_many
    lea     r8, [sk_rects]
    mov     [r8 + rdx*8], ax
    mov     [r8 + rdx*8 + 2], di
    mov     [r8 + rdx*8 + 4], cx
    mov     [r8 + rdx*8 + 6], si
    inc     edx
    mov     [sk_nrects], edx
    jmp     .next
.shared:
    cmp     edx, r13d
    jae     .differs                            ; it must name an earlier part
    lea     r8, [sk_parts]
    mov     r8, [r8 + rdx*8]                    ; the source record
    mov     eax, [rbx + SKR_W]
    xor     eax, [r8 + SKR_W]
    and     eax, 0x00FFFFFF                     ; w, h, d (not the pad byte)
    jnz     .differs
    mov     eax, [rbx + SKR_U]
    cmp     eax, [r8 + SKR_U]                   ; u and v
    jne     .differs
.next:
    inc     r13d
    add     rbx, SKREC_SIZE
    jmp     .rec
.model_done:
    add     r12, 8
    jmp     .model
.ok:
    xor     eax, eax
    jmp     .out
.outside:
    mov     eax, 2
    jmp     .out
.differs:
    mov     eax, 3
    jmp     .out
.too_many:
    mov     eax, 6
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; sk_chk_overlap() -> eax 0 / 4 two footprints in sk_rects share a texel. Leaf.
sk_chk_overlap:
    mov     r8d, [sk_nrects]
    lea     r9, [sk_rects]
    xor     ecx, ecx                            ; i
.i:
    lea     edx, [rcx + 1]                      ; j
    cmp     edx, r8d
    jae     .ok
    movzx   r10d, word [r9 + rcx*8]             ; u_i
    movzx   esi, word [r9 + rcx*8 + 2]          ; v_i
    movzx   r11d, word [r9 + rcx*8 + 4]         ; u_end_i
    movzx   edi, word [r9 + rcx*8 + 6]          ; v_end_i
.j:
    movzx   eax, word [r9 + rdx*8 + 4]
    cmp     r10d, eax
    jae     .j_next                             ; u_i >= u_end_j
    movzx   eax, word [r9 + rdx*8]
    cmp     eax, r11d
    jae     .j_next                             ; u_j >= u_end_i
    movzx   eax, word [r9 + rdx*8 + 6]
    cmp     esi, eax
    jae     .j_next
    movzx   eax, word [r9 + rdx*8 + 2]
    cmp     eax, edi
    jae     .j_next
    mov     eax, 4
    ret
.j_next:
    inc     edx
    cmp     edx, r8d
    jb      .j
    inc     ecx
    jmp     .i
.ok:
    xor     eax, eax
    ret

; sk_chk_paint(rdi atlas, rsi registry) -> eax 0 / 5 a face that was never painted
; Every texel of every face of a part must be opaque (alpha > 127); a SKPF_CUTOUT part may have holes
; but each of its faces needs at least one opaque texel.
sk_chk_paint:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    mov     r12, rdi
    mov     r13, rsi
.model:
    mov     rbx, [r13]
    test    rbx, rbx
    jz      .ok
    mov     rbx, [rbx + SKMODEL.recs]
.rec:
    movzx   eax, byte [rbx + SKR_TYPE]
    cmp     eax, SKR_PART
    je      .part
    cmp     eax, SKR_BONE
    jne     .model_done
    add     rbx, SKREC_SIZE
    jmp     .rec
.part:
    xor     r14d, r14d                          ; face
.face:
    mov     rdi, rbx
    mov     esi, r14d
    call    skin_face_rect
    test    ecx, ecx
    jz      .face_next
    test    r8d, r8d
    jz      .face_next
    imul    edx, edx, ATLAS_W
    add     edx, eax
    lea     rsi, [r12 + rdx*4]                  ; the face's first texel
    xor     r9d, r9d                            ; opaque texels seen
    mov     r10d, r8d                           ; rows left
.row:
    xor     edi, edi
.col:
    cmp     byte [rsi + rdi*4 + 3], 127
    ja      .opaque
    test    byte [rbx + SKR_FLAGS], SKPF_CUTOUT
    jz      .bad                                ; a hole in a solid part
    jmp     .col_next
.opaque:
    inc     r9d
.col_next:
    inc     edi
    cmp     edi, ecx
    jb      .col
    add     rsi, ATLAS_W * 4
    dec     r10d
    jnz     .row
    test    r9d, r9d
    jz      .bad                                ; a face without a single opaque texel
.face_next:
    inc     r14d
    cmp     r14d, 6
    jb      .face
    add     rbx, SKREC_SIZE
    jmp     .rec
.model_done:
    add     r13, 8
    jmp     .model
.ok:
    xor     eax, eax
    jmp     .out
.bad:
    mov     eax, 5
.out:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; skin_verify(rdi atlas, rsi registry) -> eax 0 / the number of the first failing check
; The structural proof for an atlas skin_build already built from this registry (the numbers are shared
; with skin_check, whose check 1 is the fit):
;   2  a part's unwrap footprint 2(w+d) x (d+h) leaves [0, ATLAS_W) x [SKIN_Y0, ATLAS_H)
;   3  a SKPART_AS part's w, h, d, u, v differ from its source's (or it names a later part)
;   4  two own-skin footprints overlap
;   5  a face with a bare texel: every texel of a solid part's faces must be opaque (alpha > 127), each
;      face of a SKPF_CUTOUT part needs at least one opaque texel
;   6  more than SK_MAX_RECTS own-skin parts in the registry
skin_verify:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
    mov     rdi, r13
    call    sk_chk_geom
    test    eax, eax
    jnz     .out
    call    sk_chk_overlap
    test    eax, eax
    jnz     .out
    mov     rdi, r12
    mov     rsi, r13
    call    sk_chk_paint
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; skin_check(rdi atlas, rsi registry) -> eax 0 / the number of the first failing check
; The whole proof for a registry on an atlas of the caller's (a zeroed 256 x 4096 RGBA buffer, or one
; texgen_build made): skin_build runs first, so this is the one call a test needs (and calling skin_build
; before is harmless, it gives the same atlas again), then skin_verify's checks:
;   1  the unwraps do not fit (skin_build returned 1, nothing was painted)
;   2..6  skin_verify's
skin_check:
    push    rbx
    push    r12
    push    r13
    mov     r12, rdi
    mov     r13, rsi
    call    skin_build
    test    eax, eax
    jnz     .out                                ; 1: it does not fit
    mov     rdi, r12
    mov     rsi, r13
    call    skin_verify
.out:
    pop     r13
    pop     r12
    pop     rbx
    ret

; skin_model_draw(rdi SKMODEL*, rsi SKPOSE* or 0, xmm0 swing_deg, xmm1 r, xmm2 g, xmm3 b)
; Draws the model in the current modelview (origin at the feet or the model centre, front -Z, units
; blocks, atlas bound, atlas texture matrix set by render_init), tinted (r, g, b). A null pose = flags 0,
; no held item, accent (1, 1, 1). The held item is pose.held, or SKMODEL.held when that is 0.
; The records are walked once: a bone closes the previous one (glEnd if its quads were begun, then the
; held item when it is BK_RARM, then glPopMatrix if it pushed one) and opens its own - skipped under
; SKP_SEATED (all but BODY and HEAD) or SKP_ARM_ONLY (all but RARM); angle = swing * swing_deg, plus for
; RARM pose.arm_deg under SKP_ARM_UP or 20 degrees while it holds an item, none at all under SKP_ARM_ONLY;
; a non-zero angle pushes a matrix and turns about X at the pivot (y, z). A part adds six quads, each
; coloured tint * skin_shades[face] (* pose.accent for SKPF_ACCENT parts), the corners lo - grow/8 /
; hi + grow/8 texels. The held item is drawn at SKMODEL.hand with held_item_draw(held, 1.0) once the
; model scale is undone (SKP_ARM_ONLY draws none).
; rbx = record, r12 = model, r15 = pose, r14d = face, r13d = corner; the open bone's state is on the stack.
skin_model_draw:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, DR_SIZE
    mov     r12, rdi
    mov     r15, rsi
    test    r15, r15
    jnz     .have_pose
    lea     r15, [skin_pose_none]
.have_pose:
    movss   [rsp + DR_SWING], xmm0
    movss   [rsp + DR_TINT], xmm1
    movss   [rsp + DR_TINT + 4], xmm2
    movss   [rsp + DR_TINT + 8], xmm3
    mov     eax, [r15 + SKPOSE.held]
    test    eax, eax
    jnz     .held_known
    movzx   eax, word [r12 + SKMODEL.held]
.held_known:
    mov     [rsp + DR_HELD], eax
    mov     dword [rsp + DR_STATE], 0
    call    glPushMatrix
    movzx   eax, word [r12 + SKMODEL.tpb]
    cvtsi2ss xmm1, eax
    movss   xmm0, [f_one]
    divss   xmm0, xmm1                          ; 1 / tpb
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    glScalef
    mov     rbx, [r12 + SKMODEL.recs]
.rec:
    cmp     byte [rbx + SKR_TYPE], SKR_PART
    je      .part
    ; a bone, or the end: close the open bone
    test    dword [rsp + DR_STATE], DRS_QUADS
    jz      .quads_closed
    call    glEnd
.quads_closed:
    test    dword [rsp + DR_STATE], DRS_ACTIVE
    jz      .closed
    cmp     dword [rsp + DR_KIND], BK_RARM
    jne     .hand_done
    cmp     dword [rsp + DR_HELD], 0
    je      .hand_done
    test    dword [r15 + SKPOSE.flags], SKP_ARM_ONLY
    jnz     .hand_done
    call    glPushMatrix                        ; the held item at the hand, in blocks again
    movsx   eax, word [r12 + SKMODEL.hand]
    cvtsi2ss xmm0, eax
    movsx   eax, word [r12 + SKMODEL.hand + 2]
    cvtsi2ss xmm1, eax
    movsx   eax, word [r12 + SKMODEL.hand + 4]
    cvtsi2ss xmm2, eax
    call    glTranslatef
    movzx   eax, word [r12 + SKMODEL.tpb]
    cvtsi2ss xmm0, eax
    movaps  xmm1, xmm0
    movaps  xmm2, xmm0
    call    glScalef
    mov     edi, [rsp + DR_HELD]
    movss   xmm0, [f_one]
    call    held_item_draw
    call    glPopMatrix
.hand_done:
    test    dword [rsp + DR_STATE], DRS_PUSHED
    jz      .closed
    call    glPopMatrix
.closed:
    mov     dword [rsp + DR_STATE], 0
    cmp     byte [rbx + SKR_TYPE], SKR_BONE
    jne     .finish
    ; open the bone
    movzx   eax, byte [rbx + SKR_KIND]
    mov     [rsp + DR_KIND], eax
    mov     ecx, [r15 + SKPOSE.flags]
    test    ecx, SKP_SEATED
    jz      .not_seated
    cmp     eax, BK_HEAD
    ja      .next_rec                           ; skipped: draws nothing, pushes nothing
.not_seated:
    mov     dword [rsp + DR_STATE], DRS_ACTIVE
    test    ecx, SKP_ARM_ONLY
    jz      .posed
    cmp     eax, BK_RARM
    je      .next_rec                           ; unrotated
    mov     dword [rsp + DR_STATE], 0
    jmp     .next_rec
.posed:
    movss   xmm0, [rbx + SKR_SWING]
    mulss   xmm0, [rsp + DR_SWING]
    cmp     eax, BK_RARM
    jne     .angle_done
    test    ecx, SKP_ARM_UP
    jz      .arm_down
    addss   xmm0, [r15 + SKPOSE.arm_deg]
    jmp     .angle_done
.arm_down:
    cmp     dword [rsp + DR_HELD], 0
    je      .angle_done
    addss   xmm0, [f_held_arm]
.angle_done:
    xorps   xmm1, xmm1
    ucomiss xmm0, xmm1
    je      .next_rec                           ; no angle: no rotation
    movss   [rsp + DR_ANGLE], xmm0
    or      dword [rsp + DR_STATE], DRS_PUSHED
    call    glPushMatrix
    xorps   xmm0, xmm0
    movsx   eax, word [rbx + SKR_PIVY]
    cvtsi2ss xmm1, eax
    movsx   eax, word [rbx + SKR_PIVZ]
    cvtsi2ss xmm2, eax
    call    glTranslatef                        ; to the pivot
    movss   xmm0, [rsp + DR_ANGLE]
    movss   xmm1, [f_one]
    xorps   xmm2, xmm2
    xorps   xmm3, xmm3
    call    glRotatef                           ; about X
    xorps   xmm0, xmm0
    movsx   eax, word [rbx + SKR_PIVY]
    neg     eax
    cvtsi2ss xmm1, eax
    movsx   eax, word [rbx + SKR_PIVZ]
    neg     eax
    cvtsi2ss xmm2, eax
    call    glTranslatef                        ; and back
    jmp     .next_rec
.part:
    test    dword [rsp + DR_STATE], DRS_ACTIVE
    jz      .next_rec
    test    dword [rsp + DR_STATE], DRS_QUADS
    jnz     .quads_on
    mov     edi, GL_QUADS
    call    glBegin
    or      dword [rsp + DR_STATE], DRS_QUADS
.quads_on:
    movzx   eax, byte [rbx + SKR_GROW]
    cvtsi2ss xmm4, eax
    mulss   xmm4, [f_eighth]                    ; the inflation, texels
    xor     ecx, ecx
.axis:
    movsx   eax, word [rbx + rcx*2 + SKR_X0]
    cvtsi2ss xmm0, eax
    movzx   eax, byte [rbx + rcx + SKR_W]
    cvtsi2ss xmm1, eax
    addss   xmm1, xmm0
    subss   xmm0, xmm4
    addss   xmm1, xmm4
    movss   [rsp + rcx*4 + DR_BOX], xmm0        ; lo
    movss   [rsp + rcx*4 + DR_BOX + 12], xmm1   ; hi
    inc     ecx
    cmp     ecx, 3
    jb      .axis
    xor     r14d, r14d                          ; face
.face:
    lea     rax, [skin_shades]
    movss   xmm3, [rax + r14*4]
    movss   xmm0, [rsp + DR_TINT]
    mulss   xmm0, xmm3
    movss   xmm1, [rsp + DR_TINT + 4]
    mulss   xmm1, xmm3
    movss   xmm2, [rsp + DR_TINT + 8]
    mulss   xmm2, xmm3
    test    byte [rbx + SKR_FLAGS], SKPF_ACCENT
    jz      .tinted
    mulss   xmm0, [r15 + SKPOSE.accent]
    mulss   xmm1, [r15 + SKPOSE.accent + 4]
    mulss   xmm2, [r15 + SKPOSE.accent + 8]
.tinted:
    movss   xmm3, [f_one]
    call    glColor4f
    mov     rdi, rbx
    mov     esi, r14d
    lea     rdx, [rsp + DR_UV]
    call    skin_face_uvs
    xor     r13d, r13d                          ; corner
.corner:
    mov     edi, [rsp + r13*8 + DR_UV]
    mov     esi, [rsp + r13*8 + DR_UV + 4]
    call    glTexCoord2i
    lea     eax, [r14*4 + r13]
    lea     eax, [rax + rax*2]                  ; the corner's three lo/hi bits
    lea     rcx, [face_corners]
    movzx   edx, byte [rcx + rax]
    lea     edx, [rdx + rdx*2]
    movss   xmm0, [rsp + rdx*4 + DR_BOX]
    movzx   edx, byte [rcx + rax + 1]
    lea     edx, [rdx + rdx*2 + 1]
    movss   xmm1, [rsp + rdx*4 + DR_BOX]
    movzx   edx, byte [rcx + rax + 2]
    lea     edx, [rdx + rdx*2 + 2]
    movss   xmm2, [rsp + rdx*4 + DR_BOX]
    call    glVertex3f
    inc     r13d
    cmp     r13d, 4
    jb      .corner
    inc     r14d
    cmp     r14d, 6
    jb      .face
.next_rec:
    add     rbx, SKREC_SIZE
    jmp     .rec
.finish:
    call    glPopMatrix
    add     rsp, DR_SIZE
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
