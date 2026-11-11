; texgen.asm - procedural 256x4096 RGBA texture atlas: the 16x16 tiles (rows 0..255 and the tiles past the font),
; the 8x8 font at FONT_Y = 256. Rows ICON32_Y0.. hold the item icons (icons.asm) and rows SKIN_Y0.. the model
; skins (skin.asm): both are painted after texgen_build.
;
; texgen_build(rdi out): zero out[ATLAS_W * ATLAS_H * 4], then draw tiles in order using a single
; xorshift32 stream (state 0x12345678, x ^= x<<13; x ^= x>>17; x ^= x<<5; a "draw"
; returns the NEW state). Pixel = base*m >> 8 per channel, alpha 255. Tiles 13, 14 and the
; crack stages (256 draws first) continue the stream after tile 12; then, in this order, the ores 26..29,
; furnaces 30/31, chest 43/44, gravel 45, TNT 46/47 and the arrow tiles 73, 77, 79 follow; the HUD icons
; (48..56) use no rng. The 0.6 RPG art (stone bricks 59/60, the gold coin glyph 138, ability icons 139..150,
; class emblems 151..154, stat icons 155..172) is drawn after the arrow tiles, so it never shifts an older
; rng draw: the bricks are 16x16 bitmaps shaded by one draw per pixel, the icons are draw-free bitmaps. The
; font is painted last (white glyph texels) at atlas rows FONT_Y..FONT_Y+47.
; The 0.7 building art (tiles 15, 61..63, 180..191, 200..202, 240..253) is drawn after the 0.6 art
; and before the font: noise tiles take one draw per pixel (NFUNC), icons copy earlier tiles.
; The 0.8 icons (tiles 217..223, 232..239, 254, 255) follow the 0.7 art, draw-free bitmaps.
; The 0.9 art (the 19 tiles 192..199, 208..215, 224, 226, 227 the font left free when it moved to
; FONT_Y) follows the 0.8 icons and precedes the font, in tile order: noise tiles take one draw
; per pixel (NFUNC / NFUNCA), the bitmaps (tall grass, the bed icon, bubbles) take none.
; The 0.10 art (shrine tiles 228, 229) follows the 0.9 art and precedes the font: draw-free bitmaps.
; The 0.10.1 art (dry grass top and side 324, 325, lava 326, past the font) follows the 0.10 art and
; precedes the font: 324 and 326 are plain noise, 325 is the grass-side generator (16 column depths,
; then one draw per pixel) in dry colours.
; The 0.10.2 art (the grimoire UI: the 16 9-slice kinds 327..342, the compass 343, the empty-slot glyphs
; 344..349, the quill 351 and the silhouette block 365..447, past the font) follows the 0.10.1 art and
; precedes the font, in tile order. The UI tiles are 16x16 bitmaps (GBMP): one draw per pixel, the
; transparent ones included, and a palette entry carries its own noise mask (m = 256 - (draw & mask),
; 0 = exact colour). The silhouette is drawn by NFUNC (px_sil), one draw per pixel of each of its 18
; sub-tiles in row-major order. The HUD icons 48..56 keep their draw-free 9x9 layout; only their
; palettes and a few shade ('d') pixels are redrawn.
; The 0.10.4 art (the Marksman emblem 352, abilities 353..356 and the stat icons 230, 231) follows
; the silhouette block and precedes the font: draw-free bitmaps (BMP), so no later draw shifts.
; 0.13 "looks": the item icons are 32x32 cells now and mobs, folk, the boss, the player's arm, the boat, the
; plane and the guns are skin models, so the tiles that depicted them are no longer drawn: 32..42, 64..72,
; 74..76, 78, 80..137, 173..179, 203..207, 216, 225, 304..323, 357..362 and 368..373 are free (common.inc).
; Their rng draws went with them: the noise of every tile drawn after tile 47 differs from the 0.12 atlas.
;
; Register use inside texgen_build (leaf function, no external calls):
;   r12  = out base          r13d = rng state
;   rbx  = tile base pointer r14d = py, r15d = px
;   rdi  = current pixel pointer (set by TILE_BEGIN)
;   r8d  = per-pixel multiplier m
%include "common.inc"
%include "art.inc"
default rel

global texgen_build

extern font8x8

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

