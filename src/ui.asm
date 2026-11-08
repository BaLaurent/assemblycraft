; ui.asm - immediate-mode GUI toolkit: rects, 8x8 bitmap text, buttons, sliders,
; text fields, item slots and icons. Everything is in GUI units (framebuffer pixels
; divided by ui_scale); the origin is the top-left corner and y grows downward.
; Text samples the font painted into the atlas at FONT_Y. Texcoords are in 1/16 px
; units, so ui_begin (re)establishes the 1/4096 texture matrix render_init uses.
%include "common.inc"
%include "gl.inc"
default rel

global ui_w, ui_h, ui_scale, ui_mx, ui_my, ui_focus
global ui_init, ui_begin, ui_rect, ui_frame, ui_panel
global ui_text, ui_text_width, ui_text_centered
global ui_button, ui_slider, ui_textfield, ui_slot
global ui_item_icon, ui_icon9, ui_tooltip, ui_tooltip_lines, ui_tile_icon

extern settings, ui_input, audio_play, tex_id
extern font8x8, item_icon, item_max_stack, item_durability
extern str_append, i32_to_str

%define WHITE   0xFFFFFFFF
%define BTN_H   20

section .rodata
align 8
d_one:       dq 1.0
d_mone:      dq -1.0
d_two:       dq 2.0
align 4
f_texscale:  dd 0.000244140625          ; 1/4096: texcoords are 1/16 px units
f_one:       dd 1.0
f_click_vol: dd 0.6
s_caret:     db "_", 0

section .bss
alignb 8
ui_focus:    resq 1                     ; TEXTFIELD* that receives typed characters, or 0
ui_active:   resq 1                     ; SLIDERDEF* being dragged, or 0
ui_w:        resd 1                     ; GUI-space framebuffer size
ui_h:        resd 1
ui_scale:    resd 1                     ; framebuffer pixels per GUI unit
ui_mx:       resd 1                     ; mouse position in GUI units
ui_my:       resd 1
glyph_w:     resb 96                    ; ink width of glyph c-32 (3 for blank glyphs)
glyph_left:  resb 96                    ; first ink column of glyph c-32, 0xFF = blank

section .text

; ---- setup ----------------------------------------------------------------

; ui_init(): measure the ink columns of every printable glyph
ui_init:
    xor     ecx, ecx                    ; glyph index 0..94 = chars 32..126
.glyph:
    mov     rax, [font8x8 + rcx*8]      ; the 8 rows of this glyph
    mov     rdx, rax
    shr     rdx, 32
    or      rax, rdx
    mov     rdx, rax
    shr     rdx, 16
    or      rax, rdx
    mov     rdx, rax
    shr     rdx, 8
    or      eax, edx
    and     eax, 255                    ; al = OR of all 8 rows
    jz      .blank
    bsf     edx, eax                    ; first ink column (bit 0 = leftmost)
    bsr     esi, eax                    ; last ink column
    sub     esi, edx
    inc     esi                         ; width = last - first + 1
    mov     [glyph_left + rcx], dl
    mov     [glyph_w + rcx], sil
    jmp     .next
.blank:
    mov     byte [glyph_left + rcx], 0xFF
    mov     byte [glyph_w + rcx], 3
.next:
    inc     ecx
    cmp     ecx, 95
    jb      .glyph
    ret

; ui_begin(edi fb_w, esi fb_h): pick the GUI scale, publish ui_w/ui_h/ui_mx/ui_my and
; put GL into 2D state (ortho in GUI units, atlas bound, alpha blending, no alpha test)
ui_begin:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    sub     rsp, 8
    mov     r12d, edi                   ; fb_w
    mov     r13d, esi                   ; fb_h
    mov     ebx, [settings + SETTINGS.gui_scale]
    test    ebx, ebx
    jg      .scale_set
    mov     eax, r12d                   ; auto: min(fb_w / 320, fb_h / 240)
    cdq
    mov     ecx, 320
    idiv    ecx
    mov     ebx, eax
    mov     eax, r13d
    cdq
    mov     ecx, 240
    idiv    ecx
    cmp     eax, ebx
    cmovl   ebx, eax
.scale_set:
    mov     eax, 1                      ; clamp to 1..4
    cmp     ebx, eax
    cmovl   ebx, eax
    mov     eax, 4
    cmp     ebx, eax
    cmovg   ebx, eax
    mov     [ui_scale], ebx
    mov     eax, r12d
    cdq
    idiv    ebx
    mov     [ui_w], eax
    mov     eax, r13d
    cdq
    idiv    ebx
    mov     [ui_h], eax
    mov     eax, [ui_input + UIINPUT.mouse_px]
    cdq
    idiv    ebx
    test    edx, edx
    jns     .mx_ok
    dec     eax                         ; floor, so a cursor left of the window stays outside
