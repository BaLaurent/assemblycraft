; texgen.asm - procedural 256x256 RGBA texture atlas (16x16 tiles plus the 8x8 font).
;
; texgen_build(rdi out): zero out[262144], then draw tiles in order using a single
; xorshift32 stream (state 0x12345678, x ^= x<<13; x ^= x>>17; x ^= x<<5; a "draw"
; returns the NEW state). Pixel = base*m >> 8 per channel, alpha 255. Tiles 13, 14,
; the crack stages (256 draws first) and 64..69 continue the stream after tile 12;
; item icons (32..42) and HUD icons (48..53) use no rng. The font is painted last
; (white glyph texels) at atlas rows FONT_Y..FONT_Y+47.
;
; Register use inside texgen_build (leaf function, no external calls):
;   r12  = out base          r13d = rng state
;   rbx  = tile base pointer r14d = py, r15d = px
;   rdi  = current pixel pointer (set by TILE_BEGIN)
;   r8d  = per-pixel multiplier m
%include "common.inc"
default rel

global texgen_build

extern font8x8

; packed colour: R | G<<8 | B<<16 (little-endian dword = RGBA bytes, A in bits 24..31)
%define RGB(r, g, b) ((r) | ((g) << 8) | ((b) << 16))
; opaque packed colour for the icon tiles (alpha 255)
%define RGBO(r, g, b) ((r) | ((g) << 8) | ((b) << 16) | 0xFF000000)

section .rodata
half:   dd 0.5

section .text

; rng: advance state, return it in eax. Clobbers ecx.
rng:
    mov     eax, r13d
    mov     ecx, eax
    shl     ecx, 13
    xor     eax, ecx
    mov     ecx, eax
    shr     ecx, 17
    xor     eax, ecx
    mov     ecx, eax
    shl     ecx, 5
    xor     eax, ecx
    mov     r13d, eax
    ret

; shade: write pixel at [rdi] = (esi.R*edx>>8, esi.G*edx>>8, esi.B*edx>>8, 255).
; Clobbers eax.
shade:
    movzx   eax, sil
    imul    eax, edx
    shr     eax, 8
    mov     [rdi], al
    mov     eax, esi
    shr     eax, 8
    movzx   eax, al
    imul    eax, edx
    shr     eax, 8
    mov     [rdi + 1], al
    mov     eax, esi
    shr     eax, 16
    movzx   eax, al
    imul    eax, edx
    shr     eax, 8
    mov     [rdi + 2], al
    mov     byte [rdi + 3], 255
    ret

; Open a tile: rbx = tile base, loop py (r14d) / px (r15d), rdi = pixel pointer.
%macro TILE_BEGIN 1
%push tile
    lea     rbx, [r12 + ((((%1) >> 4) * 16 * 256 + ((%1) & 15) * 16) * 4)]
    xor     r14d, r14d
%$row:
    xor     r15d, r15d
%$col:
    mov     edi, r14d
    shl     edi, 10
    add     rdi, rbx
    lea     rdi, [rdi + r15 * 4]
%endmacro

%macro TILE_END 0
    inc     r15d
    cmp     r15d, 16
    jb      %$col
    inc     r14d
    cmp     r14d, 16
    jb      %$row
%pop
%endmacro

; same as TILE_BEGIN but for a tile base already in rbx
%macro TILE_BEGIN_RBX 0
%push tile
    xor     r14d, r14d
%$row:
    xor     r15d, r15d
%$col:
    mov     edi, r14d
    shl     edi, 10
    add     rdi, rbx
    lea     rdi, [rdi + r15 * 4]
%endmacro

; icon tile: pixel routine returns the packed RGBA in eax
%macro ICON 2
    TILE_BEGIN %1
    call    %2
    mov     [rdi], eax
    TILE_END
%endmacro

; tool icon: r10d = main colour m, r11d = dark colour M
%macro ICONT 4
    TILE_BEGIN %1
    mov     r10d, %3
    mov     r11d, %4
    call    %2
    mov     [rdi], eax
    TILE_END
