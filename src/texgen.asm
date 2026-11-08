; texgen.asm - procedural 256x512 RGBA texture atlas (16x16 tiles in rows 0..255, the 8x8 font
; at FONT_Y = 256).
;
; texgen_build(rdi out): zero out[ATLAS_W * ATLAS_H * 4], then draw tiles in order using a single
; xorshift32 stream (state 0x12345678, x ^= x<<13; x ^= x>>17; x ^= x<<5; a "draw"
; returns the NEW state). Pixel = base*m >> 8 per channel, alpha 255. Tiles 13, 14,
; the crack stages (256 draws first) and 64..70 continue the stream after tile 12;
; then, in this order, the ores 26..29, furnaces 30/31, chest 43/44, gravel 45, TNT
; 46/47 and the mob tiles 71..79 follow tile 70; item icons (32..42, 80..128) and HUD
; icons (48..56) use no rng. The 0.6 RPG art (stone bricks 59/60, item icons 129..138, ability
; icons 139..150, class emblems 151..154, stat icons 155..172, villager/boss textures 173..179)
; is drawn after tile 128, so it never shifts an older rng draw: bricks and the 174..179
; textures are 16x16 bitmaps shaded by one draw per pixel (173 is plain noise), the icons are
; draw-free bitmaps. The font is painted last (white glyph texels) at atlas
; rows FONT_Y..FONT_Y+47.
; The 0.7 building art (tiles 15, 61..63, 180..191, 200..202, 240..253) is drawn after the 0.6 art
; and before the font: noise tiles take one draw per pixel (NFUNC), icons copy earlier tiles.
; The 0.8 icons (tiles 203..207, 216..223, 232..239, 254, 255) follow the 0.7 art, draw-free bitmaps.
; The 0.9 art (the 20 tiles 192..199, 208..215, 224..227 the font left free when it moved to
; FONT_Y) follows the 0.8 icons and precedes the font, in tile order: noise tiles take one draw
; per pixel (NFUNC / NFUNCA), the bitmaps (tall grass, bed and boat icons, bubbles) take none.
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

; 16x16 bitmap icon: tile, bitmap (256 chars), palette (PAL records, 0 terminated)
%macro BMP 3
    TILE_BEGIN %1
    lea     r9, [%2]
    lea     r10, [%3]
    call    bmp_px
    mov     [rdi], eax
    TILE_END
%endmacro

; noise-shaded 16x16 bitmap tile: tile, bitmap, palette, mbase, mask. One rng draw per pixel
; (m = mbase + (draw & mask)); every bitmap char, '.' included, must be in the palette.
%macro NBMP 5
    TILE_BEGIN %1
    call    rng
    and     eax, %5
    add     eax, %4
    mov     r8d, eax
    lea     r9, [%2]
    lea     r10, [%3]
    call    bmp_px
    mov     esi, eax
    mov     edx, r8d
    call    shade
    TILE_END
%endmacro

; porkchop-shaped icon: r9d = fat, r10d = meat, r11d = rim colours
%macro ICON3 5
    TILE_BEGIN %1
    mov     r9d, %3
    mov     r10d, %4
    mov     r11d, %5
    call    %2
    mov     [rdi], eax
    TILE_END
%endmacro

; rng-drawn tile: one draw per pixel, r9d = r, r8d = mbase + ((r >> shift) & mask),
; func returns the base colour in esi (r10d/r11d = variant parameters set by the caller)
%macro RNGTILE 5                        ; tile, mbase, mask, shift, func
    TILE_BEGIN %1
    call    rng
    mov     r9d, eax
    shr     eax, %4
    and     eax, %3
    add     eax, %2
    mov     r8d, eax
    call    %5
    mov     edx, r8d
    call    shade
    TILE_END
%endmacro

; jump to %1 when the pixel is on the tile border
%macro IF_BORDER 1
    test    r15d, r15d
    jz      %1
    cmp     r15d, 15
    je      %1
    test    r14d, r14d
    jz      %1
    cmp     r14d, 15
    je      %1
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

; 0.7 colour names (macro arguments cannot carry RGB(r,g,b): the commas split them)
%define C_SANDSTONE    RGB(222,206,154)
%define C_SANDSTONE_DK RGB(200,182,128)
%define C_SANDBOT      RGB(206,190,140)
%define C_SANDBOT_DK   RGB(186,168,118)
%define C_IRON         RGB(206,206,210)
%define C_IRON_HI      RGB(244,244,248)
%define C_GOLD         RGB(240,200,48)
%define C_GOLD_HI      RGB(255,238,120)
%define C_DIAM         RGB(70,206,196)
%define C_DIAM_HI      RGB(170,250,244)

; noise-shaded tile drawn by a per-pixel base-colour routine: tile, mbase, mask, shift, func,
; r10d, r11d. One rng draw per pixel (m = mbase + ((draw >> shift) & mask)); func gets px r15d,
; py r14d, draw r9d, parameters r10d/r11d and returns esi = base colour, 0 = transparent.
%macro NFUNC 7
    TILE_BEGIN %1
    mov     r10d, %6
    mov     r11d, %7
    call    rng
    mov     r9d, eax
    shr     eax, %4
    and     eax, %3
    add     eax, %2
    mov     r8d, eax
    call    %5
    test    esi, esi
    jz      %$clear
    mov     edx, r8d
    call    shade
    jmp     %$next
%$clear:
    mov     dword [rdi], 0
%$next:
    TILE_END
%endmacro

; NFUNC with a fixed alpha on every opaque texel (translucent tiles): tile, mbase, mask, shift,
; func, r10d, r11d, alpha
%macro NFUNCA 8
    TILE_BEGIN %1
    mov     r10d, %6
    mov     r11d, %7
    call    rng
    mov     r9d, eax
    shr     eax, %4
    and     eax, %3
    add     eax, %2
    mov     r8d, eax
    call    %5
    test    esi, esi
    jz      %$clear
    mov     edx, r8d
    call    shade
    mov     byte [rdi + 3], %8
    jmp     %$next
%$clear:
    mov     dword [rdi], 0
%$next:
    TILE_END
%endmacro

; 0.9 colour names
%define C_WATER        RGB(40,90,200)
%define C_LEAF_PINE    RGB(30,80,40)
%define C_LEAF_BIRCH   RGB(110,170,70)
%define C_RING_PINE    RGB(150,110,70)
%define C_RING_PINE_DK RGB(122,86,50)

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
    mov     ecx, ATLAS_W * ATLAS_H * 4 / 8
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
    ICON3   42, icon_pork, {RGBO(250,215,205)}, {RGBO(232,138,138)}, {RGBO(180,80,80)}

    ; ---- 48..53 HUD hearts and food (9x9 bitmaps, no rng) ----
    HUD     48, heart_bmp, heart_pal_full, heart_pal_empty, 9
    HUD     49, heart_bmp, heart_pal_full, heart_pal_empty, 5
    HUD     50, heart_bmp, heart_pal_full, heart_pal_empty, 0
    HUD     51, food_bmp, food_pal_full, food_pal_empty, 9
    HUD     52, food_bmp, food_pal_full, food_pal_empty, 5
    HUD     53, food_bmp, food_pal_full, food_pal_empty, 0
    HUD     54, armor_bmp, armor_pal_full, armor_pal_empty, 9
    HUD     55, armor_bmp, armor_pal_full, armor_pal_empty, 5
    HUD     56, armor_bmp, armor_pal_full, armor_pal_empty, 0

    ; ---- 57, 58 fire flames: two animation frames, transparent around the flames (no rng) ----
    BMP     57, fire0_bmp, pal_fire
    BMP     58, fire1_bmp, pal_fire

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

    ; ---- 70 player skin (the first-person arm) ----
    TILE_BEGIN TILE_PLAYER_SKIN
    NOISE_PIXEL RGB(198,150,112), 224, 31
    TILE_END

    ; ---- 26..29 ores: stone with a shared vein mask; r10d = ore colour, r11d = highlight ----
    mov     r10d, RGB(30,30,30)
    mov     r11d, RGB(60,60,60)
    RNGTILE 26, 200, 55, 0, px_ore
    mov     r10d, RGB(216,175,147)
    mov     r11d, RGB(240,210,180)
    RNGTILE 27, 200, 55, 0, px_ore
    mov     r10d, RGB(252,238,75)
    mov     r11d, RGB(255,255,180)
    RNGTILE 28, 200, 55, 0, px_ore
    mov     r10d, RGB(93,236,245)
    mov     r11d, RGB(200,255,255)
    RNGTILE 29, 200, 55, 0, px_ore

    ; ---- 30 furnace front, 31 lit ----
    xor     r10d, r10d
    RNGTILE 30, 200, 55, 0, px_furnace
    mov     r10d, 1
    RNGTILE 31, 200, 55, 0, px_furnace

    ; ---- 43 chest top, 44 chest side, 45 gravel, 46 TNT side, 47 TNT top ----
    RNGTILE 43, 216, 31, 0, px_chest_top
    RNGTILE 44, 216, 31, 0, px_chest_side
    RNGTILE 45, 216, 39, 8, px_gravel
    RNGTILE 46, 216, 31, 0, px_tnt_side
    RNGTILE 47, 216, 31, 0, px_tnt_top

    ; ---- 71 creeper skin, 72 face, 73 skeleton bone, 74 face, 75 spider body, 76 face,
    ;      77 chicken body, 78 face, 79 leg ----
    xor     r10d, r10d
    RNGTILE 71, 200, 55, 0, px_creeper
    mov     r10d, 1
    RNGTILE 72, 200, 55, 0, px_creeper
    xor     r10d, r10d
    RNGTILE 73, 200, 55, 0, px_skeleton
    mov     r10d, 1
    RNGTILE 74, 200, 55, 0, px_skeleton
    xor     r10d, r10d
    RNGTILE 75, 200, 55, 0, px_spider
    mov     r10d, 1
    RNGTILE 76, 200, 55, 0, px_spider
    xor     r10d, r10d
    RNGTILE 77, 220, 35, 0, px_chicken
    mov     r10d, 1
    RNGTILE 78, 220, 35, 0, px_chicken
    TILE_BEGIN 79
    NOISE_PIXEL RGB(240,180,40), 220, 35
    TILE_END

    ; ---- 80..118 item icons (no rng): materials, tools, bow and misc, armor (119..128: firearms below) ----
    BMP     80, coal_bmp, pal_coal
    BMP     81, ingot_bmp, pal_ingot_iron
    BMP     82, ingot_bmp, pal_ingot_gold
    BMP     83, diamond_bmp, pal_diamond
    ICONT   84, icon_pick,   {RGBO(220,220,220)}, {RGBO(130,130,130)}
    ICONT   85, icon_axe,    {RGBO(220,220,220)}, {RGBO(130,130,130)}
    ICONT   86, icon_shovel, {RGBO(220,220,220)}, {RGBO(130,130,130)}
    ICONT   87, icon_sword,  {RGBO(220,220,220)}, {RGBO(130,130,130)}
    ICONT   88, icon_pick,   {RGBO(250,220,60)}, {RGBO(180,130,10)}
    ICONT   89, icon_axe,    {RGBO(250,220,60)}, {RGBO(180,130,10)}
    ICONT   90, icon_shovel, {RGBO(250,220,60)}, {RGBO(180,130,10)}
    ICONT   91, icon_sword,  {RGBO(250,220,60)}, {RGBO(180,130,10)}
    ICONT   92, icon_pick,   {RGBO(90,230,230)}, {RGBO(25,140,140)}
    ICONT   93, icon_axe,    {RGBO(90,230,230)}, {RGBO(25,140,140)}
    ICONT   94, icon_shovel, {RGBO(90,230,230)}, {RGBO(25,140,140)}
    ICONT   95, icon_sword,  {RGBO(90,230,230)}, {RGBO(25,140,140)}
    BMP     96, bow_bmp, pal_bow
    BMP     97, arrow_bmp, pal_arrow
    BMP     98, string_bmp, pal_string
    BMP     99, gunpowder_bmp, pal_gunpowder
    BMP     100, flint_bmp, pal_flint
    BMP     101, flintsteel_bmp, pal_flintsteel
    BMP     102, rotten_bmp, pal_rotten
    ICON3   103, icon_pork, {RGBO(225,190,150)}, {RGBO(165,95,50)}, {RGBO(110,60,30)}
    BMP     104, feather_bmp, pal_feather
    BMP     105, drumstick_bmp, pal_drum_raw
    BMP     106, drumstick_bmp, pal_drum_cooked
    BMP     107, helmet_bmp, pal_armor_iron
    BMP     108, chestplate_bmp, pal_armor_iron
    BMP     109, leggings_bmp, pal_armor_iron
    BMP     110, boots_bmp, pal_armor_iron
    BMP     111, helmet_bmp, pal_armor_gold
    BMP     112, chestplate_bmp, pal_armor_gold
    BMP     113, leggings_bmp, pal_armor_gold
    BMP     114, boots_bmp, pal_armor_gold
    BMP     115, helmet_bmp, pal_armor_diamond
    BMP     116, chestplate_bmp, pal_armor_diamond
    BMP     117, leggings_bmp, pal_armor_diamond
    BMP     118, boots_bmp, pal_armor_diamond
    ; ---- 119..128 firearm icons: pistol, musket, shotgun, kalashnikov, rocket launcher,
    ;      then the pistol round, musket ball, shotgun shell, rifle round and rocket ----
    BMP     119, pistol_bmp, pal_pistol
    BMP     120, musket_bmp, pal_musket
    BMP     121, shotgun_bmp, pal_shotgun
    BMP     122, kalash_bmp, pal_kalash
    BMP     123, launcher_bmp, pal_launcher
    BMP     124, round_pistol_bmp, pal_brass
    BMP     125, musket_ball_bmp, pal_ball
    BMP     126, shell_bmp, pal_shell
    BMP     127, round_rifle_bmp, pal_brass
    BMP     128, rocket_bmp, pal_rocket

    ; ---- 59, 60 .. 179: RPG art (all drawn after every older rng draw, so tiles 0..128 and the
    ;      font are unchanged) ----
    ; ---- 59, 60 stone bricks, mossy: bitmaps over a light rng noise (after every older rng draw) ----
    NBMP    59, brick_bmp, pal_brick, 232, 23
    NBMP    60, mossy_bmp, pal_mossy, 232, 23
    ; ---- 129..138 weapon and consumable icons: staff, archmage staff, iron dagger, diamond dagger,
    ; Shadow Fang, King's Blade, Celestial Bow, health potion, mana potion, gold coin ----
    BMP     129, staff_bmp, pal_staff
    BMP     130, archstaff_bmp, pal_archstaff
    BMP     131, dagger_bmp, pal_dagger_iron
    BMP     132, dagger_bmp, pal_dagger_diamond
    BMP     133, fang_bmp, pal_fang
    BMP     134, kings_bmp, pal_kings
    BMP     135, celestial_bmp, pal_celestial
    BMP     136, potion_bmp, pal_potion_red
    BMP     137, potion_bmp, pal_potion_blue
    BMP     138, coin_bmp, pal_coin
    ; ---- 139..150 ability icons: Warrior Charge/War Cry/Whirlwind, Mage Fireball/Blink/Meteor Storm,
    ; Archer Volley/Explosive Arrow/Arrow Rain, Rogue Shadowstep/Smoke Bomb/Blade Dance ----
    BMP     139, charge_bmp, pal_charge
    BMP     140, warcry_bmp, pal_warcry
    BMP     141, whirl_bmp, pal_whirl
    BMP     142, fireball_bmp, pal_fireball
    BMP     143, blink_bmp, pal_blink
    BMP     144, meteor_bmp, pal_meteor
    BMP     145, volley_bmp, pal_volley
    BMP     146, explarrow_bmp, pal_explarrow
    BMP     147, arrowrain_bmp, pal_arrowrain
    BMP     148, shadowstep_bmp, pal_shadowstep
    BMP     149, smoke_bmp, pal_smoke
    BMP     150, bladedance_bmp, pal_bladedance
    ; ---- 151..154 class emblems: Warrior, Mage, Archer, Rogue ----
    BMP     151, emb_warrior_bmp, pal_emb_warrior
    BMP     152, emb_mage_bmp, pal_emb_mage
    BMP     153, emb_archer_bmp, pal_emb_archer
    BMP     154, emb_rogue_bmp, pal_emb_rogue
    ; ---- 155..172 stat icons, one per stat id (health, melee, ranged, spell, crit chance, crit dmg, mana,
    ; mana regen, stamina, stamina regen, armor, move speed, backstab, parry, lifesteal, cooldown,
    ; arrow save, dodge cost) ----
    BMP     155, st_health_bmp, pal_st_health
    BMP     156, st_melee_bmp, pal_st_melee
    BMP     157, st_ranged_bmp, pal_st_ranged
    BMP     158, st_spell_bmp, pal_st_spell
    BMP     159, st_critchance_bmp, pal_st_critchance
    BMP     160, st_critdmg_bmp, pal_st_critdmg
    BMP     161, st_mana_bmp, pal_st_mana
    BMP     162, st_manaregen_bmp, pal_st_manaregen
    BMP     163, st_stamina_bmp, pal_st_stamina
    BMP     164, st_staminaregen_bmp, pal_st_staminaregen
    BMP     165, st_armor_bmp, pal_st_armor
    BMP     166, st_speed_bmp, pal_st_speed
    BMP     167, st_backstab_bmp, pal_st_backstab
    BMP     168, st_parry_bmp, pal_st_parry
    BMP     169, st_lifesteal_bmp, pal_st_lifesteal
    BMP     170, st_cooldown_bmp, pal_st_cooldown
    BMP     171, st_arrowsave_bmp, pal_st_arrowsave
    BMP     172, st_wind_bmp, pal_st_wind
    ; ---- 173..179 villager and boss textures (noise-shaded; 174..179 carry a bitmap overlay) ----
    TILE_BEGIN 173
    NOISE_PIXEL RGB(225,180,140), 224, 31
    TILE_END
    NBMP    174, npc_face_bmp, pal_npc_face, 224, 31
    NBMP    175, npc_merchant_bmp, pal_npc_merchant, 224, 31
    NBMP    176, npc_elder_bmp, pal_npc_elder, 224, 31
    NBMP    177, npc_bossrobe_bmp, pal_npc_bossrobe, 224, 31
    NBMP    178, npc_bossface_bmp, pal_npc_bossface, 224, 31
    NBMP    179, npc_crown_bmp, pal_npc_crown, 224, 31

    ; ---- 0.7 building art (drawn after every older rng draw, before the font; the atlas outside
    ;      these tiles is untouched). Noise tiles take one draw per pixel via NFUNC. Source tiles
    ;      first, then the icons that copy them. ----
    ; 61, 62, 63 sandstone top, side, bottom
    NFUNC   61, 224, 31, 0, px_speckle, C_SANDSTONE, C_SANDSTONE_DK
    NFUNC   62, 224, 31, 0, px_sand_side, 0, 0
    NFUNC   63, 216, 31, 0, px_speckle, C_SANDBOT, C_SANDBOT_DK
    ; 180 smooth stone, 181 mossy cobblestone
    NFUNC   180, 236, 15, 0, px_smooth, 0, 0
    NFUNC   181, 176, 63, 0, px_cobble_mossy, 0, 0
    ; 182 cracked stone bricks: tile 59's bitmap with dark crack pixels
    NBMP    182, cracked_bmp, pal_cracked, 232, 23
    ; 183 bookshelf side, 184 wool
    NFUNC   183, 232, 23, 0, px_bookshelf, 0, 0
    NFUNC   184, 224, 31, 0, px_wool, 0, 0
    ; 185..187 blocks of iron, gold, diamond: 2x2 bevelled plates (base, highlight)
    NFUNC   185, 240, 15, 0, px_plates, C_IRON, C_IRON_HI
    NFUNC   186, 240, 15, 0, px_plates, C_GOLD, C_GOLD_HI
    NFUNC   187, 240, 15, 0, px_plates, C_DIAM, C_DIAM_HI
    ; 188 block of coal
    NFUNC   188, 160, 127, 0, px_coal, 0, 0
    ; 189, 190 wooden door lower, upper; 191, 15 iron door lower, upper
    NFUNC   189, 232, 23, 0, px_wood_door, 0, 0
    NFUNC   190, 232, 23, 0, px_wood_door, 1, 0
    NFUNC   191, 240, 15, 0, px_iron_door, 0, 0
    NFUNC   15, 240, 15, 0, px_iron_door, 1, 0
    ; 200 trapdoor, 201 ladder
    NFUNC   200, 232, 23, 0, px_trapdoor, 0, 0
    NFUNC   201, 224, 31, 0, px_ladder, 0, 0
    ; 202 torch (no rng)
    ICON    202, icon_torch
    ; 240..244 stair icons and 245..249 slab icons: planks, cobble, stone brick, brick, sandstone
    ICONT   240, icon_stair, 5, 0
    ICONT   241, icon_stair, 4, 0
    ICONT   242, icon_stair, 59, 0
    ICONT   243, icon_stair, 11, 0
    ICONT   244, icon_stair, 62, 0
    ICONT   245, icon_slab, 5, 0
    ICONT   246, icon_slab, 4, 0
    ICONT   247, icon_slab, 59, 0
    ICONT   248, icon_slab, 11, 0
    ICONT   249, icon_slab, 62, 0
    ; 250, 251 door icons (upper tile, lower tile), 252 fence, 253 glass pane
    ICONT   250, icon_door, 190, 189
    ICONT   251, icon_door, 15, 191
    BMP     252, fence_icon_bmp, pal_fence_icon
    BMP     253, pane_icon_bmp, pal_pane_icon

    ; ---- 0.8 art (drawn after the 0.7 art, no rng, before the font; the atlas outside these 23 tiles
    ;      is untouched) ----
    ; 203, 204 ring, amulet; 205, 206 iron and diamond warhammer; 207, 216 iron and diamond spear
    BMP     203, ring_bmp, pal_ring
    BMP     204, amulet_bmp, pal_amulet
    BMP     205, hammer_bmp, pal_gear_iron
    BMP     206, hammer_bmp, pal_gear_diamond
    BMP     207, spear_bmp, pal_gear_iron
    BMP     216, spear_bmp, pal_gear_diamond
    ; 217..220 slot-3 abilities: Ground Slam, Frost Nova, Hunter's Mark, Fan of Knives
    BMP     217, slam_bmp, pal_slam
    BMP     218, nova_bmp, pal_nova
    BMP     219, mark_bmp, pal_mark
    BMP     220, knives_bmp, pal_knives
    ; 221..223, 232 attributes: strength, dexterity, intelligence, vitality
    BMP     221, attr_str_bmp, pal_attr_str
    BMP     222, attr_dex_bmp, pal_attr_dex
    BMP     223, attr_int_bmp, pal_attr_int
    BMP     232, attr_vit_bmp, pal_attr_vit
    ; 233..236 elements: fire, frost, shock, poison
    BMP     233, elem_fire_bmp, pal_elem_fire
    BMP     234, elem_frost_bmp, pal_elem_frost
    BMP     235, elem_shock_bmp, pal_elem_shock
    BMP     236, elem_poison_bmp, pal_elem_poison
    ; 237..239, 254 stat icons: attack speed, bleed, area, elite; 255 keystone
    BMP     237, st_aspd_bmp, pal_st_aspd
    BMP     238, st_bleed_bmp, pal_st_bleed
    BMP     239, st_area_bmp, pal_st_area
    BMP     254, st_elite_bmp, pal_st_elite
    BMP     255, keystone_bmp, pal_keystone

    ; ---- 0.9 art (after the 0.8 icons, before the font; the atlas outside these 20 tiles is
    ;      untouched). Noise tiles take one draw per pixel; the bitmaps and bubbles take none. ----
    ; 192 water (alpha 180), 193 ice (alpha 200), 194 snow, 195 mud, 196 tall grass
    NFUNCA  192, 240, 15, 0, px_water, 0, 0, 180
    NFUNCA  193, 236, 15, 0, px_ice, 0, 0, 200
    NFUNC   194, 244, 11, 0, px_snow, 0, 0
    NFUNC   195, 224, 31, 0, px_mud, 0, 0
    BMP     196, tallgrass_bmp, pal_tallgrass
    ; 197, 198 cactus side, top; 199, 208 pine log side, top; 209 pine leaves
    NFUNC   197, 232, 23, 0, px_cactus_side, 0, 0
    NFUNC   198, 232, 23, 0, px_cactus_top, 0, 0
    NFUNC   199, 224, 31, 0, px_pine_bark, 0, 0
    NFUNC   208, 224, 31, 0, px_ring_top, C_RING_PINE, C_RING_PINE_DK
    NFUNC   209, 160, 95, 0, px_leaves_holes, C_LEAF_PINE, 0
    ; 210, 211 birch log side, birch leaves
    NFUNC   210, 232, 23, 0, px_birch, 0, 0
    NFUNC   211, 160, 95, 0, px_leaves_holes, C_LEAF_BIRCH, 0
    ; 212, 213 bed head top, foot top; 214, 215 bed head side, foot side
    NFUNC   212, 244, 11, 0, px_bed_top, 1, 0
    NFUNC   213, 244, 11, 0, px_bed_top, 0, 0
    NFUNC   214, 240, 15, 0, px_bed_side, 1, 0
    NFUNC   215, 240, 15, 0, px_bed_side, 0, 0
    ; 224, 225 bed and boat icons; 226, 227 breath bubble, popping bubble
    BMP     224, icon_bed_bmp, pal_icon_bed
    BMP     225, icon_boat_bmp, pal_icon_boat
    HUD     226, bubble_bmp, pal_bubble, pal_bubble, 0
    HUD     227, bubble_pop_bmp, pal_bubble, pal_bubble, 0

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
    mov     eax, r11d                   ; rim
    comiss  xmm0, [f0_72]
    ja      .done                       ; rim
    mov     eax, r10d                   ; meat
    comiss  xmm0, [f0_45]
    jbe     .done                       ; core
    cmp     r15d, 7
    jg      .done
    mov     eax, r9d                    ; fat highlight (left part of the mid ring)
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