.mx_ok:
    mov     [ui_mx], eax
    mov     eax, [ui_input + UIINPUT.mouse_py]
    cdq
    idiv    ebx
    test    edx, edx
    jns     .my_ok
    dec     eax
.my_ok:
    mov     [ui_my], eax
    cmp     dword [ui_input + UIINPUT.lmb_held], 0
    jne     .drag_ok
    mov     qword [ui_active], 0        ; a released button ends any slider drag
.drag_ok:

    xor     edi, edi
    xor     esi, esi
    mov     edx, r12d
    mov     ecx, r13d
    call    glViewport
    mov     edi, GL_PROJECTION
    call    glMatrixMode
    call    glLoadIdentity
    xorpd   xmm0, xmm0                  ; glOrtho(0, ui_w, ui_h, 0, -1, 1)
    cvtsi2sd xmm1, dword [ui_w]
    cvtsi2sd xmm2, dword [ui_h]
    xorpd   xmm3, xmm3
    movsd   xmm4, [d_mone]
    movsd   xmm5, [d_one]
    call    glOrtho
    mov     edi, GL_MODELVIEW
    call    glMatrixMode
    call    glLoadIdentity

    mov     edi, GL_DEPTH_TEST
    call    glDisable
    mov     edi, GL_CULL_FACE
    call    glDisable
    mov     edi, GL_FOG
    call    glDisable
    mov     edi, GL_TEXTURE1            ; the night-darkening unit must not touch the GUI
    call    glActiveTexture
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    mov     edi, GL_TEXTURE0
    call    glActiveTexture
    mov     edi, GL_TEXTURE_ENV
    mov     esi, GL_TEXTURE_ENV_MODE
    mov     edx, GL_MODULATE
    call    glTexEnvi
    mov     edi, GL_TEXTURE
    call    glMatrixMode
    call    glLoadIdentity
    movss   xmm0, [f_texscale]
    movss   xmm1, [f_texscale]
    movss   xmm2, [f_one]
    call    glScalef
    mov     edi, GL_MODELVIEW
    call    glMatrixMode
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     edi, GL_TEXTURE_2D
    mov     esi, [tex_id]
    call    glBindTexture
    mov     edi, GL_ALPHA_TEST
    call    glDisable
    mov     edi, GL_BLEND
    call    glEnable
    mov     edi, GL_SRC_ALPHA
    mov     esi, GL_ONE_MINUS_SRC_ALPHA
    call    glBlendFunc
    add     rsp, 8
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- internal helpers -------------------------------------------------------

; set_color(edi rgba): glColor4ub of a packed r,g,b,a
set_color:
    sub     rsp, 8
    mov     ecx, edi
    shr     ecx, 24                     ; a
    mov     edx, edi
    shr     edx, 16
    and     edx, 255                    ; b
    mov     esi, edi
    shr     esi, 8
    and     esi, 255                    ; g
    and     edi, 255                    ; r
    call    glColor4ub
    add     rsp, 8
    ret

; hit_test(edi x, esi y, edx w, ecx h) -> eax 1 if the mouse is inside the rectangle
hit_test:
    mov     eax, [ui_mx]
    sub     eax, edi
    cmp     eax, edx                    ; unsigned: also rejects mx < x
    jae     .no
    mov     eax, [ui_my]
    sub     eax, esi
    cmp     eax, ecx
    jae     .no
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; quad_rect(edi x, esi y, edx w, ecx h): the four vertices of a rectangle (GL_QUADS open)
quad_rect:
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
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; TEXQUAD_VERTEX u, v, x, y: byte offsets into the quad record at [rbx]
%macro TEXQUAD_VERTEX 4
    mov     edi, [rbx + %1]
    mov     esi, [rbx + %2]
    call    glTexCoord2i
    mov     edi, [rbx + %3]
    mov     esi, [rbx + %4]
    call    glVertex2i
%endmacro

; quad_uv(rdi q): one textured quad (GL_QUADS open);
; q = int32 {x0, y0, x1, y1, u0, v0, u1, v1}
quad_uv:
    push    rbp
    mov     rbp, rsp
    push    rbx
    sub     rsp, 8
    mov     rbx, rdi
    TEXQUAD_VERTEX 16, 20, 0, 4
    TEXQUAD_VERTEX 24, 20, 8, 4
    TEXQUAD_VERTEX 24, 28, 8, 12
    TEXQUAD_VERTEX 16, 28, 0, 12
    add     rsp, 8
    pop     rbx
    pop     rbp
    ret

; ---- rectangles --------------------------------------------------------------