%endmacro

; HUD icon: bitmap, full palette, empty palette, split column
%macro HUD 5
    TILE_BEGIN %1
    lea     r9, [%2]
    lea     r10, [%3]
    lea     r11, [%4]
    mov     r8d, %5
    call    hud_px
    mov     [rdi], eax
    TILE_END
%endmacro

; m = mbase + (rng & mask) -> r8d (one draw)
%macro DRAW_M 2
    call    rng
    and     eax, %2
    add     eax, %1
    mov     r8d, eax
%endmacro

; shade pixel with base colour (immediate) and m in r8d
%macro SHADE_IMM 1
    mov     esi, %1
    mov     edx, r8d
    call    shade
%endmacro

; plain noise pixel: draw, shade with immediate base
%macro NOISE_PIXEL 3                    ; base, mbase, mask
    DRAW_M  %2, %3
    SHADE_IMM %1
%endmacro

texgen_build:
    push    rbp
    mov     rbp, rsp
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15
    sub     rsp, 280                    ; [rsp] 16 bytes of column depths, [rsp+16] 256 bytes of crack values (+8 pad)

    mov     r12, rdi
    xor     eax, eax
    mov     ecx, 262144 / 8
    rep stosq                           ; rdi advances; r12 keeps the base
    mov     r13d, 0x12345678

    ; ---- 0 stone ----
    TILE_BEGIN 0
    NOISE_PIXEL RGB(128,128,128), 200, 55
    TILE_END

    ; ---- 1 grass_top ----
    TILE_BEGIN 1
    NOISE_PIXEL RGB(106,170,64), 192, 63
    TILE_END

    ; ---- 2 grass_side ----
    ; column depths first: d = 3 + (r&1), +2 more if (r&7)==0
    xor     r15d, r15d
.t2_depth:
    call    rng
    mov     edx, eax
    and     edx, 1
    add     edx, 3
    test    eax, 7
    jnz     .t2_store
    add     edx, 2
.t2_store:
    mov     [rsp + r15], dl
    inc     r15d
    cmp     r15d, 16
    jb      .t2_depth
    TILE_BEGIN 2
    DRAW_M  192, 63
    movzx   eax, byte [rsp + r15]
    mov     esi, RGB(150,108,74)
    cmp     r14d, eax
    jae     .t2_shade
    mov     esi, RGB(106,170,64)
.t2_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 3 dirt ----
    TILE_BEGIN 3
    NOISE_PIXEL RGB(150,108,74), 192, 63
    TILE_END

    ; ---- 4 cobble ----
    TILE_BEGIN 4
    DRAW_M  176, 63
    mov     esi, RGB(70,70,70)
    mov     eax, r14d
    and     eax, 3
    cmp     eax, 3
    je      .t4_shade
    mov     eax, r14d
    shr     eax, 2
    lea     eax, [rax + rax * 2]        ; (py>>2)*3
    add     eax, r15d
    xor     edx, edx
    mov     ecx, 5
    div     ecx
    cmp     edx, 4
    je      .t4_shade
    mov     esi, RGB(130,130,130)
.t4_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 5 planks ----
    TILE_BEGIN 5
    DRAW_M  216, 31
    mov     esi, RGB(110,86,50)
    mov     eax, r14d
    and     eax, 3
    cmp     eax, 3
    je      .t5_shade
    mov     eax, r14d
    shr     eax, 2
    imul    eax, eax, 7
    add     eax, 3
    and     eax, 15
    cmp     eax, r15d
    je      .t5_shade
    mov     esi, RGB(162,130,78)
.t5_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 6 log_side ----
    TILE_BEGIN 6
    call    rng
    mov     r9d, eax                    ; r9d = r
    and     eax, 47
    add     eax, 208
    mov     r8d, eax
    mov     eax, r9d
    and     eax, 1
    add     eax, r15d
    and     eax, 3
    mov     esi, RGB(78,60,36)
    jz      .t6_shade
    mov     esi, RGB(104,82,50)