; 16x16 bitmap pixel. In: r9 = bitmap (256 chars), r10 = palette (PAL records). A char
; that is not in the palette is transparent. Out: eax.
bmp_px:
    mov     eax, r14d
    shl     eax, 4
    add     eax, r15d
    movzx   ecx, byte [r9 + rax]
    mov     rdx, r10
.entry:
    movzx   esi, byte [rdx]
    test    esi, esi
    jz      .none
    cmp     esi, ecx
    je      .found
    add     rdx, 8
    jmp     .entry
.found:
    mov     eax, [rdx + 4]
    ret
.none:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
; Base-colour routines for the rng tiles. In: r15d = px, r14d = py, r9d = the pixel's
; rng draw, r10d (and r11d for the ores) = variant parameters. Out: esi = base colour
; (before the m multiplier). They clobber eax, ecx, edx only.
; ---------------------------------------------------------------------------

; ores: stone, ore colour r10d on 'o', highlight r11d on 'O' of ore_mask
px_ore:
    lea     rax, [ore_mask]
    mov     ecx, r14d
    shl     ecx, 4
    add     ecx, r15d
    movzx   ecx, byte [rax + rcx]
    mov     esi, RGB(128,128,128)
    cmp     ecx, 'o'
    cmove   esi, r10d
    cmp     ecx, 'O'
    cmove   esi, r11d
    ret

; furnace front (r10d = 1: lit)
px_furnace:
    mov     esi, RGB(80,80,80)
    IF_BORDER .done
    mov     esi, RGB(60,60,60)
    lea     eax, [r15 - 3]
    cmp     eax, 9
    ja      .open
    lea     eax, [r14 - 3]
    cmp     eax, 1
    jbe     .done                       ; top slot 3<=px<=12, 3<=py<=4
.open:
    mov     esi, RGB(120,120,120)
    lea     eax, [r15 - 4]
    cmp     eax, 7
    ja      .done
    lea     eax, [r14 - 8]
    cmp     eax, 4
    ja      .done                       ; opening 4<=px<=11, 8<=py<=12
    mov     esi, RGB(24,24,24)
    test    r10d, r10d
    jz      .done
    mov     esi, RGB(255,170,40)
    cmp     r14d, 11
    jae     .done
    mov     esi, RGB(250,110,20)
    cmp     r14d, 10
    je      .done
    mov     esi, RGB(190,50,10)
.done:
    ret

px_chest_top:
    mov     esi, RGB(92,64,32)
    IF_BORDER .done
    mov     esi, RGB(162,130,78)
.done:
    ret

px_chest_side:
    mov     esi, RGB(162,130,78)
    IF_BORDER .dark
    lea     eax, [r14 - 5]
    cmp     eax, 1
    ja      .latch
.dark:
    mov     esi, RGB(92,64,32)          ; border and the lid seam py 5..6
.latch:
    lea     eax, [r15 - 7]
    cmp     eax, 1
    ja      .done
    lea     eax, [r14 - 4]
    cmp     eax, 4
    ja      .done
    mov     esi, RGB(210,210,210)       ; latch 7..8 x 4..8
.done:
    ret

; gravel: colour by r & 3
px_gravel:
    mov     eax, r9d
    and     eax, 3
    lea     rcx, [gravel_cols]
    mov     esi, [rcx + rax * 4]
    ret

; TNT side: red bands py <= 3 / >= 12 (dark every px%4 == 3), white label with "TNT"
px_tnt_side:
    cmp     r14d, 3
    jbe     .band
    cmp     r14d, 12
    jae     .band
    mov     esi, RGB(230,230,230)
    lea     eax, [r14 - 6]
    cmp     eax, 4
    ja      .done
    shl     eax, 4
    add     eax, r15d
    lea     rcx, [tnt_mask]
    cmp     byte [rcx + rax], '#'
    jne     .done
    mov     esi, RGB(30,30,30)
    ret
.band:
    mov     esi, RGB(200,40,30)
    mov     eax, r15d
    and     eax, 3
    cmp     eax, 3
    jne     .done
    mov     esi, RGB(150,25,20)
.done:
    ret

px_tnt_top:
    mov     esi, RGB(200,40,30)
    lea     eax, [r15 - 6]
    cmp     eax, 3
    ja      .done
    lea     eax, [r14 - 6]
    cmp     eax, 3
    ja      .done
    mov     esi, RGB(230,230,230)
    lea     eax, [r15 - 7]
    cmp     eax, 1
    ja      .done
    lea     eax, [r14 - 7]
    cmp     eax, 1
    ja      .done
    mov     esi, RGB(40,40,40)
.done:
    ret

; creeper skin (r10d = 1: face)
px_creeper:
    mov     esi, RGB(80,180,70)
    mov     eax, r9d
    shr     eax, 8
    and     eax, 7
    jnz     .light
    mov     esi, RGB(50,120,45)
.light:
    mov     eax, r9d
    shr     eax, 11
    and     eax, 7
    cmp     eax, 1
    jne     .face
    mov     esi, RGB(140,220,120)
.face:
    test    r10d, r10d
    jz      .done
    lea     eax, [r14 - 4]
    cmp     eax, 2
    ja      .mouth
    lea     eax, [r15 - 3]
    cmp     eax, 2
    jbe     .black                      ; eyes 3..5, 10..12 x 4..6
    lea     eax, [r15 - 10]
    cmp     eax, 2
    jbe     .black
.mouth:
    lea     eax, [r15 - 6]
    cmp     eax, 3
    ja      .sides
    lea     eax, [r14 - 7]
    cmp     eax, 3
    jbe     .black                      ; mouth 6..9 x 7..10
.sides:
    lea     eax, [r14 - 10]
    cmp     eax, 2
    ja      .done
    lea     eax, [r15 - 5]
    cmp     eax, 5
    ja      .done
    cmp     eax, 1
    jbe     .black                      ; px 5, 6
    cmp     eax, 4
    jb      .done                       ; px 7, 8
.black:
    mov     esi, RGB(20,20,20)          ; px 9, 10 fall through
.done:
    ret

; skeleton bone (r10d = 1: face)
px_skeleton:
    mov     esi, RGB(200,200,200)
    test    r10d, r10d
    jz      .done
    lea     eax, [r14 - 5]
    cmp     eax, 2
    ja      .nose
    lea     eax, [r15 - 3]
    cmp     eax, 3
    jbe     .socket                     ; sockets 3..6, 9..12 x 5..7
    lea     eax, [r15 - 9]
    cmp     eax, 3
    ja      .nose
.socket:
    mov     esi, RGB(40,40,40)
    ret
.nose:
    cmp     r14d, 9
    jne     .teeth
    lea     eax, [r15 - 7]
    cmp     eax, 1
    ja      .teeth
    mov     esi, RGB(60,60,60)
    ret
.teeth:
    cmp     r14d, 12
    jne     .done
    lea     eax, [r15 - 3]
    cmp     eax, 9
    ja      .done
    test    r15d, 1
    jnz     .done
    mov     esi, RGB(60,60,60)
.done:
    ret

; spider body (r10d = 1: face, with the spider_pts specials)
px_spider:
    mov     esi, RGB(52,44,40)
    mov     eax, r9d
    shr     eax, 8
    and     eax, 7
    jnz     .face
    mov     esi, RGB(80,66,58)
.face:
    test    r10d, r10d
    jz      .done
    lea     rdx, [spider_pts]
.pt:
    movzx   eax, byte [rdx]
    cmp     eax, 0xFF
    je      .done
    cmp     eax, r15d
    jne     .next
    movzx   eax, byte [rdx + 1]
    cmp     eax, r14d
    jne     .next
    mov     esi, [rdx + 4]
    ret
.next:
    add     rdx, 8
    jmp     .pt
.done:
    ret

; chicken body (r10d = 1: face)
px_chicken:
    mov     esi, RGB(240,240,240)
    test    r10d, r10d
    jz      .done
    cmp     r14d, 5
    jne     .beak
    cmp     r15d, 3
    je      .eye
    cmp     r15d, 12
    jne     .beak
.eye:
    mov     esi, RGB(24,24,24)
    ret
.beak:
    lea     eax, [r15 - 6]
    cmp     eax, 3
    ja      .wattle
    lea     eax, [r14 - 7]
    cmp     eax, 2
    ja      .wattle
    mov     esi, RGB(240,180,40)        ; beak 6..9 x 7..9
    ret
.wattle:
    lea     eax, [r15 - 7]
    cmp     eax, 1
    ja      .done
    lea     eax, [r14 - 10]
    cmp     eax, 2
    ja      .done
    mov     esi, RGB(200,30,30)         ; wattle 7..8 x 10..12
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

armor_pal_full:
    PAL 'K', 30, 30, 30
    PAL 'm', 190, 190, 200
    PAL 'L', 255, 255, 255
    dq 0