; ui_rect(edi x, esi y, edx w, ecx h, r8d rgba): untextured filled rectangle
ui_rect:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     edi, r8d
    call    set_color
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    mov     edi, GL_QUADS
    call    glBegin
    mov     edi, ebx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r14d
    call    quad_rect
    call    glEnd
    mov     edi, GL_TEXTURE_2D          ; textured state is the default between calls
    call    glEnable
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ui_frame(edi x, esi y, edx w, ecx h, r8d rgba): 1-unit outline inside the rectangle
ui_frame:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     ebx, edi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     edi, r8d
    call    set_color
    mov     edi, GL_TEXTURE_2D
    call    glDisable
    mov     edi, GL_QUADS
    call    glBegin
    mov     edi, ebx                    ; top
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, 1
    call    quad_rect
    mov     edi, ebx                    ; bottom
    lea     esi, [r12 + r14 - 1]
    mov     edx, r13d
    mov     ecx, 1
    call    quad_rect
    mov     edi, ebx                    ; left
    lea     esi, [r12 + 1]
    mov     edx, 1
    lea     ecx, [r14 - 2]
    call    quad_rect
    lea     edi, [rbx + r13 - 1]        ; right
    lea     esi, [r12 + 1]
    mov     edx, 1
    lea     ecx, [r14 - 2]
    call    quad_rect
    call    glEnd
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ui_panel(edi x, esi y, edx w, ecx h): translucent black backing
ui_panel:
    mov     r8d, RGBA(0, 0, 0, 140)
    jmp     ui_rect

; ---- text ------------------------------------------------------------------

; ui_text_width(rdi s, esi scale) -> eax pen advance of the string, (ink + 1) per glyph
ui_text_width:
    xor     eax, eax
.char:
    movzx   ecx, byte [rdi]
    test    ecx, ecx
    jz      .done
    inc     rdi
    sub     ecx, 32
    cmp     ecx, 94
    jbe     .known
    mov     ecx, 31                     ; anything outside 32..126 draws as '?'
.known:
    movzx   edx, byte [glyph_w + rcx]
    lea     eax, [rax + rdx + 1]
    jmp     .char
.done:
    imul    eax, esi
    ret

; text_quads(rdi s, esi x, edx y, ecx scale): one quad per inked glyph (GL_QUADS open)
text_quads:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40                     ; quad record + pad
    mov     rbx, rdi
    mov     r12d, esi                   ; pen x
    mov     r13d, edx                   ; y
    mov     r14d, ecx                   ; scale
.glyph:
    movzx   eax, byte [rbx]
    test    eax, eax
    jz      .done
    inc     rbx
    sub     eax, 32
    cmp     eax, 94
    jbe     .known
    mov     eax, 31                     ; '?'
.known:
    movzx   ecx, byte [glyph_w + rax]
    movzx   edx, byte [glyph_left + rax]
    mov     r15d, ecx
    imul    r15d, r14d
    add     r15d, r12d                  ; x1 = pen + w * scale
    cmp     edx, 0xFF
    je      .advance                    ; blank glyph: advance only
    mov     [rsp], r12d                 ; x0
    mov     [rsp + 4], r13d             ; y0
    mov     [rsp + 8], r15d             ; x1
    lea     esi, [r13 + r14*8]
    mov     [rsp + 12], esi             ; y1 = y + 8 * scale
    mov     esi, eax
    and     esi, 15
    shl     esi, 7                      ; glyph column * 8 px * 16
    shl     edx, 4
    add     esi, edx                    ; u0 = (gx + left) * 16
    mov     [rsp + 16], esi
    shl     ecx, 4
    add     esi, ecx                    ; u1 = u0 + w * 16
    mov     [rsp + 24], esi
    shr     eax, 4
    shl     eax, 7
    add     eax, FONT_Y * 16            ; v0 = (FONT_Y + glyph row * 8) * 16
    mov     [rsp + 20], eax
    add     eax, 128                    ; v1 = v0 + 8 * 16
    mov     [rsp + 28], eax
    mov     rdi, rsp
    call    quad_uv
.advance:
    lea     r12d, [r15 + r14]           ; next pen = x1 + the 1-unit gap
    jmp     .glyph
.done:
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ui_text(rdi s, esi x, edx y, ecx rgba, r8d scale) -> eax pen advance
; drawn twice: a shadow at (+scale, +scale) in rgb/4 with the same alpha, then the text
ui_text:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, r8d
    mov     esi, r15d
    call    ui_text_width               ; rdi is still s
    mov     [rsp], eax
    test    eax, eax
    jz      .ret
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     edi, r14d                   ; shadow colour
    shr     edi, 2
    and     edi, 0x003F3F3F
    mov     eax, r14d
    and     eax, 0xFF000000
    or      edi, eax
    call    set_color
    mov     edi, GL_QUADS
    call    glBegin
    mov     rdi, rbx
    lea     esi, [r12 + r15]
    lea     edx, [r13 + r15]
    mov     ecx, r15d
    call    text_quads
    call    glEnd
    mov     edi, r14d
    call    set_color
    mov     edi, GL_QUADS
    call    glBegin
    mov     rdi, rbx
    mov     esi, r12d
    mov     edx, r13d
    mov     ecx, r15d
    call    text_quads
    call    glEnd