.t6_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 7 log_top ----
    TILE_BEGIN 7
    DRAW_M  224, 31
    mov     esi, RGB(104,82,50)
    test    r15d, r15d
    jz      .t7_shade
    cmp     r15d, 15
    je      .t7_shade
    test    r14d, r14d
    jz      .t7_shade
    cmp     r14d, 15
    je      .t7_shade
    lea     eax, [r15 * 2 - 15]         ; dx
    lea     ecx, [r14 * 2 - 15]         ; dy
    imul    eax, eax
    imul    ecx, ecx
    add     eax, ecx
    cvtsi2ss xmm0, eax
    sqrtss  xmm0, xmm0
    mulss   xmm0, [half]
    cvttss2si eax, xmm0
    shr     eax, 1
    and     eax, 1
    mov     esi, RGB(176,140,88)
    jz      .t7_shade
    mov     esi, RGB(150,118,70)
.t7_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 8 leaves ----
    TILE_BEGIN 8
    call    rng
    test    eax, 3
    jnz     .t8_solid
    mov     dword [rdi], 0
    jmp     .t8_next
.t8_solid:
    and     eax, 95
    add     eax, 160
    mov     r8d, eax
    SHADE_IMM RGB(60,140,40)
.t8_next:
    TILE_END

    ; ---- 9 sand ----
    TILE_BEGIN 9
    NOISE_PIXEL RGB(222,210,160), 224, 31
    TILE_END

    ; ---- 10 glass (no rng) ----
    TILE_BEGIN 10
    xor     edx, edx                    ; default transparent
    test    r15d, r15d
    jz      .t10_border
    cmp     r15d, 15
    je      .t10_border
    test    r14d, r14d
    jz      .t10_border
    cmp     r14d, 15
    je      .t10_border
    lea     eax, [r15 - 3]
    cmp     eax, 5                      ; 3 <= px <= 8
    ja      .t10_store
    lea     eax, [r15 + r14]
    sub     eax, 10
    cmp     eax, 1                      ; px+py in {10,11}
    ja      .t10_store
    mov     edx, 0xFFFFFFFF
    jmp     .t10_store
.t10_border:
    mov     edx, 0xFFF5F0DC             ; (220,240,245,255)
.t10_store:
    mov     [rdi], edx
    TILE_END

    ; ---- 11 brick ----
    TILE_BEGIN 11
    DRAW_M  200, 55
    mov     esi, RGB(180,180,170)
    mov     eax, r14d
    and     eax, 3
    cmp     eax, 3
    je      .t11_shade
    mov     eax, r14d
    shr     eax, 2
    and     eax, 1
    shl     eax, 2
    add     eax, r15d
    and     eax, 7
    cmp     eax, 7
    je      .t11_shade
    mov     esi, RGB(156,72,56)
.t11_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 12 bedrock ----
    TILE_BEGIN 12
    NOISE_PIXEL RGB(80,80,80), 64, 191
    TILE_END

    ; ---- 13 table_top (one draw per pixel) ----
    TILE_BEGIN 13
    DRAW_M  216, 31
    mov     esi, RGB(104,82,50)         ; border
    test    r15d, r15d
    jz      .t13_shade
    cmp     r15d, 15
    je      .t13_shade
    test    r14d, r14d
    jz      .t13_shade
    cmp     r14d, 15
    je      .t13_shade
    mov     esi, RGB(110,86,50)         ; cross seams
    cmp     r15d, 7
    je      .t13_shade
    cmp     r14d, 7
    je      .t13_shade
    mov     esi, RGB(162,130,78)