armor_pal_empty:
    PAL 'K', 30, 30, 30
    PAL 'm', 60, 60, 60
    PAL 'L', 60, 60, 60
    dq 0
armor_bmp:
    db ".KK...KK."
    db "KmLK.KmmK"
    db "KmmmKmmmK"
    db ".KmmmmmK."
    db ".KmmmmmK."
    db ".KmmmmmK."
    db ".KKKKKKK."
    db "........."
    db "........."

; ---- 16x16 icon palettes ----
pal_coal:
    PAL 'K', 24, 24, 24
    PAL 'k', 48, 48, 52
    PAL 'g', 96, 96, 100
    dq 0
pal_ingot_iron:
    PAL 'L', 245, 245, 245
    PAL 'm', 206, 206, 206
    PAL 'D', 120, 120, 120
    dq 0
pal_ingot_gold:
    PAL 'L', 255, 250, 160
    PAL 'm', 250, 215, 60
    PAL 'D', 175, 125, 10
    dq 0
pal_diamond:
    PAL 'K', 18, 90, 90
    PAL 'm', 90, 230, 230
    PAL 'L', 220, 255, 255
    dq 0
pal_bow:
    PAL 'w', 150, 112, 50
    PAL 'W', 84, 62, 22
    PAL 's', 230, 230, 230
    dq 0
pal_arrow:
    PAL 'h', 137, 103, 39
    PAL 'G', 220, 220, 220
    PAL 'g', 120, 120, 120
    PAL 'f', 245, 245, 245
    dq 0
pal_string:
    PAL 's', 235, 235, 235
    dq 0
pal_fire:
    PAL 'Y', 255, 230, 90
    PAL 'O', 250, 140, 30
    PAL 'R', 200, 50, 20
    dq 0
pal_gunpowder:
    PAL 'k', 60, 60, 60
    PAL 'g', 110, 110, 110
    PAL 'l', 160, 160, 160
    dq 0
pal_flint:
    PAL 'K', 20, 20, 22
    PAL 'd', 60, 60, 66
    PAL 'l', 120, 120, 130
    dq 0
pal_flintsteel:
    PAL 'D', 110, 110, 110
    PAL 'L', 210, 210, 210
    PAL 'K', 20, 20, 22
    PAL 'd', 60, 60, 66
    PAL 'l', 120, 120, 130
    dq 0
pal_rotten:
    PAL 'd', 90, 50, 30
    PAL 'm', 150, 90, 55
    PAL 'g', 100, 130, 60
    dq 0
pal_feather:
    PAL 'W', 180, 180, 180
    PAL 'w', 245, 245, 245
    PAL 'q', 150, 150, 150
    dq 0
pal_drum_raw:
    PAL 'm', 236, 170, 160
    PAL 'w', 255, 215, 205
    PAL 'b', 240, 236, 224
    dq 0
pal_drum_cooked:
    PAL 'm', 176, 98, 40
    PAL 'w', 212, 140, 72
    PAL 'b', 240, 236, 224
    dq 0
pal_armor_iron:
    PAL 'D', 90, 90, 90
    PAL 'm', 200, 200, 205
    PAL 'L', 245, 245, 245
    dq 0
pal_armor_gold:
    PAL 'D', 160, 110, 10
    PAL 'm', 245, 205, 50
    PAL 'L', 255, 245, 150
    dq 0
pal_armor_diamond:
    PAL 'D', 20, 100, 100
    PAL 'm', 90, 225, 225
    PAL 'L', 215, 255, 255
    dq 0

gravel_cols:
    dd RGB(118,110,106), RGB(146,138,134), RGB(92,88,86), RGB(166,156,146)

; spider face specials: db px, py, 0, 0 ; dd colour; px == 0xFF ends the list
%macro SPT 3
    db %1, %2, 0, 0
    dd %3
%endmacro
spider_pts:
    SPT 4, 6, RGB(200,30,30)
    SPT 5, 6, RGB(200,30,30)
    SPT 10, 6, RGB(200,30,30)
    SPT 11, 6, RGB(200,30,30)
    SPT 6, 4, RGB(200,30,30)
    SPT 9, 4, RGB(200,30,30)
    SPT 3, 8, RGB(200,30,30)
    SPT 12, 8, RGB(200,30,30)
    SPT 6, 12, RGB(30,24,22)
    SPT 9, 12, RGB(30,24,22)
    SPT 6, 13, RGB(30,24,22)
    SPT 9, 13, RGB(30,24,22)
    SPT 0xFF, 0, 0

ore_mask:
    db "................"
    db "..oo........O..."
    db ".oOo.......ooo.."
    db "..o.........o..."
    db "......oo........"
    db ".....oOoo......."
    db "......oo........"
    db ".............o.."
    db "..o.........oOo."
    db ".ooo.........o.."
    db "..O............."
    db ".......oo......."
    db "......oOoo....o."
    db ".......o.....oo."
    db "................"
    db "................"

; TNT label rows (py 6..10)
tnt_mask:
    db "..###.#..#.###.."
    db "...#..##.#..#..."
    db "...#..#.##..#..."
    db "...#..#..#..#..."
    db "...#..#..#..#..."

coal_bmp:
    db "................"
    db "................"
    db "......KKKK......"
    db "....KKkkkkKK...."
    db "...KkkggkkkkK..."
    db "...KkgkkkkkkK..."
    db "..KkkkkkkgkkkK.."
    db "..KkkkkkkkkkkK.."
    db "..KkkgkkkkkkkK.."
    db "..KkkkkkkkkgkkK."
    db "...KkkkkkkkkK..."
    db "...KKkkgkkkKK..."
    db ".....KKkkKKK...."
    db ".......KKK......"
    db "................"
    db "................"
ingot_bmp:
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "......LLLLLLL..."
    db ".....LmmmmmmLD.."
    db "....LmmmmmmmLDD."
    db "...LLLLLLLLLDDD."
    db "...LmmmmmmmmLDD."
    db "...LmmmmmmmmLD.."
    db "...DDDDDDDDDDD.."
    db "................"
    db "................"
    db "................"
    db "................"
diamond_bmp:
    db "................"
    db "................"
    db ".....KKKKKK....."
    db "....KLLmmmmK...."
    db "...KLLmmmmmmK..."
    db "..KmmmmmmmmmmK.."
    db "..KKKKKKKKKKKK.."
    db "...KmmmmmmmmK..."
    db "....KmmmmmmK...."
    db ".....KmmmmK....."
    db "......KmmK......"
    db ".......KK......."
    db "................"
    db "................"
    db "................"
    db "................"
bow_bmp:
    db "................"
    db "............wW.."
    db "............wW.."
    db "...........swW.."
    db "..........swwW.."
    db ".........s.wWW.."
    db "........s..wW..."
    db ".......s..wwW..."
    db "......s..wwWW..."
    db ".....s..wwWW...."
    db "....s..wwWW....."
    db "...swwwwWW......"
    db ".wwwwWWWW......."
    db ".WWWWW.........."
    db "................"
    db "................"
arrow_bmp:
    db "................"
    db "............GGG."
    db "...........gGGG."
    db "..........hgGG.."
    db ".........h..g..."
    db "........h......."
    db ".......h........"
    db "......h........."
    db ".....h.........."
    db "....h..........."
    db "...h............"
    db ".ffh............"
    db ".fff............"
    db "..ff............"
    db "................"
    db "................"
fire0_bmp:
    db "................"
    db "......R........."
    db "......R....R...."
    db ".....RO....R...."
    db ".R...RO...RO.R.."
    db ".R..RROR..RO.RR."
    db ".RR.ROOR.RROORO."
    db ".RO.ROYOR.ROOOR."
    db ".ROR.ROYOR.ROYOR"
    db "RROORROYYORROYOR"
    db "ROOOROOYYOOROYOR"
    db "ROYOROYYYYOOOYOR"
    db "ROYYOOYYYYYOYYOR"
    db "ROYYYOYYYYYYYYOR"
    db ".ROYYYYYYYYYYOR."
    db "..RROOYYYYOORR.."
fire1_bmp:
    db "................"
    db ".........R......"
    db ".........R...R.."
    db "....R...RO...R.."
    db "....R...RO..RO.."
    db "...RO..RROR.RO.."
    db "..RRO..ROOR.ROR."
    db "..ROOR.ROYOR.ROR"
    db ".RROYOR.ROYOR.RR"
    db "RROOYOROROYYOORR"
    db "ROOYYOOOOOYYYOOR"
    db "ROYYYOOYYYYYYOOR"
    db "ROYYYYYYYYYYYYOR"
    db "ROYYYYYYYYYYYYOR"
    db ".ROYYYYYYYYYYOR."
    db "..RROOYYYYOORR.."
string_bmp:
    db "................"
    db "................"
    db "............ss.."
    db "...........s..s."
    db "..........s....."
    db ".........s......"
    db "........s......."
    db ".......s........"
    db "......s........."
    db ".....s.........."
    db "....s..........."
    db "...s............"
    db "..s............."
    db "..s............."
    db "...ss..........."
    db "................"
gunpowder_bmp:
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "........g......."
    db "......gkkgl....."
    db ".....kkgkklk...."
    db "....kglkkgkkk..."
    db "...kkkkglkkgkk.."
    db "..kglkkkkkklkkk."
    db "..kkkkglkkkkgkk."
    db "...kkkkkkgkkkk.."
    db "................"
    db "................"
flint_bmp:
    db "................"
    db "................"
    db "................"
    db ".......KK......."
    db "......KllK......"
    db ".....KlddK......"
    db "....KlddddK....."
    db "....KdddddK....."
    db "...KlddddddK...."
    db "...KddddddddK..."
    db "...KddddddddK..."
    db "....KdddddddK..."
    db ".....KddddKK...."
    db "......KKKK......"
    db "................"
    db "................"
flintsteel_bmp:
    db "................"
    db "................"
    db "...DDDDD........"
    db "..DLLLLLD......."
    db "..DL...LD......."
    db "..DL...LD......."
    db "..DLLLLLD......."
    db "...DDDLD........"
    db "......LD........"
    db "......LD..KK...."
    db ".......D.KllK..."
    db "........KlddK..."
    db ".......KddddK..."
    db ".......KdddK...."
    db "........KKK....."
    db "................"
rotten_bmp:
    db "................"
    db "................"
    db "................"
    db "......dd........"
    db "....ddmmd......."
    db "...dmmgmmd......"
    db "...dmmmmmmdd...."
    db "..dmgmmmmmmmd..."
    db "..dmmmmmgmmmmd.."
    db "...dmmmmmmmgmd.."
    db "....ddmmgmmmmd.."
    db "......ddmmmmd..."
    db "........dddd...."
    db "................"
    db "................"
    db "................"
feather_bmp:
    db "................"
    db "............WW.."
    db "..........WWww.."
    db ".........Wwwww.."
    db "........Wwwww..."
    db ".......Wwwwq...."
    db "......Wwwwq....."
    db ".....Wwwwq......"
    db "....Wwwwq......."
    db "....wwwq........"
    db "....wwq........."
    db "....wq.........."
    db "...q............"
    db "..q............."
    db "................"
    db "................"
drumstick_bmp:
    db "................"
    db "................"
    db "................"
    db "........mmmm...."
    db ".......mwmmmm..."
    db "......mwmmmmmm.."
    db "......mmmmmmmm.."
    db "......mmmmmmmm.."
    db ".......mmmmmmm.."
    db "......bmmmmmm..."
    db ".....bbbmmmm...."
    db "....bb.........."
    db "...bb..........."
    db "..bbb..........."
    db "..bb............"
    db "................"
helmet_bmp:
    db "................"
    db "................"
    db "................"
    db "....DDDDDDDD...."
    db "...DLLLmmmmmD..."
    db "..DLmmmmmmmmmD.."
    db "..DmmmmmmmmmmD.."
    db "..DmmDDDDDDmmD.."
    db "..DmmD....DmmD.."
    db "..DmmD....DmmD.."
    db "..DDDD....DDDD.."
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
chestplate_bmp:
    db "................"
    db "..DDDD....DDDD.."
    db "..DLmD....DmmD.."
    db "..DmmDDDDDDmmD.."
    db "..DmmmmmmmmmmD.."
    db "...DLmmmmmmmD..."
    db "....DmmmmmmD...."
    db "....DmmmmmmD...."
    db "....DmmmmmmD...."
    db "....DmmmmmmD...."
    db "....DmmmmmmD...."
    db "....DmmmmmmD...."
    db "....DDDDDDDD...."
    db "................"
    db "................"
    db "................"
leggings_bmp:
    db "................"
    db "................"
    db "....DDDDDDDD...."
    db "....DLmmmmmD...."
    db "....DmmmmmmD...."
    db "....DmmDDmmD...."
    db "....DmmDDmmD...."
    db "....DmmDDmmD...."
    db "....DmmDDmmD...."
    db "....DmmDDmmD...."
    db "....DmmDDmmD...."
    db "....DDDDDDDD...."
    db "................"
    db "................"
    db "................"
    db "................"
boots_bmp:
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "...DDDD..DDDD..."
    db "...DLmD..DLmD..."
    db "...DmmD..DmmD..."
    db "...DmmD..DmmD..."
    db "..DDmmD..DmmDD.."
    db ".DLmmmD..DmmmmD."
    db ".DDDDDD..DDDDDD."
    db "................"
    db "................"
    db "................"

; ---- firearm icons (tiles 119..128) ----
pal_pistol:
    PAL 'K', 22, 22, 24
    PAL 'S', 205, 205, 212
    PAL 's', 150, 150, 160
    PAL 'd', 78, 78, 86
    PAL 'g', 62, 44, 34
    dq 0
pal_musket:
    PAL 'K', 36, 24, 14
    PAL 'I', 205, 205, 212
    PAL 'i', 140, 140, 150
    PAL 'b', 200, 160, 50
    PAL 'B', 140, 105, 25
    PAL 'w', 170, 110, 50
    PAL 'W', 110, 68, 28
    dq 0
pal_shotgun:
    PAL 'K', 28, 24, 22
    PAL 'I', 205, 205, 212
    PAL 'i', 130, 130, 140
    PAL 'w', 176, 116, 54
    PAL 'W', 112, 70, 30
    dq 0
pal_kalash:
    PAL 'K', 20, 20, 22
    PAL 'B', 105, 105, 116
    PAL 'b', 54, 54, 60
    PAL 'o', 210, 124, 46
    PAL 'O', 140, 78, 28
    PAL 'w', 170, 112, 52
    PAL 'W', 110, 70, 30
    dq 0
pal_launcher:
    PAL 'K', 20, 30, 20
    PAL 'G', 124, 174, 96
    PAL 'g', 76, 120, 62
    PAL 'd', 44, 78, 38
    PAL 'k', 66, 50, 38
    dq 0
pal_brass:
    PAL 'K', 54, 36, 10
    PAL 'c', 196, 100, 52
    PAL 'C', 232, 150, 90
    PAL 'B', 255, 226, 130
    PAL 'b', 224, 176, 62
    PAL 'D', 150, 108, 28
    dq 0
pal_ball:
    PAL 'K', 28, 28, 34
    PAL 'L', 228, 228, 236
    PAL 'm', 150, 150, 160
    PAL 'D', 84, 84, 94
    dq 0
pal_shell:
    PAL 'K', 50, 12, 10
    PAL 'R', 245, 96, 76
    PAL 'r', 205, 38, 32
    PAL 'd', 134, 22, 22
    PAL 'B', 255, 226, 130
    PAL 'b', 224, 176, 62
    PAL 'D', 150, 108, 28
    dq 0
pal_rocket:
    PAL 'K', 30, 24, 24
    PAL 'R', 250, 110, 86
    PAL 'r', 212, 40, 32
    PAL 'd', 138, 24, 22
    PAL 'S', 222, 222, 230
    PAL 's', 160, 160, 170
    PAL 'e', 104, 104, 114
    dq 0

pistol_bmp:
    db "................"
    db "................"
    db "................"
    db ".KKKKKKKKKKKKKK."
    db ".KSSSSSSSSSSSsK."
    db ".KsssssssssssdK."
    db ".KsssdsssssssdK."
    db ".KKKKKKKKKKKKKK."
    db "..KgggKKKKK....."
    db "..KgggK...K....."
    db "..KgggKKKKK....."
    db "..KgggK........."
    db "..KgggK........."
    db "..KKKKK........."
    db "................"
    db "................"
musket_bmp:
    db "............KKKK"
    db "............KIiK"
    db "...........KIiK."
    db "..........KIiK.."
    db ".........KIiK..."
    db "........KbBK...."
    db ".......KIiK....."
    db "......KIiK......"
    db ".....KwwWK......"
    db "....KwwwWK......"
    db "...KwwwWK......."
    db "..KwwwWK........"
    db ".KwwwWK........."
    db "KwwwWK.........."
    db "KKKKK..........."
    db "................"
shotgun_bmp:
    db ".........KKKKKKK"
    db ".........KIiKIiK"
    db "........KIiKIiK."
    db ".......KIiKIiK.."
    db "......KIiKIiK..."
    db ".....KIiKIiK...."
    db "...KwwwwwwwK...."
    db "..KWWWWWWWK....."
    db "..KIiKIiK......."
    db ".KwwwwwK........"
    db "KwwWwwK........."
    db "KwwWwK.........."
    db "KKKKK..........."
    db "................"
    db "................"
    db "................"