.ret:
    mov     eax, [rsp]
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ui_text_centered(rdi s, esi cx, edx y, ecx rgba, r8d scale): ink centred on cx
ui_text_centered:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 8
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, r8d
    mov     esi, r15d
    call    ui_text_width
    test    eax, eax
    jz      .ret
    sub     eax, r15d                   ; drop the trailing 1-unit gap
    sar     eax, 1
    mov     esi, r12d
    sub     esi, eax
    mov     rdi, rbx
    mov     edx, r13d
    mov     ecx, r14d
    mov     r8d, r15d
    call    ui_text
.ret:
    add     rsp, 8
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- widgets ---------------------------------------------------------------

; ui_button(rdi label, esi x, edx y, ecx w, r8d enabled) -> eax 1 if clicked
ui_button:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [rsp] = hover
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     r15d, r8d
    xor     eax, eax
    test    r15d, r15d
    jz      .hover_known
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, BTN_H
    call    hit_test
.hover_known:
    mov     [rsp], eax
    mov     r8d, RGBA(255, 255, 255, 16)
    test    r15d, r15d
    jz      .bg
    mov     r8d, RGBA(255, 255, 255, 38)
    test    eax, eax
    jz      .bg
    mov     r8d, RGBA(255, 255, 255, 77)
.bg:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, BTN_H
    call    ui_rect
    cmp     dword [rsp], 0
    je      .label
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, BTN_H
    mov     r8d, RGBA(255, 255, 255, 128)
    call    ui_frame
.label:
    mov     ecx, WHITE
    mov     eax, RGBA(128, 128, 128, 255)
    test    r15d, r15d
    cmovz   ecx, eax
    mov     eax, r14d
    shr     eax, 1
    lea     esi, [r12 + rax]            ; x + w/2
    lea     edx, [r13 + 6]
    mov     rdi, rbx
    mov     r8d, 1
    call    ui_text_centered
    xor     eax, eax
    cmp     dword [rsp], 0
    je      .ret
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .ret
    movss   xmm0, [f_click_vol]
    mov     edi, SND_CLICK
    call    audio_play
    mov     eax, 1
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ui_slider(rdi SLIDERDEF*, esi x, edx y, ecx w) -> eax 1 if the value changed
ui_slider:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 152                    ; [rsp] label (128), +128 hover, +132 old value
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     rax, [rbx + SLIDERDEF.value]
    mov     eax, [rax]
    mov     [rsp + 132], eax            ; value before this frame
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, BTN_H
    call    hit_test
    mov     [rsp + 128], eax
    test    eax, eax
    jz      .no_press
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .no_press
    mov     [ui_active], rbx
.no_press:
    cmp     [ui_active], rbx
    jne     .draw
    cmp     dword [ui_input + UIINPUT.lmb_held], 0
    jne     .drag
    mov     qword [ui_active], 0        ; released
    jmp     .draw
.drag:
    mov     dword [rsp + 128], 1        ; stays highlighted while dragging
    mov     ecx, [rbx + SLIDERDEF.max]
    sub     ecx, [rbx + SLIDERDEF.min]  ; range
    lea     esi, [r14 - 8]              ; travel = w - 8
    xor     eax, eax
    test    ecx, ecx
    jle     .have_t
    test    esi, esi
    jle     .have_t
    mov     eax, [ui_mx]
    sub     eax, r12d
    sub     eax, 4                      ; knob centre offset
    jns     .pos
    xor     eax, eax
.pos:
    cmp     eax, esi
    cmovg   eax, esi                    ; 0..travel
    imul    eax, ecx
    add     eax, eax
    add     eax, esi                    ; 2*off*range + travel: rounds to nearest
    lea     ecx, [rsi + rsi]
    xor     edx, edx
    div     ecx
.have_t:
    add     eax, [rbx + SLIDERDEF.min]
    mov     rdx, [rbx + SLIDERDEF.value]
    mov     [rdx], eax
.draw:
    mov     r8d, RGBA(255, 255, 255, 38)
    cmp     dword [rsp + 128], 0
    je      .bg
    mov     r8d, RGBA(255, 255, 255, 77)
.bg:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, BTN_H
    call    ui_rect
    cmp     dword [rsp + 128], 0
    je      .knob
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, BTN_H
    mov     r8d, RGBA(255, 255, 255, 128)
    call    ui_frame