; icon with two parameters: r10d = %3, r11d = %4 (the stairs', slabs' and doors' source tiles)
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

; noise-shaded 16x16 bitmap with transparency: tile, bitmap, palette (PALN records). One rng draw per
; pixel ('.' and any char missing from the palette are transparent); m = 256 - (draw & the entry's
; noise mask), so a mask of 0 keeps the colour exact; the pixel's alpha is the entry's.
%macro GBMP 3
    TILE_BEGIN %1
    call    rng
    mov     r11d, eax                   ; this pixel's draw
    lea     r9, [%2]
    lea     r10, [%3]
    call    gbmp_px
    test    eax, eax
    jz      %$clear
    mov     esi, eax
    mov     r8d, eax
    shr     r8d, 24                     ; the entry's alpha
    and     r11d, ecx
    mov     edx, 256
    sub     edx, r11d
    call    shade
    mov     [rdi + 3], r8b
    jmp     %$next
%$clear:
    mov     dword [rdi], 0
%$next:
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

    ; ---- 73 skeleton bone (arrow steel), 77 chicken body (fletching, muzzle flash), 79 chicken leg (brass): arrows.asm, gunmodel.asm ----
    TILE_BEGIN 73
    NOISE_PIXEL RGB(200,200,200), 200, 55
    TILE_END
    TILE_BEGIN 77
    NOISE_PIXEL RGB(240,240,240), 220, 35
    TILE_END
    TILE_BEGIN 79
    NOISE_PIXEL RGB(240,180,40), 220, 35
    TILE_END

    ; ---- RPG art, all drawn after every older rng draw: 59, 60 stone bricks, mossy (bitmaps over a light rng noise) ----
    NBMP    59, brick_bmp, pal_brick, 232, 23
    NBMP    60, mossy_bmp, pal_mossy, 232, 23
    ; ---- 138 gold coin: the glyph of the XP bonus, Gold find and Magic find stats ----
    BMP     138, coin_bmp, pal_coin
    ; ---- 139..150 ability icons: Warrior Charge/War Cry/Whirlwind, (142..144 are unused: the Mage's
    ; abilities became runes), Archer Volley/Explosive Arrow/Arrow Rain, Rogue Shadowstep/Smoke Bomb/Blade Dance ----
    BMP     139, charge_bmp, pal_charge
    BMP     140, warcry_bmp, pal_warcry
    BMP     141, whirl_bmp, pal_whirl
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

    ; ---- 0.8 art (drawn after the 0.7 art, no rng, before the font; the atlas outside these 16 tiles
    ;      is untouched) ----
    ; 217, 219, 220 slot-3 abilities: Ground Slam, Hunter's Mark, Fan of Knives (218 is unused)
    BMP     217, slam_bmp, pal_slam
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

    ; ---- 0.9 art (after the 0.8 icons, before the font; the atlas outside these 19 tiles is
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
    ; 224 bed icon; 226, 227 breath bubble, popping bubble
    BMP     224, icon_bed_bmp, pal_icon_bed
    HUD     226, bubble_bmp, pal_bubble, pal_bubble, 0
    HUD     227, bubble_pop_bmp, pal_bubble, pal_bubble, 0

    ; ---- 0.10 art (after the 0.9 art, before the font; the atlas outside these 2 tiles is
    ;      untouched). 228, 229 shrine top and side: draw-free bitmaps (every char is in the
    ;      palette: block tiles must be opaque). ----
    BMP     228, shrine_top_bmp, pal_shrine_top
    BMP     229, shrine_side_bmp, pal_shrine_side

    ; ---- 0.10.1 art (after the 0.10 art, before the font; the atlas outside these 3 tiles is
    ;      untouched). 324 dry grass top, 325 dry grass side (the tile 2 generator with the dry
    ;      colour: 16 column depths first, then one draw per pixel), 326 lava (opaque). ----
    TILE_BEGIN 324
    NOISE_PIXEL RGB(170,160,82), 192, 63
    TILE_END

    xor     r15d, r15d
.t325_depth:
    call    rng
    mov     edx, eax
    and     edx, 1
    add     edx, 3
    test    eax, 7
    jnz     .t325_store
    add     edx, 2
.t325_store:
    mov     [rsp + r15], dl
    inc     r15d
    cmp     r15d, 16
    jb      .t325_depth
    TILE_BEGIN 325
    DRAW_M  192, 63
    movzx   eax, byte [rsp + r15]
    mov     esi, RGB(150,108,74)
    cmp     r14d, eax
    jae     .t325_shade
    mov     esi, RGB(170,160,82)
.t325_shade:
    mov     edx, r8d
    call    shade
    TILE_END

    TILE_BEGIN 326
    NOISE_PIXEL RGB(214,96,26), 160, 95
    TILE_END

    ; ---- 0.10.2 grimoire art (after the 0.10.1 art, before the font; the atlas outside these tiles
    ;      is untouched, the HUD icons 48..56 are redrawn in place by their palettes). 327..342 the
    ;      NINE_* kinds, 343 compass, 344..349 empty-slot glyphs, 351 quill: GBMP bitmaps in tile
    ;      order; then the 18 silhouette sub-tiles 365.. in row-major order ----
    GBMP    327, gr_page_bmp, pal_gr_page
    GBMP    328, gr_leather_bmp, pal_gr_leather
    GBMP    329, gr_slot_bmp, pal_gr_slot
    GBMP    330, gr_button_bmp, pal_gr_button
    GBMP    331, gr_button_hot_bmp, pal_gr_button_hot
    GBMP    332, gr_button_off_bmp, pal_gr_button_off
    GBMP    333, gr_tooltip_bmp, pal_gr_tooltip
    GBMP    334, gr_ribbon_bmp, pal_gr_ribbon
    GBMP    335, gr_bar_bmp, pal_gr_bar
    GBMP    336, gr_rune_bmp, pal_gr_rune
    GBMP    337, gr_select_bmp, pal_gr_select
    GBMP    338, gr_note_bmp, pal_gr_note
    GBMP    339, gr_node_stat_bmp, pal_gr_node_stat
    GBMP    340, gr_node_abil_bmp, pal_gr_node_abil
    GBMP    341, gr_node_key_bmp, pal_gr_node_key
    GBMP    342, gr_node_path_bmp, pal_gr_node_path
    GBMP    343, gr_compass_bmp, pal_gr_compass
    GBMP    344, gr_slot_head_bmp, pal_gr_slot_head
    GBMP    345, gr_slot_chest_bmp, pal_gr_slot_chest
    GBMP    346, gr_slot_legs_bmp, pal_gr_slot_legs
    GBMP    347, gr_slot_feet_bmp, pal_gr_slot_feet
    GBMP    348, gr_slot_ring_bmp, pal_gr_slot_ring
    GBMP    349, gr_slot_amulet_bmp, pal_gr_slot_amulet
    GBMP    351, gr_quill_bmp, pal_gr_quill
%assign sil_r 0
%rep 6
%assign sil_c 0
%rep 3
    NFUNC   TILE_SIL0 + 16 * sil_r + sil_c, 224, 31, 0, px_sil, 16 * sil_c, 16 * sil_r
%assign sil_c sil_c + 1
%endrep
%assign sil_r sil_r + 1
%endrep

    ; ---- 0.10.4 Marksman art (draw-free bitmaps: no rng draw, so nothing after them shifts): 352 path
    ;      emblem, 353..356 Powder Grenade / Bullseye / Fan the Hammer / Flashbang, 230 and 231 the gun
    ;      damage and reload speed stat icons ----
    BMP     352, mk_emblem_bmp, pal_mk_emblem
    BMP     353, mk_grenade_bmp, pal_mk_grenade
    BMP     354, mk_bullseye_bmp, pal_mk_bullseye
    BMP     355, mk_fanhammer_bmp, pal_mk_fanhammer
    BMP     356, mk_flashbang_bmp, pal_mk_flashbang
    BMP     230, mk_st_gun_bmp, pal_mk_st_gun
    BMP     231, mk_st_reload_bmp, pal_mk_st_reload

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
; Per-pixel icon routines. In: r15d = px, r14d = py (r10d/r11d = the parameters of the ICONT
; macro). Out: eax = packed RGBA (0 = transparent). They never touch
; rdi, rbx, r12-r15, so TILE_BEGIN's loop survives the call.
; ---------------------------------------------------------------------------

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

; 16x16 bitmap pixel with noise: bmp_px for PALN records. Out: eax = packed RGBA (0 = the char is not
; in the palette: transparent), ecx = the entry's noise mask.
gbmp_px:
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
    movzx   ecx, byte [rdx + 1]
    mov     eax, [rdx + 4]
    ret
.none:
    xor     eax, eax
    ret

; silhouette pixel (NFUNC func). The 3 x 6 tile block TILE_SIL0 is one 48 x 96 figure in local
; coordinates x = r10d + px, y = r11d + py (r10d = 16 * the sub-tile's column, r11d = 16 * its row).
; Out: esi = base colour, 0 = outside the figure. A figure pixel with a 4-neighbour outside the
; figure is exactly C_INK (r8d = 256, no noise); the rest is parchment RGB(214, 190, 146) with the
; multiplier NFUNC left in r8d. Clobbers eax, ecx, edx.
px_sil:
    lea     ecx, [r10 + r15]
    lea     edx, [r11 + r14]
    call    sil_in
    test    eax, eax
    jz      .none
    dec     ecx
    call    sil_in                      ; left neighbour
    inc     ecx
    test    eax, eax
    jz      .edge
    inc     ecx
    call    sil_in                      ; right
    dec     ecx
    test    eax, eax
    jz      .edge
    dec     edx
    call    sil_in                      ; up
    inc     edx
    test    eax, eax
    jz      .edge
    inc     edx
    call    sil_in                      ; down
    dec     edx
    test    eax, eax
    jz      .edge
    mov     esi, RGB(214,190,146)
    ret
.edge:
    mov     esi, RGB(58,38,24)
    mov     r8d, 256
    ret
.none:
    xor     esi, esi
    ret

; sil_in(ecx x, edx y) -> eax 1 inside the figure, 0 outside (also outside the 48 x 96 block). Keeps
; ecx and edx, clobbers esi. The figure is the union of:
;   head ellipse centre (24, 12), rx 8, ry 9; neck x 21..26, y 20..23;
;   torso y 23..52, x 13..34 narrowing linearly to 16..31 (inset (3 (y - 23) + 14) / 29 per side);
;   arms: the quad (12,24)-(16,24)-(11,56)-(7,56) sampled at pixel centres, and its mirror x -> 47 - x;
;   hands: circles r 3 at (9, 58) and (38, 58); legs x 16..22 and 25..31, y 52..88;
;   feet x 14..22 and 25..33, y 88..93.
sil_in:
    cmp     ecx, 47
    ja      .out                        ; unsigned: also x < 0
    cmp     edx, 95
    ja      .out
    lea     eax, [rcx - 24]             ; head: 81 dx^2 + 64 dy^2 <= 64 * 81
    imul    eax, eax
    imul    eax, 81
    lea     esi, [rdx - 12]
    imul    esi, esi
    imul    esi, 64
    add     eax, esi
    cmp     eax, 64 * 81
    jbe     .in
    lea     eax, [rcx - 21]             ; neck
    cmp     eax, 5
    ja      .torso
    lea     eax, [rdx - 20]
    cmp     eax, 3
    jbe     .in
.torso:
    lea     eax, [rdx - 23]
    cmp     eax, 29
    ja      .arms
    lea     rsi, [sil_inset]
    movzx   esi, byte [rsi + rax]
    lea     eax, [rsi + 13]
    cmp     ecx, eax
    jl      .arms
    neg     esi
    add     esi, 34
    cmp     ecx, esi
    jle     .in
.arms:
    lea     eax, [rdx - 24]             ; y 24..55: 64 x within [736 - s, 992 - s], s = 10 (y - 24) + 5
    cmp     eax, 31
    ja      .hands
    lea     eax, [rax + rax*4]
    add     eax, eax
    add     eax, 5
    mov     esi, 736
    sub     esi, eax                    ; lo
    neg     eax
    add     eax, 992                    ; hi
    push    rcx
    shl     ecx, 6
    cmp     ecx, esi
    jl      .arm_mirror
    cmp     ecx, eax
    jle     .arm_hit
.arm_mirror:
    neg     ecx
    add     ecx, 47 * 64                ; 64 (47 - x)
    cmp     ecx, esi
    jl      .arm_miss
    cmp     ecx, eax
    jg      .arm_miss
.arm_hit:
    pop     rcx
    jmp     .in
.arm_miss:
    pop     rcx
.hands:
    lea     eax, [rdx - 58]
    imul    eax, eax
    lea     esi, [rcx - 9]
    imul    esi, esi
    add     esi, eax
    cmp     esi, 9
    jbe     .in
    lea     esi, [rcx - 38]
    imul    esi, esi
    add     esi, eax
    cmp     esi, 9
    jbe     .in
    lea     eax, [rdx - 52]             ; legs
    cmp     eax, 36
    ja      .feet
    lea     eax, [rcx - 16]
    cmp     eax, 6
    jbe     .in
    lea     eax, [rcx - 25]
    cmp     eax, 6
    jbe     .in
.feet:
    lea     eax, [rdx - 88]
    cmp     eax, 5
    ja      .out
    lea     eax, [rcx - 14]
    cmp     eax, 8
    jbe     .in
    lea     eax, [rcx - 25]
    cmp     eax, 8
    jbe     .in
.out:
    xor     eax, eax
    ret
.in:
    mov     eax, 1
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

section .rodata
; 0.10.2: the 9x9 HUD icons keep their layout; the palette is the grimoire's (ink outline RGB(58,38,24),
; the 'd' shade on the lower right is new)
heart_pal_full:
    PAL 'K', 58, 38, 24
    PAL 'r', 204, 40, 44
    PAL 'd', 150, 24, 32
    PAL 'w', 255, 196, 180
    dq 0
heart_pal_empty:
    PAL 'K', 58, 38, 24
    PAL 'r', 92, 48, 44
    PAL 'd', 74, 38, 36
    PAL 'w', 92, 48, 44
    dq 0
food_pal_full:
    PAL 'K', 58, 38, 24
    PAL 'm', 200, 120, 50
    PAL 'd', 150, 86, 38
    PAL 'w', 240, 184, 112
    PAL 'b', 244, 232, 200
    dq 0
food_pal_empty:
    PAL 'K', 58, 38, 24
    PAL 'm', 80, 56, 40
    PAL 'd', 64, 44, 32
    PAL 'w', 80, 56, 40
    PAL 'b', 130, 116, 96
    dq 0

heart_bmp:
    db ".KKK.KKK."
    db "KrrrKrrrK"
    db "KrwrrrrdK"
    db "KrrrrrrdK"
    db ".KrrrrdK."
    db "..KrrdK.."
    db "...KdK..."
    db "....K...."
    db "........."
food_bmp:
    db "....KKK.."
    db "...KmmmK."
    db "..KmmwmmK"
    db "..KmmmmdK"
    db "...KmmdK."
    db "..KbKKK.."
    db ".KbK....."
    db "KbbK....."
    db ".KK......"

armor_pal_full:
    PAL 'K', 58, 38, 24
    PAL 'm', 178, 186, 200
    PAL 'd', 120, 128, 144
    PAL 'L', 244, 238, 222
    dq 0
armor_pal_empty:
    PAL 'K', 58, 38, 24
    PAL 'm', 84, 76, 70
    PAL 'd', 66, 60, 56
    PAL 'L', 84, 76, 70
    dq 0
armor_bmp:
    db ".KK...KK."
    db "KmLK.KmdK"
    db "KmmmKmmdK"
    db ".KmmmmdK."
    db ".KmmmmdK."
    db ".KmmmmdK."
    db ".KKKKKKK."
    db "........."
    db "........."

; fire flames (tiles 57, 58)
pal_fire:
    PAL 'Y', 255, 230, 90
    PAL 'O', 250, 140, 30
    PAL 'R', 200, 50, 20
    dq 0
gravel_cols:
    dd RGB(118,110,106), RGB(146,138,134), RGB(92,88,86), RGB(166,156,146)

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

; ---- RPG art (tiles 59, 60 and 138..172): 16x16 bitmaps, palettes as for the icons above ----
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

; ---- 0.8 icons: slot-3 ability icons (217..220), attributes (221..223, 232), elements (233..236),
;      stat icons (237..239, 254), keystone (255). ----
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

; 0.10 shrine top: a gold rune ring on grey stone (every char is in the palette)
pal_shrine_top:
    PAL '#', 88, 88, 96
    PAL '.', 122, 122, 128
    PAL ',', 110, 110, 117
    PAL 'o', 240, 196, 64
    PAL 'r', 200, 150, 40
    dq 0
shrine_top_bmp:
    db "################"
    db "#.,............#"
    db "#....oooooo....#"
    db "#...ooo..ooo...#"
    db "#..oo..,...oo..#"
    db "#.oo........oo.#"
    db "#.oo...rr...oo.#"
    db "#.o...rrrr...o.#"
    db "#.o...rrrr...o.#"
    db "#.oo...rr...oo.#"
    db "#.oo.,......oo.#"
    db "#..oo......oo..#"
    db "#...ooo..ooo...#"
    db "#....oooooo....#"
    db "#.............,#"
    db "################"
; 0.10 shrine side: stone brick with a glowing amber rune (algiz) and its halo
pal_shrine_side:
    PAL 'b', 118, 118, 124
    PAL 'B', 132, 132, 138
    PAL 'm', 78, 78, 86
    PAL 'a', 140, 92, 36
    PAL 'A', 255, 176, 48
    dq 0
shrine_side_bmp:
    db "bbbbbbbmbbbbbbbm"
    db "bbBbbabmbbabbbbm"
    db "bbbbaAambaAabbbm"
    db "mmmmmaAaaAammmmm"
    db "bbbmbbaAAabmbbbb"
    db "bbbmbbaAAabmbBbb"
    db "bbbmbbaAAabmbbbb"
    db "mmmmmmaAAammmmmm"
    db "bbbbbbaAAabbbbbm"
    db "bbbBbbaAAabbbbbm"
    db "bbbbbbaAAabbbbbm"
    db "mmmmmmaAAammmmmm"
    db "bbbmbaAAAAambbbb"
    db "bbbmbbaaaabmbbbb"
    db "bbbmbbbbBbbmbbbb"
    db "mmmmmmmmmmmmmmmm"

; ---- 0.10.2 grimoire art data: sil_inset = (3 t + 14) / 29 for the torso row t = y - 23 (0..29) ----
sil_inset:
%assign sil_t 0
%rep 30
    db (3 * sil_t + 14) / 29
%assign sil_t sil_t + 1
%endrep
; 327 NINE_PAGE (b 4): ink rim, gold rule, 2 px darker margin, gold dot in each corner, 8x8 parchment noise centre
pal_gr_page:
    PALN    'd', 212, 186, 140, 15
    PALN    'g', 214, 170, 70, 0
    PALN    'p', 240, 222, 178, 31
    PALN    'G', 255, 214, 110, 0
    PALN    'K', 58, 38, 24, 0
    dq 0
gr_page_bmp:
    db ".KKKKKKKKKKKKKK."
    db "KKggggggggggggKK"
    db "KgddddddddddddgK"
    db "KgdGddddddddGdgK"
    db "KgddppppppppddgK"
    db "KgddppppppppddgK"
    db "KgddppppppppddgK"
    db "KgddppppppppddgK"
    db "KgddppppppppddgK"
    db "KgddppppppppddgK"
    db "KgddppppppppddgK"
    db "KgddppppppppddgK"
    db "KgdGddddddddGdgK"
    db "KgddddddddddddgK"
    db "KKggggggggggggKK"
    db ".KKKKKKKKKKKKKK."
; 328 NINE_LEATHER (b 4): brown leather, rim, dashed cream stitch (every other texel) 2 px inside the rim
pal_gr_leather:
    PALN    'l', 104, 66, 38, 23
    PALN    'D', 50, 30, 18, 0
    PALN    'L', 138, 92, 54, 0
    PALN    'S', 236, 220, 176, 0
    dq 0
gr_leather_bmp:
    db ".DDDDDDDDDDDDDD."
    db "DLLLLLLLLLLLLLLD"
    db "DLSlSlSlSlSllSLD"
    db "DLllllllllllllLD"
    db "DLSllllllllllSLD"
    db "DLllllllllllllLD"
    db "DLSllllllllllSLD"
    db "DLllllllllllllLD"
    db "DLSllllllllllSLD"
    db "DLllllllllllllLD"
    db "DLSllllllllllSLD"
    db "DLllllllllllllLD"
    db "DLllllllllllllLD"
    db "DLSlSlSlSlSllSLD"
    db "DLLLLLLLLLLLLLLD"
    db ".DDDDDDDDDDDDDD."
; 329 NINE_SLOT (b 2): recessed parchment cell, ink rim, 1 px top-left inner shadow, light bottom-right edge
pal_gr_slot:
    PALN    'e', 234, 216, 174, 0
    PALN    'q', 218, 194, 150, 15
    PALN    's', 176, 148, 106, 0
    PALN    'K', 58, 38, 24, 0
    dq 0
gr_slot_bmp:
    db "KKKKKKKKKKKKKKKK"
    db "KssssssssssssssK"
    db "KsqqqqqqqqqqqqeK"
    db "KsqqqqqqqqqqqqeK"
    db "KsqqqqqqqqqqqqeK"
    db "KsqqqqqqqqqqqqeK"
    db "KsqqqqqqqqqqqqeK"
    db "KsqqqqqqqqqqqqeK"
    db "KsqqqqqqqqqqqqeK"
    db "KsqqqqqqqqqqqqeK"
    db "KsqqqqqqqqqqqqeK"
    db "KsqqqqqqqqqqqqeK"
    db "KsqqqqqqqqqqqqeK"
    db "KsqqqqqqqqqqqqeK"
    db "KseeeeeeeeeeeeeK"
    db "KKKKKKKKKKKKKKKK"
; 330 NINE_BUTTON (b 3): light parchment plate, gold rim inside the ink rim
pal_gr_button:
    PALN    'd', 212, 186, 140, 15
    PALN    'g', 214, 170, 70, 0
    PALN    'K', 58, 38, 24, 0
    PALN    'P', 250, 238, 206, 15
    dq 0
gr_button_bmp:
    db ".KKKKKKKKKKKKKK."
    db "KggggggggggggggK"
    db "KgPPPPPPPPPPPPgK"
    db "KgPPPPPPPPPPPPgK"
    db "KgPPPPPPPPPPPPgK"
    db "KgPPPPPPPPPPPPgK"
    db "KgPPPPPPPPPPPPgK"
    db "KgPPPPPPPPPPPPgK"
    db "KgPPPPPPPPPPPPgK"
    db "KgPPPPPPPPPPPPgK"
    db "KgPPPPPPPPPPPPgK"
    db "KgPPPPPPPPPPPPgK"
    db "KgPPPPPPPPPPPPgK"
    db "KgddddddddddddgK"
    db "KggggggggggggggK"
    db ".KKKKKKKKKKKKKK."
; 331 NINE_BUTTON_HOT (b 3): brighter plate, 2 px gold rim
pal_gr_button_hot:
    PALN    'g', 214, 170, 70, 0
    PALN    'G', 255, 214, 110, 0
    PALN    'K', 58, 38, 24, 0
    PALN    'P', 250, 238, 206, 15
    dq 0
gr_button_hot_bmp:
    db ".KKKKKKKKKKKKKK."
    db "KggggggggggggggK"
    db "KgGGGGGGGGGGGGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGGGGGGGGGGGGgK"
    db "KggggggggggggggK"
    db ".KKKKKKKKKKKKKK."
; 332 NINE_BUTTON_OFF (b 3): greyed parchment, ink-soft rim
pal_gr_button_off:
    PALN    'd', 212, 186, 140, 15
    PALN    'k', 110, 84, 58, 0
    PALN    'q', 218, 194, 150, 15
    dq 0
gr_button_off_bmp:
    db ".kkkkkkkkkkkkkk."
    db "kddddddddddddddk"
    db "kdqqqqqqqqqqqqdk"
    db "kdqqqqqqqqqqqqdk"
    db "kdqqqqqqqqqqqqdk"
    db "kdqqqqqqqqqqqqdk"
    db "kdqqqqqqqqqqqqdk"
    db "kdqqqqqqqqqqqqdk"
    db "kdqqqqqqqqqqqqdk"
    db "kdqqqqqqqqqqqqdk"
    db "kdqqqqqqqqqqqqdk"
    db "kdqqqqqqqqqqqqdk"
    db "kdqqqqqqqqqqqqdk"
    db "kdqqqqqqqqqqqqdk"
    db "kddddddddddddddk"
    db ".kkkkkkkkkkkkkk."
; 333 NINE_TOOLTIP (b 3): dark umber page with a 1 px gold rim
pal_gr_tooltip:
    PALN    'g', 214, 170, 70, 0
    PALN    'u', 46, 30, 20, 7
    PALN    'Z', 28, 18, 10, 0
    dq 0
gr_tooltip_bmp:
    db ".ZZZZZZZZZZZZZZ."
    db "ZggggggggggggggZ"
    db "ZguuuuuuuuuuuugZ"
    db "ZguuuuuuuuuuuugZ"
    db "ZguuuuuuuuuuuugZ"
    db "ZguuuuuuuuuuuugZ"
    db "ZguuuuuuuuuuuugZ"
    db "ZguuuuuuuuuuuugZ"
    db "ZguuuuuuuuuuuugZ"
    db "ZguuuuuuuuuuuugZ"
    db "ZguuuuuuuuuuuugZ"
    db "ZguuuuuuuuuuuugZ"
    db "ZguuuuuuuuuuuugZ"
    db "ZguuuuuuuuuuuugZ"
    db "ZggggggggggggggZ"
    db ".ZZZZZZZZZZZZZZ."
; 334 NINE_RIBBON (b 4): crimson ribbon, gold trim lines, swallowtail notch (x 0..2, rows 4..11, chamfered) on both ends
pal_gr_ribbon:
    PALN    'g', 214, 170, 70, 0
    PALN    'h', 214, 76, 62, 0
    PALN    'x', 122, 22, 24, 0
    PALN    'C', 176, 38, 34, 0
    PALN    'O', 78, 14, 16, 0
    dq 0
gr_ribbon_bmp:
    db ".OOOOOOOOOOOOOO."
    db "OggggggggggggggO"
    db "OhhhhhhhhhhhhhhO"
    db ".OOCCCCCCCCCCOO."
    db "...OCCCCCCCCO..."
    db "...OCCCCCCCCO..."
    db "...OCCCCCCCCO..."
    db "...OCCCCCCCCO..."
    db "...OCCCCCCCCO..."
    db "...OCCCCCCCCO..."
    db "...OCCCCCCCCO..."
    db "...OCCCCCCCCO..."
    db ".OOCCCCCCCCCCOO."
    db "OxxxxxxxxxxxxxxO"
    db "OggggggggggggggO"
    db ".OOOOOOOOOOOOOO."
; 335 NINE_BAR (b 2): bar frame, 1 px ink and 1 px translucent gold (alpha 150), transparent centre
pal_gr_bar:
    PALN    'j', 214, 170, 70, 0, 150
    PALN    'K', 58, 38, 24, 0
    dq 0
gr_bar_bmp:
    db "KKKKKKKKKKKKKKKK"
    db "KjjjjjjjjjjjjjjK"
    db "Kj............jK"
    db "Kj............jK"
    db "Kj............jK"
    db "Kj............jK"
    db "Kj............jK"
    db "Kj............jK"
    db "Kj............jK"
    db "Kj............jK"
    db "Kj............jK"
    db "Kj............jK"
    db "Kj............jK"
    db "Kj............jK"
    db "KjjjjjjjjjjjjjjK"
    db "KKKKKKKKKKKKKKKK"
; 336 NINE_RUNE (b 3): blue-grey carved stone, light top-left and dark bottom-right bevel
pal_gr_rune:
    PALN    'a', 94, 108, 130, 15
    PALN    'A', 150, 164, 186, 0
    PALN    'B', 56, 64, 82, 0
    PALN    'Y', 30, 36, 50, 0
    dq 0
gr_rune_bmp:
    db ".YYYYYYYYYYYYYY."
    db "YAAAAAAAAAAAAAAY"
    db "YAAaaaaaaaaaaBBY"
    db "YAaaaaaaaaaaaaBY"
    db "YAaaaaaaaaaaaaBY"
    db "YAaaaaaaaaaaaaBY"
    db "YAaaaaaaaaaaaaBY"
    db "YAaaaaaaaaaaaaBY"
    db "YAaaaaaaaaaaaaBY"
    db "YAaaaaaaaaaaaaBY"
    db "YAaaaaaaaaaaaaBY"
    db "YAaaaaaaaaaaaaBY"
    db "YAaaaaaaaaaaaaBY"
    db "YABaaaaaaaaaaBBY"
    db "YABBBBBBBBBBBBBY"
    db ".YYYYYYYYYYYYYY."
; 337 NINE_SELECT (b 3): ornate gold frame, cream corner studs, transparent centre
pal_gr_select:
    PALN    'c', 244, 232, 200, 0
    PALN    'g', 214, 170, 70, 0
    PALN    'G', 255, 214, 110, 0
    PALN    'K', 58, 38, 24, 0
    dq 0
gr_select_bmp:
    db ".KKKKKKKKKKKKKK."
    db "KggggggggggggggK"
    db "KgcGGGGGGGGGGcgK"
    db "KgG..........GgK"
    db "KgG..........GgK"
    db "KgG..........GgK"
    db "KgG..........GgK"
    db "KgG..........GgK"
    db "KgG..........GgK"
    db "KgG..........GgK"
    db "KgG..........GgK"
    db "KgG..........GgK"
    db "KgG..........GgK"
    db "KgcGGGGGGGGGGcgK"
    db "KggggggggggggggK"
    db ".KKKKKKKKKKKKKK."
; 338 NINE_NOTE (b 3): small pinned paper note, rubric pin in the top-left corner
pal_gr_note:
    PALN    'd', 212, 186, 140, 15
    PALN    'k', 110, 84, 58, 0
    PALN    'r', 150, 32, 28, 0
    PALN    'P', 250, 238, 206, 15
    dq 0
gr_note_bmp:
    db ".kkkkkkkkkkkkkk."
    db "krPPPPPPPPPPPPdk"
    db "kPPPPPPPPPPPPPdk"
    db "kPPPPPPPPPPPPPdk"
    db "kPPPPPPPPPPPPPdk"
    db "kPPPPPPPPPPPPPdk"
    db "kPPPPPPPPPPPPPdk"
    db "kPPPPPPPPPPPPPdk"
    db "kPPPPPPPPPPPPPdk"
    db "kPPPPPPPPPPPPPdk"
    db "kPPPPPPPPPPPPPdk"
    db "kPPPPPPPPPPPPPdk"
    db "kPPPPPPPPPPPPPdk"
    db "kPPPPPPPPPPPPPdk"
    db "kddddddddddddddk"
    db ".kkkkkkkkkkkkkk."
; 339 NINE_NODE_STAT (b 5): round ink medallion on parchment
pal_gr_node_stat:
    PALN    'e', 234, 216, 174, 0
    PALN    'K', 58, 38, 24, 0
    PALN    'P', 250, 238, 206, 15
    dq 0
gr_node_stat_bmp:
    db ".....KKKKKK....."
    db "...KKKKKKKKKK..."
    db "..KKKeeeeeeKKK.."
    db ".KKeePPPPPPeeKK."
    db ".KKePPPPPPPPeKK."
    db "KKePPPPPPPPPPeKK"
    db "KKePPPPPPPPPPeKK"
    db "KKePPPPPPPPPPeKK"
    db "KKePPPPPPPPPPeKK"
    db "KKePPPPPPPPPPeKK"
    db "KKePPPPPPPPPPeKK"
    db ".KKePPPPPPPPeKK."
    db ".KKeePPPPPPeeKK."
    db "..KKKeeeeeeKKK.."
    db "...KKKKKKKKKK..."
    db ".....KKKKKK....."
; 340 NINE_NODE_ABIL (b 5): gold-rimmed shield
pal_gr_node_abil:
    PALN    'g', 214, 170, 70, 0
    PALN    'G', 255, 214, 110, 0
    PALN    'K', 58, 38, 24, 0
    PALN    'P', 250, 238, 206, 15
    dq 0
gr_node_abil_bmp:
    db "..KKKKKKKKKKKK.."
    db ".KggggggggggggK."
    db "KgGGGGGGGGGGGGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db "KgGPPPPPPPPPPGgK"
    db ".KgGPPPPPPPPGgK."
    db "..KgGPPPPPPGgK.."
    db "...KgGGGGGGgK..."
    db "....KggggggK...."
    db ".....KKKKKK....."
; 341 NINE_NODE_KEY (b 5): crimson frame with gold star corners
pal_gr_node_key:
    PALN    'g', 214, 170, 70, 0
    PALN    'x', 122, 22, 24, 0
    PALN    'G', 255, 214, 110, 0
    PALN    'K', 58, 38, 24, 0
    PALN    'P', 250, 238, 206, 15
    PALN    'R', 186, 44, 38, 0
    dq 0
gr_node_key_bmp:
    db ".gKKKKKKKKKKKKg."
    db "gGgKRRRRRRRRKgGg"
    db "KgKxxxxxxxxxxKgK"
    db "KKxPPPPPPPPPPxKK"
    db "KRxPPPPPPPPPPxRK"
    db "KRxPPPPPPPPPPxRK"
    db "KRxPPPPPPPPPPxRK"
    db "KRxPPPPPPPPPPxRK"
    db "KRxPPPPPPPPPPxRK"
    db "KRxPPPPPPPPPPxRK"
    db "KRxPPPPPPPPPPxRK"
    db "KRxPPPPPPPPPPxRK"
    db "KKxPPPPPPPPPPxKK"
    db "KgKxxxxxxxxxxKgK"
    db "gGgKRRRRRRRRKgGg"
    db ".gKKKKKKKKKKKKg."
; 342 NINE_NODE_PATH (b 5): double gold ring (archetype path)
pal_gr_node_path:
    PALN    'g', 214, 170, 70, 0
    PALN    'n', 70, 48, 32, 0
    PALN    'G', 255, 214, 110, 0
    PALN    'K', 58, 38, 24, 0
    PALN    'P', 250, 238, 206, 15
    dq 0
gr_node_path_bmp:
    db ".....KKKKKK....."
    db "...KKggggggKK..."
    db "..KggnnnnnnggK.."
    db ".KgnnGGGGGGnngK."
    db ".KgnGKKKKKKGngK."
    db "KgnGKPPPPPPKGngK"
    db "KgnGKPPPPPPKGngK"
    db "KgnGKPPPPPPKGngK"
    db "KgnGKPPPPPPKGngK"
    db "KgnGKPPPPPPKGngK"
    db "KgnGKPPPPPPKGngK"
    db ".KgnGKKKKKKGngK."
    db ".KgnnGGGGGGnngK."
    db "..KggnnnnnnggK.."
    db "...KKggggggKK..."
    db ".....KKKKKK....."
; 343 TILE_COMPASS: gold compass rose, drawn 2:1 at 32 x 32 GUI units
pal_gr_compass:
    PALN    'g', 214, 170, 70, 0
    PALN    'r', 150, 32, 28, 0
    PALN    'G', 255, 214, 110, 0
    PALN    'K', 58, 38, 24, 0
    PALN    'M', 188, 148, 56, 0
    dq 0
gr_compass_bmp:
    db "................"
    db ".......KK......."
    db ".....MMKKMM....."
    db "....MMKGgKMM...."
    db "...MK.KGgK.KM..."
    db "..MM.KGGggK.MM.."
    db "..MKKGGGggGKKM.."
    db ".KKGGGGrrGGGGKK."
    db ".KKggggrrggggKK."
    db "..MKKggGgggKKM.."
    db "..MM.KGGggK.MM.."
    db "...MK.KGgK.KM..."
    db "....MMKGgKMM...."
    db ".....MMKKMM....."
    db ".......KK......."
    db "................"
; 344 TILE_SLOT_HEAD: empty-slot glyph, white (the UI tints it C_INK_SOFT) with a light-grey shade
pal_gr_slot_head:
    PALN    'v', 204, 204, 204, 0
    PALN    'w', 255, 255, 255, 0
    dq 0
gr_slot_head_bmp:
    db "................"
    db ".......ww......."
    db ".....wwwwww....."
    db "....wwwwwwww...."
    db "...wwwwwwwwww..."
    db "...wwwwwwwwww..."
    db "...wvvvvvvvvw..."
    db "...wvvvvvvvvw..."
    db "...wwwwwwwwww..."
    db "...wwwwwwwwww..."
    db "...wwwwwwwwww..."
    db "...wwww..wwww..."
    db "...www....www..."
    db "................"
    db "................"
    db "................"
; 345 TILE_SLOT_CHEST: empty-slot glyph
pal_gr_slot_chest:
    PALN    'v', 204, 204, 204, 0
    PALN    'w', 255, 255, 255, 0
    dq 0
gr_slot_chest_bmp:
    db "................"
    db "..www......www.."
    db ".wwwww....wwwww."
    db ".wwwwwwwwwwwwww."
    db ".wwwwwwwwwwwwww."
    db "..wwwwwvvwwwww.."
    db "..wwwwwvvwwwww.."
    db "..wwwwwvvwwwww.."
    db "..wwwwwvvwwwww.."
    db "..wwwwwwwwwwww.."
    db "..wwwwwwwwwwww.."
    db "...wwwwwwwwww..."
    db "...wwwwwwwwww..."
    db "...wwwwwwwwww..."
    db "................"
    db "................"
; 346 TILE_SLOT_LEGS: empty-slot glyph
pal_gr_slot_legs:
    PALN    'v', 204, 204, 204, 0
    PALN    'w', 255, 255, 255, 0
    dq 0
gr_slot_legs_bmp:
    db "................"
    db "...wwwwwwwwww..."
    db "...vvvvvvvvvv..."
    db "...wwwwwwwwww..."
    db "...wwwwwwwwww..."
    db "...wwwwwwwwww..."
    db "...wwwww.wwww..."
    db "...wwww..wwww..."
    db "...wwww..wwww..."
    db "...wwww..wwww..."
    db "...wwww..wwww..."
    db "...wwww..wwww..."
    db "...wwww..wwww..."
    db "................"
    db "................"
    db "................"
; 347 TILE_SLOT_FEET: empty-slot glyph
pal_gr_slot_feet:
    PALN    'v', 204, 204, 204, 0
    PALN    'w', 255, 255, 255, 0
    dq 0
gr_slot_feet_bmp:
    db "................"
    db "................"
    db "..www....www...."
    db "..www....www...."
    db "..www....www...."
    db "..www....www...."
    db "..www....www...."
    db "..wwww...wwww..."
    db "..wwwww..wwwww.."
    db ".wwwwwww.wwwwwww"
    db ".wwwwwww.wwwwwww"
    db ".vvvvvvv.vvvvvvv"
    db "................"
    db "................"
    db "................"
    db "................"
; 348 TILE_SLOT_RING: empty-slot glyph
pal_gr_slot_ring:
    PALN    'w', 255, 255, 255, 0
    dq 0
gr_slot_ring_bmp:
    db "................"
    db ".......ww......."
    db "......wwww......"
    db ".......ww......."
    db "......wwww......"
    db ".....ww..ww....."
    db "....ww....ww...."
    db "...ww......ww..."
    db "...ww......ww..."
    db "...ww......ww..."
    db "....ww....ww...."
    db ".....wwwwww....."
    db "................"
    db "................"
    db "................"
    db "................"
; 349 TILE_SLOT_AMULET: empty-slot glyph
pal_gr_slot_amulet:
    PALN    'v', 204, 204, 204, 0
    PALN    'w', 255, 255, 255, 0
    dq 0
gr_slot_amulet_bmp:
    db "................"
    db "..w..........w.."
    db "..w..........w.."
    db "...w........w..."
    db "...w........w..."
    db "....w......w...."
    db ".....w....w....."
    db ".....w....w....."
    db "......wwww......"
    db ".....wwwwww....."
    db ".....wwvvww....."
    db ".....wwvvww....."
    db "......wwww......"
    db ".......ww......."
    db "................"
    db "................"
; 351 TILE_QUILL: crimson quill, a 12 x 12 sprite spread over the tile so that ui_tile_icon at size 12
; (nearest, uv inset 1/16 texel) samples texels 0,2,3,4,6,7,8,9,11,12,13,15 of each axis and shows it
; exactly; texels 1, 5, 10, 14 copy a neighbour
pal_gr_quill:
    PALN    'h', 214, 76, 62, 0
    PALN    'x', 122, 22, 24, 0
    PALN    'C', 176, 38, 34, 0
    PALN    'K', 58, 38, 24, 0
    dq 0
gr_quill_bmp:
    db "...........xxxxK"
    db ".........xxhhKK."
    db ".........xxhhKK."
    db "........xhhCKxx."
    db ".......xhCCKx..."
    db ".....xxhCKKCx..."
    db ".....xxhCKKCx..."
    db ".....xxhKCCx...."
    db "....xhhKCxx....."
    db "....xKKCCxx....."
    db "....xKKCCxx....."
    db "...xKCCCx......."
    db "...Kxxxx........"
    db ".KK............."
    db ".KK............."
    db "K..............."

; ---- 0.10.4 Marksman art: 352 emblem, 353..356 abilities, 357..362 items, 230/231 stat icons ----
; 352 path emblem: two crossed flintlock pistols over a gold ring
mk_emblem_bmp:
    db "....KKKGGKKK...."
    db ".K.KGGGGGGGGK.K."
    db ".sSsGGnnnnGGsSs."
    db ".KsSsnnnnnnsSsK."
    db "KGGsSsnnnnsSsggK"
    db "KGGnsSsnnsSsnggK"
    db "KGnnnsSssSsnnngK"
    db "GGnnnnsYYsnnnngg"
    db "GGnnnnsYYsnnnngg"
    db "KGnnVWwYYVWwnngK"
    db "KGGnVWwnnVWwnggK"
    db "KGGnVWwnnVWwnggK"
    db ".KGgVWwnnVWwggK."
    db "..KgYYYnnYYYgK.."
    db "...KggggggggK..."
    db "....KKKggKKK...."
pal_mk_emblem:
    PAL 'K', 30, 20, 16
    PAL 'G', 240, 196, 52
    PAL 'g', 176, 124, 24
    PAL 'n', 52, 40, 66
    PAL 'S', 222, 222, 230
    PAL 's', 140, 140, 154
    PAL 'W', 190, 126, 60
    PAL 'w', 112, 68, 30
    PAL 'Y', 255, 236, 140
    PAL 'V', 214, 160, 96
    dq 0
; 353 Powder Grenade
mk_grenade_bmp:
    db ".........FFFOYO."
    db "......KKFF..WWO."
    db ".....KcccK...YO."
    db ".....KCCCK......"
    db "....KKBBBKK....."
    db "...KBBBBBBBK...."
    db "..KBBLBBBBBBK..."
    db ".KBBLlBBBBBBbK.."
    db ".KBBLBBBBBBbbK.."
    db ".KBBBBBBBBBbbK.."
    db ".KBBBBBBBBBbbK.."
    db ".KBBBBBBBBbbbK.."
    db ".KBBBBBBBbbbbK.."
    db "..KBBBBbbbbbK..."
    db "...KBbbbbbbK...."
    db "....KKbbbKK....."
pal_mk_grenade:
    PAL 'K', 10, 10, 14
    PAL 'B', 52, 52, 62
    PAL 'b', 30, 30, 38
    PAL 'L', 160, 162, 182
    PAL 'l', 104, 106, 124
    PAL 'c', 120, 120, 132
    PAL 'C', 168, 168, 180
    PAL 'F', 172, 120, 62
    PAL 'Y', 255, 226, 100
    PAL 'O', 255, 140, 40
    PAL 'W', 255, 255, 230
    dq 0
; 354 Bullseye
mk_bullseye_bmp:
    db "....KKKKKKKK...."
    db "...KRRRRRRRRK..."
    db "..KRRRRCCRRRRK.."
    db ".KRRRCCCCCCRRrK."
    db "KRRRCCRRRRCCRrrK"
    db "KRRCCRRRRRRCCRrK"
    db "KRRCRRDDDDRRCRrK"
    db "KRCCRRDDDDRRCCrK"
    db "KRCCRRDDDDRRCCrK"
    db "KRRCRRDDDDRRCRrK"
    db "KRRCCRRRRRRCCRrK"
    db "KRRRCCRRRRCCRrrK"
    db ".KRRRCCCCCCRRrK."
    db "..KrrRRCCRRrrK.."
    db "...KrrrrrrrrK..."
    db "....KKKKKKKK...."
pal_mk_bullseye:
    PAL 'K', 54, 20, 16
    PAL 'R', 212, 44, 40
    PAL 'r', 146, 26, 28
    PAL 'C', 250, 236, 200
    PAL 'D', 52, 22, 22
    dq 0
; 355 Fan the Hammer
mk_fanhammer_bmp:
    db "................"
    db "..KK............"
    db ".KYYK.KKKK......"
    db "..KYKKssssKKKKKK"
    db "..KSSSSdddSSSSSS"
    db "YYKssssKKdSSSSSS"
    db "..Kssssdddssssss"
    db "..KssssdddKKKKKK"
    db "YYKssssKKKK....."
    db "..KwWWWsKKK....."
    db "..KwWWwK.K......"
    db "YYKwWWwK........"
    db "..KwWWwK........"
    db "..KwWWwK........"
    db "..KwWWwK........"
    db "...KKKK........."
pal_mk_fanhammer:
    PAL 'K', 26, 22, 22
    PAL 'S', 210, 210, 218
    PAL 's', 140, 140, 152
    PAL 'd', 76, 78, 90
    PAL 'W', 176, 116, 54
    PAL 'w', 110, 68, 28
    PAL 'Y', 255, 214, 70
    dq 0
; 356 Flashbang
mk_flashbang_bmp:
    db ".......oo......."
    db "......oWWo......"
    db "......oWWo......"
    db "....oooWWooo...."
    db "...oWWoWWoWWo..."
    db "...oWWWyyWWWo..."
    db ".ooooWyyyyWoooo."
    db "oWWWWyyWWyyWWWWo"
    db "oWWWWyyWWyyWWWWo"
    db ".ooooWyyyyWoooo."
    db "...oWWWyyWWWo..."
    db "...oWWoWWoWWo..."
    db "....oooWWooo...."
    db "......oWWo......"
    db "......oWWo......"
    db ".......oo......."
pal_mk_flashbang:
    PAL 'o', 214, 132, 24
    PAL 'W', 255, 252, 236
    PAL 'y', 255, 206, 56
    dq 0
; 230 gun damage stat icon (a brass bullet)
mk_st_gun_bmp:
    db ".......KK......."
    db "......KccK......"
    db ".....KccccK....."
    db "....KcCccccK...."
    db "....KcCccccK...."
    db "....KCCCCCCK...."
    db "....KBBbbDDK...."
    db "....KBBbbDDK...."
    db "....KBBbbDDK...."
    db "....KDDDDDDK...."
    db "....KBBbbDDK...."
    db "....KBBbbDDK...."
    db "....KBBbbDDK...."
    db "...KbbbbbbbbK..."
    db "...KDDDDDDDDK..."
    db "....KKKKKKKK...."
pal_mk_st_gun:
    PAL 'K', 54, 36, 10
    PAL 'b', 224, 176, 62
    PAL 'B', 255, 226, 130
    PAL 'D', 150, 108, 28
    PAL 'c', 204, 104, 56
    PAL 'Y', 255, 226, 100
    PAL 'O', 236, 120, 36
    PAL 'C', 240, 150, 100
    dq 0
; 231 reload speed stat icon (a brass round in a circular arrow)
mk_st_reload_bmp:
    db ".........HH....."
    db "......VVVHHH...."
    db "....VVVVVHHHH..."
    db "...VVV...HHHHH.."
    db "..VV...ccHHHH..."
    db ".VVV..cccc....V."
    db ".VV...cccc...VV."
    db ".vV...Bbbb...VV."
    db ".vv...Bbbb...VV."
    db ".vv...Bbbb...VV."
    db ".vv...Bbbb...VV."
    db ".vvv..DDDD..VVV."
    db "..vv........VV.."
    db "...vvv....VVV..."
    db "....vvvvvVVV...."
    db "......vvvv......"
pal_mk_st_reload:
    PAL 'K', 54, 36, 10
    PAL 'V', 160, 208, 236
    PAL 'v', 88, 140, 190
    PAL 'b', 224, 176, 62
    PAL 'B', 255, 226, 130
    PAL 'D', 150, 108, 28
    PAL 'c', 204, 104, 56
    PAL 'H', 236, 248, 255
    dq 0

section .text