kalash_bmp:
    db "............KKKK"
    db "............KBbK"
    db "...........KBbK."
    db "..........KBbK.."
    db "........KwwWK..."
    db ".......KwwWK...."
    db "......KBbbK....."
    db ".....KBbbbK....."
    db "....KBbbbbK....."
    db "...KwwwwKKoOK..."
    db "..KwWwwK.KoOK..."
    db ".KwWwwK...KoOK.."
    db "KwWwwK.....KoOK."
    db "KKKKKK.....KoOK."
    db "...........KKKK."
    db "................"
launcher_bmp:
    db "..........KKKKKK"
    db ".........KGGggdK"
    db "........KGGggdK."
    db ".......KGGggdK.."
    db "......KGGggdK..."
    db ".....KGGggdK...."
    db "....KGGggdK....."
    db "...KGGggdK......"
    db "..KGGggdK......."
    db ".KGGggdKkkK....."
    db ".KKKKKKKkkK....."
    db ".......KkkK....."
    db ".......KkkK....."
    db ".......KKKK....."
    db "................"
    db "................"
round_pistol_bmp:
    db "................"
    db "................"
    db "................"
    db "......KKKK......"
    db ".....KcCccK....."
    db ".....KcCccK....."
    db ".....KBBbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db "....KBBbbbDK...."
    db "....KKKKKKKK...."
    db "................"
    db "................"
    db "................"
musket_ball_bmp:
    db "................"
    db "................"
    db "................"
    db "................"
    db ".....KKKKKK....."
    db "...KKLLmmmmKK..."
    db "...KLLLmmmmDK..."
    db "...KLLmmmmmDK..."
    db "...KLmmmmmmDK..."
    db "...KmmmmmmDDK..."
    db "...KmmmmmDDDK..."
    db "...KKmmmDDDKK..."
    db ".....KKKKKK....."
    db "................"
    db "................"
    db "................"
shell_bmp:
    db "................"
    db "................"
    db "....KKKKKKKK...."
    db "....KRrrrrdK...."
    db "....KRrrrrdK...."
    db "....KRrrrrdK...."
    db "....KRrrrrdK...."
    db "....KRrrrrdK...."
    db "....KRrrrrdK...."
    db "....KBbbbbDK...."
    db "....KBbbbbDK...."
    db "....KBbbbbDK...."
    db "....KKKKKKKK...."
    db "................"
    db "................"
    db "................"
round_rifle_bmp:
    db "................"
    db ".......KK......."
    db "......KccK......"
    db "......KcCK......"
    db "......KccK......"
    db "......KccK......"
    db "......KccK......"
    db ".....KBBbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db ".....KBbbDK....."
    db "....KBBbbbDK...."
    db "....KKKKKKKK...."
    db "................"
rocket_bmp:
    db "................"
    db ".......KK......."
    db "......KRrK......"
    db ".....KRRrdK....."
    db ".....KRrrdK....."
    db ".....KRrrdK....."
    db ".....KKKKKK....."
    db ".....KSssdK....."
    db ".....KSssdK....."
    db ".....KSssdK....."
    db ".....KSssdK....."
    db "...KKKSssdKKK..."
    db "..KssKSssdKssK.."
    db "..KKKKKKKKKKKK.."
    db "................"
    db "................"

; ---- RPG art (tiles 59, 60 and 129..179): 16x16 bitmaps, palettes as for the icons above ----
brick_bmp:
    db "hhhhhhhDhhhhhhhD"
    db "caaaabaDacbaaacD"
    db "baaabcbDcaaacaaD"
    db "ccaabaaDaaaacbbD"
    db "acaacaaDaacbaccD"
    db "baababcDbaaacaaD"
    db "lllllllDlllllllD"
    db "DDDDDDDDDDDDDDDD"
    db "hhhDhhhhhhhDhhhh"
    db "babDbbbbaaaDcaca"
    db "aaaDbaabacbDcabc"
    db "aaaDaaaaaabDacba"
    db "bcbDacbabaaDcaab"
    db "cacDcaaaabaDbaca"
    db "lllDlllllllDllll"
    db "DDDDDDDDDDDDDDDD"
pal_brick:
    PAL 'D', 66, 66, 70
    PAL 'a', 132, 132, 134
    PAL 'b', 120, 120, 124
    PAL 'c', 144, 144, 146
    PAL 'h', 160, 160, 162
    PAL 'l', 108, 108, 112
    dq 0
mossy_bmp:
    db "hGhhhhhDhhhGhhgD"
    db "babcGaaDaagbGbaD"
    db "cccabgaDbababcaD"
    db "caababbDccaaaaaD"
    db "baGaaacDcabacaaD"
    db "babaaaaDabbccaaD"
    db "glgglllDlllllllM"
    db "DMMMDDDDDDDDDDDM"
    db "gGgDhhhhhhhDhhhh"
    db "bgaMbgaacbaDacca"
    db "bbcDGaacaabDacac"
    db "bbGMaabbbaaDbaaa"
    db "baaDabaaaabDaaaa"
    db "GgaDbbbbaaaDaaag"
    db "lllDlllllllDllll"
    db "MMDDDDDDDDDDMMDg"
pal_mossy:
    PAL 'D', 66, 66, 70
    PAL 'G', 66, 108, 42
    PAL 'M', 44, 66, 30
    PAL 'a', 132, 132, 134
    PAL 'b', 120, 120, 124
    PAL 'c', 144, 144, 146
    PAL 'g', 94, 136, 56
    PAL 'h', 160, 160, 162
    PAL 'l', 108, 108, 112
    dq 0
staff_bmp:
    db "................"
    db "...........YYY.."
    db "..........YRRRY."
    db "..........YRrRY."
    db "..........YRRRY."
    db "...........YDY.."
    db "..........wW...."
    db ".........wW....."
    db "........wW......"
    db ".......YD......."
    db "......wW........"
    db ".....wW........."
    db "....wW.........."
    db "...wW..........."
    db "..wW............"
    db ".wW............."
pal_staff:
    PAL 'D', 176, 124, 10
    PAL 'R', 230, 40, 52
    PAL 'W', 96, 64, 28
    PAL 'Y', 252, 216, 64
    PAL 'r', 255, 160, 160
    PAL 'w', 170, 122, 66
    dq 0
archstaff_bmp:
    db ".........L......"
    db "...........TTT.L"
    db "..........TLLCT."
    db "..........TLCCT."
    db "..........TCCCB."
    db "..........YTTB.."
    db "........YYYY...Y"
    db "........YYW....."
    db "........wW......"
    db ".......wW......."
    db "......wW........"
    db ".....wW........."
    db "....wW.........."
    db "...wW..........."
    db "..wW............"
    db ".wW............."
pal_archstaff:
    PAL 'B', 48, 170, 200
    PAL 'C', 96, 232, 238
    PAL 'L', 236, 255, 255
    PAL 'T', 20, 112, 124
    PAL 'W', 44, 30, 64
    PAL 'Y', 252, 216, 64
    PAL 'w', 86, 60, 112
    dq 0
dagger_bmp:
    db "................"
    db "................"
    db ".............L.."
    db "............L..."
    db "...........L...."
    db "..........Lm...."
    db ".........Lm....."
    db "........Lm......"
    db "...kG..Lm......."
    db "....gG.........."
    db ".....gG........."
    db "....HhgG........"
    db "...Hh..gG......."
    db "..Hh....k......."
    db ".pp............."
    db "ppp............."
pal_dagger_iron:
    PAL 'G', 226, 190, 60
    PAL 'H', 86, 52, 26
    PAL 'L', 248, 248, 252
    PAL 'g', 250, 222, 90
    PAL 'h', 142, 88, 44
    PAL 'k', 150, 112, 20
    PAL 'm', 168, 174, 188
    PAL 'p', 212, 182, 70
    dq 0
pal_dagger_diamond:
    PAL 'G', 226, 190, 60
    PAL 'H', 86, 52, 26
    PAL 'L', 226, 255, 255
    PAL 'g', 250, 222, 90
    PAL 'h', 142, 88, 44
    PAL 'k', 150, 112, 20
    PAL 'm', 64, 200, 212
    PAL 'p', 212, 182, 70
    dq 0
fang_bmp:
    db "................"
    db "...............V"
    db ".............VV."
    db "...........VV.KK"
    db ".........VV.KB.."
    db "........V.KB...."
    db ".......V.B......"
    db ".......VB......."
    db "......VBK......."
    db "...gg.VKK......."
    db "....gg.K........"
    db ".....eg........."
    db "......gg........"
    db "....hH.g........"
    db "..phH..........."
    db ".pp............."
pal_fang:
    PAL 'B', 72, 38, 112
    PAL 'H', 34, 22, 48
    PAL 'K', 26, 12, 40
    PAL 'V', 204, 124, 255
    PAL 'e', 240, 70, 226
    PAL 'g', 84, 60, 120
    PAL 'h', 60, 40, 76
    PAL 'p', 134, 80, 196
    dq 0
kings_bmp:
    db "..............LL"
    db ".............LL."
    db "............LWm."
    db "...........LW..."
    db ".GG.......LWm..."
    db "..G......LWm...."
    db "...G....LWm....."
    db "....Y...Wm......"
    db ".....Y.Wm......."
    db "......R........."
    db "....Hh.Y........"
    db "...Hh...Y......."
    db "..Hh.....G......"
    db ".YG......GG....."
    db "GGG............."
    db "................"
pal_kings:
    PAL 'G', 232, 182, 32
    PAL 'H', 72, 22, 26
    PAL 'L', 255, 255, 240
    PAL 'R', 224, 32, 52
    PAL 'W', 255, 246, 206
    PAL 'Y', 255, 238, 120
    PAL 'h', 124, 44, 44
    PAL 'm', 230, 196, 108
    dq 0
celestial_bmp:
    db "................"
    db "..............wc"
    db "............csw."
    db "............sw.."
    db "...........scw.."
    db "..........sccw.."
    db ".........s.cww.."
    db "........s.ccw..."
    db ".......s..cww..."
    db "......s..cww...."
    db ".....s.ccwgg...."
    db "....scccwwgg...."
    db "..csccwww...c..."
    db "..swwww........."
    db ".ww...........c."
    db ".c.............."
pal_celestial:
    PAL 'c', 100, 222, 250
    PAL 'g', 255, 226, 96
    PAL 's', 200, 244, 255
    PAL 'w', 252, 254, 255
    dq 0
potion_bmp:
    db "................"
    db "......KkkK......"
    db "......kkkk......"
    db "......oooo......"
    db "......owoo......"
    db "......owoo......"
    db ".....oooooo....."
    db "....oooooooo...."
    db "...oLLLLLLLLo..."
    db "...olwwlllllo..."
    db "...olwllllllo..."
    db "...ollllllllo..."
    db "....oddddddo...."
    db "....ooddddoo...."
    db ".....oooooo....."
    db "................"
pal_potion_red:
    PAL 'K', 100, 64, 30
    PAL 'L', 255, 120, 120
    PAL 'd', 150, 22, 38
    PAL 'k', 156, 104, 54
    PAL 'l', 232, 52, 62
    PAL 'o', 48, 40, 56
    PAL 'w', 255, 255, 255
    dq 0
pal_potion_blue:
    PAL 'K', 100, 64, 30
    PAL 'L', 140, 176, 255
    PAL 'd', 30, 52, 172
    PAL 'k', 156, 104, 54
    PAL 'l', 64, 104, 255
    PAL 'o', 48, 40, 56
    PAL 'w', 255, 255, 255
    dq 0
coin_bmp:
    db "................"
    db "................"
    db ".....RRRRRR....."
    db "...RLLYYYYYRR..."
    db "...LYYDDDDYYS..."
    db "..RLYDYDDYDYYS.."
    db "..LYDYYDDYYDYS.."
    db "..LYDYYDDYYDYS.."
    db "..RYDYYDDYYDYS.."
    db "..RYDYYDDYYDYS.."
    db "..RYYDYDDYDYYS.."
    db "...RYYDDDDYYS..."
    db "...RSYYYYYYSS..."
    db ".....SSSSSS....."
    db "................"
    db "................"
pal_coin:
    PAL 'D', 212, 156, 18
    PAL 'L', 255, 246, 170
    PAL 'R', 204, 144, 12
    PAL 'S', 150, 98, 6
    PAL 'Y', 252, 214, 60
    dq 0
charge_bmp:
    db "................"
    db ".RR...YO........"
    db "..RR...YO......."
    db "...RR...YO......"
    db "....RR...YO....."
    db "SS...RR...YO...."
    db "......RR...YO..."
    db ".......RRR..YYO."
    db "SS.....RRR..YYO."
    db "......RR...YO..."
    db ".....RR...YO...."
    db "SS..RR...YO....."
    db "...RR...YO......"
    db "..RR...YO......."
    db ".RR...YO........"
    db "................"
pal_charge:
    PAL 'O', 255, 146, 34
    PAL 'R', 214, 44, 28
    PAL 'S', 200, 200, 214
    PAL 'Y', 255, 226, 90
    dq 0
warcry_bmp:
    db "................"
    db "................"
    db "................"
    db ".......DD...O.R."
    db ".....LLDD....O.."
    db "....LYYDD..O.O.R"
    db ".YYLYYYDD.....O."
    db ".YLYYYYDD...O.O."
    db ".YYYYYYDD...O.O."
    db "..DYYYYDD.....O."
    db "...DYYYDD..O.O.."
    db "....DYYDD....O.R"
    db ".....DDDD...O..."
    db "..............R."
    db "................"
    db "................"
pal_warcry:
    PAL 'D', 168, 112, 14
    PAL 'L', 255, 248, 190
    PAL 'O', 255, 150, 40
    PAL 'R', 230, 60, 30
    PAL 'Y', 252, 212, 60
    dq 0
whirl_bmp:
    db ".......S........"
    db "...LSSSSSSS....."
    db "..LLLWWWWWSS...."
    db ".LSSW.....WSS..."
    db ".SSW.......WSS.."
    db ".SW..........S.."
    db ".SW............."
    db "SSW....YY...WSS."
    db ".SW....YY...WS.."
    db ".S..........WS.."
    db ".SS........WSS.."
    db "..SSW.....WSS.L."
    db "...SSWWWWWLLLLL."
    db "....SSSSSSSLLL.."
    db ".......S....L..."
    db "................"
pal_whirl:
    PAL 'L', 255, 255, 255
    PAL 'S', 196, 206, 226
    PAL 'W', 120, 140, 180
    PAL 'Y', 255, 226, 90
    dq 0
fireball_bmp:
    db "..........r....."
    db ".......rrrOrrr.."
    db "......rrOOOOOrr."
    db "......rOOYYYOOr."
    db "......rOYLLYYOr."
    db ".....rOOYLLYYOOr"
    db "......rOYYYYYOr."
    db ".....rrOOYYYOOr."
    db "...rrOrrOOOOOrr."
    db "..rrOOOrrrOrrr.."
    db "..rOOOOrr.r....."
    db ".rrOOOOr........"
    db ".rOOOOr........."
    db ".rOOOr.........."
    db "rO.............."
    db "................"
pal_fireball:
    PAL 'L', 255, 250, 210
    PAL 'O', 255, 138, 28
    PAL 'Y', 255, 214, 70
    PAL 'r', 204, 40, 20
    dq 0
blink_bmp:
    db "................"
    db "........PPPPC..."
    db ".......CP..P...."
    db "..C....PPCCPP..."
    db ".......P.CC.P..."
    db ".......PCCCCP..."
    db ".......PC..CP..."
    db "..pppppPC..CPL.."
    db "ppppppLLLL.CP.LL"
    db "..pppppPC..CPL.."
    db ".......PCCCCP..."
    db ".......P.CC.P..."
    db ".......PPCCPP..."
    db "....C...P..P...."
    db "......C.PPPP...."
    db "............C..."
pal_blink:
    PAL 'C', 110, 232, 255
    PAL 'L', 250, 250, 255
    PAL 'P', 176, 100, 255
    PAL 'p', 112, 60, 196
    dq 0
meteor_bmp:
    db "................"
    db "................"
    db ".....O.........."
    db "....O..........."
    db ".RRO............"
    db ".RR.......OO...."
    db "........OOO....."
    db ".......OOO......"
    db "....RRROOO......"
    db "...RYYYROL......"
    db "...RYYYR........"
    db "...RYYYR......O."
    db "...RRYRR....OOL."
    db "....RRR...RRR..."
    db "..........RRR..."
    db "................"
pal_meteor:
    PAL 'L', 255, 252, 220
    PAL 'O', 255, 142, 30
    PAL 'R', 214, 44, 24
    PAL 'Y', 255, 222, 80
    dq 0
volley_bmp:
    db "................"
    db "................"
    db ".......G........"
    db ".......GW......."
    db "......GGG......."
    db "GG....GGG....GG."
    db "GGG.....W...GGG."
    db ".GW.....W....G.."
    db "...W....W...W..."
    db "....W...W..W...."
    db "....W...W..W...."
    db ".....W..W.W....."
    db "......W.WW......"
    db "......W.WW......"
    db "......FFF......."
    db "......F..F......"
pal_volley:
    PAL 'F', 240, 240, 240
    PAL 'G', 210, 216, 228
    PAL 'W', 170, 120, 70
    dq 0