.knob:
    mov     rax, [rbx + SLIDERDEF.value]
    mov     eax, [rax]
    sub     eax, [rbx + SLIDERDEF.min]
    jns     .k_lo
    xor     eax, eax
.k_lo:
    mov     ecx, [rbx + SLIDERDEF.max]
    sub     ecx, [rbx + SLIDERDEF.min]  ; range
    cmp     eax, ecx
    cmovg   eax, ecx
    test    ecx, ecx
    jle     .k_zero
    lea     esi, [r14 - 8]
    imul    eax, esi
    xor     edx, edx
    div     ecx                         ; (v - min) * (w - 8) / range
    jmp     .k_have
.k_zero:
    xor     eax, eax
.k_have:
    lea     edi, [r12 + rax]
    mov     esi, r13d
    mov     edx, 8
    mov     ecx, BTN_H
    mov     r8d, RGBA(255, 255, 255, 170)
    call    ui_rect
    ; label = prefix + value + suffix
    mov     r15, rsp
    mov     rsi, [rbx + SLIDERDEF.prefix]
    test    rsi, rsi
    jz      .no_prefix
    mov     rdi, r15
    call    str_append
    mov     r15, rax
.no_prefix:
    mov     rax, [rbx + SLIDERDEF.value]
    mov     edi, [rax]
    mov     rsi, r15
    call    i32_to_str
    mov     r15, rax
    mov     rsi, [rbx + SLIDERDEF.suffix]
    test    rsi, rsi
    jz      .no_suffix
    mov     rdi, r15
    call    str_append
    mov     r15, rax
.no_suffix:
    mov     byte [r15], 0
    mov     eax, r14d
    shr     eax, 1
    lea     esi, [r12 + rax]
    lea     edx, [r13 + 6]
    mov     rdi, rsp
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text_centered
    mov     rax, [rbx + SLIDERDEF.value]
    mov     eax, [rax]
    xor     edx, edx
    cmp     eax, [rsp + 132]
    setne   dl
    mov     eax, edx
    add     rsp, 152
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ui_textfield(rdi TEXTFIELD*, esi x, edx y, ecx w) -> eax 1 if Enter was pressed in it
ui_textfield:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24                     ; [rsp] focused, +4 enter, +8 room, +12 text width
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     dword [rsp + 4], 0
    cmp     dword [ui_input + UIINPUT.lmb_pressed], 0
    je      .focus_known
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, BTN_H
    call    hit_test
    test    eax, eax
    jz      .clicked_outside
    mov     [ui_focus], rbx
    jmp     .focus_known
.clicked_outside:
    cmp     [ui_focus], rbx
    jne     .focus_known
    mov     qword [ui_focus], 0
.focus_known:
    xor     eax, eax
    cmp     [ui_focus], rbx
    sete    al
    mov     [rsp], eax
    test    eax, eax
    jz      .draw
    mov     esi, [rbx + TEXTFIELD.len]
    cmp     esi, 32
    jbe     .len_ok
    mov     esi, 32
.len_ok:
    mov     edx, [rbx + TEXTFIELD.max]
    cmp     edx, 32
    jbe     .max_ok
    mov     edx, 32
.max_ok:
    mov     ecx, [ui_input + UIINPUT.typed_len]
    cmp     ecx, 32
    jbe     .typed_ok
    mov     ecx, 32
.typed_ok:
    xor     r8d, r8d
.append:
    cmp     r8d, ecx
    jae     .appended
    cmp     esi, edx
    jae     .appended
    movzx   eax, byte [ui_input + UIINPUT.typed + r8]
    mov     [rbx + TEXTFIELD.buf + rsi], al
    inc     esi
    inc     r8d
    jmp     .append
.appended:
    mov     ecx, [ui_input + UIINPUT.backspace]
.erase:
    test    ecx, ecx
    jle     .erased
    test    esi, esi
    jz      .erased
    dec     esi
    dec     ecx
    jmp     .erase
.erased:
    mov     [rbx + TEXTFIELD.len], esi
    mov     byte [rbx + TEXTFIELD.buf + rsi], 0
    xor     eax, eax
    cmp     dword [ui_input + UIINPUT.enter], 0
    setne   al
    mov     [rsp + 4], eax
.draw:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, BTN_H
    mov     r8d, RGBA(0, 0, 0, 192)
    call    ui_rect
    mov     r8d, RGBA(160, 160, 160, 255)
    cmp     dword [rsp], 0
    je      .frame
    mov     r8d, WHITE
.frame:
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, r14d
    mov     ecx, BTN_H
    call    ui_frame
    ; room for text = w - 8 (minus the caret while focused); a longer text shows its tail
    mov     eax, r14d
    sub     eax, 8
    cmp     dword [rsp], 0
    je      .room_known
    mov     [rsp + 8], eax
    lea     rdi, [s_caret]
    mov     esi, 1
    call    ui_text_width
    mov     ecx, [rsp + 8]
    sub     ecx, eax
    mov     eax, ecx