.t13_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 14 table_side: planks rule plus top trim, saw and hammer ----
    TILE_BEGIN 14
    DRAW_M  216, 31
    mov     esi, RGB(110,86,50)
    mov     eax, r14d
    and     eax, 3
    cmp     eax, 3
    je      .t14_over
    mov     eax, r14d
    shr     eax, 2
    imul    eax, eax, 7
    add     eax, 3
    and     eax, 15
    cmp     eax, r15d
    je      .t14_over
    mov     esi, RGB(162,130,78)
.t14_over:
    cmp     r14d, 2
    ja      .t14_saw
    mov     esi, RGB(104,82,50)         ; py <= 2: trim
    jmp     .t14_shade
.t14_saw:
    lea     eax, [r15 - 2]
    cmp     eax, 4
    ja      .t14_handle                 ; px 2..6
    lea     eax, [r14 - 5]
    cmp     eax, 4
    ja      .t14_handle                 ; py 5..9
    cmp     r14d, 9
    jne     .t14_blade
    test    r15d, 1
    jz      .t14_shade                  ; py 9, px even: teeth gap keeps the planks
.t14_blade:
    mov     esi, RGB(150,150,150)
    jmp     .t14_shade
.t14_handle:
    lea     eax, [r15 - 10]
    cmp     eax, 1
    ja      .t14_head                   ; px 10..11
    lea     eax, [r14 - 7]
    cmp     eax, 6
    ja      .t14_head                   ; py 7..13
    mov     esi, RGB(78,60,36)
    jmp     .t14_shade
.t14_head:
    lea     eax, [r15 - 8]
    cmp     eax, 5
    ja      .t14_shade                  ; px 8..13
    lea     eax, [r14 - 5]
    cmp     eax, 1
    ja      .t14_shade                  ; py 5..6
    mov     esi, RGB(110,110,110)
.t14_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- crack values: 256 draws, v[py*16+px] = r & 255 (stack buffer at [rsp+16]) ----
    xor     r10d, r10d
.crk_draw:
    call    rng
    mov     [rsp + 16 + r10], al
    inc     r10d
    cmp     r10d, 256
    jb      .crk_draw

    ; ---- 16..25 crack stages: pixel is dark when v < 13*(k+1), else transparent ----
    xor     r10d, r10d                  ; k
.crk_stage:
    lea     r11d, [r10 + 1]
    imul    r11d, r11d, 13              ; threshold
    mov     rbx, r10
    shl     rbx, 6                      ; k * 16 px * 4 bytes
    lea     rbx, [r12 + rbx + 16 * 256 * 4]
    TILE_BEGIN_RBX
    mov     eax, r14d
    shl     eax, 4
    add     eax, r15d
    movzx   eax, byte [rsp + 16 + rax]
    xor     edx, edx
    cmp     eax, r11d
    jae     .crk_store
    mov     edx, RGBO(32,32,32)