explarrow_bmp:
    db "................"
    db "..........OO...."
    db ".......OOOOOOOO."
    db "........OYYYYO.."
    db "........OOLLOO.."
    db "........OOOOOO.."
    db ".......O.WOO..O."
    db "........W.OO...."
    db ".......W........"
    db "......W........."
    db ".....W.........."
    db "....W..........."
    db "...W............"
    db ".FF............."
    db "FF.............."
    db ".FF............."
pal_explarrow:
    PAL 'F', 240, 240, 240
    PAL 'L', 255, 252, 220
    PAL 'O', 240, 90, 24
    PAL 'W', 170, 120, 70
    PAL 'Y', 255, 214, 70
    dq 0
arrowrain_bmp:
    db ".......NN......."
    db "..NNN.NNNN.NNN.."
    db "..NNNNNNNNNNNN.."
    db "..NNNNNNNNNNNN.."
    db "..nnnnnnnnnnFFF."
    db "..FFF........W.."
    db "...W...FFF...W.."
    db "...W....W....W.."
    db "...W....W....W.."
    db "...W....W....W.."
    db "...W....W..GGGG."
    db ".GGGG...W...GG.."
    db "..GG..GGGG..GG.."
    db "..GG...GG....W.."
    db "...W...GG......."
    db "........W......."
pal_arrowrain:
    PAL 'F', 250, 250, 250
    PAL 'G', 226, 230, 240
    PAL 'N', 184, 190, 208
    PAL 'W', 170, 120, 70
    PAL 'n', 120, 126, 150
    dq 0
shadowstep_bmp:
    db "................"
    db "..........VVV..."
    db "...p..p.pVKKKV.."
    db "..p.pp.pVKKKKKV."
    db ".p.p.pp.pKKKKKV."
    db "..p.pp.pVKEKEKV."
    db "...p..p.pVKKKV.."
    db "..p.pp.pVKKKKKV."
    db ".p.p.pp.pKKKKKV."
    db "p.p.ppppKKKKKKKV"
    db ".p.ppppVKKKKKKKV"
    db "p.p.ppppKKKKKKKV"
    db ".p.ppppVKKKKKKKV"
    db "p.p.ppppKKKKKKKV"
    db ".p.ppppVKKKKKKKV"
    db "........VVVVVVV."
pal_shadowstep:
    PAL 'E', 240, 80, 255
    PAL 'K', 30, 18, 50
    PAL 'V', 150, 90, 230
    PAL 'p', 120, 64, 200
    dq 0
smoke_bmp:
    db ".........O.O...."
    db "..........Y....."
    db ".........f.O...."
    db ".........f......"
    db "......kkf......."
    db "......kk..NNN..."
    db "....KKKKK.NNNN.."
    db "...KKgKKKKNNNnn."
    db "..KKggKKKKK..nn."
    db "..KKgKKKKKKNNNn."
    db "..KKKKKKKKNNNN.."
    db "..KKKKKKKKNNNN.."
    db "..KKKKKKKKK.Nnnn"
    db "...KKKKKKK...nnn"
    db ".....KKK........"
    db "................"
pal_smoke:
    PAL 'K', 40, 40, 52
    PAL 'N', 206, 210, 222
    PAL 'O', 255, 140, 30
    PAL 'Y', 255, 226, 90
    PAL 'f', 210, 170, 110
    PAL 'g', 120, 120, 140
    PAL 'k', 110, 84, 64
    PAL 'n', 144, 150, 168
    dq 0
bladedance_bmp:
    db ".........PP....."
    db "..........PP...."
    db "............PP.."
    db "..mL........LP.."
    db "...mL......LmPP."
    db "....mL....Lm..P."
    db ".....mL..Lm....."
    db "......mYYm......"
    db ".......YY......."
    db "P.....LmmL......"
    db "PP...Lm..mL...G."
    db ".PG.Lm....mL.G.."
    db ".PPGm......mG..."
    db "..hPP......G.h.."
    db ".h..PP........h."
    db "................"
pal_bladedance:
    PAL 'G', 236, 196, 64
    PAL 'L', 250, 250, 255
    PAL 'P', 190, 110, 255
    PAL 'Y', 255, 226, 90
    PAL 'h', 130, 84, 44
    PAL 'm', 170, 176, 192
    dq 0
emb_warrior_bmp:
    db ".K............K."
    db "KLK..........KLK"
    db ".KLK........KLK."
    db ".KmLK......KLmK."
    db "..KmLK....KLmK.."
    db "...KmLK..KLmK..."
    db "....KmLKKLmK...."
    db "...KKKmLLmKKK..."
    db "..KGGKKLLKKGGK.."
    db "...KGK.KK.KGK..."
    db "....KGK..KGK...."
    db "....KhGKKGhK...."
    db "..KKhKKGGKKhKK.."
    db ".KYhK..KK..KhYK."
    db ".KYK........KYK."
    db "KYK..........KYK"
pal_emb_warrior:
    PAL 'G', 232, 182, 32
    PAL 'K', 40, 34, 40
    PAL 'L', 250, 250, 255
    PAL 'Y', 255, 230, 100
    PAL 'h', 142, 88, 44
    PAL 'm', 170, 176, 192
    dq 0
emb_mage_bmp:
    db ".........KrK..K."
    db "........KrrrKKYK"
    db "........KrOrK.K."
    db ".....K.KrrOOrK.."
    db "....KYKrrOOOrrK."
    db ".....KKrOOYOOrK."
    db "..K...KrOYYYOrK."
    db ".KYK..KrOYLOOrK."
    db "..K....KrOLOrK.."
    db ".......KYrrrK..."
    db "......KwWKKK...."
    db ".....KwWK......."
    db "....KwWK........"
    db "...KwWK........."
    db "..KwWK.........."
    db ".KwWK..........."
pal_emb_mage:
    PAL 'K', 44, 24, 20
    PAL 'L', 255, 250, 210
    PAL 'O', 255, 140, 30
    PAL 'W', 98, 66, 30
    PAL 'Y', 255, 226, 90
    PAL 'r', 210, 44, 22
    PAL 'w', 172, 124, 68
    dq 0
emb_archer_bmp:
    db "........KK......"
    db "......KKwsK....."
    db ".....KwwsWK....."
    db ".....KwWsK......"
    db "....KwwsK......."
    db "....KwWsK...K..."
    db "...KFwsK...KGKK."
    db "..KFwFsKKKKKGGGK"
    db "...KFFaaaaaaGGGK"
    db "..KFwFsKKKKKGKK."
    db "...KFwsK....K..."
    db "....KwwsK......."
    db ".....KwsWK......"
    db ".....KwwsWK....."
    db "......KKsK......"
    db "........KsK....."
pal_emb_archer:
    PAL 'F', 240, 240, 244
    PAL 'G', 210, 216, 228
    PAL 'K', 36, 28, 22
    PAL 'W', 104, 70, 32
    PAL 'a', 196, 150, 90
    PAL 's', 230, 230, 236
    PAL 'w', 178, 126, 66
    dq 0
emb_rogue_bmp:
    db "................"
    db "....KKKKK......."
    db "...KHHHHHK...LL."
    db "..KHHHHHHHK..Lm."
    db ".KHHHHHHHHHK.Lm."
    db "KHHHHFFFHHHHKLm."
    db "KHHHFFFFFHHHKLm."
    db "KHHFFFFFFFHHKLm."
    db "KHHFFEFFEFHHHLm."
    db "KHHFFFFFFFHHHLm."
    db "KHhHFFFFFFHhHLm."
    db "KHHHFFFFFFHHGGGG"
    db "KHHHHHHHHHHHHkk."
    db ".hHHHHHHHHHHhkk."
    db "KHHHHHHHHHHHHGG."
    db ".KKKKKKKKKKKK..."
pal_emb_rogue:
    PAL 'E', 150, 255, 120
    PAL 'F', 14, 8, 20
    PAL 'G', 232, 182, 32
    PAL 'H', 72, 48, 110
    PAL 'K', 30, 18, 46
    PAL 'L', 250, 250, 255
    PAL 'h', 104, 74, 150
    PAL 'k', 110, 70, 40
    PAL 'm', 170, 176, 192
    dq 0
st_health_bmp:
    db "................"
    db "....KKK..KKK...."
    db "...KRRRKKRRRK..."
    db "..KRwRRRRRRRRK.."
    db ".KRwRRRRRRRRRRK."
    db ".KRwRRRRRRRRRRK."
    db ".KRRRRRRRRRRRRK."
    db ".KRRRRRRRRRRRRK."
    db "..KRRRRRRRRRRK.."
    db "...KRRRRRRRRK..."
    db "....KRRRRRRK...."
    db ".....KRRRRK....."
    db ".....KRRRdK....."
    db "......KRdK......"
    db ".......KK......."
    db "................"
pal_st_health:
    PAL 'K', 60, 14, 22
    PAL 'R', 226, 40, 52
    PAL 'd', 160, 24, 40
    PAL 'w', 255, 170, 170
    dq 0
st_melee_bmp:
    db "..............KK"
    db ".............KLL"
    db ".............KLK"
    db "............KLK."
    db "...........KLmK."
    db "..........KLmK.."
    db "..KK.....KLmK..."
    db ".KGGK...KLmK...."
    db "..KGK..KLmK....."
    db "...KGKKLmK......"
    db "...KhGLmK......."
    db "..KhKLGK........"
    db ".KhK.KKGK......."
    db "KhK....K........"
    db "ppK............."
    db "pK.............."
pal_st_melee:
    PAL 'G', 232, 182, 32
    PAL 'K', 36, 36, 44
    PAL 'L', 250, 250, 255
    PAL 'h', 150, 60, 50
    PAL 'm', 170, 176, 192
    PAL 'p', 232, 182, 32
    dq 0
st_ranged_bmp:
    db "............KKK."
    db "...........KGGGK"
    db "..........KGGGWK"
    db "...........KGGK."
    db "...........KWGK."
    db "..........KWKK.."
    db ".........KWK...."
    db "........KWK....."
    db ".......KWK......"
    db "....K.KWK......."
    db "...KFKWK........"
    db "....KFFK........"
    db ".....KK........."
    db "................"
    db "................"
    db "................"
pal_st_ranged:
    PAL 'F', 250, 250, 250
    PAL 'G', 226, 230, 240
    PAL 'K', 40, 34, 30
    PAL 'W', 176, 124, 72
    dq 0
st_spell_bmp:
    db "................"
    db ".......KK......."
    db "......KPPK......"
    db "......KPPK......"
    db "......KPPK......"
    db ".KKKKKPQQPKKKKK."
    db "KPPPPPPQLPPPPPPK"
    db ".KPPQQQLLQQQPPK."
    db "..KKPQQQQQQPKK.."
    db "....KPQQQQPK...."
    db "....KPQQQQPK...."
    db "...KPQQPPQQPK..."
    db "...KPPPKKPPPK..."
    db "...KPKK..KKPK..."
    db "....K......K...."
    db "................"
pal_st_spell:
    PAL 'K', 40, 20, 72
    PAL 'L', 255, 250, 255
    PAL 'P', 150, 84, 240
    PAL 'Q', 208, 160, 255
    dq 0
st_critchance_bmp:
    db "......KRRK......"
    db "......KRRK......"
    db "....KKRRRKK....."
    db "...KRRRRRRRK...."
    db "..KRRKKRRKRRK..."
    db "..KRK..KK.KRK..."
    db "KKRRK.....KRRKKK"
    db "RRRRRK.YY.KRRRRR"
    db "RRRRRK.YY.KRRRRR"
    db "KKKRK.....KRKKKK"
    db "..KRRKKKKKRRK..."
    db "...KRRRRRRRK...."
    db "....KKRRRKK....."
    db "......KRRK......"
    db "......KRRK......"
    db "......KRRK......"
pal_st_critchance:
    PAL 'K', 50, 14, 12
    PAL 'R', 230, 56, 40
    PAL 'Y', 255, 222, 80
    dq 0
st_critdmg_bmp:
    db "................"
    db "..K....KK....K.."
    db ".KOK..KOOK..KOK."
    db "..KOKKKOOKKKOK.."
    db "...KYOKOOKOYK..."
    db "...KOYYYYYYOK..."
    db "..KKKYYYYYYKKK.."
    db ".KOOOYYLLYYOOOK."
    db ".KOOOYYLLYYOOOK."
    db "..KKKYYYYYYKKK.."
    db "...KOYYYYYYOK..."
    db "...KYOKOOKOYK..."
    db "..KOKKKOOKKKOK.."
    db ".KOK..KOOK..KOK."
    db "..K....KK....K.."
    db "................"
pal_st_critdmg:
    PAL 'K', 70, 20, 8
    PAL 'L', 255, 252, 220
    PAL 'O', 240, 100, 24
    PAL 'Y', 255, 214, 70
    dq 0
st_mana_bmp:
    db "................"
    db ".......KK......."
    db "......KBBK......"
    db "......KBBK......"
    db ".....KBBBBK....."
    db ".....KBBBBK....."
    db "....KBBBBBBK...."
    db "....KBBBBBBK...."
    db "...KBBBBBBBBK..."
    db "..KBBBBBBBBBBK.."
    db "..KBBwBBBBBBBK.."
    db "..KBBwBBBBBBBK.."
    db "..KBBBBBBBBBBK.."
    db "..KBBBBBBBBBdK.."
    db "...KBBBBBBBdK..."
    db "....KBBBBBdK...."
pal_st_mana:
    PAL 'B', 64, 110, 255
    PAL 'K', 14, 24, 80
    PAL 'd', 34, 60, 190
    PAL 'w', 200, 222, 255
    dq 0
st_manaregen_bmp:
    db "...........KK..."
    db "..........KAAK.."
    db "....K....KAAAAK."
    db "...KBK...KAAAAK."
    db "...KBK..KAAAAAAK"
    db "..KBBBK..KKAAKK."
    db "..KBBBK...KAAK.."
    db ".KBBBBBK..KAAK.."
    db "KBwBBBBBK.KAAK.."
    db "KBwBBBBBK.KAAK.."
    db "KBBBBBBdK.KAAK.."
    db ".KBBBBdK..KAAK.."
    db "..KKBKK...KAAK.."
    db "....K.....KAAK.."
    db "..........KAAK.."
    db "...........KK..."
pal_st_manaregen:
    PAL 'A', 120, 235, 110
    PAL 'B', 64, 110, 255
    PAL 'K', 14, 24, 70
    PAL 'd', 34, 60, 190
    PAL 'w', 200, 222, 255
    dq 0
st_stamina_bmp:
    db "........KYYK...."
    db ".......KYLK....."
    db "......KYLYK....."
    db "......KLYK......"
    db ".....KYYYK......"
    db "....KYLYKKKK...."
    db "...KYYYYYYYYK..."
    db "...KYYYYYYYK...."
    db "....KKKYYYK....."
    db "......KYYK......"
    db ".....KYYYK......"
    db ".....KYYK......."
    db ".....KYK........"
    db ".....KK........."
    db "....KYK........."
    db ".....K.........."
pal_st_stamina:
    PAL 'K', 100, 64, 0
    PAL 'L', 255, 250, 190
    PAL 'Y', 255, 214, 40
    dq 0
st_staminaregen_bmp:
    db ".....KYYK..KK..."
    db "....KYYK..KAAK.."
    db "...KYYYK.KAAAAK."
    db "...KYYK..KAAAAK."
    db "..KYYKKKKAAAAAAK"
    db ".KYYYYYYKKKAAKK."
    db ".KYYYYYK..KAAK.."
    db "..KKYYYK..KAAK.."
    db "...KYYK...KAAK.."
    db "...KYYK...KAAK.."
    db "...KYK....KAAK.."
    db "..KYK.....KAAK.."
    db "..KYK.....KAAK.."
    db "...K......KAAK.."
    db "..........KAAK.."
    db "...........KK..."
pal_st_staminaregen:
    PAL 'A', 120, 235, 110
    PAL 'K', 100, 64, 0
    PAL 'Y', 255, 214, 40
    dq 0
st_armor_bmp:
    db ".KKKKKKKKKKKKK.."
    db "KSSSSSSSSSSSSSK."
    db "KSSSSSSSSSSSSSK."
    db "KSSBBBBLLBBBBSK."
    db "KSSBwwBLLBBBBSK."
    db "KSSBwBBLLBBBBDK."
    db "KSSLLLLLLLLLLDK."
    db "KSSLLLLLLLLLLDK."
    db ".KSSBBBLLBBBDDK."
    db "..KSSBBLLBBDDK.."
    db "...KSSBLLBDDK..."
    db "....KSBLLBDK...."
    db "....KSDLLDDK...."
    db ".....KDDDDK....."
    db "......KDDK......"
    db ".......KK......."
pal_st_armor:
    PAL 'B', 58, 98, 190
    PAL 'D', 120, 126, 150
    PAL 'K', 24, 28, 44
    PAL 'L', 214, 224, 250
    PAL 'S', 190, 196, 212
    PAL 'w', 255, 255, 255
    dq 0
st_speed_bmp:
    db "....KKKKK......."
    db "...KUUUUUK......"
    db "...KUUUUUK......"
    db "...KTlTTTK......"
    db "...KTlTTTK......"
    db "ZZ.KTlTTTK......"
    db "...KTlTTTK......"
    db "...KTTTTTK......"
    db "ZZZKTTTTTK......"
    db "...KlTTTTK......"
    db "...KTlTTKKKKKK.."
    db "ZZ.KTTTTTTTTTTK."
    db "...KTTTTTTTTTTK."
    db "...KTTTTTTTTTTK."
    db "...KDDDDDDDDDDDK"
    db "...KDDDDDDDDDDDK"