.room_known:
    mov     [rsp + 8], eax
    lea     r15, [rbx + TEXTFIELD.buf]
.clip:
    mov     rdi, r15
    mov     esi, 1
    call    ui_text_width
    cmp     eax, [rsp + 8]
    jle     .clipped
    cmp     byte [r15], 0
    je      .clipped
    inc     r15
    jmp     .clip
.clipped:
    mov     rdi, r15
    lea     esi, [r12 + 4]
    lea     edx, [r13 + 6]
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
    cmp     dword [rsp], 0
    je      .ret
    mov     [rsp + 12], eax
    call    glfwGetTime
    mulsd   xmm0, [d_two]
    cvttsd2si eax, xmm0
    test    eax, 1                      ; caret shows on every other half second
    jnz     .ret
    lea     rdi, [s_caret]
    lea     esi, [r12 + 4]
    add     esi, [rsp + 12]
    lea     edx, [r13 + 6]
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
.ret:
    mov     eax, [rsp + 4]
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---- icons and item slots -----------------------------------------------------

; ui_item_icon(edi id, esi x, edx y, ecx size): the item's icon, white; ui_tile_icon with the
; item's atlas tile
ui_item_icon:
    mov     eax, edi
    cmp     eax, NUM_ITEMS
    jae     .ret
    cmp     byte [item_max_stack + rax], 0
    je      .ret                        ; air and the unused ids have no icon
    movzx   edi, byte [item_icon + rax] ; atlas tile
    mov     r8d, WHITE
    jmp     ui_tile_icon
.ret:
    ret

; ui_tile_icon(edi tile, esi x, edx y, ecx size, r8d rgba): an atlas tile scaled to size x size at
; (x, y), uv inset 1 unit, multiplied by the colour (its alpha too: 0xAABBGGRR as for ui_rect)
ui_tile_icon:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 48                     ; quad record, then the colour
    mov     eax, edi
    mov     [rsp + 32], r8d
    mov     [rsp], esi                  ; x0
    mov     [rsp + 4], edx              ; y0
    add     esi, ecx
    mov     [rsp + 8], esi              ; x1
    add     edx, ecx
    mov     [rsp + 12], edx             ; y1
    mov     edx, eax
    and     edx, 15
    shl     edx, 8
    inc     edx                         ; u0 = col * 256 + 1
    mov     [rsp + 16], edx
    add     edx, 254
    mov     [rsp + 24], edx             ; u1
    shr     eax, 4
    shl     eax, 8
    inc     eax                         ; v0 = row * 256 + 1
    mov     [rsp + 20], eax
    add     eax, 254
    mov     [rsp + 28], eax             ; v1
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     edi, [rsp + 32]
    call    set_color
    mov     edi, GL_QUADS
    call    glBegin
    mov     rdi, rsp
    call    quad_uv
    call    glEnd
    add     rsp, 48
    pop     rbp
    ret

; ui_icon9(edi tile, esi x, edx y): the top-left 9x9 texels of a tile, 9x9 GUI units
ui_icon9:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 32
    mov     [rsp], esi                  ; x0
    mov     [rsp + 4], edx              ; y0
    lea     eax, [rsi + 9]
    mov     [rsp + 8], eax              ; x1
    lea     eax, [rdx + 9]
    mov     [rsp + 12], eax             ; y1
    mov     eax, edi
    and     eax, 15
    shl     eax, 8                      ; u0 = col * 256
    mov     [rsp + 16], eax
    add     eax, 144                    ; 9 texels * 16
    mov     [rsp + 24], eax
    shr     edi, 4
    shl     edi, 8                      ; v0 = row * 256
    mov     [rsp + 20], edi
    add     edi, 144
    mov     [rsp + 28], edi
    mov     edi, GL_TEXTURE_2D
    call    glEnable
    mov     edi, WHITE
    call    set_color
    mov     edi, GL_QUADS
    call    glBegin
    mov     rdi, rsp
    call    quad_uv
    call    glEnd
    add     rsp, 32
    pop     rbp
    ret