.crk_store:
    mov     [rdi], edx
    TILE_END
    inc     r10d
    cmp     r10d, 10
    jb      .crk_stage

    ; ---- 32..42 item icons (no rng; opaque unshaded colours) ----
    ICON    32, icon_stick
    ICONT   33, icon_pick,   {RGBO(160,122,66)}, {RGBO(96,72,36)}
    ICONT   34, icon_axe,    {RGBO(160,122,66)}, {RGBO(96,72,36)}
    ICONT   35, icon_shovel, {RGBO(160,122,66)}, {RGBO(96,72,36)}
    ICONT   36, icon_sword,  {RGBO(160,122,66)}, {RGBO(96,72,36)}
    ICONT   37, icon_pick,   {RGBO(150,150,150)}, {RGBO(86,86,86)}
    ICONT   38, icon_axe,    {RGBO(150,150,150)}, {RGBO(86,86,86)}
    ICONT   39, icon_shovel, {RGBO(150,150,150)}, {RGBO(86,86,86)}
    ICONT   40, icon_sword,  {RGBO(150,150,150)}, {RGBO(86,86,86)}
    ICON    41, icon_apple
    ICON    42, icon_pork

    ; ---- 48..53 HUD hearts and food (9x9 bitmaps, no rng) ----
    HUD     48, heart_bmp, heart_pal_full, heart_pal_empty, 9
    HUD     49, heart_bmp, heart_pal_full, heart_pal_empty, 5
    HUD     50, heart_bmp, heart_pal_full, heart_pal_empty, 0
    HUD     51, food_bmp, food_pal_full, food_pal_empty, 9
    HUD     52, food_bmp, food_pal_full, food_pal_empty, 5
    HUD     53, food_bmp, food_pal_full, food_pal_empty, 0

    ; ---- 64 zombie skin ----
    TILE_BEGIN 64
    NOISE_PIXEL RGB(74,128,64), 200, 55
    TILE_END

    ; ---- 65 zombie face: eyes at px {4,5,10,11}, py {6,7}; mouth py 11, px 5..10 ----
    TILE_BEGIN 65
    DRAW_M  200, 55
    mov     esi, RGB(74,128,64)
    lea     eax, [r14 - 6]
    cmp     eax, 1
    ja      .t65_mouth
    lea     eax, [r15 - 4]
    cmp     eax, 1
    jbe     .t65_eye
    lea     eax, [r15 - 10]
    cmp     eax, 1
    ja      .t65_shade
.t65_eye:
    mov     esi, RGB(24,24,24)
    jmp     .t65_shade
.t65_mouth:
    cmp     r14d, 11
    jne     .t65_shade
    lea     eax, [r15 - 5]
    cmp     eax, 5
    ja      .t65_shade
    mov     esi, RGB(40,72,34)
.t65_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- 66 zombie shirt ----
    TILE_BEGIN 66
    NOISE_PIXEL RGB(40,160,170), 200, 55
    TILE_END

    ; ---- 67 zombie pants ----
    TILE_BEGIN 67
    NOISE_PIXEL RGB(60,60,150), 200, 55
    TILE_END

    ; ---- 68 pig skin ----
    TILE_BEGIN 68
    NOISE_PIXEL RGB(240,160,160), 220, 35
    TILE_END

    ; ---- 69 pig face: eyes px {3,4,11,12} py {5,6}; snout px 5..10 py 8..11; nostrils ----
    TILE_BEGIN 69
    DRAW_M  220, 35
    mov     esi, RGB(240,160,160)
    lea     eax, [r14 - 5]
    cmp     eax, 1
    ja      .t69_snout
    lea     eax, [r15 - 3]
    cmp     eax, 1
    jbe     .t69_eye
    lea     eax, [r15 - 11]
    cmp     eax, 1
    ja      .t69_shade
.t69_eye:
    mov     esi, RGB(24,24,24)
    jmp     .t69_shade
.t69_snout:
    lea     eax, [r14 - 8]
    cmp     eax, 3
    ja      .t69_shade
    lea     eax, [r15 - 5]
    cmp     eax, 5
    ja      .t69_shade
    mov     esi, RGB(218,128,138)
    lea     eax, [r14 - 9]
    cmp     eax, 1
    ja      .t69_shade
    cmp     r15d, 6
    je      .t69_nostril
    cmp     r15d, 9
    jne     .t69_shade
.t69_nostril:
    mov     esi, RGB(110,50,60)
.t69_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    ; ---- font (no rng; always last): glyph c-32 at ((c-32)&15)*8, FONT_Y + ((c-32)>>4)*8
    xor     r9d, r9d                    ; glyph index 0..95
.font_glyph:
    xor     r14d, r14d                  ; row y
.font_row:
    mov     eax, r9d
    lea     eax, [r14 + rax * 8]
    lea     rcx, [font8x8]
    movzx   r10d, byte [rcx + rax]      ; row bits, bit 0 = leftmost
    xor     r15d, r15d                  ; column x