pal_st_speed:
    PAL 'D', 90, 56, 28
    PAL 'K', 40, 24, 12
    PAL 'T', 160, 100, 52
    PAL 'U', 200, 170, 110
    PAL 'Z', 200, 230, 255
    PAL 'l', 204, 140, 84
    dq 0
st_backstab_bmp:
    db ".......pp......."
    db ".......hh......."
    db ".......hh......."
    db ".......hh......."
    db ".......hh......."
    db "......gggg......"
    db ".......Lm......."
    db ".......Lm......."
    db "...KKKKLmKKK...."
    db "..KHHHHLmHHHK..."
    db ".KHHjHHLmHHHHK.."
    db "KHHjHHHLmHHHHHK."
    db "HHjHHHHLRRHHHHHK"
    db "HHHHHHHRHRHHHHHK"
    db "HHHHHHHHHHHHHHHK"
    db "HHHHHHHHHHHHHHHH"
pal_st_backstab:
    PAL 'H', 78, 52, 120
    PAL 'K', 24, 14, 40
    PAL 'L', 250, 250, 255
    PAL 'R', 230, 40, 48
    PAL 'g', 232, 182, 32
    PAL 'h', 142, 88, 44
    PAL 'j', 112, 84, 160
    PAL 'm', 170, 176, 192
    PAL 'p', 232, 182, 32
    dq 0
st_parry_bmp:
    db "................"
    db "................"
    db "...K........K..."
    db "..KLK......KLK.."
    db "...KLK....KLmK.."
    db "....KLKK.KLmK..."
    db ".....KLYKLmK...."
    db ".....KYLYmK....."
    db "..K...KYLYK..K.."
    db ".KGK.KLmYLK.KGK."
    db "..KGKLmKKKLKGK.."
    db "...KGmK...KGK..."
    db "..KLmGK..KGKLK.."
    db ".KLmKK....K.KLK."
    db "KhhK........KhhK"
    db ".KK..........KK."
pal_st_parry:
    PAL 'G', 232, 182, 32
    PAL 'K', 36, 36, 48
    PAL 'L', 250, 250, 255
    PAL 'Y', 255, 214, 70
    PAL 'h', 150, 90, 50
    PAL 'm', 170, 176, 192
    dq 0
st_lifesteal_bmp:
    db "................"
    db ".......KK......."
    db "......KRRK......"
    db "......KRRK......"
    db ".....KRRRRK....."
    db ".....KRRRRK....."
    db "....KRRRRRRK...."
    db "....KRRRRRRK...."
    db "...KRRRRRRRRK..."
    db "..KRRRRRRRRRRK.."
    db "..KRRwRRRRRRRK.."
    db "..KRRwRRRRRRRK.."
    db "..KRRRRRRRRRRK.."
    db "..KRRRRRRRRRdK.."
    db "...KRRRRRRRdK..."
    db "....KRRRRRdK...."
pal_st_lifesteal:
    PAL 'K', 60, 10, 20
    PAL 'R', 214, 26, 44
    PAL 'd', 140, 14, 30
    PAL 'w', 255, 170, 170
    dq 0
st_cooldown_bmp:
    db ".KGGGGGGGGGGGGK."
    db ".KGGGGGGGGGGGGK."
    db "..KDVVVVVVVVDK.."
    db "...KwwVVVVV.K..."
    db "......VVVV......"
    db "......VVVV......"
    db ".......VV......."
    db "........Y......."
    db "........Y......."
    db ".......VY......."
    db "......VVVV......"
    db "......VYYV......"
    db "...K.VYYYYV.K..."
    db "..KDVVVVVVVVDK.."
    db ".KGGGGGGGGGGGGK."
    db ".KGGGGGGGGGGGGK."
pal_st_cooldown:
    PAL 'D', 140, 92, 20
    PAL 'G', 204, 150, 50
    PAL 'K', 50, 30, 8
    PAL 'V', 150, 200, 230
    PAL 'Y', 255, 214, 70
    PAL 'w', 255, 255, 255
    dq 0
st_arrowsave_bmp:
    db ".....W.W.W......"
    db "....FWFWFWF....."
    db ".....W.W.W......"
    db ".....W.W.W......"
    db ".....W.W.W......"
    db "...RRRRRRRRR...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "...UTTTTTTTu...."
    db "....uTTTTTu....."
    db ".....uuuuu......"
pal_st_arrowsave:
    PAL 'F', 245, 245, 245
    PAL 'R', 120, 70, 30
    PAL 'T', 168, 102, 50
    PAL 'U', 212, 160, 100
    PAL 'W', 190, 140, 90
    PAL 'u', 104, 62, 28
    dq 0
st_wind_bmp:
    db "................"
    db "................"
    db "..........WWW..."
    db ".WWWWWWWWWWWW..."
    db "............W..."
    db "............W..."
    db "..ww............"
    db ".............WW."
    db "WWWWWWWWWWWWWWWW"
    db "...............W"
    db ".ww...........WW"
    db "..........WW..W."
    db "...WWWWWWWW.W..."
    db "............W..."
    db "...........W...."
    db "................"
pal_st_wind:
    PAL 'W', 196, 230, 255
    PAL 'w', 120, 190, 240
    dq 0
npc_face_bmp:
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "..BBBBBBBBBBBB.."
    db "................"
    db "...WWW....WWW..."
    db "...WGG....GGW..."
    db "................"
    db "................"
    db "................"
    db ".....MMMMMM....."
    db "................"
    db "................"
    db "................"
pal_npc_face:
    PAL '.', 225, 180, 140
    PAL 'B', 96, 62, 36
    PAL 'G', 64, 120, 70
    PAL 'M', 150, 98, 76
    PAL 'W', 240, 240, 240
    dq 0
npc_merchant_bmp:
    db "..........f....."
    db ".....f.........."
    db "..........f....."
    db ".....f.........."
    db "..........f....."
    db ".....f.........."
    db "..........f....."
    db ".....f.........."
    db "..........f....."
    db "BBBBBBBYYBBBBBBB"
    db "BBBBBBByyBBBBBBB"
    db ".....f.........."
    db "..........f....."
    db ".....f.........."
    db "dddddddddddddddd"
    db "dddddddddddddddd"
pal_npc_merchant:
    PAL '.', 60, 130, 60
    PAL 'B', 112, 72, 32
    PAL 'Y', 250, 214, 70
    PAL 'd', 44, 100, 44
    PAL 'f', 78, 152, 76
    PAL 'y', 184, 140, 30
    dq 0
npc_elder_bmp:
    db "D......Yy......D"
    db "D..f...Yy...f..D"
    db "D......Yy......D"
    db "D......Yy......D"
    db "D......Yy......D"
    db "D..f...Yy...f..D"
    db "D......Yy......D"
    db "D......Yy......D"
    db "D......Yy......D"
    db "D..f...Yy...f..D"
    db "D......Yy......D"
    db "D......Yy......D"
    db "YYYyYYYyYYYyYYYy"
    db "YYYyYYYyYYYyYYYy"
    db "yyyyyyyyyyyyyyyy"
    db "yyyyyyyyyyyyyyyy"
pal_npc_elder:
    PAL '.', 100, 60, 140
    PAL 'D', 72, 40, 104
    PAL 'Y', 250, 214, 70
    PAL 'f', 124, 80, 168
    PAL 'y', 184, 140, 30
    dq 0
npc_bossrobe_bmp:
    db "...r...ff...r..."
    db "...r........r..."
    db "................"
    db "...r........r..."
    db "...r...ff...r..."
    db "................"
    db "...r........r..."
    db "...r........r..."
    db ".......ff......."
    db "...r........r..."
    db "...r........r..."
    db "....d....d....d."
    db "...k...kd.k..d.."
    db ".kdk..kk..k.k..k"
    db "kk.kk.kk.kkdk.kk"
    db "kkkkkdkkkkk.kkkk"
pal_npc_bossrobe:
    PAL '.', 52, 28, 72
    PAL 'd', 36, 18, 52
    PAL 'f', 84, 46, 110
    PAL 'k', 14, 6, 20
    PAL 'r', 130, 24, 52
    dq 0
npc_bossface_bmp:
    db "................"
    db "................"
    db "......c........."
    db ".......c........"
    db ".......c........"
    db "..KKKK....KKKK.."
    db "..KRRK....KRRK.."
    db "..KRRK....KRRK.."
    db "..KKKK....KKKK.."
    db ".......KK......."
    db ".......KK......."
    db "................"
    db "...KKKKKKKKKK..."
    db "...KK.K.K.K.KK.."
    db "....K.K.K.K.K..."
    db "................"
pal_npc_bossface:
    PAL '.', 222, 214, 192
    PAL 'K', 18, 8, 12
    PAL 'R', 255, 50, 36
    PAL 'c', 150, 142, 118
    dq 0
npc_crown_bmp:
    db "LLLLLLLLLLLLLLLL"
    db "................"
    db "................"
    db ".D...D...D...D.."
    db "................"
    db "................"
    db "...WR..WR..WR..."
    db "...RR..RR..RR..."
    db "................"
    db "................"
    db "................"
    db "................"
    db "LLLLLLLLLLLLLLLL"
    db "DDDDDDDDDDDDDDDD"
    db "DDDDDDDDDDDDDDDD"
    db "DDDDDDDDDDDDDDDD"
pal_npc_crown:
    PAL '.', 240, 190, 40
    PAL 'D', 176, 126, 16
    PAL 'L', 255, 236, 140
    PAL 'R', 220, 30, 50
    PAL 'W', 255, 170, 170
    dq 0

section .text

; ---------------------------------------------------------------------------
; 0.7 building art. Base-colour routines for NFUNC tiles: in r15d = px, r14d = py, r9d = the
; pixel's rng draw, r10d/r11d = parameters; out esi = base colour (0 = transparent). They clobber
; eax, ecx, edx only. Then the icon routines (out eax = packed RGBA) and the bitmaps.
; ---------------------------------------------------------------------------
section .rodata
; bookshelf: spine colour index per column (6 = dark gap between books)
spine_idx:
    db 0, 1, 1, 6, 2, 2, 2, 6, 3, 3, 6, 4, 4, 6, 5, 5
align 4
spine_pal:
    dd RGB(150,44,40), RGB(52,72,150), RGB(56,120,60), RGB(120,78,44)
    dd RGB(196,166,58), RGB(110,54,130), RGB(36,26,16), RGB(36,26,16)

; tile 59's bitmap with dark cracks ('x') running down two bricks
cracked_bmp:
    db "hhhhhhhDhhhhhhhD"
    db "caaxabaDacbaaacD"
    db "baaxbcbDcaaaxaaD"
    db "ccaaxaaDaaaaxbbD"
    db "acaaxaaDaacxaccD"
    db "baabaxcDbaaacaaD"
    db "lllllxlDlllllllD"
    db "DDDDDDDDDDDDDDDD"
    db "hhhDhhhhhhhDhhhh"
    db "babDbbbxaaaDcaca"
    db "aaaDbaaxacbDcabc"
    db "aaaDaaaaxabDacba"
    db "bcbDacbaxaaDcaab"
    db "cacDcaaaaxaDbaca"
    db "lllDlllllxlDllll"
    db "DDDDDDDDDDDDDDDD"
pal_cracked:
    PAL 'D', 66, 66, 70
    PAL 'a', 132, 132, 134
    PAL 'b', 120, 120, 124
    PAL 'c', 144, 144, 146
    PAL 'h', 160, 160, 162
    PAL 'l', 108, 108, 112
    PAL 'x', 34, 34, 38
    dq 0

; fence icon: two posts and two rails
fence_icon_bmp:
    db "................"
    db "...Wd......Wd..."
    db "...Wd......Wd..."
    db "...Wd......Wd..."
    db "...WWWWWWWWWW..."
    db "...dddddddddd..."
    db "...Wd......Wd..."
    db "...Wd......Wd..."
    db "...Wd......Wd..."
    db "...WWWWWWWWWW..."
    db "...dddddddddd..."
    db "...Wd......Wd..."
    db "...Wd......Wd..."
    db "...Wd......Wd..."
    db "...Wd......Wd..."
    db "...Wd......Wd..."
pal_fence_icon:
    PAL 'W', 176, 142, 84
    PAL 'd', 110, 84, 48
    dq 0

; glass pane icon: thin frame, clear inside with two shine strokes
pane_icon_bmp:
    db "................"
    db "....FFFFFFFF...."
    db "....F....W.F...."
    db "....F...W..F...."
    db "....F..W...F...."
    db "....F.W....F...."
    db "....F......F...."
    db "....F.....WF...."
    db "....F....W.F...."
    db "....F...W..F...."
    db "....F......F...."
    db "....F......F...."
    db "....F......F...."
    db "....F......F...."
    db "....FFFFFFFF...."
    db "................"
pal_pane_icon:
    PAL 'F', 216, 238, 244
    PAL 'W', 255, 255, 255
    dq 0

; ---- 0.8 icons: jewelry, warhammers, spears (203..207, 216), slot-3 ability icons (217..220),
;      attributes (221..223, 232), elements (233..236), stat icons (237..239, 254), keystone (255).
;      The hammer and spear bitmaps are shared by the iron and the diamond tile (two palettes). ----
ring_bmp:
    db "................"
    db "................"
    db "......KKKK......"
    db ".....KwRRrK....."
    db ".....KRRRrK....."
    db "......KKKK......"
    db "....KKKYYKKK...."
    db "...KYYLLLYYYK..."
    db "..KYLYKKKKYYDK.."
    db "..KYYK....KYDK.."
    db "..KYYK....KDDK.."
    db "..KYYK....KDDK.."
    db "..KDYK....KYDK.."
    db "...KDDKKKKDDK..."
    db "....KKDDDDKK...."
    db "................"
pal_ring:
    PAL 'K', 84, 52, 8
    PAL 'Y', 252, 214, 60
    PAL 'L', 255, 246, 170
    PAL 'D', 204, 146, 16
    PAL 'R', 226, 32, 52
    PAL 'r', 142, 10, 32
    PAL 'w', 255, 176, 176
    dq 0
amulet_bmp:
    db "................"
    db ".Y............Y."
    db ".DY..........YD."
    db "..DY........YD.."
    db "..DY........YD.."
    db "...DY......YD..."
    db "....DY....YD...."
    db ".....DYYYYD....."
    db "......KYYK......"
    db ".....KKBBKK....."
    db "....KwBBBBbK...."
    db "....KBBBBBbK...."
    db ".....KBBBbK....."
    db "......KbbK......"
    db ".......KK......."
    db "................"
pal_amulet:
    PAL 'K', 24, 24, 60
    PAL 'Y', 252, 214, 60
    PAL 'D', 204, 146, 16
    PAL 'B', 64, 128, 255
    PAL 'b', 22, 56, 176
    PAL 'w', 200, 230, 255
    dq 0
hammer_bmp:
    db "........KK......"
    db ".......KDDK....."
    db "......KDDDDK...."
    db ".....KMDMMDDK..."
    db ".....KMLMMMDDK.."
    db "......KLLMMMDDK."
    db ".......KLLMMMDDK"
    db "........HLLMMDDK"
    db ".......HhKLLDDK."
    db "......Hh..KMMK.."
    db ".....Hh....KK..."
    db "....Hh.........."
    db "...Wh..........."
    db "..Ww............"
    db "QHw............."
    db "QQ.............."
pal_gear_iron:
    PAL 'K', 40, 40, 52
    PAL 'L', 240, 240, 248
    PAL 'M', 184, 188, 200
    PAL 'D', 108, 112, 128
    PAL 'H', 176, 120, 60
    PAL 'h', 110, 70, 30
    PAL 'W', 70, 44, 24
    PAL 'w', 120, 84, 50
    PAL 'Q', 226, 190, 60
    dq 0
pal_gear_diamond:
    PAL 'K', 10, 60, 70
    PAL 'L', 200, 255, 252
    PAL 'M', 70, 206, 196
    PAL 'D', 24, 128, 128
    PAL 'H', 176, 120, 60
    PAL 'h', 110, 70, 30
    PAL 'W', 70, 44, 24
    PAL 'w', 120, 84, 50
    PAL 'Q', 226, 190, 60
    dq 0
spear_bmp:
    db "..........KLLLLM"
    db "..........KLLLMM"
    db ".........KLLLMMD"
    db "..........KLMMDD"
    db "..........KMMDDD"
    db "..........HhDDDD"
    db ".........Hh.KKKK"
    db "........Hh......"
    db ".......Wh......."
    db "......Ww........"
    db ".....Hw........."
    db "....Hh.........."
    db "...Hh..........."
    db "..Hh............"
    db "HHh............."
    db "hh.............."
slam_bmp:
    db "................"
    db "....KKKKKKK....."
    db "...KLLFFFFFK...."
    db "..KLFKFKFKFFK..."
    db "..KFFFFFFFFfK..."
    db "..KFFFFFFFffK..."
    db "..KffFFFFFffK..."
    db "...KKfffffKK...."
    db "....KKKKKKK....."
    db "OO....O..O....OO"
    db ".CCO.OCO.OCO.CC."
    db "...CCCCCCCCCC..."
    db ".CC..C.CC.C..CC."
    db "C.....C..C.....C"
    db "................"
    db "................"
pal_slam:
    PAL 'K', 60, 28, 20
    PAL 'F', 232, 172, 120
    PAL 'f', 186, 116, 76
    PAL 'L', 252, 214, 176
    PAL 'C', 48, 32, 32
    PAL 'O', 255, 140, 40
    dq 0