; ui_slot(rdi ITEMSTACK*, esi x, edx y, ecx show_count) -> eax 1 if hovered
; an 18x18 cell: icon, durability bar for damaged tools, stack count, hover highlight
ui_slot:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 40                     ; [rsp] dur, +4 dmg, +8 bar width, +16 count text
    mov     rbx, rdi
    mov     r12d, esi
    mov     r13d, edx
    mov     r14d, ecx
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, 18
    mov     ecx, 18
    call    hit_test
    mov     r15d, eax                   ; hover
    mov     edi, r12d
    mov     esi, r13d
    mov     edx, 18
    mov     ecx, 18
    mov     r8d, RGBA(0, 0, 0, 90)
    call    ui_rect
    movzx   eax, byte [rbx + ITEMSTACK.id]
    cmp     eax, NUM_ITEMS
    jae     .hover
    cmp     byte [item_max_stack + rax], 0
    je      .hover
    cmp     byte [rbx + ITEMSTACK.count], 0
    je      .hover
    mov     edi, eax
    lea     esi, [r12 + 1]
    lea     edx, [r13 + 1]
    mov     ecx, 16
    call    ui_item_icon
    ; durability bar: wearing items (tools, bow, armor...) with damage
    movzx   eax, byte [rbx + ITEMSTACK.id]
    movzx   ecx, word [item_durability + rax*2]
    movzx   edx, word [rbx + ITEMSTACK.dmg]
    test    ecx, ecx
    jz      .count
    test    edx, edx
    jz      .count
    cmp     edx, ecx
    cmova   edx, ecx                    ; dmg never exceeds the durability
    mov     [rsp], ecx
    mov     [rsp + 4], edx
    lea     edi, [r12 + 2]
    lea     esi, [r13 + 14]
    mov     edx, 14
    mov     ecx, 2
    mov     r8d, RGBA(0, 0, 0, 255)
    call    ui_rect
    mov     ecx, [rsp]                  ; dur
    mov     esi, [rsp + 4]              ; dmg
    mov     eax, ecx
    sub     eax, esi
    imul    eax, 14
    xor     edx, edx
    div     ecx                         ; filled width = 14 * (dur - dmg) / dur
    mov     [rsp + 8], eax
    mov     eax, esi
    imul    eax, 255
    xor     edx, edx
    div     ecx                         ; red = 255 * dmg / dur
    mov     edx, 255
    sub     edx, eax
    shl     edx, 8
    or      eax, edx
    or      eax, 0xFF000000             ; RGBA(red, 255 - red, 0, 255)
    mov     r8d, eax
    mov     edx, [rsp + 8]
    test    edx, edx
    jz      .count
    lea     edi, [r12 + 2]
    lea     esi, [r13 + 14]
    mov     ecx, 2
    call    ui_rect
.count:
    test    r14d, r14d
    jz      .hover
    movzx   edi, byte [rbx + ITEMSTACK.count]
    cmp     edi, 1
    jbe     .hover
    lea     rsi, [rsp + 16]
    call    i32_to_str
    mov     byte [rax], 0
    lea     rdi, [rsp + 16]
    mov     esi, 1
    call    ui_text_width
    lea     esi, [r12 + 17]
    sub     esi, eax                    ; right edge at x + 17
    lea     rdi, [rsp + 16]
    lea     edx, [r13 + 10]
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
.hover:
    test    r15d, r15d
    jz      .ret
    lea     edi, [r12 + 1]
    lea     esi, [r13 + 1]
    mov     edx, 16
    mov     ecx, 16
    mov     r8d, RGBA(255, 255, 255, 96)
    call    ui_rect
.ret:
    mov     eax, r15d
    add     rsp, 40
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ui_tooltip(rdi s): panel with the text at the mouse, kept inside the screen. Text wider than
; the screen breaks at the last space that lets the first line fit, onto a second line.
; Frame: [rsp] copy of the text (192 bytes) when it is split, [rsp+192] panel height.
ui_tooltip:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 200
    mov     rbx, rdi
    xor     r15d, r15d                  ; offset of the second line in the copy, 0 = one line
    mov     dword [rsp + 192], 14
    test    rbx, rbx
    jz      .ret
    cmp     byte [rbx], 0
    je      .ret
    mov     rdi, rbx
    mov     esi, 1
    call    ui_text_width
    lea     r12d, [rax + 6]             ; panel width: text + 3 padding each side
    cmp     r12d, [ui_w]
    jle     .place
    ; copy (at most 191 chars), then try the spaces from the end: first only those before
    ; a " - " suffix, then any space
    xor     ecx, ecx
.copy:
    mov     al, [rbx + rcx]
    mov     [rsp + rcx], al
    test    al, al
    jz      .copied
    inc     ecx
    cmp     ecx, 191
    jb      .copy
    mov     byte [rsp + rcx], 0
.copied:
    mov     r14d, 1                     ; pass 1: the break must start a " - " suffix
    mov     [rsp + 196], ecx            ; length
.pass:
    mov     r13d, [rsp + 196]           ; candidate break index
.split:
    dec     r13d
    jle     .next_pass
    cmp     byte [rsp + r13], ' '
    jne     .split
    test    r14d, r14d
    jz      .try
    cmp     byte [rsp + r13 + 1], '-'
    jne     .split