.font_col:
    bt      r10d, r15d
    jnc     .font_next
    mov     eax, r9d                    ; atlas y = FONT_Y + (g>>4)*8 + y
    shr     eax, 4
    lea     eax, [r14 + rax * 8 + FONT_Y]
    shl     eax, 8
    mov     ecx, r9d                    ; atlas x = (g&15)*8 + x
    and     ecx, 15
    lea     ecx, [r15 + rcx * 8]
    add     eax, ecx
    mov     dword [r12 + rax * 4], 0xFFFFFFFF
.font_next:
    inc     r15d
    cmp     r15d, 8
    jb      .font_col
    inc     r14d
    cmp     r14d, 8
    jb      .font_row
    inc     r9d
    cmp     r9d, 96
    jb      .font_glyph

    add     rsp, 280
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    pop     rbp
    ret

; ---------------------------------------------------------------------------
; Per-pixel icon routines. In: r15d = px, r14d = py (r10d/r11d = m/M colours for
; the tool heads). Out: eax = packed RGBA (0 = transparent). They never touch
; rdi, rbx, r12-r15, so TILE_BEGIN's loop survives the call.
; ---------------------------------------------------------------------------

; stick: h on px+py==15 (3..12), H on px+py==16 (4..13)
icon_stick:
    lea     ecx, [r15 + r14]
    cmp     ecx, 15
    jne     .shadow
    lea     edx, [r15 - 3]
    cmp     edx, 9
    ja      .none
    mov     eax, RGBO(137,103,39)
    ret
.shadow:
    cmp     ecx, 16
    jne     .none
    lea     edx, [r15 - 4]
    cmp     edx, 9
    ja      .none
    mov     eax, RGBO(84,62,22)
    ret
.none:
    xor     eax, eax
    ret

; tool handle: h on px+py==15 (2..9), H on px+py==16 (3..10)
tool_handle:
    lea     ecx, [r15 + r14]
    cmp     ecx, 15
    jne     .shadow
    lea     edx, [r15 - 2]
    cmp     edx, 7
    ja      .none
    mov     eax, RGBO(137,103,39)
    ret
.shadow:
    cmp     ecx, 16
    jne     .none
    lea     edx, [r15 - 3]
    cmp     edx, 7
    ja      .none
    mov     eax, RGBO(84,62,22)
    ret
.none:
    xor     eax, eax
    ret

; pickaxe head: arc 9.5 <= r < 12.0 around (2.5, 13.5) within the NE quadrant
icon_pick:
    cvtsi2ss xmm0, r15d
    subss   xmm0, [f2_5]                ; dx
    movss   xmm1, [f13_5]
    cvtsi2ss xmm2, r14d
    subss   xmm1, xmm2                  ; dy
    movaps  xmm2, xmm0
    addss   xmm2, xmm1                  ; dx + dy
    mulss   xmm0, xmm0
    mulss   xmm1, xmm1
    addss   xmm0, xmm1                  ; r^2
    comiss  xmm0, [f90_25]
    jb      tool_handle
    comiss  xmm0, [f144_0]
    jae     tool_handle
    movaps  xmm3, xmm0
    sqrtss  xmm0, xmm0                  ; r
    mulss   xmm0, [f_sqrt2]
    mulss   xmm0, [f0_8]                ; 0.8 * sqrt2 * r  (c >= 0.8)
    comiss  xmm2, xmm0
    jb      tool_handle
    mov     eax, r10d
    comiss  xmm3, [f121_0]
    jb      .done                       ; r < 11.0 -> m
    mov     eax, r11d
.done:
    ret

; axe blade: 5<=px<=10, 1<=py<=6, 8<=px+py<=14; M on its px==5, py==1, px+py==8 edges
icon_axe:
    lea     eax, [r15 - 5]
    cmp     eax, 5
    ja      tool_handle
    lea     eax, [r14 - 1]
    cmp     eax, 5
    ja      tool_handle
    lea     ecx, [r15 + r14]
    lea     eax, [rcx - 8]
    cmp     eax, 6
    ja      tool_handle
    mov     eax, r11d
    cmp     r15d, 5
    je      .done
    cmp     r14d, 1
    je      .done
    cmp     ecx, 8
    je      .done
    mov     eax, r10d
.done:
    ret

; shovel blade: diamond |px-11|+|py-4| <= 2 is m, == 3 is M
icon_shovel:
    mov     eax, r15d
    sub     eax, 11
    cdq
    xor     eax, edx
    sub     eax, edx
    mov     ecx, eax
    mov     eax, r14d
    sub     eax, 4
    cdq
    xor     eax, edx
    sub     eax, edx
    add     eax, ecx
    cmp     eax, 2
    jbe     .m
    cmp     eax, 3
    je      .M
    jmp     tool_handle
.m:
    mov     eax, r10d
    ret
.M:
    mov     eax, r11d
    ret

; sword: blade m on px+py==15, M on 14/16 (px 6..13) and (14,1); guard H; grip h; pommel H
icon_sword:
    lea     ecx, [r15 + r14]
    lea     edx, [r15 - 6]
    cmp     edx, 7
    ja      .notblade
    cmp     ecx, 15
    je      .m
    cmp     ecx, 14
    je      .M
    cmp     ecx, 16
    je      .M
.notblade:
    cmp     r15d, 14
    jne     .guard
    cmp     r14d, 1
    je      .M
.guard:
    mov     eax, r15d
    sub     eax, r14d
    cmp     eax, -5
    jne     .grip
    lea     edx, [r15 - 3]
    cmp     edx, 4
    ja      .grip
    mov     eax, RGBO(84,62,22)
    ret
.grip:
    cmp     ecx, 15
    jne     .pommel
    lea     edx, [r15 - 2]
    cmp     edx, 2
    ja      .pommel
    mov     eax, RGBO(137,103,39)
    ret
.pommel:
    xor     eax, eax
    cmp     r15d, 1
    jne     .done
    cmp     r14d, 14
    jne     .done
    mov     eax, RGBO(84,62,22)
.done:
    ret
.m:
    mov     eax, r10d
    ret
.M:
    mov     eax, r11d
    ret

; apple: specials (highlight, stem, leaf) over a disc around (7.5, 8.5)
icon_apple:
    lea     rsi, [apple_pts]
.pt:
    movzx   eax, byte [rsi]
    cmp     eax, 0xFF
    je      .body
    cmp     eax, r15d
    jne     .next
    movzx   eax, byte [rsi + 1]
    cmp     eax, r14d
    jne     .next
    mov     eax, [rsi + 4]
    ret
.next:
    add     rsi, 8
    jmp     .pt
.body:
    cvtsi2ss xmm0, r15d
    subss   xmm0, [f7_5]
    mulss   xmm0, xmm0
    cvtsi2ss xmm1, r14d
    subss   xmm1, [f8_5]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1                  ; d^2
    xor     eax, eax
    comiss  xmm0, [f30_25]
    ja      .done                       ; d > 5.5
    mov     eax, RGBO(128,12,12)
    comiss  xmm0, [f21_16]
    ja      .done                       ; 4.6 < d <= 5.5
    mov     eax, RGBO(196,24,24)
.done:
    ret

; porkchop: ellipse v = ((px-7.5)/6.5)^2 + ((py-8)/4.5)^2 <= 1
icon_pork:
    cvtsi2ss xmm0, r15d
    subss   xmm0, [f7_5]
    divss   xmm0, [f6_5]
    mulss   xmm0, xmm0
    cvtsi2ss xmm1, r14d
    subss   xmm1, [f8_0]
    divss   xmm1, [f4_5]
    mulss   xmm1, xmm1
    addss   xmm0, xmm1                  ; v
    xor     eax, eax
    comiss  xmm0, [f1_0]
    ja      .done                       ; outside
    mov     eax, RGBO(180,80,80)
    comiss  xmm0, [f0_72]
    ja      .done                       ; rim
    mov     eax, RGBO(232,138,138)
    comiss  xmm0, [f0_45]
    jbe     .done                       ; core
    cmp     r15d, 7
    jg      .done
    mov     eax, RGBO(250,215,205)      ; fat highlight (left part of the mid ring)
.done:
    ret

; HUD 9x9 bitmap pixel. In: r9 = bitmap (81 chars), r10 = full palette, r11 = empty
; palette, r8d = split column (px < split uses the full palette). Out: eax.
hud_px:
    xor     eax, eax
    cmp     r15d, 8
    ja      .done
    cmp     r14d, 8
    ja      .done
    lea     eax, [r14 + r14 * 8]
    add     eax, r15d
    movzx   ecx, byte [r9 + rax]
    mov     rdx, r10
    cmp     r15d, r8d
    jb      .search
    mov     rdx, r11
.search:
    xor     eax, eax
.entry:
    movzx   esi, byte [rdx]
    test    esi, esi
    jz      .done                       ; not in palette -> transparent
    cmp     esi, ecx
    je      .found
    add     rdx, 8
    jmp     .entry
.found:
    mov     eax, [rdx + 4]
.done:
    ret

section .rodata
f2_5:       dd 2.5
f13_5:      dd 13.5
f90_25:     dd 90.25
f144_0:     dd 144.0
f121_0:     dd 121.0
f_sqrt2:    dd 1.41421356
f0_8:       dd 0.80
f7_5:       dd 7.5
f8_5:       dd 8.5
f8_0:       dd 8.0
f6_5:       dd 6.5
f4_5:       dd 4.5
f30_25:     dd 30.25
f21_16:     dd 21.16
f1_0:       dd 1.0
f0_72:      dd 0.72
f0_45:      dd 0.45

; apple specials: db px, py, 0, 0 ; dd colour; px == 0xFF ends the list
%macro PT 3+
    db %1, %2, 0, 0
    dd %3
%endmacro
apple_pts:
    PT 5, 6, RGBO(240,120,120)
    PT 5, 7, RGBO(240,120,120)
    PT 6, 6, RGBO(240,120,120)
    PT 8, 2, RGBO(90,60,20)
    PT 8, 3, RGBO(90,60,20)
    PT 9, 2, RGBO(60,140,40)
    PT 10, 2, RGBO(60,140,40)
    PT 10, 1, RGBO(60,140,40)
    PT 0xFF, 0, 0

; HUD palettes: db char, 0, 0, 0 ; dd colour; char 0 ends
%macro PAL 4
    db %1, 0, 0, 0
    dd RGBO(%2, %3, %4)
%endmacro
heart_pal_full:
    PAL 'K', 24, 24, 24
    PAL 'r', 214, 28, 28
    PAL 'w', 255, 150, 150
    dq 0
heart_pal_empty:
    PAL 'K', 24, 24, 24
    PAL 'r', 52, 20, 20
    PAL 'w', 52, 20, 20
    dq 0
food_pal_full:
    PAL 'K', 40, 26, 14
    PAL 'm', 186, 108, 48
    PAL 'w', 226, 168, 108
    PAL 'b', 236, 232, 220
    dq 0
food_pal_empty:
    PAL 'K', 40, 26, 14
    PAL 'm', 58, 40, 28
    PAL 'w', 58, 40, 28
    PAL 'b', 96, 96, 96
    dq 0

heart_bmp:
    db ".KKK.KKK."
    db "KrrrKrrrK"
    db "KrwrrrrrK"
    db "KrrrrrrrK"
    db ".KrrrrrK."
    db "..KrrrK.."
    db "...KrK..."
    db "....K...."
    db "........."
food_bmp:
    db "....KKK.."
    db "...KmmmK."
    db "..KmmwmmK"
    db "..KmmmmmK"
    db "...KmmmK."
    db "..KbKKK.."
    db ".KbK....."
    db "KbbK....."
    db ".KK......"

section .text