nova_bmp:
    db "................"
    db ".....BBBBBB....."
    db "...BBB....BBB..."
    db "..BB........BB.."
    db "..B..W....W..B.."
    db ".BB...I..I...BB."
    db ".B....I.I.....B."
    db ".B.....WW.....B."
    db ".B..W.IWW.I.W.B."
    db ".B....I.I.....B."
    db ".BB...I..I...BB."
    db "..B...W...W..B.."
    db "..BB........BB.."
    db "...BBB....BBB..."
    db ".....BBBBBB....."
    db "................"
pal_nova:
    PAL 'B', 60, 124, 224
    PAL 'I', 150, 220, 255
    PAL 'W', 244, 252, 255
    dq 0
mark_bmp:
    db ".......OO......."
    db "......ROOR......"
    db "....RRROORRR...."
    db "...RR......RR..."
    db "..RR........RR.."
    db "..R...RRRR...R.."
    db ".RR..R....R..RR."
    db "OOO..R.YY.R..OOO"
    db "OOO..R.YY.R..OOO"
    db ".RR..R....R..RR."
    db "..R...RRRR...R.."
    db "..RR........RR.."
    db "...RR......RR..."
    db "....RRROORRR...."
    db "......ROOR......"
    db ".......OO......."
pal_mark:
    PAL 'R', 230, 40, 40
    PAL 'O', 255, 150, 40
    PAL 'Y', 255, 226, 90
    dq 0
knives_bmp:
    db ".......R........"
    db ".......S........"
    db ".R.....S......R."
    db ".......S........"
    db ".......S........"
    db ".......S........"
    db ".......S........"
    db "......LSS......S"
    db "LS....LSS....LS."
    db "LLS...LSS...LSS."
    db ".LLS..LSS..LSS.."
    db "..LLS.....LSS..."
    db "...L.GGGGGGS...."
    db "....GH....HG...."
    db "....G.H.HH.G...."
    db ".......HH......."
pal_knives:
    PAL 'H', 120, 76, 36
    PAL 'G', 232, 182, 32
    PAL 'L', 246, 246, 255
    PAL 'S', 150, 158, 180
    PAL 'R', 210, 24, 34
    dq 0
attr_str_bmp:
    db "................"
    db "................"
    db "................"
    db "...KKKKKKKKK...."
    db "..KLRRKRRKRRK..."
    db "..KRRRKRRKRRrK.."
    db "..KRRRRRRRRRrK.."
    db ".KRRRRRRRRRRrrK."
    db ".KRKKRRRRRRRrrK."
    db ".KRRKKKKKRRRrK.."
    db "..KRRRRRRRRrrK.."
    db "..KRRRRRRRrrK..."
    db "...KRRRRRrrK...."
    db "....KKDDDDK....."
    db ".....KDDDDK....."
    db "......KKKK......"
pal_attr_str:
    PAL 'K', 70, 10, 14
    PAL 'R', 226, 52, 44
    PAL 'r', 160, 24, 28
    PAL 'L', 255, 170, 150
    PAL 'D', 120, 16, 20
    dq 0
attr_dex_bmp:
    db "................"
    db "...........KK.Q."
    db ".........KKLGQ.."
    db "........KLGLQgK."
    db "......KKGLLQGGK."
    db ".....KGGLGQGgK.."
    db "....KGLGGQgGGK.."
    db "...KLGGLQgGgK..."
    db "..KLGLGQGggK...."
    db "..KLLGQggGgK...."
    db ".KLGLQgGggK....."
    db "..KLQGGgGK......"
    db "...QGgGGK......."
    db "..Q.KGKK........"
    db ".Q...K.........."
    db "QQ.............."
pal_attr_dex:
    PAL 'K', 16, 60, 24
    PAL 'G', 58, 184, 76
    PAL 'g', 30, 126, 52
    PAL 'L', 146, 238, 140
    PAL 'Q', 236, 236, 206
    dq 0
attr_int_bmp:
    db "................"
    db "................"
    db ".......KK......."
    db "....KKKWWKKK...."
    db "...KWWWWWWWWK..."
    db ".KKWWWbbbbWWWKK."
    db "KWWWWbwwBBbWWWWK"
    db "WWWWWbBPPBbWWWWW"
    db "WWWWWbBPPBbWWWWW"
    db "KWWWWbBBBBbWWWWK"
    db ".KKWWWbbbbWWWKK."
    db "...KWWWWWWWWK..."
    db "....KKKWWKKK...."
    db ".......KK......."
    db "................"
    db "................"
pal_attr_int:
    PAL 'K', 20, 24, 70
    PAL 'W', 226, 238, 255
    PAL 'B', 70, 128, 255
    PAL 'b', 36, 70, 200
    PAL 'P', 10, 12, 40
    PAL 'w', 255, 255, 255
    dq 0
attr_vit_bmp:
    db "................"
    db "....KKK..KKK...."
    db "...KRRRKKRRRK..."
    db "..KRwRRRRRRRRK.."
    db ".KRwRRRPPRRRRRK."
    db ".KRRRRRPPRRRRRK."
    db ".KRRRPPPPPPRRRK."
    db ".KRRRPPPPPPRRRK."
    db "..KRRRRPPRRRRK.."
    db "...KRRRPPRRRK..."
    db "....KRRRRRRK...."
    db ".....KRRRRdK...."
    db "......KRRdK....."
    db ".......KRK......"
    db "........K......."
    db "................"
pal_attr_vit:
    PAL 'K', 60, 14, 22
    PAL 'R', 226, 40, 52
    PAL 'd', 160, 24, 40
    PAL 'w', 255, 170, 170
    PAL 'P', 255, 255, 255
    dq 0
elem_fire_bmp:
    db "........O......."
    db ".......OO......."
    db ".......OOO......"
    db "......OOOO..O..."
    db ".....OOOYOO.OO.."
    db "....OOOYYOOOOO.."
    db "....OOYYYYOOOO.."
    db "...OOOYYYYYOOO.."
    db "...OOYYYYYYOOr.."
    db "...OOYYLLYYOOr.."
    db "...OOYLLLLYOOr.."
    db "....OOYLLYOOr..."
    db ".....OOYYOOr...."
    db "......rrrrr....."
    db "................"
    db "................"
pal_elem_fire:
    PAL 'O', 255, 138, 28
    PAL 'Y', 255, 214, 70
    PAL 'L', 255, 250, 210
    PAL 'r', 204, 40, 20
    dq 0
elem_frost_bmp:
    db "................"
    db "....W.B..B.W...."
    db "....IB....B....."
    db "...BBI.BB.IBB..."
    db ".....IB.B.I....."
    db "....BBI..IBB...."
    db ".B.B..I.I...B.B."
    db "..B.B..WW..B.B.."
    db "W.B.B.IWW.IBIBW."
    db ".B.B..I.I...B.B."
    db "....BBI..IBB...."
    db "......IBB.I....."
    db "...BBI.BB.IBB..."
    db ".....IB...B....."
    db "....W.B..B.W...."
    db "................"
pal_elem_frost:
    PAL 'I', 160, 224, 255
    PAL 'B', 84, 150, 235
    PAL 'W', 250, 254, 255
    dq 0
elem_shock_bmp:
    db "................"
    db "........KKKKK..."
    db ".......KYYYYK..."
    db "......KYYYYK...."
    db ".....KYYYYK....."
    db "....KYYYYYYYK..."
    db "...KYYYYYYYK...."
    db "....KKKYYYK....."
    db ".....KYYYK......"
    db "....KYYYK......."
    db "....KYYK........"
    db "...KYYK........."
    db "...KYK.........."
    db "...KK..........."
    db "................"
    db "................"
pal_elem_shock:
    PAL 'K', 100, 70, 0
    PAL 'Y', 255, 238, 70
    dq 0
elem_poison_bmp:
    db ".......KK......."
    db "......KFFK......"
    db "......KFFK......"
    db "......KFFK......"
    db ".....KFFFFK....."
    db ".....KFFFFK....."
    db "....KFFFFFFK...."
    db "...KFFFFFFFFK..."
    db "...KFFFFFDDDK..."
    db "..KFFFFLFDDDDK.."
    db "...KFFLFFDDDK..."
    db "...KFFLFFDDDK..."
    db "....KFFFFDDK...."
    db ".....KFFFDK....."
    db "......KKKK......"
    db "................"
pal_elem_poison:
    PAL 'K', 16, 60, 16
    PAL 'F', 100, 210, 60
    PAL 'D', 50, 150, 36
    PAL 'L', 200, 255, 160
    dq 0
st_aspd_bmp:
    db "................"
    db "..KK...KK......."
    db ".KLLK.KLLK......"
    db "..KYYK.KYYK....."
    db "...KYYK.KYYK...."
    db "....KYYK.KYYK..."
    db ".....KYYK.KYYK.."
    db "......KYYK.KYYK."
    db "......KYYK.KYYK."
    db ".....KLYK.KLYK.."
    db "....KLYK.KLYK..."
    db "...KLYK.KLYK...."
    db "..KLYK.KLYK....."
    db ".KLYK.KLYK......"
    db "..KK...KK......."
    db "................"
pal_st_aspd:
    PAL 'K', 90, 48, 8
    PAL 'Y', 255, 170, 40
    PAL 'L', 255, 230, 120
    dq 0
st_bleed_bmp:
    db ".......KK......."
    db "......KFFK......"
    db "......KFFK......"
    db "......KFFK......"
    db ".....KFFFFK....."
    db ".....KFFFFK....."
    db "....KFFFFFFK...."
    db "...KFFFFFFFFK..."
    db "...KFFFFFDDDK..."
    db "...KFFFLFDDDK..."
    db "...KFFLFFDDDK..."
    db "....KFLFFDDK...."
    db ".....KFFFDK....."
    db "......KKKK......"
    db "................"
    db "................"
pal_st_bleed:
    PAL 'K', 50, 0, 8
    PAL 'F', 190, 16, 30
    PAL 'D', 120, 8, 20
    PAL 'L', 255, 140, 140
    dq 0
st_area_bmp:
    db "................"
    db ".O.....OO.....O."
    db "..O....OO....O.."
    db "......BBBB......"
    db "....BBB..BBB...."
    db "....B......B...."
    db "...BB......BB..."
    db ".OOB...YY...BOO."
    db ".OOB...YY...BOO."
    db "...BB......BB..."
    db "....B......B...."
    db "....BBB..BBB...."
    db "......BBBB......"
    db "..O....OO....O.."
    db ".O.....OO.....O."
    db "................"
pal_st_area:
    PAL 'B', 255, 130, 40
    PAL 'O', 255, 214, 70
    PAL 'Y', 255, 250, 200
    dq 0
st_elite_bmp:
    db "................"
    db "....KKKKKKKK...."
    db "...KYYYYYYYYK..."
    db "..KYLLYYYYYYDK.."
    db "..KYLYYYYYYYDK.."
    db "..KYKKKYYKKKDK.."
    db "..KYKKKYYKKKDK.."
    db "..KYYKKYYKKYDK.."
    db "...KYYYKKYYYK..."
    db "....KYYYYYYDK..."
    db "....KYKYKYKDK..."
    db ".....KDKDKDK...."
    db "......KKKKK....."
    db "................"
    db "................"
    db "................"
pal_st_elite:
    PAL 'K', 84, 52, 8
    PAL 'Y', 252, 214, 60
    PAL 'L', 255, 246, 170
    PAL 'D', 204, 146, 16
    dq 0
keystone_bmp:
    db "................"
    db "..EEEEEEEEEEEE.."
    db ".ENNNNNNNNNNNNE."
    db ".ENNNNNLNNNNNNE."
    db ".ENNNNNLYNNNNNE."
    db ".ENNNNNLYNNNNNE."
    db ".ELLLLLLYYYYYYE."
    db ".ENLLLLLYYYYYNE."
    db ".ENNNYYYYYYNNNE."
    db ".ENNNYYYYYNNNNE."
    db ".ENNNYYYYYYNNNE."
    db ".ENNNYYNNYYNNNE."
    db ".ENNNYNNNNYNNNE."
    db ".ENNNNNNNNNNNNE."
    db "..EEEEEEEEEEEE.."
    db "................"
pal_keystone:
    PAL 'N', 22, 30, 86
    PAL 'E', 70, 90, 170
    PAL 'Y', 255, 200, 60
    PAL 'L', 255, 244, 150
    dq 0

section .text

; atlas_px: ecx = tile, eax = x, edx = y (0..15 inside the tile) -> eax = the pixel already drawn
; in the atlas at r12. Clobbers ecx, edx, r8d.
atlas_px:
    mov     r8d, ecx
    and     r8d, 15
    shl     r8d, 4
    add     eax, r8d                    ; x + tile col * 16
    shr     ecx, 4
    shl     ecx, 4
    add     edx, ecx                    ; y + tile row * 16
    shl     edx, 8
    add     eax, edx
    mov     eax, [r12 + rax * 4]
    ret

; speckled flat colour: r10d = base, r11d = speck (1 pixel in 16)
px_speckle:
    mov     esi, r10d
    mov     eax, r9d
    shr     eax, 9
    and     eax, 15
    jnz     .done
    mov     esi, r11d
.done:
    ret

; sandstone side: darker band on rows 0..1, strata on rows 5, 10 and 13, sparse specks
px_sand_side:
    mov     esi, RGB(196,174,120)
    cmp     r14d, 2
    jb      .done
    mov     esi, RGB(206,188,136)
    cmp     r14d, 5
    je      .done
    cmp     r14d, 10
    je      .done
    cmp     r14d, 13
    je      .done
    mov     esi, RGB(222,206,154)
    mov     eax, r9d
    shr     eax, 9
    and     eax, 15
    jnz     .done
    mov     esi, RGB(200,182,128)
.done:
    ret

; smooth stone: light grey with a faint darker outline
px_smooth:
    mov     esi, RGB(128,128,130)
    IF_BORDER .done
    mov     esi, RGB(162,162,164)
.done:
    ret

; mossy cobblestone: tile 4's pattern with moss patches on the stones and some of the mortar
px_cobble_mossy:
    mov     eax, r14d
    and     eax, 3
    cmp     eax, 3
    je      .mortar
    mov     eax, r14d
    shr     eax, 2
    lea     eax, [rax + rax * 2]
    add     eax, r15d
    xor     edx, edx
    mov     ecx, 5
    div     ecx
    cmp     edx, 4
    je      .mortar
    mov     esi, RGB(130,130,130)
    mov     eax, r9d
    shr     eax, 12
    and     eax, 15
    cmp     eax, 4
    jae     .done
    mov     esi, RGB(84,132,54)
    test    eax, eax
    jnz     .done
    mov     esi, RGB(66,108,42)
    ret
.mortar:
    mov     esi, RGB(70,70,70)
    mov     eax, r9d
    shr     eax, 10
    and     eax, 3
    jnz     .done
    mov     esi, RGB(56,92,40)
.done:
    ret

; bookshelf side: plank frame (rows 0..1, 7..8, 14..15, columns 0 and 15) around two shelves of
; coloured spines (rows 2..6 and 9..13)
px_bookshelf:
    lea     eax, [r14 - 2]
    cmp     eax, 4
    jbe     .shelf0
    lea     eax, [r14 - 9]
    cmp     eax, 4
    jbe     .shelf1
.plank:
    mov     esi, RGB(158,124,74)
    cmp     r14d, 1
    je      .shadow
    cmp     r14d, 8
    je      .shadow
    cmp     r14d, 15
    je      .shadow
    ret
.shadow:
    mov     esi, RGB(112,88,52)
    ret
.shelf0:
    xor     ecx, ecx
    jmp     .book
.shelf1:
    mov     ecx, 5                      ; the second shelf is shifted so the spines differ
.book:
    test    r15d, r15d
    jz      .plank
    cmp     r15d, 15
    je      .plank
    lea     eax, [r15 + rcx]
    and     eax, 15
    lea     rdx, [spine_idx]
    movzx   eax, byte [rdx + rax]
    lea     rdx, [spine_pal]
    mov     esi, [rdx + rax * 4]
    ret

; wool: off-white with a diagonal knit pattern
px_wool:
    mov     esi, RGB(232,232,226)
    lea     eax, [r15 + r14 * 2]
    and     eax, 3
    jnz     .done
    mov     esi, RGB(212,212,206)
.done:
    ret

; metal blocks: four 8x8 bevelled plates; r10d = plate colour, r11d = highlight (top and left edge),
; the bottom and right edges are 3/4 of the plate colour
px_plates:
    mov     eax, r15d
    and     eax, 7
    mov     ecx, r14d
    and     ecx, 7
    mov     esi, r11d
    test    eax, eax
    jz      .done
    test    ecx, ecx
    jz      .done
    cmp     eax, 7
    je      .dark
    cmp     ecx, 7
    je      .dark
    mov     esi, r10d
    ret
.dark:
    mov     esi, r10d
    shr     esi, 1
    and     esi, 0x007F7F7F
    mov     eax, r10d
    shr     eax, 2
    and     eax, 0x003F3F3F
    add     esi, eax                    ; 0.5 + 0.25 of each channel
.done:
    ret

; coal block: near-black with sparse lighter flecks
px_coal:
    mov     esi, RGB(40,40,44)
    mov     eax, r9d
    shr     eax, 9
    and     eax, 7
    jnz     .done
    mov     esi, RGB(78,78,84)
.done:
    ret

; wooden door (r10d = 0 lower, 1 upper): dark frame; the lower half has two raised panels and a
; handle, the upper half 2x2 transparent window panes
px_wood_door:
    mov     esi, RGB(104,74,38)
    IF_BORDER .done
    mov     esi, RGB(150,110,60)
    test    r10d, r10d
    jnz     .upper
    lea     eax, [r14 - 2]
    cmp     eax, 4
    jbe     .panel
    lea     eax, [r14 - 9]
    cmp     eax, 4
    jbe     .panel
    cmp     r15d, 12
    jne     .done
    lea     eax, [r14 - 7]
    cmp     eax, 1
    ja      .done
    mov     esi, RGB(228,204,112)       ; handle on rows 7..8
    ret
.panel:                                 ; eax = row inside the panel 0..4
    lea     ecx, [r15 - 2]
    cmp     ecx, 11
    ja      .done                       ; panels span px 2..13
    test    eax, eax
    jz      .pdark
    test    ecx, ecx
    jz      .pdark
    cmp     eax, 4
    je      .plite
    cmp     ecx, 11
    je      .plite
    mov     esi, RGB(166,124,70)
    ret
.pdark:
    mov     esi, RGB(116,84,44)
    ret
.plite:
    mov     esi, RGB(182,140,84)
    ret
.upper:
    lea     eax, [r15 - 3]
    cmp     eax, 3
    jbe     .wx
    lea     eax, [r15 - 9]
    cmp     eax, 3
    ja      .done
.wx:
    lea     eax, [r14 - 3]
    cmp     eax, 3
    jbe     .hole
    lea     eax, [r14 - 8]
    cmp     eax, 3
    ja      .done
.hole:
    xor     esi, esi
.done:
    ret

; iron door (r10d = 0 lower, 1 upper): riveted grey plates; the lower half has a seam and a handle,
; the upper half a barred window (bars every 3 columns, transparent between)
px_iron_door:
    mov     esi, RGB(120,120,128)
    IF_BORDER .done
    mov     esi, RGB(198,198,206)
    lea     eax, [r15 - 2]              ; rivets at (2|13, 2|13)
    test    eax, eax
    jz      .rx
    cmp     eax, 11
    jne     .norivet
.rx:
    lea     eax, [r14 - 2]
    test    eax, eax
    jz      .rivet
    cmp     eax, 11
    jne     .norivet
.rivet:
    mov     esi, RGB(132,132,140)
    ret
.norivet:
    test    r10d, r10d
    jnz     .upper
    cmp     r14d, 7
    jne     .nohseam
    mov     esi, RGB(148,148,156)       ; seam
    ret
.nohseam:
    cmp     r15d, 12
    jne     .done
    lea     eax, [r14 - 8]
    cmp     eax, 1
    ja      .done
    mov     esi, RGB(70,70,78)          ; handle on rows 8..9
    ret
.upper:
    lea     eax, [r15 - 3]
    cmp     eax, 9
    ja      .done                       ; window px 3..12
    lea     ecx, [r14 - 3]
    cmp     ecx, 6
    ja      .done                       ; window py 3..9
    mov     esi, RGB(90,90,98)
    test    ecx, ecx
    jz      .done
    cmp     ecx, 6
    je      .done                       ; top and bottom bars
    xor     edx, edx
    mov     ecx, 3
    div     ecx                         ; eax = px-3
    test    edx, edx
    jz      .done                       ; vertical bars
    xor     esi, esi                    ; open
.done:
    ret

; trapdoor: dark rim, plank frame, four transparent holes
px_trapdoor:
    mov     esi, RGB(104,76,40)
    IF_BORDER .done
    mov     esi, RGB(152,114,64)
    lea     eax, [r15 - 2]
    cmp     eax, 4
    jbe     .hx
    lea     eax, [r15 - 9]
    cmp     eax, 4
    ja      .done
.hx:
    lea     eax, [r14 - 2]
    cmp     eax, 4
    jbe     .hole
    lea     eax, [r14 - 9]
    cmp     eax, 4
    ja      .done
.hole:
    xor     esi, esi
.done:
    ret

; ladder: rails at px 2..3 and 12..13, rungs every 4 rows (1, 5, 9, 13); the rest transparent
px_ladder:
    xor     esi, esi
    lea     eax, [r15 - 2]
    cmp     eax, 1
    jbe     .rail
    lea     eax, [r15 - 12]
    cmp     eax, 1
    jbe     .rail
    lea     eax, [r15 - 4]
    cmp     eax, 7
    ja      .done
    mov     eax, r14d
    and     eax, 3
    cmp     eax, 1
    jne     .done
    mov     esi, RGB(120,86,44)
    ret
.rail:
    mov     esi, RGB(146,108,58)
.done:
    ret

; torch: px 7..8 only. Rows 6..7 flame, rows 8..15 wood (right column darker)
icon_torch:
    xor     eax, eax
    lea     ecx, [r15 - 7]
    cmp     ecx, 1
    ja      .done
    cmp     r14d, 6
    jb      .done
    je      .flame0
    cmp     r14d, 7
    je      .flame1
    mov     eax, RGBO(120,85,45)
    test    ecx, ecx
    jz      .done
    mov     eax, RGBO(96,68,36)
    ret
.flame0:
    mov     eax, RGBO(255,230,120)
    ret
.flame1:
    mov     eax, RGBO(255,160,40)
.done:
    ret

; stair icon: material tile r10d masked to a stair silhouette (rows 8..15 full width, rows 0..7
; the right half)
icon_stair:
    cmp     r14d, 8
    jae     .copy
    cmp     r15d, 8
    jb      .none
.copy:
    mov     ecx, r10d
    mov     eax, r15d
    mov     edx, r14d
    jmp     atlas_px
.none:
    xor     eax, eax
    ret

; slab icon: rows 8..15 of the material tile r10d
icon_slab:
    cmp     r14d, 8
    jb      .none
    mov     ecx, r10d
    mov     eax, r15d
    mov     edx, r14d
    jmp     atlas_px
.none:
    xor     eax, eax
    ret

; door icon: the whole door (upper tile r10d over lower tile r11d, 16x32) squeezed into px 4..11 by
; point sampling at 2n (n = 7 -> 15)
icon_door:
    lea     ecx, [r15 - 4]
    cmp     ecx, 7
    ja      .none
    lea     eax, [rcx * 2]
    cmp     ecx, 7
    jne     .x
    inc     eax
.x:
    mov     ecx, r10d
    mov     edx, r14d
    cmp     r14d, 8
    jb      .y
    mov     ecx, r11d
    sub     edx, 8
.y:
    cmp     edx, 7
    lea     edx, [rdx * 2]
    jne     .go
    inc     edx
.go:
    jmp     atlas_px
.none:
    xor     eax, eax
    ret

; ---------------------------------------------------------------------------
; 0.9 art. Base-colour routines for NFUNC/NFUNCA tiles: in r15d = px, r14d = py, r9d = the
; pixel's rng draw, r10d/r11d = parameters; out esi = base colour (0 = transparent). They clobber
; eax, ecx, edx only (px_bed_side also r8d, on purpose).
; ---------------------------------------------------------------------------

; water: blue with short light ripple dashes on every 4th row, staggered per band
px_water:
    mov     esi, C_WATER
    mov     eax, r14d
    and     eax, 3
    cmp     eax, 1
    jne     .done
    mov     eax, r14d
    shr     eax, 2
    lea     eax, [rax + rax * 4]
    add     eax, r15d
    and     eax, 7
    cmp     eax, 3
    jae     .done
    mov     esi, RGB(70,130,230)
.done:
    ret

; ice: pale blue with white cracks (one diagonal each way and a short horizontal)
px_ice:
    mov     esi, RGB(160,200,240)
    mov     eax, r15d
    sub     eax, r14d
    cmp     eax, 3
    jne     .b
    lea     ecx, [r15 - 5]
    cmp     ecx, 7
    jbe     .crack
.b:
    lea     eax, [r15 + r14]
    cmp     eax, 17
    jne     .c
    lea     ecx, [r15 - 3]
    cmp     ecx, 6
    jbe     .crack
.c:
    cmp     r14d, 8
    jne     .done
    lea     ecx, [r15 - 9]
    cmp     ecx, 4
    jbe     .crack
.done:
    ret
.crack:
    mov     esi, RGB(238,246,255)
    ret

; snow: white with a light grey speck on 1 pixel in 8
px_snow:
    mov     esi, RGB(240,245,250)
    mov     eax, r9d
    shr     eax, 8
    and     eax, 7
    jnz     .done
    mov     esi, RGB(206,216,230)
.done:
    ret

; mud: dark brown with darker and lighter clumps
px_mud:
    mov     esi, RGB(70,50,35)
    mov     eax, r9d
    shr     eax, 8
    and     eax, 7
    jnz     .l
    mov     esi, RGB(54,38,26)
    ret
.l:
    cmp     eax, 1
    jne     .done
    mov     esi, RGB(86,62,44)
.done:
    ret

; cactus side: darker rib on every 4th column, 1-px light spines between the ribs
px_cactus_side:
    mov     esi, RGB(40,130,50)
    mov     eax, r15d
    and     eax, 3
    jz      .rib
    cmp     eax, 2
    jne     .done
    mov     ecx, r15d
    shr     ecx, 2
    lea     ecx, [rcx + rcx * 2]
    add     ecx, r14d
    and     ecx, 3
    jnz     .done
    mov     esi, RGB(214,226,160)
.done:
    ret
.rib:
    mov     esi, RGB(26,96,38)
    ret

; cactus top: dark rim, a lighter ring 2..3 px inside it, a spine in the middle
px_cactus_top:
    mov     eax, r15d                   ; eax = distance to the nearest edge
    mov     ecx, 15
    sub     ecx, r15d
    cmp     ecx, eax
    cmovb   eax, ecx
    cmp     r14d, eax
    cmovb   eax, r14d
    mov     ecx, 15
    sub     ecx, r14d
    cmp     ecx, eax
    cmovb   eax, ecx
    mov     esi, RGB(26,96,38)
    test    eax, eax
    jz      .done
    mov     esi, RGB(40,130,50)
    lea     ecx, [rax - 2]
    cmp     ecx, 1
    ja      .mid
    mov     esi, RGB(86,172,88)
    ret
.mid:
    cmp     eax, 7
    jne     .done
    mov     esi, RGB(214,226,160)
.done:
    ret

; pine bark: dark brown with vertical streaks and the odd light fleck
px_pine_bark:
    mov     esi, RGB(60,40,25)
    mov     eax, r15d
    lea     eax, [rax + rax * 4]
    mov     ecx, r15d
    shr     ecx, 1
    add     eax, ecx
    and     eax, 7
    cmp     eax, 2
    jae     .fleck
    mov     esi, RGB(42,28,17)
    ret
.fleck:
    mov     eax, r9d
    shr     eax, 8
    and     eax, 15
    jnz     .done
    mov     esi, RGB(84,58,36)
.done:
    ret

; log top with rings (as tile 7): bark rim, then rings alternating r10d / r11d
px_ring_top:
    mov     esi, RGB(60,40,25)
    test    r15d, r15d
    jz      .done
    cmp     r15d, 15
    je      .done
    test    r14d, r14d
    jz      .done
    cmp     r14d, 15
    je      .done
    lea     eax, [r15 * 2 - 15]
    lea     ecx, [r14 * 2 - 15]
    imul    eax, eax
    imul    ecx, ecx
    add     eax, ecx
    cvtsi2ss xmm0, eax
    sqrtss  xmm0, xmm0
    mulss   xmm0, [half]
    cvttss2si eax, xmm0
    shr     eax, 1
    and     eax, 1
    mov     esi, r10d
    jz      .done
    mov     esi, r11d
.done:
    ret

; leaves with holes (as tile 8): r10d = colour, a hole on 1 pixel in 4 (draw bits 8..9)
px_leaves_holes:
    mov     eax, r9d
    shr     eax, 8
    and     eax, 3
    jnz     .solid
    xor     esi, esi
    ret
.solid:
    mov     esi, r10d
    ret

; birch bark: off-white, black horizontal dashes on rows 2, 6, 9, 13 (staggered per row)
px_birch:
    mov     esi, RGB(220,220,210)
    mov     ecx, 0x2244                 ; rows 2, 6, 9, 13
    bt      ecx, r14d
    jnc     .done
    lea     eax, [r14 + r14 * 2]
    add     eax, r15d
    and     eax, 7
    cmp     eax, 3
    jae     .done
    mov     esi, RGB(36,34,32)
.done:
    ret

; bed top (r10d = 1: head): head = white sheet with a 2-px red border; foot = red blanket with a
; darker fold line 3 px inside every edge
px_bed_top:
    mov     eax, r15d                   ; eax = distance to the nearest edge
    mov     ecx, 15
    sub     ecx, r15d
    cmp     ecx, eax
    cmovb   eax, ecx
    cmp     r14d, eax
    cmovb   eax, r14d
    mov     ecx, 15
    sub     ecx, r14d
    cmp     ecx, eax
    cmovb   eax, ecx
    test    r10d, r10d
    jnz     .head
    mov     esi, RGB(170,30,30)
    cmp     eax, 3
    jne     .done
    mov     esi, RGB(120,20,20)
.done:
    ret
.head:
    mov     esi, RGB(170,30,30)
    cmp     eax, 2
    jb      .done
    mov     esi, RGB(235,235,235)
    ret

; bed side (r10d = 1: head): rows 0..8 are the red blanket (foot) or white sheet (head) with a
; darker hem on row 8, rows 9..15 repeat the planks tile 5 unshaded (m = 256 is the identity)
px_bed_side:
    cmp     r14d, 9
    jae     .planks
    test    r10d, r10d
    jnz     .white
    mov     esi, RGB(170,30,30)
    cmp     r14d, 8
    jne     .done
    mov     esi, RGB(122,20,20)
    ret
.white:
    mov     esi, RGB(235,235,235)
    cmp     r14d, 8
    jne     .done
    mov     esi, RGB(196,196,196)
.done:
    ret
.planks:
    mov     eax, r15d
    mov     edx, r14d
    mov     ecx, 5
    call    atlas_px
    mov     esi, eax
    mov     r8d, 256
    ret

section .rodata
; 0.9 bitmaps. Tall grass: seven 1-px blades (heights 9, 12, 7, 14, 8, 11, 6), dark root, light tip
pal_tallgrass:
    PAL 'd', 52, 120, 40
    PAL 'g', 72, 164, 46
    PAL 'G', 108, 188, 58
    dq 0
tallgrass_bmp:
    db "................"
    db "................"
    db "........G......."
    db "........G......."
    db "...G....g......."
    db "...G....g...G..."
    db "...g....g...G..."
    db ".G.g....g...g..."
    db ".G.g....g.G.g..."
    db ".g.g.G..g.G.g..."
    db ".g.g.G..g.g.g.G."
    db ".g.g.g..g.g.g.G."
    db ".g.d.g..d.g.g.g."
    db ".d.d.g..d.g.d.g."
    db ".d.d.d..d.d.d.d."
    db ".d.d.d..d.d.d.d."

; bed icon: side-on, red blanket and white pillow on plank legs
pal_icon_bed:
    PAL 'K', 40, 26, 14
    PAL 'W', 240, 240, 240
    PAL 'w', 200, 200, 210
    PAL 'R', 190, 36, 36
    PAL 'r', 130, 22, 22
    PAL 'P', 162, 130, 78
    PAL 'p', 110, 86, 50
    dq 0
icon_bed_bmp:
    db "................"
    db "................"
    db "................"
    db "................"
    db "..pp............"
    db "..pP............"
    db "..pPWWWWWw....."
    db "..pPWWWWWwRRRR.."
    db "..pPRRRRRRRRRRr."
    db "..pPRRRRRRRRRRr."
    db "..pPrrrrrrrrrrr."
    db "..pPPPPPPPPPPPPp"
    db "..pppppppppppppp"
    db "..pP..........pP"
    db "..pp..........pp"
    db "................"

; boat icon: side-on plank hull with raised bow and stern
pal_icon_boat:
    PAL 'K', 40, 26, 14
    PAL 'P', 162, 130, 78
    PAL 'p', 110, 86, 50
    PAL 'h', 84, 62, 22
    dq 0
icon_boat_bmp:
    db "................"
    db "................"
    db "................"
    db "................"
    db "................"
    db "...h........h..."
    db "...hp......ph..."
    db "...hP......Ph..."
    db "..hhPPPPPPPPPhh."
    db "..hPPPPPPPPPPPPh"
    db "..hpPPPPPPPPPPph"
    db "...hpPPPPPPPPph."
    db "....hppppppppp.."
    db ".....hhhhhhhh..."
    db "................"
    db "................"

; breath bubbles (9x9 HUD bitmaps): a light-blue ring with a white highlight; popping = 4 dots
pal_bubble:
    PAL 'B', 70, 130, 220
    PAL 'b', 150, 205, 255
    PAL 'w', 255, 255, 255
    dq 0
bubble_bmp:
    db "..bbbbb.."
    db ".b.....B."
    db "b..ww...B"
    db "b.w.....B"
    db "b.......B"
    db "b.......B"
    db "b.......B"
    db ".B.....B."
    db "..BBBBB.."
bubble_pop_bmp:
    db "........."
    db ".bb...bb."
    db ".bw...BB."
    db "........."
    db "........."
    db "........."
    db ".bb...BB."
    db ".bB...BB."
    db "........."

section .text