.try:
    mov     byte [rsp + r13], 0
    mov     rdi, rsp
    mov     esi, 1
    call    ui_text_width
    add     eax, 6
    cmp     eax, [ui_w]
    jle     .two_lines
    mov     byte [rsp + r13], ' '
    jmp     .split
.next_pass:
    dec     r14d
    jz      .pass                       ; pass 2: any space
    jmp     .place                      ; no space lets it fit: keep one line
.two_lines:
    mov     r12d, eax
    lea     r15d, [r13 + 1]
    lea     rdi, [rsp + r15]
    mov     esi, 1
    call    ui_text_width
    add     eax, 6
    cmp     eax, r12d
    cmovg   r12d, eax
    mov     rbx, rsp
    mov     dword [rsp + 192], 25
.place:
    mov     r13d, [ui_mx]
    add     r13d, 12
    mov     r14d, [ui_my]
    sub     r14d, 12
    mov     eax, [ui_w]
    sub     eax, r12d
    cmp     r13d, eax
    cmovg   r13d, eax
    xor     eax, eax
    test    r13d, r13d
    cmovs   r13d, eax
    mov     eax, [ui_h]
    sub     eax, [rsp + 192]
    cmp     r14d, eax
    cmovg   r14d, eax
    xor     eax, eax
    test    r14d, r14d
    cmovs   r14d, eax
    mov     edi, r13d
    mov     esi, r14d
    mov     edx, r12d
    mov     ecx, [rsp + 192]
    call    ui_panel
    mov     rdi, rbx
    lea     esi, [r13 + 3]
    lea     edx, [r14 + 3]
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
    test    r15d, r15d
    jz      .ret
    lea     rdi, [rsp + r15]
    lea     esi, [r13 + 3]
    lea     edx, [r14 + 14]
    mov     ecx, WHITE
    mov     r8d, 1
    call    ui_text
.ret:
    add     rsp, 200
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ui_tooltip_lines(rdi lines qword[n], esi n, rdx colours dword[n], ecx side): a panel of n
; one-line texts, each in its own colour. The panel is the widest line + 6 wide and 11 * n + 3
; high and sits at y = my - 12; side 0 puts it right of the mouse (x = mx + 12), side 1 left of
; it (its right edge at mx - 12). It stays inside the screen. Nothing is drawn for n = 0.
; Frame: [rsp] panel x, +4 y, +8 width, +12 height, +16 line index.
ui_tooltip_lines:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 24
    mov     rbx, rdi                    ; lines
    mov     r12d, esi                   ; n
    mov     r13, rdx                    ; colours
    mov     r14d, ecx                   ; side
    xor     r15d, r15d                  ; widest line
    test    r12d, r12d
    jz      .ret
    mov     dword [rsp + 16], 0
.measure:
    mov     eax, [rsp + 16]
    mov     rdi, [rbx + rax*8]
    mov     esi, 1
    call    ui_text_width
    cmp     eax, r15d
    cmova   r15d, eax
    inc     dword [rsp + 16]
    mov     eax, [rsp + 16]
    cmp     eax, r12d
    jb      .measure
    add     r15d, 6                     ; text + 3 padding each side
    mov     [rsp + 8], r15d
    imul    eax, r12d, 11
    add     eax, 3
    mov     [rsp + 12], eax
    mov     eax, [ui_mx]
    sub     eax, 12
    sub     eax, r15d                   ; side 1: the panel ends at mx - 12
    lea     ecx, [rax + r15 + 24]       ; side 0: x = mx + 12
    test    r14d, r14d
    cmovz   eax, ecx
    mov     ecx, [ui_w]
    sub     ecx, r15d
    cmp     eax, ecx
    cmovg   eax, ecx
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    mov     [rsp], eax
    mov     eax, [ui_my]
    sub     eax, 12
    mov     ecx, [ui_h]
    sub     ecx, [rsp + 12]
    cmp     eax, ecx
    cmovg   eax, ecx
    xor     ecx, ecx
    test    eax, eax
    cmovs   eax, ecx
    mov     [rsp + 4], eax
    mov     edi, [rsp]
    mov     esi, [rsp + 4]
    mov     edx, [rsp + 8]
    mov     ecx, [rsp + 12]
    call    ui_panel
    mov     dword [rsp + 16], 0
.line:
    mov     eax, [rsp + 16]
    mov     rdi, [rbx + rax*8]
    mov     ecx, [r13 + rax*4]
    imul    edx, eax, 11
    add     edx, [rsp + 4]
    add     edx, 3
    mov     esi, [rsp]
    add     esi, 3
    mov     r8d, 1
    call    ui_text
    inc     dword [rsp + 16]
    mov     eax, [rsp + 16]
    cmp     eax, r12d
    jb      .line
.ret:
    add     rsp, 24
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret
